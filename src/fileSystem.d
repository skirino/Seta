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

module fileSystem;

private import tango.io.Stdout;
private import tango.text.Util;
private import tango.sys.Environment;

private import utils.stringUtil;
private import utils.gioUtil;


class FileSystem
{
public:// make it easier to access through Mediator class
  bool remote_;
  char[] rootDir_;
  char[] homeDir_;
  char[] pwdLocal_;
  
public:
  this(){SetLocal();}
  
  char[] SetLocal()
  {
    remote_ = false;
    rootDir_ = "/";
    homeDir_ = Environment.get("HOME") ~ '/';
    return pwdLocal_;
  }
  
  void SetRemote(char[] remoteRoot, char[] username, char[] homeDir, char[] pwdLocal)
  {
    remote_ = true;
    rootDir_ = AppendSlash(remoteRoot);
    pwdLocal_ = pwdLocal;
    
    // Try to get $(HOME) of remote filesystem.
    char[] ret = GetHomeDirFrom_etc_passwd(username);
    if(ret !is null){
      char[] vfspath = MountedVFSPath(ret);
      if(DirectoryExists(vfspath)){// can open
        homeDir_ = MountedVFSPath(ret);
        return;
      }
    }
    
    // "homeDir" is not valid.
    if(homeDir !is null){
      char[] vfspath = MountedVFSPath(homeDir);
      if(DirectoryExists(vfspath)){// can open
        homeDir_ = vfspath;
        return;
      }
    }
    
    // Both failed.
    homeDir_ = null;
  }
  
  bool LookingAtRemoteFS(char[] pwd)
  {
    return remote_ || containsPattern(pwd, "/.gvfs/sftp");
  }
  
  char[] ParentDirectory(char[] path)
  {
    return utils.stringUtil.ParentDirectory(path, rootDir_);
  }
  
  // for terminal which uses remote (native) filesystem path
  // "/home/user/.gvfs/sftp.../home/user2/somewhere/" => "/home/user2/somewhere/"
  char[] NativePath(char[] vfspath)
  {
    if(remote_){
      assert(vfspath.length >= rootDir_.length);
      return vfspath[rootDir_.length-1..$];// contents of rootDir_ before '/' should be removed
    }
    else{
      return vfspath;
    }
  }
  
  // for filer which uses locally-mounted vfs path
  char[] MountedVFSPath(char[] path)
  {
    if(remote_){
      return rootDir_[0..$-1] ~ path;
    }
    else{
      return path;
    }
  }
  
private:
  char[] GetHomeDirFrom_etc_passwd(char[] username)
  {
    char[] line = LineInFileWhichStartsWith(username ~ ':', rootDir_ ~ "etc/passwd");
    if(line !is null){
      size_t end   = locatePrior(line, ':');
      size_t start = locatePrior(line, ':', end);
      return line[start+1 .. end] ~ '/';
    }
    else{
      return null;
    }
  }
}

