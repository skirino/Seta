/*
Copyright (C) 2012 Shunsuke Kirino <shunsuke.kirino@gmail.com>

This file is part of Seta.
This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this software; see the file GPL. If not, contact the
Free Software Foundation, 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301 USA.
*/

module fm.entry;

import std.c.stdlib;
import core.sys.posix.sys.stat;

import gio.FileInfo;
import gio.ContentType;
import glib.Str;

import utils.time_util;
import utils.string_util;
import utils.gio_util;
import constants;


class DirEntry
{
private:
  string name_;
  string type_;
  long size_;
  string owner_;
  uint mode_;
  bool isSymlink_;
  ulong lastModified_;

  void Construct(bool isDir)(FileInfo info)
  {
    static if(isDir){
      name_ = info.getName() ~ '/';
    }
    else{
      name_ = info.getName();
    }
    lastModified_ = info.getAttributeUint64("time::modified");
    mode_ = info.getAttributeUint32("unix::mode");
    isSymlink_ = info.getIsSymlink() != 0;
  }

public:
  this(FileInfo info)// constructor for files in local filesystems
  {
    Construct!(false)(info);
    type_ = ContentType.getDescription(info.getContentType());
    size_ = info.getSize();
    owner_ = info.getAttributeString("owner::user");
  }

  this(FileInfo info, string pwd)// constructor for directories in local filesystems
  {
    Construct!(true)(info);
    size_ = CountNumEntries(pwd ~ name_);
    owner_ = info.getAttributeString("owner::user");
  }



  ///////////////////////// SSH
  // Since "owner::user" cannot be queried from GVFS, it is skipped.
  // Also, counting entries in directories can take very long time and is avoided.
  this(FileInfo info, int dummy1, int dummy2)// constructor for files in remote filesystems
  {
    Construct!(false)(info);
    type_ = ContentType.getDescription(info.getAttributeString("standard::fast-content-type"));
    size_ = info.getSize();
    owner_ = "(skipped)";
  }

  this(FileInfo info, int dummy)// constructor for directories in remote filesystems
  {
    Construct!(true)(info);
    size_ = -1;// output will be "? items"
    owner_ = "(skipped)";
  }
  ///////////////////////// SSH



  ///////////////////////// accessor
  string GetName      (){return name_;}
  string GetType      (){return type_;}
  string GetDirSize   (){return PluralForm!(int, "item")(cast(int)size_);}
  string GetFileSize  (){return FileSizeInStr(size_);}
  string GetOwner     (){return owner_;}
  string GetPermission(){return PermissionInStr(mode_, isSymlink_);}
  string GetModified  (){return EpochTimeToString(lastModified_);}
  bool IsSymlink(){return isSymlink_;}

  FileColorType GetDirColorType()
  {
    // directories are not considered here
    return isSymlink_ ? FileColorType.SymLink : FileColorType.Directory;
  }
  FileColorType GetFileColorType()
  {
    // directories are not considered here
    return isSymlink_ ? FileColorType.SymLink :
                        (mode_ & (S_IXUSR | S_IXGRP | S_IXOTH)) ? FileColorType.Executable :
                                                                  FileColorType.File;
  }
  ///////////////////////// accessor
}


//////////////////////// sort entries
// sort by name, ascending
int CompareNameAscending(DirEntry e1, DirEntry e2)
{
  return StrCmp(e1.name_, e2.name_);
}
// sort by name, descending
int CompareNameDescending(DirEntry e1, DirEntry e2)
{
  return -StrCmp(e1.name_, e2.name_);
}


private template CompareStringFuncMixin(string nameFun, string member)
{
  const string CompareStringFuncMixin =
    "int Compare" ~ nameFun ~ "ThenName(bool ascending)(DirEntry e1, DirEntry e2)
    {
      int i = StrCmp(e1." ~ member ~ ", e2." ~ member ~ ");
      if(i == 0){
        return StrCmp(e1.name_, e2.name_);
      }
      else{
        static if(ascending){
          return i;
        }
        else{
          return -i;
        }
      }
    }";
}
mixin(CompareStringFuncMixin!("Type", "type_"));
mixin(CompareStringFuncMixin!("Owner", "owner_"));


