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

module main;

private import gtk.Main;
private import gthread.Thread;
private import gdk.Threads;

private import tango.io.Stdout;

private import mainWindow;
private import constants;
private import rcfile = config.rcfile;
private import volumeMonitor;
private import threadList;
private import anything_cd.dir_list;
private import anything_cd.dir_history;


void Initialize()
{
  // init utilities
  constants.Init();
  rcfile.Init();
  volumeMonitor.Init();
  threadList.Init();
  anything_cd.dir_list.Init();
  anything_cd.dir_history.Init();
}


void Finalize()
{
  threadList.Finish();
  rcfile.Free();
  anything_cd.dir_list.Finish();
  anything_cd.dir_history.Finish();
}


void main(string[] args)
{
  // init libs
  Thread.init(null);
  gdkThreadsInit();
  Main.init(args);
  gdkThreadsEnter();
  
  Initialize();
  
  SetaWindow.Init();
  Main.run();
  
  Finalize();
  
  gdkThreadsLeave();
}
