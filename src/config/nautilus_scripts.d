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

module config.nautilus_scripts;

private import gio.File;
private import gio.FileInfo;

private import tango.io.Stdout;
private import tango.sys.Environment;

private import utils.string_util;


class NautilusScript
{
  string path_;
  this(string path){path_ = path;}

  string GetPath(){return path_;}
  string GetName(){return GetBasename(path_);}
  int opCmp(Object rhs)
  {
    return StrCmp(path_, (cast(NautilusScript)rhs).path_);
  }
}

class ScriptsDir
{
  string path_;
  ScriptsDir[] dirs_;
  NautilusScript[] scripts_;

  this(string path)
  {
    path_ = AppendSlash(path);

    const string attributes = "standard::name,standard::type,access::can-execute";
    scope enumerate = File.parseName(path_).enumerateChildren(attributes, GFileQueryInfoFlags.NONE, null);

    GFileInfo * pinfo;
    while((pinfo = enumerate.nextFile(null)) != null){
      scope FileInfo info = new FileInfo(pinfo);
      string name = path_ ~ info.getName();

      if(info.getFileType() == GFileType.TYPE_DIRECTORY){// directory
        dirs_ ~= new ScriptsDir(name);
      }
      else{// file
        if(info.getAttributeBoolean("access::can-execute")){
          scripts_ ~= new NautilusScript(name);
        }
      }
    }

    enumerate.close(null);

    dirs_.sort;
    scripts_.sort;
  }

  string GetName(){return GetBasename(path_);}
  int opCmp(Object rhs)
  {
    return StrCmp(path_, (cast(ScriptsDir)rhs).path_);
  }

  bool IsEmpty()
  {
    return dirs_.length == 0 && scripts_.length == 0;
  }
}


private ScriptsDir top;
ScriptsDir GetScriptsDirTop(){return top;}


void Init()
{
  top = new ScriptsDir(Environment.get("HOME") ~ "/.gnome2/nautilus-scripts/");
  if(top.IsEmpty()){
    top = null;
  }
}

