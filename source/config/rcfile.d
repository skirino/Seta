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

module config.rcfile;

import std.conv;
import std.string : join;
import std.array : array;
import std.algorithm : max, filter;
import std.process : environment;

import glib.KeyFile;
import gtk.PopupBox;
import gdk.Color;
import gio.FileIF;

import utils.gio_util;
import utils.string_util;
import constants;
import config.keybind;
import config.page_init_option;

static immutable string SetaVersion = "0.8.0";

void Init() {
  instance_ = new SetaRCFile();
}

void Write() {
  instance_.Write();
}

void Free() {
  instance_.Write();
  instance_.free();
}

private template GetString(string group, string key) {
  immutable string GetString =
    "string Get" ~ key ~ "(){return instance_.getString(\"" ~ group ~ "\", \"" ~ key ~ "\");}";
}

///////////////// [Layout]
private template GetUint(string key) {
  immutable string GetUint =
    "uint Get" ~ key ~ "(){return ForceUint(instance_.getInteger(\"Layout\", \"" ~ key ~ "\"));}";
}

mixin(GetUint!("WindowSizeH"));
mixin(GetUint!("WindowSizeV"));
mixin(GetUint!("SplitH"));
///////////////// [Layout]

///////////////// [Pages]
PageInitOption[] GetPageInitOptionsLeft () { return instance_.GetPageInitOptionsBase("InitialPagesLeft" ); }
PageInitOption[] GetPageInitOptionsRight() { return instance_.GetPageInitOptionsBase("InitialPagesRight"); }

private string GetDefaultInitialDirectoryBase(string key) {
  auto list = instance_.GetPageInitOptionsBase(key);
  return (list.length > 0) ? list[0].initialDir_ : environment.get("HOME") ~ '/';
}
string GetDefaultInitialDirectoryLeft () { return GetDefaultInitialDirectoryBase("InitialPagesLeft" ); }
string GetDefaultInitialDirectoryRight() { return GetDefaultInitialDirectoryBase("InitialPagesRight"); }

void ResetPageInitOptions(string key, PageInitOption[] list) {
  PageInitOption[] old = instance_.GetPageInitOptionsBase(key);
  if(old != list) {
    string s = PageInitOption.ToListString(list);
    instance_.setString("Pages", key, NonnullString(s));
    instance_.changed_ = true;
  }
}
///////////////// [Pages]

///////////////// [Terminal]
mixin(GetString!("Terminal", "ColorForeground"));
mixin(GetString!("Terminal", "ColorBackground"));
mixin(GetString!("Terminal", "Font"));
mixin(GetString!("Terminal", "PROMPT"));
mixin(GetString!("Terminal", "RPROMPT"));
mixin(GetString!("Terminal", "ReplaceTargetLeft"));
mixin(GetString!("Terminal", "ReplaceTargetRight"));
double GetTransparency          () { return instance_.getDouble ("Terminal", "BackgroundTransparency"); }
uint   GetScrollLinesOnKeyAction() { return instance_.getInteger("Terminal", "ScrollLinesOnKeyAction"); }
bool   GetEnablePathExpansion   () { return instance_.getBoolean("Terminal", "EnablePathExpansion") != 0; }

mixin(GetString!("Terminal", "UserDefinedText1"));
mixin(GetString!("Terminal", "UserDefinedText2"));
mixin(GetString!("Terminal", "UserDefinedText3"));
mixin(GetString!("Terminal", "UserDefinedText4"));
mixin(GetString!("Terminal", "UserDefinedText5"));
mixin(GetString!("Terminal", "UserDefinedText6"));
mixin(GetString!("Terminal", "UserDefinedText7"));
mixin(GetString!("Terminal", "UserDefinedText8"));
mixin(GetString!("Terminal", "UserDefinedText9"));
string GetUserDefinedText(int index) {
  string key = "UserDefinedText" ~ index.to!string;
  return instance_.getString("Terminal", key);
}
///////////////// [Terminal]

///////////////// [Keybind]
KeyCode[][string] GetKeybinds() { return instance_.dictKeybind_; }

bool ResetKeybind(string keyname, string[] codeList) {
  string codes = join(codeList, ",");
  return ResetStringz("Keybind", keyname, codes);
}

void ReconstructKeybinds() {
  instance_.InstallKeybinds();
  config.keybind.Init();
}

