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

module config.dialog;

import gtk.Dialog;
import gtk.Widget;
import gtk.Label;
import gtk.Notebook;
import gtk.PopupBox;
import gtk.Table;
import gtk.ScrolledWindow;
import gtk.FontButton;
import gtk.ColorButton;
import gdk.Color;
import gtk.SpinButton;
import gtk.Entry;
import gtk.CheckButton;
import gtk.Alignment;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.TreeIter;
import gtk.TreePath;
import gtk.ListStore;
import gtk.TreeStore;
import gtk.CellRendererText;
import gtk.CellRendererAccel;
import gdk.Keysyms;
import gtk.AccelGroup;
import gtk.Menu;
import gtk.MenuItem;

import std.string;

import utils.gio_util;
import utils.string_util;
import utils.tree_util;
import constants;
import rcfile = config.rcfile;
import config.keybind;
import config.hosts_view;
import page_list;


void StartConfigDialog()
{
  scope d = new ConfigDialog;
  d.showAll();
  d.run();
}


private class ConfigDialog : Dialog
{
  Notebook note_;

  this()
  {
    super();
    setDefaultSize(640, 600);
    addOnResponse(&Respond);

    addButton(StockID.CANCEL, GtkResponseType.GTK_RESPONSE_CANCEL);
    addButton(StockID.APPLY, GtkResponseType.GTK_RESPONSE_APPLY);
    addButton(StockID.OK, GtkResponseType.GTK_RESPONSE_OK);

    note_ = new Notebook;
    note_.setScrollable(1);
    getContentArea().add(note_);

    InitLayoutPage();
    InitKeybindPage();
    InitTerminalPage();
    InitDirectoriesPage();
  }

private:
  ///////////////////// [Keybind]
  TreeView keybinds_;
  TreeStore keyStore_;
  TreeIter[4] categories_;
  KeyCode[][string] dictKeyCode_;

  void InitKeybindPage()
  {
    keybinds_ = new TreeView;
    keybinds_.setEnableSearch(0);
    keybinds_.addOnButtonPress(&KeybindButtonPress);

    auto sw = new ScrolledWindow(GtkPolicyType.AUTOMATIC, GtkPolicyType.AUTOMATIC);
    sw.add(keybinds_);// without Viewport
    note_.appendPage(sw, "Key bindings");

    auto rend0 = new CellRendererText;
    auto col0 = new TreeViewColumn("Category", rend0, "text", 0);
    col0.setSizing(GtkTreeViewColumnSizing.FIXED);
    col0.setResizable(1);
    col0.setMinWidth(120);
    keybinds_.appendColumn(col0);

    auto rend1 = new CellRendererText;
    auto col1 = new TreeViewColumn("Action", rend1, "text", 1);
    col1.setSizing(GtkTreeViewColumnSizing.FIXED);
    col1.setResizable(1);
    col1.setMinWidth(180);
    keybinds_.appendColumn(col1);

    auto rend2 = new CellRendererAccel;
    rend2.setProperty("accel-mode", cast(int)GtkCellRendererAccelMode.MODE_OTHER);// to react to accels with Tab
    rend2.addOnAccelEdited(&AccelEdited);
    rend2.addOnAccelCleared(&AccelCleared);
    auto col2 = new TreeViewColumn("Key", rend2, "text", 2);
    col2.addAttribute(rend2, "editable", 3);
    col2.setSizing(GtkTreeViewColumnSizing.FIXED);
    col2.setResizable(1);
    col2.setMinWidth(180);
    keybinds_.appendColumn(col2);

    //                         Category      Action        Key           (editable)
    keyStore_ = new TreeStore([GType.STRING, GType.STRING, GType.STRING, GType.BOOLEAN]);
    keybinds_.setModel(keyStore_);

    categories_[0] = keyStore_.createIter();
    keyStore_.setValue(categories_[0], 0, "general");

    categories_[1] = keyStore_.createIter();
    keyStore_.setValue(categories_[1], 0, "file manager");

    categories_[2] = keyStore_.createIter();
    keyStore_.setValue(categories_[2], 0, "file view");

    categories_[3] = keyStore_.createIter();
    keyStore_.setValue(categories_[3], 0, "terminal");

    // arrange rows
    dictKeyCode_ = rcfile.GetKeybinds();
    string[] keys = dictKeyCode_.keys;
    keys.sort;

    foreach(key; keys){
      int x = ActionKeyToIndex(key);
      if(x != -1){
        KeyCode[] codes = dictKeyCode_[key];
        foreach(code; codes){
          scope iter = keyStore_.append(categories_[x]);
          // set Action and Key
          keyStore_.set(iter, [1, 2], [key[key.locate('.')+1 .. $], code.toString()]);
          // set Key-cell to be editable
          keyStore_.setValue(iter, 3, 1);
        }
      }
    }

    keybinds_.expandAll();
  }

