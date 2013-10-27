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

module ssh_dialog;

import gtk.Widget;
import gtk.Dialog;
import gtk.Label;
import gtk.Entry;
import gtk.RadioButton;
import gtk.MenuItem;
import gtk.VBox;
import gtk.Table;
import gtk.HSeparator;
import gtk.ScrolledWindow;
import gtk.TreeIter;
import gtk.TreePath;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gdk.Event;

import utils.string_util;
import utils.tree_util;
import utils.menu_util;
import constants;
import rcfile = config.rcfile;
import config.known_hosts;
import config.hosts_view;
import ssh_connection;


// Ask domain name of the remote host to be connected
SSHConnection SSHConnectionDialog()
{
  scope d = new StartSSHDialog;
  d.showAll();
  d.run();

  SSHConnection ret = d.connection_;
  return ret;
}


class StartSSHDialog : Dialog
{
  Entry entry1_, entry2_, entry3_, entry4_, entry5_;
  RadioButton radio1_;
  SSHConnection connection_;
  HostView hostsView_;
  TreeIter iterCursor_;

  this()
  {
    super();
    setDefaultSize(640, 400);
    addOnResponse(&Respond);

    VBox contentArea = getContentArea();
    contentArea.setSpacing(5);

    // RadioButton to choose whether to use SSH or not
    radio1_ = new RadioButton("both sftp(gvfs) and ssh");
    radio1_.setTooltipText("Mount remote filesystem using gvfs (file manager) and connect to the remotehost using SSH (terminal).\nShell commands will be executed by the remotehost.");
    contentArea.add(radio1_);
    auto radio2 = new RadioButton(radio1_, "only sftp(gvfs)");
    radio2.setTooltipText("Mount remote filesystem using gvfs (file manager) and move to the mounted directory (terminal).\nKeep working within the localhost.");
    contentArea.add(radio2);
    contentArea.add(new HSeparator());

    // Entries to directly type user name and host name
    auto label1 = new Label("user name");
    entry1_ = new Entry("");

    auto label2 = new Label("host name");
    entry2_ = new Entry("");

    auto label3 = new Label("home directory (optional)");
    entry3_ = new Entry("");
    const string tooltip3 = "Home directory in the remote host for user.";
    label3.setTooltipText(tooltip3);
    entry3_.setTooltipText(tooltip3);

    auto label4 = new Label("PROMPT (optional)");
    entry4_ = new Entry("");
    const string tooltip4 = "$PROMPT in the remote shell such as \"username@system\".\nWorks as a hint to extract command-line arguments in terminal.";
    label4.setTooltipText(tooltip4);
    entry4_.setTooltipText(tooltip4);

    auto label5 = new Label("RPROMPT (optional)");
    entry5_ = new Entry("");
    const string tooltip5 = "$RPROMPT in zsh.\nWorks as a hint to extract command-line arguments in terminal.";
    label5.setTooltipText(tooltip5);
    entry5_.setTooltipText(tooltip5);

    // set home directory as the default in most cases
    entry1_.addOnFocusOut(&SetDefaultFromUsername);

    // connect pressing Enter on entries
    entry1_.addOnActivate(&ActivateEntry);
    entry2_.addOnActivate(&ActivateEntry);
    entry3_.addOnActivate(&ActivateEntry);
    entry4_.addOnActivate(&ActivateEntry);
    entry5_.addOnActivate(&ActivateEntry);

    // pack them into a table widget
    Table table = new Table(5, 2, 0);
    table.attachDefaults(label1, 0, 1, 0, 1);
    table.attachDefaults(entry1_, 1, 2, 0, 1);
    table.attachDefaults(label2, 0, 1, 1, 2);
    table.attachDefaults(entry2_, 1, 2, 1, 2);
    table.attachDefaults(label3, 0, 1, 2, 3);
    table.attachDefaults(entry3_, 1, 2, 2, 3);
    table.attachDefaults(label4, 0, 1, 3, 4);
    table.attachDefaults(entry4_, 1, 2, 3, 4);
    table.attachDefaults(label5, 0, 1, 4, 5);
    table.attachDefaults(entry5_, 1, 2, 4, 5);
    contentArea.add(table);
    contentArea.add(new HSeparator());

    hostsView_ = new HostView;
    hostsView_.addOnRowActivated(&RowActivated);
    hostsView_.addOnCursorChanged(&CursorChanged);
    hostsView_.addOnButtonPress(&ButtonPress);
    auto sw = new ScrolledWindow(GtkPolicyType.AUTOMATIC, GtkPolicyType.AUTOMATIC);
    sw.add(hostsView_);
    contentArea.packStart(sw, 1, 1, 5);

    addButton("_Cancel", GtkResponseType.CANCEL);
    addButton("_OK",     GtkResponseType.OK);

    // focus first row of "hostsView_"
    hostsView_.grabFocus();
    TreeIter iter = GetIterFirst(hostsView_.getModel());
    if(iter !is null){
      hostsView_.setCursor(iter.getTreePath(), null, 0);
    }
  }

