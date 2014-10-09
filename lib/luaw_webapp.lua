local lfs = require('lfs')
local Luaw = require("luaw_lib")
local template_compiler = require ("luaw_template_compiler")

local registeredWebApps = {}

local DIR_SEPARATOR = string.match (package.config, "[^\n]+")
local STRING_PATH_PARAM = { start = string.byte(":"), valueOf = tostring }
local NUM_PATH_PARAM = { start = string.byte("#"), valueOf = tonumber }

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

local pathIterator = Luaw.splitter('/')
local function splitPath(path)
    if not path then return Luaw.nilFn end
    return pathIterator, path, 0
end

local function findAction(method, path)
    assert(method, "HTTP method may not be nil")
    assert(method, "HTTP request path may not be nil")

    local webApp = nil
    local route = nil
    local pathParams = {}

    for idx, pseg in splitPath(path) do
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
            local nextRoute = route.childRoutes[pseg]
            if not nextRoute then
                -- may be it's a path param
                nextRoute = route.childRoutes["_path_param_"]
                if nextRoute then
                    pathParams[nextRoute.pathParam] = nextRoute.pathParamType.valueOf(pseg)
                end
            end
            if not nextRoute then return nil end
            route = nextRoute
        end
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

local function dispatchAction(req, resp)
    assert(req, "HTTP request may not be nil")

    req:readFull() -- read and parse full request
    local parsedURL = req:getParsedURL()

    if not(req.method and  parsedURL) then
        -- EOF in case of persistent connections
        return
    end

    local webApp, action, pathParams = findAction(req.method, parsedURL.path)
    assert(action, "No action found for path "..parsedURL.path.." for method "..req.method)

    if req:shouldCloseConnection() then
        resp:addHeader('Connection', 'close')
    end

    v1, v2 = action.action(req, resp, pathParams)

    -- handle action returned response, if any
    if v1 then
        if (type(v1) == 'number') then
            -- v1 is HTTP status
            resp:setStatus(v1)
            resp:startStreaming()
            if v2 then
                -- v2 is body content
                resp:appendBody(tostring(v2))
            end
        else
            if not resp.statusCode then
                resp:setStatus(200)
            end
            resp:startStreaming()
            if ((type(v1) == 'string')and(v2)) then
                -- v1 is view path, v2 is view model
                local compiledView = webApp.compiledViews[v1]
                if not compiledView then
                    error("View '"..tostring(v1).."' is not defined")
                end
                compiledView(req, resp, pathParams, v2)
            else
                -- v1 is the body content itself
                resp:appendBody(tostring(v1))
            end
        end
    end

    resp:flush()
end

local function registerAction(webapp, method, path, action)
    local route = webapp.root
    for idx, pseg in splitPath(path) do
        local firstChar = string.byte(pseg)
        local pathParam = nil
        if ((firstChar == STRING_PATH_PARAM.start)or(firstChar == NUM_PATH_PARAM.start)) then
            pathParam = pseg:sub(2)
            pseg = "_path_param_"
        end

        local nextRoute = route.childRoutes[pseg]
        if not nextRoute then
            nextRoute = { childRoutes = {} }
            if pathParam then
                nextRoute.pathParam = pathParam
                if (firstChar == NUM_PATH_PARAM.start) then
                    nextRoute.pathParamType = NUM_PATH_PARAM
                else
                    nextRoute.pathParamType = STRING_PATH_PARAM
                end
            end
            route.childRoutes[pseg] = nextRoute
        end
        route = nextRoute
    end

    assert(route, "Could not register action "..path)
    assert((not route[method]), 'Action already registered for '..method..' for path "/'..webapp.path..'/'..path..'"')
    action.action = action[1]
    action[1] = nil
    route[method] = action
end

local webappMT = {}
webappMT.__index = webappMT

function webappMT.GET(webapp, path)
    return function(route)
        registerAction(webapp, 'GET', path, route)
    end
end

function webappMT.POST(webapp, path)
    return function(route)
        registerAction(webapp, 'POST', path, route)
    end
end

function webappMT.PUT(webapp, path)
    return function(route)
        registerAction(webapp, 'PUT', path, route)
    end
end

function webappMT.DELETE(webapp, path)
    return function(route)
        registerAction(webapp, 'DELETE', path, route)
    end
end

function webappMT.HEAD(webapp, path)
    return function(route)
        registerAction(webapp, 'HEAD', path, route)
    end
