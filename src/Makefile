SRC = anything_cd/*.d config/*.d fm/*.d term/*.d utils/*.d *.d
INPUTS = C/workaround.o ${SRC}

SYSTEM = $(shell uname -s)
ifeq ("$(SYSTEM)", "Darwin")
	DFLAGS = -m32 -w
	LINKOPTS = -L-lgtkd -L-lvte -L-L/opt/local/lib -L-lgtk-x11-2.0 -L-ldl
else # assuming Linux
	DFLAGS = -Iextern/libnotify/ -w
	LINKOPTS = -L-lgtkd-2 -L-lvte2_90 -L-ldl -L-lnotify -L-lgtk-3
endif

all: C/workaround.o
	dmd ${DFLAGS} -g -version=DEBUG -ofseta ${LINKOPTS} ${INPUTS}

release: C/workaround.o
	dmd ${DFLAGS} -O -ofseta ${LINKOPTS} ${INPUTS}

test: C/workaround.o
	dmd ${DFLAGS} -unittest -ofsetatest ${LINKOPTS} ${INPUTS}
	./setatest

C/workaround.o:
	make -C ./C

install:
	@install -m 755 ./seta /usr/bin
	@install -m 644 ../debian/usr/share/applications/seta.desktop /usr/share/applications/
	@install -m 644 ../debian/usr/share/pixmaps/seta/seta_show-hidden-files.svg /usr/share/pixmaps/
	@install -m 644 ../debian/usr/share/pixmaps/seta/gnome-session-switch.svg /usr/share/pixmaps/
