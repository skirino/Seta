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

module fm.rename_dialog;

import gtk.Dialog;
import gtk.Button;
import gtk.Entry;
import gtk.EditableIF;
import gtk.Label;
import gtk.Table;
import gtk.VBox;
import gtk.HBox;
import gtk.Widget;
import gtk.TreeView;
import gtk.TreeIter;
import gtk.TreePath;
import gtk.TreeModelIF;
import gtk.ListStore;
import gtk.TreeViewColumn;
import gtk.CellRenderer;
import gtk.CellRendererText;
import gtk.ScrolledWindow;
import gtk.Tooltip;
import gtk.PopupBox;
import gtk.HSeparator;
import gtk.ComboBoxText;
import gdk.Event;
import gio.File;
import glib.GException;
import glib.Str;
import glib.Regex;
import gobject.Signals;
import pango.PgAttribute;
import pango.PgAttributeList;

import utils.string_util;
import utils.tree_util;
import input_dialog;
import statusbar;


void RenameFiles(string dir, string[] infiles)
{
  string[] files;

  if(dir.containsPattern("/.gvfs/sftp")){// remote
    // try renaming all files since "access::can-rename" is not accurate for remote files
    files = infiles;
  }
  else{
    // fileter by "access::can-rename"
    foreach(file; infiles){
      File f = File.parseName(dir ~ file);
      scope info = f.queryInfo("access::can-rename", GFileQueryInfoFlags.NONE, null);
      if(info.getAttributeBoolean("access::can-rename")){
        files ~= file;
      }
    }

    if(files.length == 0){// nothing to be renamed
      PopupBox.error("Cannot rename: Permission denied", "error");
      return;
    }
  }

  // fire up dialog
  scope d = new RenameDialog(files);
  d.run();

  // now dialog is destroyed
  string[] newnames = d.ret_;
  uint num = 0;
  if(newnames !is null && newnames.length == files.length){// do rename
    bool askOverwrite = true;
    foreach(i, file; files){
      string newname = newnames[i];
      if(newname.length > 0 && file != newname){// new name is not null

        // check whether "newname" contains slash or not
        if(file[$-1] == '/'){// directory
          if(newname[0 .. $-1].contains('/')){// && has slash
            PopupBox.error("Cannot rename " ~ file ~ " to " ~ newname, "error");
            continue;
          }
        }
        else{// file
          if(newname.contains('/')){
            PopupBox.error("Cannot rename " ~ file ~ " to " ~ newname, "error");
            continue;
          }
        }

        // now "newname" is free from slash-issue
        File dest = File.parseName(dir ~ newname);

        // check for overwriting existing file
        if(askOverwrite && dest.queryExists(null) != 0){// exists
          string message = newname ~ " exists. Overwrite?";
          int x;

          if(files.length - i == 1){// only one file to rename
            x = ChooseDialog!(2)(message, ["_OK", "_Cancel"]);
          }
          else{// there are still more than one files to rename
            x = ChooseDialog!(4)(message, ["_OK", "_Skip this file", "Overwrite _all", "_Cancel all"]);
          }

          if(x == 3){// "cancel all"
            break;
          }
          else if(x == 2){// "overwrite all"
            askOverwrite = false;
          }
          else if(x == -1 || x == 1){// invalid, "cancel"
            continue;
          }
        }

        // does not exist || (exists && ("OK" || "overwrite all"))
        try{
          File src  = File.parseName(dir ~ file);
          src.move(dest, GFileCopyFlags.OVERWRITE, null, null, null);
          ++num;
        }
        catch(GException ex){
          int x = ChooseDialog!(2)(ex.msg, ["_Skip this file", "_Cancel all"]);
          if(x == -1 || x == 1){
            break;
          }
        }
      }
    }
  }

  // notify statusbar
  if(num == 0){
    PushIntoStatusbar("Rename was canceled");
  }
  else{
    PushIntoStatusbar(PluralForm!(uint, "item was", "items were")(num) ~ " renamed");
  }
}


// local variables to store Dialog's state
int idxComboBox = 0;
private string searchFor, replaceWith, prependText, appendText;


private class RenameDialog : Dialog
{
  string[] ret_;
  Widget ok_, cancel_;
  TreeView view_;
  ListStore store_;
  TreeViewColumn colOld_, colNew_;
  CellRendererText renderer_;
  ComboBoxText comboBox_;
  Label lold_, lnew_, lpre_, lapp_, lerr_;
  Entry eold_, enew_, epre_, eapp_;

