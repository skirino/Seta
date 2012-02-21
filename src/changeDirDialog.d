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

module changeDirDialog;

private import gtk.Dialog;
private import gtk.Widget;
private import gtk.PopupBox;
private import gtk.VBox;
private import gtk.ScrolledWindow;
private import gtk.Entry;
private import gtk.EditableIF;
private import gtk.TreeView;
private import gtk.TreeViewColumn;
private import gtk.TreeIter;
private import gtk.TreePath;
private import gtk.ListStore;
private import gtk.CellRendererText;
private import gdk.Threads;
private import gdk.Keysyms;
private import glib.Source;

private import tango.io.Stdout;
private import tango.text.Util;
private import tango.sys.Environment;
private import tango.core.Thread;
private import tango.util.MinMax;

private import stringUtil;
private import treeUtil;
static private import config;
private import keybind;
private import page;
private import filterDirPathThread;


const uint DelayTimeToStartScanInMillis = 500;


void StartChangeDirDialog(Page page)
{
  scope d = new ChangeDirDialog;
  d.showAll();
  d.run();
  
  string path = d.ret_;
  if(!IsBlank(path)){
    if(path.StartsWith("~")){
      path = Environment.get("HOME") ~ path[1..$];
    }
    page.GetFileManager().ChangeDirectory(path);
  }
}


private class ChangeDirDialog : Dialog
{
private:
  TreeView view_;
  ListStore store_;
  Entry entry_;
  bool destroyed_;
  
public:
  this()
  {
    textChanged_ = false;
    super();
    setDefaultSize(768, 600);
    addOnResponse(&Respond);
    addOnKeyPress(&KeyPressed);
    destroyed_ = false;
    VBox contentArea = getContentArea();
    
    // setup TreeView
    auto win = new ScrolledWindow(GtkPolicyType.AUTOMATIC, GtkPolicyType.AUTOMATIC);
    contentArea.packStart(win, 1, 1, 5);
    view_ = new TreeView();
    win.add(view_);
    view_.setRulesHint(1);// alternating row colors
    view_.addOnRowActivated(&RowActivated);
    
    //                      path          (color)
    store_ = new ListStore([GType.STRING, GType.STRING]);
    view_.setModel(store_);
    
    // setup column
    auto renderer = new CellRendererText;
    auto col = new TreeViewColumn("Directories", renderer, "text", 0);
    col.addAttribute(renderer, "foreground", 1);
    view_.appendColumn(col);
    
    // setup Entry
    entry_ = new Entry("");
    entry_.addOnChanged(&TextChanged);
    contentArea.packStart(entry_, 0, 0, 5);
    
    addButton(StockID.REFRESH, SCAN_FILESYSTEM);
    addButton(StockID.CANCEL,  GtkResponseType.GTK_RESPONSE_CANCEL);
    addButton(StockID.OK,      GtkResponseType.GTK_RESPONSE_OK);
    
    entry_.grabFocus();
    
    InitFilteredCandidates();
  }
  
  
  
  //////////////////// filtering in background
private:
  bool textChanged_;
  uint sourceID_;
  FilterDirPathThread filterThread_;
  
  void CancelTimeoutCallback()
  {
    // cancel previous gdkThreadsAddTimeout to wait for an idle time (0.5 second)
    if(sourceID_ > 0){
      Source.remove(sourceID_);
    }
  }
  
  void TextChanged(EditableIF e)
  {
    if(textChanged_){
      CancelTimeoutCallback();
    }
    else{
      textChanged_ = true;
    }
    sourceID_ = gdkThreadsAddTimeout(DelayTimeToStartScanInMillis, &SearchDirsCallback, cast(void*)this);
  }
  
  extern(C) static int SearchDirsCallback(void * ptr)
  {
    ChangeDirDialog self = cast(ChangeDirDialog)ptr;
    if(self !is null && self.textChanged_ && !self.destroyed_){
      self.StartFiltering();
    }
    return 0;
  }
  
