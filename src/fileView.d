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

module fileView;

private import gtk.TreeView;
private import gtk.Widget;
private import gtk.ListStore;
private import gtk.TreeIter;
private import gtk.TreePath;
private import gtk.TreeViewColumn;
private import gtk.TreeSelection;
private import gtk.TreeModelIF;
private import gtk.CellRendererText;
private import gtk.PopupBox;
private import gtk.Tooltip;
private import gtk.DragAndDrop;
private import gtk.Selections;
private import gtk.TargetList;
private import gdk.Event;
private import gdk.Threads;
private import gdk.Rectangle;
private import gio.File;
private import gio.FileInfo;
private import gio.FileMonitor;
private import gio.DesktopAppInfo;
private import glib.GException;
private import gtkc.gtk;

private import tango.io.Stdout;
private import tango.text.Util;
private import tango.core.Thread;
private import tango.util.MinMax;
private import tango.stdc.stdlib;

private import utils.bind;
private import utils.timeUtil;
private import utils.stringUtil;
private import utils.gioUtil;
private import utils.templateUtil;
private import utils.treeUtil;
private import utils.vector;
private import constants;
private import rcfile = config.rcfile;
private import config.keybind;
private import entry;
private import listupThread;
private import popupMenu;
private import mediator;
private import transferFiles;
private import rename.dialog;
private import entryList;


class FileView : TreeView
{
  //////////////////// GUI stuff
private:
  static const int[] cols =
    [ColumnType.NAME, ColumnType.TYPE, ColumnType.SIZE,
     ColumnType.OWNER, ColumnType.PERMISSIONS, ColumnType.LAST_MODIFIED,
     ColumnType.COLOR];
  ListStore store_;
  
  EntryList eList_;
  
public:
  this(Mediator mediator)
  {
    mediator_ = mediator;
    showHidden_ = false;
    eList_ = new EntryList;

    super();
    setRulesHint(1);// alternating row colors
    setGridLines(GtkTreeViewGridLines.BOTH);
    setFixedHeightMode(1);
    setRubberBanding(1);

    addOnRowActivated(&RowActivated);
    addOnKeyPress(&KeyPressed);
    addOnUnrealize(&StopOngoingOperations);
    getSelection.setMode(GtkSelectionMode.MULTIPLE);

    //                      name          type          size          owner         permissions   lastmodified  (color)
    store_ = new ListStore([GType.STRING, GType.STRING, GType.STRING, GType.STRING, GType.STRING, GType.STRING, GType.STRING]);
    setModel(store_);

    // columns
    cols_[ColumnType.NAME]          = SetupNewColumn(ColumnType.NAME);
    cols_[ColumnType.TYPE]          = SetupNewColumn(ColumnType.TYPE);
    cols_[ColumnType.SIZE]          = SetupNewColumn(ColumnType.SIZE);
    cols_[ColumnType.OWNER]         = SetupNewColumn(ColumnType.OWNER);
    cols_[ColumnType.PERMISSIONS]   = SetupNewColumn(ColumnType.PERMISSIONS);
    cols_[ColumnType.LAST_MODIFIED] = SetupNewColumn(ColumnType.LAST_MODIFIED);

    cols_[ColumnType.NAME].setExpand(1);
    cols_[ColumnType.TYPE].setSortIndicator(1);// default sort order
    sortColumn_ = ColumnType.TYPE;
    sortOrder_ = GtkSortType.ASCENDING;

    appendColumn(cols_[ColumnType.NAME]);
    appendColumn(cols_[ColumnType.TYPE]);
    appendColumn(cols_[ColumnType.SIZE]);
    appendColumn(cols_[ColumnType.OWNER]);
    appendColumn(cols_[ColumnType.PERMISSIONS]);
    appendColumn(cols_[ColumnType.LAST_MODIFIED]);

    InitFileInfoAttributes();
    InitTooltipFunctionality();
    InitDragAndDropFunctionality();
  }

  void SetLayout()
  {
    foreach(int id, width; rcfile.GetWidths()){
      if(width == 0){
        cols_[id].setVisible(0);
      }
      else{
        cols_[id].setVisible(1);
        cols_[id].setFixedWidth(width);
      }
    }
    
    string old = fileInfoAttributes_;
    ResetFileInfoAttributes();
    if(pwd_ !is null){// not first time "SetLayout()" is called
      // there may be some changes in preferences
      TryUpdate();
    }
  }
  //////////////////// GUI stuff
  
  
  
  //////////////////// column
private:
  TreeViewColumn[ColumnType.COLOR] cols_;
  
