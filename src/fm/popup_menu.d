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

module fm.popup_menu;

private import gtk.Menu;
private import gtk.MenuItem;
private import gtk.SeparatorMenuItem;
private import gtk.CheckMenuItem;
private import gtk.PopupBox;
private import gtk.Widget;
private import gio.File;
private import gio.FileInfo;
private import gio.AppInfoIF;
private import gio.DesktopAppInfo;
private import glib.Str;
private import glib.ListG;
private import glib.GException;

private import tango.io.Stdout;
private import tango.sys.Environment;
private import tango.stdc.stdlib;
private import tango.stdc.posix.unistd;

private import utils.string_util;
private import constants;
private import rcfile = config.rcfile;
private import config.dialog;
private import scripts = config.nautilus_scripts;
private import fm.file_view;
private import fm.rename_dialog;
private import move_files_job;
private import input_dialog;


void LaunchApp(AppInfoIF appInfo, File f)
{
  ListG arg = ListG.alloc();
  arg.getListGStruct().data = f.getFileStruct();
  appInfo.launch(arg, null);
}


extern(C) void RightClickMenuPositioning(
  GtkMenu * menu, gint * x, gint * y,
  gboolean * pushIn, void * data)
{
  GdkRectangle * rect = cast(GdkRectangle*)data;
  *pushIn = 1;
  *x = rect.x + rect.width/2;
  *y = rect.y + rect.height*2;
}


class RightClickMenu : Menu
{
private:
  bool selectedOneIsDir_;
  File[] selectedFiles_;
  AppInfoIF[] defaultApps_;
  CheckMenuItem submenuItem_;
  bool setDefaultApp_ = false;
  string contentType_;
  Menu submenu_;
  ListG availableApps_;

  string pwd_;
  string nameCursor_;
  string[] selectedFileNames_;
  bool delegate(string) changeDir_;
  FileView view_;


public:
  this(
    FileView view,
    string pwd,
    string nameCursor,
    string[] selected,
    bool delegate(string) changeDir)
  {
    view_ = view;
    pwd_ = pwd;
    nameCursor_ = nameCursor;
    selectedFileNames_ = selected;
    changeDir_ = changeDir;
    bool parentIncluded = (selected.length > 0) && (selected[0] == PARENT_STRING);

    super();

    if(selectedFileNames_.length > 0){
      if(selectedFileNames_.length == 1){
        selectedFiles_.length = 1;
        defaultApps_.length = 1;

        selectedFiles_[0] = File.parseName(pwd ~ nameCursor_);
        FileInfo info = selectedFiles_[0].queryInfo("standard::content-type,access::can-execute", GFileQueryInfoFlags.NONE, null);
        contentType_ = info.getContentType();
        selectedOneIsDir_ = (contentType_ == "inode/directory");

        if((!selectedOneIsDir_) && info.getAttributeBoolean("access::can-execute")){
          append(new MenuItem(&ExecuteFun, "_Execute"));
        }

        defaultApps_[0] = DesktopAppInfo.getDefaultForType(contentType_, 0);
        if(defaultApps_[0] !is null){
          // button to open with default application
          append(new MenuItem(&OpenFun, "_Open (" ~ defaultApps_[0].getName() ~ ')'));

          // submenu to open with other applications
          availableApps_ = DesktopAppInfo.getAllForType(contentType_);
          if(availableApps_.length() > 1){
            submenuItem_ = new CheckMenuItem("Open _With (check to set as default)");
            append(submenuItem_);
            submenuItem_.addOnToggled(&SubmenuItemToggled);
            submenuItem_.addOnButtonPress(&SubmenuItemClicked);

            submenu_ = new Menu;
            submenuItem_.setSubmenu(submenu_);

            for(ListG node = availableApps_; node !is null; node = node.next()){
              auto appInfo = new DesktopAppInfo(cast(GDesktopAppInfo*)node.data());
              submenu_.append(new MenuItem(&OpenWithFun, appInfo.getName(), false));
            }

            submenu_.append(new SeparatorMenuItem);
            submenu_.append(new MenuItem(&OpenWithCommandFun, "Use custom command", false));
          }
        }
      }
      else{// selectedFileNames_.length > 1
        foreach(name; selectedFileNames_){
          auto file = File.parseName(pwd ~ name);
          auto info = file.queryInfo("standard::content-type", GFileQueryInfoFlags.NONE, null);
          string type = info.getContentType();
          if(type != "inode/directory"){
            auto app = DesktopAppInfo.getDefaultForType(type, 0);
            if(app !is null){
              selectedFiles_ ~= file;
              defaultApps_   ~= app;
            }
          }
        }
        if(selectedFiles_.length > 1){
          append(new MenuItem(&OpenAllFun, "Open _All"));
        }
      }
    }

    bool itemAboveIsSeparator = false;// to avoid double separator
    if(getChildren() !is null){
      append(new SeparatorMenuItem);
      itemAboveIsSeparator = true;
    }

    if((!parentIncluded) && selected.length > 0){
      append(new MenuItem(&CutFun, "Cut(_X)"));
      append(new MenuItem(&CopyFun, "_Copy"));
      itemAboveIsSeparator = false;
    }

    if(CanPaste()){
      append(new MenuItem(&PasteFun, "_Paste"));
      itemAboveIsSeparator = false;
    }

    if((getChildren() !is null) && (!itemAboveIsSeparator)){
      append(new SeparatorMenuItem);
    }

    if((!parentIncluded) && selected.length > 0){
      append(new MenuItem(&RenameFun, "_Rename"));
    }

    if((!parentIncluded) && selected.length != 0){
      append(new MenuItem(&DeleteFun!(true), "Move to _Trash"));
      append(new SeparatorMenuItem);
      // append(new MenuItem(&DeleteFun!(false), "_Delete"));
    }

    append(new MenuItem(&MkdirFun, "_Make directory"));

    // nautilus-scripts
    auto scriptsDir = scripts.GetScriptsDirTop();
    if(scriptsDir !is null){
      AppendScriptDirectory(this, scriptsDir);
    }

    append(new SeparatorMenuItem);
    if(selectedOneIsDir_){// only one entry is selected
      append(new MenuItem(&AddDirectoryShortcutFun, "_Add shortcut button"));
    }
    append(new MenuItem(&PreferenceDialogFun, "Pre_ferences"));

    showAll();
  }

private:
  void PreferenceDialogFun(MenuItem item)
  {
    StartConfigDialog();
  }

