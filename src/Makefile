SRC = anything_cd/*.d config/*.d fm/*.d gtk/*.d term/*.d utils/*.d *.d

all: C/workaround.o
	dmd -O -ofseta -L-lgtkd -L-lvte -L-ldl C/workaround.o ${SRC}

debug: C/workaround.o
	dmd -g -version=DEBUG -ofseta -L-lgtkd -L-lvte -L-ldl C/workaround.o ${SRC}

C/workaround.o:
	make -C ./C

install:
	@install -m 755 ./seta /usr/bin
	@install -m 644 ../debian/usr/share/applications/seta.desktop /usr/share/applications/
	@install -m 644 ../debian/usr/share/pixmaps/seta/seta_show-hidden-files.svg /usr/share/pixmaps/
	@install -m 644 ../debian/usr/share/pixmaps/seta/gnome-session-switch.svg /usr/share/pixmaps/

.PHONY: clean
clean:
	rm -f $(OBJS) $(COBJS)
