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

private import gtk.Widget;
private import gtk.Label;
private import gtk.Button;
private import gtk.Image;
private import gtk.HBox;
private import gtk.VBox;
private import gtk.EventBox;
private import glib.Str;

private import tango.io.Stdout;


// tab with close button
// In order to catch button press event on tab, make a subclass of EventBox
class Tab : EventBox
{
private:
  HBox hbox_;
  Label labelIndex_;
  Label labelPath_;// shared with FileManager
  Button closeButton_;
  void delegate(char, uint) closePage_;
  char lr_;// 'L' or 'R'
  uint pageNum_;
  
public:
  this(char side, void delegate(char, uint) closePage)
  {
    lr_ = side;
    labelIndex_ = new Label("idx");
    labelPath_ = new Label("");
    labelPath_.setEllipsize(PangoEllipsizeMode.START);
    
    // to reduce blank space around the button, wrap "img" by HBox and VBox
    auto img = new Image("gtk-close", GtkIconSize.MENU);
    auto hboxImg = new HBox(0, 0);
    hboxImg.packStart(img, 1, 0, 0);
    auto vboxImg = new VBox(0, 0);
    vboxImg.packStart(hboxImg, 1, 0, 0);
    
    // close button with x-mark
    closeButton_ = new Button;
    closeButton_.add(vboxImg);
    closeButton_.setRelief(GtkReliefStyle.NONE);
    closeButton_.setSizeRequest(20, 20);
    closeButton_.addOnClicked(&ClosePage);
    
    hbox_ = new HBox(0, 0);
    hbox_.packStart(labelIndex_, 0, 0, 2);
    hbox_.packStart(labelPath_, 1, 1, 2);
    hbox_.packEnd(closeButton_, 0, 0, 2);
    
    super();
    add(hbox_);
    closePage_ = closePage;
    addOnButtonPress(&ButtonPressed);
    setVisibleWindow(0);// For clean redrawing of tabs, it is better not to have visible window.
    showAll();
  }
  
private:
  bool ButtonPressed(GdkEventButton * eb, Widget w)
  {
    if(eb.button == 2){// middle button, close the page associated this tab
      CloseThisPage();
      return true;
    }
    else{
      return false;
    }
  }
  
  void ClosePage(Button b)
  {
    CloseThisPage();
  }
  
public:
  void CloseThisPage()
  {
    closePage_(lr_, pageNum_);
  }
  
  void SetID(char lr, uint n)
  {
    lr_ = lr;
    pageNum_ = n;
    labelIndex_.setText(Str.toString(n) ~ ": ");
  }
  string GetID()
  {
    return "" ~ lr_ ~ Str.toString(pageNum_);
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

