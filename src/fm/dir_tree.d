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

module fm.dir_tree;

import gtk.TreeView;
import gtk.TreeStore;
import gtk.TreeModelIF;
import gtk.TreeViewColumn;
import gtk.TreeIter;
import gtk.TreePath;
import gtk.CellRenderer;
import gtk.CellRendererText;
import gtk.Widget;
import gtk.DragAndDrop;
import gtk.Tooltip;
import gdk.Event;
import gio.File;
import gio.FileInfo;
import glib.GException;

import utils.vector;
import utils.template_util;
import utils.gio_util;
import utils.string_util;
import utils.tree_util;
import fm.file_view;
import move_files_job;


class DirTree : TreeView
{
private:
  TreeStore store_;
  TreeViewColumn col_;
  bool widgetShown_;
  bool showHidden_;
  Vector!(string) workspace_;
  string delegate() getPWD_;
  bool delegate(string dirname) cdFileManager_;
  bool[string] openedDirs_;

public:
  this(
    string delegate() getPWD,
    bool delegate(string) cdFileManager)
  {
    widgetShown_ = true;
    showHidden_ = false;
    workspace_ = new Vector!(string)(100);
    getPWD_ = getPWD;
    cdFileManager_ = cdFileManager;

    super();
    setHeadersVisible(0);
    setShowExpanders(1);
    setHoverExpand(0);

    store_ = new TreeStore([GType.STRING]);
    setModel(store_);

    CellRenderer renderer = new CellRendererText;
    col_ = new TreeViewColumn("directory", renderer, "text", 0);
    col_.setSizing(GtkTreeViewColumnSizing.AUTOSIZE);
    appendColumn(col_);

    addOnShow(&OnShow);
    addOnHide(&OnHide);
    addOnRowActivated(&RowActivated);
    addOnButtonRelease(&ButtonRelease, GConnectFlags.AFTER);
    addOnTestExpandRow(&TestExpandRow);
    addOnRowExpanded(&RowExpanded);
    addOnRowCollapsed(&RowCollapsed);

    InitDragAndDropFunctionality();

    setHasTooltip(1);
    addOnQueryTooltip(&TooltipCallback);

    // setup root directory
    rootDir_ = "/";
    AddPathWithDummyChild!(false)(rootDir_, null);
  }

  void SetShowHidden(bool b)
  {
    if(showHidden_ != b){
      showHidden_ = b;
      if(widgetShown_){
        ReconstructFromOpenedDirs();
      }
    }
  }

  void ChangeDirectory(string fullpath)
  {
    assert(fullpath.StartsWith(rootDir_));

    if(!widgetShown_){
      return;
    }

    TreeIter iter;
    if(fullpath in openedDirs_){
      iter = GetIterOpened(fullpath);
    }
    else{
      // do not expand row for "fullpath"
      string parentDir = ParentDirectory(fullpath);
      TreeIter iterParent = RecursiveExpandTo(parentDir);
      string name = fullpath[parentDir.length .. $];
      iter = GetChildIterForName(name, fullpath, iterParent);
    }

    ScrollToIter(iter);
  }

  void ReconstructFromOpenedDirs()
  {
    auto keys = openedDirs_.keys;
    keys.sort.reverse;

    RemoveAll();

    foreach(key; keys){
      RecursiveExpandTo(key);
    }
  }

  void RemoveUnmountedPath(string fullpath)
  {
    // remove rows for its children
    if(fullpath in openedDirs_){
      TreeIter iter = GetIterOpened(fullpath);
      RemoveAllChildren(iter);
      RemovePathFromOpenedDirs(fullpath);
    }

    // remove row for itself
    string parent = ParentDirectory(fullpath);
    if(parent in openedDirs_){
      TreeIter iterParent = GetIterOpened(parent);
      TreeIter iter = GetChildIterForName(fullpath[parent.length .. $], fullpath, iterParent);
      if(iter !is null){
        store_.remove(iter);
      }
    }
  }

  void Update(string dirname)
  {
    if(!widgetShown_){
      return;
    }
    if(!(dirname in openedDirs_)){
      return;
    }

    ReconstructFromOpenedDirs();
  }



  ///////////////////// callbacks
private:
  void OnShow(Widget w)
  {
    widgetShown_ = true;
    string pwd = getPWD_();
    TreeIter iter;
    if(pwd == rootDir_){
      iter = GetIterForRoot();
    }
    else{
      string parentPath = ParentDirectory(pwd);
      TreeIter iterParent = RecursiveExpandTo(parentPath);
      string name = pwd[parentPath.length .. $];
      iter = GetChildIterForName(name, pwd, iterParent);
    }
    ScrollToIter(iter);
  }

  void OnHide(Widget w)
  {
    widgetShown_ = false;
    RemoveAll();
  }

