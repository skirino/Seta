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

module fm.prepare_entries_job;

import core.thread;
import core.stdc.string;

import gio.File;
import gio.FileIF;
import gio.FileInfo;
import gio.FileEnumerator;
import gdk.Threads;
import gtk.Widget;
import gtk.TreeView;

import utils.string_util;
import utils.vector;
import constants;
import fm.entry;
import thread_list;


class PrepareEntriesJob : Thread, StoppableOperationIF
{
private:
  mixin ListedOperationT;
  bool canceled_;
  string dir_;
  Widget fv_;

  // directory entries (reference to class fields in FileView)
  Vector!(DirEntry) entriesDAll_;
  Vector!(DirEntry) entriesFAll_;
  Vector!(DirEntry) entriesDFiltered_;
  Vector!(DirEntry) entriesFFiltered_;

  void delegate(bool, string, FileIF) setRowsCallback_;



  /////////////// fields
private:
  // enumerate
  bool remote_;
  string attributes_;
  FileIF pwdFile_;

  // filter
  bool showHidden_;
  string filterText_;

  // sort
  ColumnType sortColumn_;
  GtkSortType sortOrder_;

public:
  void SetForEnumerate(bool remote, string attr, FileIF pwdFile)
  {
    remote_ = remote;
    if(remote)
      // "owner::user" cannot be obtained from the GVFS, then switch to faster content-type
      attributes_ = attr
        .substitute(",owner::user", "")
        .substitute("standard::content-type", "standard::fast-content-type")
        .idup;
    else
      attributes_ = attr;
    pwdFile_ = pwdFile;
  }

  void SetForFilter(bool showHidden, string filter)
  {
    showHidden_ = showHidden;
    filterText_ = filter;
  }

  void SetForSort(ColumnType sortColumn, GtkSortType sortOrder)
  {
    sortColumn_ = sortColumn;
    sortOrder_ = sortOrder;
  }
  /////////////// fields



  /////////////// inside worker thread
private:

  static immutable string ReturnProcess =
    "
    threadsEnter();
    Unregister();
    threadsLeave();
    return;
    ";
  static immutable string ReturnIfCanceled =
    "if(canceled_){" ~
      ReturnProcess ~
    "}";

  static immutable string CloseAndReturnIfCanceled =
    "if(canceled_){
      enumerate.close(null);" ~
      ReturnProcess ~
    "}";

  void EnumerateFilterSort()
  {
    mixin(ReturnIfCanceled);

    // enumerate children and store them into "entriesDAll_"
    entriesDAll_.clear();
    entriesFAll_.clear();

    // this code should be surrounded by try statement
    scope enumerate = pwdFile_.enumerateChildren(attributes_, GFileQueryInfoFlags.NONE, null);

    FileInfo info;
    if(remote_){// remote
      while((info = enumerate.nextFile(null)) !is null){
        mixin(CloseAndReturnIfCanceled);

        if(info.getFileType() == GFileType.DIRECTORY)// directory
          entriesDAll_.append(new DirEntry(info, 0));
        else// file
          entriesFAll_.append(new DirEntry(info, 0, 0));
      }
    }
    else{// local
      while((info = enumerate.nextFile(null)) !is null){
        mixin(CloseAndReturnIfCanceled);

        if(info.getFileType() == GFileType.DIRECTORY)// directory
          entriesDAll_.append(new DirEntry(info, dir_));
        else// file
          entriesFAll_.append(new DirEntry(info));
      }
    }

    enumerate.close(null);

    FilterSort();
  }