private template CompareIntegerFuncMixin(string nameFun, string member)
{
  const string CompareIntegerFuncMixin =
    "int Compare" ~ nameFun ~ "ThenName(bool ascending)(DirEntry e1, DirEntry e2)
    {
      if(e1." ~ member ~ " == e2." ~ member ~ "){
        return StrCmp(e1.name_, e2.name_);
      }
      else{
        static if(ascending){
          return cast(int)(e1." ~ member ~ " - e2." ~ member ~ ");
        }
        else{
          return cast(int)(e2." ~ member ~ " - e1." ~ member ~ ");
        }
      }
    }";
}
mixin(CompareIntegerFuncMixin!("Size", "size_"));
mixin(CompareIntegerFuncMixin!("Permissions", "mode_"));
mixin(CompareIntegerFuncMixin!("LastModified", "lastModified_"));
//////////////////////// sort entries



long CountNumEntries(string dirname)
{
  scope f = GetFileForDirectory(dirname);
  if(f !is null){
    try{
      long num = 0;
      scope enumerate = f.enumerateChildren("", GFileQueryInfoFlags.NONE, null);
      FileInfo info;
      while((info = enumerate.nextFile(null)) !is null){
        ++num;
      }
      enumerate.close(null);
      return num;
    }
    catch(Exception ex){// cannot see contents of the directory, maybe permission denied
      return -1;
    }
  }
  else{
    return -1;
  }
}


string FileSizeInStr(long n)
{
  const int kilo = 0x400;
  const int mega = 0x100000;
  const int giga = 0x40000000;

  if(n < kilo){
    return Str.toString(cast(ulong)n) ~ " B";
  }
  else{
    string buffer;
    const size_t buflen = 4;
    buffer.length = buflen;

    if(n < mega){
      string sizeStr = Str.asciiFormatd(buffer, buflen, "%3.1f", 1.0*n/kilo);
      return (sizeStr[$-1] == '.' ? sizeStr[0..$-1] : sizeStr) ~ " KB";
    }
    else if(n < giga){
      string sizeStr = Str.asciiFormatd(buffer, buflen, "%3.1f", 1.0*n/mega);
      return (sizeStr[$-1] == '.' ? sizeStr[0..$-1] : sizeStr) ~ " MB";
    }
    else{
      string sizeStr = Str.asciiFormatd(buffer, buflen, "%3.1f", 1.0*n/giga);
      return (sizeStr[$-1] == '.' ? sizeStr[0..$-1] : sizeStr) ~ " GB";
    }
  }
}


string PermissionInStr(uint mode, bool isSymlink)
{
  static __gshared char[10] ret;

  if(isSymlink){
    ret[0] = 'l';
  }
  else if((mode & S_IFMT) == S_IFDIR){
    ret[0] = 'd';
  }
  else{
    ret[0] = '-';
  }

  ret[1..4]  = RWX[(mode & S_IRWXU)/64][];
  if(mode & S_ISUID){
    ret[3] = ret[3] == 'x' ? 's' : 'S';
  }

  ret[4..7]  = RWX[(mode & S_IRWXG)/8][];
  if(mode & S_ISGID){
    ret[6] = ret[6] == 'x' ? 's' : 'S';
  }

  ret[7..10] = RWX[(mode & S_IRWXO)][];
  if(mode & S_ISVTX){
    ret[9] = ret[9] == 'x' ? 't' : 'T';
  }

  return ret.idup;
}

private static const char[3][8] RWX =
  ["---",
   "--x",
   "-w-",
   "-wx",
   "r--",
   "r-x",
   "rw-",
   "rwx"];


