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

module shellrc;

private import tango.io.Stdout;
private import tango.io.device.File;
private import tango.io.stream.Lines;
private import tango.sys.Environment;
private import tango.text.Util;

private import utils.stringUtil;


private ShellSetting localhostShell_;
ShellSetting GetLocalShellSetting(){return localhostShell_;}
void Init()
{
  localhostShell_ = new ShellSetting(Environment.get("HOME"), Environment.get("SHELL"));
}


struct ChangeDirAlias
{
  char[] command_, path_;
}


class ShellSetting
{
private:
  bool autoCd_ = false;
  ChangeDirAlias[] cdAliases_;
  
public:
  bool GetAutoCd(){return autoCd_;}
  ChangeDirAlias[] GetChangeDirAliases(){return cdAliases_;}
  
  this(char[] home, char[] shell)
  {
    if(home.length == 0 || shell.length == 0){
      return;// there's nothing I can do
    }
    
    // obtain fullpaths to the shell's rc file
    uint possh    = shell.locatePattern("sh");
    uint posslash = shell.locatePrior('/', possh);
    if(possh == shell.length || posslash == shell.length){
      return;
    }
    char[] shelltype = shell[posslash+1 .. possh+2];
    char[][] filenames =
      [
        home ~ "/." ~ shelltype ~ "rc",               // ~/.bashrc, ~/.zshrc
        home ~ "/." ~ shelltype ~ "env",              // ~/.zshenv
        "/etc/" ~ shelltype ~ "rc",                   // /etc/bashrc
        "/etc/" ~ shelltype ~ '.' ~ shelltype ~ "rc", // /etc/bash.bashrc
        "/etc/" ~ shelltype ~ '/' ~ shelltype ~ "rc", // /etc/zsh/zshrc
        "/etc/" ~ shelltype ~ '/' ~ shelltype ~ "env" // /etc/zsh/zshenv
      ];
    
    bool[char[]] filesProcessed;
    
    for(size_t i=0; i<filenames.length; ++i){
      char[] filename = filenames[i];
      if(!(filename in filesProcessed)){
        filesProcessed[filename] = true;
        char[][] srcs = ReadFile(filename, home);
        filenames ~= srcs;
      }
    }
  }
  
private:
  char[][] ReadFile(char[] filename, char[] home)
  {
    char[][] fileList;
    
    try{
      scope file = new File(filename);
      scope lines = new Lines!(char)(file);
      foreach(line; lines){
        char[] l = trim(line);
        
        // search for lines such as "alias cdu='cd ..'"
        // assume Bourne-like shell
        if(l.StartsWith("alias ")){// alias command
          char[] l2 = l[6 .. $];// line after "alias "
          uint posequal = l2.locate('=');
          if(posequal != l2.length){// contains '='
            char[] rhs = Extract1stArg(l2[posequal+2 .. $-1]);// rhs should be quoted by ' or ", remove them
            if(rhs.StartsWith("cd ")){
              char[] command = l2[0 .. posequal];// lhs
              char[] path = AppendSlash(trim(rhs[3 .. $]));// rhs after "cd " with last slash appended
              cdAliases_ ~= ChangeDirAlias(command, path);
            }
          }
        }
        
        // search for "setopt auto_cd"
        if(l.StartsWith("setopt ")){
          char[] l2 = triml(l[7 .. $]);
          if(l2 == "auto_cd"){// line after "setopt "
            autoCd_ = true;
          }
        }
        
        // "source" command
        if(l.StartsWith("source ")){
          char[] args = triml(l[7 .. $]);
          // currently only 1 file (specified by the 1st argument) is processed
          char[] arg = Extract1stArg(args);
          fileList ~= home ~ '/' ~ ExpandEnvVars(arg);
        }
      }
      
      file.close;
    }
    catch(Exception ex){}// IOException: no such file or directory
    
    return fileList;
  }
}

