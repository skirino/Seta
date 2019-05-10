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

module config.page_init_option;

import std.string : split, join;
import std.algorithm : map;

import utils.gio_util;

immutable SEPARATOR_PAGE_INIT_OPTIONS_LIST = "_///_";
immutable SEPARATOR_PAGE_INIT_OPTIONS      = "_//_";

struct PageInitOption
{
  string initialDir_;
  string terminalRunCommand_;

  string toString() {
    return initialDir_ ~ SEPARATOR_PAGE_INIT_OPTIONS ~ terminalRunCommand_;
  }

  static PageInitOption Parse(string s) {
    string[] l = s.split(SEPARATOR_PAGE_INIT_OPTIONS);
    if(l.length == 1) {
      auto path = l[0];
      if(DirectoryExists(path)) {
        return PageInitOption(path, null);
      }
    } else if(l.length == 2) {
      auto path    = l[0];
      auto command = l[1];
      if(DirectoryExists(path)) {
        return PageInitOption(path, command);
      }
    }
    throw new Exception("Failed to parse!");
  }

  static PageInitOption[] ParseList(string listStr) {
    string[] list = listStr.split(SEPARATOR_PAGE_INIT_OPTIONS_LIST);
    PageInitOption[] ret;
    foreach(s; list) {
      try {
        ret ~= Parse(s);
      } catch(Exception e) {}
    }
    return ret;
  }

  static string ToListString(PageInitOption[] list) {
    return list.map!"a.toString"().join(SEPARATOR_PAGE_INIT_OPTIONS_LIST);
  }
}
