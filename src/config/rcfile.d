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

module config.rcfile;

import std.string;
import std.array;
import std.algorithm;
import std.process;

import glib.KeyFile;
import gtk.PopupBox;
import gdk.Color;
import gio.File;
import gio.FileOutputStream;
import glib.Str;

import utils.min_max;
import utils.gio_util;
import utils.string_util;
import constants;
import config.shellrc;
import config.nautilus_scripts;
import config.keybind;
import known_hosts = config.known_hosts;
import ssh_connection;
import page_list;


static const string SetaVersion = "0.6.3";

void Init()
{
  instance_ = new SetaRCFile();
}

void Write()
{
  instance_.Write();
}

void Free()
{
  instance_.Write();
  instance_.free();
}



private template GetString(string group, string key)
{
  const string GetString =
    "string Get" ~ key ~ "(){return instance_.getString(\"" ~ group ~ "\", \"" ~ key ~ "\");}";
}


///////////////// [Layout]
private template GetUint(string key)
{
  const string GetUint =
    "uint Get" ~ key ~ "(){return ForceUint(instance_.getInteger(\"Layout\", \"" ~ key ~ "\"));}";
}
private template GetBoolean(string key)
{
  const string GetBoolean =
    "bool Get" ~ key ~ "(){return instance_.getBoolean(\"Layout\", \"" ~ key ~ "\") != 0;}";
}
mixin(GetUint!("WindowSizeH"));
mixin(GetUint!("WindowSizeV"));
mixin(GetUint!("SplitH"));
mixin(GetUint!("SplitVLeft"));
mixin(GetUint!("SplitVRight"));

mixin(GetBoolean!("ShowBackButton"));
mixin(GetBoolean!("ShowForwardButton"));
mixin(GetBoolean!("ShowUpButton"));
mixin(GetBoolean!("ShowRootButton"));
mixin(GetBoolean!("ShowHomeButton"));
mixin(GetBoolean!("ShowOtherSideButton"));
mixin(GetBoolean!("ShowRefreshButton"));
mixin(GetBoolean!("ShowSSHButton"));
mixin(GetBoolean!("ShowHiddenButton"));
mixin(GetBoolean!("ShowDirTreeButton"));
mixin(GetBoolean!("ShowFilter"));

mixin(GetUint!("WidthShortcutButton"));
mixin(GetUint!("WidthFilterEntry"));
mixin(GetUint!("WidthDirectoryTree"));
mixin(GetUint!("WidthType"));
mixin(GetUint!("WidthSize"));
mixin(GetUint!("WidthOwner"));
mixin(GetUint!("WidthPermissions"));
mixin(GetUint!("WidthLastModified"));

uint[] GetWidths()
{
  int widthName = Max(10,
                      instance_.getInteger("Layout", "SplitH") - 40 -
                      instance_.getInteger("Layout", "WidthDirectoryTree") -
                      instance_.getInteger("Layout", "WidthType") -
                      instance_.getInteger("Layout", "WidthSize") -
                      instance_.getInteger("Layout", "WidthOwner") -
                      instance_.getInteger("Layout", "WidthPermissions") -
                      instance_.getInteger("Layout", "WidthLastModified"));
  return [
    ForceUint(widthName),
    ForceUint(instance_.getInteger("Layout", "WidthType")),
    ForceUint(instance_.getInteger("Layout", "WidthSize")),
    ForceUint(instance_.getInteger("Layout", "WidthOwner")),
    ForceUint(instance_.getInteger("Layout", "WidthPermissions")),
    ForceUint(instance_.getInteger("Layout", "WidthLastModified"))
    ];
}
mixin(GetUint!("HeightStatusbar"));

string[] GetRowColors()
{
  return [instance_.getString("Layout", "ColorDirectory"),
          instance_.getString("Layout", "ColorFile"),
          instance_.getString("Layout", "ColorSymlink"),
          instance_.getString("Layout", "ColorExecutable")];
}
mixin(GetString!("Layout", "ColorDirectory"));
mixin(GetString!("Layout", "ColorFile"));
mixin(GetString!("Layout", "ColorSymlink"));
mixin(GetString!("Layout", "ColorExecutable"));

mixin(GetBoolean!("UseDesktopNotification"));
mixin(GetUint!("NotifyExpiresInMSec"));
///////////////// [Layout]



