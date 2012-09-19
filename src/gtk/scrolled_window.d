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

module gtk.scrolled_window;

import gtk.ScrolledWindow;
import gtk.Adjustment;

import utils.min_max;


static const double STEP_INCREMENT = 1;

void ScrollUp(ScrolledWindow win)
{
  auto adj = win.getVadjustment();
  auto value = Max(adj.getLower(), adj.getValue() - STEP_INCREMENT);
  adj.setValue(value);
}

void ScrollDown(ScrolledWindow win)
{
  auto adj = win.getVadjustment();
  auto value = Min(adj.getUpper() - adj.getPageSize(), adj.getValue() + STEP_INCREMENT);
  adj.setValue(value);
}
