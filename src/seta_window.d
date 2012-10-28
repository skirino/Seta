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
import gtk.HPaned;
import gtk.VBox;
import gdk.Event;

import gdk.Keysyms;
import core.memory;
import std.stdio;

import constants;
import rcfile = config.rcfile;
import config.dialog;
import config.keybind;
import anything_cd.dialog;
import statusbar;
import note;


class SetaWindow : MainWindow
{
  ///////////////////////// GUI stuff
private:
  static __gshared SetaWindow singleton_;

  HPaned hpaned_;
  SetaStatusbar statusbar_;
  Note noteL_;
  Note noteR_;

public:
  static void Init()
  {
    singleton_ = new SetaWindow();
    SetLayout();// set parameters in rcfile
    singleton_.showAll();// do size allocations and negotiations
    SetLayout();// reset parameters and hide some of child widgets such as statusbar

    // set initial focus to lower left widget (terminal)
    singleton_.noteL_.GetCurrentPage().FocusShownWidget();
  }

  this()
  {
    super("Seta");
    addOnKeyPress(&KeyPressed);
    addOnWindowState(&WindowStateChangedCallback);
    addOnDelete(&WindowDelete);
    //setIcon(new Pixbuf("/home/skirino/temp/seta_main.jpg"));

    auto vbox = new VBox(0, 0);
    {
      hpaned_ = new HPaned;
      {
        noteL_ = new Note('L', this);
        noteR_ = new Note('R', this);

        string[] dirsL = rcfile.GetInitialDirectoriesLeft();
        foreach(dir; dirsL){
          noteL_.AppendNewPage(dir);
        }
        string[] dirsR = rcfile.GetInitialDirectoriesRight();
        foreach(dir; dirsR){
          noteR_.AppendNewPage(dir);
        }

        hpaned_.pack1(noteL_, 1, 0);
        hpaned_.pack2(noteR_, 1, 0);
      }
      vbox.packStart(hpaned_, 1, 1, 0);

      statusbar_ = InitStatusbar(noteL_, noteR_);
      vbox.packEnd(statusbar_, 0, 0, 0);
    }
    add(vbox);
  }

  static void SetLayout()
  {
    singleton_.setDefaultSize(rcfile.GetWindowSizeH(), rcfile.GetWindowSizeV());
    singleton_.hpaned_.setPosition(rcfile.GetSplitH());
    singleton_.statusbar_.SetLayout();
  }

private:
  bool WindowDelete(Event e, Widget w)
  {
    // For clean shutdown of Seta application,
    // it turns out to be better here to return TRUE (stop propagating the delete signal).
    // If the event is further propagated, the terminal in which Seta is started
    // cannot temporarily catch any keypress events.
    return true;
  }

  void AppendPageCopy(char lr)
  {
    // Make a copy of the displayed page.
    // If a remote directory is being displayed,
    // it is problematic to startup zsh within a remote directory,
    // so just create a new page with initial directory.
    if(lr == 'L'){
      noteL_.AppendPageCopy();
    }
    else{
      noteR_.AppendPageCopy();
    }
  }

