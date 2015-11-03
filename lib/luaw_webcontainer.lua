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

local luaw_utils_lib = require("luaw_utils")
local luaw_logging = require("luaw_logging")
local luaw_tcp_lib = require('luaw_tcp')
local luaw_timer = require("luaw_timer")
local luaw_http_lib = require("luaw_http")
local scheduler = require('luaw_scheduler')
local luaw_lpack = require("luapack")

local HTTP_METHODS = {
    GET = "GET",
    POST = "POST",
    PUT = "PUT",
    DELETE = "DELETE",
    HEAD = "HEAD",
    OPTIONS = "OPTIONS",
    TRACE = "TRACE",
    CONNECT = "CONNECT",
    SERVICE = "SERVICE"
}


local DIR_SEPARATOR = string.match (package.config, "[^\n]+")
local STRING_PATH_PARAM = { start = string.byte(":"), valueOf = tostring }
local NUM_PATH_PARAM = { start = string.byte("#"), valueOf = tonumber }
TAB = '    '


local function registerResource(app, resource)
    local route = assert(app.root, "App root not defined")
    local path = assert(resource.path , "Handler definition is missing value for 'path'")
    local handlerFn = assert(resource.handler, "Handler definition is missing 'handler' function")
    local method = resource.method or 'SERVICE'    
    if(not HTTP_METHODS[method]) then
        error(method.." is not a valid HTTP method")
    end

    for pseg in string.gmatch(path, "([^/]+)") do
        local firstChar = string.byte(pseg)
        local pathParam = nil
        if ((firstChar == STRING_PATH_PARAM.start)or(firstChar == NUM_PATH_PARAM.start)) then
            pathParam = pseg:sub(2)
            pseg = "_path_param_"
        end

        local childRoutes = route.childRoutes
        if (not childRoutes) then
            childRoutes = {}
            route.childRoutes = childRoutes
        end

        local nextRoute = childRoutes[pseg]
        if not nextRoute then
            nextRoute = {}
            if pathParam then
                nextRoute.pathParam = pathParam
                if (firstChar == NUM_PATH_PARAM.start) then
                    nextRoute.pathParamType = NUM_PATH_PARAM
                else
                    nextRoute.pathParamType = STRING_PATH_PARAM
                end
            end
            childRoutes[pseg] = nextRoute
        end
        route = nextRoute
    end

    assert(route, "Could not register handler for path "..path)
    assert((not route[method]), 'Handler already registered for '..method..' for path '..'"/'..path..'"')
    route[method] = {handler = handlerFn}
end

local function findAction(app, method, path)
    assert(app, "app may not be nil")
    assert(method, "method may not be nil")
    assert(path, "resource path may not be nil")

    local route = app.root
    local pathParams = {}

    for pseg in string.gmatch(path, "([^/]+)") do
        -- first iteration only
        local childRoutes = route.childRoutes
        if (not childRoutes) then
            return nil
        end

        local nextRoute = childRoutes[pseg]
        if not nextRoute then
            -- may be it's a path param
            nextRoute = childRoutes["_path_param_"]
            if nextRoute then
                pathParams[nextRoute.pathParam] = nextRoute.pathParamType.valueOf(pseg)
            end
        end

        if not nextRoute then 
            return nil 
        end

        route = nextRoute
    end

    if (not route) then
        -- check if default match all route exists
        route = app.root.childRoutes['*']
    end

    if (route) then
        local action = route[method]
        if not action then
            -- try catch call action as a fallback
            action = route['SERVICE']
        end
        return action, pathParams
    end
end


local function generateViewSource(viewFile)
    local firstLine = true
    local lastLine = false
    local viewLines = io.lines(viewFile)

    return function()
        local line = nil
        if firstLine then
            firstLine = false
            line = "return function(httpConn, model, BEGIN, TEXT, END) "
        else
            if (not lastLine) then
                local vl = viewLines()
                if (not vl) then
                    lastLine = true
                    line = "end"
                else
                    line = vl
                end
            end
        end
        if line then
            return (line .. '\n')
        end
    end
end

local function compileView(viewFile)
    local viewDefn = generateViewSource(viewFile)
    local compiledView, errMesg = load(viewDefn, viewFile)
    if (not compiledView) then
        luaw_utils_lib.formattedLine("\nError while compiling view: "..view)
        error(errMesg)
    end
    return compiledView()
end

