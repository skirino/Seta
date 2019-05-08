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
import constants;
import page;
import terminal;


class Mediator
{
private:
  Nonnull!Page     page_;
  Nonnull!Terminal term_;

public:
  this(Page p)
  {
    page_.init(p);
  }

  void Set(Terminal t)
  {
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
  bool FilerChangeDirectory(string p, bool appendHistory = true, bool notifyTerminal = true)
  {
    return true;
  }
  bool FilerChangeDirFromTerminal(string path)
  {
    return true;
  }
  /////////////////// interface to FileManager



  /////////////////// interface to Terminal
  void TerminalChangeDirectoryFromFiler(string p)
  {
    // remove "/home/username/.gvfs/sftp ..." from p and pass it to the terminal
    string path = "/";
    term_.ChangeDirectoryFromFiler(path);
  }
  /////////////////// interface to Terminal
}
