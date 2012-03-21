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

module page_list;

import gtk.PopupBox;

import page;
import seta_window;


private __gshared Page[] pages_;


void Register(Page p)
{
  pages_ ~= p;
}

void Unregister(Page p)
{
  int idx = -1;
  foreach(i, page; pages_){
    if(page is p){
      idx = i;
      break;
    }
  }

  if(idx != -1){
    pages_ = pages_[0 .. idx] ~ pages_[idx+1 .. $];
  }
}


void NotifyReconstructShortcuts()
{
  foreach(page; pages_){
    page.GetFileManager().ReconstructShortcuts();
  }
}

void NotifyFilerDisconnect(string mountName, string gvfsroot)
{
  bool alreadyPopup = false;

  foreach(page; pages_){
    if(page.FileSystemRoot() == gvfsroot){
      if(!alreadyPopup){// popup once
        PopupBox.information("SFTP connection to " ~ mountName ~ " has suddenly been shut down.", "");
        alreadyPopup = true;
      }
      page.GetFileManager().Disconnect!(false)();// do not force Terminal to logout
    }
  }
}

void NotifyEscapeFromPath(string path)
{
  foreach(page; pages_){
    page.GetFileManager().EscapeFromPath(path);
  }
}

void NotifySetLayout()
{
  foreach(page; pages_){
    page.GetFileManager().SetLayout();
    page.SetLayout();
  }
  SetaWindow.SetLayout();
}

void NotifyApplyTerminalPreferences()
{
  foreach(page; pages_){
    page.GetTerminal().ApplyPreferences();
  }
}
