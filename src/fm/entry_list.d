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

module fm.entry_list;

import utils.vector;
import fm.entry;


class EntryList
{
private:
  Vector!(DirEntry) dAll_;
  Vector!(DirEntry) fAll_;
  Vector!(DirEntry) dSorted_;
  Vector!(DirEntry) fSorted_;

  // workspace to read, filter and sort entries
  Vector!(DirEntry) dTemp_;
  Vector!(DirEntry) fTemp_;
  Vector!(DirEntry) dFiltered_;
  Vector!(DirEntry) fFiltered_;


public:
  this()
  {
    dAll_ = new Vector!(DirEntry)(200);
    fAll_ = new Vector!(DirEntry)(200);
    dSorted_ = new Vector!(DirEntry)(200);
    fSorted_ = new Vector!(DirEntry)(200);
    dTemp_ = new Vector!(DirEntry)(200);
    fTemp_ = new Vector!(DirEntry)(200);
    dFiltered_ = new Vector!(DirEntry)(200);
    fFiltered_ = new Vector!(DirEntry)(200);
  }

  Vector!(DirEntry) GetDAll(){return dAll_;}
  Vector!(DirEntry) GetFAll(){return fAll_;}
  Vector!(DirEntry) GetDSorted(){return dSorted_;}
  Vector!(DirEntry) GetFSorted(){return fSorted_;}
  Vector!(DirEntry) GetDTemp(){return dTemp_;}
  Vector!(DirEntry) GetFTemp(){return fTemp_;}
  Vector!(DirEntry) GetDFiltered(){return dFiltered_;}
  Vector!(DirEntry) GetFFiltered(){return fFiltered_;}

  long NumEntriesAll()
  {
    return cast(long)(dAll_.size() + fAll_.size());
  }

  size_t NumEntriesSorted()
  {
    return dSorted_.size() + fSorted_.size();
  }

  void SwapEntries(bool withEnumerateDirEntries)()
  {
    static if(withEnumerateDirEntries){
      dTemp_.swap(dAll_);
      fTemp_.swap(fAll_);
    }
    dFiltered_.swap(dSorted_);
    fFiltered_.swap(fSorted_);
  }
}
