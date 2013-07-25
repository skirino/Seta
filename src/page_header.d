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

module page_header;

import gtk.HBox;
import gtk.Label;
import gtk.Button;
import gtk.Widget;
import gtk.Tooltip;

import utils.ref_util;
import utils.image_util;
import utils.string_util;


class PageHeader : HBox
{
private:
  Nonnull!Label hostLabel_, pwdLabel_, itemsLabel_;

public:
  this(void delegate(Button) dlgAppendPage,
       void delegate(Button) dlgViewModeSwitch,
       void delegate(Button) dlgGoToDirOtherPane)
  {
    super(0, 0);

    // temporarily change button size
    Button.setIconSize(GtkIconSize.MENU);
    scope(exit) Button.setIconSize(GtkIconSize.BUTTON);

    auto appendPageButton = new Button(StockID.ADD, dlgAppendPage, true);
    appendPageButton.setTooltipText("Open new tab");
    appendPageButton.setCanFocus(1);
    packStart(appendPageButton, 0, 0, 0);

    auto viewModeButton = new Button(StockID.FULLSCREEN, dlgViewModeSwitch, true);
    viewModeButton.setTooltipText("Switch view mode");
    viewModeButton.setCanFocus(0);
    packStart(viewModeButton, 0, 0, 0);

    auto img = LoadImage("/usr/share/pixmaps/seta/gnome-session-switch.svg");
    auto goToDirOtherPaneButton = new Button;
    goToDirOtherPaneButton.setTooltipText("Go to directory shown in the other pane");
    goToDirOtherPaneButton.setCanFocus(0);
    goToDirOtherPaneButton.setImage(img);
    goToDirOtherPaneButton.addOnClicked(dlgGoToDirOtherPane);
    packStart(goToDirOtherPaneButton, 0, 0, 0);

    hostLabel_.init(new Label("localhost"));
    packStart(hostLabel_, 0, 0, 10);

    pwdLabel_.init(new Label(""));
    SetupPWDLabel();
    packStart(pwdLabel_, 1, 1, 0);

    itemsLabel_.init(new Label(""));
    packStart(itemsLabel_, 0, 0, 10);
  }

  string GetHost()
  {
    return hostLabel_.getText();
  }
  void SetHost(string h)
  {
    hostLabel_.setText(h);
  }
  void SetPwd(string pwd)
  {
    pwdLabel_.setText(pwd);
  }
  void SetNumItems(long n)
  {
    itemsLabel_.setText(PluralForm!(long, "item")(n));
  }

private:
  void SetupPWDLabel()
  {
    pwdLabel_.setSelectable(1);
    pwdLabel_.setEllipsize(PangoEllipsizeMode.START);
    // tooltip for long path
    pwdLabel_.setHasTooltip(1);
    pwdLabel_.addOnQueryTooltip(
      delegate bool(int x, int y, int keyboardTip, Tooltip tip, Widget w){
        auto l = cast(Label)w;
        if(l.getLayout().isEllipsized()){
          tip.setText(l.getText());
          return true;
        }
        return false;
      });
  }
}
