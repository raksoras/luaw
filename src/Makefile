# Makefile for building Luaw

# == CHANGE THE SETTINGS BELOW TO SUIT YOUR ENVIRONMENT =======================

# Your platform. See PLATS for possible values.
PLAT= none

CC= gcc
CFLAGS= -O2 -g -Wall $(SYSCFLAGS) $(MYCFLAGS)
LDFLAGS= $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= -lm -luv -llua -lpthread $(SYSLIBS) $(MYLIBS)

SYSCFLAGS=
SYSLDFLAGS=
SYSLIBS=

MYCFLAGS=
MYLDFLAGS=
MYLIBS=
MYOBJS=

# How to install. If your install program does not support "-p", then
# you may have to run ranlib on the installed liblua.a.
INSTALL= install -p
INSTALL_EXEC= $(INSTALL) -m 0755
INSTALL_DATA= $(INSTALL) -m 0644
#
# If you don't have "install" you can use "cp" instead.
# INSTALL= cp -p
# INSTALL_EXEC= $(INSTALL)
# INSTALL_DATA= $(INSTALL)

# Other utilities.
MKDIR= mkdir -p
RM= rm -rf

# == END OF USER SETTINGS -- NO NEED TO CHANGE ANYTHING BELOW THIS LINE =======



PLATS= aix ansi bsd freebsd generic linux macosx mingw posix solaris

#What to install
LUAW_BIN=luaw_server

LUAW_SCRIPTS=luapack.lua luaw_init.lua luaw_logging.lua luaw_template_lang.lua \
luaw_data_structs_lib.lua luaw_lib.lua luaw_scheduler.lua luaw_template_compiler.lua \
luaw_webapp.lua

LUAW_CONF=server.cfg

#where to install
INSTALL_BIN=$(INSTALL_ROOT)/bin
INSTALL_LIB=$(INSTALL_ROOT)/lib
INSTALL_CONF=$(INSTALL_ROOT)/conf
INSTALL_LOGS=$(INSTALL_ROOT)/logs
INSTALL_WEBAPP=$(INSTALL_ROOT)/webapp

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

install: check_install_root
	$(MKDIR) $(INSTALL_BIN)
	$(MKDIR) $(INSTALL_LIB)
	$(MKDIR) $(INSTALL_CONF)
	$(MKDIR) $(INSTALL_LOGS)
	$(MKDIR) $(INSTALL_WEBAPP)
	$(INSTALL_EXEC) $(LUAW_BIN) $(INSTALL_BIN)
	cd ../lib && $(INSTALL_DATA) $(LUAW_SCRIPTS) $(INSTALL_BIN)
	cd ../conf && $(INSTALL_DATA) $(LUAW_CONF) $(INSTALL_CONF)

uninstall: check_install_root
	$(RM) $(INSTALL_BIN)
	$(RM) $(INSTALL_LIB)
	$(RM) $(INSTALL_CONF)
	$(RM) $(INSTALL_LOGS)
	$(RM) $(INSTALL_WEBAPP)

check_install_root:
ifndef INSTALL_ROOT
	$(error INSTALL_ROOT is undefined)
endif

# Convenience targets for popular platforms
ALL= all

none:
	@echo "Please do 'make PLATFORM' where PLATFORM is one of these:"
	@echo "   $(PLATS)"

aix:
	$(MAKE) $(ALL) CC="xlc" CFLAGS="-O2" SYSLIBS="-ldl" SYSLDFLAGS="-brtl -bexpall"

ansi:
	$(MAKE) $(ALL)

bsd:
	$(MAKE) $(ALL) SYSLIBS="-Wl,-E"

freebsd:
	$(MAKE) $(ALL) SYSLIBS="-Wl,-E"

generic: $(ALL)

linux:
	$(MAKE) $(ALL) SYSLIBS="-Wl,-E -ldl"

macosx:
	$(MAKE) $(ALL) CC=cc

posix:
	$(MAKE) $(ALL)

solaris:
	$(MAKE) $(ALL) SYSLIBS="-ldl"

# list targets that do not create files (but not all makes understand .PHONY)
.PHONY: all $(PLATS) default o a clean depend echo none

# DO NOT DELETE

http_parser.o: http_parser.c http_parser.h
lua_lpack.o: lua_lpack.c lua_lpack.h luaw_common.h
luaw_common.o: luaw_common.c luaw_common.h luaw_tcp.h luaw_http_parser.h luaw_timer.h lua_lpack.h
luaw_http_parser.o: luaw_http_parser.c luaw_http_parser.h luaw_common.h luaw_tcp.h lfs.h
luaw_server.o: luaw_server.c luaw_common.h luaw_tcp.h
luaw_tcp.o: luaw_tcp.c luaw_tcp.h luaw_common.h http_parser.h luaw_http_parser.h luaw_tcp.h
luaw_timer.o: luaw_timer.c luaw_timer.h luaw_common.h
lfs.o: lfs.c lfs.h