  void AccelEdited(string pathStr, uint key, GdkModifierType mod, uint hardwareKeycode, CellRendererAccel rend)
  {
    // update contents of the cell by the accelerator name
    TreeIter iter = GetIterFromString(keyStore_, pathStr);
    keyStore_.setValue(iter, 2, AccelGroup.acceleratorName(key, mod));
  }

  void AccelCleared(string pathStr, CellRendererAccel rend)
  {
    // Backspace is pressed
    // do not clear and set "BackSpace" to the cell
    TreeIter iter = GetIterFromString(keyStore_, pathStr);
    keyStore_.setValue(iter, 2, AccelGroup.acceleratorName(cast(uint)GdkKeysyms.GDK_BackSpace, cast(GdkModifierType)0));
  }

  void ApplyChangesInKeybind()
  {
    bool changed = false;

    TreeIter iter = new TreeIter;
    iter.setModel(keyStore_);
    foreach(int i, category; categories_){
      if(keyStore_.iterChildren(iter, category)){
        string categoryName = IndexToActionKey(i) ~ '.';
        string previousKey;
        string[] codeList;

        do{
          string key  = iter.getValueString(1);
          string code = iter.getValueString(2);
          if(key == previousKey){
            if(code.length > 0){// skip empty (cleared) row
              codeList ~= code;
            }
          }
          else{
            if(previousKey.length > 0){// exclude first time for each category
              changed |= rcfile.ResetKeybind(categoryName ~ previousKey, codeList);
            }

            previousKey = key;
            codeList.length = 0;
            if(code.length > 0){// skip empty (cleared) row
              codeList ~= code;
            }
          }
        }
        while(keyStore_.iterNext(iter));

        if(previousKey.length > 0){
          changed |= rcfile.ResetKeybind(categoryName ~ previousKey, codeList);
        }
      }
    }

    if(changed){
      rcfile.ReconstructKeybinds();
    }
  }

  // for right click menu
  bool KeybindButtonPress(GdkEventButton * eb, Widget w)
  {
    if(eb.window != keybinds_.getBinWindow().getWindowStruct()){// header is clicked
      return false;
    }
    if(eb.button != MouseButton.RIGHT){// not right button
      return false;
    }

    grabFocus();

    TreePath path = GetPathAtPos(keybinds_, eb.x, eb.y);
    if(path is null){// empty space is clicked
      return false;
    }

    TreeIter iter = GetIter(keyStore_, path);
    path.free();

    // show menu for "Clear" and "Add"
    auto menu = new KeybindMenu(keyStore_, iter);
    menu.popup(0, eb.time);

    return false;
  }

  class KeybindMenu : Menu
  {
    TreeStore keyStore_;
    TreeIter iter_;

    this(TreeStore store, TreeIter iter)
    {
      keyStore_ = store;
      iter_ = iter;

      append(new MenuItem(&Clear, "_Clear this accelerator"));
      append(new MenuItem(&Add, "_Add new accelerator for this action"));

      showAll();
    }

    void Clear(MenuItem item)
    {
      keyStore_.setValue(iter_, 2, "");
    }

    void Add(MenuItem item)
    {
      TreeIter next = new TreeIter;
      keyStore_.insertAfter(next, null, iter_);
      keyStore_.setValue(next, 1, iter_.getValueString(1));
      keyStore_.setValue(next, 3, 1);// set editable
    }
  }
  ///////////////////// [Keybind]



  ///////////////////// [Layout]
  Table pageLayout_;
  SpinButton sbWidthType_, sbWidthSize_, sbWidthOwner_, sbWidthPermissions_, sbWidthLastModified_;
  SpinButton sbWidthDirectoryTree_, sbHeightStatusbar_;

  // toolbar
  CheckButton cbShowBackButton_, cbShowForwardButton_, cbShowUpButton_, cbShowRootButton_, cbShowHomeButton_,
    cbShowOtherSideButton_, cbShowRefreshButton_, cbShowSSHButton_, cbShowHiddenButton_, cbShowDirTreeButton_,
    cbShowFilter_, cbUseDesktopNotification_;
  SpinButton sbWidthFilterEntry_, sbWidthShortcutButton_;

  // main widgets
  SpinButton sbWindowSizeH_, sbWindowSizeV_, sbSplitH_, sbSplitVLeft_, sbSplitVRight_,
    sbNotifyExpiresInMSec_;

