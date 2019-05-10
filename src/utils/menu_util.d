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

module utils.menu_util;

import gtk.Menu;

class MenuWithMargin : Menu
{
  static immutable int DEFAULT_MARGIN = 1;

  this() {
    super();
    setMarginLeft  (DEFAULT_MARGIN);
    setMarginRight (DEFAULT_MARGIN);
    setMarginTop   (DEFAULT_MARGIN);
    setMarginBottom(DEFAULT_MARGIN);
  }
}
