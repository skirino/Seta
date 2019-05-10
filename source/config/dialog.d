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

module config.dialog;

import std.string : strip, indexOf;
import std.algorithm : sort;

import gtk.Dialog;
import gtk.Widget;
import gtk.Label;
import gtk.Notebook;
import gtk.PopupBox;
import gtk.Table;
import gtk.ScrolledWindow;
import gtk.FontButton;
import gtk.ColorButton;
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
import gtk.AccelGroup;
import gtk.MenuItem;
import gdk.Keysyms;
import gdk.Event;
import gdk.Color;

import utils.string_util;
import utils.tree_util;
import utils.menu_util;
import utils.gio_util;
import constants;
import rcfile = config.rcfile;
import config.keybind;
import config.page_init_option;
import seta_window;

void StartConfigDialog() {
  auto d = new ConfigDialog;
  d.showAll();
  d.run();
}

private class ConfigDialog : Dialog
{
  Notebook note_;

  this() {
    super();
    setResizable(false);
    setSizeRequest(800, 720);
    addOnResponse(&Respond);

    addButton(StockID.CANCEL, GtkResponseType.CANCEL);
    addButton(StockID.APPLY,  GtkResponseType.APPLY);
    addButton(StockID.OK,     GtkResponseType.OK);

    note_ = new Notebook;
    note_.setScrollable(1);
    note_.setVexpand(1);
    getContentArea().add(note_);

    InitLayoutPage();
    InitPagesPage();
    InitKeybindPage();
    InitTerminalPage();
  }

private:
  ///////////////////// [Layout]
  Table pageLayout_;
  SpinButton sbWindowSizeH_, sbWindowSizeV_, sbSplitH_;

  void InitLayoutPage() {
    pageLayout_ = AppendWrappedTable(note_, "Window arrangement");
    uint row = 0;
    AttachSectionLabel(pageLayout_, row++, "Size of the main window");
    mixin(AddSpinButton!("Layout", "WindowSizeH", "10, 5000, 10", "Horizontal size of the main window: "));
    mixin(AddSpinButton!("Layout", "WindowSizeV", "10, 5000, 10", "Vertical size of the main window: "));
    mixin(AddSpinButton!("Layout", "SplitH",      "0, 5000, 10",  "Width of the left half: "));
  }

  void ApplyChangesInLayout() {
    bool changed = false;
    mixin(CheckSpinButton!("SplitH"));
    mixin(CheckSpinButton!("WindowSizeH"));
    mixin(CheckSpinButton!("WindowSizeV"));
    if(changed) {
      SetaWindow.SetLayout();
    }
  }
  ///////////////////// [Layout]



  ///////////////////// [Pages]
  Table pagePages_;
  TreeView pagesLeft_, pagesRight_;
  ListStore pagesLeftStore_, pagesRightStore_;

  void InitPagesPage() {
    pagePages_ = AppendWrappedTable(note_, "Pages");

    uint row = 0;

    AttachSectionLabel(pagePages_, row++, "Pages shown on left side on start-up");
    InitPagesTree!(Side.LEFT)(row++, pagesLeft_, pagesLeftStore_);

    AttachSectionLabel(pagePages_, row++, "Pages shown on right side on start-up");
    InitPagesTree!(Side.RIGHT)(row++, pagesRight_, pagesRightStore_);
  }

  void InitPagesTree(Side side)(uint row, ref TreeView view, ref ListStore store) {
    view = new TreeView;
    view.setVexpand(1);
    view.addOnButtonPress(delegate bool(Event e, Widget w) {
        return ShowAppendRemoveMenu(e, w, view, store);
      });
    AppendWithScrolledWindow(pagePages_, row, view);

    auto rendPath = new CellRendererText;
    rendPath.setProperty("editable", 1);
    rendPath.addOnEdited(&(CellEdited!(0, "pages" ~ (side == Side.LEFT ? "Left" : "Right") ~ "Store_", "AppendSlash")));
    auto colPath = new TreeViewColumn("path", rendPath, "text", 0);
    colPath.setResizable(1);
    view.appendColumn(colPath);

    auto rendCommand = new CellRendererText;
    rendCommand.setProperty("editable", 1);
    rendCommand.addOnEdited(&(CellEdited!(1, "pages" ~ (side == Side.LEFT ? "Left" : "Right") ~ "Store_")));
    auto colCommand = new TreeViewColumn("command", rendCommand, "text", 1);
    colCommand.setResizable(1);
    view.appendColumn(colCommand);

    store = new ListStore([GType.STRING, GType.STRING]);
    view.setModel(store);

    auto source = (side == Side.LEFT) ? rcfile.GetPageInitOptionsLeft() : rcfile.GetPageInitOptionsRight();
    foreach(opt; source) {
      auto iter = new TreeIter;
      store.append(iter);
      store.setValue(iter, 0, opt.initialDir_);
      store.setValue(iter, 1, opt.terminalRunCommand_);
    }
  }