  // row colors
  ColorButton cbColorDirectory_, cbColorFile_, cbColorSymlink_, cbColorExecutable_;

  void InitLayoutPage()
  {
    pageLayout_ = AppendWrappedTable(note_, "Appearance");

    uint row = 0;

    AttachSectionLabel(pageLayout_, row++, "Columns in file view (0 to hide)");
    mixin(AddSpinButton!("Layout", "WidthType",         "0, 500, 1", "Width of 'type' column: "));
    mixin(AddSpinButton!("Layout", "WidthSize",         "0, 500, 1", "Width of 'size' column: "));
    mixin(AddSpinButton!("Layout", "WidthOwner",        "0, 500, 1", "Width of 'owner' column: "));
    mixin(AddSpinButton!("Layout", "WidthPermissions",  "0, 500, 1", "Width of 'permissions' column: "));
    mixin(AddSpinButton!("Layout", "WidthLastModified", "0, 500, 1", "Width of 'last modified' column: "));

    AttachSectionLabel(pageLayout_, row++, "Colors for rows in file list");
    mixin(AddColorButton!("Layout", "ColorSymlink",    "Color for symbolic links: "));
    mixin(AddColorButton!("Layout", "ColorDirectory",  "Color for directories: "));
    mixin(AddColorButton!("Layout", "ColorExecutable", "Color for executable files: "));
    mixin(AddColorButton!("Layout", "ColorFile",       "Color for the others: "));

    AttachSectionLabel(pageLayout_, row++, "Toolbar");
    mixin(AddCheckButton!("Layout", "ShowBackButton", "Show 'go back' button"));
    mixin(AddCheckButton!("Layout", "ShowForwardButton", "Show 'go forward' button"));
    mixin(AddCheckButton!("Layout", "ShowUpButton", "Show 'go up' button"));
    mixin(AddCheckButton!("Layout", "ShowRootButton", "Show 'go to root directory' button"));
    mixin(AddCheckButton!("Layout", "ShowHomeButton", "Show 'go to home directory' button"));
    mixin(AddCheckButton!("Layout", "ShowOtherSideButton", "Show 'go to directory shown in the other pane' button"));
    mixin(AddCheckButton!("Layout", "ShowRefreshButton", "Show 'refresh' button"));
    mixin(AddCheckButton!("Layout", "ShowSSHButton", "Show 'SSH' button"));
    mixin(AddCheckButton!("Layout", "ShowHiddenButton", "Show 'show/hide hidden files' button"));
    mixin(AddCheckButton!("Layout", "ShowDirTreeButton", "Show 'show/hide directory tree' button"));
    mixin(AddCheckButton!("Layout", "ShowFilter", "Show filter box"));

    mixin(AddSpinButton!("Layout", "WidthFilterEntry", "0, 200, 1", "Width of filter box in toolbar: "));
    mixin(AddSpinButton!("Layout", "WidthShortcutButton", "0, 200, 1", "Width of shortcut buttons in toolbar: "));

    AttachSectionLabel(pageLayout_, row++, "Other widgets");
    mixin(AddSpinButton!("Layout", "WidthDirectoryTree", "0, 500, 1", "Default width of directory tree widget (0 to hide): "));
    mixin(AddSpinButton!("Layout", "HeightStatusbar", "0, 100, 1", "Height of the statusbar (0 to hide): "));

    AttachSectionLabel(pageLayout_, row++, "Sizes of main widgets");
    mixin(AddSpinButton!("Layout", "SplitH", "0, 5000, 10", "Width of the left half: "));
    mixin(AddSpinButton!("Layout", "SplitVLeft" , "0, 5000, 10", "Height of the upper half on the left side: "));
    mixin(AddSpinButton!("Layout", "SplitVRight", "0, 5000, 10", "Height of the upper half on the right side: "));
    mixin(AddSpinButton!("Layout", "WindowSizeH", "10, 5000, 10", "Horizontal size of the main window: "));
    mixin(AddSpinButton!("Layout", "WindowSizeV", "10, 5000, 10", "Vertical size of the main window: "));

    AttachSectionLabel(pageLayout_, row++, "Desktop notification");
    mixin(AddCheckButton!("Layout", "UseDesktopNotification", "Notify finish of async file transfer using desktop-notification"));
    mixin(AddSpinButton!("Layout", "NotifyExpiresInMSec", "0, 30000, 100", "Expiration time on a notification (in milliseconds): "));
  }