  TreeViewColumn SetupNewColumn(ColumnType id)
  {
    auto renderer = new CellRendererText;
    TreeViewColumn col = new TreeViewColumn(ColumnTitles[id], renderer, "text", id);
    col.addAttribute(renderer, "foreground", ColumnType.COLOR);
    col.setSizing(GtkTreeViewColumnSizing.FIXED);
    col.setFixedWidth(50);// minimum width
    col.setResizable(1);
    col.setClickable(1);
    col.addOnClicked(&SortOrderCallback);
    return col;
  }
  
  string GetValueString(TreeIter iter, TreeViewColumn col)
  {
    foreach(i, c; cols_){
      if(c is col){
        return iter.getValueString(i);
      }
    }
    return null;
  }
  //////////////////// column
  
  
  
  //////////////////// list entries in directory
private:
  Mediator mediator_;
  string pwd_;
  
public:
  void TryUpdate()
  {
    try{
      Update(pwd_);
    }
    catch(GException ex){// "pwd_" does not exist in the file system!
      PopupBox.error(ex.toString() ~ "\nMove to its parent directory.", "error");

      string parent = mediator_.FileSystemParentDirectory(pwd_);
      while(true){
        if(Exists(parent)){
          mediator_.FilerChangeDirectory(parent);
          break;
        }

        if(parent == mediator_.FileSystemRoot()){
          // The root directory does not exist!
          // This should be due to accidental disconnection from a SSH host
          assert(mediator_.FileSystemIsRemote());
          mediator_.FilerDisconnect();
          break;
        }

        parent = mediator_.FileSystemParentDirectory(parent);
      }
    }
  }
  
private:
  void Update(string dirname, File file = null, bool appendToHistory = false, bool notifyTerminal = false)
  {
    assert(dirname[$-1] == '/');
    
    File dirFile = file is null ? File.parseName(dirname) : file;
    bool remote = mediator_.FileSystemLookingAtRemoteFS(dirname);
    
    if(!mediator_.FilerIsVisible()){
      pwd_ = dirname;
      contentsChanged_ = false;
      mediator_.UpdatePathLabel(dirname, CountNumEntries(dirname));// just count number of entries
      ResetMonitoring(remote, dirFile);
      
      if(notifyTerminal){
        mediator_.TerminalChangeDirectoryFromFiler(pwd_);
      }
      
      if(appendToHistory){
        mediator_.FilerAppendToHistory(pwd_);
      }
    }
    else{
      // start worker thread
      EnumerateFilterSortSet(remote, dirname, dirFile, appendToHistory, notifyTerminal);
    }
  }
  ///////////////////// list up entries in directory
  
  
  
  ///////////////////// update driven by changes in directory
private:
  FileMonitor monitor_;
  bool contentsChanged_;
  
  extern(C) static int UpdateCallback(void * ptr)
  {
    FileView view = cast(FileView)ptr;
    if(view !is null && view.contentsChanged_){
      if(view.isRubberBandingActive()){// Updating contents of TreeView during rubber banding is problematic
        return 1;// this function will be repeatedly called until FALSE is returned
      }
      else{
        // contents-change should not cancel user's request for "change directory"
        if(view.prepareUpdateThread_ !is null && view.prepareUpdateThread_.isRunning()){// not updating
          return 1;
        }
        else{
          view.TryUpdate();
          view.mediator_.UpdateDirTree(view.pwd_);
        }
      }
    }
    return 0;
  }
  
  void DirChanged(File f1, File f2, GFileMonitorEvent e, FileMonitor m)
  {
    if(!contentsChanged_){
      contentsChanged_ = true;
      gdkThreadsAddTimeout(500, &UpdateCallback, cast(void*)this);
    }
  }
  
  void UpdateIfNecessary()
  {
    if(contentsChanged_){
      TryUpdate();
    }
  }
  
  void ResetMonitoring(bool remote, File pwdNewFile)
  {
    if(monitor_ !is null){
      monitor_.cancel();
    }
    if(!remote){// remote dirs cannot be monitored
      try{
        monitor_ = pwdNewFile.monitorDirectory(GFileMonitorFlags.NONE, null);
        monitor_.addOnChanged(&DirChanged);
      }
      catch(GException ex){}// cannot monitor e.g. directories in music CDs
    }
  }
  
public:
  void StopOngoingOperations(Widget w = null)
  {
    // disable monitoring of directory
    if(monitor_ !is null){
      monitor_.cancel();
    }
    contentsChanged_ = false;
    
    // stop running thread
    WaitStopIfRunning();
  }
  ///////////////////// update driven by changes in directory
  
  
  