  void ClosePage(char lr, uint num)
  {
    Note note = lr == 'L' ? noteL_ : noteR_;
    note.GetNthPage(num-1).PrepareDestroy();
    note.removePage(num-1);

    int npagesL = noteL_.getNPages();
    int npagesR = noteR_.getNPages();

    if(npagesL == 0 && npagesR == 0){
      Main.quit();
    }
    else if(lr == 'L' && npagesL == 0){
      auto pageR = noteR_.GetCurrentPage();
      if(pageR.WhichIsFocused() == FocusInPage.NONE){
        pageR.FocusLower();
      }
      ExpandRightPane();
      ExpandRightPane();// expand twice in order to switch from left-pane-only mode to right-pane-only
    }
    else if(lr == 'R' && npagesR == 0){
      auto pageL = noteL_.GetCurrentPage();
      if(pageL.WhichIsFocused() == FocusInPage.NONE){
        pageL.FocusLower();
      }
      ExpandLeftPane();
      ExpandLeftPane();
    }
    else{// each note has at least one page
      /+
       + Work around bug: newly-focused terminal does not process key-press events
       + after closing a page (VTE's bug?).
       + Occurs with Mint Lisa but not with Ubuntu 11.10.
       + Once focus filer, then terminal.
       +/
      auto page = note.GetCurrentPage();
      page.FocusUpper();
      page.FocusLower();
    }
  }
  ///////////////////////// GUI stuff



  ///////////////////////// file/dir path
  string GetCWDOfChildWidget(char lr, uint n)
  {
    assert(lr == 'L' || lr == 'R');
    Note note = (lr == 'L') ? noteL_ : noteR_;
    auto page = (n == 0) ? note.GetCurrentPage() : note.GetNthPage(n-1);
    return (page is null) ? null : page.GetCWD();
  }
  ///////////////////////// file/dir path



  ///////////////////////// manipulation of focus
  FocusInMainWindow WhichIsFocused()
  {
    auto pageL = noteL_.GetCurrentPage();
    if(pageL !is null && pageL.WhichIsFocused() != FocusInPage.NONE){
      return FocusInMainWindow.LEFT;
    }

    auto pageR = noteR_.GetCurrentPage();
    if(pageR !is null && pageR.WhichIsFocused() != FocusInPage.NONE){
      return FocusInMainWindow.RIGHT;
    }

    return FocusInMainWindow.NONE;
  }

  Note GetFocusedNote()
  {
    switch(WhichIsFocused()){
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

  void MoveFocus(Direction direction)()
  {
    static if(direction == Direction.UP || direction == Direction.DOWN){
      auto note = GetFocusedNote();
      if(note is null){
        return;
      }
      auto page = note.GetCurrentPage();
      FocusInPage f = page.WhichIsFocused();

      static if(direction == Direction.UP){
        if(f == FocusInPage.LOWER){
          page.FocusUpper();
        }
      }
      static if(direction == Direction.DOWN){
        if(f == FocusInPage.UPPER){
          page.FocusLower();
        }
      }
    }
    else{// direction == Direction.LEFT || direction == Direction.RIGHT
      auto pageL = noteL_.GetCurrentPage();
      if(pageL is null){
        return;
      }
      auto pageR = noteR_.GetCurrentPage();
      if(pageR is null){
        return;
      }

      FocusInPage fl = pageL.WhichIsFocused();
      FocusInPage fr = pageR.WhichIsFocused();
      if(fl == FocusInPage.NONE && fr == FocusInPage.NONE){
        return;
      }

      static if(direction == Direction.LEFT){
        if(fr == FocusInPage.UPPER){
          pageL.FocusUpper();
        }
        else if(fr == FocusInPage.LOWER){
          pageL.FocusLower();
        }
      }
      static if(direction == Direction.RIGHT){
        if(fl == FocusInPage.UPPER){
          pageR.FocusUpper();
        }
        else if(fl == FocusInPage.LOWER){
          pageR.FocusLower();
        }
      }
    }
  }
  ///////////////////////// manipulation of focus



  ///////////////////////// callback for keyboard shortcuts
  bool KeyPressed(GdkEventKey * ekey, Widget w)
  {
    version(DEBUG){
      // manually run GC
      if((ekey.state == (GdkModifierType.CONTROL_MASK | GdkModifierType.SHIFT_MASK)) &&
         ekey.keyval == GdkKeysyms.GDK_G){
        writefln("start GC");
        GC.collect();
        writefln("end GC");
        return true;
      }
    }

    // called before the focused widget's callback
    switch(QueryMainWindowAction(ekey)){

    case -1:
      return false;

    case MainWindowAction.CreateNewPage:
      switch(WhichIsFocused()){
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

    case MainWindowAction.MoveToNextPage:
      auto note = GetFocusedNote();
      if(note is null){
        return false;
      }
      else{
        if(note.getCurrentPage() == note.getNPages() - 1){// last page
          note.setCurrentPage(0);// move to the 1st page
        }
        else{
          note.nextPage();
        }
        note.GetCurrentPage().FocusShownWidget();
        return true;
      }

    case MainWindowAction.MoveToPreviousPage:
      auto note = GetFocusedNote();
      if(note is null){
        return false;
      }
      else{
        if(note.getCurrentPage() == 0){// 1st page
          note.setCurrentPage(note.getNPages() - 1);// move to the last page
        }
        else{
          note.prevPage();
        }
        note.GetCurrentPage().FocusShownWidget();
        return true;
      }

    case MainWindowAction.SwitchViewMode:
      auto note = GetFocusedNote();
      if(note is null){
        return false;
      }
      auto page = note.GetCurrentPage();
      page.ViewModeButtonClicked(null);
      return true;

    case MainWindowAction.MoveFocusUp:
      MoveFocus!(Direction.UP)();
      return true;

    case MainWindowAction.MoveFocusDown:
      MoveFocus!(Direction.DOWN)();
      return true;

    case MainWindowAction.MoveFocusLeft:
      MoveFocus!(Direction.LEFT)();
      return true;

    case MainWindowAction.MoveFocusRight:
      MoveFocus!(Direction.RIGHT)();
      return true;

    case MainWindowAction.ExpandLeftPane:
      if(statusbar.ExpandLeftPane()){
        // now only noteL is displayed.
        // if noteL does not have focus, move it to terminal widget of noteL
        auto pageL = noteL_.GetCurrentPage();
        if(pageL.WhichIsFocused() == FocusInPage.NONE){
          pageL.FocusShownWidget();
        }
      }
      return true;

    case MainWindowAction.ExpandRightPane:
      if(statusbar.ExpandRightPane()){
        auto pageR = noteR_.GetCurrentPage();
        if(pageR.WhichIsFocused() == FocusInPage.NONE){
          pageR.FocusShownWidget();
        }
      }
      return true;

    case MainWindowAction.ShowChangeDirDialog:
      auto note = GetFocusedNote();
      if(note is null){
        return false;
      }
      auto page = note.GetCurrentPage();
      if(page.FileSystemIsRemote()){
        return false;
      }
      StartChangeDirDialog(page);
      return true;

    case MainWindowAction.ShowConfigDialog:
      StartConfigDialog();
      return true;

    case MainWindowAction.ToggleFullscreen:
      if(isFullscreen_){
        unfullscreen();
      }
      else{
        fullscreen();
      }
      return true;

    case MainWindowAction.QuitApplication:
      Main.quit();
      return true;

    default:
      return false;
    }
  }
  ///////////////////////// callback for keyboard shortcuts



  ///////////////////////// toggle fullscreen
private:
  bool isFullscreen_;

  bool WindowStateChangedCallback(GdkEventWindowState * e, Widget w)
  {
    isFullscreen_ = (GdkWindowState.FULLSCREEN & e.newWindowState) != 0;
    return false;
  }
  ///////////////////////// toggle fullscreen
}
