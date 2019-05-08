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

module seta_window;

import gtk.MainWindow;
import gtk.Main;
import gtk.Widget;
import gtk.Paned;
import gtk.VBox;
import gtk.PopupBox;
import gtk.c.types : GtkOrientation;
import gdk.Event;
import gdk.Keysyms;

import utils.ref_util;
import constants;
import rcfile = config.rcfile;
import config.dialog;
import config.keybind;
import note;
import page;

class SetaWindow : MainWindow
{
  ///////////////////////// static members for application-wide access
private:
  static __gshared Nonnull!SetaWindow singleton_;

public:
  static void Init() {
    singleton_.init(new SetaWindow());
    SetLayout();                                    // set parameters in rcfile
    singleton_.showAll();                           // do size allocations and negotiations
    SetLayout();                                    // reset parameters and hide some of child widgets
    singleton_.noteL_.GetCurrentPage().GrabFocus(); // set initial focus to lower left widget (terminal)
  }

  static void SetLayout() {
    singleton_.setDefaultSize(rcfile.GetWindowSizeH(), rcfile.GetWindowSizeV());
    singleton_.hpaned_.setPosition(rcfile.GetSplitH());
  }

  static void NotifyTerminalsToApplyPreferences() {
    singleton_.ForeachPage(delegate void(Page page) {
        page.GetTerminal().ApplyPreferences();
      });
  }

private:
  void ForeachPage(void delegate(Page) f) {
    ForeachPageInNote(singleton_.noteL_, f);
    ForeachPageInNote(singleton_.noteR_, f);
  }

  static void ForeachPageInNote(Note note, void delegate(Page) f) {
    auto n = note.getNPages();
    for(int i = 0; i < n; i++) {
      f(note.GetNthPage(i));
    }
  }
  ///////////////////////// static members for application-wide access



  ///////////////////////// GUI stuff
private:
  Nonnull!Paned hpaned_;
  Nonnull!Note noteL_;
  Nonnull!Note noteR_;

public:
  this() {
    super("Seta");
    addOnKeyPress(&KeyPressed);
    addOnWindowState(&WindowStateChangedCallback);
    PrepareScreenWithAlphaForTransparency();
    InitWidgets();
  }

private:
  void PrepareScreenWithAlphaForTransparency() {
    auto screen = getScreen();
    if(screen.isComposited()) {
      auto visual = screen.getRgbaVisual();
      if(visual is null) {
        visual = screen.getSystemVisual();
      }
      setVisual(visual);
    }
  }

  void InitWidgets() {
    auto vbox = new VBox(0, 0);
    hpaned_.init(new Paned(GtkOrientation.HORIZONTAL));
    noteL_.init(new Note(Side.LEFT , this));
    noteR_.init(new Note(Side.RIGHT, this));
    foreach(opt; rcfile.GetPageInitOptionsLeft()) {
      noteL_.AppendNewPage(opt);
    }
    foreach(opt; rcfile.GetPageInitOptionsRight()) {
      noteR_.AppendNewPage(opt);
    }
    hpaned_.pack1(noteL_, 1, 0);
    hpaned_.pack2(noteR_, 1, 0);
    vbox.packStart(hpaned_, 1, 1, 0);
    add(vbox);
  }

public:
  void AppendPageCopy(Side side) {
    // Make a copy of the displayed page.
    // If a remote directory is being displayed,
    // it is problematic to startup zsh within a remote directory,
    // so just create a new page with initial directory.
    auto note = side == Side.LEFT ? noteL_ : noteR_;
    note.AppendPageCopy();
  }

