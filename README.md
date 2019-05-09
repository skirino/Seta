# DESCRIPTION

Seta is a GTK+ application which aims to be a replacement for terminal emulator.
Seta is written in D language (http://www.digitalmars.com/d/) using the GtkD library (http://dsource.org/projects/gtkd/).
Seta is licensed under the FSF General Public License version 3.

# PREREQUISITE LIBS TO RUN THIS SOFTWARE

1. libgtk+-3.0
2. libvte3 : usually come with Gnome libraries

# COMPILE & INSTALL

To compile this software (and required D libraries) it is highly recommended that you use dsss.
With dsss, to build the software just type
$ dsss build
in the Seta's root or "src" directory.

Without dsss, edit $(INCLUDE), $(LIBPATH) and name of the libraries
(listed above) in src/Makefile and type
$ make
in "src" directory.

To install this software,
$ sudo make install
in "src" directory.
