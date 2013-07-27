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

import std.stdio;

import gtk.Main;
import gthread.Thread;
import gdk.Threads;

import constants;
import config.init;
import anything_cd.init;
import desktop_notification;
import volume_monitor;
import thread_list;
import seta_window;


private void Initialize()
{
  constants.Init();
  config.init.Init();
  anything_cd.init.Init();
  desktop_notification.Init();
  volume_monitor.Init();
  thread_list.Init();
}


private void Finalize()
{
  thread_list.Finish();
  desktop_notification.Finish();
  anything_cd.init.Finish();
  config.init.Finish();
}


void main(string[] args)
{
  version(unittest){
    writeln("All tests passed!");
  }
  else{
    threadsInit();
    Main.init(args);
    threadsEnter();
    scope(exit){ threadsLeave(); }

    Initialize();
    scope(exit){ Finalize(); }

    SetaWindow.Init();
    Main.run();
  }
}
