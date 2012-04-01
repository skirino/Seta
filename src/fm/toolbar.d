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

module fm.toolbar;

import gtk.Widget;
import gtk.Label;
import gtk.Entry;
import gtk.Button;
import gtk.ToggleButton;
import gtk.Menu;
import gtk.MenuItem;
import gtk.CheckMenuItem;
import gtk.Image;
import gtk.Toolbar;
import gtk.ToolItem;
import gtk.SeparatorToolItem;
import gtk.IconSize;
import gdk.Pixbuf;
import gdk.Event;
import glib.GException;
import glib.Str;
import glib.ListG;

import utils.template_util;
import utils.string_util;
import constants;
import rcfile = config.rcfile;
import config.known_hosts;
import file_manager;
import volume_monitor;


class SetaToolbar : Toolbar
{
private:
  FileManager parent_;
  uint numToolItemsShown_;
  size_t numShortcuts_;

  ToolItem itemBack_, itemForward_, itemUp_, itemRoot_, itemHome_, itemOtherSide_, itemRefresh_,
    itemSSH_, itemHidden_, itemDirTree_, itemSeparator1_, itemFilter_, itemSeparator2_;
  Entry filter_;
  ToggleButton showHiddenButton_;
  CheckMenuItem showHiddenMenuItem_;
  ToggleButton dirTreeButton_;
  CheckMenuItem dirTreeMenuItem_;

public:
  this(FileManager fm)
  {
    parent_ = fm;
    super();
    InitToolButtons();
    ReconstructShortcuts();
  }



  ///////////////////// accessor
  uint GetNumShortcuts(){return cast(uint)numShortcuts_;}
  Entry GetFilterEntry(){return filter_;}

  void ToggleShowHidden()
  {
    showHiddenButton_.setActive(showHiddenButton_.getActive() == 0);
  }
  void DirTreeSetActive()
  {
    dirTreeButton_.setActive(true);
  }
  bool DirTreeGetActive()
  {
    return dirTreeButton_.getActive() != 0;
  }
  void ToggleShowDirTree()
  {
    dirTreeButton_.setActive(dirTreeButton_.getActive() == 0);
  }
  ///////////////////// accessor



  ///////////////////// Layout
  void SetLayout()
  {
    dirTreeButton_.setActive(rcfile.GetWidthDirectoryTree() > 0);

    // buttons in toolbar
    numToolItemsShown_ = 0;
    mixin(FoldTupple!(InsertOrRemove, "Back", "Forward", "Up", "Root", "Home", "OtherSide", "Refresh", "SSH", "Hidden", "DirTree"));
    mixin(InsertOrRemove!("Separator1", "rcfile.GetShowFilter()"));
    mixin(InsertOrRemove!("Filter",     "rcfile.GetShowFilter()"));
    mixin(InsertOrRemove!("Separator2", "numToolItemsShown_ > 0"));

    // width of filter entry
    filter_.setSizeRequest(rcfile.GetWidthFilterEntry(), -1);

    // widths of the shortcut buttons in the toolbar
    auto list = GetShortcutButtonList();
    while(list !is null){
      Widget widget = new Widget(cast(GtkWidget*)list.data());
      widget.setSizeRequest(rcfile.GetWidthShortcutButton(), -1);
      list = list.next();
    }
  }
  ///////////////////// Layout



