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

module hostView;

private import gtk.TreeView;
private import gtk.TreeViewColumn;
private import gtk.TreeIter;
private import gtk.ListStore;
private import gtk.CellRendererText;

private import tango.io.Stdout;
private import tango.text.Util;

private import utils.stringUtil;
static private import config;


class HostView : TreeView
{
private:
  TreeViewColumn colUser_, colHost_, colHome_, colPrompt_, colRPrompt_;
  CellRendererText rendUser_, rendHost_, rendHome_, rendPrompt_, rendRPrompt_;
  ListStore hostsStore_;
  
public:
  this()
  {
    super();
    setSizeRequest(-1, 160);
    
    rendUser_ = new CellRendererText;
    colUser_ = new TreeViewColumn("user name", rendUser_, "text", 0);
    colUser_.setResizable(1);
    appendColumn(colUser_);
    
    rendHost_ = new CellRendererText;
    colHost_ = new TreeViewColumn("host name", rendHost_, "text", 1);
    colHost_.setResizable(1);
    appendColumn(colHost_);
    
    rendHome_ = new CellRendererText;
    colHome_ = new TreeViewColumn("home directory", rendHome_, "text", 2);
    colHome_.setResizable(1);
    appendColumn(colHome_);
    
    rendPrompt_ = new CellRendererText;
    colPrompt_ = new TreeViewColumn("PROMPT", rendPrompt_, "text", 3);
    colPrompt_.setResizable(1);
    appendColumn(colPrompt_);
    
    rendRPrompt_ = new CellRendererText;
    colRPrompt_ = new TreeViewColumn("RPROMPT", rendRPrompt_, "text", 4);
    colRPrompt_.setResizable(1);
    appendColumn(colRPrompt_);
    
    //                           user          host          home          prompt        rprompt
    hostsStore_ = new ListStore([GType.STRING, GType.STRING, GType.STRING, GType.STRING, GType.STRING]);
    setModel(hostsStore_);
    
    foreach(host; config.GetSSHHosts()){
      TreeIter iter = new TreeIter;
      hostsStore_.append(iter);
      
      string[] items = TrimAll(split!(char)(host, ":"));
      foreach(i, item; items){
        hostsStore_.setValue(iter, i, item);
      }
    }
  }
  
  ListStore GetListStore(){return hostsStore_;}
  
  void SetEditable(
    void delegate(string, string, CellRendererText) cb0,
    void delegate(string, string, CellRendererText) cb1,
    void delegate(string, string, CellRendererText) cb2,
    void delegate(string, string, CellRendererText) cb3,
    void delegate(string, string, CellRendererText) cb4)
  {
    rendUser_.setProperty("editable", 1);
    rendHost_.setProperty("editable", 1);
    rendHome_.setProperty("editable", 1);
    rendPrompt_.setProperty("editable", 1);
    rendRPrompt_.setProperty("editable", 1);
    rendUser_.addOnEdited(cb0);
    rendHost_.addOnEdited(cb1);
    rendHome_.addOnEdited(cb2);
    rendPrompt_.addOnEdited(cb3);
    rendRPrompt_.addOnEdited(cb4);
  }
}
