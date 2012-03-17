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

module anything_cd.filter_dirs_job;

private import gdk.Threads;

//private import tango.text.Util;
//private import tango.core.Thread;
private import core.thread;
//private import tango.text.Unicode;

private import utils.min_max;
private import utils.string_util;
private import utils.vector;
static private import anything_cd.dir_list;
static private import anything_cd.dir_history;
private import thread_list;


class FilterDirsJob : Thread, StoppableOperationIF
{
private:
  static const size_t MaxNumberOfPathsFromHistory = 100;
  static const size_t MaxNumberOfPathsFromList = 1000;
  static const size_t MaxNumberOfPaths = 1000;
  static const size_t PER_PAGE = 100;

  mixin ListedOperationT;
  bool canceled_;
  string targetText_;
  void delegate(string[], string[]) callbackSuccess_;
  void delegate() callbackCancel_;

public:
  this(
    string targetText,
    void delegate(string[], string[]) callbackSuccess,
    void delegate() callbackCancel)
  {
    super(&Start);

    canceled_ = false;
    targetText_ = targetText;
    callbackSuccess_ = callbackSuccess;
    callbackCancel_ = callbackCancel;

    Register();
  }

  string GetThreadListLabel(string startTime)
  {
    return "Filtering directories in the whole file tree (" ~ startTime ~ ')';
  }

  gdk.Window.Window GetAssociatedWindow(){return null;}

  void Stop()
  {
    canceled_ = true;
  }

  string GetStopDialogLabel(string startTime)
  {
    return GetThreadListLabel(startTime) ~ ".\nStop this thread?";
  }

  void Start()
  {
    if(IsBlank(targetText_)){
      return;
    }

    mixin(ReturnIfCanceled);

    string[] words = [];

    //TODO
    /+
    foreach(word; targetText_.toLower().delimit(" ")){
      if(word.length > 0){
        words ~= word;
      }
    }
    +/
    words = [targetText_];


    // process paths PER_PAGE and check cancel flag at start of page
    auto pathsFromHistory = new Vector!(string)(MaxNumberOfPathsFromHistory);
    {
      string[] dirlist = anything_cd.dir_history.Get();
      size_t len = dirlist.length;
      size_t pageNum = len / PER_PAGE + 1;
      for(size_t pageIndex=0; pageIndex<pageNum; pageIndex++){
        mixin(ReturnIfCanceled);

        size_t start = pageIndex * PER_PAGE;
        size_t end   = Min(start + PER_PAGE, len);
        for(size_t i=start; i<end; ++i){
          if(dirlist[i].containsStrings(words)){
            pathsFromHistory.append(dirlist[i]);
          }
        }
      }
    }

    auto pathsFromList = new Vector!(string)(MaxNumberOfPathsFromList);
    if(!anything_cd.dir_list.IsScanning()){
      string[] dirlist = anything_cd.dir_list.Get();
      size_t len = dirlist.length;
      size_t pageNum = len / PER_PAGE + 1;
      for(size_t pageIndex=0; pageIndex<pageNum; pageIndex++){
        mixin(ReturnIfCanceled);

        size_t start = pageIndex * PER_PAGE;
        size_t end   = Min(start + PER_PAGE, len);
        for(size_t i=start; i<end; ++i){
          if(dirlist[i].containsStrings(words)){
            pathsFromList.append(dirlist[i]);
          }
        }

        if(pathsFromList.size >= MaxNumberOfPaths){// sufficient number of paths found
          break;
        }
      }
    }

    mixin(ReturnIfCanceled);

    // notify finish
    gdkThreadsEnter();
    Unregister();
    callbackSuccess_(pathsFromHistory.array(), pathsFromList.array());
    gdkThreadsLeave();
  }


private:
  static const string ReturnIfCanceled =
    "if(canceled_){
      gdkThreadsEnter();
      Unregister();
      callbackCancel_();
      gdkThreadsLeave();
      return;
    }
    ";
}


private bool containsStrings(string targetStr, string[] words)
{
  bool ret = true;

  //TODO
  /+
  string str = targetStr.toLower();
  foreach(word; words){
    ret &= str.containsPattern(word);
  }
  +/
  return ret;
}
