--[[
Copyright (c) 2015 raksoras

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local ds_lib = require('luaw_data_structs_lib')
local luaw_utils_lib = require("luaw_utils")
local luapack_lib = require('luapack')

local log_module = {}

local PATH_SEPARATOR = string.match (package.config, "[^\n]+")

-- Log file states
local LOG_NOT_OPEN = 0
local OPENING_LOG = 1
local LOG_IS_OPEN = 2

-- Log levels
local EMERGENCY = 0
local ALERT = 1
local CRITICAL = 2
local ERROR = 3
local WARNING = 4
local NOTICE = 5
local INFO = 6
local DEBUG = 7

log_module.EMERGENCY = EMERGENCY
log_module.ALERT = ALERT
log_module.CRITICAL = CRITICAL
log_module.ERROR = ERROR
log_module.WARNING = WARNING
log_module.NOTICE = NOTICE
log_module.INFO = INFO
log_module.DEBUG = DEBUG

-- Log appender types
local FILE_LOG = "FILE"
local SYS_LOG = "SYSLOG"

log_module.SYSLOG_FACILITY_USER = 1
log_module.SYSLOG_FACILITY_AUTH = 10
log_module.SYSLOG_FACILITY_AUDIT = 13
log_module.SYSLOG_FACILITY_ALERT = 14
log_module.SYSLOG_FACILITY_LOCAL0 = 16
log_module.SYSLOG_FACILITY_LOCAL1 = 17
log_module.SYSLOG_FACILITY_LOCAL2 = 18
log_module.SYSLOG_FACILITY_LOCAL3 = 19
log_module.SYSLOG_FACILITY_LOCAL4 = 20
log_module.SYSLOG_FACILITY_LOCAL5 = 21
log_module.SYSLOG_FACILITY_LOCAL6 = 22
log_module.SYSLOG_FACILITY_LOCAL7 = 23

local logRoot = { }

local logDir = assert(luaw_log_config.log_dir, "Invalid log directory specified")
local noOfLogLinesToBuffer = luaw_log_config.log_lines_buffer_count or 100
local logfileBaseName = luaw_log_config.log_file_basename or "luaw-log"
local logfileSizeLimit = luaw_log_config.log_file_size_limit or (1024 * 1024 * 10) -- 10MB
local logfileCountLimit = luaw_log_config.log_file_count_limit or 99
local logLineTimeFormat = luaw_log_config.log_line_timestamp_format or "%x %X"
local logFileNameTimeFormat = luaw_log_config.log_filename_timestamp_format or '%Y%m%d-%H%M%S'

local syslogTag = luaw_log_config.syslog_tag or 'luaw'
local syslogPresent = luaw_logging_lib.syslogConnect(luaw_log_config.syslog_server, luaw_log_config.syslog_port)
logRoot.facility = luaw_log_config.syslog_facility or log_module.SYSLOG_FACILITY_LOCAL7
local hostname = luaw_logging_lib.hostname()


local logSequenceNum = 0
local logSize = 0
local logBuffer = ds_lib.newOverwrittingRingBuffer(noOfLogLinesToBuffer + 32)
local noOfLogLinesDropped = 0

local currentTimeStr
local syslogTimeStr

log_module.updateCurrentTime = function(currentTime)
    currentTimeStr = os.date(logLineTimeFormat, currentTime)
    if syslogPresent then
        syslogTimeStr = os.date("%b %d %X", currentTime)
    end
end

local function nextLogSequenceNum()
    if logSequenceNum > logfileCountLimit then logSequenceNum = 0 end
    logSequenceNum = logSequenceNum + 1
    return logSequenceNum
end

local function concatLogLines()
    local temp = luapack_lib.createDict(logBuffer.filled+1, 0)
    local i = 1
    local logLine = logBuffer:take()
    while logLine do
        temp[i] = logLine
        i = i+1
        logLine = logBuffer:take()
    end
    temp[i] = '' -- for the last newline
    return table.concat(temp, '\n')
end

local function logToFile(logLine)
    local added = logBuffer:offer(currentTimeStr..' '..logLine)
    if not added then noOfLogLinesDropped = noOfLogLinesDropped +1 end

    local state = luaw_logging_lib.logState()

    if ((state == LOG_IS_OPEN)and(logBuffer.filled >= noOfLogLinesToBuffer)) then
        local logBatch = concatLogLines()
        logSize = logSize + string.len(logBatch)
        local rotateLog = (logSize >= logfileSizeLimit)
        state = luaw_logging_lib.writeLog(logBatch, rotateLog)
    end

    if (state == LOG_NOT_OPEN) then
        logSize = 0
        local ts = os.date(logFileNameTimeFormat, os.time())
        local fileName = logDir..PATH_SEPARATOR..logfileBaseName..'-'..ts..'-'..nextLogSequenceNum()..'.log'
        luaw_logging_lib.openLog(fileName)
    end
end

local function syslog(priority, facility, mesg)
    local pri = priority + (facility * 8)
    local logLine = string.format("<%d>%s %s %s: %s", pri, syslogTimeStr, hostname, syslogTag, mesg)
    luaw_logging_lib.syslogSend(logLine);
end

local nameIterator = luaw_utils_lib.splitter('.')
local function splitName(name)
    if not name then return luaw_utils_lib.nilFn end
    return nameIterator, name, 0
end

local function logInternal(logLevel, fileLevel, syslogLevel, syslogFacility, mesg)
    if (logLevel <= fileLevel) then
        logToFile(mesg)
    end
    if ((syslogPresent)and(logLevel <= syslogLevel)) then
        syslog(logLevel, syslogFacility, mesg)
    end
end

local function log(logger, logLevel, mesg)
    local fileLevel = logger[FILE_LOG] or ERROR
    local syslogLevel = logger[SYS_LOG] or ERROR
    logInternal(logLevel, fileLevel, syslogLevel, logger.facility, mesg)
end

local function logf(logger, logLevel, mesgFormat, ...)
    local fileLevel = logger[FILE_LOG] or ERROR
    local syslogLevel = logger[SYS_LOG] or ERROR
    if ((logLevel <= fileLevel)or(logLevel <= syslogLevel)) then
        local mesg = string.format(mesgFormat, ...)
        logInternal(logLevel, fileLevel, syslogLevel, logger.facility, mesg)
    end
end

logRoot.log = log

logRoot.logf = logf

logRoot.emergency = function(logger, mesg)
    log(logger, EMERGENCY, mesg)
end

logRoot.alert = function(logger, mesg)
    log(logger, ALERT, mesg)
end

logRoot.critical = function(logger, mesg)
    log(logger, CRITICAL, mesg)
end

logRoot.error = function(logger, mesg)
    log(logger, ERROR, mesg)
end

logRoot.warning = function(logger, mesg)
    log(logger, WARNING, mesg)
end

logRoot.notice = function(logger, mesg)
    log(logger, NOTICE, mesg)
end

logRoot.info = function(logger, mesg)
    log(logger, INFO, mesg)
end

logRoot.debug = function(logger, mesg)
    log(logger, DEBUG, mesg)
end

logRoot.emergencyf = function(logger, mesgFormat, ...)
    logf(logger, EMERGENCY, mesgFormat, ...)
end

logRoot.alertf = function(logger, mesgFormat, ...)
    logf(logger, ALERT, mesgFormat, ...)
end

logRoot.criticalf = function(logger, mesgFormat, ...)
    logf(logger, CRITICAL, mesgFormat, ...)
end

logRoot.errorf = function(logger, mesgFormat, ...)
    logf(logger, ERROR, mesgFormat, ...)
end

logRoot.warningf = function(logger, mesgFormat, ...)
    logf(logger, WARNING, mesgFormat, ...)
end

logRoot.noticef = function(logger, mesgFormat, ...)
    logf(logger, NOTICE, mesgFormat, ...)
end

logRoot.infof = function(logger, mesgFormat, ...)
    logf(logger, INFO, mesgFormat, ...)
end

logRoot.debugf = function(logger, mesgFormat, ...)
    logf(logger, DEBUG, mesgFormat, ...)
end

local function getLogger(name)
    local logger = logRoot
    if (name == 'root') then return logger end

    for idx, namePart in splitName(name) do
        local child = logger[namePart]
        if not child then
            child = {}
            setmetatable(child, {__index = logger})
            logger[namePart] = child
        end
        logger = child
    end
    return logger
end

log_module.getLogger = getLogger

local function configureLogger(logCfg, logType)
    local loggerName = assert(logCfg.name, "Logger name missing")
    local logLevel = assert(logCfg.level, "Logger level missing")
    local logger = assert(getLogger(loggerName), "Could not find logger "..loggerName)
    logger[logType] = logLevel
    return logger
end

log_module.file = function(logCfg)
    configureLogger(logCfg, FILE_LOG)
end

log_module.syslog = function(logCfg)
    local logger = configureLogger(logCfg, SYS_LOG)
    logger.facility = logCfg.facility
end

return log_module