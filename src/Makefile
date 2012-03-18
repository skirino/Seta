
# name of the compiled lib includes "DG" or something like that,
# depending on the compiler used by the dsss.
# please modify the name of the libraries to fit to your system.
D_OR_G=DD

# this is the author's case, modify this line
DSSS_PATH=~/code/D/dsss

DCOMPILER=$(DSSS_PATH)/bin/dmd
#DCOMPILER=gdmd

# directory where .d or .di files reside
INCLUDE=$(DSSS_PATH)/include/d

# directory where Tango, Tangobos and GtkD libraries reside
LIBPATH=$(DSSS_PATH)/lib

OBJS = \
	bind.o\
	changeDirDialog.o\
	config.o\
	configDialog.o\
	constants.o\
	dirPathHistory.o\
	dirPathList.o\
	dirTree.o\
	entry.o\
	fileManager.o\
	fileSystem.o\
	fileView.o\
	filterDirPathThread.o\
	gioUtil.o\
	history.o\
	hostView.d\
	hosts.d\
	inputDialog.o\
	keybind.o\
	listupThread.o\
	main.o\
	mainWindow.o\
	mediator.o\
	note.o\
	page.o\
	pageList.o\
	popupMenu.o\
	rename.o\
	scripts.o\
	shellrc.o\
	sshConnection.o\
	sshDialog.o\
	statusbar.o\
	stringUtil.o\
	tab.o\
	templateUtil.o\
	terminal.o\
	terminalSearchDialog.o\
	threadList.o\
	timeUtil.o\
	toolbar.o\
	transferFiles.o\
	treeUtil.o\
	vector.o\
	volumeMonitor.o

COBJS = C/workaround.o

# dmd compiler, modify compiler outputs to enable 'next/previous-error' in *Compilation* buffer in Emacs
all:
	dmd -O -ofseta -L-lgtkd -L-lvte -L-ldl C/workaround.o anything_cd/*.d config/*.d fm/*.d term/*.d utils/*.d *.d
#	~/code/D/dsss/bin/dsss build | tr -d : | tr \(\) :
# gdc compiler
#	/home/skirino/code/D/dsss/bin/dsss build

seta:	$(OBJS) CWORKAROUND
	$(DCOMPILER) -of$@ -L--start-group -L-L$(LIBPATH) $(OBJS) $(COBJS) -L-l$(D_OR_G)-tango-core -L-l$(D_OR_G)-tango-util -L-l$(D_OR_G)-tango-text -L-l$(D_OR_G)-tango-sys -L-l$(D_OR_G)-tango-stdc -L-l$(D_OR_G)-tango-io -L-l$(D_OR_G)-tango-net -L-l$(D_OR_G)-tango-time -L-l$(D_OR_G)-tango-sys-linux -L-l$(D_OR_G)-gtk -L-l$(D_OR_G)-gio -L-l$(D_OR_G)-glib -L-l$(D_OR_G)-gdk -L-l$(D_OR_G)-gdkpixbuf -L-l$(D_OR_G)-gthread -L-l$(D_OR_G)-gobject -L-l$(D_OR_G)-atk -L-l$(D_OR_G)-gtkc -L-l$(D_OR_G)-pango -L-l$(D_OR_G)-cairo -L-ldl -L-lvte

CWORKAROUND:
	make -C ./C

.SUFFIXES: .d .o
.d.o: 
	$(DCOMPILER) -version=Posix -version=Tango -c -O -release -of$@ -I$(INCLUDE) $<

install:
	@install -m 755 ./seta /usr/bin
	@install -m 644 ../debian/usr/share/applications/seta.desktop /usr/share/applications/
	@install -m 644 ../debian/usr/share/pixmaps/seta/seta_show-hidden-files.svg /usr/share/pixmaps/
	@install -m 644 ../debian/usr/share/pixmaps/seta/gnome-session-switch.svg /usr/share/pixmaps/

.PHONY: clean
clean:
	rm -f $(OBJS) $(COBJS)

# for dmd compiler
check-syntax:
	$(DCOMPILER) -c -w -o- -version=Posix -version=Tango -c -O -release -I$(INCLUDE) $(CHK_SOURCES) | tr -d : | tr \(\) :
# for gdc compiler
#	$(DCOMPILER) -c -w -o- -version=Posix -version=Tango -c -O -release -I$(INCLUDE) $(CHK_SOURCES)