  ///////////////////// default buttons
private:
  void InitToolButtons()
  {
    int width, height;
    gtk.IconSize.IconSize.lookup(GtkIconSize.LARGE_TOOLBAR, width, height);

    itemBack_ = ConstructToolItemWithButton(LoadImage(StockID.GO_BACK), "Go back",
                                            &parent_.NextDirInHistoryClicked!(false, Button),
                                            &parent_.NextDirInHistoryClicked!(false, MenuItem),
                                            &parent_.PopupDirHistoryMenu!(false));
    itemForward_ = ConstructToolItemWithButton(LoadImage(StockID.GO_FORWARD), "Go forward",
                                               &parent_.NextDirInHistoryClicked!(true,  Button),
                                               &parent_.NextDirInHistoryClicked!(true,  MenuItem),
                                               &parent_.PopupDirHistoryMenu!(true));
    itemUp_ = ConstructToolItemWithButton(LoadImage(StockID.GO_UP), "Go up",
                                          &parent_.UpClicked!(Button),
                                          &parent_.UpClicked!(MenuItem),
                                          &parent_.PopupGoupMenu);
    itemRoot_ = ConstructToolItemWithButton(LoadImage(StockID.GOTO_TOP), "Go to root directory",
                                            &parent_.RootClicked!(Button), &parent_.RootClicked!(MenuItem));
    itemHome_ = ConstructToolItemWithButton(LoadImage(StockID.HOME), "Go to home directory",
                                            &parent_.HomeClicked!(Button), &parent_.HomeClicked!(MenuItem));
    itemOtherSide_ = ConstructToolItemWithButton(LoadImage("/usr/share/pixmaps/seta/gnome-session-switch.svg", width),
                                                 "Go to directory shown in the other pane",
                                                 &parent_.MoveToDirOtherSide!(Button),
                                                 &parent_.MoveToDirOtherSide!(MenuItem));
    itemRefresh_ = ConstructToolItemWithButton(LoadImage(StockID.REFRESH), "Refresh",
                                               &parent_.RefreshClicked!(Button),
                                               &parent_.RefreshClicked!(MenuItem));
    itemSSH_ = ConstructToolItemWithButton(LoadImage(StockID.NETWORK), "Start/quit SSH",
                                           &parent_.SSHClicked!(Button), &parent_.SSHClicked!(MenuItem));

    itemHidden_ = ConstructToolItemWithToggleButton(LoadImage("/usr/share/pixmaps/seta/seta_show-hidden-files.svg", width),
                                                    "Show/hide hidden files",
                                                    &HiddenClicked,
                                                    &HiddenClickedMenuItem,
                                                    showHiddenMenuItem_);
    showHiddenButton_ = cast(ToggleButton) itemHidden_.getChild();

    itemDirTree_ = ConstructToolItemWithToggleButton(LoadImage(StockID.INDENT), "Show/hide directory tree pane",
                                                     &DirTreeButtonClicked,
                                                     &DirTreeButtonClickedMenuItem,
                                                     dirTreeMenuItem_);
    dirTreeButton_ = cast(ToggleButton) itemDirTree_.getChild();

    itemSeparator1_ = new SeparatorToolItem;

    // add Entry for filter
    filter_ = new Entry;
    filter_.setTooltipText("Filter directory entries");
    filter_.addOnChanged(&parent_.FilterChanged);
    filter_.addOnActivate(&parent_.GrabFocus);
    itemFilter_ = new ToolItem;
    itemFilter_.add(filter_);

    itemSeparator2_ = new SeparatorToolItem;
  }

  Image LoadImage(StockID stockID)
  {
    return new Image(stockID, GtkIconSize.LARGE_TOOLBAR);
  }
  Image LoadImage(string path, int size){
    try{
      auto pixbuf = new Pixbuf(path, size, size, 1);
      return new Image(pixbuf);
    }
    catch(GException ex){
      return LoadImage(StockID.MISSING_IMAGE);
    }
  }

