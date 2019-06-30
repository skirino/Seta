# Seta

Seta is a GTK+ terminal emulator written in [D language](http://www.digitalmars.com/d/) using [GtkD library](https://gtkd.org/).
It depends on `libgtk+-3.0` and `libvte3` (which usually come with recent gnome packages).

- To build:
    - `$ gcc -c source/utils/darwin_readcwd.c`
    - `$ dub build`
- bugs in macOS
    - To address these issues I currently use a [fork of libvte](https://github.com/skirino/vte).
      To run seta with the modified vte library:
      `$ LD_LIBRARY_PATH=/Users/skirino/code/C/vte/_build/src ./seta`
