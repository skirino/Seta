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

module ssh_connection;

private import gtk.Window;
private import gtk.MountOperation;

private import tango.text.Util;

private import utils.string_util;
private import shellrc = config.shellrc;


class SSHConnection : gtk.MountOperation.MountOperation
{
private:
  uint count_ = 0;
  bool bothSFTPAndSSH_;
  string homeDir_;
  string prompt_;
  string rprompt_;
  shellrc.ShellSetting shellSetting_;

public:
  void IncrementUseCount(){++count_;}
  void DecrementUseCount(){--count_;}
  bool IsUsed(){return count_ > 0;}

  string getHomeDir(){return homeDir_;}
  void setHomeDir(string home){homeDir_ = AppendSlash(home);}
  string getPrompt(){return prompt_;}
  void setPrompt(string p){prompt_ = p;}
  string getRPrompt(){return rprompt_;}
  void setRPrompt(string p){rprompt_ = p;}

  shellrc.ShellSetting GetShellSetting(){return shellSetting_;}

  void ReadShellSetting(string gvfsRoot)
  {
    // called after successful mounting

    // if already constructed, return immediately
    if(shellSetting_ !is null){
      return;
    }

    // read /etc/passwd
    string line = LineInFileWhichStartsWith(getUsername() ~ ':', gvfsRoot ~ "etc/passwd");
    if(line !is null){
      size_t end   = locatePrior(line, ':');
      size_t start = locatePrior(line, ':', end);
      string home  = line[start+1 .. end] ~ '/';
      string shell = line[end+1 .. $];

      if(home.length > 0 && shell.length > 0){
        string home2 = gvfsRoot[0 .. $-1] ~ home ~ '/';
        if(homeDir_ != home2){
          homeDir_ = home2;
        }

        shellSetting_ = new shellrc.ShellSetting(homeDir_, shell);
      }
    }
  }

  bool IsValid()
  {
    return getUsername().length > 0 && getDomain().length > 0;
  }

  this()
  {
    super(cast(Window)null);
    setPasswordSave(GPasswordSave.NEVER);
  }

  this(string[] userDomainHome)
  {
    this();

    if(2 <= userDomainHome.length || userDomainHome.length <= 5){
      setUsername(userDomainHome[0]);
      setDomain  (userDomainHome[1]);

      // first initialize by default value
      homeDir_ = "/home/" ~ getUsername() ~ '/';
      prompt_ = getUsername() ~ "@";
      rprompt_ = "";

      // substitute supplied value
      if(userDomainHome.length >= 3){
        string temp = userDomainHome[2];
        if(temp.length > 0){
          homeDir_ = AppendSlash(temp);
        }
      }

      if(userDomainHome.length >= 4){
        string temp = userDomainHome[3];
        if(temp.length > 0){
          prompt_ = temp;
        }
      }

      if(userDomainHome.length >= 5){
        string temp = userDomainHome[4];
        if(temp.length > 0){
          rprompt_ = temp;
        }
      }
    }
  }

  this(string line)
  {
    string[] userDomainHome = TrimAll(tango.text.Util.split!(char)(line, ":"));
    this(userDomainHome);
  }

  string GetUserDomain()
  {
    return getUsername() ~ '@' ~ getDomain();
  }

  bool GetBothSFTPAndSSH()
  {
    return bothSFTPAndSSH_;
  }
  void SetBothSFTPAndSSH(bool b)
  {
    bothSFTPAndSSH_ = b;
  }

  bool Equals(SSHConnection rhs)
  {
    return Equals(rhs.getUsername(), rhs.getDomain());
  }

  bool Equals(string user, string domain)
  {
    return (user == getUsername()) && (domain == getDomain());
  }

  string toStr(bool withSlash = true)()
  {
    const char separator = ':';
    string ret = getUsername() ~ separator ~ getDomain();
    if(homeDir_.length > 0){
      static if(withSlash){
        ret ~= separator ~ AppendSlash(homeDir_);
      }
      else{
        ret ~= separator ~ RemoveSlash(homeDir_);
      }
      if(prompt_.length > 0){
        ret ~= separator ~ prompt_;
        if(rprompt_.length > 0){
          ret ~= separator ~ rprompt_;
        }
      }
    }
    return ret;
  }

  string toString()
  {
    return toStr!(true);
  }
}