  ToolItem ConstructToolItemWithButton(
    Image img,
    string tooltip,
    void delegate(Button) dlg,
    void delegate(MenuItem) dlg2,
    bool delegate(GdkEventButton*, Widget) dlg3 = null)
  {
    auto b = new Button;
    b.setRelief(GtkReliefStyle.NONE);
    b.setImage(img);
    b.setTooltipText(tooltip);
    b.addOnClicked(dlg);
    if(dlg3 !is null){
      b.addOnButtonPress(dlg3);
    }

    auto item = new ToolItem;
    item.add(b);

    // for overflow menu
    auto menuItem = new MenuItem(dlg2, tooltip, false);
    item.setProxyMenuItem(tooltip, menuItem);

    return item;
  }
  ToolItem ConstructToolItemWithToggleButton(
    Image img,
    string tooltip,
    void delegate(ToggleButton) dlg,
    void delegate(CheckMenuItem) dlg2,
    ref CheckMenuItem menuItem)
  {
    auto b = new ToggleButton;
    b.setRelief(GtkReliefStyle.NONE);
    b.setImage(img);
    b.setTooltipText(tooltip);
    b.addOnToggled(dlg);

    auto item = new ToolItem;
    item.add(b);

    // for overflow menu
    menuItem = new CheckMenuItem(tooltip, false);
    menuItem.addOnToggled(dlg2);
    item.setProxyMenuItem(tooltip, menuItem);

    return item;
  }
  ///////////////////// default buttons



  ///////////////////// shortcut buttons
public:
  void ReconstructShortcuts()
  {
    ClearShortcuts();

    // shortcuts
    rcfile.Shortcut[] shortcuts = rcfile.GetShortcuts();
    numShortcuts_ = shortcuts.length;
    foreach(i, shortcut; shortcuts){
      string label = "(" ~ Str.toString(i+1) ~ ") " ~ shortcut.label_;
      string dir = shortcut.path_;
      AppendShortcutButton(
        dir, label, dir,
        delegate bool(GdkEventButton * eb, Widget w){
          return RemoveShortcutPopup(eb, w, dir);
        });
    }

    // mounted volumes
    string[] names, paths;
    QueryMountedVolumes(names, paths);

    foreach(i, name; names){
      string path = paths[i];
      string baseName = GetBasename(path);

      size_t index = i + 1 + numShortcuts_;
      string label = index <= 9 ? "(" ~ Str.toString(index) ~ ") " ~ baseName : baseName;
      string tooltip = name ~ " (" ~ path ~ ')';
      AppendShortcutButton(
        path, label, tooltip,
        delegate bool(GdkEventButton * eb, Widget w){
          return UnmountMediaPopup(eb, w, path, name);
        });
    }

    showAll();
  }

  void ClearShortcuts()
  {
    auto list = GetShortcutButtonList();
    while(list !is null){
      Widget w = new Widget(cast(GtkWidget*)list.data());
      remove(w);
      list = list.next();
    }
  }

private:
  void AppendShortcutButton(
    string path,
    string label,
    string tooltip,
    bool delegate(GdkEventButton*, Widget) dlgButtonPress = null)
  {
    auto child = new Label(label, false);
    child.setEllipsize(PangoEllipsizeMode.END);
    auto b = new Button;
    b.add(child);
    b.setTooltipText(tooltip);
    b.addOnClicked(
      delegate void(Button b){
        parent_.PathButtonClicked(b, path);
      });
    if(dlgButtonPress !is null){// connect callback on right-clicking this button
      b.addOnButtonPress(dlgButtonPress);
    }

    auto item = new ToolItem;
    item.setSizeRequest(rcfile.GetWidthShortcutButton(), -1);
    item.add(b);
    insert(item);

    // for overflow menu
    auto menuItem = new MenuItem(
      delegate void(MenuItem item){
        parent_.PathButtonClicked(item, path);
      },
      label ~ " (" ~ path ~ ')', false);
    if(dlgButtonPress !is null){// connect callback on right-clicking this menuitem
      menuItem.addOnButtonPress(dlgButtonPress);
    }
    item.setProxyMenuItem(label, menuItem);
  }

  bool RemoveShortcutPopup(GdkEventButton * eb, Widget w, string path)
  {
    if(eb.button == MouseButton.RIGHT){
      auto menu = new Menu;
      menu.append(new MenuItem(
                    delegate void(MenuItem item){
                      RemoveShortcut(item, path);
                    },
                    "Remove this shortcut", false));
      menu.showAll();
      menu.popup(3, (new Event(cast(GdkEvent*)eb)).getTime());// 3 indicates "right click"
    }
    return false;
  }

