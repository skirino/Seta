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


module mediator;

private import tango.io.Stdout;

private import constants;
private import input_dialog;
private import page;
private import file_manager;
private import terminal;
private import file_system;
private import ssh_connection;
private import statusbar;


class Mediator
{
private:
  Page page_;
  FileSystem fsys_;
  FileManager filer_;
  Terminal term_;

public:
  this(Page p)
  {
    page_ = p;
    filer_ = null;
    term_ = null;
    fsys_ = new FileSystem;
  }

  void SetFiler(FileManager f){filer_ = f;}
  void SetTerm(Terminal t){term_ = t;}



  /////////////////// SSH
  void SSHConnectionSucceeded(char[] gvfsRoot, SSHConnection con)
  {
    // within GDK lock
    char[] userDomain = con.GetUserDomain();

    if(con.GetBothSFTPAndSSH()){
      char[] password = con.getPassword();
      if(password.length == 0){
        password = InputDialog!(true)("SSH", "The remote filesystem is already mounted by gvfs.\nInput password for SSH :");
        if(password.length == 0){// no valid password
          return;
        }
        con.setPassword(password);
      }

      con.ReadShellSetting(gvfsRoot);
      term_.StartSSH(con);
      fsys_.SetRemote(gvfsRoot, con.getUsername(), con.getHomeDir(), FilerGetPWD(false));
    }

    filer_.ConnectionSucceeded(con, gvfsRoot);
    PushIntoStatusbar("Succeeded in connecting to " ~ userDomain);
  }
  /////////////////// SSH



  /////////////////// interface to Page
  bool FilerIsVisible(){return page_.GetViewMode() != ViewMode.TERMINAL;}
  char[] GetPageID(){return page_.GetTab().GetID();}
  void UpdatePathLabel(char[] path, int numItems){page_.UpdatePathLabel(path, numItems);}
  void SetHostLabel(char[] p){page_.SetHostLabel(p);}
  char[] GetHostLabel(){return page_.GetHostLabel();}
  char[] GetCWDOtherSide(){return page_.GetCWDOtherSide();}
  void CloseThisPage(){page_.CloseThisPage();}
  bool OnLeftSide(){return page_.OnLeftSide();}
  /////////////////// interface to Page



  /////////////////// interface to FileManager
  char[] FilerGetPWD(bool b){return filer_.GetPWD(b);}
  void FilerAppendToHistory(char[] dir){filer_.AppendToHistory(dir);}
  char[] FilerCDToPrevious()// for "cd -"
  {
    char[] previous = filer_.GetPreviousDir();
    if(previous.length > 0){
      filer_.ChangeDirectory(previous, true, false);
    }
    return previous;
  }
  bool FilerChangeDirectory(char[] p, bool appendHistory = true, bool notifyTerminal = true)
  {
    return filer_.ChangeDirectory(p, appendHistory, notifyTerminal);
  }
  bool FilerChangeDirFromTerminal(char[] path)
  {
    if(filer_.ChangeDirectory(path, true, false)){
      PushIntoStatusbar("\"cd " ~ path ~ "\" was sent to file manager(" ~ GetPageID() ~ ")");
      return true;
    }
    else{
      return false;
    }
  }
  void UpdateDirTree(char[] dirname)
  {
    filer_.UpdateDirTree(dirname);
  }
  void FilerDisconnect(){filer_.Disconnect();}
  void FilerFocusFilter(){filer_.FocusFilter();}
  void FilerClearFilter(){filer_.ClearFilter();}
  /////////////////// interface to FileManager



  /////////////////// interface to Terminal
  void TerminalChangeDirectoryFromFiler(char[] p)
  {
    // remove "/home/username/.gvfs/sftp ..." from p and pass it to the terminal
    char[] path = fsys_.NativePath(p);
    term_.ChangeDirectoryFromFiler(path);
    PushIntoStatusbar("\"cd " ~ path ~ "\" was sent to terminal(" ~ GetPageID() ~ ")");
  }
  void TerminalQuitSSH(char[] pwd){term_.QuitSSH(pwd);}
  /////////////////// interface to Terminal



  /////////////////// interface to FileSystem
  bool FileSystemIsRemote(){return fsys_.remote_;}
  char[] FileSystemRoot(){return fsys_.rootDir_;}
  char[] FileSystemHome(){return fsys_.homeDir_;}
  char[] FileSystemNewPath(){return fsys_.homeDir_ is null ? fsys_.rootDir_ : fsys_.homeDir_;}
  char[] FileSystemParentDirectory(char[] p){return fsys_.ParentDirectory(p);}
  char[] FileSystemNativePath(char[] p){return fsys_.NativePath(p);}
  char[] FileSystemMountedVFSPath(char[] path){return fsys_.MountedVFSPath(path);}
  char[] FileSystemSetLocal(){return fsys_.SetLocal();}
  bool FileSystemLookingAtRemoteFS(char[] p){return fsys_.LookingAtRemoteFS(p);}
  /////////////////// interface to FileSystem
}