  void ExecuteFun(MenuItem item)
  {
    string command = selectedFiles_[0].getPath() ~ " & \0";
    system(command.ptr);
  }

  void OpenAllFun(MenuItem item)
  {
    for(int i=0; i<selectedFiles_.length; ++i){
      LaunchApp(defaultApps_[i], selectedFiles_[i]);
    }
  }

  void OpenFun(MenuItem item)
  {
    assert(defaultApps_[0] !is null);
    if(selectedOneIsDir_){// open a directory
      string fullpath = selectedFiles_[0].getPath() ~ '/';
      changeDir_(fullpath);
    }
    else{// open a file
      LaunchApp(defaultApps_[0], selectedFiles_[0]);
    }
  }

  void SubmenuItemToggled(CheckMenuItem)
  {
    submenuItem_.setActive(setDefaultApp_);
  }

  bool SubmenuItemClicked(GdkEventButton * eb, Widget w)
  {
    setDefaultApp_ = !setDefaultApp_;
    submenuItem_.setActive(setDefaultApp_);
    return false;
  }

  void OpenWithFun(MenuItem item)
  {
    string label = item.getLabel();
    ListG node = availableApps_;
    for(; node !is null; node = node.next()){
      GDesktopAppInfo * ptrAppInfo = cast(GDesktopAppInfo*)node.data();
      auto appInfo = new DesktopAppInfo(ptrAppInfo);
      if(appInfo.getName() == label){
        LaunchApp(appInfo, selectedFiles_[0]);
        if(setDefaultApp_){
          appInfo.setAsDefaultForType(contentType_);
        }
        break;
      }
    }
  }

  void OpenWithCommandFun(MenuItem item)
  {
    string command = InputDialog("", "command: ");
    if(command.length == 0){
      return;
    }

    string fullcommand = command ~ ' ' ~ pwd_ ~ selectedFileNames_[0] ~ " &\0";
    system(fullcommand.ptr);
  }

  void CutFun(MenuItem item) {PreparePaste(true,  pwd_, selectedFileNames_, view_);}
  void CopyFun(MenuItem item){PreparePaste(false, pwd_, selectedFileNames_, view_);}
  void PasteFun(MenuItem item){PasteFiles(pwd_);}

