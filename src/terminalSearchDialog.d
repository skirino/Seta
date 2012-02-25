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

module terminalSearchDialog;

private import gtk.Dialog;
private import gtk.Widget;
private import gtk.Label;
private import gtk.VBox;
private import gtk.HBox;
private import gtk.Entry;
private import gtk.EditableIF;
private import gtk.ComboBox;
private import gtk.ComboBoxEntry;
private import gtk.CheckButton;
private import gdk.Keysyms;
private import glib.Regex;
private import glib.GException;

private import tango.io.Stdout;

private import utils.stringUtil;
private import config.keybind;
private import terminal;


void StartTerminalSearch(Terminal terminal)
{
  scope d = new TerminalSearchDialog(terminal);
  d.showAll();
  d.run();
}


private class TerminalSearchDialog : Dialog
{
private:
  Terminal terminal_;
  Regex re_;
  Entry e_;
  ComboBoxEntry cb_;
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
    cb_.addOnChanged(&SearchTextChanged);
    hbox.packStart(cb_, 0, 0, 0);
    l.setMnemonicWidget(cb_);
    contentArea.packStart(hbox, 0, 0, 5);
    
    ignoreCases_ = new CheckButton("_Ignore cases");
    contentArea.packStart(ignoreCases_, 0, 0, 0);
    
    backwardDirection_ = new CheckButton("_Backward search");
    contentArea.packStart(backwardDirection_, 0, 0, 0);
    
    overwrappedSearch_ = new CheckButton("_Overwrapped search");
    contentArea.packStart(overwrappedSearch_, 0, 0, 0);
    
    addButton(StockID.CLOSE, GtkResponseType.GTK_RESPONSE_DELETE_EVENT);
    searchButton_ = addButton(StockID.FIND,  1);
    
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
    else if(responseID == 1){
      Search();
    }
  }
  
  void Search()
  {
    terminal_.SetOverwrappedSearch(overwrappedSearch_.getActive());
    
    if(backwardDirection_.getActive() == 0){
      terminal_.SearchNext();
    }
    else{
      terminal_.SearchPrevious();
    }
    
    // prepend or reorder the search text
    cb_.prependOrReplaceText(cb_.getActiveText());
  }
  
  void SearchTextChanged(ComboBox cb)
  {
    BuildRegexp();
    if(re_ is null){
      searchButton_.setSensitive(0);
    }
    else{
      searchButton_.setSensitive(1);
      terminal_.SetSearchRegexp(re_);
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
      return;
    }
    
    try{
      auto compileFlags =
        (ignoreCases_.getActive() == 0) ? GRegexCompileFlags.MULTILINE :
                                          GRegexCompileFlags.MULTILINE | GRegexCompileFlags.CASELESS;
      re_ = new Regex(text, compileFlags, cast(GRegexMatchFlags)0);
    }
    catch(GException ex){
      re_ = null;
    }
  }
  
  
  
  //////////////// remember settings used at last time
  static string[] searchTextHistory = [];
  static int ignoreCases = 0;
  static int backwardDirection = 0;
  static int overwrappedSearch = 0;
  
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