  void FilterSort()
  {
    mixin(ReturnIfCanceled);

    // filter "entriesDAll_" -> "entriesDFiltered_"
    struct FilterHiddenFiles
    {
      bool opCall(DirEntry e){
        return e.GetName()[0] != '.';
      }
    }

    struct FilterByName
    {
      string filterText_;
      bool opCall(DirEntry e){
        return containsPattern(e.GetName(), filterText_);
      }
    }

    struct FilterHiddenAndName
    {
      string filterText_;
      bool opCall(DirEntry e)
      {
        string name = e.GetName();
        return name[0] != '.' && name.containsPattern(filterText_);
      }
    }

    if(filterText_.length == 0){// simply copy contents
      if(showHidden_){
        entriesDAll_.copy(entriesDFiltered_);
        entriesFAll_.copy(entriesFFiltered_);
      }
      else{
        FilterHiddenFiles f;
        entriesDAll_.filter!(FilterHiddenFiles)(entriesDFiltered_, f);
        entriesFAll_.filter!(FilterHiddenFiles)(entriesFFiltered_, f);
      }
    }
    else{
      if(showHidden_){
        FilterByName f;
        f.filterText_ = filterText_;
        entriesDAll_.filter!(FilterByName)(entriesDFiltered_, f);
        entriesFAll_.filter!(FilterByName)(entriesFFiltered_, f);
      }
      else{
        FilterHiddenAndName f;
        f.filterText_ = filterText_;
        entriesDAll_.filter!(FilterHiddenAndName)(entriesDFiltered_, f);
        entriesFAll_.filter!(FilterHiddenAndName)(entriesFFiltered_, f);
      }
    }

    mixin(ReturnIfCanceled);


    // start sorting
    switch(sortColumn_){
    case ColumnType.NAME:
      if(sortOrder_ == GtkSortType.ASCENDING){
        StoppableMPSort(entriesDFiltered_, &CompareNameAscending);
        mixin(ReturnIfCanceled);
        StoppableMPSort(entriesFFiltered_, &CompareNameAscending);
      }
      else{
        StoppableMPSort(entriesDFiltered_, &CompareNameDescending);
        mixin(ReturnIfCanceled);
        StoppableMPSort(entriesFFiltered_, &CompareNameDescending);
      }
      break;
    case ColumnType.TYPE:
      StoppableMPSort(entriesDFiltered_, &CompareNameAscending);
      mixin(ReturnIfCanceled);
      if(sortOrder_ == GtkSortType.ASCENDING){
        StoppableMPSort(entriesFFiltered_, &CompareTypeThenName!(true));
      }
      else{
        StoppableMPSort(entriesFFiltered_, &CompareTypeThenName!(false));
      }
      break;
    case ColumnType.SIZE:
      if(sortOrder_ == GtkSortType.ASCENDING){
        StoppableMPSort(entriesDFiltered_, &CompareSizeThenName!(true));
        mixin(ReturnIfCanceled);
        StoppableMPSort(entriesFFiltered_, &CompareSizeThenName!(true));
      }
      else{
        StoppableMPSort(entriesDFiltered_, &CompareSizeThenName!(false));
        mixin(ReturnIfCanceled);
        StoppableMPSort(entriesFFiltered_, &CompareSizeThenName!(false));
      }
      break;
    case ColumnType.OWNER:
      if(sortOrder_ == GtkSortType.ASCENDING){
        StoppableMPSort(entriesDFiltered_, &CompareOwnerThenName!(true));
        mixin(ReturnIfCanceled);
        StoppableMPSort(entriesFFiltered_, &CompareOwnerThenName!(true));
      }
      else{
        StoppableMPSort(entriesDFiltered_, &CompareOwnerThenName!(false));
        mixin(ReturnIfCanceled);
        StoppableMPSort(entriesFFiltered_, &CompareOwnerThenName!(false));
      }
      break;
    case ColumnType.PERMISSIONS:
      if(sortOrder_ == GtkSortType.ASCENDING){
        StoppableMPSort(entriesDFiltered_, &ComparePermissionsThenName!(true));
        mixin(ReturnIfCanceled);
        StoppableMPSort(entriesFFiltered_, &ComparePermissionsThenName!(true));
      }
      else{
        StoppableMPSort(entriesDFiltered_, &ComparePermissionsThenName!(false));
        mixin(ReturnIfCanceled);
        StoppableMPSort(entriesFFiltered_, &ComparePermissionsThenName!(false));
      }
      break;
    case ColumnType.LAST_MODIFIED:
      if(sortOrder_ == GtkSortType.ASCENDING){
        StoppableMPSort(entriesDFiltered_, &CompareLastModifiedThenName!(true));
        mixin(ReturnIfCanceled);
        StoppableMPSort(entriesFFiltered_, &CompareLastModifiedThenName!(true));
      }
      else{
        StoppableMPSort(entriesDFiltered_, &CompareLastModifiedThenName!(false));
        mixin(ReturnIfCanceled);
        StoppableMPSort(entriesFFiltered_, &CompareLastModifiedThenName!(false));
      }
      break;

    default:
    }

    mixin(ReturnIfCanceled);

    NotifyFinish();
  }

