SRC = config/*.d utils/*.d *.d

SYSTEM = $(shell uname -s)
ifeq ("$(SYSTEM)", "Darwin")
	DFLAGS = -m32 -w
	LINKOPTS = -L-lgtkd -L-lvte -L-L/opt/local/lib -L-lgtk-x11-2.0 -L-ldl
else # assuming Linux
	DFLAGS = -wi
	LINKOPTS = -L-L/opt/dmd/current/lib -L-lvted-3 -L-lgtkd-3 -L-lvte-2.91 -L-ldl -L-lgtk-3
endif

all:
	dmd ${DFLAGS} -g -version=DEBUG -ofseta ${LINKOPTS} ${SRC}

release:
	dmd ${DFLAGS} -O -ofseta ${LINKOPTS} ${SRC}

test:
	dmd ${DFLAGS} -unittest -ofsetatest ${LINKOPTS} ${SRC}
	./setatest

install:
	@install -m 755 ./seta /usr/bin
	@install -m 644 ../debian/usr/share/applications/seta.desktop /usr/share/applications/
	@install -m 644 ../debian/usr/share/pixmaps/seta/seta_show-hidden-files.svg /usr/share/pixmaps/
	@install -m 644 ../debian/usr/share/pixmaps/seta/gnome-session-switch.svg /usr/share/pixmaps/
