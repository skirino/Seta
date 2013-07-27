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
import gtk.MenuItem;
import gtk.CheckMenuItem;
import gtk.Image;
import gtk.Toolbar;
import gtk.ToolItem;
import gtk.SeparatorToolItem;
import gdk.Event;
import glib.Str;
import glib.ListG;

import utils.template_util;
import utils.string_util;
import utils.image_util;
import utils.menu_util;
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

  ToolItem itemBack_, itemForward_, itemUp_, itemRoot_, itemHome_, itemRefresh_,
    itemSSH_, itemHidden_, itemSeparator1_, itemFilter_, itemSeparator2_;
  Entry filter_;
  ToggleButton showHiddenButton_;
  CheckMenuItem showHiddenMenuItem_;

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
  ///////////////////// accessor



  ///////////////////// Layout
  void SetLayout()
  {
    // buttons in toolbar
    numToolItemsShown_ = 0;
    mixin(FoldTupple!(InsertOrRemove, "Back", "Forward", "Up", "Root", "Home", "Refresh", "SSH", "Hidden"));
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
                                          &parent_.PopupGoUpMenu);
    itemRoot_ = ConstructToolItemWithButton(LoadImage(StockID.GOTO_TOP), "Go to root directory",
                                            &parent_.RootClicked!(Button), &parent_.RootClicked!(MenuItem));
    itemHome_ = ConstructToolItemWithButton(LoadImage(StockID.HOME), "Go to home directory",
                                            &parent_.HomeClicked!(Button), &parent_.HomeClicked!(MenuItem));
    itemRefresh_ = ConstructToolItemWithButton(LoadImage(StockID.REFRESH), "Refresh",
                                               &parent_.RefreshClicked!(Button),
                                               &parent_.RefreshClicked!(MenuItem));
    itemSSH_ = ConstructToolItemWithButton(LoadImage(StockID.NETWORK), "Start/quit SSH",
                                           &parent_.SSHClicked!(Button), &parent_.SSHClicked!(MenuItem));

    itemHidden_ = ConstructToolItemWithToggleButton(LoadImage("/usr/share/pixmaps/seta/seta_show-hidden-files.svg"),
                                                    "Show/hide hidden files",
                                                    &HiddenClicked,
                                                    &HiddenClickedMenuItem,
                                                    showHiddenMenuItem_);
    showHiddenButton_ = cast(ToggleButton) itemHidden_.getChild();

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

  ToolItem ConstructToolItemWithButton(
    Image img,
    string tooltip,
    void delegate(Button) dlg,
    void delegate(MenuItem) dlg2,
    bool delegate(Event, Widget) dlg3 = null)
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
      size_t index = i + 1;
      string dir   = shortcut.path_;
      string label = "(" ~ Str.toString(index) ~ ") " ~ shortcut.label_;
      AppendShortcutToDirectoryButton(dir, label);
    }

    // mounted volumes
    string[] names, paths;
    QueryMountedVolumes(names, paths);

    foreach(i, name; names){
      string dir      = paths[i];
      string baseName = GetBasename(dir);
      size_t index    = i + 1 + numShortcuts_;
      string label    = (index <= 9) ? "(" ~ Str.toString(index) ~ ") " ~ baseName : baseName;
      AppendShortcutToMountedVolumeButton(dir, label, name);
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
  void AppendShortcutToDirectoryButton(
    string dir,
    string label)
  {
    auto dlgButtonPress = delegate bool(Event e, Widget w){
      return RemoveShortcutPopup(e.button(), w, dir);
    };
    AppendShortcutButtonBase(dir, label, dir, dlgButtonPress);
  }

  void AppendShortcutToMountedVolumeButton(
    string dir,
    string label,
    string name)
  {
    string tooltip = name ~ " (" ~ dir ~ ')';
    auto dlgButtonPress = delegate bool(Event e, Widget w){
      return UnmountMediaPopup(e.button(), w, dir, name);
    };
    AppendShortcutButtonBase(dir, label, tooltip, dlgButtonPress);
  }

  void AppendShortcutButtonBase(
    string path,
    string label,
    string tooltip,
    bool delegate(Event, Widget) dlgButtonPress = null)
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
    b.addOnButtonPress(dlgButtonPress);// connect callback on right-clicking this button

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
    menuItem.addOnButtonPress(dlgButtonPress);// connect callback on right-clicking this menuitem
    item.setProxyMenuItem(label, menuItem);
  }

  bool RemoveShortcutPopup(GdkEventButton * eb, Widget w, string path)
  {
    if(eb.button == MouseButton.RIGHT){
      auto menu = new MenuWithMargin;
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

      auto menu = new MenuWithMargin;
      auto dlg = delegate void(MenuItem item){
        UnmountMedia(item, path);
      };
      menu.append(new MenuItem(dlg, "Unmount " ~ name, false));
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

    UnmountByPath(path);

    // move focus to the file manager, since the focused button will go away
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
  ///////////////////// callbacks
}


template InsertOrRemove(string s, string booleanExpression)
{
  immutable string InsertOrRemove =
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
  immutable string InsertOrRemove = InsertOrRemove!(s, "rcfile.GetShow" ~ s ~ "Button()");
}
