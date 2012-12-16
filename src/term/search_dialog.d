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

module term.search_dialog;

import gtk.Dialog;
import gtk.Widget;
import gtk.Label;
import gtk.VBox;
import gtk.HBox;
import gtk.Entry;
import gtk.EditableIF;
import gtk.ComboBox;
import gtk.ComboBoxEntry;
import gtk.CheckButton;
import gtk.ToggleButton;
import gdk.Keysyms;
import glib.Regex;
import glib.GException;
import pango.PgAttribute;
import pango.PgAttributeList;

import utils.string_util;
import config.keybind;
import terminal;


void StartTerminalSearch(Terminal terminal)
{
  auto d = new TerminalSearchDialog(terminal);
  d.showAll();
  d.run();
}


private class TerminalSearchDialog : Dialog
{
private:
  immutable int RESPONSE_ID_SEARCH = 1;

  Terminal terminal_;
  Regex re_;
  Entry e_;
  ComboBoxEntry cb_;
  Label reErrorLabel_;
  Widget searchButton_;
  CheckButton ignoreCases_;
  CheckButton backwardDirection_;
  CheckButton overwrappedSearch_;

public:
  this(Terminal terminal)
  {
    terminal_ = terminal;
    super();
    addOnResponse(&Respond);
    addOnKeyPress(&KeyPressed);
    VBox contentArea = getContentArea();

    auto hbox = new HBox(0, 0);
    auto l = new Label("_Search for: ");
    hbox.packStart(l, 0, 0, 5);

    cb_ = new ComboBoxEntry;
    cb_.addOnChanged(&SearchTextChanged!(ComboBox));
    hbox.packStart(cb_, 0, 0, 0);
    l.setMnemonicWidget(cb_);
    contentArea.packStart(hbox, 0, 0, 5);

    reErrorLabel_ = new Label("");
    reErrorLabel_.setEllipsize(PangoEllipsizeMode.END);
    auto attrs = new PgAttributeList;
    attrs.insert(PgAttribute.foregroundNew(65535, 0, 0));
    reErrorLabel_.setAttributes(attrs);
    contentArea.packStart(reErrorLabel_, 0, 0, 0);

    ignoreCases_ = new CheckButton("_Ignore cases");
    ignoreCases_.addOnToggled(&SearchTextChanged!(ToggleButton));
    contentArea.packStart(ignoreCases_, 0, 0, 0);

    backwardDirection_ = new CheckButton("_Backward search");
    contentArea.packStart(backwardDirection_, 0, 0, 0);

    overwrappedSearch_ = new CheckButton("_Overwrapped search");
    contentArea.packStart(overwrappedSearch_, 0, 0, 0);

    addButton(StockID.CLOSE, GtkResponseType.GTK_RESPONSE_DELETE_EVENT);
    searchButton_ = addButton(StockID.FIND, RESPONSE_ID_SEARCH);

    ApplySettings();
  }

private:
  bool KeyPressed(GdkEventKey * ekey, Widget w)
  {
    if(TurnOffLockFlags(ekey.state) == 0 && ekey.keyval == GdkKeysyms.GDK_Return){
      Search();
      return true;
    }
    return false;
  }

  void Respond(int responseID, Dialog dialog)
  {
    if(responseID == GtkResponseType.GTK_RESPONSE_DELETE_EVENT){
      RestoreSettings();
      destroy();
    }
    else if(responseID == RESPONSE_ID_SEARCH){
      Search();
    }
  }

  void Search()
  {
    if(re_ is null){
      return;
    }

    terminal_.SetOverwrappedSearch(overwrappedSearch_.getActive());
    if(backwardDirection_.getActive()){
      terminal_.SearchPrevious();
    }
    else{
      terminal_.SearchNext();
    }

    // prepend or reorder the search text
    cb_.prependOrReplaceText(cb_.getActiveText());
  }

  void SearchTextChanged(T)(T t)
  {
    BuildRegexp();
    if(re_ is null){
      searchButton_.setSensitive(0);
    }
    else{
      searchButton_.setSensitive(1);
    }
  }

  void BuildRegexp()
  {
    if(re_ !is null){
      re_.unref();
    }

    auto text = cb_.getActiveText();
    if(IsBlank(text)){
      re_ = null;
      reErrorLabel_.setText("");
      reErrorLabel_.setTooltipText("");
      return;
    }

    try{
      auto compileFlags =
        (ignoreCases_.getActive() == 0) ? GRegexCompileFlags.MULTILINE :
                                          GRegexCompileFlags.MULTILINE | GRegexCompileFlags.CASELESS;
      re_ = new Regex(text, compileFlags, cast(GRegexMatchFlags)0);
      terminal_.SetSearchRegexp(re_);
      reErrorLabel_.setText("");
      reErrorLabel_.setTooltipText("");
    }
    catch(GException ex){
      re_ = null;
      reErrorLabel_.setText(ex.msg);
      reErrorLabel_.setTooltipText(ex.msg);
    }
  }



  //////////////// remember settings used at last time
  static __gshared string[] searchTextHistory = [];
  static __gshared int ignoreCases       = 1;
  static __gshared int backwardDirection = 0;
  static __gshared int overwrappedSearch = 1;

  void ApplySettings()
  {
    foreach(text; searchTextHistory){
      cb_.appendText(text);
    }
    cb_.setActive(0);

    ignoreCases_.setActive(ignoreCases);
    backwardDirection_.setActive(backwardDirection);
    overwrappedSearch_.setActive(overwrappedSearch);
  }

  void RestoreSettings()
  {
    searchTextHistory = [];

    // append text until it returns the same text twice
    string previous;
    int index = 0;
    while(true){
      cb_.setActive(index);
      string text = cb_.getActiveText();
      if(text == previous){
        break;
      }
      searchTextHistory ~= text;
      previous = text;
      ++index;
    }

    ignoreCases = ignoreCases_.getActive();
    backwardDirection = backwardDirection_.getActive();
    overwrappedSearch = overwrappedSearch_.getActive();
  }
}

