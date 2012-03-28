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

module gtk.combo_box_text;

public import gtkc.gtktypes;
import gtkc.gtk;
import glib.Str;
import glib.ConstructionException;
import gtk.ComboBox;

import std.stdio;


class ComboBoxText : ComboBox
{
  protected GtkComboBoxText * gtkComboBoxText;

  public GtkComboBoxText * getComboBoxTextStruct()
  {
    return gtkComboBoxText;
  }

  protected override void* getStruct()
  {
    return cast(void*)gtkComboBoxText;
  }

  public this(GtkComboBoxText * obj)
  {
    if(obj is null){
      this = null;
      return;
    }
    void * ptr = getDObject(cast(GObject*)obj);
    if(ptr !is null){
      this = cast(ComboBoxText)ptr;
      return;
    }
    super(cast(GtkComboBox*)obj);
    this.gtkComboBoxText = obj;
  }

  protected override void setStruct(GObject * obj)
  {
    super.setStruct(obj);
    gtkComboBoxText = cast(GtkComboBoxText*)obj;
  }

  public this()
  {
    GtkComboBoxText * p = cast(GtkComboBoxText*)gtk_combo_box_text_new();
    if(p is null){
      throw new ConstructionException("null returned by gtk_combo_box_text_new");
    }
    this(p);
  }

  public override void appendText(string text)
  {
    gtk_combo_box_text_append_text(gtkComboBoxText, Str.toStringz(text));
  }
}


extern(C){
  struct GtkComboBoxText{};
  GtkWidget *         gtk_combo_box_text_new              ();
  void                gtk_combo_box_text_append_text      (GtkComboBoxText *combo_box,
                                                           const gchar *text);
}