  void ApplyChangesInPages() {
    ApplyChangesInPageInitOptions(pagesLeftStore_ , "InitialPagesLeft" );
    ApplyChangesInPageInitOptions(pagesRightStore_, "InitialPagesRight");
  }

  void ApplyChangesInPageInitOptions(ListStore store, string key) {
    PageInitOption[] opts;
    ForeachRow(store, null, delegate void(TreeIter iter) {
        auto path    = iter.getValueString(0).strip().AppendSlash();
        auto command = iter.getValueString(1);
        if(CanEnumerateChildren(path)) {
          opts ~= PageInitOption(path, command);
        }
      });
    rcfile.ResetPageInitOptions(key, opts);
  }
  ///////////////////// [Pages]



  ///////////////////// [Keybind]
  static immutable N_CATEGORIES = 2;
  static immutable string[N_CATEGORIES] CATEGORY_IDENTIFIERS  = ["MainWindow", "Terminal"];
  static immutable string[N_CATEGORIES] CATEGORY_EXPLANATIONS = ["general", "terminal"];

  TreeView keybinds_;
  TreeStore keyStore_;
  TreeIter[N_CATEGORIES] categories_;
  KeyCode[][string] dictKeyCode_;

  void InitKeybindPage() {
    keybinds_ = new TreeView;
    keybinds_.setEnableSearch(0);
    keybinds_.addOnButtonPress(&KeybindButtonPress);

    auto sw = new ScrolledWindow(GtkPolicyType.AUTOMATIC, GtkPolicyType.AUTOMATIC);
    sw.add(keybinds_); // without Viewport
    note_.appendPage(sw, "Key bindings");

    auto rend0 = new CellRendererText;
    auto col0 = new TreeViewColumn("Category", rend0, "text", 0);
    col0.setSizing(GtkTreeViewColumnSizing.FIXED);
    col0.setResizable(1);
    col0.setMinWidth(150);
    keybinds_.appendColumn(col0);

    auto rend1 = new CellRendererText;
    auto col1 = new TreeViewColumn("Action", rend1, "text", 1);
    col1.setSizing(GtkTreeViewColumnSizing.FIXED);
    col1.setResizable(1);
    col1.setMinWidth(240);
    keybinds_.appendColumn(col1);

    auto rend2 = new CellRendererAccel;
    rend2.setProperty("accel-mode", cast(int)GtkCellRendererAccelMode.OTHER); // to react to accels with Tab
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

    for(int i = 0; i < N_CATEGORIES; ++i) {
      categories_[i] = keyStore_.createIter();
      keyStore_.setValue(categories_[i], 0, CATEGORY_EXPLANATIONS[i]);
    }

    // arrange rows
    dictKeyCode_ = rcfile.GetKeybinds();
    string[] keys = dictKeyCode_.keys;
    sort(keys);

    foreach(key; keys) {
      auto categoryIter = FindCategoryIterFromActionKey(key);
      KeyCode[] codes = dictKeyCode_[key];
      foreach(code; codes) {
        auto iter = keyStore_.append(categoryIter);
        keyStore_.set(iter, [1, 2], [key[key.indexOf('.') + 1 .. $], code.toString()]);
        keyStore_.setValue(iter, 3, 1); // make Key-cell editable
      }
    }

    keybinds_.expandAll();
  }

  TreeIter FindCategoryIterFromActionKey(string key) {
    foreach(i, id; CATEGORY_IDENTIFIERS) {
      if(key.StartsWith(id)) {
        return categories_[i];
      }
    }
    assert(false);
  }

  void AccelEdited(string pathStr, uint key, GdkModifierType mod, uint hardwareKeycode, CellRendererAccel rend) {
    // update contents of the cell by the accelerator name
    TreeIter iter = GetIterFromString(keyStore_, pathStr);
    keyStore_.setValue(iter, 2, AccelGroup.acceleratorName(key, mod));
  }

  void AccelCleared(string pathStr, CellRendererAccel rend) {
    // Backspace is pressed
    // do not clear and set "BackSpace" to the cell
    TreeIter iter = GetIterFromString(keyStore_, pathStr);
    keyStore_.setValue(iter, 2, AccelGroup.acceleratorName(cast(uint)GdkKeysyms.GDK_BackSpace, cast(GdkModifierType)0));
  }

