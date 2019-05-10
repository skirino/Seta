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

module utils.string_util;

import std.string;
import std.algorithm : min, map, fold;
import std.conv;

pure string NonnullString(string s) {
  return s is null ? "" : s;
}

pure bool StartsWith(string s1, string s2) {
  if(s1.length >= s2.length) {
    return s1[0 .. s2.length] == s2;
  } else {
    return false;
  }
}

pure string AppendSlash(string s) {
  if(s is null) {
    return "/";
  } else {
    return (s[$-1] == '/') ? s : s ~ '/';
  }
}

// backslash should be the first entry
private immutable string SpecialChars = "\\!\"$&\'()~=|`{}[]*:;<>?, ";

pure string EscapeSpecialChars(string input) {
  return SpecialChars.fold!((s, c) => s.tr(c.to!string, "\\" ~ c.to!string))(input);
}

pure bool ContainsPattern(C)(const(C)[] source, const(C)[] match) {
  return source.indexOf(match) != -1;
}

unittest
{
  string x = "abcあいう123";
  assert(x.ContainsPattern("abc"));
  assert(x.dup.ContainsPattern("abc"));
  assert(!x.ContainsPattern("xyz"));
}
