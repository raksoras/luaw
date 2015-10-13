# Makefile for building Luaw
# == CHANGE THE SETTINGS BELOW TO SUIT YOUR ENVIRONMENT =======================

CC?= gcc
CFLAGS?= -O2 -g -Wall
CFLAGS+= $(SYSCFLAGS) $(MYCFLAGS) -I../$(UVDIR)/include -I../$(LUADIR)/src -I/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.11.sdk/usr/include 
LDFLAGS= $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= ../$(UVLIB) -lpthread ../$(LUALIB) -lm $(SYSLIBS) $(MYLIBS)

# == END OF USER SETTINGS -- NO NEED TO CHANGE ANYTHING BELOW THIS LINE =======

# Build artifacts
LUAW_OBJS= http_parser.o lua_lpack.o luaw_common.o luaw_logging.o luaw_buffer.o luaw_http_parser.o luaw_server.o luaw_tcp.o luaw_timer.o lfs.o
LUAW_BIN= luaw
LUAW_START_SCRIPT= start_luaw.sh
LUAW_SCRIPTS= luapack.lua luaw_logging.lua luaw_data_structs_lib.lua luaw_utils.lua \
luaw_scheduler.lua luaw_webapp.lua luaw_timer.lua luaw_tcp.lua luaw_http.lua luaw_constants.lua

# How to install. If your install program does not support "-p", then
# you may have to run ranlib on the installed liblua.a.
INSTALL= install
INSTALL_EXEC= $(INSTALL) -p -m 0755
INSTALL_DATA= $(INSTALL) -p -m 0644

#
# If you don't have "install" you can use "cp" instead.
# INSTALL= cp -p
# INSTALL_EXEC= $(INSTALL)
# INSTALL_DATA= $(INSTALL)

# Other utilities.
MKDIR= mkdir -p
RM= rm -f
RMDIR= rm -rf

#where to install
INSTALL_BIN=$(INSTALL_ROOT)/bin
INSTALL_LIB=$(INSTALL_ROOT)/lib
INSTALL_LOGS=$(INSTALL_ROOT)/logs
INSTALL_WEBAPP=$(INSTALL_ROOT)/webapps

# Targets start here.

all: $(LUAW_BIN)

$(LUAW_BIN): $(LUAW_OBJS)
	$(CC) -o $@ $(LDFLAGS) $(LUAW_OBJS) $(LIBS)

install: check_install_root
	$(MKDIR) $(INSTALL_BIN)
	$(MKDIR) $(INSTALL_LIB)
	$(MKDIR) $(INSTALL_LOGS)
	$(MKDIR) $(INSTALL_WEBAPP)
	$(INSTALL_EXEC) $(LUAW_BIN) $(INSTALL_BIN)
	cd ../lib && $(INSTALL_DATA) $(LUAW_SCRIPTS) $(INSTALL_BIN)
	$(INSTALL_EXEC) ../sample/$(LUAW_START_SCRIPT) $(INSTALL_ROOT)

install-sample: install
	cd ../sample && cp -r * $(INSTALL_ROOT)

uninstall: check_install_root
	$(RMDIR) $(INSTALL_ROOT)/*

check_install_root:
ifndef INSTALL_ROOT
	$(error INSTALL_ROOT is undefined)
endif

clean:
	$(RM) $(LUAW_BIN) $(LUAW_OBJS)

echo:
	@echo "CC= $(CC)"
	@echo "CFLAGS= $(CFLAGS)"
	@echo "LDFLAGS= $(SYSLDFLAGS)"
	@echo "LIBS= $(LIBS)"
	@echo "RM= $(RM)"

# list targets that do not create files (but not all makes understand .PHONY)
.PHONY: default install install-sample uninstall check_install_root clean echo

# Luaw object files
http_parser.o: http_parser.c http_parser.h
lua_lpack.o: lua_lpack.c lua_lpack.h luaw_common.h
luaw_logging.o: luaw_logging.c luaw_logging.h luaw_common.h
luaw_common.o: luaw_common.c luaw_common.h luaw_tcp.h luaw_http_parser.h luaw_timer.h lua_lpack.h
luaw_buffer.o: luaw_buffer.c luaw_buffer.h
luaw_http_parser.o: luaw_http_parser.c luaw_http_parser.h luaw_common.h luaw_tcp.h lfs.h
luaw_server.o: luaw_server.c luaw_common.h luaw_tcp.h luaw_logging.h
luaw_tcp.o: luaw_tcp.c luaw_tcp.h luaw_common.h http_parser.h luaw_http_parser.h luaw_tcp.h
luaw_timer.o: luaw_timer.c luaw_timer.h luaw_common.h
lfs.o: lfs.c lfs.h

