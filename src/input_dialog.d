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

module input_dialog;

import std.algorithm;

import gtk.Label;
import gtk.Entry;
import gtk.Dialog;
import gtk.VBox;

import utils.string_util;


string InputDialog(bool hideInput = false)(string title, string description, string defaultValue = "")
{
  scope label = new Label(description, false);
  scope entry = new Entry(defaultValue);
  entry.setWidthChars(cast(int)max(defaultValue.length, 20));// ensure width of "entry"
  static if(hideInput){
    entry.setVisibility(0);
  }

  scope d = new Dialog;
  d.setTitle(title);

  string ret;
  entry.addOnActivate(delegate void(Entry e){
      d.response(GtkResponseType.OK);
    });

  scope box = new VBox(0, 5);
  box.add(label);
  box.add(entry);
  d.getContentArea.add(box);
  d.addButtons(["OK"                           , "_cancel"],
               [GtkResponseType.OK, GtkResponseType.CANCEL]);

  d.addOnResponse(
    delegate void(int responseID, Dialog dialog)
    {
      if(responseID == GtkResponseType.OK){
        ret = entry.getText();
        d.destroy();
      }
      else if(responseID == GtkResponseType.CANCEL){
        d.destroy();
      }
    });

  d.showAll();

  entry.selectRegion(0, cast(int)locatePrior(defaultValue, '.'));// do not select extension

  d.run();
  return ret;
}


// return -1 on clicking close button
//         0 on clicking 1st button
//         1 on clicking 2nd button
//        ...
int ChooseDialog(uint numOptions)(string message, string[numOptions] labels)
{
  static if(numOptions == 2){
    GtkResponseType[] indices = cast(GtkResponseType[])[0, 1];
  }
  static if(numOptions == 3){
    GtkResponseType[] indices = cast(GtkResponseType[])[0, 1, 2];
  }
  static if(numOptions == 4){
    GtkResponseType[] indices = cast(GtkResponseType[])[0, 1, 2, 3];
  }

  scope d = new Dialog;
  d.getContentArea.add(new Label(message, false));
  d.addButtons(labels.dup, indices);

  int ret;
  d.addOnResponse(
    delegate void(int responseID, Dialog dialog){
      if(responseID == GtkResponseType.DELETE_EVENT){
        responseID = -1;
      }
      ret = responseID;
      d.destroy();
    });

  d.showAll();
  d.run();
  return ret;
}