private template GetKeybindInString(string widget, string action) {
  immutable string GetKeybindInString =
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

  this() {
    super();
    setListSeparator(',');

    ulong len;
    changed_ = false;
    filename_ = environment.get("HOME") ~ "/.setarc";
    if(Exists(filename_)) {
      loadFromFile(filename_, GKeyFileFlags.KEEP_COMMENTS);
      if(getGroups(len) == ["Version", "Layout", "Pages", "Terminal", "Directories", "Keybind"]) {
        if(getString("Version", "Version") != SetaVersion) { // .setarc is old
          changed_ = true;
          setString("Version", "Version", SetaVersion);
        }
      } else { // .setarc is old (<= 0.4.0) or there's something wrong with .setarc
        loadFromData(defaultContents, len, GKeyFileFlags.KEEP_COMMENTS);
        changed_ = true;
        PopupBox.information("Your configuration file may be older than the application or may be broken.\nStarts with default settings.", "");
      }
    } else {
      loadFromData(defaultContents, defaultContents.length, GKeyFileFlags.KEEP_COMMENTS);
      changed_ = true;
    }

    // fill default values
    // [Layout]
    mixin(SetDefaultValue!("Integer", "Layout", "WindowSizeH", "1600"));
    mixin(SetDefaultValue!("Integer", "Layout", "WindowSizeV", "900"));
    mixin(SetDefaultValue!("Integer", "Layout", "SplitH",      "800"));

    // [Pages]
    InitInitialPages("InitialPagesLeft");
    InitInitialPages("InitialPagesRight");

    // [Terminal]
    auto colorTest = new Color;
    if(!hasKey("Terminal", "ColorForeground") ||
       !Color.parse(getString("Terminal", "ColorForeground"), colorTest)) {
      setString("Terminal", "ColorForeground", "#000000");
    }
    if(!hasKey("Terminal", "ColorBackground") ||
       !Color.parse(getString("Terminal", "ColorBackground"), colorTest)) {
      setString("Terminal", "ColorBackground", "#ffffff");
    }
    mixin(SetDefaultValue!("String", "Terminal", "Font", "\"Monospace 11\""));
    mixin(SetDefaultValue!("Double", "Terminal", "BackgroundTransparency", "0.0"));
    mixin(SetDefaultValue!("String", "Terminal", "PROMPT", "environment.get(\"USER\") ~ \"@\""));
    mixin(SetDefaultValue!("String", "Terminal", "RPROMPT", "\"\""));

    mixin(SetDefaultValue!("Boolean","Terminal", "EnablePathExpansion", "true"));
    mixin(SetDefaultValue!("String", "Terminal", "ReplaceTargetLeft" , "\"$L<n>DIR\""));
    mixin(SetDefaultValue!("String", "Terminal", "ReplaceTargetRight", "\"$R<n>DIR\""));

    mixin(SetDefaultValue!("Integer", "Terminal", "ScrollLinesOnKeyAction", "1"));

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
    InitInitialDirectories("InitialDirectoriesLeft");
    InitInitialDirectories("InitialDirectoriesRight");

    // [Keybind]
    InstallKeybinds();
  }

  void Write() {
    if(changed_) {
      changed_ = false;

      // "scope" storage-class specifier is necessary to remove segfault at shutdown of Seta
      scope f = FileIF.parseName(filename_);
      scope stream = f.replace(null, 1, GFileCreateFlags.NONE, null);
      ulong len1, len2;
      stream.writeAll(cast(ubyte[]) toData(len1), len2, null);
      stream.close(null);
    }
  }

  void InstallKeybinds() {
    mixin(InstallKeybind!("MainWindowAction.CreateNewPage"     , "<Alt>t,<Shift><Primary>t"));
    mixin(InstallKeybind!("MainWindowAction.MoveToNextPage"    , "<Alt>m,<Shift><Primary>m,<Primary>Tab,<Shift><Primary>greater"));
    mixin(InstallKeybind!("MainWindowAction.MoveToPreviousPage", "<Shift><Primary>Tab,<Shift><Primary>less"));
    mixin(InstallKeybind!("MainWindowAction.CloseThisPage"     , "<Shift><Primary>d"));
    mixin(InstallKeybind!("MainWindowAction.MoveFocusLeft"     , "<Shift><Primary>h"));
    mixin(InstallKeybind!("MainWindowAction.MoveFocusRight"    , "<Shift><Primary>l"));
    mixin(InstallKeybind!("MainWindowAction.ExpandLeftPane"    , "<Shift><Primary>Left"));
    mixin(InstallKeybind!("MainWindowAction.ExpandRightPane"   , "<Shift><Primary>Right"));
    mixin(InstallKeybind!("MainWindowAction.GoToDirOtherSide"  , "<Alt>o,<Shift><Primary>o"));
    mixin(InstallKeybind!("MainWindowAction.ShowConfigDialog"  , "<Shift><Primary>Escape"));
    mixin(InstallKeybind!("MainWindowAction.ToggleFullscreen"  , "F11"));
    mixin(InstallKeybind!("MainWindowAction.QuitApplication"   , "<Shift><Primary>q"));

    mixin(InstallKeybind!("TerminalAction.ScrollUp"     , "<Shift><Primary>p"));
    mixin(InstallKeybind!("TerminalAction.ScrollDown"   , "<Shift><Primary>n"));
    mixin(InstallKeybind!("TerminalAction.Copy"         , "<Shift><Primary>c"));
    mixin(InstallKeybind!("TerminalAction.Paste"        , "<Shift><Primary>v"));
    mixin(InstallKeybind!("TerminalAction.FindRegexp"   , "<Shift><Primary>f"));
    mixin(InstallKeybind!("TerminalAction.InputPWDLeft" , "<Shift><Primary>braceleft"));
    mixin(InstallKeybind!("TerminalAction.InputPWDRight", "<Shift><Primary>braceright"));
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

  PageInitOption[] GetPageInitOptionsBase(string key) {
    if(hasKey("Pages", key)) {
      return PageInitOption.ParseList(getString("Pages", key));
    } else {
      return null;
    }
  }

  void InitInitialPages(string key) {
    auto pageOpts = GetPageInitOptionsBase(key);
    auto pageOptsWithExistingDirs = pageOpts.filter!((p) => CanEnumerateChildren(p.initialDir_)).array();
    if(pageOptsWithExistingDirs.length == 0) {
      pageOptsWithExistingDirs = [PageInitOption(environment.get("HOME") ~ '/', null)];
    }
    if(pageOptsWithExistingDirs != pageOpts) {
      changed_ = true;
      setString("Pages", key, PageInitOption.ToListString(pageOptsWithExistingDirs));
    }
  }

  void InitInitialDirectories(string key) {
    changed_ = true;
    setStringList("Directories", key, [AppendSlash(environment.get("HOME"))]);
  }

  string[] getStringList(string group, string key) {
    if(hasKey(group, key)) {
      return super.getStringList(group, key);
    } else {
      return null;
    }
  }
}

private template SetDefaultValue(string Type, string group, string key, string value) {
  immutable string SetDefaultValue =
    "
    if(!hasKey(\"" ~ group ~ "\", \"" ~ key ~ "\")) {
      changed_ = true;
      set" ~ Type ~ "(\"" ~ group ~ "\", \"" ~ key ~ "\", " ~ value ~ ");
    }";
}

private template InstallKeybind(string action, string keystr) {
  immutable string InstallKeybind =
    SetDefaultValue!("String", "Keybind", action, "\"" ~ keystr ~ "\"") ~
    "{
      string val = getString(\"Keybind\", \"" ~ action ~ "\");
      KeyCode[] array = ParseKeyCodeList(val, " ~ action ~ ");
      if(array.length > 0) {
        dictKeybind_[\"" ~ action ~ "\"] = array;
      }
    }";
}

/////////////////// for ConfigDialog
private template ResetValue(string type, string Type) {
  immutable string ResetValue =
    "
    bool Reset" ~ Type ~ "(string group, string key, " ~ type ~ " val) {
      if(instance_.get" ~ Type ~ "(group, key) == val) { // has the same value
        return false;
      } else {
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

bool ResetStringz(string group, string key, string val) {
  return ResetString(group, key, NonnullString(val));
}
/////////////////// for ConfigDialog


private uint ForceUint(int i) {
  return i < 0 ? 0 : i;
}

private const string defaultContents =
  "###################### configuration file for Seta

[Version]
Version=" ~ SetaVersion ~ "


[Layout]
WindowSizeH=1600
WindowSizeV=900
SplitH=800


[Pages]
### Pages to be shown on startup


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

ScrollLinesOnKeyAction=5

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


[Keybind]
### Key codes are expressed as \"modifiers\" and \"key values\"
### key values are defined in \"/usr/include/gtk-2.0/gdk/gdkkeysyms.h\" with prefix \"GDK_\"
MainWindowAction.CreateNewPage=<Alt>t,<Shift><Primary>t
MainWindowAction.MoveToNextPage=<Alt>m,<Shift><Primary>m,<Primary>Tab,<Shift><Primary>greater
MainWindowAction.MoveToPreviousPage=<Shift><Primary>Tab,<Shift><Primary>less
MainWindowAction.CloseThisPage=<Shift><Primary>d
MainWindowAction.MoveFocusLeft=<Shift><Primary>h
MainWindowAction.MoveFocusRight=<Shift><Primary>l
MainWindowAction.ExpandLeftPane=<Shift><Primary>Left
MainWindowAction.ExpandRightPane=<Shift><Primary>Right
MainWindowAction.GoToDirOtherSide=<Alt>o,<Shift><Primary>o
MainWindowAction.ShowConfigDialog=<Shift><Primary>Escape
MainWindowAction.ToggleFullscreen=F11
MainWindowAction.QuitApplication=<Shift><Primary>q

TerminalAction.ScrollUp=<Shift><Primary>p
TerminalAction.ScrollDown=<Shift><Primary>n
TerminalAction.Copy=<Shift><Primary>c
TerminalAction.Paste=<Shift><Primary>v
TerminalAction.FindRegexp=<Shift><Primary>f
TerminalAction.InputPWDLeft=<Shift><Primary>braceleft
TerminalAction.InputPWDRight=<Shift><Primary>braceright
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