  ///////////////////// listup in another thread
private:
  // number of rows (DirEntry's) present in the TreeView now
  uint numRowsNow_;
  
  PrepareDirEntriesThread prepareUpdateThread_;
  
  void WaitStopIfRunning()
  {
    if(prepareUpdateThread_ !is null && prepareUpdateThread_.isRunning()){
      prepareUpdateThread_.Stop();
      
      // wait for the end of the thread
      while(prepareUpdateThread_.isRunning()){
        // For the thread to finish its work, releasing GDK lock is necessary here
        gdkThreadsLeave();
        Thread.yield();
        Thread.sleep(0.05);
        gdkThreadsEnter();
      }
    }
  }
  
  void EnumerateFilterSortSet(bool remote, string dir, File dirFile, bool appendToHistory, bool notifyTerminal)
  {
    WaitStopIfRunning();
    
    prepareUpdateThread_ =
      new PrepareDirEntriesThread(
        true, dir,
        mixin(RuntimeDispatch3!("&SetRowsCallback", "true", "appendToHistory", "notifyTerminal")),
        eList_.GetDTemp(), eList_.GetFTemp(), eList_.GetDFiltered(), eList_.GetFFiltered());
    prepareUpdateThread_.SetForEnumerate(remote, fileInfoAttributes_, dirFile);
    prepareUpdateThread_.SetForFilter(showHidden_, filterText_);
    prepareUpdateThread_.SetForSort(sortColumn_, sortOrder_);
    prepareUpdateThread_.start();
  }
  
  void FilterSortSet()
  {
    WaitStopIfRunning();
    
    // Do not read the directory entries from disk,
    // reuse previous results (which are stored in entriesDAll_ and entriesFAll_)
    prepareUpdateThread_ =
      new PrepareDirEntriesThread(
        false, pwd_,
        &SetRowsCallback!(false, false, false),
        eList_.GetDAll(), eList_.GetFAll(), eList_.GetDFiltered(), eList_.GetFFiltered());
    prepareUpdateThread_.SetForFilter(showHidden_, filterText_);
    prepareUpdateThread_.SetForSort(sortColumn_, sortOrder_);
    prepareUpdateThread_.start();
  }
  
  void SetRowsCallback(bool withEnumerateDirEntries, bool appendToHistory, bool notifyTerminal)(
    bool remote, string pwdNew, File pwdNewFile)
  {
    // set DirEntry vectors (swap internal arrays to avoid deep copy)
    eList_.SwapEntries!(withEnumerateDirEntries)();
    
    // update monitoring
    static if(withEnumerateDirEntries){
      if(pwd_ != pwdNew){
        ResetMonitoring(remote, pwdNewFile);
      }
    }
    
    pwd_ = pwdNew;
    contentsChanged_ = false;
    
    ResetRows();
    
    static if(appendToHistory){
      mediator_.FilerAppendToHistory(pwd_);
    }
    
    static if(notifyTerminal){
      mediator_.TerminalChangeDirectoryFromFiler(pwd_);
    }
  }
  
  void ResetRows()
  {
    mediator_.UpdatePathLabel(pwd_, eList_.NumEntriesAll());
    
    // cleanup
    store_.clear();
    numRowsNow_ = 0;
    
    string[] colors = rcfile.GetRowColors();
    TreeIter iter = new TreeIter;
    {// parent dir
      store_.append(iter);
      string parentPath = mediator_.FileSystemParentDirectory(pwd_);
      File f = File.parseName(parentPath);
      FileInfo info = f.queryInfo("standard::is-symlink,unix::mode,owner::user,time::modified", GFileQueryInfoFlags.NONE, null);
      store_.set(
        iter, cols,
        [PARENT_STRING,
         GetDirectoryTypeDescription(),
         PluralForm!(int, "item")(CountNumEntries(parentPath)),
         info.getAttributeString("owner::user"),
         PermissionInStr(info.getAttributeUint32("unix::mode"), info.getIsSymlink() != 0),
         EpochTimeToString(info.getAttributeUint64("time::modified")),
         colors[FileColorType.Directory]]);
    }
    
    // set entries to ListStore
    AppendRows(1000, colors, iter);// append up to 1000 rows
    if(numRowsNow_ < eList_.NumEntriesSorted()){// if there are remaining rows to be added
      gdkThreadsAddIdle(&AppendRowsAtIdle, cast(void*)this);
    }
  }
  
