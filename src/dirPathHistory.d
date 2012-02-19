/*
Copyright (C) 2010 Shunsuke Kirino <shunsuke.kirino@gmail.com>

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

module dirPathHistory;

private import tango.io.Stdout;
private import tango.io.device.File;
private import tango.io.stream.Lines;
private import tango.sys.Environment;

private import vector;
private import stringUtil;
static private import config;


private DirPathHistory instance_;

char[][] Get()
{
  return instance_.list_.array();
}

void Push(char[] path)
{
  instance_.Push(path);
}

void Init()
{
  instance_ = new DirPathHistory;
}

void Finish()
{
  instance_.Save();
}


private class DirPathHistory
{
private:
  static const size_t MAX = 1000;
  
  char[] home_, filename_;
  Vector!(char[]) list_;
  
public:
  this()
  {
    home_ = Environment.get("HOME");
    filename_ = home_ ~ "/.seta_history";
    list_ = new Vector!(char[])(MAX);
    Load();
    Push(config.GetInitialDirectoryLeft());
    Push(config.GetInitialDirectoryRight());
  }
  
  void Push(char[] path)
  {
    if(path.StartsWith(home_)){
      path = "~" ~ path[home_.length .. $];
    }
    char[][] array = list_.array();
    
    // check uniqueness of paths
    int index = -1;
    foreach(int i, dir; array){
      if(dir == path){
        index = i;
      }
    }
    
    if(index == -1){// not found
      if(list_.size() == MAX){
        list_.pop();
      }
      list_.prepend(path);
    }
    else{// found
      list_.moveToHead(index);
    }
  }
  
  void Load()
  {
    try{
      scope file = new File(filename_);
      scope lines = new Lines!(char)(file);
      foreach(line; lines){
        if(line.length > 0){
          list_.append(line.dup);
          if(list_.size() == MAX){
            break;
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
}
