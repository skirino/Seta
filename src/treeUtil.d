/*
Copyright (C) 2010 Shunsuke Kirino <shunsuke.kirino@gmail.com>

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

module treeUtil;

private import gtk.TreeView;
private import gtk.TreeViewColumn;
private import gtk.TreeModelIF;
private import gtk.TreeIter;
private import gtk.TreePath;
private import gtk.CellRenderer;

private import tango.io.Stdout;


// convenience functions to wrap TreeView's API
TreePath GetPathAtCursor(TreeView view)
{
  TreePath path;
  TreeViewColumn col;
  view.getCursor(path, col);
  return path;
}


TreePath GetPathAtPos(TreeView view, double x, double y)
{
  TreePath path;
  TreeViewColumn col;
  int cellx, celly;
  view.getPathAtPos(cast(int)x, cast(int)y, path, col, cellx, celly);
  return path;
}


TreeViewColumn GetColAtPos(TreeView view, double x, double y)
{
  TreePath path;
  TreeViewColumn col;
  int cellx, celly;
  view.getPathAtPos(cast(int)x, cast(int)y, path, col, cellx, celly);
  return col;
}


TreeIter GetIter(TreeModelIF model, TreePath path)
{
  if(path is null){
    return null;
  }
  else{
    TreeIter iter = new TreeIter;
    if(model.getIter(iter, path)){
      return iter;
    }
    else{
      return null;
    }
  }
}


TreeIter GetIterFirst(TreeModelIF model)
{
  TreeIter iter = new TreeIter;
  iter.setModel(model);
  if(model.getIterFirst(iter)){
    return iter;
  }
  else{
    return null;
  }
}


TreeIter GetIterFromString(TreeModelIF model, string pathStr)
{
  TreeIter iter = new TreeIter;
  iter.setModel(model);
  if(model.getIterFromString(iter, pathStr)){
    return iter;
  }
  else{
    return null;
  }
}


CellRenderer GetCellRendererFromCol(TreeViewColumn col)
{
  void * ptr = col.getCells().data();
  return new CellRenderer(cast(GtkCellRenderer*)ptr);
}


