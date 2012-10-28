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

import gtk.VBox;
import gtk.HBox;
import gtk.VPaned;
import gtk.ScrolledWindow;
import gtk.Widget;
import gtk.Label;
import gtk.Button;
import gtk.Tooltip;

import std.process;

import utils.string_util;
import utils.gio_util;
import utils.min_max;
import constants;
import rcfile = config.rcfile;
import tab;
import terminal;
import file_manager;
import mediator;
import page_list;


class Page : VBox
{
  /////////////////////////// GUI stuff
private:
  Mediator mediator_;

  HBox topBar_;
  Label hostLabel_;
  Label pwdLabel_;
  Label itemsLabel_;

  VPaned paned_;
  FileManager filer_;
  ScrolledWindow swTerm_;// to resize Terminal widget
  Terminal terminal_;

  // just to have reference to the tab widget
  Tab tab_;

public:
  this(char side,
       string initialDir,
       string delegate(char, uint) GetCWDFromMain,
       void delegate(char) AppendPageCopy,
       void delegate(char, uint) ClosePage)
  {
    // check whether "initialDir" is a valid path or not
    if(!DirectoryExists(initialDir)){
      initialDir = getenv("HOME") ~ '/';
    }

    getCWDFromMain_ = GetCWDFromMain;
    appendPage_ = AppendPageCopy;

    super(0, 0);
    addOnMap(&ResetLayoutOnMap);
    addOnUnrealize(&UnregisterFromPageList);

    // initialize children
    tab_ = new Tab(side, ClosePage);
    mediator_ = new Mediator(this);
    terminal_ = new Terminal(mediator_, initialDir, GetCWDFromMain);
    filer_ = new FileManager(mediator_, initialDir);
    mediator_.Set(filer_, terminal_);

    topBar_ = new HBox(0, 0);
    SetupTopBar();
    packStart(topBar_, 0, 0, 0);

    paned_ = new VPaned;
    {
      paned_.pack1(filer_, 1, 0);

      // AUTOMATIC is a workaround to resize horizontally; not for horizontal scrolling
      swTerm_ = new ScrolledWindow(GtkPolicyType.AUTOMATIC, GtkPolicyType.ALWAYS);
      swTerm_.add(terminal_);
      paned_.pack2(swTerm_, 1, 0);
    }
    packStart(paned_,  1, 1, 0);

    filer_.ChangeDirectory(initialDir, false, false);// do not notify terminal and do not append history

    showAll();
    SetLayout();
  }

  // initialize and set 5 widgets in topBar_
  private void SetupTopBar()
  {
    // set button size
    Button.setIconSize(GtkIconSize.MENU);

    auto appendPageButton = new Button(StockID.ADD, &AppendPage, true);
    appendPageButton.setTooltipText("Open new tab");
    appendPageButton.setCanFocus(0);
    topBar_.packStart(appendPageButton, 0, 0, 0);

    auto viewModeButton = new Button(StockID.FULLSCREEN, &ViewModeButtonClicked, true);
    viewModeButton.setTooltipText("Switch view mode");
    viewModeButton.setCanFocus(0);
    topBar_.packStart(viewModeButton, 0, 0, 0);

    // reset button size
    Button.setIconSize(GtkIconSize.BUTTON);

    hostLabel_ = new Label("localhost");
    topBar_.packStart(hostLabel_, 0, 0, 10);

    pwdLabel_ = new Label("");
    SetupPWDLabel();
    topBar_.packStart(pwdLabel_, 1, 1, 0);

    itemsLabel_ = new Label("");
    topBar_.packStart(itemsLabel_, 0, 0, 10);
  }

  private void SetupPWDLabel()
  {
    pwdLabel_.setEllipsize(PangoEllipsizeMode.START);
    // tooltip for long path
    pwdLabel_.setHasTooltip(1);
    pwdLabel_.addOnQueryTooltip(
      delegate bool(int x, int y, int keyboardTip, GtkTooltip * p, Widget w){
        auto l = cast(Label)w;
        if(l.getLayout().isEllipsized()){
          auto tip = new Tooltip(p);
          tip.setText(l.getText());
          return true;
        }
        return false;
      });
  }

  void SetLayout()
  {
    if(!this.getRealized()){
      // Just realize all children on startup.
      uint split = rcfile.GetWindowSizeV() / 2;
      paned_.setPosition(split);
    }
    else{
      uint split = tab_.OnLeftSide() ? rcfile.GetSplitVLeft() : rcfile.GetSplitVRight();
      if(split == 0){
        TerminalMode();
      }
      else if(split >= rcfile.GetWindowSizeV()){
        FilerMode();
      }
      else{
        BothMode();
        paned_.setPosition(split);
      }
    }
  }

  private void ResetLayoutOnMap(Widget w)
  {
    // After "realize" of this page and its child widgets,
    // set layout again in order to set proper mode_ of this page.
    SetLayout();
  }


  bool OnLeftSide(){return tab_.OnLeftSide();}
  FileManager GetFileManager(){return filer_;}
  Terminal GetTerminal(){return terminal_;}
  Tab GetTab(){return tab_;}