  void ApplyChangesInKeybind() {
    bool changed = false;

    foreach(int i, category; categories_) {
      string categoryName = CATEGORY_IDENTIFIERS[i] ~ "Action.";
      string[][string] bindings;
      ForeachRow(keyStore_, category, delegate void(TreeIter iter) {
          string key  = iter.getValueString(1);
          string code = iter.getValueString(2);
          bindings[key] ~= code;
        });
      foreach(key, codes; bindings) {
        changed |= rcfile.ResetKeybind(categoryName ~ key, codes);
      }
    }

    if(changed) {
      rcfile.ReconstructKeybinds();
    }
  }

  // for right click menu
  bool KeybindButtonPress(Event e, Widget w) {
    auto eb = e.button();

    if(eb.window != keybinds_.getBinWindow().getWindowStruct()) { // header is clicked
      return false;
    }
    if(eb.button != MouseButton.RIGHT) { // not right button
      return false;
    }

    grabFocus();

    TreePath path = GetPathAtPos(keybinds_, eb.x, eb.y);
    if(path is null) { // empty space is clicked
      return false;
    }
    TreeIter iter = GetIter(keyStore_, path);

    // show menu for "Clear" and "Add"
    auto menu = new KeybindMenu(keyStore_, iter);
    menu.popup(0, eb.time);

    return false;
  }

  class KeybindMenu : MenuWithMargin
  {
    TreeStore keyStore_;
    TreeIter iter_;

    this(TreeStore store, TreeIter iter) {
      keyStore_ = store;
      iter_ = iter;

      append(new MenuItem(&Clear, "_Clear this accelerator"));
      append(new MenuItem(&Add, "_Add new accelerator for this action"));

      showAll();
    }

    void Clear(MenuItem item) {
      keyStore_.setValue(iter_, 2, "");
    }

    void Add(MenuItem item) {
      TreeIter next = new TreeIter;
      keyStore_.insertAfter(next, null, iter_);
      keyStore_.setValue(next, 1, iter_.getValueString(1));
      keyStore_.setValue(next, 3, 1);// set editable
    }
  }
  ///////////////////// [Keybind]



  ///////////////////// [Terminal]
  Table pageTerminal_;
  FontButton fontButton_;
  ColorButton cbColorForeground_, cbColorBackground_;
  SpinButton sbTransparency_, sbScrollLinesOnKeyAction_;
  CheckButton cbEnablePathExpansion_;
  Entry entPROMPT_, entRPROMPT_, entReplaceTargetLeft_, entReplaceTargetRight_,
    entUserDefinedText1_, entUserDefinedText2_, entUserDefinedText3_, entUserDefinedText4_, entUserDefinedText5_,
    entUserDefinedText6_, entUserDefinedText7_, entUserDefinedText8_, entUserDefinedText9_;