  void RowActivated(TreePath path, TreeViewColumn col, TreeView view)
  {
    TreeIter iter = GetIter(store_, path);

    string fullpath = GetFullPath(iter);
    TryGoToDirectory(fullpath);

    // now "iter" and "path" may be invalid.
    string parent = ParentDirectory(fullpath);
    TreeIter iterParent = GetIterOpened(parent);
    string name = fullpath[parent.length .. $];
    iter = FindChildForName(name, iterParent);
    if(iter !is null){
      TreePath p = iter.getTreePath();
      if(store_.iterHasChild(iter)){
        if(rowExpanded(p)){
          collapseRow(p);
        }
        else{
          expandRow(p, 0);
        }
      }
      else{
        // does not have any children at this time, rescan
        mixin(RuntimeDispatch1!("ScanChildren", "showHidden_", "(iter, fullpath)") ~ ';');

        expandRow(p, 0);
      }
      p.free();
    }
  }

  bool ButtonRelease(Event e, Widget w)
  {
    auto eb = e.button();

    TreePath path = GetPathAtPos(this, eb.x, eb.y);
    if(path is null){
      return false;
    }

    TreeIter iter = GetIter(store_, path);
    path.free();

    string fullpath = GetFullPath(iter);
    TryGoToDirectory(fullpath);
    return false;
  }

  bool TestExpandRow(TreeIter iter, TreePath path, TreeView view)
  {
    RemoveAllChildren(iter);

    string fullpath = GetFullPath(iter);
    mixin(RuntimeDispatch1!("ScanChildren", "showHidden_", "(iter, fullpath)") ~ ';');

    // run default handler to expand
    // (does nothing when no child is appended)
    return false;
  }

  void RowExpanded(TreeIter iter, TreePath path, TreeView view)
  {
    openedDirs_[GetFullPath(iter)] = true;
  }

  void RowCollapsed(TreeIter iter, TreePath path, TreeView view)
  {
    RemovePathFromOpenedDirs(GetFullPath(iter));
  }
  void RemovePathFromOpenedDirs(string fullpath)
  {
    openedDirs_.remove(fullpath);
    foreach(key; openedDirs_.keys){
      if(key.StartsWith(fullpath)){
        openedDirs_.remove(key);
      }
    }
  }

  bool TooltipCallback(int x, int y, int keyboardTip, GtkTooltip * p, Widget w)
  {
    TreePath path;
    TreeIter iter = new TreeIter;
    if(GetTooltipContext(this, &x, &y, keyboardTip, path, iter)){
      if(path !is null){
        CellRenderer renderer = GetCellRendererFromCol(col_);
        Tooltip tip = new Tooltip(p);
        tip.setText(GetFullPath(iter));
        setTooltipCell(tip, path, null, renderer);
        path.free();
        return true;
      }
    }
    return false;
  }
  ///////////////////// callbacks




  TreeIter GetChildIterForName(string name, string fullpath, TreeIter parent)
  {
    if(name[0] == '.' && !showHidden_ && !(fullpath in openedDirs_)){
      TreeIter iter = FindChildForName(name, parent);
      return iter is null ? AddPathWithDummyChild!(true)(name, parent) : iter;
    }
    else{
      return FindChildForName(name, parent);
    }
  }

  TreeIter FindChildForName(string name, TreeIter parent)
  {
    TreeIter child = new TreeIter;
    if(store_.iterChildren(child, parent)){
      child.setModel(store_);
      do{
        if(child.getValueString(0) == name){
          return child;
        }
      }
      while(store_.iterNext(child));
    }
    return null;
  }

  TreeIter GetIterForRoot()
  {
    return GetIterFirst(store_);
  }

  TreeIter GetIterOpened(string fullpath)
  {
    TreeIter iter = GetIterForRoot();
    string path = rootDir_;
    while(path.length != fullpath.length){
      string next = NextChildDirectory(fullpath, path);
      string name = next[path.length .. $];
      iter = FindChildForName(name, iter);
      path = next;
    }
    return iter;
  }

  TreeIter RecursiveExpandTo(string fullpath)
  {
    if(!(rootDir_ in openedDirs_)){// root is not expanded, need to expand
      expandRow(GetIterForRoot(), store_, 0);
    }

    if(fullpath in openedDirs_){
      return GetIterOpened(fullpath);
    }

    string opened = fullpath;
    do{
      opened = ParentDirectory(opened);
    }
    while(!(opened in openedDirs_));

    TreeIter iter = GetIterOpened(opened);
    while(opened.length != fullpath.length){
      string nextChild = NextChildDirectory(fullpath, opened);
      string name = nextChild[opened.length .. $];
      iter = GetChildIterForName(name, nextChild, iter);

      expandRow(iter, store_, 0);
      opened = nextChild;
    }
    return iter;
  }