  void ActivateEntry(Entry e)
  {
    response(GtkResponseType.OK);
  }

  bool SetDefaultFromUsername(Event e, Widget w)
  {
    string username = entry1_.getText();
    if(username.length > 0){
      entry3_.setText("/home/" ~ username ~ '/');
      entry4_.setText(username ~ '@');
    }
    return false;
  }

  void RowActivated(TreePath path, TreeViewColumn col, TreeView view)
  {
    SetRowContents(path, view);
    response(GtkResponseType.OK);
  }

  void CursorChanged(TreeView view)
  {
    SetRowContents(GetPathAtCursor(view), view);
  }

  void SetRowContents(TreePath path, TreeView view)
  {
    if(path is null)
      return;
    SetRowContents(GetIter(view.getModel(), path));
  }

  void SetRowContents(TreeIter iter)
  {
    entry1_.setText(NonnullString(iter.getValueString(0)));
    entry2_.setText(NonnullString(iter.getValueString(1)));
    entry3_.setText(NonnullString(iter.getValueString(2)));
    entry4_.setText(NonnullString(iter.getValueString(3)));
    entry5_.setText(NonnullString(iter.getValueString(4)));
  }

  bool ButtonPress(Event e, Widget w)
  {
    auto eb = e.button();

    if(eb.window != hostsView_.getBinWindow().getWindowStruct())// header is clicked
      return false;
    if(eb.button != MouseButton.RIGHT)// not right button
      return false;

    TreePath path = GetPathAtPos(hostsView_, eb.x, eb.y);
    if(path is null)// empty space
      return false;
    iterCursor_ = GetIter(hostsView_.getModel(), path);

    // menu for "Connect", "Unregister"
    auto menu = new MenuWithMargin;
    menu.append(new MenuItem(&ConnectCallback, "_Connect"));
    menu.append(new MenuItem(&UnregisterCallback, "_Unregister"));
    menu.showAll();
    menu.popup(0, eb.time);

    return false;
  }

  void ConnectCallback(MenuItem item)
  {
    SetRowContents(iterCursor_);
    response(GtkResponseType.OK);
  }

  void UnregisterCallback(MenuItem item)
  {
    // make SSHConnection object
    string[] userDomainHome;
    for(uint i=0; i<5; ++i){
      userDomainHome ~= iterCursor_.getValueString(i);
    }
    auto con = new SSHConnection(userDomainHome);
    rcfile.RemoveSSHHost(con);
    hostsView_.GetListStore().remove(iterCursor_);
  }

  void Respond(int responseID, Dialog dialog)
  {
    if(responseID == GtkResponseType.OK){// connect to the host inputted in Entry widgets
      string username = entry1_.getText();
      string domain   = entry2_.getText();
      if(username.length > 0 && domain.length > 0){

        connection_ = Find(username, domain);
        if(connection_ is null){
          connection_ = new SSHConnection;
          connection_.setUsername(username);
          connection_.setDomain(domain);

          string home = entry3_.getText();
          if(home.length == 0){// set default value
            home = "/home/" ~ connection_.getUsername() ~ '/';
          }
          connection_.setHomeDir(home);

          string prompt = entry4_.getText();
          if(prompt.length == 0){// set default value
            prompt = connection_.getUsername() ~ '@';
          }
          connection_.setPrompt(prompt);

          string rprompt = entry5_.getText();
          if(rprompt.length > 0){
            connection_.setRPrompt(rprompt);
          }
        }
        connection_.SetBothSFTPAndSSH(radio1_.getActive() != 0);
      }
    }
    destroy();
  }
}
