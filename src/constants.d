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

module constants;

import std.string;

import gtk.DragAndDrop;
import gtk.TargetEntry;
import gio.ContentType;


immutable string PARENT_STRING = "../";

immutable string[] COLUMN_TITLES = [
  "name",
  "type",
  "size",
  "owner",
  "permissions",
  "last modified"];

enum ColumnType
{
  NAME,
  TYPE,
  SIZE,
  OWNER,
  PERMISSIONS,
  LAST_MODIFIED,
  COLOR,
}

enum FileColorType
{
  Directory,
  File,
  SymLink,
  Executable,
}

enum Direction
{
  LEFT,
  RIGHT,
}

enum Side
{
  LEFT  = 'L',
  RIGHT = 'R',
}

enum Order
{
  FORWARD,
  BACKWARD,
}

enum FocusInMainWindow
{
  NONE,
  LEFT,
  RIGHT,
}

enum MouseButton{
  LEFT   = 1,
  MIDDLE = 2,
  RIGHT  = 3,
}

enum DraggingState
{
  NEUTRAL,
  PRESSED,
  DRAGGING,
}

enum PasteModeFlags{
  CANCEL_ALL = 0,
  MULTIPLE   = 1,
  ASK        = 2,
}



void Init()
{
  directoryTypeDescription = ContentType.getDescription("inode/directory");

  gtkDragTarget.target = cast(char*) "text/uri-list".toStringz();
  gtkDragTarget.flags  = 0;
  gtkDragTarget.info   = 1;
  dragTargets[0] = new TargetEntry(&gtkDragTarget);

  gtkTextPlainDragTarget.target = cast(char*) "text/plain".toStringz();
  gtkTextPlainDragTarget.flags  = 0;
  gtkTextPlainDragTarget.info   = 2;
}


private __gshared string directoryTypeDescription;
string GetDirectoryTypeDescription()
{
  return directoryTypeDescription;
}

private __gshared GtkTargetEntry gtkDragTarget;
private __gshared TargetEntry[1] dragTargets;
TargetEntry[] GetDragTargets()
{
  return dragTargets;
}

private __gshared GtkTargetEntry gtkTextPlainDragTarget;
TargetEntry GetTextPlainDragTarget()
{
  return new TargetEntry(&gtkTextPlainDragTarget);
}


enum MainWindowAction
{
  CreateNewPage,
  MoveToNextPage,
  MoveToPreviousPage,
  CloseThisPage,
  MoveFocusLeft,
  MoveFocusRight,
  ExpandLeftPane,
  ExpandRightPane,
  GoToDirOtherSide,
  ShowConfigDialog,
  ToggleFullscreen,
  QuitApplication,
}

enum TerminalAction
{
  ScrollUp,
  ScrollDown,
  Enter,
  Replace,
  Copy,
  Paste,
  PasteFilePaths,
  FindRegexp,
  InputPWDLeft,
  InputPWDRight,
  InputUserDefinedText1,
  InputUserDefinedText2,
  InputUserDefinedText3,
  InputUserDefinedText4,
  InputUserDefinedText5,
  InputUserDefinedText6,
  InputUserDefinedText7,
  InputUserDefinedText8,
  InputUserDefinedText9,
}
