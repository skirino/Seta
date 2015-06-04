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

module config.shellrc;

import std.string;
import std.process;

import utils.string_util;


private __gshared ShellSetting localhostShell_;
ShellSetting GetLocalShellSetting(){ return localhostShell_; }
void Init()
{
  localhostShell_ = new ShellSetting(environment.get("HOME"), environment.get("SHELL"));
}


struct ChangeDirAlias
{
  string command_, path_;
}


class ShellSetting
{
private:
  bool autoCd_ = false;
  ChangeDirAlias[] cdAliases_;

public:
  bool GetAutoCd(){ return autoCd_; }
  ChangeDirAlias[] GetChangeDirAliases(){ return cdAliases_; }

  this(string home, string shell)
  {
    if(home.length == 0 || shell.length == 0)
      return;// there's nothing I can do

    // obtain fullpaths to the shell's rc file
    size_t possh    = shell.locatePattern("sh");
    size_t posslash = shell.locatePrior('/', possh);
    if(possh == shell.length || posslash == shell.length)
      return;
    string shelltype = shell[posslash+1 .. possh+2];

    string[] filenames =
      [
        home ~ "/." ~ shelltype ~ "rc",               // ~/.bashrc, ~/.zshrc
        home ~ "/." ~ shelltype ~ "env",              // ~/.zshenv
        "/etc/" ~ shelltype ~ "rc",                   // /etc/bashrc
        "/etc/" ~ shelltype ~ '.' ~ shelltype ~ "rc", // /etc/bash.bashrc
        "/etc/" ~ shelltype ~ '/' ~ shelltype ~ "rc", // /etc/zsh/zshrc
        "/etc/" ~ shelltype ~ '/' ~ shelltype ~ "env" // /etc/zsh/zshenv
      ];

    bool[string] filesProcessed;

    for(size_t i=0; i<filenames.length; ++i){
      string filename = filenames[i];
      if(filename !in filesProcessed){
        filesProcessed[filename] = true;
        string[] srcs = ReadFile(filename, home);
        filenames ~= srcs;
      }
    }
  }

private:
  string[] ReadFile(string filename, string home)
  {
    string[] fileList;

    EachLineInFile(filename, delegate bool(string line){
        string l = trim(line);

        // search for lines such as "alias cdu='cd ..'"
        // assume Bourne-like shell
        if(l.StartsWith("alias ")){// alias command
          string l2 = l[6 .. $];// line after "alias "
          size_t posequal = l2.locate('=');
          if(posequal != l2.length){// contains '='
            string rhs = l2[posequal+1 .. $];
            string originalCommand = trim(rhs[1 .. $-1]);// rhs should be quoted by ' or ", remove them
            if(originalCommand.StartsWith("cd ")){
              string aliasCommand = l2[0 .. posequal];// lhs
              string path = Extract1stArg(originalCommand[3 .. $]).AppendSlash();
              cdAliases_ ~= ChangeDirAlias(aliasCommand, path);
            }
          }
        }

        // search for "setopt auto_cd"
        if(l.StartsWith("setopt ")){
          string l2 = triml(l[7 .. $]);
          if(l2 == "auto_cd")// line after "setopt "
            autoCd_ = true;
        }

        // "source" command
        string args;
        if(l.StartsWith("source "))
          args = triml(l[7 .. $]);
        else if(l.StartsWith(". "))
          args = triml(l[2 .. $]);

        if(args !is null){
          // currently only 1 file (specified by the 1st argument) is processed
          string arg = args.Extract1stArg().ExpandEnvVars();
          if(arg.StartsWith("/"))
            fileList ~= arg;
          else if(arg.StartsWith("~"))
            fileList ~= home ~ arg[1 .. $];
          else
            fileList ~= home ~ '/' ~ ExpandEnvVars(arg);
        }

        return true;// continue reading this file
      });
    return fileList;
  }
}
