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

private import gtk.DragAndDrop;
private import gio.ContentType;


static const string[] ColumnTitles = ["name", "type", "size", "owner", "permissions", "last modified"];
enum ColumnType {NAME, TYPE, SIZE, OWNER, PERMISSIONS, LAST_MODIFIED, COLOR}

enum FileColorType {Directory, File, SymLink, Executable}

enum Direction {UP, DOWN, LEFT, RIGHT}

enum FocusInPage {NONE, UPPER, LOWER}

enum FocusInMainWindow {NONE, LEFT, RIGHT}

enum ViewMode {TERMINAL, FILER, BOTH}

enum MouseButton{
  LEFT=1,
  MIDDLE=2,
  RIGHT=3
}

enum DraggingState {NEUTRAL, PRESSED, DRAGGING}

enum PasteModeFlags {
  CANCEL_ALL=0,
  MULTIPLE=1,
  ASK=2
}

static const string PARENT_STRING = "../";



void Init()
{
  directoryTypeDescription = ContentType.getDescription("inode/directory");

  dragTargets[0].target = "text/uri-list";
  dragTargets[0].flags  = 0;
  dragTargets[0].info   = 1;
}


private string directoryTypeDescription;
string GetDirectoryTypeDescription()
{
  return directoryTypeDescription;
}


private GtkTargetEntry[1] dragTargets;
GtkTargetEntry[] GetDragTargets()
{
  return dragTargets;
}



enum MainWindowAction
{
  CreateNewPage,
  MoveToNextPage,
  MoveToPreviousPage,
  SwitchViewMode,
  MoveFocusUp,
  MoveFocusDown,
  MoveFocusLeft,
  MoveFocusRight,
  ExpandLeftPane,
  ExpandRightPane,
  ShowChangeDirDialog,
  ShowConfigDialog,
  ToggleFullscreen,
  QuitApplication
}

enum FileManagerAction
{
  GoToPrevious,
  GoToNext,
  GoToParent,
  GoToRoot,
  GoToHome,
  GoToDirOtherSide,
  Refresh,
  StartSSH,
  ShowHidden,
  ShowDirTree,
  SyncTerminalPWD,
  GoToChild,
  GoToDir1,
  GoToDir2,
  GoToDir3,
  GoToDir4,
  GoToDir5,
  GoToDir6,
  GoToDir7,
  GoToDir8,
  GoToDir9
}

enum FileViewAction
{
  SelectAll,
  SelectRow,
  Cut,
  Copy,
  Paste,
  PopupMenu,
  Rename,
  MakeDirectory,
  MoveToTrash,
  FocusFilter,
  ClearFilter
}

enum TerminalAction
{
  Enter,
  Replace,
  Copy,
  Paste,
  PasteFilePaths,
  FindRegexp,
  SyncFilerPWD,
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
  InputUserDefinedText9
}

