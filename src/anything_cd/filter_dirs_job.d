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

import core.thread;
import std.string;

import gdk.Threads;

import utils.min_max;
import utils.string_util;
import utils.vector;
static import anything_cd.dir_list;
static import anything_cd.dir_history;
import thread_list;


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
    foreach(word; toLower(targetText_).split()){
      if(word.length > 0){
        words ~= word;
      }
    }

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
          if(dirlist[i].containsWords(words)){
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
          if(dirlist[i].containsWords(words)){
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


private bool containsWords(string targetStr, string[] words)
{
  string str = targetStr.toLower();
  foreach(word; words){
    if(!str.containsPattern(word)){
      return false;
    }
  }
  return true;
}
