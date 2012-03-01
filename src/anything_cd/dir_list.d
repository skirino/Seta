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

module anything_cd.dir_list;

private import gio.FileInfo;
private import gdk.Threads;
private import gdk.Window;

private import tango.io.Stdout;
private import tango.io.stream.Lines;
private import tango.io.device.File;
private import tango.sys.Environment;
private import tango.core.Array;
private import tango.core.Thread;

private import utils.vector;
private import utils.string_util;
private import utils.gio_util;
private import thread_list;
private import statusbar;
private import anything_cd.dir_history;


///////////// public interfaces of this module
char[][] Get()
{
  return instance_.list_.array();
}

bool Changed(){return instance_.changed_;}

bool IsScanning(){return (thread_ !is null) && (thread_.isRunning());}

void Scan()
{
  thread_ = new ScanHomeDirectoryJob;
  thread_.start();
}

void Remove(char[] dir)
{
  auto home = Environment.get("HOME");
  if(dir.StartsWith(dir)){
    dir = '~' ~ dir[home.length .. $];
  }
  instance_.Remove(dir);
  anything_cd.dir_history.Remove(dir);
}


void Init()
{
  instance_ = new DirList;
}
void Finish()
{
  instance_.Save();
}
///////////// public interfaces of this module


private DirList instance_;
private ScanHomeDirectoryJob thread_;


class DirListBase
{
protected:
  static const size_t MAX = 1000;
  Vector!(char[]) list_;
  char[] filename_;

public:
  this(char[] filename)
  {
    filename_ = filename;
    list_ = new Vector!(char[])(MAX);
  }

  void Load(bool withinMAX = false)()
  {
    try{
      scope file = new tango.io.device.File.File(filename_);
      scope lines = new Lines!(char)(file);
      foreach(line; lines){
        if(line.length > 0){
          list_.append(line.dup);

          static if(withinMAX){
            if(list_.size() == MAX){
              break;
            }
          }
        }
      }

      file.close();
    }
    catch(Exception ex){}// no such file
  }

  void Save()
  {
    scope file = new tango.io.device.File.File(filename_, tango.io.device.File.File.WriteCreate);
    foreach(path; list_.array()){
      file.write(path ~ '\n');
    }
    file.close();
  }

  void Remove(char[] dir)
  {
    list_.remove(dir);
  }
}


private class DirList : DirListBase
{
private:
  bool changed_;

public:
  this()
  {
    super(Environment.get("HOME") ~ "/.seta_dirlist");
    changed_ = false;
    Load();
  }

  void Save()
  {
    if(changed_){
      super.Save();
    }
  }

  void Remove(char[] dir)
  {
    super.Remove(dir);
    changed_ = true;
  }
}



private class ScanHomeDirectoryJob : Thread, StoppableOperationIF
{
  mixin ListedOperationT;
  bool canceled_;
  char[] home_;
  Vector!(char[]) v_;

  this()
  {
    super(&Scan);
    home_ = Environment.get("HOME");
    v_ = new Vector!(char[])(DirList.MAX);

    Register();
  }

  void Stop()
  {
    canceled_ = true;
  }

  char[] GetThreadListLabel(char[] startTime)
  {
    return "Scanning directories under " ~ home_;
  }

  char[] GetStopDialogLabel(char[] startTime)
  {
    return GetThreadListLabel(startTime) ~ ".\nStop this thread?";
  }

  gdk.Window.Window GetAssociatedWindow(){return null;}



  void Scan()
  {
    ScanOneDirectory(home_);

    gdkThreadsEnter();
    Unregister();
    if(!canceled_){
      instance_.list_.swap(v_);
      instance_.changed_ = true;
      PushIntoStatusbar("Finished updating directory list.");
    }
    gdkThreadsLeave();
  }

  void AppendOneDirectory(char[] path)
  {
    if(path.StartsWith(home_)){
      path = "~" ~ path[home_.length .. $];
    }
    v_.append(AppendSlash(path));
  }

  void ScanOneDirectory(char[] path)
  {
    // depth-first
    AppendOneDirectory(path);

    char[][] dirs = ScanChildren(path);
    foreach(dir; dirs){
      ScanOneDirectory(path ~ '/' ~ dir);

      if(canceled_){
        break;
      }
    }
  }

  char[][] ScanChildren(char[] path)
  {
    static const char[] attributes = "standard::name,standard::type,standard::is-symlink";
    static const char[][] ignoreDirs = ["lost+found", ".svn", ".git"];

    char[][] dirs = [];

    try{
      scope enumerate = GetFileForDirectory(path).enumerateChildren(attributes, GFileQueryInfoFlags.NONE, null);

      GFileInfo * pinfo;
      while((pinfo = enumerate.nextFile(null)) != null){
        scope FileInfo info = new FileInfo(pinfo);
        if((info.getFileType() == GFileType.TYPE_DIRECTORY) && (info.getIsSymlink() == 0)){
          char[] name = info.getName();
          if(ignoreDirs.find(name) == ignoreDirs.length){
            dirs ~= name;
          }
        }
      }
      enumerate.close(null);
    }
    catch(Exception ex){}// permission denied or directory has been removed

    dirs.sort;
    return dirs;
  }
}
