# Makefile for building Luaw
# == CHANGE THE SETTINGS BELOW TO SUIT YOUR ENVIRONMENT =======================

export UVDIR= deps/libuv
export UVLIB= deps/libuv/.libs/libuv.a

ifeq ($(LUAVM),luajit)
    export LUADIR= deps/luajit-2.0
    export LUALIB= deps/luajit-2.0/src/libluajit.a
    export OSXLDFLAGS= "-Wl,-pagezero_size,10000 -Wl,-image_base,100000000"
else
    export LUADIR= deps/lua-PUC-Rio
    export LUALIB= deps/lua-PUC-Rio/src/liblua.a
    export OSXLDFLAGS=
endif

# == END OF USER SETTINGS -- NO NEED TO CHANGE ANYTHING BELOW THIS LINE =======

# Supported platforms
PLATS= aix ansi bsd freebsd generic linux macosx mingw posix solaris
ALL= all

# Targets start here.

all:
	@echo "Please do 'make PLATFORM' where PLATFORM is one of these:"
	@echo "   $(PLATS)"

$(UVLIB): $(UVDIR)/Makefile
	$(MAKE) -C $(UVDIR)

$(UVDIR)/Makefile: $(UVDIR)/configure
	cd $(UVDIR) && ./configure

$(UVDIR)/configure: $(UVDIR)/autogen.sh
	cd $(UVDIR) && sh autogen.sh

$(LUADIR)/src/libluajit.a:
	$(MAKE) -C $(LUADIR)

$(LUADIR)/src/liblua.a:
	$(MAKE) -C $(LUADIR) $(TARGET)

luaw:
	$(MAKE) -C src $(ALL) SYSLDFLAGS=$(SYSLDFLAGS) CC=$(CC)

# Convenience targets for popular platforms

aix: TARGET= aix
aix: $(UVLIB) $(LUALIB)
	$(MAKE) -C src $(ALL) CC="xlc" CFLAGS="-O2" SYSLIBS="-ldl" SYSLDFLAGS="-brtl -bexpall"

ansi: TARGET= ansi
ansi: $(UVLIB) $(LUALIB)
	$(MAKE) -C src $(ALL)

bsd: TARGET= bsd
bsd: $(UVLIB) $(LUALIB)
	$(MAKE) -C src $(ALL) SYSLIBS="-Wl,-E"

freebsd: TARGET= freebsd
freebsd: $(UVLIB) $(LUALIB)
	$(MAKE) -C src $(ALL) SYSLIBS="-Wl,-E"

linux: TARGET= linux
linux: SYSLIBS= -Wl,-E -ldl
linux: $(UVLIB) $(LUALIB)
	$(MAKE) -C src $(ALL) SYSLIBS="-lrt -Wl,-E -ldl"

macosx: TARGET= macosx
macosx: $(UVLIB) $(LUALIB)
	$(MAKE) -C src $(ALL) CC="cc" SYSLDFLAGS=$(OSXLDFLAGS)

posix: TARGET= posix
posix: $(UVLIB) $(LUALIB)
	$(MAKE) -C src $(ALL)

solaris: TARGET= solaris
solaris: $(UVLIB) $(LUALIB)
	$(MAKE) -C src $(ALL) SYSLIBS="-ldl"

#build objects management

install:
	$(MAKE) -C src install

install-sample:
	$(MAKE) -C src install-sample

uninstall:
	$(MAKE) -C src uninstall

clean: $(UVDIR)/Makefile
	$(MAKE) -C deps/luajit-2.0 clean
	$(MAKE) -C deps/lua-PUC-Rio clean
	$(MAKE) -C $(UVDIR) distclean
	$(MAKE) -C src clean

# list targets that do not create files (but not all makes understand .PHONY)
.PHONY: all check_plat $(LUALIB) $(PLATS) luaw install uninstall clean $(LUADIR)/src/libluajit.a $(LUADIR)/src/liblua.a