  void ApplyChangesInLayout()
  {
    bool changed = false;

    mixin(CheckSpinButton!("WidthType"));
    mixin(CheckSpinButton!("WidthSize"));
    mixin(CheckSpinButton!("WidthOwner"));
    mixin(CheckSpinButton!("WidthPermissions"));
    mixin(CheckSpinButton!("WidthLastModified"));

    mixin(CheckColorButton!("Layout", "ColorSymlink"));
    mixin(CheckColorButton!("Layout", "ColorDirectory"));
    mixin(CheckColorButton!("Layout", "ColorExecutable"));
    mixin(CheckColorButton!("Layout", "ColorFile"));

    mixin(CheckCheckButton!("Layout", "ShowBackButton"));
    mixin(CheckCheckButton!("Layout", "ShowForwardButton"));
    mixin(CheckCheckButton!("Layout", "ShowUpButton"));
    mixin(CheckCheckButton!("Layout", "ShowRootButton"));
    mixin(CheckCheckButton!("Layout", "ShowHomeButton"));
    mixin(CheckCheckButton!("Layout", "ShowOtherSideButton"));
    mixin(CheckCheckButton!("Layout", "ShowRefreshButton"));
    mixin(CheckCheckButton!("Layout", "ShowSSHButton"));
    mixin(CheckCheckButton!("Layout", "ShowHiddenButton"));
    mixin(CheckCheckButton!("Layout", "ShowDirTreeButton"));
    mixin(CheckCheckButton!("Layout", "ShowFilter"));

    mixin(CheckSpinButton!("WidthFilterEntry"));
    mixin(CheckSpinButton!("WidthShortcutButton"));

    mixin(CheckSpinButton!("WidthDirectoryTree"));
    mixin(CheckSpinButton!("HeightStatusbar"));

    mixin(CheckSpinButton!("SplitH"));
    mixin(CheckSpinButton!("SplitVLeft"));
    mixin(CheckSpinButton!("SplitVRight"));
    mixin(CheckSpinButton!("WindowSizeH"));
    mixin(CheckSpinButton!("WindowSizeV"));

    mixin(CheckCheckButton!("Layout", "UseDesktopNotification"));
    mixin(CheckSpinButton!("NotifyExpiresInMSec"));

    if(changed){
      page_list.NotifySetLayout();
    }
  }
  ///////////////////// [Layout]



  ///////////////////// [Terminal]
  Table pageTerminal_;
  FontButton fontButton_;
  ColorButton cbColorForeground_, cbColorBackground_;
  SpinButton sbTransparency_;
  CheckButton cbEnablePathExpansion_;
  Entry entPROMPT_, entRPROMPT_, entReplaceTargetLeft_, entReplaceTargetRight_,
    entUserDefinedText1_, entUserDefinedText2_, entUserDefinedText3_, entUserDefinedText4_, entUserDefinedText5_,
    entUserDefinedText6_, entUserDefinedText7_, entUserDefinedText8_, entUserDefinedText9_;

