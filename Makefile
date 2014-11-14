# Makefile for building Luaw

# == CHANGE THE SETTINGS BELOW TO SUIT YOUR ENVIRONMENT =======================

# Your platform. See PLATS for possible values.
PLAT= none

CC= gcc
CFLAGS= -O2 -g -Wall $(SYSCFLAGS) $(MYCFLAGS)
LDFLAGS= $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= -lm -luv -llua -lpthread $(SYSLIBS) $(MYLIBS)

RM= rm -f

SYSCFLAGS=
SYSLDFLAGS=
SYSLIBS=

MYCFLAGS=
MYLDFLAGS=
MYLIBS=
MYOBJS=

# == END OF USER SETTINGS -- NO NEED TO CHANGE ANYTHING BELOW THIS LINE =======

PLATS= aix ansi bsd freebsd generic linux macosx mingw posix solaris

CORE_O=	http_parser.o lua_lpack.o luaw_common.o luaw_http_parser.o luaw_server.o luaw_tcp.o luaw_timer.o lfs.o
LUAW_O= $(CORE_O) $(MYOBJS)

LUAW_T=	luaw_server


# Targets start here.
default: $(PLAT)

all:	$(LUAW_T)

o:	$(LUAW_O)

$(LUAW_T): $(LUAW_O)
	$(CC) -o $@ $(LDFLAGS) $(LUAW_O) $(LIBS)

clean:
	$(RM) $(LUAW_T) $(LUAW_O)

depend:
	@$(CC) $(CFLAGS) -MM l*.c

echo:
	@echo "PLAT= $(PLAT)"
	@echo "CC= $(CC)"
	@echo "CFLAGS= $(CFLAGS)"
	@echo "LDFLAGS= $(SYSLDFLAGS)"
	@echo "LIBS= $(LIBS)"
	@echo "RM= $(RM)"

# Convenience targets for popular platforms
ALL= all

none:
	@echo "Please do 'make PLATFORM' where PLATFORM is one of these:"
	@echo "   $(PLATS)"

aix:
	$(MAKE) $(ALL) CC="xlc" CFLAGS="-O2 -DLUA_USE_POSIX -DLUA_USE_DLOPEN" SYSLIBS="-ldl" SYSLDFLAGS="-brtl -bexpall"

ansi:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_ANSI"

bsd:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_POSIX -DLUA_USE_DLOPEN" SYSLIBS="-Wl,-E"

freebsd:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_LINUX" SYSLIBS="-Wl,-E"

generic: $(ALL)

linux:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_LINUX" SYSLIBS="-Wl,-E -ldl"

macosx:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_MACOSX" CC=cc

posix:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_POSIX"

solaris:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_POSIX -DLUA_USE_DLOPEN" SYSLIBS="-ldl"

# list targets that do not create files (but not all makes understand .PHONY)
.PHONY: all $(PLATS) default o a clean depend echo none

# DO NOT DELETE

http_parser.o: http_parser.c http_parser.h
lua_lpack.o: lua_lpack.c lua_lpack.h luaw_common.h
luaw_common.o: luaw_common.c luaw_common.h luaw_tcp.h luaw_http_parser.h luaw_timer.h lua_lpack.h lfs.h
luaw_http_parser.o: luaw_http_parser.c luaw_http_parser.h luaw_common.h luaw_tcp.h
luaw_server.o: luaw_server.c luaw_common.h luaw_tcp.h
luaw_tcp.o: luaw_tcp.c luaw_tcp.h luaw_common.h http_parser.h luaw_http_parser.h luaw_tcp.h
luaw_timer.o: luaw_timer.c luaw_timer.h luaw_common.h
lfs.o: lfs.c lfs.h
