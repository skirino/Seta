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

module vector;

private import tango.io.Stdout;
private import tango.core.Array;


class Vector(T)
{
private:
  size_t size_;
  T[] array_;
  
public:
  alias T element_type;
  
  this(size_t reserved = 1)
  {
    size_ = 0;
    array_.length = reserved;
  }
  
  size_t size()  {return size_;}
  size_t length(){return size_;}
  size_t capacity(){return array_.length;}
  
  void clear(){size_ = 0;}
  
  void append(T t)
  {
    if(size_ == array_.length){
      enlarge();
    }
    array_[size_++] = t;
  }
  
  void prepend(T t)
  {
    if(size_ == array_.length){
      enlarge();
    }
    for(int i=size_-1; i>=0; --i){
      array_[i+1] = array_[i];
    }
    array_[0] = t;
    size_++;
  }
  
  T pop()
  {
    return array_[--size_];
  }
  
  void moveToHead(size_t index)
  {
    T t = array_[index];
    for(int i=index-1; i>=0; --i){
      array_[i+1] = array_[i];
    }
    array_[0] = t;
  }
  
  T opIndex(size_t i)
  {
    // note that for valued types T, returned element is copied, not reference to the same element
    return array_[i];
  }
  
  void opIndexAssign(T val, size_t i)
  {
    return array_[i] = val;
  }
  
  T[] array()
  {
    return array_[0..size_];
  }
  
  void sort(bool function(T, T) pred)
  {
    tango.core.Array.sort(array_[0..size_], pred);
  }
  
  void reserve(size_t len)
  {
    if(len > capacity()){
      array_.length = len;
    }
  }
  
  void copy(Vector!(T) v)
  {
    v.reserve(array_.length);
    v.size_ = size_;
    v.array_[0 .. size_] = array_[0 .. size_];
  }
  
  void filter(FilterFunc)(Vector!(T) v, FilterFunc filter)
  {
    v.clear();
    foreach(elem; array()){
      if(filter(elem)){
        v.append(elem);
      }
    }
  }
  
  void swap(Vector!(T) v)
  {
    if(v !is this){
      size_t temp = v.size_;
      v.size_ = size_;
      size_ = temp;
      T[] array = v.array_;
      v.array_ = array_;
      array_ = array;
    }
  }
  
private:
  void enlarge()
  {
    reserve(2 * array_.length);
  }
}


private Vector!(char[]) explicitInstantiationToAvoidLinkerError;