///////////////// [Terminal]
mixin(GetString!("Terminal", "ColorForeground"));
mixin(GetString!("Terminal", "ColorBackground"));
mixin(GetString!("Terminal", "Font"));
mixin(GetString!("Terminal", "PROMPT"));
mixin(GetString!("Terminal", "RPROMPT"));
mixin(GetString!("Terminal", "ReplaceTargetLeft"));
mixin(GetString!("Terminal", "ReplaceTargetRight"));
double GetTransparency(){return instance_.getDouble("Terminal", "BackgroundTransparency");}
bool GetEnablePathExpansion(){return instance_.getBoolean("Terminal", "EnablePathExpansion") != 0;}

mixin(GetString!("Terminal", "UserDefinedText1"));
mixin(GetString!("Terminal", "UserDefinedText2"));
mixin(GetString!("Terminal", "UserDefinedText3"));
mixin(GetString!("Terminal", "UserDefinedText4"));
mixin(GetString!("Terminal", "UserDefinedText5"));
mixin(GetString!("Terminal", "UserDefinedText6"));
mixin(GetString!("Terminal", "UserDefinedText7"));
mixin(GetString!("Terminal", "UserDefinedText8"));
mixin(GetString!("Terminal", "UserDefinedText9"));
string GetUserDefinedText(int index)
{
  string key = "UserDefinedText" ~ Str.toString(index);
  return instance_.getString("Terminal", key);
}
///////////////// [Terminal]



///////////////// [Directories]
private const string SeparatorShortcutList = "_///_";
private const string SeparatorShortcut = "_//_";

string[] GetInitialDirectoriesLeft (){return instance_.getStringList("Directories", "InitialDirectoriesLeft");}
string[] GetInitialDirectoriesRight(){return instance_.getStringList("Directories", "InitialDirectoriesRight");}
string GetInitialDirectoryLeft (){return GetInitialDirectoriesLeft ()[0];}
string GetInitialDirectoryRight(){return GetInitialDirectoriesRight()[0];}

struct Shortcut
{
  string label_, path_;
  string toString()
  {
    return label_ ~ SeparatorShortcut ~ path_;
  }
  bool opEquals(Shortcut * rhs)
  {
    return label_ == rhs.label_ && path_ == rhs.path_;
  }
  bool Parse(string s)
  {
    string[] l = s.split(SeparatorShortcut);
    if(l.length == 1){// path only
      if(DirectoryExists(l[0])){
        label_ = GetBasename(l[0]);
        path_ = l[0];
        return true;
      }
    }
    else if(l.length == 2){// label and path
      if(DirectoryExists(l[1])){
        label_ = l[0];
        path_ = l[1];
        return true;
      }
    }
    return false;
  }
}

Shortcut[] GetShortcuts()
{
  if(instance_.hasKey("Directories", "Shortcuts")){
    string contents = instance_.getString("Directories", "Shortcuts");
    string[] list = contents.split(SeparatorShortcutList);

    Shortcut[] ret;
    foreach(s; list){
      Shortcut temp;
      if(temp.Parse(s)){
        ret ~= temp;
      }
    }

    return ret;
  }
  else{
    return null;
  }
}

string GetNthShortcut(uint n)
{
  Shortcut[] shortcuts = GetShortcuts();
  if(n < shortcuts.length){
    return shortcuts[n].path_;
  }
  else{
    return null;
  }
}

void AddDirectoryShortcut(string path)
{
  instance_.changed_ = true;

  Shortcut[] list = GetShortcuts();
  list ~= Shortcut(GetBasename(path), path);
  ResetShortcuts(list);
}

void RemoveDirectoryShortcut(string path)
{
  instance_.changed_ = true;

  if(instance_.hasKey("Directories", "Shortcuts")){
    Shortcut[] old = GetShortcuts();
    Shortcut[] list;
    foreach(shortcut; old){
      if(shortcut.path_ != path){
        list ~= shortcut;
      }
    }
    ResetShortcuts(list);
  }
}

void ResetShortcuts(Shortcut[] list)
{
  Shortcut[] old = GetShortcuts();

  bool same = list.length == old.length;
  if(same){
    foreach(i, l; list){
      if(!l.opEquals(&old[i])){
        same = false;
        break;
      }
    }
  }

  if(!same){
    string s = ToStringArray(list).join(SeparatorShortcutList);
    instance_.setString("Directories", "Shortcuts", NonnullString(s));
    instance_.changed_ = true;
    page_list.NotifyReconstructShortcuts();
  }
}
///////////////// [Directories]



///////////////// [SSH]
string GetSSHOption(){return instance_.getString("SSH", "SSHOption");}

string[] GetSSHHosts()
{
  return instance_.GetSSHHosts();
}

