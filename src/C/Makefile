SYSTEM = $(shell uname -s)
ifeq ("$(SYSTEM)", "Darwin")
	CFLAGS = -m32
else
	CFLAGS =
endif

default: workaround.c
	gcc ${CFLAGS} -c `pkg-config --cflags gtk+-2.0` workaround.c

