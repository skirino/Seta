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

module note;

private import gtk.Notebook;
private import gtk.Widget;

private import tango.io.Stdout;

private import rcfile = config.rcfile;
private import page_list;
private import page;
private import main_window;


class Note : Notebook
{
  ////////////////////////// GUI stuff
private:
  char side_;
  SetaWindow mainWin_;

public:
  this(char lr, SetaWindow mainWin)
  {
    side_ = lr;
    mainWin_ = mainWin;

    super();
    setScrollable(1);
    setGroup(cast(void*)mainWin_);
    addOnPageAdded(&PageAdded);
    addOnPageRemoved(&LabelAllPages);
    addOnPageReordered(&LabelAllPages);
  }

  Page GetNthPage(uint n)
  {
    return cast(Page)getNthPage(n);
  }
  Page GetCurrentPage()
  {
    return GetNthPage(getCurrentPage());
  }

  void AppendNewPage(string initialDir)
  {
    auto page = new Page(
      side_,
      initialDir,
      &mainWin_.GetCWDOfChildWidget,
      &mainWin_.AppendPageCopy,// not "&AppendPageCopy", since pages can be dragged onto the other Notebook
      &mainWin_.ClosePage);
    appendPage(page, page.GetTab());
    setTabReorderable(page, 1);
    setTabDetachable(page, 1);
    setTabLabelPacking(page, 1, 1, GtkPackType.START);
    page.show();
  }

  void AppendPageCopy()
  {
    auto p = GetCurrentPage();
    string initialDir;
    if(p.LookingAtRemoteDir()){
      if(side_ == 'L'){
        initialDir = rcfile.GetInitialDirectoryLeft();
      }
      else{
        initialDir = rcfile.GetInitialDirectoryRight();
      }
    }
    else{
      initialDir = p.GetCWD();
    }
    AppendNewPage(initialDir);
  }

private:
  void LabelAllPages(Widget w, uint u, Notebook note)
  {
    uint num = getNPages();
    if(num > 0){
      setShowTabs(num-1);// show tabs when note has more than 1 pages

      for(uint i=0; i<num; ++i){
        GetNthPage(i).GetTab().SetID(side_, i+1);
      }
    }
  }

  void PageAdded(Widget w, uint u, Notebook note)
  {
    page_list.Register(cast(Page)w);
    LabelAllPages(w, u, note);
  }
  ////////////////////////// GUI stuff
}