void AddSSHHost(SSHConnection con)
{
  instance_.changed_ = true;

  string s = con.toStr!(true)();
  if(instance_.hasKey("SSH", "Hosts")){
    string older = instance_.getString("SSH", "Hosts");
    string newer = (trim(older).split(",") ~ s).join(",");
    instance_.setString("SSH", "Hosts", newer);
  }
  else{
    instance_.setString("SSH", "Hosts", s);
  }
}

void RemoveSSHHost(SSHConnection con)
{
  instance_.changed_ = true;

  known_hosts.Unregister(con);
  if(instance_.hasKey("SSH", "Hosts")){
    string s1 = con.toStr!(true)();
    string s2 = con.toStr!(false)();

    string older = instance_.getString("SSH", "Hosts");
    string[] hosts = split(older, ",");
    string[] newhosts;
    foreach(host; hosts){
      host = trim(host);
      scope con2 = new SSHConnection(host);
      if(!con2.Equals(con)){
        newhosts ~= host;
      }
    }
    string newer = join(newhosts, ",");
    instance_.setString("SSH", "Hosts", newer);
  }
}

void ResetRemoteHosts(string[] list)
{
  if(instance_.getStringList("SSH", "Hosts") != list){// has different value
    string s = join(list, ",");
    instance_.setString("SSH", "Hosts", NonnullString(s));
    instance_.changed_ = true;
    known_hosts.Register(list);
  }
}
///////////////// [SSH]



///////////////// [Keybind]
KeyCode[][string] GetKeybinds(){return instance_.dictKeybind_;}

bool ResetKeybind(string keyname, string[] codeList)
{
  string codes = join(codeList, ",");
  return ResetStringz("Keybind", keyname, codes);
}

void ReconstructKeybinds()
{
  instance_.InstallKeybinds();
  config.keybind.Init();
}

private template GetKeybindInString(string widget, string action)
{
  const string GetKeybindInString =
    "string Get" ~ action ~ "(){return instance_.getString(\"Keybind\", \"" ~ widget ~ "Action." ~ action ~ "\");}";
}

mixin(GetKeybindInString!("Terminal", "InputUserDefinedText1"));
mixin(GetKeybindInString!("Terminal", "InputUserDefinedText2"));
mixin(GetKeybindInString!("Terminal", "InputUserDefinedText3"));
mixin(GetKeybindInString!("Terminal", "InputUserDefinedText4"));
mixin(GetKeybindInString!("Terminal", "InputUserDefinedText5"));
mixin(GetKeybindInString!("Terminal", "InputUserDefinedText6"));
mixin(GetKeybindInString!("Terminal", "InputUserDefinedText7"));
mixin(GetKeybindInString!("Terminal", "InputUserDefinedText8"));
mixin(GetKeybindInString!("Terminal", "InputUserDefinedText9"));
///////////////// [Keybind]



private __gshared SetaRCFile instance_;

class SetaRCFile : KeyFile
{
private:
  bool changed_;
  string filename_;
  KeyCode[][string] dictKeybind_;

