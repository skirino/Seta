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

import gtk.TargetEntry;

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

enum MouseButton
{
  LEFT   = 1,
  MIDDLE = 2,
  RIGHT  = 3,
}

void Init() {
  dragTarget          = new TargetEntry("text/uri-list", 0, 1);
  textPlainDragTarget = new TargetEntry("text/plain"   , 0, 2);
}

private __gshared TargetEntry dragTarget;
TargetEntry[] GetDragTargets() { return [dragTarget]; }

private __gshared TargetEntry textPlainDragTarget;
TargetEntry GetTextPlainDragTarget() { return textPlainDragTarget; }

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
