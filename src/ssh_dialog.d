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

private import gtk.Widget;
private import gtk.Dialog;
private import gtk.Label;
private import gtk.Entry;
private import gtk.RadioButton;
private import gtk.Menu;
private import gtk.MenuItem;
private import gtk.VBox;
private import gtk.Table;
private import gtk.HSeparator;
private import gtk.ScrolledWindow;
private import gtk.TreeIter;
private import gtk.TreePath;
private import gtk.TreeView;
private import gtk.TreeViewColumn;

private import utils.string_util;
private import utils.tree_util;
private import constants;
private import rcfile = config.rcfile;
private import config.known_hosts;
private import config.hosts_view;
private import ssh_connection;


// Ask domain name of the remote host to be connected
SSHConnection SSHConnectionDialog()
{
  scope d = new StartSSHDialog;
  d.showAll();
  d.run();

  SSHConnection ret = d.ret;
  return ret;
}


class StartSSHDialog : Dialog
{
  Label label1, label2, label3, label4, label5;
  Entry entry1, entry2, entry3, entry4, entry5;
  RadioButton radio1, radio2;
  SSHConnection ret;
  HostView hosts;
  TreeIter iterCursor;

  this()
  {
    super();
    setDefaultSize(640, 400);
    addOnResponse(&Respond);

    VBox contentArea = getContentArea();
    contentArea.setSpacing(5);

    // RadioButton to choose whether to use SSH or not
    radio1 = new RadioButton("both sftp(gvfs) and ssh");
    radio1.setTooltipText("Mount remote filesystem using gvfs (file manager) and connect to the remotehost using SSH (terminal).\nShell commands will be executed by the remotehost.");
    contentArea.add(radio1);
    radio2 = new RadioButton(radio1, "only sftp(gvfs)");
    radio2.setTooltipText("Mount remote filesystem using gvfs (file manager) and move to the mounted directory (terminal).\nKeep working within the localhost.");
    contentArea.add(radio2);
    contentArea.add(new HSeparator());

    // Entries to directly type user name and host name
    label1 = new Label("user name");
    entry1 = new Entry("");

    label2 = new Label("host name");
    entry2 = new Entry("");

    label3 = new Label("home directory (optional)");
    entry3 = new Entry("");
    const string tooltip3 = "Home directory in the remote host for user.";
    label3.setTooltipText(tooltip3);
    entry3.setTooltipText(tooltip3);

    label4 = new Label("PROMPT (optional)");
    entry4 = new Entry("");
    const string tooltip4 = "$PROMPT in the remote shell such as \"username@system\".\nWorks as a hint to extract command-line arguments in terminal.";
    label4.setTooltipText(tooltip4);
    entry4.setTooltipText(tooltip4);

    label5 = new Label("RPROMPT (optional)");
    entry5 = new Entry("");
    const string tooltip5 = "$RPROMPT in zsh.\nWorks as a hint to extract command-line arguments in terminal.";
    label5.setTooltipText(tooltip5);
    entry5.setTooltipText(tooltip5);

    // set home directory as the default in most cases
    entry1.addOnFocusOut(&SetDefaultFromUsername);

    // connect pressing Enter on entries
    entry1.addOnActivate(&ActivateEntry);
    entry2.addOnActivate(&ActivateEntry);
    entry3.addOnActivate(&ActivateEntry);
    entry4.addOnActivate(&ActivateEntry);
    entry5.addOnActivate(&ActivateEntry);

    // pack them into a table widget
    Table table = new Table(5, 2, 0);
    table.attachDefaults(label1, 0, 1, 0, 1);
    table.attachDefaults(entry1, 1, 2, 0, 1);
    table.attachDefaults(label2, 0, 1, 1, 2);
    table.attachDefaults(entry2, 1, 2, 1, 2);
    table.attachDefaults(label3, 0, 1, 2, 3);
    table.attachDefaults(entry3, 1, 2, 2, 3);
    table.attachDefaults(label4, 0, 1, 3, 4);
    table.attachDefaults(entry4, 1, 2, 3, 4);
    table.attachDefaults(label5, 0, 1, 4, 5);
    table.attachDefaults(entry5, 1, 2, 4, 5);
    contentArea.add(table);
    contentArea.add(new HSeparator());

    hosts = new HostView;
    hosts.addOnRowActivated(&RowActivated);
    hosts.addOnCursorChanged(&CursorChanged);
    hosts.addOnButtonPress(&ButtonPress);
    auto sw = new ScrolledWindow(GtkPolicyType.AUTOMATIC, GtkPolicyType.AUTOMATIC);
    sw.add(hosts);
    contentArea.add(sw);

    addButton("_Cancel", GtkResponseType.GTK_RESPONSE_CANCEL);
    addButton("_OK", GtkResponseType.GTK_RESPONSE_OK);

    // focus first row of "hosts"
    hosts.grabFocus();
    TreeIter iter = GetIterFirst(hosts.getModel());
    if(iter !is null){
      TreePath path = iter.getTreePath();
      hosts.setCursor(path, null, 0);
      path.free();
    }
  }