  this()
  {
    super();
    setListSeparator(',');

    changed_ = false;
    filename_ = getenv("HOME") ~ "/.setarc";
    bool exist = Exists(filename_);
    if(exist){
      loadFromFile(filename_, GKeyFileFlags.KEEP_COMMENTS);

      size_t len;
      if(getGroups(len) == ["Version", "Layout", "Terminal", "Directories", "SSH", "Keybind"]){
        if(getString("Version", "Version") != SetaVersion){// .setarc is old
          changed_ = true;
          setString("Version", "Version", SetaVersion);
        }
      }
      else{// .setarc is old (<= 0.4.0) or there's something wrong with .setarc
        loadFromData(defaultContents, defaultContents.length, GKeyFileFlags.KEEP_COMMENTS);
        changed_ = true;
        PopupBox.information("Your configuration file may be older than the application or may be broken.\nStarts with default settings.", "");
      }
    }
    else{
      loadFromData(defaultContents, defaultContents.length, GKeyFileFlags.KEEP_COMMENTS);
      changed_ = true;
    }

    // fill default values
    // [Layout]
    mixin(SetDefaultValue!("Integer", "Layout", "WindowSizeH", "1600"));
    mixin(SetDefaultValue!("Integer", "Layout", "WindowSizeV", "900"));
    mixin(SetDefaultValue!("Integer", "Layout", "SplitH",      "800"));
    mixin(SetDefaultValue!("Integer", "Layout", "SplitVLeft",  "450"));
    mixin(SetDefaultValue!("Integer", "Layout", "SplitVRight", "450"));

    mixin(SetDefaultValue!("Boolean", "Layout", "ShowBackButton", "true"));
    mixin(SetDefaultValue!("Boolean", "Layout", "ShowForwardButton", "true"));
    mixin(SetDefaultValue!("Boolean", "Layout", "ShowUpButton", "true"));
    mixin(SetDefaultValue!("Boolean", "Layout", "ShowRootButton", "true"));
    mixin(SetDefaultValue!("Boolean", "Layout", "ShowHomeButton", "true"));
    mixin(SetDefaultValue!("Boolean", "Layout", "ShowOtherSideButton", "true"));
    mixin(SetDefaultValue!("Boolean", "Layout", "ShowRefreshButton", "true"));
    mixin(SetDefaultValue!("Boolean", "Layout", "ShowSSHButton", "true"));
    mixin(SetDefaultValue!("Boolean", "Layout", "ShowHiddenButton", "true"));
    mixin(SetDefaultValue!("Boolean", "Layout", "ShowDirTreeButton", "true"));
    mixin(SetDefaultValue!("Boolean", "Layout", "ShowFilter", "true"));

    mixin(SetDefaultValue!("Integer", "Layout", "WidthFilterEntry",    "120"));
    mixin(SetDefaultValue!("Integer", "Layout", "WidthShortcutButton", "80"));
    mixin(SetDefaultValue!("Integer", "Layout", "WidthDirectoryTree",  "0"));

    mixin(SetDefaultValue!("Integer", "Layout", "WidthType", "120"));
    mixin(SetDefaultValue!("Integer", "Layout", "WidthSize", "70"));
    mixin(SetDefaultValue!("Integer", "Layout", "WidthOwner", "70"));
    mixin(SetDefaultValue!("Integer", "Layout", "WidthPermissions", "85"));
    mixin(SetDefaultValue!("Integer", "Layout", "WidthLastModified", "125"));

    mixin(SetDefaultValue!("Integer", "Layout", "HeightStatusbar", "20"));

    mixin(SetDefaultValue!("String", "Layout", "ColorDirectory",  "\"#0000FF\""));
    mixin(SetDefaultValue!("String", "Layout", "ColorFile",       "\"#000000\""));
    mixin(SetDefaultValue!("String", "Layout", "ColorSymlink",    "\"#20B0E0\""));
    mixin(SetDefaultValue!("String", "Layout", "ColorExecutable", "\"#228B22\""));

    mixin(SetDefaultValue!("Boolean", "Layout", "UseDesktopNotification", "false"));
    mixin(SetDefaultValue!("Integer", "Layout", "NotifyExpiresInMSec", "3000"));

    // [Terminal]
    GdkColor colorTest;
    if(!hasKey("Terminal", "ColorForeground") ||
       !Color.parse(getString("Terminal", "ColorForeground"), colorTest)){
      setString("Terminal", "ColorForeground", "#000000");
    }
    if(!hasKey("Terminal", "ColorBackground") ||
       !Color.parse(getString("Terminal", "ColorBackground"), colorTest)){
      setString("Terminal", "ColorBackground", "#ffffff");
    }
    mixin(SetDefaultValue!("String", "Terminal", "Font", "\"Monospace 11\""));
    mixin(SetDefaultValue!("Double", "Terminal", "BackgroundTransparency", "0.0"));
    mixin(SetDefaultValue!("String", "Terminal", "PROMPT", "getenv(\"USER\") ~ \"@\""));
    mixin(SetDefaultValue!("String", "Terminal", "RPROMPT", "\"\""));

    mixin(SetDefaultValue!("Boolean","Terminal", "EnablePathExpansion", "true"));
    mixin(SetDefaultValue!("String", "Terminal", "ReplaceTargetLeft" , "\"$L<n>DIR\""));
    mixin(SetDefaultValue!("String", "Terminal", "ReplaceTargetRight", "\"$R<n>DIR\""));

    mixin(SetDefaultValue!("String", "Terminal", "UserDefinedText1", "\"\""));
    mixin(SetDefaultValue!("String", "Terminal", "UserDefinedText2", "\"\""));
    mixin(SetDefaultValue!("String", "Terminal", "UserDefinedText3", "\"\""));
    mixin(SetDefaultValue!("String", "Terminal", "UserDefinedText4", "\"\""));
    mixin(SetDefaultValue!("String", "Terminal", "UserDefinedText5", "\"\""));
    mixin(SetDefaultValue!("String", "Terminal", "UserDefinedText6", "\"\""));
    mixin(SetDefaultValue!("String", "Terminal", "UserDefinedText7", "\"\""));
    mixin(SetDefaultValue!("String", "Terminal", "UserDefinedText8", "\"\""));
    mixin(SetDefaultValue!("String", "Terminal", "UserDefinedText9", "\"\""));

    // [Directories]
    // check if entry is an existing directory
    InitInitialDirectories("InitialDirectoriesLeft");
    InitInitialDirectories("InitialDirectoriesRight");

    mixin(SetDefaultValue!("String", "Directories", "Shortcuts", "\"\""));

    // [SSH]
    mixin(SetDefaultValue!("String", "SSH", "Hosts", "\"\""));
    mixin(SetDefaultValue!("String", "SSH", "SSHOption", "\"-X\""));

    // [Keybind]
    InstallKeybinds();

    // register SSH hosts
    known_hosts.Register(GetSSHHosts());
  }

