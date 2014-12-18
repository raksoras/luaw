#8. Luaw logging framework

Luaw comes equipped with logging framework that's modeled after Java's popular log4j logging framework. Like log4j, it allows different destinations for logs (either file system or syslog) and different log levels per package to allow enabling/disabling logging by setting
runtime properties

Luaw's logging is configured at two levels

##Logging configuration for the whole server
Configuration related to log destinations is configured in `conf/server.cfg` and applies to all web applications deployed in that server. luaw_log_config section contains this configuration in server.cfg
```lua
luaw_log_config = {
	log_dir = "/apps/luaw/sample/log",
	log_file_basename = "luaw-log",
	log_filename_timestamp_format = '%Y%m%d',
	log_file_size_limit = 1024*1024,
	log_file_count_limit = 9,
    log_lines_buffer_count = 16,
	syslog_server = "127.0.0.1",
	syslog_port = 514
}
```

Example above configures,

1. Log directory where the files should go: /apps/luaw/sample/log
2. Log file base name: luaw-log
3. [Timestamp format](http://www.lua.org/pil/22.1.html) used along with log file base name to generate full log file name for versioned log files: %Y%m%d
4. File size limit for an individual log file: 1MB
5. Total number of log files to keep: 9
6. How many log lines to buffer in memory before flushing them to log file: 16
7. syslog server address: 127.0.0.1
8. syslog server port: 514

You could omit either file system related configuration or syslog configuration but at least one must be present to use Luaw logging.


##Logging configuration per webapp

Configuration related to individual webapps' logging is configured in `web.lua` config file of each webapp. Here are some example entries from sample "web.lua":
```lua
Luaw.logging.file {
    name = "root",
    level = Luaw.logging.ERROR
}
```

Above entry configures root level logging ("root" is a special word) for the entire webapp that applies to all loggers used by the webapp by default unless overridden by more specific logger. It configures all logging to go to log file - whose destination and name is configured in server.cfg - and states only logs with log level ERROR and above should be logged.

```lua
Luaw.logging.file {
    name = "com.myapp",
    level = Luaw.logging.INFO
}
```

Overrides default ("root") logging for the logger "com.myapp" and sets its level to INFO which means for any logger with name starting with "com.myapp", log lines with the log level INFO and above will get logged to the file instead of just ERROR as dictated by the default (root) configuration above. "com.myapp" is a logger name. You can use any name separated by periods. Each part of the name delimited by a period forms logger hierarchy just like log4j. For example, the logger named "com" is a parent to logger name "com.myapp" and any logging configuration defined for "com" is inherited by "com.myapp" unless specififcally overriden on "com.myapp". This makes it easy to fine tune logging levels of different parts of code using loggers arranged in a logical hierarchy.

To actually log a line you use code like following:

```lua
local log = require("luaw_logging")

local logger = log.getLogger("com.myapp")
logger.error("some error occurred")
logger.warning("this is a warning")
logger.info("some information")
logger.debug("lowest level debug")
```

Here are different log levels and Luaw logger functions corresponding to them in a decreasing order of severity:

|Log Level  | Logging function   |
|--------------------------------
| EMERGENCY | logger.emergency() |
| ALERT     | logger.alert()     |
| CRITICAL  | logger.critical()  |
| ERROR     | logger.error()     |
| WARNING   | logger.warning()   |
| NOTICE    | logger.notice()    |
| INFO      | logger.info()      |
| DEBUG     | logger.debug()     |


All these functions also have a counterpart ending in "f" - `logger.errorf()`, `logger.warningf()`, `logger.debugf()` etc. - that take a [lua format string](http://lua-users.org/wiki/StringLibraryTutorial) followed by variable number of arguments that are used to substitute place holderes in the format string like below

```lua
logger.infof("User name %s, User Id %d", name, id)
```

This form is useful to avoid unnecessary string concatenation beforehand when the configured logger level may actually end up filtering the log line anyways.

Finally, here is an example of configuring syslog as a log destination for logger "com.myapp.system" and setting it to the log level WARNING in web.lua:

```lua
Luaw.logging.syslog {
    name = "com.myapp.system",
    level = Luaw.logging.WARNING
}
```

syslog sever and port to use is specified in server.cfg