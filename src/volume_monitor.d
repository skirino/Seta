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

module volume_monitor;

import gio.VolumeMonitor;
import gio.Mount;
import gio.MountIF;
import gtkc.gio;
import glib.ListG;
import glib.Timeout;

import std.algorithm;

import utils.string_util;
import page_list;
import statusbar;


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
    page_list.NotifyReconstructShortcuts();
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
          page_list.NotifyFilerDisconnect(name, p);
          break;
        }
      }
    }
    page_list.NotifyReconstructShortcuts();
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

private __gshared MountedVolumeMonitor monitorInstance;


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



// Unmount mouted volume
const int STATE_IDLE    = 0;
const int STATE_FAILED  = 1;
const int STATE_RUNNING = 2;
const int STATE_FINISH  = 3;
const int MAX_FAILED_COUNT = 10;

struct UnmountOperationArgs
{
  int state_;
  int failedCount_;
  string path_;
}
__gshared UnmountOperationArgs[] argsArray;

void UnmountByPath(string path)
{
  // Clear previously used elements in argsArray in case all elements are STATE_FINISH.
  if(all!"a.state_ == 3"(argsArray)){
    argsArray = [];
  }

  // Transfer ownership of local var to argsArray
  argsArray ~= UnmountOperationArgs(STATE_IDLE, 0, path);
  Timeout.add(500, &UnmountCallback, cast(void*)(&argsArray[$-1]));
}

extern(C) int UnmountCallback(void * data)
{
  auto args = cast(UnmountOperationArgs*)data;
  switch(args.state_){
  case STATE_IDLE:
    args.state_ = STATE_RUNNING;
    StartUnmountOperation(args);
    return 1;
  case STATE_RUNNING:
    return 1;
  case STATE_FAILED:
    if(args.failedCount_ < MAX_FAILED_COUNT){// retry
      args.state_ = STATE_IDLE;
      return 1;
    } else {// quit
      args.state_ = STATE_FINISH;
      return 0;
    }
  default:// case STATE_FINISH:
    return 0;
  }
}

void StartUnmountOperation(UnmountOperationArgs * args)
{
  ListG list = monitorInstance.volumeMonitor_.getMounts();
  while(list){
    auto mount = new Mount(cast(GMount*)list.data());
    string mountPoint = mount.getRoot().getPath() ~ '/';
    if(mountPoint == args.path_){// found
      mount.unmountWithOperation(GMountUnmountFlags.NONE, null, null,
                                 cast(GAsyncReadyCallback)&UnmountReadyCallback,
                                 cast(void*)(args));
    }
    list = list.next();
  }
}

extern(C) void UnmountReadyCallback(GMount * mount, GAsyncResult * res, void * data)
{
  auto args = cast(UnmountOperationArgs*)data;
  if(g_mount_unmount_with_operation_finish(mount, res, null)){
    args.state_ = STATE_FINISH;
  } else {
    args.state_ = STATE_FAILED;
    args.failedCount_++;
  }
}
