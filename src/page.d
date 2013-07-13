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

import gtk.VBox;
import gtk.HBox;
import gtk.VPaned;
import gtk.VScrollbar;
import gtk.Widget;
import gtk.Label;
import gtk.Button;
import gtk.Tooltip;

import utils.string_util;
import utils.gio_util;
import utils.min_max;
import utils.image_util;
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
  Button appendPageButton_;
  Label hostLabel_;
  Label pwdLabel_;
  Label itemsLabel_;

  VPaned paned_;
  FileManager filer_;
  HBox termWithScrollbar_;
  Terminal terminal_;

  // just to have reference to the tab widget
  Tab tab_;

  bool mapped_ = false;

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
    addOnMap(&ResetLayoutOnFirstMap);
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

      termWithScrollbar_ = new HBox(0, 0);
      termWithScrollbar_.packStart(terminal_, true, true, 0);
      auto vscrollbar = new VScrollbar(terminal_.getVadjustment());
      termWithScrollbar_.packStart(vscrollbar, false, false, 0);
      paned_.pack2(termWithScrollbar_, 1, 0);
    }
    packStart(paned_,  1, 1, 0);

    filer_.ChangeDirectory(initialDir, false, false);// do not notify terminal and do not append history

    showAll();
    SetLayout();
  }

  // initialize and set 5 widgets in topBar_
  private void SetupTopBar()
  {
    // temporarily change button size
    Button.setIconSize(GtkIconSize.MENU);
    scope(exit) Button.setIconSize(GtkIconSize.BUTTON);

    appendPageButton_ = new Button(StockID.ADD, &AppendPage, true);
    appendPageButton_.setTooltipText("Open new tab");
    topBar_.packStart(appendPageButton_, 0, 0, 0);

    auto viewModeButton = new Button(StockID.FULLSCREEN, &ViewModeButtonClicked, true);
    viewModeButton.setTooltipText("Switch view mode");
    viewModeButton.setCanFocus(0);
    topBar_.packStart(viewModeButton, 0, 0, 0);

    auto img = LoadImage("/usr/share/pixmaps/seta/gnome-session-switch.svg");
    auto goToDirOtherPaneButton = new Button;
    goToDirOtherPaneButton.setTooltipText("Go to directory shown in the other pane");
    goToDirOtherPaneButton.setCanFocus(0);
    goToDirOtherPaneButton.setImage(img);
    goToDirOtherPaneButton.addOnClicked(delegate void(Button _){
        filer_.ChangeDirectory(GetCWDOtherSide());
      });
    topBar_.packStart(goToDirOtherPaneButton, 0, 0, 0);

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
      delegate bool(int x, int y, int keyboardTip, Tooltip tip, Widget w){
        auto l = cast(Label)w;
        if(l.getLayout().isEllipsized()){
          tip.setText(l.getText());
          return true;
        }
        return false;
      });
  }

  void SetLayout()
  {
    if(this.getRealized()){
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
    else{
      // Just realize all children on startup.
      uint split = rcfile.GetWindowSizeV() / 2;
      paned_.setPosition(split);
    }
  }


  private void ResetLayoutOnFirstMap(Widget w)
  {
    // Avoid errors due to "unrealized widgets";
    // After "realize" of this page and its child widgets,
    // set layout again in order to set proper mode_ of this page.
    if(!mapped_){
      mapped_ = true;
      SetLayout();
    }
  }


  bool        OnLeftSide    (){return tab_.OnLeftSide();}
  FileManager GetFileManager(){return filer_;}
  Terminal    GetTerminal   (){return terminal_;}
  Tab         GetTab        (){return tab_;}

  void UpdatePathLabel(string path, long numItems)
  {
    string nativePath = mediator_.FileSystemNativePath(path);
    pwdLabel_.setText(nativePath);
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
      termWithScrollbar_.showAll();
      MoveFocusPosition();
      filer_.hide();
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
      filer_.showAll();
      MoveFocusPosition();
      termWithScrollbar_.hide();
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
      filer_.showAll();
      termWithScrollbar_.showAll();
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

  void ChangeDirectoryToPage(Page page)
  {
    filer_.ChangeDirectory(page.GetCWD());
  }
  ////////////////////////// file/dir path (for $LDIR and $RDIR)



  ///////////////////////// manipulation of focus
  FocusInPage WhichIsFocused()
  {
    if(filer_.hasFocus() || appendPageButton_.hasFocus())
      return FocusInPage.UPPER;
    if(terminal_.hasFocus())
      return FocusInPage.LOWER;
    return FocusInPage.NONE;
  }

  void FocusLower()
  {
    terminal_.grabFocus();
  }

  void FocusUpper()
  {
    if(mode_ == ViewMode.TERMINAL)
      appendPageButton_.grabFocus();
    else
      filer_.GrabFocus();
  }

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