  void InitTerminalPage() {
    pageTerminal_ = AppendWrappedTable(note_, "Terminal");

    uint row = 0;

    AttachSectionLabel(pageTerminal_, row++, "Appearance");
    fontButton_ = new FontButton(rcfile.GetFont());
    AttachPairWidget(pageTerminal_, row++, "Fo_nt used in terminals: ", fontButton_);

    mixin(AddColorButton!("Terminal", "ColorForeground", "_Foreground color: "));
    mixin(AddColorButton!("Terminal", "ColorBackground", "_Background color: "));

    mixin(AddSpinButton!("Terminal", "Transparency", "0.0, 1.0, 0.1", "_Transparency of background: "));

    AttachSectionLabel(pageTerminal_, row++, "Hints for Seta to extract command-line arguments");

    mixin(AddEntry!("Terminal", "PROMPT",  "\"_PROMPT regex pattern: \"", "PROMPT in shell"));
    mixin(AddEntry!("Terminal", "RPROMPT", "\"_RPROMPT regex patter: \"",
                    "RPROMPT in zsh, which is usually used to show additional information (e.g. working directory) on right side of terminal window"));

    AttachSectionLabel(pageTerminal_, row++, "Assist in inputting directory paths by substitution in command-line");
    mixin(AddCheckButton!("Terminal", "EnablePathExpansion", "_Enable this feature"));

    mixin(AddEntry!("Terminal", "ReplaceTargetLeft",  "\"Signature to be replaced with path (left): \"",
                    "In the case of $L<n>DIR, $LDIR will be replaced with pwd in left pane, $L1DIR with pwd in 1st tab in left pane and so on, when Enter or Tab is pressed."));
    mixin(AddEntry!("Terminal", "ReplaceTargetRight", "\"Signature to be replaced with path (right): \"",
                    "In the case of $R<n>DIR, $RDIR will be replaced with pwd in right pane, $R1DIR with pwd in 1st tab in right pane and so on, when Enter or Tab is pressed."));

    AttachSectionLabel(pageTerminal_, row++, "Scrolling");
    mixin(AddSpinButton!("Terminal", "ScrollLinesOnKeyAction", "0, 100, 1", "_Lines to scroll on pressing keyboard shortcut: "));

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

  void ApplyChangesInTerminal() {
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
    if(targetL.ContainsPattern("<n>")) {
      changed |= rcfile.ResetStringz("Terminal", "ReplaceTargetLeft" , targetL);
    } else {
      PopupBox.error(targetL ~ " is neglected since the signature for replace should contain \"<n>\".", "");
    }

    string targetR = entReplaceTargetRight_.getText();
    if(targetR.ContainsPattern("<n>")) {
      changed |= rcfile.ResetStringz("Terminal", "ReplaceTargetRight", targetR);
    } else {
      PopupBox.error(targetR ~ " is neglected since the signature for replace should contain \"<n>\".", "");
    }

    changed |= rcfile.ResetInteger("Terminal", "ScrollLinesOnKeyAction", cast(int)sbScrollLinesOnKeyAction_.getValue());

    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText1", entUserDefinedText1_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText2", entUserDefinedText2_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText3", entUserDefinedText3_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText4", entUserDefinedText4_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText5", entUserDefinedText5_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText6", entUserDefinedText6_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText7", entUserDefinedText7_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText8", entUserDefinedText8_.getText());
    changed |= rcfile.ResetStringz("Terminal", "UserDefinedText9", entUserDefinedText9_.getText());

    if(changed) {
      SetaWindow.NotifyTerminalsToApplyPreferences();
    }
  }
  ///////////////////// [Terminal]



  ///////////////////// common parts
  bool ShowAppendRemoveMenu(Event e, Widget w, TreeView view, ListStore store) {
    auto eb = e.button();
    if(eb.window != view.getBinWindow().getWindowStruct()) { // header is clicked
      return false;
    }
    if(eb.button != MouseButton.RIGHT) { // not right button
      return false;
    }

    auto iter = store.GetIter(GetPathAtPos(view, eb.x, eb.y));
    auto menu = new AppendRemoveMenu(view, store, iter);
    menu.popup(0, eb.time);
    return false;
  }

  class AppendRemoveMenu : MenuWithMargin
  {
    TreeView view_;
    ListStore store_;
    TreeIter iter_;

    this(TreeView view, ListStore store, TreeIter iter) {
      view_ = view;
      store_ = store;
      iter_ = iter;

      append(new MenuItem(&Append, "_Append"));
      if(iter !is null) {
        append(new MenuItem(&Remove, "_Remove"));
      }
      showAll();
    }

    void Append(MenuItem item) {
      TreeIter next = new TreeIter;
      if(iter_ is null) { // empty space is clicked
        store_.append(next);
      } else { // one row is clicked
        store_.insertAfter(next, iter_);
      }
      next.setModel(store_);
      TreePath path = next.getTreePath();
      view_.setCursor(path, null, 1);
    }

    void Remove(MenuItem item) {
      store_.remove(iter_);
    }
  }

  void CellEdited(int idx, string modelIdentifier, string transformFun = "")(string pathStr, string newName, CellRendererText rend) {
    ListStore model = mixin(modelIdentifier);
    TreeIter iter = GetIterFromString(model, pathStr);
    static if(transformFun.length == 0) {
      model.setValue(iter, idx, newName);
    } else {
      model.setValue(iter, idx, mixin(transformFun)(newName));
    }
  }
  ///////////////////// common parts


  void Respond(int responseID, Dialog dialog) {
    if(responseID == GtkResponseType.OK || responseID == GtkResponseType.APPLY) {
      ApplyChangesInKeybind();
      ApplyChangesInLayout();
      ApplyChangesInPages();
      ApplyChangesInTerminal();
      rcfile.Write();
    }
    if(responseID != GtkResponseType.APPLY) {
      destroy();
    }
  }
}



