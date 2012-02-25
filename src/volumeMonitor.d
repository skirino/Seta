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

module volumeMonitor;

private import gio.VolumeMonitor;
private import gio.Mount;
private import gio.MountIF;
private import gtkc.gio;
private import glib.ListG;

private import tango.io.Stdout;

private import utils.stringUtil;
private import statusbar;
private import pageList;


private struct MountedVolumeMonitor
{
private:
  VolumeMonitor volumeMonitor_;
  string[] names_;
  string[] paths_;
  
  void Init()
  {
    // for an unknown reason (maybe GtkD's bug)
    // it seems necessary to directly call the GIO API to construct a VolumeMonitor object
    GVolumeMonitor * pMonitor = g_volume_monitor_get();
    volumeMonitor_ = new VolumeMonitor(pMonitor);
    volumeMonitor_.addOnMountAdded(  &NotifyMount);
    volumeMonitor_.addOnMountRemoved(&NotifyUnmount);
    RescanAll();
  }
  
  void NotifyMount(MountIF mount, VolumeMonitor monitor)
  {
    PushIntoStatusbar("\"" ~ mount.getName() ~ "\" was mounted");
    RescanAll();
    pageList.NotifyReconstructShortcuts();
  }
  
  void NotifyUnmount(MountIF mount, VolumeMonitor monitor)
  {
    string name = mount.getName();
    PushIntoStatusbar("\"" ~ name ~ "\" was unmounted");
    
    string[] oldpaths = paths_.dup;// explicitly make copy of dynamic array
    RescanAll();
    
    if(name.StartsWith("sftp (")){
      // BUG? gvfsRoot cannot be obtained by "mount.getRoot().getPath() ~ '/'".
      // Take diff between "oldpaths" and "paths_"
      foreach(p; oldpaths){
        bool found = false;
        foreach(path; paths_){
          if(p == path){
            found = true;
            break;
          }
        }
        if(!found){
          pageList.NotifyFilerDisconnect(name, p);
          break;
        }
      }
    }
    pageList.NotifyReconstructShortcuts();
  }
  
  void RescanAll()
  {
    names_.length = 0;
    paths_.length = 0;
    
    auto list = volumeMonitor_.getMounts();
    while(list !is null){
      auto mount = new Mount(cast(GMount*)list.data());
      names_ ~= mount.getName();
      paths_ ~= mount.getRoot().getPath() ~ '/';
      list = list.next();
    }
    
    // sort volumes by their paths
    size_t len = names_.length;
    for(size_t i=0; i<len; ++i){
      for(size_t j=i; j<len; ++j){
        if(paths_[i] > paths_[j]){
          string temp;
          temp = paths_[i]; paths_[i] = paths_[j]; paths_[j] = temp;
          temp = names_[i]; names_[i] = names_[j]; names_[j] = temp;
        }
      }
    }
  }
}

private MountedVolumeMonitor monitorInstance;


void Init()
{
  monitorInstance.Init();
}


void QueryMountedVolumes(out string[] names, out string[] paths)
{
  names = monitorInstance.names_;
  paths = monitorInstance.paths_;
}


string GetPathToNthVolume(size_t n)
{
  if(n < monitorInstance.paths_.length){
    return monitorInstance.paths_[n];
  }
  else{
    return null;
  }
}


bool UnmountByPath(string path)
{
  ListG list = monitorInstance.volumeMonitor_.getMounts();
  
  while(list !is null){
    auto mount = new Mount(cast(GMount*)list.data());
    string volumePath = mount.getRoot().getPath() ~ '/';
    if(volumePath == path){// found
      mount.unmountWithOperation(GMountUnmountFlags.NONE, null, null, null, null);
      return true;
    }
    list = list.next();
  }
  
  // "path" not found
  return false;
}
