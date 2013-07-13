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

module statusbar;

import gtk.Statusbar;
import gtk.ToggleButton;
import gtk.Arrow;
import gtk.MenuShell;
import gtk.MenuItem;
import gtkc.gtk;// for gtk_get_current_event_time()

import utils.menu_util;
import rcfile = config.rcfile;
import thread_list;
import note;


private __gshared SetaStatusbar statusbarInstance;


SetaStatusbar InitStatusbar(Note noteL, Note noteR)
{
  statusbarInstance = new SetaStatusbar(noteL, noteR);
  return statusbarInstance;
}

void PushIntoStatusbar(string text)
{
  // should be called within the GDK lock
  statusbarInstance.pop(0);
  statusbarInstance.push(0, text);
  statusbarInstance.SetTooltip(text);
}


class SetaStatusbar : Statusbar
{
private:
  static const uint num_ = 10;
  string[num_] previousMessages_;
  string messageNow_;


  this(Note noteL, Note noteR)
  {
    super();

    noteL_ = noteL;
    noteR_ = noteR;
    mixin(ConstructToggleButton!('R'));
    mixin(ConstructToggleButton!('L'));

    InitShowThreadListButton();
  }

public:
  void SetLayout()
  {
    uint height = rcfile.GetHeightStatusbar();
    if(height == 0){
      hide();
    }
    else{
      show();
      setSizeRequest(-1, height);
    }
  }

private:
  void SetTooltip(string text)
  {
    for(size_t i=0; i<num_-1; ++i){
      previousMessages_[i] = previousMessages_[i+1];
    }
    previousMessages_[num_-1] = messageNow_;
    messageNow_ = text;

    string tooltip = "previous messages:";
    foreach(message; previousMessages_){
      if(message.length > 0){
        tooltip ~= "\n\n" ~ message;
      }
    }
    setTooltipText(tooltip);
  }



  ///////////////////////// show/hide left/right pane
private:
  ToggleButton showLButton, showRButton;
  Note noteL_, noteR_;

  mixin(ToggleCallbackMixin!('L', 'R'));
  mixin(ToggleCallbackMixin!('R', 'L'));

  mixin(MoveLRMixin!('L', 'R'));
  mixin(MoveLRMixin!('R', 'L'));
  ///////////////////////// show/hide left/right pane



  ///////////////////////// list up threads executing copying/moving files
private:
  ToggleButton showThreadListButton_;

  void InitShowThreadListButton()
  {
    showThreadListButton_ = new ToggleButton;
    showThreadListButton_.add(new Arrow(GtkArrowType.UP, GtkShadowType.NONE));
    packEnd(showThreadListButton_, 0, 0, 0);
    showThreadListButton_.setTooltipText("Show operations in progress");
    showThreadListButton_.addOnToggled(&ShowThreadList);
  }

  void ThreadListDone(MenuShell m)
  {
    showThreadListButton_.setActive(0);
  }

  struct XYPosition {int x_, y_;}
  ThreadInfo[] array_;

  void ShowThreadList(ToggleButton b)
  {
    if(b.getActive()){
      XYPosition temp;
      showThreadListButton_.translateCoordinates(getToplevel(), 0, 0, temp.x_, temp.y_);

      auto menu = new MenuWithMargin;
      menu.addOnSelectionDone(&ThreadListDone);

      // append items
      ThreadInfo[] list = GetWorkingThreadList();
      if(list.length == 0){
        menu.append(new MenuItem(delegate void(MenuItem){}, "<No working thread>"));
      }
      else{
        foreach(info; list){
          menu.append(new MenuItem(&info.StopThread!(MenuItem), info.GetLabel(), false));
        }
      }
      array_ = list;

      // convert relative positions to absolute ones
      int posx, posy;
      getWindow().getPosition(posx, posy);
      temp.x_ += posx;
      temp.y_ += posy;

      menu.showAll();
      menu.popup(null, null, &ThreadListPositioning, &temp, 0, gtk_get_current_event_time());
    }
  }

  extern(C) static void ThreadListPositioning(
    GtkMenu * menu, gint * x, gint * y,
    gboolean * pushIn, void * data)
  {
    auto ptr = cast(XYPosition*)data;
    GtkRequisition req;
    gtk_widget_size_request(cast(GtkWidget*)menu, &req);

    *x = ptr.x_;
    // horizontal position should be shifted by the height of the menu
    *y = ptr.y_ - req.height;
    *pushIn = 1;
  }
  ///////////////////////// list up threads executing copying/moving files
}



///////////////////////// show/hide left/right pane
bool ExpandLeftPane()
{
  return statusbarInstance.MoveL();
}

bool ExpandRightPane()
{
  return statusbarInstance.MoveR();
}
///////////////////////// show/hide left/right pane




  template ConstructToggleButton(char l)
  {
    const string ConstructToggleButton =
      "
      show" ~ l ~ "Button = new ToggleButton(\"" ~ l ~ "\");
      show" ~ l ~ "Button.setActive(1);
      show" ~ l ~ "Button.setTooltipText(\"show/hide " ~ l ~ " pane\");
      show" ~ l ~ "Button.addOnToggled(&Toggle" ~ l ~ ");
      packEnd(show" ~ l ~ "Button, 0, 0, 0);
      ";
  }

  template ToggleCallbackMixin(char l, char r)
  {
    const string ToggleCallbackMixin =
      "void Toggle" ~ l ~ "(ToggleButton b)
      {
        if(show" ~ l ~ "Button.getActive() == 0){
          note" ~ l ~ "_.hide();
          if(show" ~ r ~ "Button.getActive() == 0){
            show" ~ r ~ "Button.setActive(1);
          }
        }
        else{
          if(note" ~ l ~ "_.getNPages() == 0){
            if('" ~ l ~ "' == 'L'){
              note" ~ l ~ "_.AppendNewPage();
            }
            else{
              note" ~ l ~ "_.AppendNewPage();
            }
          }
          note" ~ l ~ "_.show();
        }
      }";
  }

  template MoveLRMixin(char l, char r)
  {
    const string MoveLRMixin =
      "bool Move" ~ l ~ "()
      {
        if(show" ~ l ~ "Button.getActive() != 0){
          if(show" ~ r ~ "Button.getActive() != 0){// both pane
            show" ~ r ~ "Button.setActive(0);
            return true;
          }
          // else : only l pane
        }
        else{// only r pane
          show" ~ l ~ "Button.setActive(1);
        }
        return false;
      }";
  }