  void AppendRows(size_t numAppend, string[] colors = null, TreeIter iter = null)
  {
    if(numRowsNow_ >= eList_.NumEntriesSorted()){
      return;
    }
    
    if(colors is null){
      colors = rcfile.GetRowColors();
    }
    if(iter is null){
      iter = new TreeIter;
    }
    
    size_t entDSize = eList_.GetDSorted().size();
    size_t entFSize = eList_.GetFSorted().size();
    size_t maxRows = numRowsNow_ + numAppend;
    
    if(numRowsNow_ < entDSize){// there are directories which should be appended to the view
      size_t upper = min(maxRows, entDSize);
      foreach(p; eList_.GetDSorted()[numRowsNow_ .. upper]){
        store_.append(iter);
        store_.set(
          iter, cols,
          [p.GetName(), GetDirectoryTypeDescription(), p.GetDirSize(), p.GetOwner(),
           p.GetPermission(), p.GetModified(), colors[p.GetDirColorType()]]);
      }
      numRowsNow_ = upper;
      
      if(maxRows <= entDSize){// finished appending "numAppend" directories at this time
        return;
      }
    }
    
    if(numRowsNow_ < entDSize + entFSize){// there are files which should be appended to the view
      size_t upper = min(maxRows - entDSize, entFSize);
      
      foreach(p; eList_.GetFSorted()[numRowsNow_ - entDSize .. upper]){
        store_.append(iter);
        store_.set(
          iter, cols,
          [p.GetName(), p.GetType(), p.GetFileSize(), p.GetOwner(),
           p.GetPermission(), p.GetModified(), colors[p.GetFileColorType()]]);
      }
      numRowsNow_ = entDSize + upper;
    }
  }
  
  void AppendAllRows()
  {
    AppendRows(eList_.NumEntriesSorted());
  }
  
  extern(C) static gboolean AppendRowsAtIdle(void * ptr)
  {
    // This callback is called when displaying directories with more than 1000 entries.
    auto view = cast(FileView)ptr;// should not be 'scope'
    view.AppendRows(5000);// Append 5000 items at a time.
    if(view.numRowsNow_ < view.eList_.NumEntriesSorted()){
      return 1;// continue to call this callback function
    }
    else{
      return 0;
    }
  }
  ///////////////////// listup in another thread
  
  
  
  ///////////////////// enumerate directory entries
private:
  string fileInfoAttributes_;
  
  static const string necessaryAttributes_ = "standard::name,standard::type,standard::is-symlink";
  static const string[ColumnType.COLOR] optionalAttributes_ =
    ["", "standard::content-type", "standard::size", "owner::user", "unix::mode", "time::modified"];
  
  void InitFileInfoAttributes()
  {
    fileInfoAttributes_ = necessaryAttributes_ ~ ',' ~ optionalAttributes_.join(",");
  }
  
  void ResetFileInfoAttributes()
  {
    fileInfoAttributes_ = necessaryAttributes_;
    
    foreach(int id, width; rcfile.GetWidths()){
      if(id > 0){// omit "ColumnType.NAME"
        if(width > 0){
          fileInfoAttributes_ ~= ',' ~ optionalAttributes_[id];
        }
      }
    }
  }
  ///////////////////// enumerate directory entries
  
  
  
  ///////////////////// filter
private:
  bool showHidden_;
  string filterText_;
  
public:
  void SetShowHidden(bool b)
  {
    showHidden_ = b;
    FilterSortSet();
  }
  
  void FilterChanged(string text)
  {
    filterText_ = text;
    FilterSortSet();
  }
  ///////////////////// filter
  
  
  
  ////////////////////// sort entries
private:
  ColumnType sortColumn_;
  GtkSortType sortOrder_;
  
  void SortOrderCallback(TreeViewColumn col)
  {
    if(col is cols_[sortColumn_]){// flip sort order of clicked column
      sortOrder_ = cast(GtkSortType)(1 - sortOrder_);
      col.setSortOrder(sortOrder_);
    }
    else{
      // move sort indicator
      cols_[sortColumn_].setSortIndicator(0);
      col.setSortIndicator(1);
      
      // default for sortOrder_ is "ascending";
      sortOrder_ = GtkSortType.ASCENDING;
      col.setSortOrder(sortOrder_);// default is 'ascending'
      
      // update sortColumn_
      foreach(i, c; cols_){
        if(col is c){
          sortColumn_ = cast(ColumnType)i;
          break;
        }
      }
    }
    
    // reorder rows (no need to read disk)
    FilterSortSet();
  }
  ////////////////////// sort entries
  
  
  
