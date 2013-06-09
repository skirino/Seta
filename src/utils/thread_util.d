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

module utils.thread_util;

import core.thread;

import gdk.Threads;


void SleepMillisecs(uint msecs)
{
  Thread.sleep(dur!("msecs")(msecs));
}


private void WaitWithGDKLock(Thread t)
{
  while(t.isRunning()){
    threadsLeave();
    Thread.yield();
    SleepMillisecs(50);
    threadsEnter();
  }
}


void StopAndWait(JobThread)(JobThread t)
{
  if(t !is null && t.isRunning()){
    t.Stop();
    WaitWithGDKLock(t);
  }
}
