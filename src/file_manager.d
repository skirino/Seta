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

import gtk.Widget;
import gtk.VBox;
import gtk.Entry;
import gtk.EditableIF;
import gtk.Button;
import gtk.ScrolledWindow;
import gtk.PopupBox;
import gtk.Menu;
import gtk.MenuItem;
import gdk.Threads;
import gdk.Event;
import gio.File;
import glib.Str;
import gtkc.gio;

import utils.string_util;
import constants;
import rcfile = config.rcfile;
import config.keybind;
import known_hosts = config.known_hosts;
import fm.file_view;
import fm.history;
import fm.toolbar;
import thread_list;
import mediator;
import statusbar;
import volume_monitor;
import ssh_connection;
import ssh_dialog;


class FileManager : VBox
{
  //////////////////////// GUI stuff
private:
  Mediator mediator_;
  SetaToolbar toolbar_;
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

    toolbar_ = new SetaToolbar(this);
    packStart(toolbar_, 0, 0, 0);

    // TreeView does not need Viewport. just use add()
    swView_ = new ScrolledWindow(GtkPolicyType.AUTOMATIC, GtkPolicyType.ALWAYS);
    swView_.add(view_);
    packStart(swView_, 1, 1, 0);

    SetLayout();
  }

  void SetLayout()
  {
    toolbar_.SetLayout();
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
  override int hasFocus(){return view_.hasFocus();}

  void GrabFocus(Entry e = null){view_.GrabFocus();}
  ///////////////////// manipulation of focus



  //////////////////////// key pressed
private:
  bool KeyPressed(Event e, Widget w)
  {
    auto ekey = e.key();

    int q = QueryFileManagerAction(ekey);
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
      SSHClicked!(Button)(null);
      return true;

    case FileManagerAction.ShowHidden:
      toolbar_.ToggleShowHidden();
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
      int index = q - FileManagerAction.GoToDir1;// 0 <= index <= 8
      if(index < toolbar_.GetNumShortcuts()){// shortcut exists
        string dir = rcfile.GetNthShortcut(index);
        CheckChangeDir(dir);
      }
      else{// mounted volumes
        string path = GetPathToNthVolume(index - toolbar_.GetNumShortcuts());
        CheckChangeDir(path);
      }
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
      anything_cd.dir_list.Add(dir);
      return true;
    }
    else{
      anything_cd.dir_list.Remove(dir);
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
      string defaultDir = mediator_.OnLeftSide() ? rcfile.GetInitialDirectoryLeft() : rcfile.GetInitialDirectoryRight();
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

    auto menu = new Menu;
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
  bool PopupGoupMenu(Event e, Widget w)
  {
    auto eb = e.button();
    if(eb.button != MouseButton.RIGHT){
      return false;
    }

    string pwd = GetPWD();
    if(pwd == "/"){
      return false;
    }

    auto menu = new Menu;
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
  void FocusFilter(){toolbar_.GetFilterEntry().grabFocus();}
  void ClearFilter(){toolbar_.GetFilterEntry().setText("");}
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
  void ReconstructShortcuts()
  {
    if(!mediator_.FileSystemIsRemote()){// only when dealing within localhost
      toolbar_.ReconstructShortcuts();
    }
  }
  /////////////////////// callbacks for toolbar



  ///////////////////////// SSH
private:
  void SSHClicked(ArgType)(ArgType b)
  {
    if(!mediator_.FileSystemIsRemote()){
      SSHConnection connection = SSHConnectionDialog();
      if(connection !is null && connection.IsValid()){

        // send message to statusbar
        PushIntoStatusbar("Trying to establish SSH connection to " ~ connection.GetUserDomain() ~ " ...");

        // check whether the remote host is already mounted
        File remoteRoot = File.parseName("sftp://" ~ connection.GetUserDomain() ~ '/');
        if(remoteRoot.queryExists(null)){// already mounted
          string remotePath = remoteRoot.getPath() ~ '/';
          mediator_.SSHConnectionSucceeded(remotePath, connection);
        }
        else{// try to mount
          // initialize sftpStarter_ and register it to the global ThreadList
          if(sftpStarter_ is null){
            sftpStarter_ = new SFTPMountStarter;
          }
          sftpStarter_.Start(remoteRoot, &(mediator_.SSHConnectionSucceeded), connection);
        }
      }
    }
    else{// already connected to a remotehost
      Disconnect();
    }
  }

public:
  void Disconnect(bool notifyTerminal = true)()
  {
    string userDomain = mediator_.GetHostLabel();

    // decrement use count
    known_hosts.Disconnect(userDomain);

    // send message to statusbar
    PushIntoStatusbar("Disconnected from " ~ userDomain);

    string pwd = mediator_.FileSystemSetLocal();
    static if(notifyTerminal){
      mediator_.TerminalQuitSSH(pwd);
    }

    mediator_.SetHostLabel("localhost");
    hist_.Reset(pwd);
    view_.ChangeDirectory(pwd);
    ReconstructShortcuts();
  }

  // executed within the GDK lock
  void ConnectionSucceeded(SSHConnection con, string gvfsRoot)
  {
    string newpath;
    if(con.GetBothSFTPAndSSH()){
      mediator_.SetHostLabel(con.GetUserDomain());
      newpath = mediator_.FileSystemNewPath();
    }
    else{
      newpath = gvfsRoot ~ con.getHomeDir();
    }

    view_.ChangeDirectory(newpath);

    if(con.GetBothSFTPAndSSH()){
      hist_.Reset(newpath);
      toolbar_.ClearShortcuts();
      con.IncrementUseCount();
    }
    else{
      hist_.Append(newpath);
      mediator_.TerminalChangeDirectoryFromFiler(newpath);
    }

    if(! known_hosts.AlreadyRegistered(con)){// not registered
      bool save = PopupBox.yesNo("Register " ~ con.getDomain() ~ '?', "Unregistered host");
      known_hosts.AddNewHost(con, save);
    }
  }

private:
  extern(C) static void MountFinishedCallback(
    GFile * ptr,
    GAsyncResult * res,
    void * data)
  {
    // need GDK lock to call gtk functions
    threadsEnter();
    SFTPMountStarter arg = cast(SFTPMountStarter)data;
    arg.Unregister();

    // Since I don't know how to instantiate AsyncResultIF from GAsyncResult* (maybe I should use SimpleAsyncResult),
    // I use the original GIO function
    GError * error;
    g_file_mount_enclosing_volume_finish(ptr, res, &error);

    if(error == null){// notify successful mount
      arg.dlgSuccess_(arg.remoteRoot_.getPath() ~ '/', arg.con_);// mediator_.ConnectionSucceeded
    }
    else{
      // FAILED_HANDLED is returned when password dialog has been canceled
      if(error.code != GIOErrorEnum.FAILED_HANDLED){// other cases, e.g. password is incorrect
        PopupBox.error(Str.toString(error.message), "error");
        PushIntoStatusbar("Failed to establish SSH/SFTP connection");
      }
    }
    threadsLeave();
  }

  class SFTPMountStarter : ListedOperationIF
  {
    mixin ListedOperationT;
    File remoteRoot_;
    void delegate(string, SSHConnection) dlgSuccess_;
    SSHConnection con_;

    void Start(File remoteRoot, void delegate(string, SSHConnection) dlg, SSHConnection con)
    {
      remoteRoot_ = remoteRoot;
      dlgSuccess_ = dlg;
      con_ = con;
      Register();

      remoteRoot_.mountEnclosingVolume(
        GMountMountFlags.NONE, con_, null,
        cast(GAsyncReadyCallback)(&MountFinishedCallback), cast(void*)this);
    }

    // Judging from the source code in gvfs (gdaemonfile.c),
    // canceling "g_file_mount_enclosing_volume" seems not to be supported at present.
    // Thus this class is not a StoppableOperationIF.
    // implementation of ListedOperationIF
    string GetThreadListLabel(string startTime)
    {
      return "Mounting " ~ con_.GetUserDomain() ~ " (" ~ startTime ~ ')';
    }

    gdk.Window.Window GetAssociatedWindow(){return null;}
  }

  SFTPMountStarter sftpStarter_;
  ///////////////////////// SSH
}