private template AddSpinButton(string group, string key, string args, string explanation) {
  const string AddSpinButton =
    "
    sb" ~ key ~ "_ = new SpinButton(" ~ args ~ ");
    sb" ~ key ~ "_.setValue(rcfile.Get" ~ key ~ "());
    AttachPairWidget(page" ~ group ~ "_, row++, \"" ~ explanation ~ "\", sb" ~ key ~ "_);
    ";
}
private template CheckSpinButton(string key) { // currently only for "Layout" group
  const string CheckSpinButton =
    "
    changed |= rcfile.ResetInteger(\"Layout\", \"" ~ key ~ "\", sb" ~ key ~ "_.getValueAsInt());
    ";
}

private template AddCheckButton(string group, string key, string explanation) {
  const string AddCheckButton =
    "
    cb" ~ key ~ "_ = new CheckButton(\"" ~ explanation ~ "\");
    cb" ~ key ~ "_.setActive(rcfile.Get" ~ key ~ "());
    page" ~ group ~ "_.attach(Alignment.west(cb" ~ key ~ "_), 0, 2, row, row+1,
                              GtkAttachOptions.FILL, cast(GtkAttachOptions)0, XPadding, YPadding);
    ++row;
    ";
}
private template CheckCheckButton(string group, string key) {
  const string CheckCheckButton =
    "
    changed |= rcfile.ResetBoolean(\"" ~ group ~ "\", \"" ~ key ~ "\", cb" ~ key ~ "_.getActive() != 0);
    ";
}

private template AddColorButton(string group, string key, string explanation) {
  const string AddColorButton =
    "
    {
      auto color = new Color;
      Color.parse(rcfile.Get" ~ key ~ "(), color);
      cb" ~ key ~ "_ = new ColorButton(color);
      AttachPairWidget(page" ~ group ~ "_, row++, \"" ~ explanation ~ "\", cb" ~ key ~ "_);
    }
    ";
}
private template CheckColorButton(string group, string key) {
  const string CheckColorButton =
    "
    {
      Color color = new Color;
      cb" ~ key ~ "_.getColor(color);
      changed |= rcfile.ResetStringz(\"" ~ group ~ "\", \"" ~ key ~ "\", color.toString());
    }
    ";
}

private template AddEntry(string group, string key, string explanation, string tooltip = "") {
  const string AddEntry =
    "
    ent" ~ key ~ "_ = new Entry(NonnullString(rcfile.Get" ~ key ~ "()));
    AttachPairWidget(page" ~ group ~ "_, row++, " ~ explanation ~ ", ent" ~ key ~ "_, \"" ~ tooltip ~ "\");
    ";
}

private Table AppendWrappedTable(Notebook note, string title) {
  Table t = new Table(1, 2, 0);
  auto win = new ScrolledWindow(GtkPolicyType.AUTOMATIC, GtkPolicyType.AUTOMATIC);
  win.addWithViewport(t); // Table needs Viewport
  note.appendPage(win, title);
  return t;
}

private void AppendWithScrolledWindow(Table t, uint row, Widget w) {
  auto sw = new ScrolledWindow(GtkPolicyType.NEVER, GtkPolicyType.AUTOMATIC);
  sw.add(w); // widget is assumed to support scrolling by itself, not with Viewport
  t.attach(sw, 0, 2, row, row+1, GtkAttachOptions.FILL | GtkAttachOptions.EXPAND, GtkAttachOptions.FILL, XPadding, YPadding);
}

private void AttachPairWidget(Table t, uint row, string labelText, Widget w, string tooltip = "") {
  Label l = new Label(labelText);
  if(tooltip.length > 0) {
    l.setTooltipText(tooltip);
    w.setTooltipText(tooltip);
  }
  l.setMnemonicWidget(w);
  l.setAlignment(0.0, 0.5); // left-align labels
  t.attach(l, 0, 1, row, row+1, GtkAttachOptions.FILL,   cast(GtkAttachOptions)0, XPadding, YPadding);
  t.attach(w, 1, 2, row, row+1, GtkAttachOptions.FILL | GtkAttachOptions.EXPAND, cast(GtkAttachOptions)0, XPadding, YPadding);
}

private void AttachSectionLabel(Table t, uint row, string text) {
  if(row > 0) { // append additional space between sections
    t.setRowSpacing(row-1, 15);
  }

  auto l = new Label("<b>" ~ text ~ "</b>"); // bold text
  l.setUseMarkup(1);
  l.setAlignment(0.0, 1.0);
  t.attach(l, 0, 2, row, row+1, GtkAttachOptions.FILL, GtkAttachOptions.FILL, 10, 5);
}

// constants to align widgets in Table
private immutable int XPadding = 20;
private immutable int YPadding = 3;