  void RenameFun(MenuItem item)
  {
    RenameFiles(pwd_, selectedFileNames_);
    view_.TryUpdate();
  }

  void DeleteFun(bool toTrash)(MenuItem item)
  {
    DeleteFiles!(toTrash)(pwd_, selectedFileNames_);
  }

  void MkdirFun(MenuItem item)
  {
    MakeDirectory(pwd_);
  }

  void AddDirectoryShortcutFun(MenuItem item)
  {
    string path = (nameCursor_ == "../" ? ParentDirectory(pwd_) : (pwd_ ~ nameCursor_));
    rcfile.AddDirectoryShortcut(path);
  }



  /////////////////// nautilus-scripts
  void AppendScriptDirectory(Menu m, scripts.ScriptsDir dir)
  {
    auto item = new MenuItem(RemoveSlash(dir.GetName()), false);
    m.append(item);
    auto submenu = new Menu;
    item.setSubmenu(submenu);
    if(dir.IsEmpty()){
      submenu.append(new MenuItem("<empty>"));
    }
    else{
      foreach(d; dir.dirs_){
        AppendScriptDirectory(submenu, d);
      }
      foreach(s; dir.scripts_){
        auto i = new MenuItemWithScript(RemoveSlash(s.GetName()), s.GetPath());
        i.addOnActivate(&LaunchNautilusScript);
        submenu.append(i);
      }
    }
  }

  void LaunchNautilusScript(MenuItem i)
  {
    auto item = cast(MenuItemWithScript)i;
    string scriptPath = item.path_ ~ '\0';

    // environment variables
    string[string] denv = Environment.get();
    char*[] envv;
    string[] keys = denv.keys;
    foreach(key; keys){
      envv ~= Str.toStringz(key ~ '=' ~ denv[key]);
    }

    // environment variables specific to nautilus-scripts
    string currentURI = "NAUTILUS_SCRIPT_CURRENT_URI=file://" ~ RemoveSlash(pwd_) ~ '\0';

    string selectedFilePaths = "NAUTILUS_SCRIPT_SELECTED_FILE_PATHS=";
    string selectedURIs = "NAUTILUS_SCRIPT_SELECTED_URIS=";
    foreach(name; selectedFileNames_){
      string fullpath = pwd_ ~ name;
      selectedFilePaths ~= fullpath ~ '\n';
      selectedURIs      ~= "file://" ~ fullpath ~ '\n';
    }
    selectedFilePaths ~= '\0';
    selectedURIs      ~= '\0';

    envv ~= currentURI.ptr;
    envv ~= selectedFilePaths.ptr;
    envv ~= selectedURIs.ptr;
    envv ~= null;

    // arguments
    char*[] argv;
    foreach(name; selectedFileNames_){
      argv ~= Str.toStringz(name);
    }
    argv ~= null;

    // fork-exec
    pid_t p = fork();
    if(p == 0){// child process
      chdir(Str.toStringz(pwd_));
      execve(scriptPath.ptr, argv.ptr, envv.ptr);
    }
  }

  class MenuItemWithScript : MenuItem
  {
    string path_;
    this(string label, string path)
    {
      super(label, false);
      path_ = path;
    }
  }
  /////////////////// nautilus-scripts
}


void MakeDirectory(string pwd)
{
  string dirname = InputDialog("mkdir", "new directory: ");
  if(dirname.length > 0){// valid input
    string absname = pwd ~ dirname;
    File newdir = File.parseName(absname);
    if(newdir.queryExists(null)){
      PopupBox.error(dirname ~ " exists.", "error");
    }
    else{
      try{
        newdir.makeDirectory(null);
      }
      catch(GException ex){
        PopupBox.error(ex.toString(), "error");
      }
    }
  }
}


void DeleteFiles(bool toTrash)(string pwd, string[] names)
{
  if(names.length > 0){
    try{
      foreach(name; names){
        File f = File.parseName(pwd ~ name);
        static if(toTrash){
          f.trash(null);
        }
        else{
          f.delet(null);
        }
      }
    }
    catch(GException ex){
      PopupBox.error(ex.toString(), "error");
    }
  }
}

alias DeleteFiles!(true) MoveToTrash;

