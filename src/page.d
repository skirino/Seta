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

  bool mapped_ = false;

public:
  this(Side side,
       PageInitOption opt,
       string delegate(Side, uint) GetCWDFromMain,
       void delegate(Side) AppendPageCopy,
       void delegate(Side, uint) ClosePage) {
    auto initialDir = opt.initialDir_;
    if(!DirectoryExists(initialDir)) {
      initialDir = environment.get("HOME") ~ '/';
    }

    getCWDFromMain_ = GetCWDFromMain;
    appendPage_     = AppendPageCopy;

    super(0, 0);
    addOnMap(&ResetLayoutOnFirstMap);

    tab_     .init(new Tab(side, ClosePage));
    mediator_.init(new Mediator(this));
    term_    .init(new Terminal(mediator_, initialDir, opt.terminalRunCommand_, GetCWDFromMain));
    mediator_.Set(term_);
    PackTerminalWithScrollbar();
    showAll();
    SetLayout();
  }

  private void PackTerminalWithScrollbar() {
    auto box = new HBox(false, 0);
    box.packStart(term_, true, true, 0);
    auto vscrollbar = new VScrollbar(term_.getVadjustment());
    box.packStart(vscrollbar, false, false, 0);
    packStart(box, true, true, 0);
  }

  void SetLayout() {
    if(this.getRealized()) {
      uint split = tab_.OnLeftSide() ? rcfile.GetSplitVLeft() : rcfile.GetSplitVRight();
      if(split == 0) {
        TerminalMode();
      } else if(split >= rcfile.GetWindowSizeV()) {
        FilerMode();
      } else {
        BothMode();
      }
    }
  }

  private void ResetLayoutOnFirstMap(Widget w) {
    // Avoid errors due to "unrealized widgets";
    // After "realize" of this page and its child widgets,
    // set layout again in order to set proper mode_ of this page.
    if(!mapped_) {
      mapped_ = true;
      SetLayout();
    }
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



  //////////////////////// view mode
private:
  ViewMode mode_ = ViewMode.BOTH;// initialize BOTH to read disk at startup
  int lastSplitPosition_;
  void delegate(Side) appendPage_;

  void AppendPage(Button b) {
    appendPage_(tab_.GetSide());
  }

  void GoToDirOtherSide(Button b) {
  }

public:
  ViewMode GetViewMode() { return mode_; }

  void ViewModeButtonClicked(Button b) {
    switch(mode_) {
    case ViewMode.BOTH:// switch from BOTH mode to TERMINAL mode
      TerminalMode();
      break;
    case ViewMode.TERMINAL:// switch from TERMINAL mode to FILER mode
      FilerMode();
      break;
    case ViewMode.FILER:// switch from FILER mode to BOTH mode
      BothMode();
      break;
    default:
    }
  }

private:
  void TerminalMode() {
    if(mode_ != ViewMode.TERMINAL) {
      mode_ = ViewMode.TERMINAL;
      MoveFocusPosition();
    }
  }

  void FilerMode() {
    if(mode_ != ViewMode.FILER) {
      bool needUpdate = mode_ == ViewMode.TERMINAL;
      mode_ = ViewMode.FILER;
      MoveFocusPosition();
    }
  }

  void BothMode() {
    if(mode_ != ViewMode.BOTH) {
      bool needUpdate = mode_ == ViewMode.TERMINAL;
      mode_ = ViewMode.BOTH;
      MoveFocusPosition();
    }
  }
  //////////////////////// view mode



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

  void FocusLower() {
    term_.grabFocus();
  }

  void FocusUpper() {
    term_.grabFocus();
  }

  void FocusShownWidget() {
    term_.grabFocus();
  }

  void MoveFocusPosition() {
    if(getFocusChild() !is null) {
      FocusShownWidget();
    }
  }
  ///////////////////////// manipulation of focus
}