  void WaitStopIfRunning()
  {
    if(filterThread_ !is null && filterThread_.isRunning()){
      filterThread_.Stop();
      
      while(filterThread_.isRunning()){
        gdkThreadsLeave();
        Thread.yield();
        Thread.sleep(0.05);
        gdkThreadsEnter();
      }
    }
  }
  
  void StartFiltering()
  {
    WaitStopIfRunning();
    
    string text = trim(entry_.getText());
    if(text is null || text.length == 0){
      InitFilteredCandidates();
    }
    else{
      filterThread_ = new FilterDirPathThread(text, &EndFiltering, &ResetTextChanged);
      filterThread_.start();
    }
  }
  
  void EndFiltering(string[] dirsFromHistory, string[] dirsFromList)
  {
    store_.clear();
    TreeIter iter = new TreeIter;
    
    foreach(dir; dirsFromHistory){
      store_.append(iter);
      store_.setValue(iter, 0, dir);
      store_.setValue(iter, 1, "#0000FF");
    }
    
    foreach(dir; dirsFromList){
      store_.append(iter);
      store_.setValue(iter, 0, dir);
    }
    
    // select 1st row if it exists
    scope iter1st = GetIterFirst(store_);
    if(iter1st !is null){
      view_.getSelection().selectIter(iter1st);
    }
    
    ResetTextChanged();
  }
  
  void ResetTextChanged()
  {
    textChanged_ = false;
  }
  
  void InitFilteredCandidates()
  {
    // put most recent history (at most 100)
    string[] dirlist = dirPathHistory.Get()[0 .. min!(size_t)($, 100)];
    EndFiltering(dirlist, []);
  }
  //////////////////// filtering in background
  
  
  
  //////////////////// change directory
private:
  private const int SCAN_FILESYSTEM = 1;// custom response ID
  string ret_;
  
  void Respond(int responseID, Dialog dialog)
  {
    CancelTimeoutCallback();
    WaitStopIfRunning();
    destroyed_ = true;
    
    if(responseID == GtkResponseType.GTK_RESPONSE_OK){
      TreeIter iter = view_.getSelectedIter();
      if(iter !is null){
        ret_ = iter.getValueString(0);
      }
    }
    else if(responseID == SCAN_FILESYSTEM){
      if(PopupBox.yesNo("Start to scan your home directory?", "")){
        dirPathList.Scan();
      }
      else{// do not destroy this dialog
        return;
      }
    }
    
    destroy();
  }
  
  bool KeyPressed(GdkEventKey * ekey, Widget w)
  {
    GdkModifierType state = TurnOffLockFlags(ekey.state);
    
    // Enter --> try to change directory
    if(state == 0 && ekey.keyval == GdkKeysyms.GDK_Return){
      Respond(GtkResponseType.GTK_RESPONSE_OK, this);
      return false;
    }
    
    // C-n, Up / C-p, Down --> move cursor in directory list view upward/downward
    if((state == GdkModifierType.CONTROL_MASK && ekey.keyval == GdkKeysyms.GDK_n) ||
       (state == 0                            && ekey.keyval == GdkKeysyms.GDK_Up)){
      scope iter = view_.getSelectedIter();
      if(iter !is null){
        scope path = iter.getTreePath();
        path.next();
        view_.setCursor(path, null, 0);
        view_.getSelection().selectPath(path);
        path.free();
      }
    }
    else if((state == GdkModifierType.CONTROL_MASK && ekey.keyval == GdkKeysyms.GDK_p) ||
            (state == 0                            && ekey.keyval == GdkKeysyms.GDK_Down)){
      scope iter = view_.getSelectedIter();
      if(iter !is null){
        scope path = iter.getTreePath();
        if(path.prev()){
          view_.setCursor(path, null, 0);
          view_.getSelection().selectPath(path);
        }
        path.free();
      }
    }
    
    return false;
  }
  
  void RowActivated(TreePath path, TreeViewColumn col, TreeView view)
  {
    view_.getSelection().selectPath(path);
    Respond(GtkResponseType.GTK_RESPONSE_OK, this);
  }
  //////////////////// change directory
}