  void InitTerminalPage()
  {
    pageTerminal_ = AppendWrappedTable(note_, "Terminal");

    uint row = 0;

    AttachSectionLabel(pageTerminal_, row++, "Appearance");
    fontButton_ = new FontButton(rcfile.GetFont());
    AttachPairWidget(pageTerminal_, row++, "Fo_nt used in terminals: ", fontButton_);

    mixin(AddColorButton!("Terminal", "ColorForeground", "_Foreground color: "));
    mixin(AddColorButton!("Terminal", "ColorBackground", "_Background color: "));

    mixin(AddSpinButton!("Terminal", "Transparency", "0.0, 1.0, 0.1", "_Transparency of background: "));

    AttachSectionLabel(pageTerminal_, row++, "Hints for Seta to extract command-line argument");

    mixin(AddEntry!("Terminal", "PROMPT",  "\"_PROMPT for terminal: \"", "PROMPT in shell"));
    mixin(AddEntry!("Terminal", "RPROMPT", "\"_RPROMPT for terminal (zsh): \"",
                    "RPROMPT in zsh, which is usually used to show additional information (e.g. working directory) on right side of terminal window"));

    AttachSectionLabel(pageTerminal_, row++, "Assist in inputting directory paths by substitution in command-line");
    mixin(AddCheckButton!("Terminal", "EnablePathExpansion", "_Enable this feature"));

    mixin(AddEntry!("Terminal", "ReplaceTargetLeft",  "\"Signature to be replaced with path (left): \"",
                    "In the case of $L<n>DIR, $LDIR will be replaced with pwd in left pane, $L1DIR with pwd in 1st tab in left pane and so on, when Enter or Tab is pressed."));
    mixin(AddEntry!("Terminal", "ReplaceTargetRight", "\"Signature to be replaced with path (right): \"",
                    "In the case of $R<n>DIR, $RDIR will be replaced with pwd in right pane, $R1DIR with pwd in 1st tab in right pane and so on, when Enter or Tab is pressed."));

    AttachSectionLabel(pageTerminal_, row++, "User defined texts that can be input by keyboard shortcuts\n   (\"\\n\" will be replaced with newline)");
    mixin(AddEntry!("Terminal", "UserDefinedText1",
                    "\"User defined text 1 (bound to \" ~ rcfile.GetInputUserDefinedText1() ~ ')'"));
    mixin(AddEntry!("Terminal", "UserDefinedText2",
                    "\"User defined text 2 (bound to \" ~ rcfile.GetInputUserDefinedText2() ~ ')'"));
    mixin(AddEntry!("Terminal", "UserDefinedText3",
                    "\"User defined text 3 (bound to \" ~ rcfile.GetInputUserDefinedText3() ~ ')'"));
    mixin(AddEntry!("Terminal", "UserDefinedText4",
                    "\"User defined text 4 (bound to \" ~ rcfile.GetInputUserDefinedText4() ~ ')'"));
    mixin(AddEntry!("Terminal", "UserDefinedText5",
                    "\"User defined text 5 (bound to \" ~ rcfile.GetInputUserDefinedText5() ~ ')'"));
    mixin(AddEntry!("Terminal", "UserDefinedText6",
                    "\"User defined text 6 (bound to \" ~ rcfile.GetInputUserDefinedText6() ~ ')'"));
    mixin(AddEntry!("Terminal", "UserDefinedText7",
                    "\"User defined text 7 (bound to \" ~ rcfile.GetInputUserDefinedText7() ~ ')'"));
    mixin(AddEntry!("Terminal", "UserDefinedText8",
                    "\"User defined text 8 (bound to \" ~ rcfile.GetInputUserDefinedText8() ~ ')'"));
    mixin(AddEntry!("Terminal", "UserDefinedText9",
                    "\"User defined text 9 (bound to \" ~ rcfile.GetInputUserDefinedText9() ~ ')'"));
  }

  void ApplyChangesInTerminal()
  {
    bool changed = false;

    changed |= rcfile.ResetStringz("Terminal", "Font", fontButton_.getFontName());

    mixin(CheckColorButton!("Terminal", "ColorForeground"));
    mixin(CheckColorButton!("Terminal", "ColorBackground"));

    changed |= rcfile.ResetDouble("Terminal", "BackgroundTransparency", sbTransparency_.getValue());

    changed |= rcfile.ResetStringz("Terminal", "PROMPT",  entPROMPT_ .getText());
    changed |= rcfile.ResetStringz("Terminal", "RPROMPT", entRPROMPT_.getText());

    mixin(CheckCheckButton!("Terminal", "EnablePathExpansion"));

    // check whether replace targets have "<n>"
    string targetL = entReplaceTargetLeft_.getText();
    if(targetL.containsPattern("<n>")){
      changed |= rcfile.ResetStringz("Terminal", "ReplaceTargetLeft" , targetL);
    }
    else{
      PopupBox.error(targetL ~ " is neglected since the signature for replace should contain \"<n>\".", "");
    }
    string targetR = entReplaceTargetRight_.getText();
    if(targetR.containsPattern("<n>")){
      changed |= rcfile.ResetStringz("Terminal", "ReplaceTargetRight", targetR);
    }
    else{
      PopupBox.error(targetR ~ " is neglected since the signature for replace should contain \"<n>\".", "");
    }

    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText1", entUserDefinedText1_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText2", entUserDefinedText2_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText3", entUserDefinedText3_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText4", entUserDefinedText4_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText5", entUserDefinedText5_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText6", entUserDefinedText6_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText7", entUserDefinedText7_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText8", entUserDefinedText8_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText9", entUserDefinedText9_.getText());

    if(changed){
      page_list.NotifyApplyTerminalPreferences();
    }
  }
  ///////////////////// [Terminal]



  ///////////////////// [Directories]
  Table pageDirectories_;
  Entry sshOptionEntry_;
  TreeView shortcuts_, initialDirsL_, initialDirsR_;
  ListStore shortcutsStore_, initialDirsLStore_, initialDirsRStore_;

