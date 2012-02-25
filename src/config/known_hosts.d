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

module config.known_hosts;

private import tango.io.Stdout;
private import tango.text.Util;

private import utils.stringUtil;
private import rcfile = config.rcfile;
private import sshConnection;
private import sshDialog;


private SSHConnection[] registeredHosts_;
private SSHConnection[] temporalHosts_;

SSHConnection[] GetKnownHosts(){return registeredHosts_;}


char[][] GetHostsStringList()
{
  return ToStringArray(registeredHosts_);
}

void Register(char[][] list)
{
  registeredHosts_.length = 0;
  foreach(host; list){
    auto con = new SSHConnection(host);
    if(con.IsValid()){
      registeredHosts_ ~= con;
    }
  }
}

void Unregister(SSHConnection con)
{
  SSHConnection[] temp;
  foreach(host; registeredHosts_){
    if(!host.Equals(con.getUsername(), con.getDomain())){
      temp ~= host;
    }
  }
  registeredHosts_ = temp;
}

bool HostIsLoggedIn(char[] username, char[] domain)
{
  auto con = Find(username, domain);
  return (con !is null) && (con.IsUsed());
}

void Disconnect(char[] userDomain)
{
  size_t posAtmark = locate(userDomain, '@');
  assert(posAtmark != userDomain.length);
  
  auto con = Find(userDomain[0 .. posAtmark], userDomain[posAtmark+1 .. $]);
  assert(con !is null);
  con.DecrementUseCount();
}

bool AlreadyRegistered(SSHConnection con)
{
  return Find(con.getUsername(), con.getDomain()) !is null;
}

void AddNewHost(SSHConnection con, bool save)
{
  if(save){
    registeredHosts_ ~= con;
    rcfile.AddSSHHost(con);
  }
  else{
    temporalHosts_ ~= con;
  }
}

SSHConnection Find(char[] username, char[] domain)
{
  // if the host has been registered, return it
  foreach(host; registeredHosts_){
    if(host.Equals(username, domain)){
      return host;
    }
  }
  foreach(host; temporalHosts_){
    if(host.Equals(username, domain)){
      return host;
    }
  }
  return null;
}