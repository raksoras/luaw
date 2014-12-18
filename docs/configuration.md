#3. Configuring Luaw

Before we can write our first Luaw webapp we need to configure our Luaw server with some basic settings -- TCP port on which Luaw server will listen for incoming HTTP connections, for example. These settings are specified in a text file which is named server.cfg by convention and is put under `luaw_root_dir/conf` directory. This file is Luaw's counterpart of Apache web server's httpd.conf or Tomcat's server.xml file. All Luaw configuration files use [Lua object notation syntax](http://www.lua.org/pil/10.1.html#DataDesc) and server.cfg is no exception to this rule.

Like Tomcat, Luaw allows deploying multiple web apps in a single Luaw server. Settings configured in server.cfg apply to the whole server, that is, they apply to all webapps that are deployed in that server. Settings specific to each webapps are configured using "web.lua" file per webapp.

`make INSTALL_ROOT=luaw_root_dir install` step from the last chapter should have created the standard directory structure for you and put sample server.cfg file under `luaw_root_dir/conf` directory. You can use this server.cfg as a starting point for defining your configuration. Open your conf/server.cfg and take a look.

##Server configuration

Here is a sample server.cfg

```lua
luaw_server_config = {
    server_ip = "0.0.0.0",
    server_port = 7001,
    connect_timeout = 4000,
    read_timeout = 8000,
    write_timeout = 8000
}

luaw_log_config = {
    log_dir = "/apps/luaw/sample/log",
    log_file_basename = "luaw-log",
    log_file_size_limit = 1024*1024,
    log_file_count_limit = 9,
    log_filename_timestamp_format = '%Y%m%d',
    log_lines_buffer_count = 16,
    syslog_server = "127.0.0.1",
    syslog_port = 514,
}

luaw_webapp_config = {
    base_dir = "/apps/luaw/sample/webapps"
}
```
luaw_server_config section specifies listening port and read/connection timeout defaults for TCP socket connections. "server_ip" setting's value "0.0.0.0" tells server to accept connections coming in on any of the host's ip addresses. Some hosts have  more than one IP address assigned to them. In such case "server_ip"  can be used to restrict Luaw server to accept incoming connections on only one of the multiple IP addresses of the host.

luaw_log_config section sets up parameters for Luaw's log4j like logging subsystem - log file name pattern, size limit for a single log file after which Luaw should open new log file, how many of such past log files to keep around (log rotation) etc. Luaw logging framework can send messages to syslog daemon as well and this section can be used to specify target syslog server's ip address and port.

Finally, luaw_webapp_config section specifies location of directory that houses all the webapps that this Luaw server will load and run. By convention this directory is named "webapps" and is placed directly under Luaw server's root folder but you can place it anywhere you like using this section, should your build/deploy procedure requires you to choose another location.

## webapp configuration

Like Tomcat, Luaw allows deploying multiple webapps in a single Luaw server. These webapps are deployed under `luaw_root_dir/webapps`. Here is a sample layout for a Luaw server that has two webapps - `myapp1` and `myapp2` - deployed in it:

```
luaw_root_dir
 |
 +--- bin
 |
 +--- conf
 |     |
 │     +--- server.cfg
 |
 +--- lib
 |
 +--- logs
 |
 +--- webapps
       |
       +--- myapp1
       |     |
       |     +---web.lua
       |
       +--- myapp2
             |
             +---web.lua
```

Each webapp contains file named web.lua that specifies settings specific to that particular webapp. The same directory (`/myapp1` and `/myapp2` in the example above) also contains Lua code for the webapp - REST handlers, views etc. We will visit application code in the next chapter. In this chapter we will focus on just the configuration piece.

##Sample web.lua:

```lua
luaw_webapp = {
    resourcePattern = "handler%-.*%.lua",
	views = {
		"user/address-view.lua",
		"account/account-view.lua"
	}
}

Luaw.logging.file {
    name = "root",
    level = Luaw.logging.ERROR,
}

Luaw.logging.file {
    name = "com.luaw",
    level = Luaw.logging.INFO,
}

Luaw.logging.syslog {
    name = "com.luaw",
    level = Luaw.logging.WARNING,
}
```

luaw_webapp section specifies resources (request handlers) and views (templates) that make up the web application. These can be specified in two different ways:

1. **Using pattern **: You can use configuration elements *resourcePattern* and *viewPattern* to specify name pattern for request handlers and views. Luaw will traverse all directories under current webapp recursively to load all files that match these patterns. The patterns are specified using standard [Lua regular expressions](http://www.lua.org/pil/20.2.html). These are somewhat different than usual POSIX or PERL regular expressions so be sure to read the documentation linked above before you use them.
2. **Listing them one by one by exact name and path **: You can also use configuration elements *resources* and *views* to list exact resources and views by name to load them. Each entry should contain a path that is relative to the root webapp directory (**myapp1** and **myapp2** in the example above) ending in the filename of the file to load.

You can mix and match both these approach. For example you can use *resourcePattern* to specify resources and *views* for specifying exact list of views. You can even use both the ways together. That is, you can use both *resourcePattern* and *resources* in the same section and Luaw will load all the files under the given webapp's folder that either match the *resourcePattern* or match the path and file name from the *resources* list (union operation). This could be useful if most of your resource files follow certain naming convention or a pattern but you also have few one off files that don't follow those conventions that you'd like to load nonetheless.

Rest of the file specifies logging level and logging target (file vs syslog) for different Luaw packages. Logging settings in web.lua specify log levels that are specific to that webapp while overall logging settings like log file name and size limit are determined by server.cfg settings at a global server level.
