--[[=========================================================================
    XClient auto-loader - lightweight, disk-cached
    -------------------------------------------------------------------------
    A drop-in replacement for the plain one-shot

       local XClient = loadstring(game:HttpGet("URL_TO/xclient.lua"))()

    line.  Instead of pulling the whole library over HTTP on every injection it
    keeps a local copy of xclient.lua on disk and only asks the repository for a
    tiny version marker:

       * first run         -> downloads xclient.lua, writes it to the cache
                              folder (writefile) and remembers its version;
       * later runs        -> fetches only the version / hash with a short
                              request; when it has not changed the saved file
                              is loaded straight from disk (readfile);
       * a new version     -> re-downloads xclient.lua and refreshes the cache;
       * no network at all -> keeps using the cached copy (offline friendly).

    Usage
       local XClient = loadstring(game:HttpGet("URL_TO/loader.lua"))()

    The loader returns the library table exactly like xclient.lua does and also
    registers it as getgenv().XClient, so nothing else in your script changes.

    Configuration lives in Loader.Config below - point User / Repo / Branch at
    your fork.  Everything else has a sensible default.
=========================================================================]]

local Loader = {}
Loader.Version = "1.0.3"

--=========================================================================
--  1. CONFIGURATION
--=========================================================================

Loader.Config = {
    User   = "geragori11",
    Repo   = "xclientnew",
    Branch = "main",
    File   = "Rayfield-main/xclient.lua",

    DirectURL = "https://raw.githubusercontent.com/geragori11/xclientnew/refs/heads/main/Rayfield-main/xclient.lua",

    VersionURL = nil,

    Folder     = "XClient",
    CacheFile  = "xclient.lua",
    MarkerFile = ".version",

    Cache   = true,
    Offline = false,
}

--=========================================================================
--  2. SMALL HELPERS
--=========================================================================

local function withOptions(options)
    local cfg = {}
    for key, value in pairs(Loader.Config) do
       cfg[key] = value
    end
    if type(options) == "table" then
       for key, value in pairs(options) do
          cfg[key] = value
       end
    end
    return cfg
end