  void ClosePage(Side side, uint num) {
    Note note = (side == Side.LEFT) ? noteL_ : noteR_;
    note.GetNthPage(num).PrepareDestroy();
    note.removePage(num);

    const npagesL = noteL_.getNPages();
    const npagesR = noteR_.getNPages();

    if(npagesL == 0 && npagesR == 0) {
      Main.quit();
    } else if(side == Side.LEFT && npagesL == 0) {
      auto pageR = noteR_.GetCurrentPage();
      pageR.GrabFocus();
    } else if(side == Side.RIGHT && npagesR == 0) {
      auto pageL = noteL_.GetCurrentPage();
      pageL.GrabFocus();
    } else { // each note has at least one page
      /+
       + Work around bug: newly-focused terminal does not process key-press events
       + after closing a page (VTE's bug?).
       + Occurs with Mint Lisa but not with Ubuntu 11.10.
       + Once focus filer, then terminal.
       +/
      auto page = note.GetCurrentPage();
      page.GrabFocus();
    }
  }

private:
  void CloseThisPage() {
    auto note = GetFocusedNote();
    if(note is null) return;
    auto side = (note is noteL_) ? Side.LEFT : Side.RIGHT;
    ClosePage(side, note.getCurrentPage());
  }
  ///////////////////////// GUI stuff



  ///////////////////////// file/dir path
public:
  string GetCWDOfChildWidget(Side side, uint n) {
    auto note = (side == Side.LEFT) ? noteL_ : noteR_;
    auto page = (n == 0) ? note.GetCurrentPage() : note.GetNthPage(n-1);
    return (page is null) ? null : page.GetCWD();
  }

private:
  bool GoToDirOtherSide() {
    auto f = WhichIsFocused();
    auto pageL = noteL_.GetCurrentPage();
    auto pageR = noteR_.GetCurrentPage();
    if(f == FocusInMainWindow.NONE || pageL is null || pageR is null) {
      return false;
    }
    if(f == FocusInMainWindow.LEFT) {
      pageL.ChangeDirectoryToPage(pageR);
    } else {
      pageR.ChangeDirectoryToPage(pageL);
    }
    return true;
  }
  ///////////////////////// file/dir path



  ///////////////////////// pages
private:
  bool CreateNewPage() {
    switch(WhichIsFocused()) {
    case FocusInMainWindow.NONE:
      return false;
    case FocusInMainWindow.LEFT:
      noteL_.AppendPageCopy();
      return true;
    case FocusInMainWindow.RIGHT:
      noteR_.AppendPageCopy();
      return true;
    default:
      return false;
    }
  }

  void MoveToNextPage(Note note) {
    if(note.getCurrentPage() == note.getNPages() - 1) { // last page
      note.setCurrentPage(0);// move to the 1st page
    } else {
      note.nextPage();
    }
    note.GetCurrentPage().GrabFocus();
  }

  void MoveToPreviousPage(Note note) {
    if(note.getCurrentPage() == 0) { // 1st page
      note.setCurrentPage(note.getNPages() - 1);// move to the last page
    } else {
      note.prevPage();
    }
    note.GetCurrentPage().GrabFocus();
  }
  ///////////////////////// pages



  ///////////////////////// manipulation of focus
private:
  FocusInMainWindow WhichIsFocused() {
    auto pageL = noteL_.GetCurrentPage();
    if(pageL !is null) {
      return FocusInMainWindow.LEFT;
    }
    auto pageR = noteR_.GetCurrentPage();
    if(pageR !is null) {
      return FocusInMainWindow.RIGHT;
    }
    return FocusInMainWindow.NONE;
  }

  Note GetFocusedNote() {
    switch(WhichIsFocused()) {
    case FocusInMainWindow.NONE:
      return null;
    case FocusInMainWindow.LEFT:
      return noteL_;
    case FocusInMainWindow.RIGHT:
      return noteR_;
    default:
      return null;
    }
  }

  void MoveFocus(Direction direction) {
    auto pageL = noteL_.GetCurrentPage();
    if(pageL is null) return;
    auto pageR = noteR_.GetCurrentPage();
    if(pageR is null) return;
    auto note = direction == Direction.LEFT ? noteL_ : noteR_;
    if(note.getVisible()) {
      note.GetCurrentPage().GrabFocus();
    }
  }

private:
  void AddFocusToNoteIfNone(Note note) {
    note.GetCurrentPage().GrabFocus();
  }
  ///////////////////////// manipulation of focus



  ///////////////////////// fullscreen
private:
  bool isFullscreen_;

  void ToggleFullscreen() {
    if(isFullscreen_) {
      unfullscreen();
    } else {
      fullscreen();
    }
  }

  bool WindowStateChangedCallback(Event e, Widget w) {
    auto ewin = e.windowState();
    isFullscreen_ = (GdkWindowState.FULLSCREEN & ewin.newWindowState) != 0;
    return false;
  }
  ///////////////////////// fullscreen



  ///////////////////////// callback for keyboard shortcuts
  static immutable string FocusedNoteOrReturnFalse =
    "auto note = GetFocusedNote();
    if(note is null){
      return false;
    }";

  bool KeyPressed(Event e, Widget w) {
    auto ekey = e.key();

    version(DEBUG) {
      import std.stdio;
      import core.memory;
      // manually run GC
      if(TurnOffLockFlags(ekey.state) == (GdkModifierType.CONTROL_MASK | GdkModifierType.SHIFT_MASK) &&
         ekey.keyval == GdkKeysyms.GDK_G){
        writefln("start GC");
        GC.collect();
        writefln("end GC");
        return true;
      }
    }

    // called before the focused widget's callback
    switch(QueryAction!"MainWindow"(ekey)) {
    case -1:
      return false;

    case MainWindowAction.CreateNewPage:
      return CreateNewPage();

    case MainWindowAction.MoveToNextPage:
      mixin(FocusedNoteOrReturnFalse);
      MoveToNextPage(note);
      return true;

    case MainWindowAction.MoveToPreviousPage:
      mixin(FocusedNoteOrReturnFalse);
      MoveToPreviousPage(note);
      return true;

    case MainWindowAction.CloseThisPage:
      CloseThisPage();
      return true;

    case MainWindowAction.MoveFocusLeft:
      MoveFocus(Direction.LEFT);
      return true;

    case MainWindowAction.MoveFocusRight:
      MoveFocus(Direction.RIGHT);
      return true;

    case MainWindowAction.ExpandLeftPane:
      return true;

    case MainWindowAction.ExpandRightPane:
      return true;

    case MainWindowAction.GoToDirOtherSide:
      return GoToDirOtherSide();

    case MainWindowAction.ShowConfigDialog:
      StartConfigDialog();
      return true;

    case MainWindowAction.ToggleFullscreen:
      ToggleFullscreen();
      return true;

    case MainWindowAction.QuitApplication:
      if(PopupBox.yesNo("Quit Seta?", "")) {
        Main.quit();
      }
      return true;

    default:
      return false;
    }
  }
  ///////////////////////// callback for keyboard shortcuts
}
