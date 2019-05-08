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

module utils.ref_util;

import std.exception;

struct Nonnull(T) if(is(T == class) || is(T == interface))
{
private:
  T _Nonnull_t;

public:
  @disable void opAssign(Nonnull!(T) rhs);
  void init(T t) {
    enforce(_Nonnull_t is null, "!!! Nonnull 1");
    enforce(t         !is null, "!!! Nonnull 2");
    _Nonnull_t = t;
  }
  this(T t) { init(t); }
  T _Nonnull_get() { return _Nonnull_t; }
  alias _Nonnull_get this;
}

unittest
{
  void AssertThrowBase(bool b, R)(R delegate() f) {
    bool thrown;
    try {
      f();
    } catch(Exception) { thrown = true; }
    assert(thrown == b);
  }
  void ShouldThrow(R)(R delegate() f) {
    AssertThrowBase!(true, R)(f);
  }
  void ShouldNotThrow(R)(R delegate() f) {
    AssertThrowBase!(false, R)(f);
  }

  class X
  {
    int x;
    void f1() { x = 1; }
    int f2(int a, int b) { return x + a + b; }
  }
  int func(X x) { return x.x; }

  ShouldThrow   (() => Nonnull!X(null));
  ShouldNotThrow(() => Nonnull!X());
  ShouldNotThrow(() => Nonnull!X().init(new X));
  ShouldThrow   (() => Nonnull!X().init(null));
  ShouldThrow   (delegate void() { auto n = Nonnull!X(); n.init(new X); n.init(new X); });

  auto n = Nonnull!X(new X);
  assert(n._Nonnull_t.x == 0);
  n.f1();
  assert(n._Nonnull_t.x == 1);
  assert(n.x == 1);
  assert(func(n) == 1);
  assert(n.f2(2, 3) == 6);
}
