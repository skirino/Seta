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

module move_files_job;

import std.conv;
import core.thread;
import core.stdc.stdlib : system;

import gtk.Clipboard;
import gdk.Threads;
import gio.File;
import gio.Cancellable;
import glib.GException;
import glib.URI;
import gtkc.gtk;
import gtkc.glib;

import utils.string_util;
import utils.gio_util;
import utils.dialog_util;
import constants;
import fm.file_view;
import thread_list;
import statusbar;


string[] GetFilesFromStrv(char ** curis)
{
  if(curis == null)
    return null;

  string[] files;
  char ** ptr = curis;
  while((*ptr) != null){
    string temp = URI.uriUnescapeString(to!string(*ptr), null);
    if(temp.length > 7){
      files ~= temp[7 .. $];// remove "file://"
    }
    ptr++;
  }
  return files;
}

string[] GetFilesFromSelection(GtkSelectionData * selection)
{
  // to work around a limitation of Str.toStringArray
  // (whose return is limited to max 10 length)
  // I use the bare GTK API.
  char ** curis = gtk_selection_data_get_uris(selection);
  string[] files = GetFilesFromStrv(curis);
  g_strfreev(curis);
  return files;
}

string[] MakeURIList(string dir, string[] files)
{
  string[] ret;
  string head = "file://" ~ dir;
  foreach(file; files){
    string temp = head ~ file;
    ret ~= URI.uriEscapeString(temp, ":/", 0);
  }
  return ret;
}


/////////////////////// cut(copy) and paste
private __gshared bool     storedMove;
private __gshared string   storedDir;
private __gshared string[] storedFiles;
private const string URI_MOVE = "action:move";

void PreparePaste(bool moveMode, string dir, string[] files, FileView sourceView)
{
  // remove "../" if included in the selected files
  if(files.length > 0 && files[0] == PARENT_STRING){
    storedFiles = files[1 .. $];
  }
  else{
    storedFiles = files;
  }

  size_t numItems = storedFiles.length;
  if(numItems > 0){
    storedMove  = moveMode;
    storedDir   = dir;
    auto cl = DefaultClipboard();
    cl.setWithOwner(GetDragTargets(), &ClipboardGetFun, &ClipboardClearFun, sourceView);

    // send message to statusbar
    PushIntoStatusbar(
      PluralForm!(size_t, "item was", "items were")(numItems) ~
      " selected for " ~
      (moveMode ? "move" : "copy"));
  }
}

private extern(C) void ClipboardGetFun(
  GtkClipboard * clip, GtkSelectionData * selection, uint info, void * data_or_owner)
{
  if(storedFiles.length > 0){
    string[] uris = storedMove ? [URI_MOVE] : [];
    uris ~= MakeURIList(storedDir, storedFiles);
    // Since destructor of SelectionData frees the memory which is also handled by gtk lib,
    // creating a new instance of SelectionData causes double free error.
    // To workaround the issue I directly use gtk API here.
    gtk_selection_data_set_uris(selection, ToStringzArray(uris));
  }
}

private extern(C) void ClipboardClearFun(
  GtkClipboard * clip, void * data_or_owner)
{
  // do nothing
}

bool CanPaste()
{
  auto cl = DefaultClipboard();
  return cl.waitIsUrisAvailable() != 0;
}

void PasteFiles(string destDir, FileView destView = null)
{
  string[] files;
  GdkDragAction action = GetFilesInClipboard(files);
  if(files.length > 0){
    TransferFiles(action, files, null, destDir, destView);
  }
}

GdkDragAction GetFilesInClipboard(out string[] files)
{
  // use GTK API and avoid using GtkD functions (which internally use Str.toStringArray)
  GtkClipboard * cl = GetDefaultClipboard();
  char ** curis = gtk_clipboard_wait_for_uris(cl);
  auto action = GdkDragAction.COPY;
  if((curis != null) && (*curis != null)){
    char ** ptr = curis;

    // check whether "action" is explicitly specified as "move" by the source side
    if(curis[0].to!string == URI_MOVE){
      action = GdkDragAction.MOVE;
      ptr++;
      gtk_clipboard_clear(cl);
    }

    files = GetFilesFromStrv(ptr);
    g_strfreev(curis);
  }

  return action;
}
/////////////////////// cut(copy) and paste



