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

module config.keybind;

import std.string : split, strip;
import std.ascii : isAlpha, toUpper;

import gtk.AccelGroup;
import gdk.Keysyms;

import utils.string_util : StartsWith;
import constants : TerminalAction;
import rcfile = config.rcfile;

struct KeyCode
{
  GdkModifierType state_;
  uint keyval_, actIdx_;

  bool IsValid() {
    return state_ > 0 || keyval_ > 0;
  }

  bool IsEqual(KeyCode code) {
    return (state_ == code.state_) && (keyval_ == code.keyval_);
  }

  string toString() {
    return AccelGroup.acceleratorName(keyval_, state_);
  }
}

private KeyCode MakeKeyCode(GdkEventKey * ekey) {
  KeyCode code;

  // translate redundant keyvals into the standard one
  switch(ekey.keyval) {
  case GdkKeysyms.GDK_KP_Tab, GdkKeysyms.GDK_ISO_Left_Tab, GdkKeysyms.GDK_3270_BackTab:
    code.keyval_ = GdkKeysyms.GDK_Tab;
    break;

    // other redundant keyvals should be put here ...

  default:
    code.keyval_ = ekey.keyval;
  }

  code.state_ = TurnOffLockFlags(ekey.state);
  code.actIdx_ = 0;

  return code;
}

private KeyCode ParseKeyCode(string s, uint action) {
  KeyCode ret;
  ret.actIdx_ = action;
  if(s.length > 0) { // not empty
    AccelGroup.acceleratorParse(s, ret.keyval_, ret.state_);
    // if keyval_ is alphabet and SHIFT is pressed, keycode should be modified to uppercase
    if(isAlpha(ret.keyval_) && (ret.state_ & GdkModifierType.SHIFT_MASK)) {
      ret.keyval_ = toUpper(ret.keyval_);
    }
  } else { // empty string
    ret.state_ = cast(GdkModifierType)0;
    ret.keyval_ = 0;
  }
  return ret;
}

KeyCode[] ParseKeyCodeList(string s, uint action) {
  KeyCode[] ret;
  auto list = split(s, ",");

  foreach(x; list) {
    KeyCode code = ParseKeyCode(strip(x), action);
    if(code.IsValid()) {
      ret ~= code;
    }
  }
  return ret;
}

string SerializeKeyCodeList(KeyCode[] codes) {
  string ret;
  foreach(code; codes[0 .. $-1]) {
    ret ~= code.toString() ~ ',';
  }
  ret ~= codes[$-1].toString();
  return ret;
}

private struct MapKeyAction
{
  KeyCode[] actions_;

  int QueryAction(GdkEventKey * ekey) {
    KeyCode code = MakeKeyCode(ekey);

    // simple linear search
    foreach(action; actions_) {
      if(code.IsEqual(action)) {
        return action.actIdx_;
      }
    }
    return -1;
  }

  void Register(KeyCode code) {
    actions_ ~= code;
  }

  void Clear() {
    actions_.length = 0;
  }
}


private __gshared MapKeyAction keymapMainWindow;
private __gshared MapKeyAction keymapFileManager;
private __gshared MapKeyAction keymapFileView;
private __gshared MapKeyAction keymapTerminal;

private MapKeyAction* FindKeymapForActionKey(string key) {
  if(key.StartsWith("MainWindow"))  return &keymapMainWindow;
  if(key.StartsWith("FileManager")) return &keymapFileManager;
  if(key.StartsWith("FileView"))    return &keymapFileView;
  if(key.StartsWith("Terminal"))    return &keymapTerminal;
  assert(false);
}

void Init() {
  keymapMainWindow .Clear();
  keymapFileManager.Clear();
  keymapFileView   .Clear();
  keymapTerminal   .Clear();

  KeyCode[][string] dict = rcfile.GetKeybinds();
  foreach(key; dict.keys) {
    auto keymap = FindKeymapForActionKey(key);
    foreach(code; dict[key]) {
      keymap.Register(code);
    }
  }

  // keybinds in terminal which should not be modified by users
  // register Ret, C-j, C-m, C-o
  keymapTerminal.Register(KeyCode(cast(GdkModifierType)0,       GdkKeysyms.GDK_Return, TerminalAction.Enter));
  keymapTerminal.Register(KeyCode(GdkModifierType.CONTROL_MASK, GdkKeysyms.GDK_j,      TerminalAction.Enter));
  keymapTerminal.Register(KeyCode(GdkModifierType.CONTROL_MASK, GdkKeysyms.GDK_m,      TerminalAction.Enter));
  keymapTerminal.Register(KeyCode(GdkModifierType.CONTROL_MASK, GdkKeysyms.GDK_o,      TerminalAction.Enter));

  // register Tab, C-i
  keymapTerminal.Register(KeyCode(cast(GdkModifierType)0,       GdkKeysyms.GDK_Tab, TerminalAction.Replace));
  keymapTerminal.Register(KeyCode(GdkModifierType.CONTROL_MASK, GdkKeysyms.GDK_i,   TerminalAction.Replace));
}

int QueryAction(string actionType)(GdkEventKey * ekey) {
  return mixin("keymap" ~ actionType).QueryAction(ekey);
}

///////////////////// utils to interpret GdkEventKey struct
GdkModifierType TurnOffLockFlags(uint state) {
  const GdkModifierType MASK = GdkModifierType.SHIFT_MASK | GdkModifierType.CONTROL_MASK | GdkModifierType.MOD1_MASK;
  return cast(GdkModifierType) (state & MASK);
}
///////////////////// utils to interpret GdkEventKey struct
