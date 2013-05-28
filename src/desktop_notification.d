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

module desktop_notification;

import std.string;

import deimos.notify.notify;
import config.rcfile;


void Init()
{
  notify_init(toStringz("Seta"));
}

void Finish()
{
  notify_uninit();
}

void Notify(string message)
{
  if(GetUseDesktopNotification()){
    auto n = notify_notification_new(toStringz("Seta"), toStringz(message), null);
    notify_notification_set_timeout(n, GetNotifyExpiresInMSec());
    notify_notification_show(n, null);
  }
}