local function candidateURLs(cfg)
    local cleanBranch = tostring(cfg.Branch or "main"):gsub("^refs/heads/", "")
    local cacheBust = tostring(os and os.time and os.time() or math.random(100000, 999999))
    local list = {}

    if cfg.DirectURL and cfg.DirectURL ~= "" then
       list[#list + 1] = cfg.DirectURL
       list[#list + 1] = cfg.DirectURL .. "?t=" .. cacheBust
    end

    list[#list + 1] = string.format("https://raw.githubusercontent.com/%s/%s/refs/heads/%s/%s", cfg.User, cfg.Repo, cleanBranch, cfg.File)
    list[#list + 1] = string.format("https://raw.githubusercontent.com/%s/%s/refs/heads/%s/%s?t=%s", cfg.User, cfg.Repo, cleanBranch, cfg.File, cacheBust)
    list[#list + 1] = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", cfg.User, cfg.Repo, cleanBranch, cfg.File)
    list[#list + 1] = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s?t=%s", cfg.User, cfg.Repo, cleanBranch, cfg.File, cacheBust)
    list[#list + 1] = string.format("https://github.com/%s/%s/raw/refs/heads/%s/%s", cfg.User, cfg.Repo, cleanBranch, cfg.File)
    list[#list + 1] = string.format("https://github.com/%s/%s/raw/%s/%s", cfg.User, cfg.Repo, cleanBranch, cfg.File)

    return list
end

local function cachePath(cfg)
    return cfg.Folder .. "/" .. cfg.CacheFile
end

local function markerPath(cfg)
    return cfg.Folder .. "/" .. cfg.MarkerFile
end

local function filesystemAvailable()
    return type(writefile) == "function"
       and type(readfile) == "function"
       and type(isfile) == "function"
       and type(isfolder) == "function"
       and type(makefolder) == "function"
end

local function ensureFolder(path)
    if type(makefolder) ~= "function" or type(isfolder) ~= "function" then return end
    local segments = {}
    for segment in string.gmatch(path, "[^/]+") do
       segments[#segments + 1] = segment
       local current = table.concat(segments, "/")
       if not isfolder(current) then
          pcall(makefolder, current)
       end
    end
end

local function requestHTTP(url)
    if type(url) ~= "string" or url == "" then return nil end

    if type(game) == "table" and type(game.HttpGet) == "function" then
       local ok, body = pcall(function()
          return game:HttpGet(url)
       end)
       if ok and type(body) == "string" and #body > 50 and not body:find("404: Not Found") and not body:find("<!DOCTYPE html>") then
          return body
       end

       ok, body = pcall(function()
          return game:HttpGet(url, true)
       end)
       if ok and type(body) == "string" and #body > 50 and not body:find("404: Not Found") and not body:find("<!DOCTYPE html>") then
          return body
       end
    end

    local customReq = (syn and syn.request) or (http and http.request) or http_request or request
    if type(customReq) == "function" then
       local ok, res = pcall(customReq, {
          Url = url,
          Method = "GET"
       })
       if ok and type(res) == "table" and res.StatusCode == 200 and type(res.Body) == "string" and #res.Body > 50 then
          return res.Body
       end
    end

    return nil
end

local function downloadFile(cfg)
    local urls = candidateURLs(cfg)
    for _, url in ipairs(urls) do
       local body = requestHTTP(url)
       if body and #body > 50 then
          return body
       end
    end
    return nil
end

local function getHttpService()
    if type(game) ~= "table" then return nil end
    local ok, service = pcall(function()
       return game:GetService("HttpService")
    end)
    if ok then return service end
    return nil
end

--=========================================================================
--  3. VERSION RESOLUTION
--=========================================================================

local function normalizeVersion(text)
    if type(text) ~= "string" then return nil end
    text = string.gsub(text, "%s+", "")
    if text == "" then return nil end
    return text
end

local function fetchMarkerVersion(cfg)
    if not cfg.VersionURL then return nil end
    return normalizeVersion(requestHTTP(cfg.VersionURL))
end

local function fetchApiVersion(cfg)
    local HttpService = getHttpService()
    if not HttpService then return nil end
    local cleanBranch = tostring(cfg.Branch or "main"):gsub("^refs/heads/", "")
    local url = string.format(
       "https://api.github.com/repos/%s/%s/commits?path=%s&sha=%s&per_page=1",
       cfg.User, cfg.Repo, cfg.File, cleanBranch)
    local body = requestHTTP(url)
    if not body then return nil end
    local ok, data = pcall(function()
       return HttpService:JSONDecode(body)
    end)
    if ok and type(data) == "table" and type(data[1]) == "table" and data[1].sha then
       return tostring(data[1].sha)
    end
    return nil
end

local function resolveRemoteVersion(cfg)
    return fetchMarkerVersion(cfg) or fetchApiVersion(cfg)
end

--=========================================================================
--  4. CACHE
--=========================================================================

local function readCache(cfg)
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return nil end
    local path = cachePath(cfg)
    if not isfile(path) then return nil end
    local ok, contents = pcall(readfile, path)
    if ok and type(contents) == "string" and contents ~= "" then
       return contents
    end
    return nil
end

local function writeCache(cfg, source)
    if not filesystemAvailable() or type(source) ~= "string" then return false end
    ensureFolder(cfg.Folder)
    return pcall(writefile, cachePath(cfg), source)
end

local function readMarker(cfg)
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return nil end
    local path = markerPath(cfg)
    if not isfile(path) then return nil end
    local ok, contents = pcall(readfile, path)
    if ok then return normalizeVersion(contents) end
    return nil
end

local function writeMarker(cfg, version)
    if not filesystemAvailable() or type(version) ~= "string" then return false end
    ensureFolder(cfg.Folder)
    return pcall(writefile, markerPath(cfg), version)
end

--=========================================================================
--  5. LOADING
--=========================================================================

local function runSource(source, label)
    local chunk, compileError = loadstring(source, "@" .. (label or "xclient.lua"))
    if not chunk then
       return nil, "compile error: " .. tostring(compileError)
    end
    local ok, result = pcall(chunk)
    if not ok then
       return nil, "runtime error: " .. tostring(result)
    end
    return result
end

function Loader:Fetch(options)
    local cfg = withOptions(options)
    local source = downloadFile(cfg)
    if type(source) ~= "string" then return nil, "the repository is unreachable" end
    if cfg.Cache then
       writeCache(cfg, source)
       local remoteVersion = resolveRemoteVersion(cfg)
       if remoteVersion then writeMarker(cfg, remoteVersion) end
    end
    local library, loadError = runSource(source, cfg.File)
    if not library then return nil, loadError end
    if getgenv then getgenv().XClient = library end
    return library
end

function Loader:Load(options)
    local cfg = withOptions(options)

    local cachedSource  = cfg.Cache and readCache(cfg) or nil
    local cachedVersion = readMarker(cfg)

    local remoteVersion = nil
    if not cfg.Offline then
       remoteVersion = resolveRemoteVersion(cfg)
    end

    local upToDate = cachedSource ~= nil
       and (cfg.Offline or remoteVersion == nil or remoteVersion == cachedVersion)

    local usedCache = false
    local source = nil

    if upToDate then
       source = cachedSource
       usedCache = true
       if remoteVersion and remoteVersion ~= cachedVersion then
          writeMarker(cfg, remoteVersion)
       end
    else
       source = downloadFile(cfg)
       if source then
          if cfg.Cache then
             writeCache(cfg, source)
             if remoteVersion then
                writeMarker(cfg, remoteVersion)
             else
                writeMarker(cfg, tostring(os and os.time and os.time() or "1"))
             end
          end
       elseif cachedSource then
          source = cachedSource
          usedCache = true
       end
    end

    if not source then
       error("[XClient loader] could not obtain xclient.lua: no cached copy and the repository is unreachable.", 0)
    end

    local library, loadError = runSource(source, cfg.File)
    if not library and usedCache then
       local fresh = downloadFile(cfg)
       if fresh then
          if cfg.Cache then
             writeCache(cfg, fresh)
             local freshVersion = remoteVersion or resolveRemoteVersion(cfg)
             if freshVersion then writeMarker(cfg, freshVersion) end
          end
          library, loadError = runSource(fresh, cfg.File)
       end
    end

    if not library then
       error("[XClient loader] xclient.lua failed to load (" .. tostring(loadError) .. ").", 0)
    end

    if getgenv then getgenv().XClient = library end
    return library
end

--=========================================================================
--  6. PUBLIC UTILITIES
--=========================================================================

function Loader:GetVersion(options)
    return readMarker(withOptions(options))
end

function Loader:CheckForUpdate(options)
    local cfg = withOptions(options)
    local localVersion = readMarker(cfg)
    local remoteVersion = resolveRemoteVersion(cfg)
    return remoteVersion, (remoteVersion ~= nil and remoteVersion ~= localVersion)
end

function Loader:Update(options)
    local cfg = withOptions(options)
    local source = downloadFile(cfg)
    if type(source) ~= "string" then return false end
    local ok = writeCache(cfg, source)
    local remoteVersion = resolveRemoteVersion(cfg)
    if remoteVersion then writeMarker(cfg, remoteVersion) end
    return ok and true or false
end

function Loader:ClearCache(options)
    local cfg = withOptions(options)
    if type(delfile) ~= "function" or type(isfile) ~= "function" then return false end
    local removed = false
    for _, path in ipairs({ cachePath(cfg), markerPath(cfg) }) do
       if isfile(path) then
          if pcall(delfile, path) then removed = true end
       end
    end
    return removed
end

--=========================================================================
--  7. AUTO-RUN
--=========================================================================

local autoOptions
if getgenv then
    pcall(function()
       local env = getgenv()
       if type(env) == "table" then autoOptions = env.XClientLoaderOptions end
    end)
end

local XClient = Loader:Load(autoOptions)

if getgenv then
    getgenv().XClientLoader = Loader
end

return XClient