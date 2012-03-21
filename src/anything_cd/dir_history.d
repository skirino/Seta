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

module anything_cd.dir_history;

import std.process;

import utils.vector;
import utils.string_util;
import rcfile = config.rcfile;
import anything_cd.dir_list;


///////////// public interfaces of this module
string[] Get()
{
  return instance_.list_.array();
}

void Push(string path)
{
  instance_.Push(path);
}

void Remove(string dir)
{
  instance_.Remove(dir);
}


void Init()
{
  instance_ = new DirHistory;
}

void Finish()
{
  instance_.Save();
}
///////////// public interfaces of this module


private __gshared DirHistory instance_;


private class DirHistory : DirListBase
{
private:
  string home_;

public:
  this()
  {
    home_ = getenv("HOME");
    super(home_ ~ "/.seta_history");
    Load!(true)();
    Push(rcfile.GetInitialDirectoryLeft());
    Push(rcfile.GetInitialDirectoryRight());
  }

  void Push(string path)
  {
    if(path.StartsWith(home_)){
      path = "~" ~ path[home_.length .. $];
    }
    string[] array = list_.array();

    // check uniqueness of paths
    int index = -1;
    foreach(i, dir; array){
      if(dir == path){
        index = i;
        break;
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
}