  this(string[] files)
  {
    super();
    setTitle("Rename " ~ PluralForm!(size_t, "file")(files.length));
    setDefaultSize(430, 450);
    addOnResponse(&Respond);
    auto contentArea = getContentArea();

    cancel_ = addButton("_Cancel", GtkResponseType.CANCEL);
    ok_     = addButton("_Rename", GtkResponseType.OK);

    // setup TreeView
    auto win = new ScrolledWindow(GtkPolicyType.AUTOMATIC, GtkPolicyType.AUTOMATIC);
    contentArea.packStart(win, 1, 1, 5);
    view_ = new TreeView();
    win.add(view_);
    view_.setRulesHint(1);// alternating row colors
    view_.setHasTooltip(1);
    view_.addOnQueryTooltip(&QueryTooltip);

    store_ = new ListStore([GType.STRING, GType.STRING]);
    view_.setModel(store_);

    // setup columns
    colOld_ = new TreeViewColumn("Name", new CellRendererText, "text", 0);
    renderer_ = new CellRendererText;
    renderer_.setProperty("editable", 1);
    renderer_.addOnEdited(&EditedNewName);
    // connect callback to update contents of the editable cell when focus-out
    Signals.connectData(renderer_.getCellRendererTextStruct(), "editing-started",
                        cast(GCallback)(&EditingStarted), cast(void*)this, null, GConnectFlags.AFTER);

    colNew_ = new TreeViewColumn("New Name", renderer_, "text", 1);
    colOld_.setSizing(GtkTreeViewColumnSizing.FIXED);
    colNew_.setSizing(GtkTreeViewColumnSizing.FIXED);
    colOld_.setMinWidth(200);
    colNew_.setMinWidth(200);
    colOld_.setResizable(1);
    colNew_.setResizable(1);

    view_.appendColumn(colOld_);
    view_.appendColumn(colNew_);

    // insert rows to TreeView
    TreeIter iter = new TreeIter;
    foreach(file; files){
      store_.append(iter);
      store_.setValue(iter, 0, file);
    }

    contentArea.packStart(new HSeparator, 0, 0, 0);

    // setup ComboBox (all, first, last) for search & replace
    HBox hbox = new HBox(0, 10);
    contentArea.packStart(hbox, 0, 0, 0);

    comboBox_ = new ComboBoxText();
    comboBox_.appendText("All Matches");
    comboBox_.appendText("First Match");
    comboBox_.appendText("Last Match");
    comboBox_.appendText("Regular Expression");
    comboBox_.setActive(idxComboBox);
    comboBox_.addOnChanged(&EntriesChanged!(ComboBoxText));
    hbox.packStart(comboBox_, 0, 0, 0);

    lerr_ = new Label("");
    lerr_.setEllipsize(PangoEllipsizeMode.END);
    auto attrs = new PgAttributeList;
    attrs.insert(PgAttribute.foregroundNew(65535, 0, 0));
    lerr_.setAttributes(attrs);
    hbox.packEnd(lerr_, 1, 1, 10);

    // setup Entries for search & replace
    lold_ = new Label("_Search For: ");
    lnew_ = new Label("Replace _With: ");
    eold_ = new Entry(searchFor   is null ? "" : searchFor);
    enew_ = new Entry(replaceWith is null ? "" : replaceWith);
    lold_.setMnemonicWidget(eold_);
    lnew_.setMnemonicWidget(enew_);
    eold_.addOnChanged(&EntriesChanged!(EditableIF));
    enew_.addOnChanged(&EntriesChanged!(EditableIF));

    // setup Entries for prepend & append
    lpre_ = new Label("_Prepend Text: ");
    lapp_ = new Label("_Append Text: ");
    epre_ = new Entry(prependText is null ? "" : prependText);
    eapp_ = new Entry(appendText  is null ? "" : appendText);
    lpre_.setMnemonicWidget(epre_);
    lapp_.setMnemonicWidget(eapp_);
    epre_.addOnChanged(&EntriesChanged!(EditableIF));
    eapp_.addOnChanged(&EntriesChanged!(EditableIF));
    EntriesChanged!(Button)(null);

    auto table = new Table(2, 2, 0);
    table.attachDefaults(lold_, 0, 1, 0, 1);
    table.attachDefaults(eold_, 1, 2, 0, 1);
    table.attachDefaults(lnew_, 0, 1, 1, 2);
    table.attachDefaults(enew_, 1, 2, 1, 2);
    contentArea.packStart(table, 0, 0, 5);

    contentArea.packStart(new HSeparator, 0, 0, 0);

    table = new Table(2, 2, 0);
    table.attachDefaults(lpre_, 0, 1, 0, 1);
    table.attachDefaults(epre_, 1, 2, 0, 1);
    table.attachDefaults(lapp_, 0, 1, 1, 2);
    table.attachDefaults(eapp_, 1, 2, 1, 2);
    contentArea.packStart(table, 0, 0, 5);

    // set initial focus
    showAll();
    if(files.length == 1){// only one file
      TreeIter iter1st = GetIterFirst(store_);
      TreePath path = iter1st.getTreePath();
      view_.setCursor(path, colNew_, 1);// start editing
      path.free();
    }
    else{// multiple files
      eold_.grabFocus();
    }
  }

