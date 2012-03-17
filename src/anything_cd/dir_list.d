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

//private import tango.core.Thread;
private import core.thread;

private import migrate;
private import utils.vector;
private import utils.string_util;
private import utils.gio_util;
private import thread_list;
private import statusbar;
private import anything_cd.dir_history;


///////////// public interfaces of this module
string[] Get()
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

void Remove(string dir)
{
  auto home = getenv("HOME");
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
  Vector!(string) list_;
  string filename_;

public:
  this(string filename)
  {
    filename_ = filename;
    list_ = new Vector!(string)(MAX);
  }

  void Load(bool withinMAX = false)()
  {
    EachLineInFile(filename_, delegate bool(string line){
        if(line.length > 0){
          list_.append(line);
          static if(withinMAX){
            if(list_.size() == MAX){
              return false;
            }
          }
        }
        return true;
      });
  }

  void Save()
  {
    //TODO
    /+
    scope file = new tango.io.device.File.File(filename_, tango.io.device.File.File.WriteCreate);
    foreach(path; list_.array()){
      file.write(path ~ '\n');
    }
    file.close();
    +/
  }

  void Remove(string dir)
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
    super(getenv("HOME") ~ "/.seta_dirlist");
    changed_ = false;
    Load();
  }

  void Save()
  {
    if(changed_){
      super.Save();
    }
  }

  void Remove(string dir)
  {
    super.Remove(dir);
    changed_ = true;
  }
}



private class ScanHomeDirectoryJob : Thread, StoppableOperationIF
{
  mixin ListedOperationT;
  bool canceled_;
  string home_;
  Vector!(string) v_;

  this()
  {
    super(&Scan);
    home_ = getenv("HOME");
    v_ = new Vector!(string)(DirList.MAX);

    Register();
  }

  void Stop()
  {
    canceled_ = true;
  }

  string GetThreadListLabel(string startTime)
  {
    return "Scanning directories under " ~ home_;
  }

  string GetStopDialogLabel(string startTime)
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

  void AppendOneDirectory(string path)
  {
    if(path.StartsWith(home_)){
      path = "~" ~ path[home_.length .. $];
    }
    v_.append(AppendSlash(path));
  }

  void ScanOneDirectory(string path)
  {
    // depth-first
    AppendOneDirectory(path);

    string[] dirs = ScanChildren(path);
    foreach(dir; dirs){
      ScanOneDirectory(path ~ '/' ~ dir);

      if(canceled_){
        break;
      }
    }
  }

  string[] ScanChildren(string path)
  {
    static const string attributes = "standard::name,standard::type,standard::is-symlink";
    static const string[] ignoreDirs = ["lost+found", ".svn", ".git"];

    string[] dirs = [];

    try{
      scope enumerate = GetFileForDirectory(path).enumerateChildren(attributes, GFileQueryInfoFlags.NONE, null);

      GFileInfo * pinfo;
      while((pinfo = enumerate.nextFile(null)) != null){
        scope FileInfo info = new FileInfo(pinfo);
        if((info.getFileType() == GFileType.TYPE_DIRECTORY) && (info.getIsSymlink() == 0)){
          string name = info.getName();
          if(ignoreDirs.findElement(name) == ignoreDirs.length){
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
