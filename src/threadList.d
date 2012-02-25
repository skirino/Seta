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

module threadList;

private import gtk.PopupBox;

private import tango.io.Stdout;

private import utils.vector;
private import utils.timeUtil;


private enum ThreadInfoState
{
  INVALID,
  RUNNING,
  STOPPED
}

template ListedOperationT()
{
  uint threadID_;
  
  void Register()
  {
    threadID_ = ThreadStart(this);
  }
  
  void Unregister()
  {
    ThreadEnd(threadID_);
  }
}

interface ListedOperationIF
{
  string GetThreadListLabel(string startTime);
}

interface StoppableOperationIF : ListedOperationIF
{
  // if the operation is stoppable, it should override the following two methods
  void Stop();
  string GetStopDialogLabel(string startTime);
}

class ThreadInfo
{
private:
  ThreadInfoState state_;
  ulong timeStart_;
  ListedOperationIF th_;
  
  this()
  {
    state_ = ThreadInfoState.INVALID;
  }
  
  string StartTimeStr(){return "started at " ~ EpochTimeToStringSeconds(timeStart_);}
  
  void ForceStopThread()
  {
    if(state_ == ThreadInfoState.RUNNING){
      auto stoppable = cast(StoppableOperationIF)th_;// downcast
      if(stoppable !is null){// can stop
        state_ = ThreadInfoState.STOPPED;
        stoppable.Stop();
      }
    }
  }
  
public:
  void StopThread(T)(T t)
  {
    if(state_ == ThreadInfoState.RUNNING){
      auto stoppable = cast(StoppableOperationIF)th_;// downcast
      if(stoppable !is null){// can stop
        if(PopupBox.yesNo(stoppable.GetStopDialogLabel(StartTimeStr()), "Operation in progress")){
          // Popping up a dialog can make some idle time in glib's main loop and
          // during the idle time contents of "this" may be modified. Recheck its "state_".
          if(state_ == ThreadInfoState.RUNNING){
            state_ = ThreadInfoState.STOPPED;
            stoppable.Stop();
          }
        }
      }
    }
  }
  
  string GetLabel()
  {
    return th_.GetThreadListLabel(StartTimeStr());
  }
  
  int opCmp(Object rhs){return cast(int)(timeStart_ - (cast(ThreadInfo)rhs).timeStart_);}
}


// Global list of working threads. Only the main thread can safely modify the list.
private Vector!(ThreadInfo) list;

void Init()
{
  // create vector with length 10
  list = new Vector!(ThreadInfo);
  for(int i=0; i<10; ++i){
    list.append(new ThreadInfo);
  }
}

void Finish()
{
  // stop all running threads
  foreach(th; list.array()){
    if(th !is null){
      th.ForceStopThread();
    }
  }
}

ThreadInfo[] GetWorkingThreadList()
{
  // pick up RUNNING threads
  ThreadInfo[] ret;
  foreach(info; list.array()){
    if(info.state_ == ThreadInfoState.RUNNING){
      ret ~= info;
    }
  }
  
  // sort by timeStart_, since order of threads in the list is completely random
  ret.sort;
  
  return ret;
}

uint ThreadStart(ListedOperationIF th)
{
  // called before spawning the thread, no need of gdk lock stuff
  
  // register the thread to list (use INVALID element in the vector)
  uint idx = 0;
  foreach(info; list.array()){
    if(info.state_ == ThreadInfoState.INVALID){
      break;
    }
    ++idx;
  }
  
  if(idx == list.size()){// no INVALID elements in the list, append one
    list.append(new ThreadInfo);
  }
  
  list[idx].state_ = ThreadInfoState.RUNNING;
  list[idx].timeStart_ = GetCurrentTime();
  list[idx].th_ = th;
  
  return idx;
}

void ThreadEnd(uint idx)
{
  // gdk lock should be held by the caller
  
  // reset list[idx]
  list[idx].state_ = ThreadInfoState.INVALID;
  list[idx].th_ = null;
}