  // on finish
  void NotifyFinish()
  {
    threadsEnter();
    Unregister();
    setRowsCallback_(remote_, dir_, pwdFile_);
    threadsLeave();
  }
  /////////////// inside worker thread



public:
  this(
    bool readDisk,
    string dir,
    Widget fv,
    void delegate(bool, string, FileIF) callback,
    Vector!(DirEntry) entriesD,
    Vector!(DirEntry) entriesF,
    Vector!(DirEntry) entriesDFiltered,
    Vector!(DirEntry) entriesFFiltered)
  {
    if(readDisk)
      super(&EnumerateFilterSort);
    else
      super(&FilterSort);

    canceled_ = false;
    dir_ = dir;
    fv_ = fv;
    setRowsCallback_ = callback;

    // if(readDisk) : entriesD is already filled by valid entries
    // else         : it is necessary to read the filesystem and store entries into "entriesDAll_"
    entriesDAll_ = entriesD;
    entriesFAll_ = entriesF;
    entriesDFiltered_ = entriesDFiltered;
    entriesFFiltered_ = entriesFFiltered;

    Register();
  }

  string GetThreadListLabel(string startTime)
  {
    return "Preparing directory entries in \"" ~ dir_ ~ "\" (" ~ startTime ~ ')';
  }

  void Stop()
  {
    canceled_ = true;
  }

  string GetStopDialogLabel(string startTime)
  {
    return GetThreadListLabel(startTime) ~ ".\nStop this thread?";
  }

  gdk.Window.Window GetAssociatedWindow()
  {
    return (fv_ is null) ? null : fv_.getWindow();
  }



  ///////////////// cancellable sort (based on mpsort in coreutils package, used by e.g. /bin/ls)
private:
  /*
    Sort a vector BASE containing N pointers, placing the sorted array
    into TMP.  Compare pointers with CMP.  N must be at least 2.
  */
  bool mpsort_into_tmp(Pred)(DirEntry * base,
                             size_t n,
                             DirEntry * tmp,
                             Pred cmp)
  {
    // cancel check
    if(canceled_)
      return true;

    size_t n1 = n / 2;
    size_t n2 = n - n1;

    if(mpsort_with_tmp (base + n1, n2, tmp, cmp))
      return true;

    if(mpsort_with_tmp (base,      n1, tmp, cmp))
      return true;

    size_t a = 0;
    size_t alim = n1;
    size_t b = n1;
    size_t blim = n;
    DirEntry ba = base[a];
    DirEntry bb = base[b];

    for (;;){
      if (cmp (ba, bb) <= 0){
        *tmp++ = ba;
        a++;
        if (a == alim){
          a = b;
          alim = blim;
          break;
        }
        ba = base[a];
      }
      else{
        *tmp++ = bb;
        b++;
        if (b == blim)
          break;
        bb = base[b];
      }
    }

    core.stdc.string.memcpy (tmp, base + a, (alim - a) * DirEntry.sizeof);
    return false;
  }

  /*
    Sort a vector BASE containing N pointers, in place.  Use TMP
    (containing N / 2 pointers) for temporary storage.  Compare
    pointers with CMP.
  */
  bool mpsort_with_tmp(Pred)(DirEntry * base,
                             size_t n,
                             DirEntry * tmp,
                             Pred cmp)
  {
    if (n <= 2){
      if (n == 2){
        DirEntry p0 = base[0];
        DirEntry p1 = base[1];
        if (cmp (p0, p1) > 0){
          base[0] = p1;
          base[1] = p0;
        }
      }
      return false;
    }
    else{
      if(canceled_)// cancel check
        return true;

      size_t n1 = n / 2;
      size_t n2 = n - n1;

      if(mpsort_with_tmp (base + n1, n2, tmp, cmp))
        return true;

      if (n1 < 2){
        tmp[0] = base[0];
      }
      else{
        if(mpsort_into_tmp (base, n1, tmp, cmp))
          return true;
      }

      size_t t = 0;
      size_t tlim = n1;
      size_t b = n1;
      size_t blim = n;
      DirEntry tt = tmp[t];
      DirEntry bb = base[b];

      for (size_t i = 0; ; ){
        if (cmp (tt, bb) <= 0){
          base[i++] = tt;
          t++;
          if (t == tlim)
            break;
          tt = tmp[t];
        }
        else{
          base[i++] = bb;
          b++;
          if (b == blim){
            core.stdc.string.memcpy (base + i, tmp + t, (tlim - t) * DirEntry.sizeof);
            break;
          }
          bb = base[b];
        }
      }
      return false;
    }
  }

  void StoppableMPSort(Pred)(Vector!(DirEntry) buf, Pred pred)
  {
    size_t n = buf.size();
    if(n > 1){
      // allocate workspace needed by the mpsort
      buf.reserve(n + n/2);
      DirEntry * base = buf.array().ptr;
      mpsort_with_tmp!(Pred)(base, n, base+n, pred);
    }
  }
  ///////////////// cancellable sort (based on mpsort in coreutils package, used by e.g. /bin/ls)
}
