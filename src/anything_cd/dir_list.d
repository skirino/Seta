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

private import tango.io.Stdout;
private import tango.io.stream.Lines;
private import tango.io.device.File;
private import tango.sys.Environment;
private import tango.core.Array;
private import tango.core.Thread;

private import utils.vector;
private import utils.stringUtil;
private import utils.gioUtil;
private import threadList;
private import statusbar;


private DirPathList instance_;
private ScanHomeDirectoryThread thread_;


string[] Get()
{
  return instance_.list_.array();
}

bool Changed(){return instance_.changed_;}
bool IsScanning(){return (thread_ !is null) && (thread_.isRunning());}

void Scan()
{
  thread_ = new ScanHomeDirectoryThread;
  thread_.start();
}

void Init()
{
  instance_ = new DirPathList;
}
void Finish()
{
  instance_.Save();
}


class DirPathList
{
private:
  static const size_t MAX = 1000;
  
  bool changed_;
  string filename_;
  Vector!(string) list_;
  
public:
  this()
  {
    changed_ = false;
    filename_ = Environment.get("HOME") ~ "/.seta_dirlist";
    list_ = new Vector!(string)(MAX);
    Load();
  }
  
  void Load()
  {
    try{
      scope file = new tango.io.device.File.File(filename_);
      scope lines = new Lines!(char)(file);
      foreach(line; lines){
        if(line.length > 0){
          list_.append(line.dup);
        }
      }
      
      file.close();
    }
    catch(Exception ex){}// no such file
  }
  
  void Save()
  {
    if(changed_){
      scope file = new tango.io.device.File.File(filename_, tango.io.device.File.File.WriteCreate);
      foreach(path; list_.array()){
        file.write(path ~ '\n');
      }
      file.close();
    }
  }
}



private class ScanHomeDirectoryThread : Thread, StoppableOperationIF
{
  mixin ListedOperationT;
  bool canceled_;
  string home_;
  Vector!(string) v_;
  
  this()
  {
    super(&Start);
    home_ = Environment.get("HOME");
    v_ = new Vector!(string)(DirPathList.MAX);
    
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
  
  void Start()
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