local function loadResourcesAndViews(folder, app)
    if (not folder) then return end
    
    for file in lfs.dir(folder) do
        if (file ~= '.' and file ~= '..') then
            local f = folder..DIR_SEPARATOR..file
            local attrs = lfs.attributes(f)
            if attrs then
                local mode = attrs.mode
                if (mode == 'file') then
                    -- reinitialize global variable
                    webapp = app
                    if (string.find(f, "handler.lua", 1, true)) then
                        -- resource
                        luaw_utils_lib.formattedLine(".Loading resource "..f)
                        local routeDefn = assert(loadfile(f), string.format("Could not load resource %s", f))
                        routeDefn()
                    elseif (string.find(f, "view.lua", 1, true)) then
                        -- view
                        luaw_utils_lib.formattedLine(".Loading view     "..f)
                        app.compiledViews[file] = compileView(f)
                    end
                elseif (mode == 'directory') then
                    -- recurse
                    loadResourcesAndViews(f, webapp)
                end
            end
        end
    end
    
    return app
end

local function loadApp(basedir)
    return loadResourcesAndViews(
        basedir, 
        {   -- app object
            registerResource = registerResource,
            findAction = findAction,
            root = { 
                childRoutes = {} 
            },
            compiledViews = {}
        }
    )
end

local function sendHTTPError(conn, status, errmesg)
    conn:setStatus(status)
    conn:appendBody(errmesg)
    conn:flush()
    conn:close()
    error(errmesg)
end

local function renderView(conn, viewPath, model)
    local compiledView = conn.luaw_views[viewPath]
    if (not compiledView) then
        sendHTTPError(conn, 500, 'Missing view definition: '..viewPath)
        return
    end

    local isTagOpen = false
    local indent = 0

    local attributes = function(attrs)
        if attrs then
            for k,v in pairs(attrs) do
                conn:appendBody(' ')
                conn:appendBody(k)
                conn:appendBody('="')
                conn:appendBody(tostring(v))
                conn:appendBody('"')
            end
        end
    end

    local BEGIN = function(tag)
        if (isTagOpen) then
            conn:appendBody('>\n')
        end
        for i=1, indent do
            conn:appendBody(TAB)
        end
        conn:appendBody('<')
        conn:appendBody(tag)
        isTagOpen = true;
        indent = indent+1
        return attributes
    end

    local END = function(tag)
        if (isTagOpen) then
            conn:appendBody('>\n')
            isTagOpen = false;
        end

        indent = indent - 1
        if indent > 0 then
            indent = indent
        else
            indent = 0
        end
        for i=1, indent do
            conn:appendBody(TAB)
        end

        conn:appendBody('</')
        conn:appendBody(tag)
        conn:appendBody('>\n')
    end

    local TEXT = function(...)
        if (isTagOpen) then
            conn:appendBody('>\n')
            isTagOpen = false;
        end
        for i=1, indent do
            conn:appendBody(TAB)
        end
        local values = {...}
        for i,v in ipairs(values) do
            conn:appendBody(tostring(v))
            conn:appendBody(' ')
        end
        conn:appendBody('\n')
    end

    -- render view
    if (conn.luaw_view_chunked) then
        conn:startStreaming()
    end

    compiledView(conn, model, BEGIN, TEXT, END)
end

local function serviceHTTP(webapp, rawConn)
    luaw_tcp_lib.startReading(rawConn)

    -- loop to support HTTP 1.1 persistent (keep-alive) connections
    while true do    
        local conn = luaw_tcp_lib.wrapConnection(rawConn)
        luaw_http_lib.addHttpServerMethods(conn)

        -- read and parse request till HTTP headers
        conn:readHeaders()
        local parsedURL = conn.parsedURL

        if (not(conn.method and  parsedURL)) then
            sendHTTPError(conn, 400, "No URL found in HTTP request")
        end

        local action, pathParams = findAction(webapp, conn.method, parsedURL.path)
        if (not action) then
            sendHTTPError(conn, 400, "No action found for path "..parsedURL.path.." for method "..conn.method)
        end

        if conn:shouldCloseConnection() then
            conn.responseHeaders['Connection'] = 'close'
        else
            conn.responseHeaders['Connection'] = 'Keep-Alive'
        end

        -- use chunked encoding response if request was HTTP 1.1 or greater
        if ((conn.major_version >= 1)and(conn.minor_version >= 1)) then
            conn.luaw_view_chunked = true
        end

        conn.pathParams = pathParams
        conn.luaw_views = webapp.compiledViews    
        conn.renderView = renderView

        -- call the actual handler
        action.handler(conn)

        -- Consume any outstanding bytes of the current request just in case some badly written
        -- user handler returns prematurely without reading the request fully. Such incomplete
        -- readers may cause issues in processing subsequent requests in case of HTTP pipelining.
        conn:readBody()
        conn:flush()

        --free bufffers
        conn:free()        
    end
end

local function loadWebApp(basedir)
    luaw_utils_lib.formattedLine('Starting webapp', 120, '*', '\n')
    local webapp = loadApp(basedir)
    webapp.httpHandler = function()
        return function(conn)
            serviceHTTP(webapp, conn)
        end
    end
    luaw_utils_lib.formattedLine('Webapp started', 120, '*')
    return webapp
end


return {
    loadApp = loadApp,
    loadWebApp = loadWebApp
}
