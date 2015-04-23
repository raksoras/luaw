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

# Targets start here.

all: check_plat $(UVLIB) $(LUALIB) luaw

check_plat:
ifndef PLAT
	$(error PLAT is not defined)
endif

$(UVLIB): $(UVDIR)/Makefile
	$(MAKE) -C $(UVDIR)

$(UVDIR)/Makefile: $(UVDIR)/configure
	cd $(UVDIR) && ./configure

$(UVDIR)/configure: $(UVDIR)/autogen.sh
	cd $(UVDIR) && sh autogen.sh

$(LUADIR)/src/libluajit.a:
	$(MAKE) -C $(LUADIR)

$(LUADIR)/src/liblua.a:
	$(MAKE) -C $(LUADIR) $(PLAT)

luaw:
	$(MAKE) -C src $(PLAT)

clean: $(UVDIR)/Makefile
	$(MAKE) -C $(LUADIR) clean
	$(MAKE) -C $(UVDIR) distclean
	$(MAKE) -C src clean

# list targets that do not create files (but not all makes understand .PHONY)
.PHONY: all check_plat $(UVLIB) $(LUALIB) luaw clean

