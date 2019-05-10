/*
Copyright (C) 2012-2019, Shunsuke Kirino <shunsuke.kirino@gmail.com>

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

import std.process : environment;

import gtk.HBox;
import gtk.VScrollbar;
import gtk.Paned;
import gtk.c.types : GtkOrientation;

import utils.gio_util;
import constants : Side;
import config.page_init_option;
import tab;
import terminal;
import terminal_search_bar;

class Page : Paned
{
  /////////////////////////// GUI stuff
private:
  Tab               tab_;
  TerminalSearchBar searchBar_;
  Terminal          term_;

public:
  this(Side side,
       PageInitOption opt,
       string delegate(Side, uint) GetCWDFromMain,
       void delegate(Side, uint) ClosePage) {
    auto initialDir = opt.initialDir_;
    if(!DirectoryExists(initialDir)) {
      initialDir = environment.get("HOME") ~ '/';
    }

    super(GtkOrientation.VERTICAL);
    tab_  = new Tab(side, ClosePage);
    term_ = new Terminal(initialDir, opt.terminalRunCommand_, GetCWDFromMain, &CloseThisPage);
    AddTerminalSearchBar();
    AddTerminalWithScrollbar();
  }

  private void AddTerminalSearchBar() {
    searchBar_ = new TerminalSearchBar(term_);
    add1(searchBar_);
  }

  private void AddTerminalWithScrollbar() {
    auto box = new HBox(false, 0);
    box.packStart(term_, true, true, 0);
    auto vscrollbar = new VScrollbar(term_.getVadjustment());
    box.packStart(vscrollbar, false, false, 0);
    add2(box);
    box.showAll();
  }

  void ShowTerminalSearchBar() {
    searchBar_.Show();
  }

  void HideTerminalSearchBar() {
    searchBar_.hide();
  }

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
public:
  string GetCWD() {
    return term_.GetCWD();
  }

  void ChangeDirectoryToPage(Page page) {
    term_.ChangeDirectory(page.GetCWD());
  }
  ////////////////////////// file/dir path (for $LDIR and $RDIR)



  ///////////////////////// manipulation of focus
  void GrabFocus() {
    term_.grabFocus();
  }

  bool HasFocus() {
    return term_.hasFocus();
  }

  void MoveFocusPosition() {
    if(getFocusChild() !is null) {
      term_.grabFocus();
    }
  }
  ///////////////////////// manipulation of focus
}