  void RemoveShortcut(MenuItem item, string path)
  {
    rcfile.RemoveDirectoryShortcut(path);
    // move focus to the file manager, since the focused button will go away by removing the shortcut
    parent_.GrabFocus();
  }

  ListG GetShortcutButtonList()
  {
    ListG list = getChildren();

    // skip default buttons
    size_t i=0;
    while(list !is null){
      if(i == numToolItemsShown_){
        break;
      }
      ++i;
      list = list.next();
    }

    return list;
  }
  ///////////////////// shortcut buttons



  ///////////////////// mounted volume buttons
  bool UnmountMediaPopup(GdkEventButton * eb, Widget w, string path, string name)
  {
    if(eb.button == MouseButton.RIGHT){

      // if the remote host is still accessed via ssh, skip
      if(name.StartsWith("sftp (")){
        size_t posAtmark = locate(name, '@');
        assert(posAtmark != name.length);
        string user   = name[6 .. posAtmark];
        string domain = name[posAtmark+1 .. $-1];
        if(HostIsLoggedIn(user, domain)){
          return false;
        }
      }

      auto menu = new Menu;
      menu.append(new MenuItem(
                    delegate void(MenuItem item){
                      UnmountMedia(item, path);
                    },
                    "Unmount " ~ name, false));
      menu.showAll();
      menu.popup(3, (new Event(cast(GdkEvent*)eb)).getTime());// 3 indicates "right click"
    }
    return false;
  }

  void UnmountMedia(MenuItem item, string path)
  {
    // change directory of all pages showing dirs under "path"
    if(path.containsPattern("/.gvfs/sftp ")){
      page_list.NotifyFilerDisconnect(path, path);
    }
    page_list.NotifyEscapeFromPath(path);

    if(!UnmountByPath(path)){// "path" not found in monitored volumes, just remove the "item"
      remove(item);
    }

    // move focus to the file manager, since the focused button will go away by removing the shortcut
    parent_.GrabFocus();
  }
  ///////////////////// mounted volume buttons



  ///////////////////// callbacks
  void HiddenClicked(ToggleButton x)
  {
    bool b = showHiddenButton_.getActive() != 0;
    parent_.SetShowHidden(b);
    showHiddenMenuItem_.setActive(b);
  }
  void HiddenClickedMenuItem(CheckMenuItem i)
  {
    bool b = showHiddenMenuItem_.getActive() != 0;
    parent_.SetShowHidden(b);
    showHiddenButton_.setActive(b);
  }
  void DirTreeButtonClicked(ToggleButton b)
  {
    bool show = dirTreeButton_.getActive() != 0;
    parent_.SetShowDirTree(show);
    dirTreeMenuItem_.setActive(show);
  }
  void DirTreeButtonClickedMenuItem(CheckMenuItem i)
  {
    bool show = dirTreeMenuItem_.getActive() != 0;
    parent_.SetShowDirTree(show);
    dirTreeButton_.setActive(show);
  }
  ///////////////////// callbacks
}



template InsertOrRemove(string s, string booleanExpression)
{
  const string InsertOrRemove =
    "
      if(" ~ booleanExpression ~ "){
        if(item" ~ s ~ "_.getParent is null){
          insert(item" ~ s ~ "_, numToolItemsShown_);
        }
        ++numToolItemsShown_;
      }
      else{
        if(item" ~ s ~ "_.getParent !is null){
          item" ~ s ~ "_.doref();
          remove(item" ~ s ~ "_);
        }
      }
    ";
}

template InsertOrRemove(string s)
{
  const string InsertOrRemove = InsertOrRemove!(s, "rcfile.GetShow" ~ s ~ "Button()");
}