  void ActivateEntry(Entry e)
  {
    response(GtkResponseType.GTK_RESPONSE_OK);
  }

  bool SetDefaultFromUsername(GdkEventFocus * ef, Widget w)
  {
    string username = entry1.getText();
    if(username.length > 0){
      entry3.setText("/home/" ~ username ~ '/');
      entry4.setText(username ~ '@');
    }
    return false;
  }

  void RowActivated(TreePath path, TreeViewColumn col, TreeView view)
  {
    SetRowContents(path, view);
    response(GtkResponseType.GTK_RESPONSE_OK);
  }

  void CursorChanged(TreeView view)
  {
    TreePath path = GetPathAtCursor(view);
    SetRowContents(path, view);
    path.free();
  }

  void SetRowContents(TreePath path, TreeView view)
  {
    SetRowContents(GetIter(view.getModel(), path));
  }

  void SetRowContents(TreeIter iter)
  {
    entry1.setText(NonnullString(iter.getValueString(0)));
    entry2.setText(NonnullString(iter.getValueString(1)));
    entry3.setText(NonnullString(iter.getValueString(2)));
    entry4.setText(NonnullString(iter.getValueString(3)));
    entry5.setText(NonnullString(iter.getValueString(4)));
  }

  bool ButtonPress(GdkEventButton * eb, Widget w)
  {
    if(eb.window != hosts.getBinWindow().getWindowStruct()){// header is clicked
      return false;
    }

    if(eb.button != MouseButton.RIGHT){// not right button
      return false;
    }

    TreePath path = GetPathAtPos(hosts, eb.x, eb.y);
    if(path is null){// empty space
      return false;
    }

    // set TreeIter
    iterCursor = GetIter(hosts.getModel(), path);
    path.free();

    // menu for "Connect", "Unregister"
    auto menu = new Menu;
    menu.append(new MenuItem(&ConnectCallback, "_Connect"));
    menu.append(new MenuItem(&UnregisterCallback, "_Unregister"));
    menu.showAll();
    menu.popup(0, eb.time);

    return false;
  }

  void ConnectCallback(MenuItem item)
  {
    SetRowContents(iterCursor);
    response(GtkResponseType.GTK_RESPONSE_OK);
  }

  void UnregisterCallback(MenuItem item)
  {
    // make SSHConnection object
    string[] userDomainHome;
    for(uint i=0; i<5; ++i){
      userDomainHome ~= iterCursor.getValueString(i);
    }
    auto con = new SSHConnection(userDomainHome);
    rcfile.RemoveSSHHost(con);
    hosts.GetListStore().remove(iterCursor);
  }

  void Respond(int responseID, Dialog dialog)
  {
    if(responseID == GtkResponseType.GTK_RESPONSE_OK){// connect to the host inputted in Entry widgets
      string username = entry1.getText();
      string domain   = entry2.getText();
      if(username.length > 0 && domain.length > 0){

        ret = Find(username, domain);
        if(ret is null){
          ret = new SSHConnection;
          ret.setUsername(username);
          ret.setDomain(domain);

          string home = entry3.getText();
          if(home.length == 0){// set default value
            home = "/home/" ~ ret.getUsername() ~ '/';
          }
          ret.setHomeDir(home);

          string prompt = entry4.getText();
          if(prompt.length == 0){// set default value
            prompt = ret.getUsername() ~ '@';
          }
          ret.setPrompt(prompt);

          string rprompt = entry5.getText();
          if(rprompt.length > 0){
            ret.setRPrompt(rprompt);
          }
        }
        ret.SetBothSFTPAndSSH(radio1.getActive() != 0);
      }
      destroy();
    }
    else{// canceled
      destroy();
    }
  }
}
