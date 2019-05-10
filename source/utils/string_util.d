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
import std.stdio;
import std.ascii;
import std.process;
import std.algorithm : min, map;
import std.array;
import std.conv;
import core.stdc.string : memcmp;

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
  char[] ret = input.dup;
  foreach(c; SpecialChars) {
    ret = ret.substitute("" ~ c, "\\" ~ c);
  }
  return ret.idup;
}

C[] substitute(C)(const(C)[] s, const(C)[] from, const(C)[] to) {
  if(from.length == 0) {
    return s.dup;
  }
  C[] p;
  size_t istart = 0;
  while(istart < s.length) {
    auto i = indexOf(s[istart .. s.length], from);
    if(i == -1) {
      p ~= s[istart .. s.length];
      break;
    }
    p ~= s[istart .. istart + i];
    p ~= to;
    istart += i + from.length;
  }
  return p;
}

unittest
{
  string x = "abcあいうabc123abc";
  assert(x == x.substitute("",   "def"));
  assert(x == x.substitute("nohit", "def"));

  // Should accept both mutable and immutable strings
  assert("defあいうdef123def" == x    .substitute("abc",     "def"));
  assert("defあいうdef123def" == x.dup.substitute("abc",     "def"));
  assert("defあいうdef123def" == x    .substitute("abc".dup, "def"));
  assert("defあいうdef123def" == x.dup.substitute("abc".dup, "def"));
  assert("defあいうdef123def" == x    .substitute("abc".dup, "def".dup));
  assert("defあいうdef123def" == x.dup.substitute("abc".dup, "def".dup));

  // Should substitute multibyte chars
  assert("abcえおabc123abc" == x.substitute("あいう", "えお"));
}

private immutable string LocateFunctionBody =
"
  if(start >= source.length) {
    return source.length;
  }
  auto i = source[start .. $].indexOf(match);
  if(i == -1) {
    return source.length;
  } else {
    return i + start;
  }
";

size_t locate(C1, C2)(const(C1)[] source, const(C2) match, size_t start = 0) {
  mixin(LocateFunctionBody);
}
size_t locatePattern(C)(const(C)[] source, const(C)[] match, size_t start = 0) {
  mixin(LocateFunctionBody);
}

unittest
{
  string x = "abcあいう123";
  assert(0        == x.locate('a'));
  assert(0        == x.dup.locate('a'));
  assert(6        == x.locate('い')); // 'あ' is 3-byte character in UTF-8
  assert(6        == x.dup.locate('い'));
  assert(x.length == x.locate('x'));
  assert(x.length == x.locate('x', 100));
  assert(x.length == x.locate('a', 1));
  assert(x.length == x.locate('a', 100));
  assert(2        == x.locate('c', 1));

  assert(0        == x.locatePattern("abc"));
  assert(0        == x.dup.locatePattern("abc"));
  assert(3        == x.locatePattern("あいう"));
  assert(1        == x.locatePattern("bcあ"));
  assert(x.length == x.locatePattern("xyz"));
}

private immutable string LocatePriorFunctionBody =
"
  if(start >= source.length) {
    start = source.length;
  }
  auto i = source[0 .. start].lastIndexOf(match);
  if(i == -1) {
    return source.length;
  } else {
    return i;
  }
";

size_t locatePrior(C1, C2)(const(C1)[] source, const(C2) match, size_t start = size_t.max) {
  mixin(LocatePriorFunctionBody);
}
size_t locatePatternPrior(C)(const(C)[] source, const(C)[] match, size_t start = size_t.max) {
  mixin(LocatePriorFunctionBody);
}

unittest
{
  string x = "abcあいう123";
  assert(x.length == x.locatePrior('x'));
  assert(x.length == x.dup.locatePrior('x'));
  assert(x.length == x.locatePrior('x', 5));
  assert(0        == x.locatePrior('a'));
  assert(0        == x.locatePrior('a', 13));
  assert(6        == x.locatePrior('い'));
  assert(6        == x.locatePrior('い', 13));
  assert(13       == x.locatePrior('2'));
  assert(x.length == x.locatePrior('2', 13));

  assert(0        == x.locatePatternPrior("abc"));
  assert(0        == x.dup.locatePatternPrior("abc"));
  assert(3        == x.locatePatternPrior("あいう"));
  assert(1        == x.locatePatternPrior("bcあ"));
  assert(x.length == x.locatePatternPrior("xyz"));
}

bool containsPattern(C)(const(C)[] source, const(C)[] match) {
  return source.locatePattern(match) != source.length;
}

unittest
{
  string x = "abcあいう123";
  assert(x.containsPattern("abc"));
  assert(x.dup.containsPattern("abc"));
  assert(!x.containsPattern("xyz"));
}