  void UpdatePathLabel(string path, long numItems)
  {
    string nativePath=mediator_.FileSystemNativePath(path);
    pwdLabel_.setText(mediator_.FileSystemNativePath(path));
    tab_.SetPath(path);
    itemsLabel_.setText(PluralForm!(long, "item")(numItems));
  }

  void SetHostLabel(string h)
  {
    hostLabel_.setText(h);
  }
  string GetHostLabel()
  {
    return hostLabel_.getText();
  }
  void CloseThisPage()
  {
    tab_.CloseThisPage();
  }
  // to stop directory monitoring
  void PrepareDestroy()
  {
    filer_.PrepareDestroy();
  }
  /////////////////////////// GUI stuff



  //////////////////////// view mode
private:
  ViewMode mode_ = ViewMode.BOTH;// initialize BOTH to read disk at startup
  int lastSplitPosition_;
  void delegate(char) appendPage_;

  void AppendPage(Button b)
  {
    char side = tab_.GetID()[0];
    appendPage_(side);
  }

public:
  ViewMode GetViewMode(){return mode_;}

  void ViewModeButtonClicked(Button b)
  {
    switch(mode_){
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
  void SetLastSplitPosition()
  {
    uint pos = paned_.getPosition();
    auto windowHeight = rcfile.GetWindowSizeV();
    lastSplitPosition_ = Max(Min(pos, 9*windowHeight/10), windowHeight/10);
  }

  void TerminalMode()
  {
    if(mode_ != ViewMode.TERMINAL){
      if(mode_ == ViewMode.BOTH){
        SetLastSplitPosition();
      }
      mode_ = ViewMode.TERMINAL;
      swTerm_.showAll();
      MoveFocusPosition();
      filer_.hideAll();
    }
  }

  void FilerMode()
  {
    if(mode_ != ViewMode.FILER){
      if(mode_ == ViewMode.BOTH){
        SetLastSplitPosition();
      }
      bool needUpdate = mode_ == ViewMode.TERMINAL;
      mode_ = ViewMode.FILER;
      filer_.ShowAll();
      MoveFocusPosition();
      swTerm_.hideAll();
      if(needUpdate){// Update AFTER changing the mode
        filer_.Update();
      }
    }
  }

  void BothMode()
  {
    if(mode_ != ViewMode.BOTH){
      bool needUpdate = mode_ == ViewMode.TERMINAL;
      mode_ = ViewMode.BOTH;
      filer_.ShowAll();
      swTerm_.showAll();
      MoveFocusPosition();
      paned_.setPosition(lastSplitPosition_);
      if(needUpdate){// Update AFTER changing the mode
        filer_.Update();
      }
    }
  }
  //////////////////////// view mode



  ////////////////////////// file/dir path (for $LDIR and $RDIR)
private:
  string delegate(char, uint) getCWDFromMain_;

public:
  string FileSystemRoot()
  {
    return mediator_.FileSystemRoot();
  }

  bool FileSystemIsRemote()
  {
    return mediator_.FileSystemIsRemote();
  }

  string GetCWD()
  {
    // if remote, return locally-mounted path
    return filer_.GetPWD(!mediator_.FileSystemIsRemote());
  }

  string GetCWDOtherSide()
  {
    char side = (tab_.GetID()[0] == 'L') ? 'R' : 'L';
    return getCWDFromMain_(side, 0);
  }

  bool LookingAtRemoteDir()
  {
    return mediator_.FileSystemLookingAtRemoteFS(filer_.GetPWD(false));
  }
  ////////////////////////// file/dir path (for $LDIR and $RDIR)



  ///////////////////////// manipulation of focus
  FocusInPage WhichIsFocused()
  {
    // Widget.hasFocus() doesn't work on Ubuntu 9.04 (gtk+-2.16 does not have gtk_widget_has_focus()).
    // The following is a workaround for it.
    Widget w = paned_.getFocusChild();
    if(w is null){
      return FocusInPage.NONE;
    }
    else{
      auto t = cast(FileManager)w;
      if(t !is null){// if downcast succeeds, the focused child is filer
        return FocusInPage.UPPER;
      }
      else{
        return FocusInPage.LOWER;
      }
    }
  }

  void FocusLower(){terminal_.grabFocus();}
  void FocusUpper(){filer_.GrabFocus();}

  void FocusShownWidget()
  {
    if(mode_ == ViewMode.FILER){
      filer_.GrabFocus();
    }
    else{// mode_ == ViewMode.TERMINAL || mode_ == ViewMode.BOTH
      terminal_.grabFocus();
    }
  }

  void MoveFocusPosition()
  {
    if(getFocusChild() !is null){
      FocusShownWidget();
    }
  }
  ///////////////////////// manipulation of focus



  ///////////////////////// PageList
  // It is unsafe to make this method inline-delegate since
  // "this" parameter's address might be different inside definition of inline-delegates.
  void UnregisterFromPageList(Widget w)
  {
    page_list.Unregister(this);
  }
  ///////////////////////// PageList
}
