/*
Copyright (C) 2010 Shunsuke Kirino <shunsuke.kirino@gmail.com>

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

module templateUtil;

private import tango.io.Stdout;


template RuntimeDispatch1(char[] tmplt, char[] b, char[] args = "")
{
  const char[] RuntimeDispatch1 =
    "
    ( " ~ b ~ " ? " ~ tmplt ~ "!(true)"  ~ args ~
    "           : " ~ tmplt ~ "!(false)" ~ args ~
    ")";
}

template RuntimeDispatch2(char[] tmplt, char[] b1, char[] b2, char[] args = "")
{
  const char[] RuntimeDispatch2 =
    "
    ( " ~ b1 ~ " ? (" ~ b2 ~ " ? " ~ tmplt ~ "!(true,  true)"  ~ args ~
    "                          : " ~ tmplt ~ "!(true,  false)" ~ args ~ ")" ~
    "            : (" ~ b2 ~ " ? " ~ tmplt ~ "!(false, true)"  ~ args ~
    "                          : " ~ tmplt ~ "!(false, false)" ~ args ~ ")" ~
    ")";
}

template RuntimeDispatch3(char[] tmplt, char[] b1, char[] b2, char[] b3, char[] args = "")
{
  const char[] RuntimeDispatch3 =
    "
    ( " ~ b1 ~ " ? (" ~ b2 ~ " ? (" ~ b3 ~ " ? " ~ tmplt ~ "!(true,  true,  true)"  ~ args ~
    "                                        : " ~ tmplt ~ "!(true,  true,  false)" ~ args ~ ")" ~
    "                          : (" ~ b3 ~ " ? " ~ tmplt ~ "!(true,  false, true)"  ~ args ~
    "                                        : " ~ tmplt ~ "!(true,  false, false)" ~ args ~ ") )" ~
    "            : (" ~ b2 ~ " ? (" ~ b3 ~ " ? " ~ tmplt ~ "!(false, true,  true)"  ~ args ~
    "                                        : " ~ tmplt ~ "!(false, true,  false)" ~ args ~ ")" ~
    "                          : (" ~ b3 ~ " ? " ~ tmplt ~ "!(false, false, true)"  ~ args ~
    "                                        : " ~ tmplt ~ "!(false, false, false)" ~ args ~ ") )" ~
    ")";
}


template FoldTupple(alias templateFun, s ...)
{
  static if(s.length == 0){
    const char[] FoldTupple = "";
  }
  else{
    const char[] FoldTupple = templateFun!(s[0]) ~ FoldTupple!(templateFun, s[1 .. $]);
  }
}