  ////////////////////// change directory
public:
  // called by the parent (FileManager)
  bool ChangeDirectory(string dirname, bool appendToHistory = false, bool notifyTerminal = false)
  {
    // dirname must end with '/'
    assert(dirname[$-1] == '/');
    
    if(dirname != pwd_){
      // check whether the directory can be opened
      File f = GetFileForDirectory(dirname);
      if(f !is null){// path exists
        if(CanEnumerateChildren(f)){// not permission denied
          Update(dirname, f, appendToHistory, notifyTerminal);
          return true;
        }
      }
    }
    return false;
  }
  
  void GoDownIfOnlyOneDir()
  {
    auto ents = eList_.GetDSorted();
    if(ents.size() == 1){
      mediator_.FilerChangeDirectory(pwd_ ~ ents[0].GetName());
    }
  }
  ////////////////////// change directory
  
  
  
  ////////////////////// manipulation of focus
public:
  void GrabFocus()
  {
    grabFocus();
    MoveCursorToSecondRow();
  }
  
private:
  void MoveCursorToSecondRow()
  {
    // move cursor to the next row of "../"
    TreePath path = new TreePath(true);
    path.next();
    setCursor(path, null, 0);
    getSelection().unselectPath(path);
    path.free();
  }
  ////////////////////// manipulation of focus
  
  
  
  /////////////////////////// tooltip
private:
  void InitTooltipFunctionality()
  {
    setHasTooltip(1);
    addOnQueryTooltip(&TooltipCallback);
  }
  
  // callback to show tooltip for ellipsized texts or target paths of symlinks
  bool TooltipCallback(int x, int y, int keyboardTip, GtkTooltip * p, Widget w)
  {
    // show tooltip for ellipsized texts in NAME and TYPE column
    TreeModelIF model;
    TreePath path;
    TreeIter iter = new TreeIter;
    iter.setModel(store_);
    if(getTooltipContext(&x, &y, keyboardTip, model, path, iter)){
      if(path !is null){
        TreeViewColumn col = GetColAtPos(this, x, y);
        string tooltipContent;
        auto renderer = GetCellRendererFromCol(col);
        
        ////////////////////// tooltip for long file name or type
        {
          // get actualWidth, widthNeeded for column (at this point not for cell)
          int startPos, actualWidth;
          col.cellGetPosition(renderer, startPos, actualWidth);
          string text = GetValueString(iter, col);
          int textWidth = GetTextWidth(text);
          if(actualWidth < textWidth){// text in the cell is too long and thus ellipsized
            tooltipContent ~= text;
          }
        }
        //////////////////////
        
        ////////////////////// tooltip for symlink target
        int row = path.getIndices()[0];
        if(row != 0){// exclude "../"
          // Just after changing directory, "row" can be larger than the max index of entries.
          // Exclude these cases.
          
          if(row < 1 + eList_.NumEntriesSorted()){
            DirEntry ent =
              (row <= eList_.GetDSorted().size()) ? eList_.GetDSorted()[row-1] :
                                                    eList_.GetFSorted()[row - 1 - eList_.GetDSorted().size];

            if(ent.IsSymlink()){
              File f = File.parseName(pwd_ ~ ent.GetName());
              FileInfo info = f.queryInfo("standard::symlink-target", GFileQueryInfoFlags.NONE, null);
              string linkTarget = "link to: " ~ info.getSymlinkTarget();
              tooltipContent ~= tooltipContent.length > 0 ? '\n' ~ linkTarget : linkTarget;
            }
          }
        }
        //////////////////////
        
        if(tooltipContent.length > 0){
          Tooltip tip = new Tooltip(p);
          tip.setText(tooltipContent);
          setTooltipCell(tip, path, col, renderer);// set position for the tooltip to appear
          return true;
        }
        
        path.free();
      }
    }
    
    // in the other cases tooltip should not appear
    return false;
  }
  /////////////////////////// tooltip
  
  
  
  /////////////////////////// util
private:
  string[] GetSelectedFileNames()
  {
    TreeIter[] iters = getSelectedIters();
    string[] ret;
    foreach(iter; iters){
      string name = GetNameFromIter(iter);
      if(name !is null){
        ret ~= name;
      }
    }
    return ret;
  }
  
  string GetNameFromIter(TreeIter iter)
  {
    if(iter is null){
      return null;
    }
    else{
      return iter.getValueString(ColumnType.NAME);
    }
  }
  
