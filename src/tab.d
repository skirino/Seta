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

module tab;

import std.conv;

import gtk.Widget;
import gtk.Label;
import gtk.Button;
import gtk.Image;
import gtk.HBox;
import gtk.VBox;
import gtk.EventBox;
import gdk.Event;

import utils.ref_util;


// tab with close button
// In order to catch button press event on tab, make a subclass of EventBox
class Tab : EventBox
{
private:
  Nonnull!HBox   hbox_;
  Nonnull!Label  labelIndex_;
  Nonnull!Label  labelPath_;// shared with FileManager
  Nonnull!Button closeButton_;
  void delegate(char, uint) closePage_;
  char lr_;// 'L' or 'R'
  uint pageNum_;

public:
  this(char side, void delegate(char, uint) closePage)
  {
    lr_ = side;
    closePage_ = closePage;

    labelIndex_.init(new Label("idx"));
    labelPath_ .init(new Label(""));
    labelPath_.setEllipsize(PangoEllipsizeMode.START);

    // to reduce blank space around the button, wrap "img" by HBox and VBox
    auto img = new Image("gtk-close", GtkIconSize.MENU);
    auto hboxImg = new HBox(0, 0);
    hboxImg.packStart(img, 1, 0, 0);
    auto vboxImg = new VBox(0, 0);
    vboxImg.packStart(hboxImg, 1, 0, 0);

    // close button with x-mark
    closeButton_.init(new Button);
    closeButton_.add(vboxImg);
    closeButton_.setRelief(GtkReliefStyle.NONE);
    closeButton_.setSizeRequest(20, 20);
    closeButton_.addOnClicked(&ClosePage);

    hbox_.init(new HBox(0, 0));
    hbox_.packStart(labelIndex_, 0, 0, 2);
    hbox_.packStart(labelPath_,  1, 1, 2);
    hbox_.packEnd(closeButton_,  0, 0, 2);

    super();
    add(hbox_);
    addOnButtonPress(&ButtonPressed);
    setVisibleWindow(0);// For clean redrawing of tabs, it is better not to have visible window.
    showAll();
  }

private:
  bool ButtonPressed(Event e, Widget w)
  {
    auto eb = e.button();
    if(eb.button != 2) // only middle button
      return false;
    CloseThisPage();
    return true;
  }

  void ClosePage(Button b)
  {
    CloseThisPage();
  }

public:
  void CloseThisPage()
  {
    closePage_(lr_, pageNum_ - 1);// convert to 0-based number
  }

  void SetID(char lr, uint n)
  {
    lr_ = lr;
    pageNum_ = n;
    labelIndex_.setText(n.to!string ~ ": ");
  }
  string GetID()
  {
    return "" ~ lr_ ~ pageNum_.to!string;
  }
  bool OnLeftSide()
  {
    return lr_ == 'L';
  }

  void SetPath(string p)
  {
    labelPath_.setText(p);
    setTooltipText(p);
  }
}
