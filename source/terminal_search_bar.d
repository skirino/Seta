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

module terminal_search_bar;

import gtk.Dialog;
import gtk.Widget;
import gtk.Label;
import gtk.HBox;
import gtk.ComboBoxText;
import gtk.Button;
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

class TerminalSearchBar : HBox
{
private:
  Terminal     terminal_;
  ComboBoxText cb_;
  Label        reErrorLabel_;
  Button       searchForwardButton_;
  Button       searchBackwardButton_;
  CheckButton  ignoreCases_;
  Regex        re_;

public:
  this(Terminal terminal) {
    terminal_ = terminal;
    super(0, 0);
    addOnKeyPress(&KeyPressed);

    auto l = new Label("_Search for: ");
    packStart(l, 0, 0, 5);

    cb_ = new ComboBoxText;
    cb_.addOnChanged(&SearchTextChanged!(ComboBoxText));
    packStart(cb_, 0, 0, 0);
    l.setMnemonicWidget(cb_);

    ignoreCases_ = new CheckButton("_Ignore cases");
    ignoreCases_.addOnToggled(&SearchTextChanged!(ToggleButton));
    packStart(ignoreCases_, 0, 0, 0);

    searchBackwardButton_ = new Button(StockID.MEDIA_PREVIOUS);
    searchForwardButton_  = new Button(StockID.MEDIA_NEXT    );
    searchBackwardButton_.addOnClicked(&SearchFromButton!(Order.BACKWARD));
    searchForwardButton_ .addOnClicked(&SearchFromButton!(Order.FORWARD ));
    packStart(searchBackwardButton_, false, false, 0);
    packStart(searchForwardButton_ , false, false, 0);

    reErrorLabel_ = new Label("");
    reErrorLabel_.setEllipsize(PangoEllipsizeMode.END);
    auto attrs = new PgAttributeList;
    attrs.insert(PgAttribute.foregroundNew(65535, 0, 0));
    reErrorLabel_.setAttributes(attrs);
    packStart(reErrorLabel_, false, false, 0);

    auto closeButton = new Button(StockID.CLOSE);
    closeButton.addOnClicked(&Hide);
    packEnd(closeButton, false, false, 0);
  }

  void Show() {
    show();
    cb_.grabFocus();
  }

private:
  void Hide() {
    hide();
    terminal_.grabFocus();
  }
  void Hide(Button b) { Hide(); }

  bool KeyPressed(Event e, Widget w) {
    auto ekey = e.key();
    auto state = TurnOffLockFlags(ekey.state);
    if(state == 0 && ekey.keyval == GdkKeysyms.GDK_Return) {
      Search!(Order.FORWARD)();
      return true;
    }
    if(state == GdkModifierType.SHIFT_MASK && ekey.keyval == GdkKeysyms.GDK_Return) {
      Search!(Order.BACKWARD)();
      return true;
    }
    if(ekey.keyval == GdkKeysyms.GDK_Escape) {
      Hide();
      return true;
    }
    return false;
  }

  void Search(Order o)() {
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
  void SearchFromButton(Order o)(Button b) {
    Search!(o);
  }

  void SearchTextChanged(T)(T t) {
    BuildRegexp();
    bool sensitive = re_ !is null;
    searchForwardButton_ .setSensitive(sensitive);
    searchBackwardButton_.setSensitive(sensitive);
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
}