  string GetNameFromPath(TreePath path)
  {
    return GetNameFromIter(GetIter(store_, path));
  }
  /////////////////////////// util
  
  
  
  /////////////////////  event handling
private:
  // double clicking or pressing Enter
  void RowActivated(TreePath path, TreeViewColumn tcolumn, TreeView tview)
  {
    int rowSelected = path.getIndices()[0];
    if(rowSelected == 0){// parent is double-clicked
      string parentDir = mediator_.FileSystemParentDirectory(pwd_);
      mediator_.FilerChangeDirectory(parentDir);
    }
    else if(rowSelected <= eList_.GetDSorted().size()){// directory is double-clicked
      size_t index = rowSelected - 1;
      if(! mediator_.FilerChangeDirectory(pwd_ ~ eList_.GetDSorted()[index].GetName())){
        // no such directory, just update
        TryUpdate();
      }
    }
    else{// file is double-clicked
      size_t index = rowSelected - 1 - eList_.GetDSorted().size();
      string fullname = pwd_ ~ eList_.GetFSorted()[index].GetName();
      try{// to open file using appropriate application
        File f = File.parseName(fullname);
        FileInfo info = f.queryInfo("standard::content-type,access::can-execute", GFileQueryInfoFlags.NONE, null);
        auto appInfo = DesktopAppInfo.getDefaultForType(info.getContentType(), 0);
        if(appInfo !is null){
          LaunchApp(appInfo, f);
        }
        else{// cannot find appropriate application to open this file
          // execute the file if it is executable one
          if(info.getAttributeBoolean("access::can-execute")){
            string command = fullname ~ " & \0";
            system(command.ptr);
          }
        }
      }
      catch(GException ex){// no such file
        TryUpdate();
      }
    }
  }
  
  bool KeyPressed(GdkEventKey * ekey, Widget w)
  {
    switch(QueryFileViewAction(ekey)){
      
    case -1:
      return false;
      
    case FileViewAction.SelectAll:
      // add all DirEntry's to the view
      AppendAllRows();
      
      // select all except "../"
      MoveCursorToSecondRow();
      TreeSelection selection = getSelection();
      selection.selectAll();
      TreePath path = new TreePath(true);
      selection.unselectPath(path);// unselect 1st row
      path.free();
      return true;
      
    case FileViewAction.SelectRow:
      TreePath path = GetPathAtCursor(this);
      if(path is null){
        return false;
      }
      else{
        TreeSelection selection = getSelection();
        if(selection.pathIsSelected(path)){
          selection.unselectPath(path);
        }
        else{
          selection.selectPath(path);
        }
        path.free();
        return true;
      }
      
    case FileViewAction.Cut:
      PreparePaste(true, pwd_, GetSelectedFileNames(), this);
      return true;
      
    case FileViewAction.Copy:
      PreparePaste(false, pwd_, GetSelectedFileNames(), this);
      return true;
      
    case FileViewAction.Paste:
      PasteFiles(pwd_, this);
      return true;
      
    case FileViewAction.PopupMenu:
      // popup right-click menu
      TreePath path = GetPathAtCursor(this);
      if(path !is null){// select the path
        getSelection().selectPath(path);
      }
      PopupFilerMenu!(true)(path, ekey.time);
      if(path !is null){
        path.free();
      }
      return true;
      
    case FileViewAction.Rename:
      RenameFiles(pwd_, GetSelectedFileNames());
      TryUpdate();
      return true;
      
    case FileViewAction.MakeDirectory:
      MakeDirectory(pwd_);
      return true;
      
    case FileViewAction.MoveToTrash:
      MoveToTrash(pwd_, GetSelectedFileNames());
      return true;
      
    case FileViewAction.FocusFilter:
      mediator_.FilerFocusFilter();
      return true;
      
    case FileViewAction.ClearFilter:
      mediator_.FilerClearFilter();
      return true;
      
    default:
      return false;
    }
  }
  