  void Write()
  {
    if(changed_){
      changed_ = false;

      // "scope" storage-class specifier is necessary to remove segfault at shutdown of Seta
      scope File f = File.parseName(filename_);
      scope FileOutputStream fs = f.replace(null, 1, GFileCreateFlags.NONE, null);
      size_t len;
      char[] contents = cast(char[]) toData(len);
      fs.writeAll(contents.ptr, contents.length, &len, null);
      fs.close(null);
    }
  }

  void InstallKeybinds()
  {
    mixin(InstallKeybind!("MainWindowAction.CreateNewPage"      , "<Alt>t,<Shift><Control>t"));
    mixin(InstallKeybind!("MainWindowAction.MoveToNextPage"     , "<Alt>m,<Shift><Control>m,<Control>Tab,<Shift><Control>greater"));
    mixin(InstallKeybind!("MainWindowAction.MoveToPreviousPage" , "<Shift><Control>Tab,<Shift><Control>less"));
    mixin(InstallKeybind!("MainWindowAction.SwitchViewMode"     , "<Shift><Control>x"));
    mixin(InstallKeybind!("MainWindowAction.CloseThisPage"      , "<Shift><Control>d"));
    mixin(InstallKeybind!("MainWindowAction.MoveFocusUp"        , "<Shift><Control>k"));
    mixin(InstallKeybind!("MainWindowAction.MoveFocusDown"      , "<Shift><Control>j"));
    mixin(InstallKeybind!("MainWindowAction.MoveFocusLeft"      , "<Shift><Control>h"));
    mixin(InstallKeybind!("MainWindowAction.MoveFocusRight"     , "<Shift><Control>l"));
    mixin(InstallKeybind!("MainWindowAction.ExpandLeftPane"     , "<Shift><Control>Left"));
    mixin(InstallKeybind!("MainWindowAction.ExpandRightPane"    , "<Shift><Control>Right"));
    mixin(InstallKeybind!("MainWindowAction.ShowChangeDirDialog", "<Shift><Control>plus"));
    mixin(InstallKeybind!("MainWindowAction.ShowConfigDialog"   , "<Shift><Control>Escape"));
    mixin(InstallKeybind!("MainWindowAction.ToggleFullscreen"   , "F11"));
    mixin(InstallKeybind!("MainWindowAction.QuitApplication"    , "<Shift><Control>q"));

    mixin(InstallKeybind!("FileManagerAction.GoToPrevious"    , "<Alt>b,<Shift><Control>b,<Alt>Left"));
    mixin(InstallKeybind!("FileManagerAction.GoToNext"        , "<Alt>f,<Alt>Right"));
    mixin(InstallKeybind!("FileManagerAction.GoToParent"      , "<Alt>p,<Shift><Control>p,<Alt>Up"));
    mixin(InstallKeybind!("FileManagerAction.GoToRoot"        , "<Alt>r"));
    mixin(InstallKeybind!("FileManagerAction.GoToHome"        , "<Alt>h"));
    mixin(InstallKeybind!("FileManagerAction.GoToDirOtherSide", "<Alt>o,<Shift><Control>o"));
    mixin(InstallKeybind!("FileManagerAction.Refresh"         , "F5"));
    mixin(InstallKeybind!("FileManagerAction.StartSSH"        , "<Alt>s,<Shift><Control>s"));
    mixin(InstallKeybind!("FileManagerAction.ShowHidden"      , "<Alt>period"));
    mixin(InstallKeybind!("FileManagerAction.ShowDirTree"     , "<Alt>semicolon"));
    mixin(InstallKeybind!("FileManagerAction.SyncTerminalPWD" , "<Alt>c,<Shift><Control>c"));
    mixin(InstallKeybind!("FileManagerAction.GoToChild"       , "<Alt>n,<Shift><Control>n,<Alt>Down"));
    mixin(InstallKeybind!("FileManagerAction.GoToDir1"        , "<Alt>1"));
    mixin(InstallKeybind!("FileManagerAction.GoToDir2"        , "<Alt>2"));
    mixin(InstallKeybind!("FileManagerAction.GoToDir3"        , "<Alt>3"));
    mixin(InstallKeybind!("FileManagerAction.GoToDir4"        , "<Alt>4"));
    mixin(InstallKeybind!("FileManagerAction.GoToDir5"        , "<Alt>5"));
    mixin(InstallKeybind!("FileManagerAction.GoToDir6"        , "<Alt>6"));
    mixin(InstallKeybind!("FileManagerAction.GoToDir7"        , "<Alt>7"));
    mixin(InstallKeybind!("FileManagerAction.GoToDir8"        , "<Alt>8"));
    mixin(InstallKeybind!("FileManagerAction.GoToDir9"        , "<Alt>9"));

    mixin(InstallKeybind!("FileViewAction.SelectAll"    , "<Control>a"));
    mixin(InstallKeybind!("FileViewAction.UnselectAll"  , "<Control>g"));
    mixin(InstallKeybind!("FileViewAction.SelectRow"    , "space,<Control>space"));
    mixin(InstallKeybind!("FileViewAction.Cut"          , "<Control>x"));
    mixin(InstallKeybind!("FileViewAction.Copy"         , "<Control>c"));
    mixin(InstallKeybind!("FileViewAction.Paste"        , "<Control>v"));
    mixin(InstallKeybind!("FileViewAction.PopupMenu"    , "<Control>Return"));
    mixin(InstallKeybind!("FileViewAction.Rename"       , "F6"));
    mixin(InstallKeybind!("FileViewAction.MakeDirectory", "F7"));
    mixin(InstallKeybind!("FileViewAction.MoveToTrash"  , "F8"));
    mixin(InstallKeybind!("FileViewAction.FocusFilter"  , "<Control>f"));
    mixin(InstallKeybind!("FileViewAction.ClearFilter"  , "<Shift><Control>f"));

    mixin(InstallKeybind!("TerminalAction.ScrollUp"      , "<Shift><Control>p"));
    mixin(InstallKeybind!("TerminalAction.ScrollDown"    , "<Shift><Control>n"));
    mixin(InstallKeybind!("TerminalAction.Copy"          , "<Shift><Control>c"));
    mixin(InstallKeybind!("TerminalAction.Paste"         , "<Shift><Control>v"));
    mixin(InstallKeybind!("TerminalAction.PasteFilePaths", "<Shift><Control>y"));
    mixin(InstallKeybind!("TerminalAction.FindRegexp"    , "<Shift><Control>f"));
    mixin(InstallKeybind!("TerminalAction.SyncFilerPWD"  , "<Alt>c"));
    mixin(InstallKeybind!("TerminalAction.InputPWDLeft"  , "<Shift><Control>braceleft"));
    mixin(InstallKeybind!("TerminalAction.InputPWDRight" , "<Shift><Control>braceright"));
    mixin(InstallKeybind!("TerminalAction.InputUserDefinedText1", "<Alt>1"));
    mixin(InstallKeybind!("TerminalAction.InputUserDefinedText2", "<Alt>2"));
    mixin(InstallKeybind!("TerminalAction.InputUserDefinedText3", "<Alt>3"));
    mixin(InstallKeybind!("TerminalAction.InputUserDefinedText4", "<Alt>4"));
    mixin(InstallKeybind!("TerminalAction.InputUserDefinedText5", "<Alt>5"));
    mixin(InstallKeybind!("TerminalAction.InputUserDefinedText6", "<Alt>6"));
    mixin(InstallKeybind!("TerminalAction.InputUserDefinedText7", "<Alt>7"));
    mixin(InstallKeybind!("TerminalAction.InputUserDefinedText8", "<Alt>8"));
    mixin(InstallKeybind!("TerminalAction.InputUserDefinedText9", "<Alt>9"));
  }

