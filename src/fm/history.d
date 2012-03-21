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

module fm.history;

import anything_cd.dir_history;


// history of directories visited by each page
class DirHistory
{
private:
  static const int MaxHistory = 50;
  string[MaxHistory] dirs_;// ring buffer
  int idxPWD_, bufferStart_, bufferEnd_;

  int Idx(int i)
  {
    if(i < 0){
      return MaxHistory + i;
    }
    else if(i >= MaxHistory){
      return i - MaxHistory;
    }
    else{
      return i;
    }
  }

public:
  this(string dir){Reset(dir);}

  void Reset(string dir)
  {
    bufferStart_ = 0;
    bufferEnd_ = 0;
    idxPWD_ = 0;
    dirs_[0] = dir;
  }

  string GetPWD(){return dirs_[idxPWD_];}

  void Append(string dir)
  {
    int next = Idx(idxPWD_ + 1);

    if(idxPWD_ == bufferEnd_){// if "idxPWD_" is at the end of the ring buffer
      if(bufferStart_ == next){// "start" and "end" lie next to each other
        bufferStart_ = Idx(bufferStart_ + 1);
      }
    }

    bufferEnd_ = idxPWD_ = next;
    dirs_[idxPWD_] = dir;

    anything_cd.dir_history.Push(dir);
  }

  void GoNext(bool ForwardDirection)()
  {
    static if(ForwardDirection){
      if(idxPWD_ != bufferEnd_){
        idxPWD_ = Idx(idxPWD_ + 1);
      }
    }
    else{//back
      if(idxPWD_ != bufferStart_){
        idxPWD_ = Idx(idxPWD_ - 1);
      }
    }
  }

  string GetDirNext(bool ForwardDirection)()
  {
    static if(ForwardDirection){
      if(idxPWD_ == bufferEnd_){
        return null;
      }
      else{
        return dirs_[Idx(idxPWD_ + 1)];
      }
    }
    else{// back
      if(idxPWD_ == bufferStart_){
        return null;
      }
      else{
        return dirs_[Idx(idxPWD_ - 1)];
      }
    }
  }

  void RemoveDirNext(bool ForwardDirection)()
  {
    static if(ForwardDirection){
      int i = Idx(idxPWD_ + 1);
    }
    else{
      int i = Idx(idxPWD_ - 1);
      idxPWD_ = i;
    }

    while(i != bufferEnd_){
      int next = Idx(i + 1);
      if(next == bufferEnd_){
        dirs_[i] = dirs_[next];
        break;
      }
      dirs_[i] = dirs_[next];
    }
    bufferEnd_ = Idx(bufferEnd_ - 1);
  }

  string[] Listup10(bool ForwardDirection)()
  {
    static if(ForwardDirection){
      const int shift = 1;
      int last = bufferEnd_;
    }
    else{
      const int shift = -1;
      int last = bufferStart_;
    }

    int index = idxPWD_;
    string[] ret;

    while(ret.length < 10 && index != last){
      index = Idx(index + shift);
      ret ~= dirs_[index];
    }

    return ret;
  }
}
