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

module main;

private import gtk.Main;
private import gthread.Thread;
private import gdk.Threads;

private import tango.io.Stdout;

private import constants;
private import config.init;
private import anything_cd.init;
private import volume_monitor;
private import thread_list;
private import seta_window;


void Initialize()
{
  constants.Init();
  config.init.Init();
  anything_cd.init.Init();
  volume_monitor.Init();
  thread_list.Init();
}


void Finalize()
{
  thread_list.Finish();
  anything_cd.init.Finish();
  config.init.Finish();
}


void main(string[] args)
{
  // initialize libraries
  Thread.init(null);
  gdkThreadsInit();
  Main.init(args);
  gdkThreadsEnter();

  // initialize Seta utilities
  Initialize();

  SetaWindow.Init();
  Main.run();

  Finalize();

  gdkThreadsLeave();
}