  void ReopenUnder(string fullpath)
  {
    string[] keys = openedDirs_.keys;
    keys.sort;

    string[] reopen;
    foreach(key; keys){
      if(key.StartsWith(fullpath)){
        reopen ~= key;
        if(key in openedDirs_){// check whether the key is still in
          TreeIter iter = GetIterOpened(key);
          TreePath path = iter.getTreePath();
          collapseRow(path);
          path.free();
        }
      }
    }

    reopen.reverse;
    foreach(dir; reopen){
      RecursiveExpandTo(dir);
    }
  }

  void RemoveAll()
  {
    TreeIter root = GetIterForRoot();
    store_.remove(root);
    AddPathWithDummyChild!(false)(rootDir_, null);
    openedDirs_ = null;
  }

  void RemoveAllChildren(TreeIter iter)
  {
    TreeIter child = new TreeIter;
    if(store_.iterChildren(child, iter)){
      while(store_.remove(child)){}
    }
  }

  TreeIter AddPathWithDummyChild(bool beforeFirstRow)(string name, TreeIter parent)
  {
    static if(beforeFirstRow){
      TreeIter iter = store_.prepend(parent);
    }
    else{
      TreeIter iter = store_.append(parent);
    }
    store_.setValue(iter, 0, name);
    store_.append(iter);
    return iter;
  }

  string GetFullPath(TreeIter iter)
  {
    iter.setModel(store_);
    string ret = iter.getValueString(0);
    TreeIter parent = iter.getParent();
    while(parent !is null){
      ret = parent.getValueString(0) ~ ret;
      parent = parent.getParent();
    }
    return ret;
  }

  void ScanChildren(bool showHiddenFiles)(TreeIter iter, string fullpath)
  {
    File f = File.parseName(fullpath);
    try{
      scope enumerate = f.enumerateChildren("standard::name,standard::type", GFileQueryInfoFlags.NONE, null);
      FileInfo info;
      while((info = enumerate.nextFile(null)) !is null){
        if(info.getFileType() == GFileType.TYPE_DIRECTORY){
          string name = info.getName();
          static if(!showHiddenFiles){
            if(name[0] == '.') continue;
          }
          workspace_.append(name);
        }
      }
      enumerate.close(null);
    }
    catch(GException ex){
      // permission denied
    }

    workspace_.array().sort;
    foreach(name; workspace_.array()){
      AddPathWithDummyChild!(false)(name ~ '/', iter);
    }
    workspace_.clear();
  }

  void TryGoToDirectory(string fullpath)
  {
    // check whether the "fullpath" exists
    // if true, go to that directory
    // if false, reconstruct the directory tree
    if(fullpath != getPWD_()){
      if(!cdFileManager_(fullpath)){// no such directory
        // remove nonexistent path from "openedDirs_" and
        // reopen originally opened directories

        openedDirs_.remove(fullpath);
        string d = ParentDirectory(fullpath);
        while(!Exists(d)){
          openedDirs_.remove(d);
          d = ParentDirectory(d);
        }
        ReopenUnder(d);
      }
    }
  }

  void ScrollToIter(TreeIter iter)
  {
    TreePath path = store_.getPath(iter);
    setCursor(path, null, 0);
    scrollToCell(path, null, 1, 0.5, 0.0);
    path.free();
  }



  ////////////////// drag and drop
  void InitDragAndDropFunctionality()
  {
    enableModelDragDest(
      constants.GetDragTargets(),
      GdkDragAction.ACTION_MOVE | GdkDragAction.ACTION_COPY);
    addOnDragDataReceived(&DragDataReceived);
  }

  void DragDataReceived(
    GdkDragContext * context, int x, int y,
    GtkSelectionData * selection, uint info, uint time, Widget w)
  {
    TreePath path;
    GtkTreeViewDropPosition pos;
    getDestRowAtPos(x, y, path, pos);
    DragAndDrop dnd = new DragAndDrop(context);

    if(path !is null){// destination exists
      TreeIter iter = GetIter(store_, path);
      path.free();
      string fullpath = GetFullPath(iter);
      string[] files = GetFilesFromSelection(selection);
      GdkDragAction action = ExtractSuggestedAction(context);// initialize it as given by GdkDragContext

      TransferFiles(action, files, cast(FileView)dnd.getSourceWidget(), fullpath);
    }

    dnd.finish(1, 0, 0);
  }
  ////////////////// drag and drop



  ////////////////// SFTP/SSH
  string rootDir_;

public:
  void StartSSH(string gvfsRoot, string initialDir)
  {
    rootDir_ = AppendSlash(gvfsRoot);
    RemoveAll();
    ChangeDirectory(initialDir);
  }

  void QuitSSH(string pwd)
  {
    rootDir_ = "/";
    RemoveAll();
    ChangeDirectory(pwd);
  }
  ////////////////// SFTP/SSH
}


private string NextChildDirectory(string fullpath, string parent)
{
  size_t end = locate(fullpath, '/', parent.length);
  return fullpath[0 .. end+1];
}