  void PopupFilerMenu(bool usePositionFunc = false)(TreePath path, uint activateTime)
  {
    try{
      RightClickMenu menu = new RightClickMenu(
        this, pwd_, GetNameFromPath(path), GetSelectedFileNames(),
        bind(&(mediator_.FilerChangeDirectory), _0, true, true).ptr());
      
      // Passing eb.button as the 1st argument of menu.popup() is problematic,
      // since in that case the submenu cannot be simply activated.
      // The 1st arg should be 0 as written in the gtk+ docs.
      static if(!usePositionFunc){
        menu.popup(0, activateTime);
      }
      else{
        // get position for popup menu
        GdkRectangle * ptr = new GdkRectangle;
        Rectangle rect = new Rectangle(ptr);
        getCellArea(path, cols_[ColumnType.NAME], rect);
        int x, y;
        convertBinWindowToWidgetCoords(ptr.x, ptr.y, x, y);
        translateCoordinates(getToplevel(), x, y, ptr.x, ptr.y);
        menu.popup(null, null, &RightClickMenuPositioning, ptr, 0, activateTime);
      }
    }
    catch(GException ex){// no such file or directory, rescan the directory
      TryUpdate();
    }
  }
  /////////////////////  event handling
  
  
  
  ////////////////////// drag and drop
private:
  DraggingState draggingState_;
  static int dragStartButton_;
  int dragStartX_;
  int dragStartY_;
  bool selectionDoneWhenPressed_;
  
  void InitDragAndDropFunctionality()
  {
    GtkTargetEntry[] dragTargets = constants.GetDragTargets();
    enableModelDragDest(
      dragTargets,
      GdkDragAction.ACTION_MOVE | GdkDragAction.ACTION_COPY);
    
    enableModelDragSource(
      GdkModifierType.BUTTON1_MASK | GdkModifierType.BUTTON2_MASK,
      dragTargets,
      GdkDragAction.ACTION_MOVE | GdkDragAction.ACTION_COPY);
    
    addOnButtonPress(&ButtonPressed);
    addOnButtonRelease(&ButtonReleased);
    addOnMotionNotify(&MotionNotify);
    addOnDragDataGet(&DragDataGet);
    addOnDragDataReceived(&DragDataReceived);
  }
  
  // handles row selections and stores the position of the cursor for drag start
  bool ButtonPressed(GdkEventButton * eb, Widget treeView)
  {
    if(eb.window != getBinWindow().getWindowStruct()){// header is clicked
      return false;
    }
    
    grabFocus();// to enable select path at 1st click
    TreePath path = GetPathAtPos(this, eb.x, eb.y);
    TreeSelection selection = getSelection();
    if(path is null){// empty space is clicked
      selection.unselectAll();
    }
    
    if(eb.button == MouseButton.RIGHT){// right button, popup menu
      if(path !is null){
        // check whether the clicked row is already selected
        if(selection.pathIsSelected(path) == 0){
          // "path" is not selected, now select it
          selection.unselectAll();
          selection.selectPath(path);
        }
      }
      
      PopupFilerMenu(path, eb.time);
      
      // prevent default handler to unselect selected rows other than "path"
      if(path !is null) path.free();
      return true;
    }
    
    if(path !is null){
      if(eb.button == MouseButton.LEFT && Event.isDoubleClick(eb)){// when double-clicked, activate the clicked row
        draggingState_ = DraggingState.NEUTRAL;
        RowActivated(path, null, this);
        path.free();
        return true;
      }
      else if(eb.button == MouseButton.LEFT || eb.button == MouseButton.MIDDLE){
        
        if(selection.pathIsSelected(path)){
          // check whether the mouse cursor is on the first row ("../") or not
          string namePath = GetNameFromPath(path);
          if(namePath != PARENT_STRING){
            // check "../" is not included in the selected files
            TreeIter firstIter = getSelectedIter();
            string firstRow = GetNameFromIter(firstIter);
            if(firstRow != PARENT_STRING){
              // prepare for dragging
              draggingState_ = DraggingState.PRESSED;
              dragStartButton_ = eb.button;
              dragStartX_ = cast(int)eb.x;
              dragStartY_ = cast(int)eb.y;
            }
          }
          
          // returning false here will unselect the selected rows
          // and avoid rubber banding
          path.free();
          return true;
        }
        else{// if not selected, pass control to the default handler
          selectionDoneWhenPressed_ = true;
          path.free();
          return false;// default handler will select the clicked row
        }
      }
      
      path.free();
    }
    
    return false;
  }
  
