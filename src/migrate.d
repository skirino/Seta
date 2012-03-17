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

module migrate;

//private import tango.sys.Environment;
private import std.process;

string getenv(string key)
{
  return getenv(key);
  //return Environment.get(key);
}

string[string] getenvall()
{
  //environment.toAA();
  return null;
}



size_t findElement(const string[] ss, const string target)
{
  foreach(i, s; ss){
    if(s == target){
      return i;
    }
  }
  return ss.length;
}
