SYSTEM = $(shell uname -s)
ifeq ("$(SYSTEM)", "Darwin")
	CFLAGS = -m32
else
	CFLAGS =
endif

default: workaround.c
	gcc ${CFLAGS} -fPIC -c `pkg-config --cflags gtk+-3.0` workaround.c

