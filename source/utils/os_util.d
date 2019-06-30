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

module utils.os_util;

import std.conv;
import core.sys.posix.sys.types : pid_t;
import core.sys.posix.unistd;

import utils.string_util;

string ReadCwdOfProcess(pid_t pid, char[] buffer) {
  version(darwin) {
    int len = readCwd(pid, buffer.ptr);
  } else {
    string path = "/proc/" ~ pid.to!string ~ "/cwd";
    ssize_t len = readlink(toStringz(path), buffer.ptr, buffer.length);
  }
  if(len <= 0) {
    throw new Exception("Failed to get working directory of " ~ pid.to!string);
  }
  return AppendSlash(buffer[0 .. len].idup);
}

// In case of macOS use libproc (but note that it's basically private interface).
// https://opensource.apple.com/source/xnu/xnu-2422.1.72/libsyscall/wrappers/libproc/libproc.h.auto.html
extern (C) {
  int readCwd(pid_t, char*);
}
