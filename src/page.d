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

module page;

import std.process;
import std.algorithm;

import gtk.VBox;
import gtk.HBox;
import gtk.VScrollbar;
import gtk.Paned;
import gtk.Widget;
import gtk.Label;
import gtk.Button;
import gtk.Tooltip;
import gtk.c.types : GtkOrientation;

import utils.ref_util;
import utils.string_util;
import utils.gio_util;
import constants;
import rcfile = config.rcfile;
import config.page_init_option;
import tab;
import terminal;
import mediator;

class Page : VBox
{
  /////////////////////////// GUI stuff
private:
  Nonnull!Mediator mediator_;
  Nonnull!Tab      tab_;
  Nonnull!Terminal term_;

public:
  this(Side side,
       PageInitOption opt,
       string delegate(Side, uint) GetCWDFromMain,
       void delegate(Side, uint) ClosePage) {
    auto initialDir = opt.initialDir_;
    if(!DirectoryExists(initialDir)) {
      initialDir = environment.get("HOME") ~ '/';
    }
    getCWDFromMain_ = GetCWDFromMain;

    super(0, 0);
    tab_     .init(new Tab(side, ClosePage));
    mediator_.init(new Mediator(this));
    term_    .init(new Terminal(mediator_, initialDir, opt.terminalRunCommand_, GetCWDFromMain));
    mediator_.Set(term_);
    PackTerminalWithScrollbar();
    showAll();
  }

  private void PackTerminalWithScrollbar() {
    auto box = new HBox(false, 0);
    box.packStart(term_, true, true, 0);
    auto vscrollbar = new VScrollbar(term_.getVadjustment());
    box.packStart(vscrollbar, false, false, 0);
    packStart(box, true, true, 0);
  }

  bool     OnLeftSide () { return tab_.OnLeftSide(); }
  Terminal GetTerminal() { return term_; }
  Tab      GetTab     () { return tab_; }

  void CloseThisPage() {
    tab_.CloseThisPage();
  }

  void PrepareDestroy() {
    GetTerminal().KillChildProcessIfStillAlive();
  }
  /////////////////////////// GUI stuff



  ////////////////////////// file/dir path (for $LDIR and $RDIR)
private:
  string delegate(Side, uint) getCWDFromMain_;

public:
  string GetCWD() {
    // if remote, return locally-mounted path
    return "/";
  }

  void ChangeDirectoryToPage(Page page) {
    // TODO
  }
  ////////////////////////// file/dir path (for $LDIR and $RDIR)



  ///////////////////////// manipulation of focus
  FocusInPage WhichIsFocused() {
    return FocusInPage.LOWER;
  }

  void GrabFocus() {
    term_.grabFocus();
  }

  void MoveFocusPosition() {
    if(getFocusChild() !is null) {
      term_.grabFocus();
    }
  }
  ///////////////////////// manipulation of focus
}
