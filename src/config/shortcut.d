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

module config.shortcut;

import std.string;
import std.algorithm;

import utils.string_util;
import utils.gio_util;

immutable string SeparatorShortcutList = "_///_";
immutable string SeparatorShortcut = "_//_";

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

  static Shortcut Parse(string s) {
    string[] l = s.split(SeparatorShortcut);
    if(l.length == 1) {
      auto path = l[0];
      if(DirectoryExists(path)) {
        auto label = GetBasename(path);
        return Shortcut(label, path);
      }
    }
    else if(l.length == 2) {
      auto label = l[0];
      auto path  = l[1];
      if(DirectoryExists(path)) {
        return Shortcut(label, path);
      }
    }
    throw new Exception("Failed to parse!");
  }

  static Shortcut[] ParseList(string listStr) {
    auto list = listStr.split(SeparatorShortcutList);
    Shortcut[] ret;
    foreach(s; list) {
      try {
        ret ~= Parse(s);
      } catch(Exception e) {}
    }
    return ret;
  }

  static string ToShortcutListString(Shortcut[] list) {
    return list.map!"a.toString"().join(SeparatorShortcutList);
  }
}
