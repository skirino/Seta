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

module file_manager;

import std.conv;

import gtk.Widget;
import gtk.VBox;
import gtk.Entry;
import gtk.EditableIF;
import gtk.Button;
import gtk.ScrolledWindow;
import gtk.PopupBox;
import gtk.MenuItem;
import gdk.Threads;
import gdk.Event;
import gio.File;
import gio.FileIF;
import gtkc.gio;

import utils.string_util;
import utils.menu_util;
import constants;
import rcfile = config.rcfile;
import config.keybind;
import known_hosts = config.known_hosts;
import fm.file_view;
import fm.history;
import anything_cd.dir_list : Add, Remove;
import thread_list;
import mediator;
import statusbar;


class FileManager : VBox
{
  //////////////////////// GUI stuff
private:
  Mediator mediator_;
  ScrolledWindow swTree_;
  ScrolledWindow swView_;
  FileView view_;


public:
  this(Mediator mediator, string initialDir)
  {
    mediator_ = mediator;
    hist_ = new DirHistory(initialDir);
    view_ = new FileView(mediator_);

    super(0, 0);
    addOnKeyPress(&KeyPressed);

    // TreeView does not need Viewport. just use add()
    swView_ = new ScrolledWindow(GtkPolicyType.AUTOMATIC, GtkPolicyType.ALWAYS);
    swView_.add(view_);
    packStart(swView_, 1, 1, 0);

    SetLayout();
  }

  void SetLayout()
  {
    view_.SetLayout();
  }

  void PrepareDestroy()
  {
    view_.StopOngoingOperations();
  }
  //////////////////////// GUI stuff



  //////////////////////// view mode
public:
  void Update(){view_.TryUpdate();}// called when switching from TERMINAL mode to FILER mode
  //////////////////////// view mode



  ///////////////////// manipulation of focus
public:
  override bool hasFocus(){return view_.hasFocus();}

  void GrabFocus(Entry e = null){view_.GrabFocus();}
  ///////////////////// manipulation of focus



  //////////////////////// key pressed
private:
  bool KeyPressed(Event e, Widget w)
  {
    auto ekey = e.key();

    int q = QueryAction!"FileManager"(ekey);
    switch(q){

    case -1:
      return false;

    case FileManagerAction.GoToPrevious:
      NextDirInHistoryClicked!(false)(null);
      return true;

    case FileManagerAction.GoToNext:
      NextDirInHistoryClicked!(true)(null);
      return true;

    case FileManagerAction.GoToParent:
      UpClicked(null);
      return true;

    case FileManagerAction.GoToRoot:
      RootClicked(null);
      return true;

    case FileManagerAction.GoToHome:
      HomeClicked(null);
      return true;

    case FileManagerAction.Refresh:
      RefreshClicked!(Button)(null);
      return true;

    case FileManagerAction.StartSSH:
      return true;

    case FileManagerAction.ShowHidden:
      return true;

    case FileManagerAction.SyncTerminalPWD:
      mediator_.TerminalChangeDirectoryFromFiler(hist_.GetPWD());
      return true;

    case FileManagerAction.GoToChild:
      view_.GoDownIfOnlyOneDir();
      return true;

    case FileManagerAction.GoToDir1,
      FileManagerAction.GoToDir2,
      FileManagerAction.GoToDir3,
      FileManagerAction.GoToDir4,
      FileManagerAction.GoToDir5,
      FileManagerAction.GoToDir6,
      FileManagerAction.GoToDir7,
      FileManagerAction.GoToDir8,
      FileManagerAction.GoToDir9:
      return true;

    default:
      return false;
    }
  }
  //////////////////////// key pressed



  /////////////////////// traveling directory tree
public:
  bool ChangeDirectory(
    string dir,
    bool appendToHistory = true,
    bool notifyTerminal = true)
  {
    if(view_.ChangeDirectory(dir, appendToHistory, notifyTerminal)){
      Add(dir);
      return true;
    }
    else{
      Remove(dir);
      return false;
    }
  }

private:
  void CheckChangeDir(string path)
  {
    if(path !is null && hist_.GetPWD() != path){
      ChangeDirectory(path);
    }
  }
  /////////////////////// traveling directory tree



  /////////////////////// history of directories
private:
  DirHistory hist_;

public:
  string GetPWD(bool onlyAfterGVFS = true)
  {
    if(onlyAfterGVFS){// return "/..." instead of "/home/username/.gvfs/sftp aaa@bbb/..."
      return mediator_.FileSystemNativePath(hist_.GetPWD());
    }
    else{// to substitute $LDIR and $RDIR, non-native path is required
      return hist_.GetPWD();
    }
  }

