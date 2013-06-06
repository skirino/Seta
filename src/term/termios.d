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

module term.termios;

import core.sys.posix.termios;
import std.stdio;


/+
 Constants defined in
 [1] /usr/include/bits/termios.h   (C, linux)
 [2] /usr/include/sys/termios.h        (C, OSX)
 [3] phobos core.sys.posix.termios (D, version=linux)
 [4] phobos core.sys.posix.termios (D, version=OSX)

+-------+-----------+-------------+-------------+-------------+-------------+
|       |   FIELD   | [1] c-linux | [2] c-OSX   | [3] d-linux | [4] d-OSX   |
+-------+-----------+-------------+-------------+-------------+-------------+
|       |  BRKINT   |    02       |    02       |    02       |    02       |
|       +-----------+-------------+-------------+-------------+-------------+
|       |  IGNPAR   |    04       |    04       |    04       |    04       |
|       +-----------+-------------+-------------+-------------+-------------+
|       |  INLCR    |    0100     |    0100     |    0100     |    0100     |
|       +-----------+-------------+-------------+-------------+-------------+
|       |  ICRNL    |    0400     |    0400     |    0400     |    0400     |
| iflag +-----------+-------------+-------------+-------------+-------------+
|       |  IXON     |    02000    |    0x200    |    02000    |    0x200    | (different value)
|       +-----------+-------------+-------------+-------------+-------------+
|       |  IXANY    |    04000    |    0x800    |    04000    |             |
|       +-----------+-------------+-------------+-------------+-------------+
|       |  IMAXBEL  |    020000   |    0x2000   |             |             |
|       +-----------+-------------+-------------+-------------+-------------+
|       |  IUTF8    |    040000   |    0x4000   |             |             |
+-------+-----------+-------------+-------------+-------------+-------------+
|       |  OPOST    |    01       |    01       |    01       |    01       |
| oflag +-----------+-------------+-------------+-------------+-------------+
|       |  ONLCR    |    04       |    02       |    04       |             |
+-------+-----------+-------------+-------------+-------------+-------------+
|       |  ICANON   |    02       |    0x100    |    02       |    0x100    | (different value)
| lflag +-----------+-------------+-------------+-------------+-------------+
|       |  ECHO     |    010      |    0x8      |    010      |    0x8      |
+-------+-----------+-------------+-------------+-------------+-------------+
+/


version(linux){
  immutable int IMAXBEL = 0x2000;
  immutable int IUTF8   = 0x4000;
}
version(OSX){
  immutable int IXANY   = 0x800;
  immutable int IMAXBEL = 0x2000;
  immutable int IUTF8   = 0x4000;
  immutable int ONLCR   = 0x2;
}


void InitTermios(int pty)
{
  termios tios;
  tcgetattr(pty, &tios);
  tios.c_iflag &= (~(IMAXBEL | IXANY | BRKINT));
  tcsetattr(pty, TCSADRAIN, &tios);
}

bool ReadyToFeed(int pty, bool remote)
{
  // Check whether a command-line application is running inside the terminal;
  // At present only c_iflag and c_oflag are checked.
  return remote ? ReadyToFeedRemote(pty) : ReadyToFeedLocal(pty);
}

private bool ReadyToFeedRemote(int pty)
{
  termios tios;
  tcgetattr(pty, &tios);
  return (tios.c_iflag & (IUTF8 | IGNPAR)) &&
         (tios.c_oflag == ONLCR);

}
private bool ReadyToFeedLocal(int pty)
{
  termios tios;
  tcgetattr(pty, &tios);
  return
    (tios.c_iflag & (IUTF8 | IXON                ) || // bash
     tios.c_iflag & (IUTF8 | IXON | ICRNL | INLCR) )  // zsh
     &&
    (tios.c_oflag == (ONLCR | OPOST));
}

bool AskingPassword(int pty)
{
  termios tios;
  tcgetattr(pty, &tios);

  // ECHO flag is off and ICANON flag is on
  return (tios.c_lflag & ECHO  ) == 0 &&
         (tios.c_lflag & ICANON) != 0;
}
