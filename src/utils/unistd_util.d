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

module utils.unistd_util;

import glib.Str;

import std.string;
import core.sys.posix.unistd;
import core.sys.posix.stdlib;

import utils.string_util;


string ReadLink(const string path, char[] buffer)
{
  ssize_t len = readlink(Str.toStringz(path), buffer.ptr, buffer.length);
  if(len != -1){
    return AppendSlash(buffer[0 .. len].idup);
  }
  else{
    return null;
  }
}


string RealPath(const string path, char[] buffer)
{
  char * ptr = realpath(Str.toStringz(path), buffer.ptr);
  if(ptr){
    return AppendSlash(Str.toString(ptr));
  }
  else{
    return null;
  }
}


void ForkExec(string executablePath, string childDir, string[] args, string[string] envs)
{
  char*[] argv, envv;

  foreach(arg; args){
    argv ~= Str.toStringz(arg);
  }
  argv ~= null;

  foreach(key; envs.keys){
    envv ~= Str.toStringz(key ~ '=' ~ envs[key]);
  }
  envv ~= null;

  pid_t p = fork();
  if(p == 0){// child process
    chdir(Str.toStringz(childDir));
    execve(Str.toStringz(executablePath), argv.ptr, envv.ptr);
  }
}
