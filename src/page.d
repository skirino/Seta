/*
Copyright (C) 2010 Shunsuke Kirino <shunsuke.kirino@gmail.com>

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

private import gtk.VBox;
private import gtk.HBox;
private import gtk.VPaned;
private import gtk.ScrolledWindow;
private import gtk.Widget;
private import gtk.Label;
private import gtk.Button;
private import gtk.Tooltip;

private import tango.io.Stdout;
private import tango.sys.Environment;

private import utils.stringUtil;
private import utils.gioUtil;
private import constants;
static private import config;
private import tab;
private import terminal;
private import fileManager;
private import mediator;
private import pageList;


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
    getCWDFromMain_ = GetCWDFromMain;
    appendPage_ = AppendPageCopy;
    
    tab_ = new Tab(side, ClosePage);
    mediator_ = new Mediator(this);
    
    Button.setIconSize(GtkIconSize.MENU);
    auto appendPageButton = new Button(StockID.ADD, &AppendPage, true);
    appendPageButton.setTooltipText("Open new tab");
    auto viewModeButton = new Button(StockID.FULLSCREEN, &ViewModeButtonClicked, true);
    viewModeButton.setTooltipText("Switch view mode");
    Button.setIconSize(GtkIconSize.BUTTON);
    
    hostLabel_ = new Label("localhost");
    pwdLabel_ = new Label("");
    pwdLabel_.setEllipsize(PangoEllipsizeMode.START);
    // tooltip for long path
    pwdLabel_.setHasTooltip(1);
    pwdLabel_.addOnQueryTooltip(
      delegate bool(int x, int y, int keyboardTip, GtkTooltip * p, Widget w)
      {
        auto l = cast(Label)w;
        if(l.getLayout().isEllipsized()){
          auto tip = new Tooltip(p);
          tip.setText(l.getText());
          return true;
        }
        return false;
      });
    itemsLabel_ = new Label("");
    topBar_ = new HBox(0, 0);
    topBar_.packStart(appendPageButton, 0, 0, 0);
    topBar_.packStart(viewModeButton, 0, 0, 0);
    topBar_.packStart(hostLabel_, 0, 0, 10);
    topBar_.packStart(pwdLabel_, 1, 1, 0);
    topBar_.packStart(itemsLabel_, 0, 0, 10);
    
    // check whether "initialDir" is a valid path or not
    if(!DirectoryExists(initialDir)){
      initialDir = Environment.get("HOME") ~ '/';
    }
    
    terminal_ = new Terminal(mediator_, initialDir, GetCWDFromMain);
    filer_ = new FileManager(mediator_, initialDir);
    
    mediator_.SetFiler(filer_);
    mediator_.SetTerm(terminal_);
    filer_.ChangeDirectory(initialDir, false, false);// do not notify terminal and do not append history
    
    // AUTOMATIC is a workaround to resize horizontally, not for horizontal scrolling
    swTerm_ = new ScrolledWindow(GtkPolicyType.AUTOMATIC, GtkPolicyType.ALWAYS);
    swTerm_.add(terminal_);
    
    paned_ = new VPaned;
    paned_.pack1(filer_, 1, 0);
    paned_.pack2(swTerm_, 1, 0);
    
    super(0, 0);
    packStart(topBar_, 0, 0, 0);
    packStart(paned_,  1, 1, 0);
    
    addOnUnrealize(&UnregisterFromPageList);
    
    showAll();
    SetLayout();
  }
  
  void SetLayout()
  {
    uint split = tab_.OnLeftSide() ? config.GetSplitVLeft() : config.GetSplitVRight();
    paned_.setPosition(split);
  }
  
  bool OnLeftSide(){return tab_.OnLeftSide();}
  Mediator GetMediator(){return mediator_;}
  FileManager GetFileManager(){return filer_;}
  Terminal GetTerminal(){return terminal_;}
  Tab GetTab(){return tab_;}
  
  void UpdatePathLabel(string path, uint numItems)
  {
    string nativePath=mediator_.FileSystemNativePath(path);
    pwdLabel_.setText(mediator_.FileSystemNativePath(path));
    tab_.SetPath(path);
    itemsLabel_.setText(PluralForm!(uint, "item")(numItems));
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
  void TerminalMode()
  {
    if(mode_ != ViewMode.TERMINAL){
      if(mode_ == ViewMode.BOTH){
        lastSplitPosition_ = paned_.getPosition();
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
        lastSplitPosition_ = paned_.getPosition();
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
    pageList.Unregister(this);
  }
  ///////////////////////// PageList
}