  void InitDirectoriesPage()
  {
    pageDirectories_ = AppendWrappedTable(note_, "Directories and SSH");

    uint row = 0;

    AttachSectionLabel(pageDirectories_, row++, "Directories shown on start-up on the left pane");
    InitInitialDirTreeView!('L')(row++, initialDirsL_, initialDirsLStore_);

    AttachSectionLabel(pageDirectories_, row++, "Directories shown on start-up on the right pane");
    InitInitialDirTreeView!('R')(row++, initialDirsR_, initialDirsRStore_);

    AttachSectionLabel(pageDirectories_, row++, "Directory shortcuts");
    InitShortcutsTreeView(row++);

    AttachSectionLabel(pageDirectories_, row++, "Registered SSH hosts");
    InitSSHPage(row++);
    sshOptionEntry_ = new Entry(NonnullString(rcfile.GetSSHOption()));
    AttachPairWidget(pageDirectories_, row++, "Command-line option for SSH: ", sshOptionEntry_);
  }

  void InitInitialDirTreeView(char lr)(uint row, ref TreeView view, ref ListStore store)
  {
    view = new TreeView;
    view.setSizeRequest(-1, 160);
    view.setReorderable(1);
    view.addOnButtonPress(delegate bool(GdkEventButton * eb, Widget w){
        return ShowAppendRemoveMenu(eb, w, view, store);
      });
    AppendWithScrolledWindow(pageDirectories_, row, view);

    auto rend = new CellRendererText;
    rend.setProperty("editable", 1);
    rend.addOnEdited(&(CellEdited!(0, "initialDirs" ~ lr ~ "Store_", "AppendSlash")));
    auto col = new TreeViewColumn("path", rend, "text", 0);
    col.setResizable(1);
    view.appendColumn(col);

    store = new ListStore([GType.STRING]);
    view.setModel(store);

    auto source = lr == 'L' ? rcfile.GetInitialDirectoriesLeft() : rcfile.GetInitialDirectoriesRight();
    foreach(dir; source){
      TreeIter iter = new TreeIter;
      store.append(iter);
      store.setValue(iter, 0, dir);
    }
  }

  void InitShortcutsTreeView(uint row)
  {
    shortcuts_ = new TreeView;
    shortcuts_.setSizeRequest(-1, 160);
    shortcuts_.setReorderable(1);
    shortcuts_.addOnButtonPress(delegate bool(GdkEventButton * eb, Widget w){
        return ShowAppendRemoveMenu(eb, w, shortcuts_, shortcutsStore_);
      });
    AppendWithScrolledWindow(pageDirectories_, row, shortcuts_);

    auto rendLabel = new CellRendererText;
    rendLabel.setProperty("editable", 1);
    rendLabel.addOnEdited(&(CellEdited!(0, "shortcutsStore_")));
    auto colLabel = new TreeViewColumn("label", rendLabel, "text", 0);
    colLabel.setResizable(1);
    shortcuts_.appendColumn(colLabel);

    auto rendDir = new CellRendererText;
    rendDir.setProperty("editable", 1);
    rendDir.addOnEdited(&(CellEdited!(1, "shortcutsStore_", "AppendSlash")));
    auto colDir = new TreeViewColumn("path", rendDir, "text", 1);
    colDir.setResizable(1);
    shortcuts_.appendColumn(colDir);

    //                               label         path          add color for dirs which are not found?
    shortcutsStore_ = new ListStore([GType.STRING, GType.STRING]);
    shortcuts_.setModel(shortcutsStore_);

    foreach(shortcut; rcfile.GetShortcuts()){
      TreeIter iter = new TreeIter;
      shortcutsStore_.append(iter);
      shortcutsStore_.setValue(iter, 0, shortcut.label_);
      shortcutsStore_.setValue(iter, 1, shortcut.path_);
    }
  }

  void ApplyChangesInDirectories()
  {
    ApplyChangesInInitialDirectories(initialDirsLStore_, "InitialDirectoriesLeft");
    ApplyChangesInInitialDirectories(initialDirsRStore_, "InitialDirectoriesRight");
    ApplyChangesInShortcuts();
  }

  void ApplyChangesInInitialDirectories(ListStore store, string key)
  {
    string[] dirs;
    TreeIter iter = new TreeIter;
    iter.setModel(store);
    if(store.getIterFirst(iter)){// ListStore is not empty
      do{
        auto dir = AppendSlash(trim(iter.getValueString(0)));
        if(CanEnumerateChildren(dir)){
          dirs ~= dir;
        }
      }
      while(store.iterNext(iter));
    }
    rcfile.ResetStringList("Directories", key, dirs);
  }

