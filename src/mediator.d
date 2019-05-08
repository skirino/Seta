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

import utils.ref_util;
import utils.dialog_util;
import constants;
import page;
import file_manager;
import terminal;
import file_system;
import statusbar;


class Mediator
{
private:
  Nonnull!Page        page_;
  Nonnull!FileSystem  fsys_;
  Nonnull!FileManager filer_;
  Nonnull!Terminal    term_;

public:
  this(Page p)
  {
    page_.init(p);
    fsys_.init(new FileSystem);
  }

  void Set(FileManager f, Terminal t)
  {
    filer_.init(f);
    term_ .init(t);
  }



  /////////////////// interface to Page
  void CloseThisPage(){ page_.CloseThisPage(); }
  void UpdatePathLabel(string path, long numItems){ page_.UpdatePathLabel(path, numItems); }
  void SetHostLabel   (string path)               { page_.SetHostLabel(path); }
  bool FilerIsVisible (){ return page_.GetViewMode() != ViewMode.TERMINAL; }
  bool OnLeftSide     (){ return page_.OnLeftSide(); }
  string GetPageID      (){ return page_.GetTab().GetID(); }
  string GetHostLabel   (){ return page_.GetHostLabel(); }
  string GetCWDOtherSide(){ return page_.GetCWDOtherSide(); }
  /////////////////// interface to Page



  /////////////////// interface to FileManager
  string FilerGetPWD(bool onlyAfterGVFS = true){ return filer_.GetPWD(onlyAfterGVFS); }
  void FilerAppendToHistory(string dir){ filer_.AppendToHistory(dir); }
  string FilerCDToPrevious()// for "cd -"
  {
    string previous = filer_.GetPreviousDir();
    if(previous.length > 0){
      filer_.ChangeDirectory(previous, true, false);
    }
    return previous;
  }
  bool FilerChangeDirectory(string p, bool appendHistory = true, bool notifyTerminal = true)
  {
    return filer_.ChangeDirectory(p, appendHistory, notifyTerminal);
  }
  bool FilerChangeDirFromTerminal(string path)
  {
    if(!filer_.ChangeDirectory(path, true, false))
      return false;
    PushIntoStatusbar("\"cd " ~ path ~ "\" was sent to file manager(" ~ GetPageID() ~ ")");
    return true;
  }
  void FilerFocusFilter(){ filer_.FocusFilter(); }
  void FilerClearFilter(){ filer_.ClearFilter(); }
  /////////////////// interface to FileManager



  /////////////////// interface to Terminal
  void TerminalChangeDirectoryFromFiler(string p)
  {
    // remove "/home/username/.gvfs/sftp ..." from p and pass it to the terminal
    string path = fsys_.NativePath(p);
    term_.ChangeDirectoryFromFiler(path);
    PushIntoStatusbar("\"cd " ~ path ~ "\" was sent to terminal(" ~ GetPageID() ~ ")");
  }
  void TerminalQuitSSH(string pwd){ term_.QuitSSH(pwd); }
  /////////////////// interface to Terminal



  /////////////////// interface to FileSystem
  bool FileSystemLookingAtRemoteFS(string p){ return fsys_.LookingAtRemoteFS(p); }
  bool FileSystemIsRemote(){ return fsys_.remote_; }
  string FileSystemRoot   (){ return fsys_.rootDir_; }
  string FileSystemHome   (){ return fsys_.homeDir_; }
  string FileSystemNewPath(){ return fsys_.homeDir_ is null ? fsys_.rootDir_ : fsys_.homeDir_; }
  string FileSystemParentDirectory(string path){ return fsys_.ParentDirectory(path); }
  string FileSystemNativePath     (string path){ return fsys_.NativePath(path); }
  string FileSystemMountedVFSPath (string path){ return fsys_.MountedVFSPath(path); }
  string FileSystemSetLocal(){ return fsys_.SetLocal(); }
  /////////////////// interface to FileSystem
}
