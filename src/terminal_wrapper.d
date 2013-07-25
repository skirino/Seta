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

module terminal_wrapper;

import gtk.HBox;
import gtk.VScrollbar;

import utils.ref_util;
import terminal;
import mediator;


class TerminalWrapper : HBox
{
private:
  Nonnull!Terminal terminal_;

public:
  this(Mediator m,
       string initialDir,
       string delegate(char, uint) GetCWDFromMain)
  {
    super(0, 0);
    terminal_.init(new Terminal(m, initialDir, GetCWDFromMain));
    packStart(terminal_, true, true, 0);
    auto vscrollbar = new VScrollbar(terminal_.getVadjustment());
    packStart(vscrollbar, false, false, 0);
  }

  Terminal Get(){ return terminal_; }
}