  void ApplyChangesInShortcuts()
  {
    rcfile.Shortcut[] list;
    TreeIter iter = new TreeIter;
    iter.setModel(shortcutsStore_);
    if(shortcutsStore_.getIterFirst(iter)){// ListStore is not empty
      do{
        string label = trim(iter.getValueString(0));
        string path  = trim(iter.getValueString(1));
        if(label.length == 0){
          label = GetBasename(path);
        }
        if(CanEnumerateChildren(path)){
          list ~= rcfile.Shortcut(label, path);
        }
      }
      while(shortcutsStore_.iterNext(iter));
    }
    rcfile.ResetShortcuts(list);
  }

  void CellEdited(int idx, string modelIdentifier, string transformFun = "")(
    string pathStr, string newName, CellRendererText rend)
  {
    ListStore model = mixin(modelIdentifier);
    TreeIter iter = GetIterFromString(model, pathStr);
    static if(transformFun.length == 0){
      model.setValue(iter, idx, newName);
    }
    else{
      model.setValue(iter, idx, mixin(transformFun) (newName));
    }
  }

  // for right click menu
  bool ShowAppendRemoveMenu(GdkEventButton * eb, Widget w, TreeView view, ListStore store)
  {
    if(eb.window != view.getBinWindow().getWindowStruct()){// header is clicked
      return false;
    }
    if(eb.button != MouseButton.RIGHT){// not right button
      return false;
    }

    TreePath path = GetPathAtPos(view, eb.x, eb.y);
    TreeIter iter;
    if(path !is null){// there is a row at cursor
      iter = GetIter(store, path);
      path.free();
    }

    auto menu = new AppendRemoveMenu(view, store, iter);
    menu.popup(0, eb.time);

    return false;
  }

  class AppendRemoveMenu : Menu
  {
    TreeView view_;
    ListStore store_;
    TreeIter iter_;

    this(TreeView view, ListStore store, TreeIter iter)
    {
      view_ = view;
      store_ = store;
      iter_ = iter;

      append(new MenuItem(&Append, "_Append"));
      if(iter !is null){
        append(new MenuItem(&Remove, "_Remove"));
      }

      showAll();
    }

    void Append(MenuItem item)
    {
      TreeIter next = new TreeIter;
      next.setModel(store_);
      if(iter_ is null){// empty space is clicked
        store_.append(next);
      }
      else{// one row is clicked
        store_.insertAfter(next, iter_);
      }

      // select the new row
      TreePath path = next.getTreePath();
      view_.setCursor(path, null, 1);
      path.free();
    }

    void Remove(MenuItem item)
    {
      store_.remove(iter_);
    }
  }
  ///////////////////// [Directories]



  ///////////////////// [SSH]
  HostView hosts_;
  ListStore hostsStore_;

  void InitSSHPage(uint row)
  {
    hosts_ = new HostView;
    hosts_.setReorderable(1);
    hosts_.addOnButtonPress(delegate bool(GdkEventButton * eb, Widget w){
        return ShowAppendRemoveMenu(eb, w, hosts_, hostsStore_);
      });

    hosts_.SetEditable(
      &CellEdited!(0, "hostsStore_"),
      &CellEdited!(1, "hostsStore_"),
      &CellEdited!(2, "hostsStore_", "AppendSlash"),
      &CellEdited!(3, "hostsStore_"),
      &CellEdited!(4, "hostsStore_"));

    hostsStore_ = hosts_.GetListStore();
    AppendWithScrolledWindow(pageDirectories_, row, hosts_);
  }

  void ApplyChangesInSSH()
  {
    rcfile.ResetStringz("SSH", "SSHOption", sshOptionEntry_.getText());

    string[] list;
    TreeIter iter = new TreeIter;
    iter.setModel(hostsStore_);
    if(hostsStore_.getIterFirst(iter)){// ListStore is not empty
      do{
        string[] items;
        for(uint i=0; i<5; ++i){
          items ~= trim(iter.getValueString(i));
        }
        list ~= join(items, ":");
      }
      while(hostsStore_.iterNext(iter));
    }

    rcfile.ResetRemoteHosts(list);
  }
  ///////////////////// [SSH]



  void Respond(int responseID, Dialog dialog)
  {
    if(responseID == GtkResponseType.GTK_RESPONSE_OK || responseID == GtkResponseType.GTK_RESPONSE_APPLY){
      ApplyChangesInKeybind();
      ApplyChangesInLayout();
      ApplyChangesInTerminal();
      ApplyChangesInDirectories();
      ApplyChangesInSSH();
      rcfile.Write();
    }

    if(responseID != GtkResponseType.GTK_RESPONSE_APPLY){
      destroy();
    }
  }
}



