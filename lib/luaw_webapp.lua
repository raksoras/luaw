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

local registeredWebApps = {}

local DIR_SEPARATOR = string.match (package.config, "[^\n]+")
local STRING_PATH_PARAM = { start = string.byte(":"), valueOf = tostring }
local NUM_PATH_PARAM = { start = string.byte("#"), valueOf = tonumber }

TAB = '    '

local function findFiles(path, pattern, matches)
    if (path and pattern) then
        for file in lfs.dir(path) do
            if (file ~= '.' and file ~= '..') then
                local f = path..DIR_SEPARATOR..file
                local attrs = lfs.attributes(f)
                if attrs then
                    local mode = attrs.mode
                    if mode == 'file' then
                        if (string.match(f, pattern)) then
                            table.insert(matches, f)
                        end
                    elseif mode == 'directory' then
                        findFiles(f, pattern, matches)
                    end
                end
            end
        end
    end
    return matches
end

local function findAction(method, path)
    assert(method, "HTTP method may not be nil")
    assert(method, "HTTP request path may not be nil")

    local webApp = nil
    local route = nil
    local pathParams = {}

    for pseg in string.gmatch(path, "([^/]+)") do
        -- first iteration only
        if not webApp then
            webApp = registeredWebApps[pseg]
            if not webApp then
                -- fallback to root path
                webApp = registeredWebApps['/']
            end
            if not webApp then
                return nil
            end
            route = webApp.root
        else
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
    end

    if (not route) then
        -- check if default match all route exists
        route = webApp.root.childRoutes['*']
    end

    if (route) then
        local action = route[method]
        if not action then
            -- try catch call action as a fallback
            action = route['SERVICE']
        end
        return webApp, action, pathParams
    end
end

local function renderView(resp, viewPath, model)
    local compiledView = resp.luaw_views[viewPath]
    if (not compiledView) then
        resp:appendBody('Missing view definition: '..viewPath)
        return
    end

    local isTagOpen = false
    local indent = 0

    local attributes = function(attrs)
        if attrs then
            for k,v in pairs(attrs) do
                resp:appendBody(' ')
                resp:appendBody(k)
                resp:appendBody('="')
                resp:appendBody(tostring(v))
                resp:appendBody('"')
            end
        end
    end

    local BEGIN = function(tag)
        if (isTagOpen) then
            resp:appendBody('>\n')
        end
        for i=1, indent do
            resp:appendBody(TAB)
        end
        resp:appendBody('<')
        resp:appendBody(tag)
        isTagOpen = true;
        indent = indent+1
        return attributes
    end

    local END = function(tag)
        if (isTagOpen) then
            resp:appendBody('>\n')
            isTagOpen = false;
        end

        indent = indent - 1
        if indent > 0 then
            indent = indent
        else
            indent = 0
        end
        for i=1, indent do
            resp:appendBody(TAB)
        end

        resp:appendBody('</')
        resp:appendBody(tag)
        resp:appendBody('>\n')
    end

    local TEXT = function(...)
        if (isTagOpen) then
            resp:appendBody('>\n')
            isTagOpen = false;
        end
        for i=1, indent do
            resp:appendBody(TAB)
        end
        local values = {...}
        for i,v in ipairs(values) do
            resp:appendBody(tostring(v))
            resp:appendBody(' ')
        end
        resp:appendBody('\n')
    end

    -- render view
    if (resp.luaw_view_chunked) then
        resp:startStreaming()
    end
    
    compiledView(resp, model, BEGIN, TEXT, END)
end

local function dispatch(req, resp)
    assert(req, "HTTP request may not be nil")
    local parsedURL = req.parsedURL

    if not(req.method and  parsedURL) then
        return false, "No URL found in HTTP request"
    end

    local webApp, action, pathParams = findAction(req.method, parsedURL.path)
    assert(action, "No action found for path "..parsedURL.path.." for method "..req.method)

    req.pathParams = pathParams
    resp.luaw_views = webApp.compiledViews    
    if req:shouldCloseConnection() then
        resp.headers['Connection'] = 'close'
    else
        resp.headers['Connection'] = 'Keep-Alive'
    end

    resp.renderView = renderView
    -- use chunked encoding response if request was HTTP 1.1 or greater
    if ((req.major_version >= 1)and(req.minor_version >= 1)) then
        resp.luaw_view_chunked = true
    end
    action.handler(req, resp, pathParams)
    -- Consume any outstanding bytes of the current request just in case some badly written
    -- user handler returns prematurely without reading the request fully. Such incomplete
    -- readers may cause issues in processing subsequent requests in case of HTTP pipelining.
    req:readBody()
    
    resp:flush()
end

local function registerResource(resource)
    assert(webapp, "webapp not initialized")
    local route = assert(webapp.root, "webapp root not defined")
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
    assert((not route[method]), 'Handler already registered for '..method..' for path "/'..webapp.path..'/'..path..'"')
    route[method] = {handler = handlerFn}
end