end

function webappMT.OPTIONS(webapp, path)
    return function(route)
        registerAction(webapp, 'OPTIONS', path, route)
    end
end

function webappMT.TRACE(webapp, path)
    return function(route)
        registerAction(webapp, 'TRACE', path, route)
    end
end

function webappMT.CONNECT(webapp, path)
    return function(route)
        registerAction(webapp, 'CONNECT', path, route)
    end
end

function webappMT.SERVICE(webapp, path)
    return function(route)
        registerAction(webapp, 'SERVICE', path, route)
    end
end

local function httpErrorHandler(req, resp, errMesg)
    print(errMesg)
    local httpCode, httpMesg = Luaw.toHttpError(errMesg)
    if (httpCode == 0) then httpCode = 500 end
    resp:setStatus(httpCode)
    resp:addHeader('Connection', 'close')
    resp:appendBody(httpMesg)
    resp:flush()
end

local function serviceHTTP(conn)
    -- loop to support HTTP 1.1 persistent (keep-alive) connections
    while true do
        local req = Luaw.newServerHttpRequest(conn)
        local resp = Luaw.newServerHttpResponse(conn)
        local status, errMesg = pcall(dispatchAction, req, resp)
        if (not status) then
            httpErrorHandler(req, resp, errMesg)
        end
        if (req:shouldCloseConnection() or resp:shouldCloseConnection()) then
            resp:close()
            print('closed connection')
            break
        end
        print('connection persistent')
    end
end

local function toFullPath(appRoot, files)
    local fullPaths = {}
    if files then
        for i, file in ipairs(files) do
            table.insert(fullPaths, appRoot..'/'..file)
        end
    end
    return fullPaths
end

local function loadWebApp(appName, appDir)
    local app = {}
    setmetatable(app, webappMT)

    app.path = assert(appName, "Missing mandatory configuration property 'path'")
    app.appRoot = assert(appDir, "Missing mandatory configuration property 'root_dir'")

    if (registeredWebApps[app.path]) then
        error('Anothe web app is already registered for path '..app.path)
    end
    registeredWebApps[app.path] = app

    app.root = { childRoutes = {} }

    -- Load resource handlers
    local resources = toFullPath(app.appRoot, luaw_webapp.resources)
    if luaw_webapp.resourcePattern then
        resources = findFiles(app.appRoot, luaw_webapp.resourcePattern, resources)
    end
    assert((resources and (#resources > 0)), "Either 'resources' or 'resourcePattern' must be specified in a web app configuration")
    app.resources = resources

    -- Load view files if any
    local views = toFullPath(app.appRoot, luaw_webapp.views)
    if luaw_webapp.viewPattern then
        views = findFiles(app.appRoot, luaw_webapp.viewPattern, views)
    end
    app.views = views

    return app
end

local function startWebApp(app)
    -- register resources
    local resources = app.resources
    for i,resource in ipairs(resources) do
        Luaw.formattedLine(".Loading resource "..resource)
        -- declare global variable 'action' for the duration of the loadfile(resource)
        action = app
        local routeDefn = assert(loadfile(resource), string.format("Could not load resource %s", resource))
        routeDefn()
    end
    Luaw.formattedLine("#Loaded total "..#resources.." resources\n")

    -- compile views
    local views = app.views
    local compiledViews = {}
    local appRootLen = string.len(app.appRoot) + 1
    for i,view in ipairs(views) do
        local relativeViewPath = string.sub(view, appRootLen)
        Luaw.formattedLine(".Compiling view "..view)
        local compiledView = template_compiler.compileFile(view)
        compiledViews[relativeViewPath] = compiledView
    end
    app.views = nil
    app.compiledViews = compiledViews
    Luaw.formattedLine("#Compiled total "..#views.." views")
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
                        Luaw.formattedLine('Starting webapp '..webappName, 120, '*', '\n')
                        dofile(webappCfgFile) -- defines global variable luaw_webapp
                        local app = loadWebApp(webappName, webappDir)
                        startWebApp(app)
                        Luaw.formattedLine('Webapp '..webappName..' started', 120, '*')
                        webapp = nil  -- reset global variable
                    end
                end
            end
        end
    end
end

-- install REST HTTP app handler as a default request handler
Luaw.request_handler = serviceHTTP

return {
    init = init,
    dispatchAction = dispatchAction,
    serviceHTTP = serviceHTTP
}