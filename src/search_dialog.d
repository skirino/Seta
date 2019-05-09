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

module search_dialog;

import gtk.Dialog;
import gtk.Widget;
import gtk.Label;
import gtk.HBox;
import gtk.Entry;
import gtk.ComboBoxText;
import gtk.CheckButton;
import gtk.ToggleButton;
import gdk.Keysyms;
import gdk.Event;
import glib.GException;
import pango.PgAttribute;
import pango.PgAttributeList;
import vte.Regex;

import constants;
import utils.ref_util;
import utils.string_util;
import config.keybind;
import terminal;

void StartTerminalSearch(Terminal terminal) {
  auto d = new TerminalSearchDialog(terminal);
  d.showAll();
  d.run();
}

private class TerminalSearchDialog : Dialog
{
private:
  enum ResponseID
  {
    SEARCH_FORWARD  = 1,
    SEARCH_BACKWARD = 2,
  }

  Nonnull!Terminal     terminal_;
  Nonnull!ComboBoxText cb_;
  Nonnull!Label        reErrorLabel_;
  Nonnull!Widget       searchForwardButton_;
  Nonnull!Widget       searchBackwardButton_;
  Nonnull!CheckButton  ignoreCases_;
  Regex re_;

public:
  this(Terminal terminal) {
    terminal_.init(terminal);
    super();
    setResizable(false);
    addOnResponse(&Respond);
    addOnKeyPress(&KeyPressed);
    addOnFocusOut(&FocusOut);
    auto contentArea = getContentArea();

    auto hbox = new HBox(0, 0);
    auto l = new Label("_Search for: ");
    hbox.packStart(l, 0, 0, 5);

    cb_.init(new ComboBoxText);
    cb_.addOnChanged(&SearchTextChanged!(ComboBoxText));
    hbox.packStart(cb_, 0, 0, 0);
    l.setMnemonicWidget(cb_);
    contentArea.packStart(hbox, 0, 0, 5);

    reErrorLabel_.init(new Label(""));
    reErrorLabel_.setEllipsize(PangoEllipsizeMode.END);
    auto attrs = new PgAttributeList;
    attrs.insert(PgAttribute.foregroundNew(65535, 0, 0));
    reErrorLabel_.setAttributes(attrs);
    contentArea.packStart(reErrorLabel_, 0, 0, 0);

    ignoreCases_.init(new CheckButton("_Ignore cases"));
    ignoreCases_.addOnToggled(&SearchTextChanged!(ToggleButton));
    contentArea.packStart(ignoreCases_, 0, 0, 0);

    addButton(StockID.CLOSE, GtkResponseType.DELETE_EVENT);
    searchBackwardButton_.init(addButton(StockID.MEDIA_PREVIOUS, ResponseID.SEARCH_BACKWARD));
    searchForwardButton_ .init(addButton(StockID.MEDIA_NEXT    , ResponseID.SEARCH_FORWARD ));

    ApplySettings();
  }

private:
  bool KeyPressed(Event e, Widget w) {
    auto ekey = e.key();
    auto state = TurnOffLockFlags(ekey.state);
    if(state == 0 && ekey.keyval == GdkKeysyms.GDK_Return) {
      Search();
      return true;
    }
    if(state == GdkModifierType.SHIFT_MASK && ekey.keyval == GdkKeysyms.GDK_Return) {
      Search!(Order.BACKWARD)();
      return true;
    }
    return false;
  }

  void Respond(int responseID, Dialog dialog) {
    if(responseID == GtkResponseType.DELETE_EVENT) {
      RestoreSettings();
      destroy();
    } else if(responseID == ResponseID.SEARCH_FORWARD) {
      Search();
    } else if(responseID == ResponseID.SEARCH_BACKWARD) {
      Search!(Order.BACKWARD)();
    }
  }

  bool FocusOut(Event e, Widget w) {
    RestoreSettings();
    destroy();
    return false;
  }

  void Search(Order o = Order.FORWARD)() {
    if(re_ is null) {
      return;
    }
    static if(o == Order.FORWARD) {
      terminal_.searchFindNext();
    } else {
      terminal_.searchFindPrevious();
    }
    // prepend or reorder the search text
    cb_.prependOrReplaceText(cb_.getActiveText());
  }

  void SearchTextChanged(T)(T t) {
    BuildRegexp();
    if(re_ is null) {
      searchForwardButton_ .setSensitive(0);
      searchBackwardButton_.setSensitive(0);
    } else {
      searchForwardButton_ .setSensitive(1);
      searchBackwardButton_.setSensitive(1);
    }
  }

  void BuildRegexp() {
    auto text = cb_.getActiveText();
    if(text.empty()) {
      re_ = null;
      reErrorLabel_.setText("");
      reErrorLabel_.setTooltipText("");
      return;
    }

    try {
      re_ = MakeVteRegex(text, ignoreCases_.getActive() != 0);
      reErrorLabel_.setText("");
      reErrorLabel_.setTooltipText("");
      terminal_.searchSetRegex(re_, 0);
    } catch(GException ex) {
      re_ = null;
      reErrorLabel_.setText(ex.msg);
      reErrorLabel_.setTooltipText(ex.msg);
    }
  }

  Regex MakeVteRegex(string text, bool ignoreCase) {
    auto PCRE2_CASELESS  = 0x00000008u;
    auto PCRE2_MULTILINE = 0x00000400u;
    auto compileFlags = ignoreCase ? (PCRE2_MULTILINE | PCRE2_CASELESS) : PCRE2_MULTILINE;
    return Regex.newSearch(text, -1, compileFlags);
  }



  //////////////// remember settings used at last time
  static __gshared string[] searchTextHistory = [];
  static __gshared bool ignoreCases = true;

  void ApplySettings() {
    foreach(text; searchTextHistory) {
      cb_.appendText(text);
    }
    cb_.setActive(0);
    ignoreCases_.setActive(ignoreCases);
  }

  void RestoreSettings() {
    searchTextHistory = [];

    // append text until it returns the same text twice
    string previous;
    int index = 0;
    while(true) {
      cb_.setActive(index);
      string text = cb_.getActiveText();
      if(text == previous) {
        break;
      }
      searchTextHistory ~= text;
      previous = text;
      ++index;
    }
    ignoreCases = ignoreCases_.getActive();
  }
}