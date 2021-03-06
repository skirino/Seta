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

module note;

import gtk.Notebook;
import gtk.Widget;
import gobject.Value;

import constants : Side;
import rcfile = config.rcfile;
import config.page_init_option;
import page;
import seta_window;

class Note : Notebook
{
private:
  immutable Side side_;
  SetaWindow mainWin_;

public:
  this(Side side, SetaWindow mainWin) {
    side_ = side;
    mainWin_ = mainWin;
    super();
    setShowTabs(true);
    setScrollable(1);
    setGroupName("Seta notebook");
    addOnPageAdded(&PageAdded);
    addOnPageRemoved(&LabelAllPages);
    addOnPageReordered(&LabelAllPages);
  }

  Page GetNthPage(uint n) {
    return cast(Page)getNthPage(n);
  }

  Page GetCurrentPage() {
    return GetNthPage(getCurrentPage());
  }

  void AppendNewPage(PageInitOption opt) {
    auto page = new Page(side_, opt, &mainWin_.GetCWDOfChildWidget, &mainWin_.ClosePage);
    appendPage(page, page.GetTab());
    setTabReorderable(page, 1);
    setTabDetachable(page, 1);
    page.show();
    setCurrentPage(getNPages() - 1);
  }

  void AppendNewPage() {
    auto dir = GetInitialDirectoryBySide();
    AppendNewPage(PageInitOption(dir, null));
  }

  void AppendPageCopy() {
    auto dir = GetCurrentPage().GetCWD();
    AppendNewPage(PageInitOption(dir, null));
  }

private:
  string GetInitialDirectoryBySide() {
    if(side_ == Side.LEFT) {
      return rcfile.GetDefaultInitialDirectoryLeft();
    } else {
      return rcfile.GetDefaultInitialDirectoryRight();
    }
  }

  void LabelAllPages(Widget w, uint u, Notebook note) {
    uint num = getNPages();
    for(uint i = 0; i < num; ++i) {
      GetNthPage(i).GetTab().SetID(side_, i + 1);
    }
  }

  void PageAdded(Widget w, uint u, Notebook note) {
    LabelAllPages(w, u, note);
  }
}