  void Respond(int responseID, Dialog dialog)
  {
    if(responseID == GtkResponseType.OK){
      TreeIter iter = GetIterFirst(store_);
      do{
        ret_ ~= iter.getValueString(1);
      }
      while(store_.iterNext(iter));
    }
    else{
      ret_ = null;
    }

    // restore dialog's state
    idxComboBox = comboBox_.getActive();
    searchFor   = eold_.getText();
    replaceWith = enew_.getText();
    prependText = epre_.getText();
    appendText  = eapp_.getText();

    destroy();
  }



  //////////////////// search & replace, then prepend & append
  void SetErrorLabel(string message)
  {
    lerr_.setText(message);//"<span foreground=\"red\"> " ~ message ~ " </span>");
    lerr_.setTooltipText(message);

    if(message.IsBlank()){
      ok_.setSensitive(1);
    }
    else{// there is something wrong, forbid to rename
      ok_.setSensitive(0);
    }
  }

  void EntriesChanged(ArgType)(ArgType arg)
  {
    // clear error message
    SetErrorLabel("");

    map_.textSearch_  = eold_.getText();
    map_.textReplace_ = enew_.getText();
    map_.textPre_ = epre_.getText();
    map_.textApp_ = eapp_.getText();

    // check slash
    if(map_.textSearch_.contains('/') ||
       map_.textReplace_.contains('/') ||
       map_.textPre_.contains('/') ||
       map_.textApp_.contains('/')){
      SetErrorLabel("Cannot rename: slashes are not supported");
      return;
    }

    if(map_.textSearch_.length == 0){// no search & replace
      RenameForeach!(Default)();
      return;
    }

    int target = comboBox_.getActive();// 0: all, 1: first, 2: last, 3: regexp

    if(target == 3){// regexp
      try{// check whether the input texts are valid
        map_.re_ = new Regex(map_.textSearch_, cast(GRegexCompileFlags)0, cast(GRegexMatchFlags)0);
      }
      catch(GException ex){// failed to compile regexp, e.g. just after inputting '('
        SetErrorLabel(ex.msg);
        return;
      }

      if(map_.textReplace_.length == 0){// remove all matches
        RenameForeach!(RemoveRegexp)();
      }
      else{
        try{// check replace string
          int x;
          Regex.checkReplacement(map_.textReplace_, x);
        }
        catch(GException ex){
          SetErrorLabel(ex.msg);
          return;
        }
        RenameForeach!(ReplaceRegexp)();
      }
    }
    else if(target == 0){// all
      RenameForeach!(ReplaceStringAll)();
    }
    else if(target == 1){// first
      RenameForeach!(ReplaceStringFirst)();
    }
    else{// last
      RenameForeach!(ReplaceStringLast)();
    }
  }

  enum{
    ReplaceRegexp,
    RemoveRegexp,
    ReplaceStringAll,
    ReplaceStringFirst,
    ReplaceStringLast,
    Default
  }

  void RenameForeach(int ReplaceType)()
  {
    TreeIter iter = GetIterFirst(store_);
    do{
      store_.setValue(iter, 1, map_.Do!(ReplaceType)(iter.getValueString(0)));
    }
    while(store_.iterNext(iter));
  }

  MapNewName map_;
  struct MapNewName
  {
    string textSearch_, textReplace_, textPre_, textApp_;
    Regex re_;

