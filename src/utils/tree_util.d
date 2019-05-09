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

module utils.tree_util;

import glib.ListG;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.TreeModelIF;
import gtk.TreeIter;
import gtk.TreePath;

TreePath GetPathAtPos(TreeView view, double x, double y) {
  TreePath path;
  TreeViewColumn col;
  int cellx, celly;
  if(view.getPathAtPos(cast(int)x, cast(int)y, path, col, cellx, celly))
    return path;
  else
    return null;
}

TreeIter GetIter(TreeModelIF model, TreePath path) {
  if(path is null) {
    return null;
  }
  TreeIter iter = new TreeIter;
  if(model.getIter(iter, path)) {
    return iter;
  } else {
    return null;
  }
}

TreeIter GetIterFromString(TreeModelIF model, string pathStr) {
  TreeIter iter = new TreeIter;
  iter.setModel(model);
  if(model.getIterFromString(iter, pathStr)) {
    return iter;
  } else {
    return null;
  }
}

void ForeachRow(TreeModelIF model, TreeIter categoryOrNull, void delegate(TreeIter) dlg) {
  auto iter = new TreeIter;
  if(model.iterChildren(iter, categoryOrNull)) {
    iter.setModel(model);
    do {
      dlg(iter);
    } while(model.iterNext(iter));
  }
}
