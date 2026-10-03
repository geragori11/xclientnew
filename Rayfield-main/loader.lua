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
Loader.Version = "1.0.0"

--=========================================================================
--  1. CONFIGURATION
--=========================================================================

Loader.Config = {
    --  Repository that hosts the library (edit these three to your own fork).
    User   = "geragori11",
    Repo   = "xclientnew",
    Branch = "main",
    File   = "Rayfield-main/xclient.lua",

    --  Optional tiny marker published next to the library, e.g. "v1.2.0" or a
    --  short hash.  When set it is used for the version check (~40 bytes)
    --  instead of the GitHub API.  Leave it nil to ask the GitHub API for the
    --  hash of the latest commit that touched File - that stays correct on its
    --  own, without bumping anything by hand.
    --      e.g. "https://raw.githubusercontent.com/<user>/<repo>/<branch>/version.txt"
    VersionURL = nil,

    --  Cache location - a single folder inside the executor's workspace.
    Folder     = "XClient",
    CacheFile  = "xclient.lua",   -- the saved library (read back with readfile)
    MarkerFile = ".version",      -- the last seen remote version / hash

    --  Cache = false -> always re-download (handy while editing the library).
    Cache   = true,
    --  Offline = true -> never touch the network, use the cached copy only.
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

local function rawURL(cfg)
    return string.format(
       "https://raw.githubusercontent.com/%s/%s/%s/%s",
       cfg.User, cfg.Repo, cfg.Branch, cfg.File)
end

local function cachePath(cfg)
    return cfg.Folder .. "/" .. cfg.CacheFile
end

local function markerPath(cfg)
    return cfg.Folder .. "/" .. cfg.MarkerFile
end

--  The functions every executor that supports file IO exposes.  When they are
--  missing the loader still works, it just cannot cache between runs.
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

--  GET wrapped in a pcall.  The second argument asks the executor to bypass its
--  own HTTP cache so a fresh version marker really is fresh; clients whose
--  HttpGet takes a single argument are retried without it.
local function httpGet(url)
    if type(url) ~= "string" or url == "" or type(game) ~= "table" then return nil end
    if type(game.HttpGet) ~= "function" then return nil end
    local ok, body = pcall(function()
       return game:HttpGet(url, true)
    end)
    if ok and type(body) == "string" and body ~= "" then
       return body
    end
    ok, body = pcall(function()
       return game:HttpGet(url)
    end)
    if ok and type(body) == "string" and body ~= "" then
       return body
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
--  3. VERSION RESOLUTION (the short request)
--=========================================================================

local function normalizeVersion(text)
    if type(text) ~= "string" then return nil end
    text = string.gsub(text, "%s+", "")
    if text == "" then return nil end
    return text
end

--  A tiny companion file, when the fork publishes one.
local function fetchMarkerVersion(cfg)
    if not cfg.VersionURL then return nil end
    return normalizeVersion(httpGet(cfg.VersionURL))
end

--  Fallback: the hash of the latest commit that touched the library file.  It
--  changes on its own every time xclient.lua is pushed, so there is nothing to
--  keep in sync by hand.
local function fetchApiVersion(cfg)
    local HttpService = getHttpService()
    if not HttpService then return nil end
    local url = string.format(
       "https://api.github.com/repos/%s/%s/commits?path=%s&sha=%s&per_page=1",
       cfg.User, cfg.Repo, cfg.File, cfg.Branch)
    local body = httpGet(url)
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

--  Downloads the library once, runs it and returns whatever it returned.  Does
--  not consult the cache - Load() uses it to refresh a damaged copy.
function Loader:Fetch(options)
    local cfg = withOptions(options)
    local source = httpGet(rawURL(cfg))
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

--  The main entry point.  Returns the library table (the same value xclient.lua
--  returns) or raises an error when neither the cache nor the repository could
--  provide a working copy.
function Loader:Load(options)
    local cfg = withOptions(options)

    local cachedSource  = cfg.Cache and readCache(cfg) or nil
    local cachedVersion = readMarker(cfg)

    --  One short request decides everything (unless we were told to stay offline).
    local remoteVersion
    if not cfg.Offline then
       remoteVersion = resolveRemoteVersion(cfg)
    end

    --  The cached copy wins when it exists and we already have the newest
    --  version, could not reach the repository, or were asked to stay offline.
    local upToDate = cachedSource ~= nil
       and (cfg.Offline or remoteVersion == nil or remoteVersion == cachedVersion)

    local usedCache = false
    local source

    if upToDate then
       source = cachedSource
       usedCache = true
       --  Heal a missing / stale marker we just learned the right value for.
       if remoteVersion and remoteVersion ~= cachedVersion then
          writeMarker(cfg, remoteVersion)
       end
    else
       source = httpGet(rawURL(cfg))
       if source then
          if cfg.Cache then
             writeCache(cfg, source)
             if remoteVersion then writeMarker(cfg, remoteVersion) end
          end
       elseif cachedSource then
          --  Download failed but an older copy is still there: keep working.
          source = cachedSource
          usedCache = true
       end
    end

    if not source then
       error("[XClient loader] could not obtain xclient.lua: no cached copy and the repository is unreachable.", 0)
    end

    local library, loadError = runSource(source, cfg.File)
    if not library and usedCache then
       --  The cached file is damaged: try one fresh download before giving up.
       local fresh = httpGet(rawURL(cfg))
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
--  6. PUBLIC UTILITIES (optional)
--=========================================================================

--  The version currently stored in the cache, or nil when there is none.
function Loader:GetVersion(options)
    return readMarker(withOptions(options))
end

--  Asks the repository for the newest version and reports whether it differs
--  from the cached one:  remoteVersion, hasUpdate
function Loader:CheckForUpdate(options)
    local cfg = withOptions(options)
    local localVersion = readMarker(cfg)
    local remoteVersion = resolveRemoteVersion(cfg)
    return remoteVersion, (remoteVersion ~= nil and remoteVersion ~= localVersion)
end

--  Forces a re-download of the library into the cache (does not run it).
function Loader:Update(options)
    local cfg = withOptions(options)
    local source = httpGet(rawURL(cfg))
    if type(source) ~= "string" then return false end
    local ok = writeCache(cfg, source)
    local remoteVersion = resolveRemoteVersion(cfg)
    if remoteVersion then writeMarker(cfg, remoteVersion) end
    return ok and true or false
end

--  Removes the cached library and its version marker.
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
--  Runs exactly like the one-shot HttpGet line it replaces.  Callers that want
--  to override the configuration without editing this file can set
--  getgenv().XClientLoaderOptions = { ... } before loading it.
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