  string GetPreviousDir()// for "cd -" in terminal
  {
    return hist_.GetDirNext!(false)();
  }

  void AppendToHistory(string dir)
  {
    hist_.Append(dir);
  }
  /////////////////////// history of directories



  /////////////////////// called for all pages in PageList
public:
  void EscapeFromPath(string path)
  {
    string pwd = hist_.GetPWD();
    if(pwd.StartsWith(path)){// inside the mounted volume
      string defaultDir = mediator_.OnLeftSide() ? rcfile.GetDefaultInitialDirectoryLeft() : rcfile.GetDefaultInitialDirectoryRight();
      ChangeDirectory(defaultDir);
    }
  }
  /////////////////////// called for all pages in PageList



  /////////////////////// callbacks for toolbar
public:
  // back and forward
  void NextDirInHistoryClicked(bool ForwardDirection, ArgType = Button)(ArgType b)
  {
    string d = hist_.GetDirNext!(ForwardDirection)();
    if(d !is null){// valid path is in history
      if(d == hist_.GetPWD()){// same directory
        hist_.RemoveDirNext!(ForwardDirection)();
      }
      else{
        if(ChangeDirectory(d, false, true)){// path exists, cd successfully
          hist_.GoNext!(ForwardDirection)();
        }
        else{// path does not exist
          PopupBox.error("directory " ~ d ~ " does not exist.", "error");
          hist_.RemoveDirNext!(ForwardDirection)();
        }
      }
    }
  }
  bool PopupDirHistoryMenu(bool ForwardDirection)(Event e, Widget w)
  {
    auto eb = e.button();
    if(eb.button != MouseButton.RIGHT){
      return false;
    }

    string[] list = hist_.Listup10!(ForwardDirection)();
    if(list.length == 0){
      return false;
    }

    auto menu = new MenuWithMargin;
    foreach(int n, l; list){
      string label = mediator_.FileSystemNativePath(l);
      auto dlg = delegate void(MenuItem item){
        MoveNTimesAndChangeDir!(ForwardDirection)(item, n+1);
      };
      menu.append(new MenuItem(dlg, label, false));
    }
    menu.showAll();
    menu.popup(0, eb.time);

    return false;
  }
  void MoveNTimesAndChangeDir(bool ForwardDirection)(MenuItem item, uint n)
  {
    for(uint i=0; i<n; ++i){
      hist_.GoNext!(ForwardDirection)();
    }
    ChangeDirectory(hist_.GetPWD(), false, true);
  }

  // go up
  void UpClicked(ArgType)(ArgType b)
  {
    string pwd = hist_.GetPWD();
    string parent = mediator_.FileSystemParentDirectory(pwd);
    if(pwd != parent){
      ChangeDirectory(parent);
    }
  }
  bool PopupGoUpMenu(Event e, Widget w)
  {
    auto eb = e.button();
    if(eb.button != MouseButton.RIGHT){
      return false;
    }

    string pwd = GetPWD();
    if(pwd == "/"){
      return false;
    }

    auto menu = new MenuWithMargin;
    string path = ParentDirectory(pwd);
    while(path != "/"){
      auto fullpath = mediator_.FileSystemMountedVFSPath(path);
      auto dlg = delegate void(MenuItem item){
        PathButtonClicked(item, fullpath);
      };
      menu.append(new MenuItem(dlg, path, false));
      path = ParentDirectory(path);
    }
    auto fullpath = mediator_.FileSystemMountedVFSPath("/");
    auto dlg = delegate void(MenuItem item){
      PathButtonClicked(item, fullpath);
    };
    menu.append(new MenuItem(dlg, "/", false));

    menu.showAll();
    menu.popup(0, eb.time);

    return false;
  }

  // miscellaneous
  void RootClicked(ArgType)(ArgType b)
  {
    CheckChangeDir(mediator_.FileSystemRoot());
  }
  void HomeClicked(ArgType)(ArgType b)
  {
    CheckChangeDir(mediator_.FileSystemHome());
  }
  void RefreshClicked(ArgType)(ArgType b)
  {
    view_.TryUpdate();
  }

  // filter
  void FilterChanged(EditableIF entry){view_.FilterChanged((cast(Entry)entry).getText());}

  // toggle buttons
  void SetShowHidden(bool b)
  {
    view_.SetShowHidden(b);
  }

  // shortcut buttons
  void PathButtonClicked(ArgType)(ArgType b, string path)
  {
    CheckChangeDir(path);
  }
  /////////////////////// callbacks for toolbar
}