local function serviceHTTP(conn)
    conn:startReading()
    local req = luaw_http_lib.newServerHttpRequest(conn)
    local resp = luaw_http_lib.newServerHttpResponse(conn)

    -- loop to support HTTP 1.1 persistent (keep-alive) connections
    while true do    
        req:reset()
        resp:reset()

        -- read and parse request till HTTP headers
        local status, errmesg = pcall(req.readHeaders, req)

        if ((not status)or(req.luaw_EOF == true)) then
            conn:close()
            if (status) then
                return "read time out"
            end
            print(status, "Error: ", errmesg, debug.traceback('', 3))
            return "connection reset by peer"
        end

        status, errMesg = pcall(dispatch, req, resp)
        if (not status) then
            -- send HTTP error response
            resp:setStatus(500)
            resp:addHeader('Connection', 'close')
            pcall(resp.appendBody, resp, errMesg)
            pcall(resp.flush, resp)
            conn:close()
            error(errMesg)
        end

        if (req:shouldCloseConnection() or resp:shouldCloseConnection()) then
            conn:close()
            return "connection reset by peer"
        end
    end
end

local function toFullPath(appBaseDir, files)
    local fullPaths = {}
    if files then
        for i, file in ipairs(files) do
            table.insert(fullPaths, appBaseDir..'/'..file)
        end
    end
    return fullPaths
end

local function loadWebApp(appName, appDir)
    local app = {}

    app.path = assert(appName, "Missing mandatory configuration property 'path'")
    app.appBaseDir = assert(appDir, "Missing mandatory configuration property 'root_dir'")

    if (registeredWebApps[app.path]) then
        error('Anothe web app is already registered for path '..app.path)
    end
    registeredWebApps[app.path] = app

    app.root = { childRoutes = {} }

    -- Load resource handlers
    local resources = toFullPath(app.appBaseDir, luaw_webapp.resources)
    if luaw_webapp.resourcePattern then
        resources = findFiles(app.appBaseDir, luaw_webapp.resourcePattern, resources)
    end
    assert((resources and (#resources > 0)), "Either 'resources' or 'resourcePattern' must be specified in a web.lua")
    app.resources = resources

    -- Load view files if any
    local views = toFullPath(app.appBaseDir, luaw_webapp.views)
    if luaw_webapp.viewPattern then
        views = findFiles(app.appBaseDir, luaw_webapp.viewPattern, views)
    end
    app.views = views

    return app
end

local function loadView(viewPath)
    local firstLine = true
    local lastLine = false
    local viewLines = io.lines(viewPath)

    return function()
        local line = nil

        if firstLine then
            firstLine = false
            line = "return function(resp, model, BEGIN, TEXT, END) "
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

local function startWebApp(app)
    -- register resources
    local resources = app.resources
    for i,resource in ipairs(resources) do
        luaw_utils_lib.formattedLine(".Loading resource "..resource)
        -- declare globals (registerHandler and webapp) for the duration of the loadfile(resource)
        registerHandler = registerResource
        webapp = app
        local routeDefn = assert(loadfile(resource), string.format("Could not load resource %s", resource))
        routeDefn()
    end
    luaw_utils_lib.formattedLine("#Loaded total "..#resources.." resources\n")

    -- compile views
    local views = app.views
    local compiledViews = {}
    local appBaseDirLen = string.len(app.appBaseDir) + 1
    for i,view in ipairs(views) do
        local relativeViewPath = string.sub(view, appBaseDirLen)
        luaw_utils_lib.formattedLine(".Loading view "..relativeViewPath)
        local viewDefn = loadView(view)
        local compiledView, errMesg = load(viewDefn, relativeViewPath)
        if (not compiledView) then
            luaw_utils_lib.formattedLine("\nError while compiling view: "..view)
            error(errMesg)
        end
        compiledViews[relativeViewPath] = compiledView()
    end
    app.views = nil
    app.resources = nil
    app.compiledViews = compiledViews
    luaw_utils_lib.formattedLine("#Compiled total "..#views.." views")
end

local function init()
    if ((luaw_webapp_config)and(luaw_webapp_config.base_dir)) then
        local root = luaw_webapp_config.base_dir
        for webappName in lfs.dir(root) do
            if (webappName ~= '.' and webappName ~= '..') then
                local webappDir = root..DIR_SEPARATOR..webappName
                local attrs = lfs.attributes(webappDir)
                if ((attrs)and(attrs.mode == 'directory')) then
                    local webappCfgFile = webappDir..DIR_SEPARATOR..'web.lua'
                    if (lfs.attributes(webappCfgFile, 'mode') == 'file') then
                        luaw_utils_lib.formattedLine('Starting webapp '..webappName, 120, '*', '\n')
                        dofile(webappCfgFile) -- defines global variable luaw_webapp
                        local app = loadWebApp(webappName, webappDir)
                        startWebApp(app)
                        luaw_utils_lib.formattedLine('Webapp '..webappName..' started', 120, '*')
                        -- reset global variables
                        luaw_webapp = nil
                        webapp = nil  
                    end
                end
            end
        end
    end
end

-- install REST HTTP app handler as a default request handler
scheduler.setRequestHandler(serviceHTTP)

return {
    init = init,
    dispatch = dispatch,
    serviceHTTP = serviceHTTP
}