  void InitInitialDirectories(string key)
  {
    string[] initialDirs;
    if(hasKey("Directories", key)){
      auto dirs = getStringList("Directories", key);
      auto existingDirs = dirs.map!(trim).map!(AppendSlash).filter!(CanEnumerateChildren);
      initialDirs = array(existingDirs);
      if(dirs != initialDirs){
        changed_ = true;
        setStringList("Directories", key, initialDirs);
      }
    }
    if(initialDirs.length == 0){
      changed_ = true;
      setStringList("Directories", key, [AppendSlash(getenv("HOME"))]);
    }
  }

  string[] getStringList(string group, string key)
  {
    if(hasKey(group, key)){
      size_t len;
      return super.getStringList(group, key, len);
    }
    return null;
  }

  string[] GetSSHHosts()
  {
    return getStringList("SSH", "Hosts");
  }
}


private template SetDefaultValue(string Type, string group, string key, string value)
{
  const string SetDefaultValue =
    "
    if(!hasKey(\"" ~ group ~ "\", \"" ~ key ~ "\")){
      changed_ = true;
      set" ~ Type ~ "(\"" ~ group ~ "\", \"" ~ key ~ "\", " ~ value ~ ");
    }";
}

private template InstallKeybind(string action, string keystr)
{
  const string InstallKeybind =
    SetDefaultValue!("String", "Keybind", action, "\"" ~ keystr ~ "\"") ~
    "{
      string val = getString(\"Keybind\", \"" ~ action ~ "\");
      KeyCode[] array = ParseKeyCodeList(val, " ~ action ~ ");
      if(array.length > 0){
        dictKeybind_[\"" ~ action ~ "\"] = array;
      }
    }";
}


/////////////////// for ConfigDialog
private template ResetValue(string type, string Type)
{
  const string ResetValue =
    "
    bool Reset" ~ Type ~ "(string group, string key, " ~ type ~ " val)
    {
      if(instance_.get" ~ Type ~ "(group, key) == val){// has the same value
        return false;
      }
      else{
        instance_.set" ~ Type ~ "(group, key, val);
        instance_.changed_ = true;
        return true;
      }
    }";
}

mixin(ResetValue!("int", "Integer"));
mixin(ResetValue!("bool", "Boolean"));
mixin(ResetValue!("double", "Double"));
mixin(ResetValue!("string[]", "StringList"));
mixin("private " ~ ResetValue!("string", "String"));// use ResetStringz instead

bool ResetStringz(string group, string key, string val)
{
  return ResetString(group, key, NonnullString(val));
}
/////////////////// for ConfigDialog



private uint ForceUint(int i)
{
  return i < 0 ? 0 : i;
}


private const string defaultContents =
  "###################### configuration file for Seta

[Version]
Version=" ~ SetaVersion ~ "



[Layout]
### Sizes of main widgets
WindowSizeH=1600
WindowSizeV=900
SplitH=800
SplitVLeft=450
SplitVRight=450

ShowBackButton=true
ShowForwardButton=true
ShowUpButton=true
ShowRootButton=true
ShowHomeButton=true
ShowOtherSideButton=true
ShowRefreshButton=true
ShowSSHButton=true
ShowHiddenButton=true
ShowDirTreeButton=true
ShowFilter=true

WidthShortcutButton=80
WidthFilterEntry=120
WidthDirectoryTree=0

### Widths of columns in filer (columns whose width=0 will not be shown)
WidthType=120
WidthSize=70
WidthOwner=70
WidthPermissions=85
WidthLastModified=125

HeightStatusbar=20

ColorDirectory=#0000FF
ColorFile=#000000
ColorSymlink=#20B0E0
ColorExecutable=#228B22

UseDesktopNotification=false
NotifyExpiresInMSec=3000


[Terminal]
### Colors are specified by hex integers in the form '#rgb', '#rrggbb',
### '#rrrgggbbb' or '#rrrrggggbbbb' where 'r', 'g' and 'b' are hex digits
### of the red, green and blue components of the color, respectively.
### For example #000000 is black, #ff0000 red and #00ff00 green)
ColorForeground=#ffffff
ColorBackground=#000000

### Font to be used in terminal
Font=Monospace 11

### Transparency of terminal background, 0.0 (opaque) to 1.0 (transparent)
BackgroundTransparency=0.3

### Hints for Seta to extract argument for \"cd\" command which is used for synchronization of directory
# PROMPT <username>@<machine name>
# RPROMPT (for zsh users, currently only first and last chars are used, others are ignored)

EnablePathExpansion=true
ReplaceTargetLeft=$L<n>DIR
ReplaceTargetRight=$R<n>DIR

UserDefinedText1=
UserDefinedText2=
UserDefinedText3=
UserDefinedText4=
UserDefinedText5=
UserDefinedText6=
UserDefinedText7=
UserDefinedText8=
UserDefinedText9=



[Directories]
# InitialDirectoriesLeft(Right)=/home/xxx/, ...
# Shortcuts=[<label for directory1>_//_]<path to directory1>, ...
Shortcuts=



[SSH]
# Hosts=<username1>:<URL of host1>:<path to home directory>:<PROMPT of default shell>:<RPROMPT (if zsh)>, ...
Hosts=

# command-line option for SSH
SSHOption=-X



[Keybind]
### Key codes are expressed as \"modifiers\" and \"key values\"
### key values are defined in \"/usr/include/gtk-2.0/gdk/gdkkeysyms.h\" with prefix \"GDK_\"
MainWindowAction.CreateNewPage=<Alt>t,<Shift><Control>t
MainWindowAction.MoveToNextPage=<Alt>m,<Shift><Control>m,<Control>Tab,<Shift><Control>greater
MainWindowAction.MoveToPreviousPage=<Shift><Control>Tab,<Shift><Control>less
MainWindowAction.SwitchViewMode=<Shift><Control>x
MainWindowAction.CloseThisPage=<Shift><Control>d
MainWindowAction.MoveFocusUp=<Shift><Control>k
MainWindowAction.MoveFocusDown=<Shift><Control>j
MainWindowAction.MoveFocusLeft=<Shift><Control>h
MainWindowAction.MoveFocusRight=<Shift><Control>l
MainWindowAction.ExpandLeftPane=<Shift><Control>Left
MainWindowAction.ExpandRightPane=<Shift><Control>Right
MainWindowAction.ShowChangeDirDialog=<Shift><Control>plus
MainWindowAction.ShowConfigDialog=<Shift><Control>Escape
MainWindowAction.ToggleFullscreen=F11
MainWindowAction.QuitApplication=<Shift><Control>q

FileManagerAction.GoToPrevious=<Alt>b,<Shift><Control>b,<Alt>Left
FileManagerAction.GoToNext=<Alt>f,<Alt>Right
FileManagerAction.GoToParent=<Alt>p,<Shift><Control>p,<Alt>Up
FileManagerAction.GoToRoot=<Alt>r
FileManagerAction.GoToHome=<Alt>h
FileManagerAction.GoToDirOtherSide=<Alt>o,<Shift><Control>o
FileManagerAction.Refresh=F5
FileManagerAction.StartSSH=<Alt>s,<Shift><Control>s
FileManagerAction.ShowHidden=<Alt>period
FileManagerAction.ShowDirTree=<Alt>semicolon
FileManagerAction.SyncTerminalPWD=<Alt>c,<Shift><Control>c
FileManagerAction.GoToChild=<Alt>n,<Shift><Control>n,<Alt>Down
FileManagerAction.GoToDir1=<Alt>1
FileManagerAction.GoToDir2=<Alt>2
FileManagerAction.GoToDir3=<Alt>3
FileManagerAction.GoToDir4=<Alt>4
FileManagerAction.GoToDir5=<Alt>5
FileManagerAction.GoToDir6=<Alt>6
FileManagerAction.GoToDir7=<Alt>7
FileManagerAction.GoToDir8=<Alt>8
FileManagerAction.GoToDir9=<Alt>9

FileViewAction.SelectAll=<Control>a
FileViewAction.UnselectAll=<Control>g
FileViewAction.SelectRow=space,<Control>space
FileViewAction.Cut=<Control>x,<Shift><Control>x
FileViewAction.Copy=<Control>c,<Shift><Control>c
FileViewAction.Paste=<Control>v
FileViewAction.PopupMenu=<Control>Return
FileViewAction.Rename=F6
FileViewAction.MakeDirectory=F7
FileViewAction.MoveToTrash=F8
FileViewAction.FocusFilter=<Control>f
FileViewAction.ClearFilter=<Shift><Control>f

TerminalAction.ScrollUp=<Shift><Control>p
TerminalAction.ScrollDown=<Shift><Control>n
TerminalAction.Copy=<Shift><Control>c
TerminalAction.Paste=<Shift><Control>v
TerminalAction.PasteFilePaths=<Shift><Control>y
TerminalAction.FindRegexp=<Shift><Control>f
TerminalAction.SyncFilerPWD=<Alt>c
TerminalAction.InputPWDLeft=<Shift><Control>braceleft
TerminalAction.InputPWDRight=<Shift><Control>braceright
TerminalAction.InputUserDefinedText1=<Alt>1
TerminalAction.InputUserDefinedText2=<Alt>2
TerminalAction.InputUserDefinedText3=<Alt>3
TerminalAction.InputUserDefinedText4=<Alt>4
TerminalAction.InputUserDefinedText5=<Alt>5
TerminalAction.InputUserDefinedText6=<Alt>6
TerminalAction.InputUserDefinedText7=<Alt>7
TerminalAction.InputUserDefinedText8=<Alt>8
TerminalAction.InputUserDefinedText9=<Alt>9

";
