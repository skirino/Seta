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

module utils.gio_util;

import gio.FileIF;
import gio.FileInfo;
import gio.FileEnumerator;
import glib.GException;

private FileIF GetFileForDirectory(string dirname) {
  if(dirname.length == 0) {
    return null;
  }
  try {
    auto f = FileIF.parseName(dirname);
    scope info = f.queryInfo("standard::type", GFileQueryInfoFlags.NONE, null);
    if(info.getFileType() == GFileType.DIRECTORY) {
      return f;
    } else { // not a directory
      return null;
    }
  } catch(GException ex) { // no such file or directory
    return null;
  }
}

bool Exists(string path) {
  if(path.length == 0) {
    return false;
  }
  scope f = FileIF.parseName(path);
  return f.queryExists(null) != 0;
}

bool DirectoryExists(string path) {
  return GetFileForDirectory(path) !is null;
}

// Check whether the user can see children of "dir".
private bool CanEnumerateChildren(FileIF dir) {
  try {
    scope enumerate = dir.enumerateChildren("", GFileQueryInfoFlags.NONE, null);
    enumerate.close(null);
    return true;
  } catch(GException ex) {
    return false;
  }
}

bool CanEnumerateChildren(string dir) {
  auto f = GetFileForDirectory(dir);
  if(f is null) {
    return false;
  }
  return CanEnumerateChildren(f);
}