  // selection handling, right click menu and end of dragging
  bool ButtonReleased(GdkEventButton * eb, Widget w)
  {
    if(draggingState_ != DraggingState.DRAGGING){// released before starting drag
      if(eb.button == MouseButton.LEFT || eb.button == MouseButton.MIDDLE){
        if(!(eb.state & GdkModifierType.SHIFT_MASK || eb.state & GdkModifierType.CONTROL_MASK)){// Shift or Ctrl is not pressed
          if(!isRubberBandingActive()){// on rubber banding, the selection should not be modified here
            TreePath path = GetPathAtPos(this, eb.x, eb.y);
            if(path !is null){
              // select only the clicked row, that is, unselect the others
              TreeSelection selection = getSelection();
              if(selection.pathIsSelected(path)){
                selection.unselectAll();
                selection.selectPath(path);
                setCursor(path, null, 0);
              }
              path.free();
            }
          }
        }
        else if(eb.state & GdkModifierType.CONTROL_MASK){// CTRL - left or middle button
          // remove TreePath from the selection
          if(!selectionDoneWhenPressed_){
            TreePath path = GetPathAtPos(this, eb.x, eb.y);
            TreeSelection selection = getSelection();
            if(path !is null){
              if(selection.pathIsSelected(path)){
                selection.unselectPath(path);
              }
              path.free();
            }
          }
        }
      }
      
      // reset
      selectionDoneWhenPressed_ = false;
      draggingState_ = DraggingState.NEUTRAL;
    }
    
    return false;
  }
  
  // Check whether the left or middle button has been pressed
  // and whether the distance covered is larger than the threshold value.
  // If true, start dragging.
  bool MotionNotify(GdkEventMotion * em, Widget w)
  {
    if(draggingState_ == DraggingState.PRESSED){
      if(DragAndDrop.checkThreshold(this, dragStartX_, dragStartY_,
                                    cast(int)em.x, cast(int)em.y)){
        // start dragging
        draggingState_ = DraggingState.DRAGGING;
        
        // specify possible action for this drag here (judging from the dragging button)
        GdkDragAction action = dragStartButton_ == MouseButton.LEFT ? GdkDragAction.ACTION_MOVE : GdkDragAction.ACTION_COPY;
        
        auto dnd = DragAndDrop.begin(
          this,
          new TargetList(constants.GetDragTargets()),
          action,
          dragStartButton_,
          new Event(cast(GdkEvent*)em));
        
        gtk_drag_set_icon_default(dnd.getDragContextStruct());
        
        // reset drag button
        dragStartButton_ = 0;
      }
      return true;
    }
    else{
      return false;
    }
  }
  
  void DragDataGet(GdkDragContext * context, GtkSelectionData * selection, uint info, uint time, Widget w)
  {
    // prepare items that will be moved/copied
    string[] filenames = GetSelectedFileNames();
    if(filenames.length > 0){
      Selections.dataSetUris(selection, MakeURIList(pwd_, filenames));
    }
    draggingState_ = DraggingState.NEUTRAL;
  }
  
  // do move or copy dragged items
  void DragDataReceived(
    GdkDragContext * context, int x, int y,
    GtkSelectionData * selection, uint info, uint time, Widget w)
  {
    DragAndDrop dnd = new DragAndDrop(context);
    string[] files = GetFilesFromSelection(selection);
    
    if(files.length > 0){
      // determine "destDir"
      string destDir = pwd_;
      TreePath path;
      GtkTreeViewDropPosition pos;
      getDestRowAtPos(x, y, path, pos);
      Widget sourceWidget = dnd.getSourceWidget();
      
      // if dropped on a row for a directory, set "destDir" to the path to that directory
      if(pos == GtkTreeViewDropPosition.GTK_TREE_VIEW_DROP_INTO_OR_BEFORE ||
         pos == GtkTreeViewDropPosition.GTK_TREE_VIEW_DROP_INTO_OR_AFTER){
        if(path !is null){
          string name = GetNameFromPath(path);
          if(sourceWidget is this && name[$-1] == '/' && getSelection().pathIsSelected(path)){
            // dropped position is included in the selection, do nothing
            goto finish;
          }
          else{
            if(name == PARENT_STRING){// drop on "../"
              destDir = mediator_.FileSystemParentDirectory(pwd_);
            }
            else if(name[$-1] == '/'){// drop on directory
              destDir = pwd_ ~ name;
            }
          }
        }
      }
      
      GdkDragAction action = ExtractSuggestedAction(context);
      TransferFiles(action, files, cast(FileView)sourceWidget, destDir, this);// cast may fail and null may be passed
      
      finish:
      if(path !is null) path.free();
    }
    
    dnd.finish(1, 0, 0);
  }
  
public:
  // called from sub threads (other than main thread)
  void TransferFinished(string destDir)
  {
    if(destDir == pwd_){// still showing contents of the same directory, and
      if(mediator_.FileSystemLookingAtRemoteFS(pwd_)){// it is remote one
        TryUpdate();
      }
    }
  }
  ////////////////////// drag and drop
}