    string Do(int ReplaceType)(string oldname)
    {
      if(oldname[$-1] == '/'){// directory
        return textPre_ ~ SearchReplace!(ReplaceType)(oldname[0 .. $-1]) ~ textApp_ ~ '/';
      }
      else{// file
        return textPre_ ~ SearchReplace!(ReplaceType)(oldname) ~ textApp_;
      }
    }

    string SearchReplace(int ReplaceType)(string name)
    {
      static if(ReplaceType == ReplaceRegexp){
        return re_.replace(name, name.length, 0, textReplace_, cast(GRegexMatchFlags)0);
      }
      else if(ReplaceType == RemoveRegexp){
        // take split-join approach since there seems to be no direct way to remove matches in glib.Regex
        string[] l = re_.split(name, cast(GRegexMatchFlags)0);
        string ret;
        foreach(s; l){
          ret ~= s;
        }
        return ret;
      }
      else if(ReplaceType == ReplaceStringAll){
        return substitute(name, textSearch_, textReplace_).idup;
      }
      else if(ReplaceType == ReplaceStringFirst ||
              ReplaceType == ReplaceStringLast){
        static if(ReplaceType == ReplaceStringFirst){
          size_t idx = locatePattern(name, textSearch_);
        }
        else{// ReplaceStringLast
          size_t idx = locatePatternPrior(name, textSearch_);
        }

        if(idx == name.length){// no match
          return name;
        }
        else{
          return name[0 .. idx] ~ textReplace_ ~ name[idx+textSearch_.length .. $];
        }
      }
      else{// do not replace
        return name;
      }
    }
  }
  //////////////////// search & replace, then prepend & append



  //////////////////// tooltip for long contents
  bool QueryTooltip(int x, int y, int keyboardTip, Tooltip tip, Widget w)
  {
    // obtain the cell where the mouse cursor is
    TreePath path;
    TreeIter iter = new TreeIter;
    iter.setModel(store_);
    if(GetTooltipContext(view_, &x, &y, keyboardTip, path, iter)){
      if(path !is null){
        TreeViewColumn col = GetColAtPos(view_, x, y);

        int colIndex = col is colOld_ ? 0 : 1;
        string text = iter.getValueString(colIndex);
        CellRenderer renderer = GetCellRendererFromCol(col);

        // check whether the text is ellipsized or not
        int startPos, actualWidth;
        col.cellGetPosition(renderer, startPos, actualWidth);
        int textWidth = GetTextWidth(text);

        if(actualWidth < textWidth){// text is too long
          tip.setText(text);
          view_.setTooltipCell(tip, path, col, renderer);
          path.free();
          return true;
        }

        path.free();
      }
    }

    return false;
  }
  //////////////////// tooltip for long contents



  ///////////////////// editable cell
  void EditedNewName(string pathString, string newName, CellRendererText renderer)
  {
    if(newName.length > 0){// valid input
      // update store
      TreeIter iter = GetIterFromString(store_, pathString);

      // check whether the entry is a directory or not
      string name = iter.getValueString(0);
      if(name[$-1] == '/'){
        newName = AppendSlash(newName);
        if(!newName[0 .. $-1].contains('/')){
          store_.setValue(iter, 1, newName);
        }
      }
      else{
        newName = RemoveSlash(newName);
        if(!newName.contains('/')){
          store_.setValue(iter, 1, newName);
        }
      }
    }
  }

  void EditingCellActivate(Entry e)
  {
    ok_.grabFocus();
  }

  // to ensure that the cell contents is modified on focus-out
  string pathStringLast_;
  bool FocusOut(Event e, Widget w)
  {
    Entry ent = cast(Entry)w;
    // this can cause "EditedNewName" to be called twice (here and by "edited" signal), but no problem
    EditedNewName(pathStringLast_, ent.getText(), renderer_);
    return false;
  }

  // due to difficulties related to the GtkD interfaces,
  // the easiest way is to use C API
  extern(C) static void EditingStarted(GtkCellRenderer *renderer,
                                       GtkCellEditable *editable,
                                       gchar           *path,
                                       gpointer         user_data)
  {
    RenameDialog d = cast(RenameDialog)user_data;
    d.pathStringLast_ = Str.toString(path);
    Entry ent = new Entry(cast(GtkEntry*)editable);
    ent.addOnFocusOut(&(d.FocusOut));// update "store_"
    ent.addOnActivate(&(d.EditingCellActivate));// move focus to "Rename" button
  }
  ///////////////////// editable cell
}