/////////////////////// move or copy files
void TransferFiles(GdkDragAction action, string[] files, FileView sourceView, string destDir, FileView destView = null)
{
  if(files.length == 0)
    return;

  // obtain source directory by removing "basename" in files[0]
  string sourceDir = ParentDirectory(AppendSlash(files[0]));

  if(action == GdkDragAction.MOVE){
    if(sourceDir != destDir){// skip "move to the same directory"
      (new MoveFilesJob!(true)(files, sourceDir, sourceView, destDir, destView)).start();
    }
  }
  else if(action == GdkDragAction.COPY){
    (new MoveFilesJob!(false)(files, sourceDir, sourceView, destDir, destView)).start();
  }
}


private class MoveFilesJob(bool move) : Thread, StoppableOperationIF
{
  // public interface for ThreadList, implements StoppableOperationIF
  void Stop()
  {
    mode_ = PasteModeFlags.CANCEL_ALL;
    if(canCancelNow_){
      cancellable_.cancel();
    }
  }

  string GetThreadListLabel(string startTime)
  {
    return
      "(" ~ GetRatioNow() ~ ") " ~ Moving ~ ' ' ~
      GetFromSourceDir() ~ ' ' ~ GetToDestDir() ~ " (" ~ startTime ~ ')';
  }

  string GetStopDialogLabel(string startTime)
  {
    return
      "This thread is " ~ moving ~ ' ' ~ PluralForm!(size_t, "item")(files_.length) ~ '\n' ~
      GetFromSourceDir() ~ '\n' ~ GetToDestDir() ~ '\n' ~
      '(' ~ startTime ~ ", now finished " ~ PluralForm!(uint, "item")(numTransferred_) ~ ").\nStop this thread?";
  }

  gdk.Window.Window GetAssociatedWindow(){return null;}



private:
  // utils for message strings
  static if(move){
    static immutable string moving = "moving";
    static immutable string Moving = "Moving";
  }
  else{
    static immutable string moving = "copying";
    static immutable string Moving = "Copying";
  }

  string GetRatioNow()
  {
    return numTransferred_.to!string ~ '/' ~ files_.length.to!string;
  }
  string GetRatioItems()
  {
    return GetRatioNow() ~ (numTransferred_ == 1 ? " item" : " items");
  }
  string GetFromSourceDir(){ return "from \"" ~ sourceDir_ ~ '\"'; }
  string GetToDestDir()    { return "to \""   ~ destDir_   ~ '\"'; }



  // files to be transferred
  string[] files_;
  uint numTransferred_;
  PasteModeFlags mode_;
  string sourceDir_;
  FileView sourceView_;
  string destDir_;
  FileView destView_;

  // for managing thread and cancel operation
  mixin ListedOperationT;
  bool canCancelNow_;
  Cancellable cancellable_;

  this(string[] files, string sourceDir, FileView sourceView, string destDir, FileView destView)
  {
    super(&Start);
    files_      = files;
    destDir_    = destDir;
    destView_   = destView;
    sourceDir_  = sourceDir;
    sourceView_ = sourceView;

    // still within the main thread
    PushIntoStatusbar(
      Moving ~ ' ' ~ PluralForm!(size_t, "item")(files_.length) ~ ' ' ~
      GetFromSourceDir() ~ ' ' ~ GetToDestDir() ~ " ...");

    canCancelNow_ = false;
    cancellable_ = new Cancellable;
    Register();
  }

  string NotificationMessage()
  {
    if(numTransferred_ == 0){
      return "Canceled " ~ moving;
    }
    else if(numTransferred_ == files_.length){// all
      return "Finished " ~
        moving ~
        ' ' ~
        PluralForm!(uint, "item")(numTransferred_) ~
        ' ' ~
        GetToDestDir();
    }
    else if(mode_ == PasteModeFlags.CANCEL_ALL){// stopped by the user
      return "Canceled " ~
        moving ~
        " after finishing " ~
        GetRatioItems();
    }
    else{// part of files have been transferred
      return "Finished " ~ moving ~ ' ' ~ GetRatioItems() ~ ' ' ~ GetToDestDir();
    }
  }

  void NotifyFinish()
  {
    // inside gdk lock

    auto message = NotificationMessage();
    PushIntoStatusbar(message);

    if(numTransferred_ > 0){
      // notify the source side to Update
      bool sourceUpdated = false;
      static if(move){
        if(sourceView_ !is null){// sourceView is null when the source belongs to other application
          sourceView_.TransferFinished(sourceDir_);
          sourceUpdated = true;
        }
      }

      // notify the destination side to Update
      if(destView_ !is null){
        if(!(sourceView_ is destView_ && sourceUpdated)){
          destView_.TransferFinished(destDir_);
        }
      }
    }

    // remove from thread list
    Unregister();
  }

