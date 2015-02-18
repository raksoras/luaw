#2. Getting started

Let's build Luaw from its sources. Luaw depends on,

1. Lua 5.2(+)
2. libuv (v1.0.0 )

We will first build these dependencies from their sources and then finally build Luaw itself. To build these artifacts you would need [Git](http://git-scm.com/),  [Make](http://www.gnu.org/software/make/) and [autotools](http://www.gnu.org/software/automake/manual/html_node/Autotools-Introduction.html) setup on your machine.

##Building Lua 5.2
Lua sources can be downloaded from [here](http://www.lua.org/download.html). Here are the steps to download Lua 5.2 sources and build it for Linux:

    curl -R -O http://www.lua.org/ftp/lua-5.2.3.tar.gz
    tar zxf lua-5.2.3.tar.gz
    cd lua-5.2.3
    make linux test
    sudo make linux install

To build for other OSes replace "linux" from the last two make commands with the OS you are building for. For example for when building for Mac OS run,

    make macosx test
    sudo make linux install

To see what OSes are supported run ./lua-5.2.3/src/Makefile targets


##Building libuv
Luaw uses node.js library libuv to do asynchronous, event based IO in a portable, cross platform  manner. To build libuv:

1. first clone libuv repository
        git clone https://github.com/joyent/libuv.git
2. Checkout latest stable release of libuv from the cloned local repository. As of this writing the latest stable release is v1.0.0 and Luaw is verified to compile and run successfully with this release of libuv.
        cd libuv
        git checkout tags/v1.0.0
3. Build libuv. This may require you to install autotools. Detailed instructions are [here](https://github.com/joyent/libuv#build-instructions)
        sh autogen.sh
        ./configure
        make
        make check
        sudo make install

## Building Luaw
With all dependencies built, now we are ready to build Luaw itself.

1. Clone Luaw repository
        git clone https://github.com/raksoras/luaw.git
2. Build Luaw
        cd luaw/src
        make linux
3. Install Luaw binary - luaw_server - in directory of your choice
		make INSTALL_ROOT=<luaw_root_dir> install
4. Note: On Mac running Yosemite version of Mac OS you may have to run,
		make SYSCFLAGS=-I/usr/local/include SYSLDFLAGS=-L/usr/local/lib macosx
        make INSTALL_ROOT=<luaw_root_dir> install


##Luaw directory structure

In the tree diagram below `luaw_root_dir` is a directory that you chose in the `make intsall` step above. It will act as a root for Luaw server's directory structure. The `make install` step will create following directory structure under `luaw_root_dir`

```
luaw_root_dir
 |
 |
 +--- bin              Directory that holds Luaw server binary we built
 |                     along with all necessary Lua libraries
 |
 +--- conf             Directory for server configuration
 |   |
 │   +--- server.cfg   Sample server configuration file, to be used as a starting point
 |
 +--- lib              Directory to install any third party or user supplied Lua
 |                     libraries that application may depend on.
 |
 +--- logs             Directory for server logs
 |
 +--- webapps          Directory to install Luaw webapps
```

This directory structure and its usage is further explained in the next chapter "Configuring Luaw"