private template AddSpinButton(string group, string key, string args, string explanation){
  const string AddSpinButton =
    "
    sb" ~ key ~ "_ = new SpinButton(" ~ args ~ ");
    sb" ~ key ~ "_.setValue(rcfile.Get" ~ key ~ "());
    AttachPairWidget(page" ~ group ~ "_, row++, \"" ~ explanation ~ "\", sb" ~ key ~ "_);
    ";
}
private template CheckSpinButton(string key)// currently only for "Layout" group
{
  const string CheckSpinButton =
    "
    changed |= rcfile.ResetInteger(\"Layout\", \"" ~ key ~ "\", sb" ~ key ~ "_.getValueAsInt());
    ";
}


private template AddCheckButton(string group, string key, string explanation)
{
  const string AddCheckButton =
    "
    cb" ~ key ~ "_ = new CheckButton(\"" ~ explanation ~ "\");
    cb" ~ key ~ "_.setActive(rcfile.Get" ~ key ~ "());
    page" ~ group ~ "_.attach(Alignment.west(cb" ~ key ~ "_), 0, 2, row, row+1,
                              GtkAttachOptions.FILL, cast(GtkAttachOptions)0, XPadding, YPadding);
    ++row;
    ";
}
private template CheckCheckButton(string group, string key)
{
  const string CheckCheckButton =
    "
    changed |= rcfile.ResetBoolean(\"" ~ group ~ "\", \"" ~ key ~ "\", cb" ~ key ~ "_.getActive() != 0);
    ";
}


private template AddColorButton(string group, string key, string explanation)
{
  const string AddColorButton =
    "
    {
      GdkColor color;
      Color.parse(rcfile.Get" ~ key ~ "(), color);
      cb" ~ key ~ "_ = new ColorButton(new Color(&color));
      AttachPairWidget(page" ~ group ~ "_, row++, \"" ~ explanation ~ "\", cb" ~ key ~ "_);
    }
    ";
}
private template CheckColorButton(string group, string key)
{
  const string CheckColorButton =
    "
    {
      Color temp = new Color;
      cb" ~ key ~ "_.getColor(temp);
      changed |= rcfile.ResetStringz(\"" ~ group ~ "\", \"" ~ key ~ "\", temp.toString());
    }
    ";
}


private template AddEntry(string group, string key, string explanation, string tooltip = "")
{
  const string AddEntry =
    "
    ent" ~ key ~ "_ = new Entry(NonnullString(rcfile.Get" ~ key ~ "()));
    AttachPairWidget(page" ~ group ~ "_, row++, " ~ explanation ~ ", ent" ~ key ~ "_, \"" ~ tooltip ~ "\");
    ";
}


private Table AppendWrappedTable(Notebook note, string title)
{
  Table t = new Table(1, 2, 0);
  auto win = new ScrolledWindow(GtkPolicyType.AUTOMATIC, GtkPolicyType.AUTOMATIC);
  win.addWithViewport(t);// Table needs Viewport
  note.appendPage(win, title);
  return t;
}


private void AppendWithScrolledWindow(Table t, uint row, Widget w)
{
  auto sw = new ScrolledWindow(GtkPolicyType.NEVER, GtkPolicyType.AUTOMATIC);
  sw.add(w);// widget is assumed to support scrolling by itself, not with Viewport
  t.attach(sw, 0, 2, row, row+1, GtkAttachOptions.FILL | GtkAttachOptions.EXPAND, GtkAttachOptions.FILL, XPadding, YPadding);
}


private void AttachPairWidget(Table t, uint row, string labelText, Widget w, string tooltip = "")
{
  Label l = new Label(labelText);
  if(tooltip.length > 0){
    l.setTooltipText(tooltip);
    w.setTooltipText(tooltip);
  }
  l.setMnemonicWidget(w);
  l.setAlignment(0.0, 0.5);// left-align labels
  t.attach(l, 0, 1, row, row+1, GtkAttachOptions.FILL,   cast(GtkAttachOptions)0, XPadding, YPadding);
  t.attach(w, 1, 2, row, row+1, GtkAttachOptions.FILL | GtkAttachOptions.EXPAND, cast(GtkAttachOptions)0, XPadding, YPadding);
}

private void AttachSectionLabel(Table t, uint row, string text)
{
  if(row > 0){// append additional space between sections
    t.setRowSpacing(row-1, 15);
  }
  auto l = new Label("<b>" ~ text ~ "</b>");// bold text
  l.setUseMarkup(1);
  l.setAlignment(0.0, 1.0);
  t.attach(l, 0, 2, row, row+1, GtkAttachOptions.FILL, GtkAttachOptions.FILL, 10, 5);
}


// constants to align widgets in Table
private const int XPadding = 20;
private const int YPadding = 3;