  void Start()
  {
    size_t numItems = files_.length;
    numTransferred_ = 0;
    mode_ = numItems == 1 ? PasteModeFlags.ASK : (PasteModeFlags.MULTIPLE | PasteModeFlags.ASK);

    foreach(file; files_){
      // stop copying/moving when forced by the main thread
      if(mode_ == PasteModeFlags.CANCEL_ALL)
        break;

      // determine "newname"
      string name = GetBasename(file);
      string newname = destDir_ ~ name;
      if(newname == file){
        static if(!move){// copy mode, ask new name
          string defaultValue = (name[$-1] == '/' ? name[0..$-1] : name) ~ "(copy)";

          threadsEnter();
          string newBasename = InputDialog("copy", "New name: ", defaultValue);
          threadsLeave();

          if(newBasename.length == 0){// no valid input is returned (CANCEL is pressed)
            break;
          }
          else if(newBasename == name || // the same name is returned, skip it
                  (file[$-1] == '/' && newBasename == file[0..$-1])){// difference is only '/' at last, essentially the same
            continue;
          }
          else{
            newname = destDir_ ~ newBasename;
          }
        }
      }

      // now start transfer this file/dir
      if(!move || !newname.StartsWith(file)){// avoid moving to its child directory
        try{
          if(Transfer1(file, newname))
            ++numTransferred_;
        }
        catch(GException ex){}// in most cases permission denied
      }
    }

    threadsEnter();// grab gdk lock here to avoid repeating getting/releasing
    NotifyFinish();
    threadsLeave();
  }

  bool Transfer1(string oldname, string newname)
  {
    bool doPaste = true;
    if((mode_ & PasteModeFlags.ASK) && Exists(newname)){// file already exists
      int x;
      string message = GetBasename(newname) ~ " exists. Overwrite?";

      threadsEnter();
      if(mode_ & PasteModeFlags.MULTIPLE){
        x = ChooseDialog!(4)(message, ["_OK", "_Skip this file", "Overwrite _all", "_Cancel all"]);
      }
      else{
        x = ChooseDialog!(2)(message, ["_OK", "_Cancel"]);
      }
      threadsLeave();

      if(x == -1 || x == 1 || x == 3){// invalid, "cancel" or "cancel all"
        doPaste = false;
      }

      if(x == 2){// "overwrite all"
        mode_ -= PasteModeFlags.ASK;
      }
      else if(x == 3){// "cancel all"
        mode_ = PasteModeFlags.CANCEL_ALL;
      }
    }

    if(doPaste && mode_ != PasteModeFlags.CANCEL_ALL){
      if(oldname[$-1] == '/'){// directory
        // g_file_copy in GIO library does not support recursive copy/move of directories.
        // Workaround at present is to use shell command ("cp -r" or "mv").
        string oldpath = EscapeSpecialChars(oldname);
        string destDir;
        bool includeTOption = false;
        if(sourceDir_ == destDir_){// within the same directory, only copy mode
          // do not place "oldpath" under "newname",
          // instead place the contents of "oldpath" into "newname" (which is done by the -T option)
          // this may overwrite existing directory with the same name
          destDir = EscapeSpecialChars(newname);
          includeTOption = true;
        }
        else{// different directory, may overwrite existing directory with the same name
          destDir = EscapeSpecialChars(ParentDirectory(newname));
        }
        string command = (move ? "mv " : (includeTOption ? "cp -rT " : "cp -r ")) ~ oldpath ~ ' ' ~ destDir ~ '\0';
        int systemResult = system(command.ptr);
        return systemResult == 0;
      }
      else{
        scope src  = File.parseName(oldname);
        scope dest = File.parseName(newname);
        int result;

        // Strictly speaking I should use mutex locking when reading/writing canCancelNow_,
        // but it does not have significant difference, just do another copy/move.
        // Also, GCancellable seems to permit cancel() after the work has been finished.
        // So I omit locking here.
        canCancelNow_ = true;
        static if(move){
          result = src.move(dest, GFileCopyFlags.OVERWRITE, cancellable_, null, null);
        }
        else{
          result = src.copy(dest, GFileCopyFlags.OVERWRITE, cancellable_, null, null);
        }
        canCancelNow_ = false;

        return result != 0;
      }
    }
    else{
      return false;
    }
  }
}
/////////////////////// move or copy files



//////////////////////// interface to C (workaround for GtkD)
Clipboard DefaultClipboard()
{
  return new Clipboard(GetDefaultClipboard());
}

extern(C) {
  // GdkAtom GDK_SELECTION_CLIPBOARD is not available from D
  GtkClipboard * GetDefaultClipboard();
}
//////////////////////// interface to C
