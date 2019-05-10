/*
Copyright (C) 2012-2019, Shunsuke Kirino <shunsuke.kirino@gmail.com>

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

import constants;

// Notebook tab with close button.
// In order to catch button press event on tab, make a subclass of EventBox.
class Tab : EventBox
{
private:
  Label  labelIndex_;
  Button closeButton_;
  void delegate(Side, uint) closePage_;
  Side side_;
  uint pageNum_;

public:
  this(Side side, void delegate(Side, uint) closePage) {
    side_ = side;
    closePage_ = closePage;
    super();
    InitChildWidgets();
    setVisibleWindow(0); // For clean redrawing of tabs, it is better not to have visible window.
    showAll();
  }

private:
  void InitChildWidgets() {
    labelIndex_ = new Label("idx");
    InitCloseButton();
    auto hbox = new HBox(0, 0);
    hbox.packStart(labelIndex_, 0, 0, 2);
    hbox.packEnd(closeButton_,  0, 0, 2);
    add(hbox);
  }

  void InitCloseButton() {
    closeButton_ = new Button;
    closeButton_.add(makeWrappedCloseImage());
    closeButton_.setRelief(GtkReliefStyle.NONE);
    closeButton_.setSizeRequest(20, 20);
    closeButton_.addOnClicked(&ClosePage);
  }

  Widget makeWrappedCloseImage() {
    // to reduce blank space around the button, wrap "img" by HBox and VBox
    auto img = new Image("window-close", GtkIconSize.MENU);
    auto hboxImg = new HBox(0, 0);
    hboxImg.packStart(img, 1, 0, 0);
    auto vboxImg = new VBox(0, 0);
    vboxImg.packStart(hboxImg, 1, 0, 0);
    return vboxImg;
  }

  void ClosePage(Button b) {
    CloseThisPage();
  }

public:
  void CloseThisPage() {
    closePage_(side_, pageNum_ - 1); // convert to 0-based number
  }

  void SetID(Side side, uint n) {
    side_ = side;
    pageNum_ = n;
    labelIndex_.setText(n.to!string ~ ": ");
  }
}
