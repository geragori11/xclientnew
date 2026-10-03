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
Loader.Version = "1.0.5"

--=========================================================================
--  1. CONFIGURATION
--=========================================================================

Loader.Config = {
    User   = "geragori11",
    Repo   = "xclientnew",
    Branch = "main",
    File   = "Rayfield-main/xclient.lua",

    DirectURL = "https://raw.githubusercontent.com/geragori11/xclientnew/refs/heads/main/Rayfield-main/xclient.lua",

    --  Manual version check - no GitHub API, no rate limit.
    --  "version.txt" is published next to File and holds exactly the string the
    --  library declares in its own 'XClient.Build = "..."' line. The loader
    --  compares that published tag with the build tag of the file on disk, so
    --  it always knows which version it holds and which one is on GitHub.
    VersionFile = "version.txt",

    --  Optional explicit URL for the marker; when nil it is derived from
    --  User/Repo/Branch and the folder of File.
    VersionURL = nil,

    Folder     = "XClient",
    CacheFile  = "xclient.lua",
    MarkerFile = ".version",

    Cache   = true,
    Offline = false,

    --  What to do when the repository version cannot be read (the GitHub API
    --  is rate limited or blocked in most executors):
    --    true  -> verify the copy on disk against the repository before using
    --             it, so a fix pushed to GitHub always reaches the player;
    --    false -> trust the copy on disk anyway (old behaviour, can pin an
    --             outdated library on disk indefinitely).
    VerifyCache = true,
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

local function notify(message)
    if type(warn) == "function" then
       pcall(warn, message)
    elseif type(print) == "function" then
       pcall(print, message)
    end
end

--  minLength defaults to 50 bytes: a shorter body is almost always an error
--  page ("404: Not Found" is 14 bytes). Version markers are tiny, so
--  fetchMarkerVersion asks for a floor of 1 byte instead.
local function requestHTTP(url, minLength)
    if type(url) ~= "string" or url == "" then return nil end
    if type(minLength) ~= "number" then minLength = 50 end

    local function usable(body)
       return type(body) == "string"
          and #body >= minLength
          and not body:find("404: Not Found", 1, true)
          and not body:find("<!DOCTYPE html>", 1, true)
    end

    if type(game) == "table" and type(game.HttpGet) == "function" then
       local ok, body = pcall(function()
          return game:HttpGet(url)
       end)
       if ok and usable(body) then return body end

       ok, body = pcall(function()
          return game:HttpGet(url, true)
       end)
       if ok and usable(body) then return body end
    end

    local customReq = (syn and syn.request) or (http and http.request) or http_request or request
    if type(customReq) == "function" then
       local ok, res = pcall(customReq, {
          Url = url,
          Method = "GET"
       })
       if ok and type(res) == "table" and res.StatusCode == 200 and usable(res.Body) then
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

--  Build tag baked into the library itself ('XClient.Build = "..."'), i.e. the
--  version of the file *on disk*. Reading it means the loader does not depend
--  on the stored marker to know what it holds: the marker may be missing, or
--  written by an older loader as a commit hash.
local function versionFromSource(source)
    if type(source) ~= "string" then return nil end
    return normalizeVersion(string.match(source, 'XClient%.Build%s*=%s*"([^"]+)"'))
end

--  What to remember next to the cached file. When the published *marker* (a
--  manual tag) is what we matched against, the build tag of the file is the
--  honest answer; when the version came from the API (a commit hash) that hash
--  is the only value that can match again on the next run, otherwise the cache
--  would be thrown away on every injection.
local function versionToRemember(source, remoteVersion, remoteSource)
    local build = versionFromSource(source)
    if remoteSource == "marker" then return build or remoteVersion end
    return remoteVersion or build
end

--  URLs of the published version marker (version.txt), cache-busted form first:
--  raw.githubusercontent and most executors may serve a stale cached body.
local function markerURLs(cfg)
    local cleanBranch = tostring(cfg.Branch or "main"):gsub("^refs/heads/", "")
    local bust = tostring(os and os.time and os.time() or math.random(100000, 999999))
    local list = {}

    local function push(url)
       if type(url) ~= "string" or url == "" then return end
       local separator = url:find("?", 1, true) and "&" or "?"
       list[#list + 1] = url .. separator .. "t=" .. bust
       list[#list + 1] = url
    end

    push(cfg.VersionURL)

    if cfg.VersionFile and cfg.VersionFile ~= "" then
       local folder = string.match(tostring(cfg.File or ""), "^(.*)/[^/]+$")
       local path = folder and (folder .. "/" .. cfg.VersionFile) or cfg.VersionFile
       push(string.format("https://raw.githubusercontent.com/%s/%s/refs/heads/%s/%s",
          cfg.User, cfg.Repo, cleanBranch, path))
    end

    return list
end

--  A published version marker is a single short token ("1.0.5"). Anything else
--  (an HTML error page, a proxy notice) is ignored so that a junk response can
--  never be mistaken for a version.
local function isVersionTag(text)
    return type(text) == "string"
       and #text > 0
       and #text <= 64
       and text:match("^[%w][%w%.%-_]*$") ~= nil
end

local function fetchMarkerVersion(cfg)
    for _, url in ipairs(markerURLs(cfg)) do
       local version = normalizeVersion(requestHTTP(url, 1))
       if isVersionTag(version) then return version end
    end
    return nil
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
    local marker = fetchMarkerVersion(cfg)
    if marker then return marker, "marker" end
    local hash = fetchApiVersion(cfg)
    if hash then return hash, "api" end
    return nil, nil
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
       local remoteVersion, remoteSource = resolveRemoteVersion(cfg)
       local version = versionToRemember(source, remoteVersion, remoteSource)
       if version then writeMarker(cfg, version) end
    end
    local library, loadError = runSource(source, cfg.File)
    if not library then return nil, loadError end
    if getgenv then getgenv().XClient = library end
    return library
end

function Loader:Load(options)
    local cfg = withOptions(options)

    local cachedSource  = cfg.Cache and readCache(cfg) or nil
    local cachedVersion = readMarker(cfg)                   -- tag recorded last time
    local cachedBuild   = versionFromSource(cachedSource)   -- tag of the file itself

    local remoteVersion, remoteSource = nil, nil
    if not cfg.Offline then
       remoteVersion, remoteSource = resolveRemoteVersion(cfg)   -- tag published on GitHub
    end

    --  The copy on disk is current when the published version matches either the
    --  marker we stored or the build tag inside the file itself - the file's own
    --  tag is what makes the check reliable, because older loaders wrote commit
    --  hashes into the marker (which would never match a manual tag again).
    --  "version unknown" means "verify", not "up to date": that assumption used
    --  to pin a stale file on disk forever whenever the version lookup failed.
    local sameVersion = remoteVersion ~= nil
       and (remoteVersion == cachedVersion or remoteVersion == cachedBuild)
    local trustCache = cfg.Offline or (remoteVersion == nil and cfg.VerifyCache == false)
    local upToDate = cachedSource ~= nil and (trustCache or sameVersion)

    local usedCache = false
    local source = nil

    if upToDate then
       source = cachedSource
       usedCache = true
       if remoteVersion and remoteVersion ~= cachedVersion then
          --  The match came from the build tag inside the file, so keep the
          --  marker honest about what is actually on disk.
          writeMarker(cfg, cachedBuild or remoteVersion)
       end
    else
       if cachedSource and remoteVersion == nil and not cfg.Offline then
          notify("[XClient loader] the published version could not be read; verifying the cached copy against the repository.")
       end
       source = downloadFile(cfg)
       if source then
          if cfg.Cache then
             local freshBuild = versionFromSource(source)
             if remoteVersion and freshBuild and freshBuild ~= remoteVersion then
                notify(string.format(
                   "[XClient loader] version.txt says '%s' but the published file declares '%s' - run 'lua _mkversion.lua' and push both.",
                   tostring(remoteVersion), tostring(freshBuild)))
             end
             writeCache(cfg, source)
             --  Remember what we matched against: the build tag of the file when
             --  the manual marker was the source, otherwise the published value.
             writeMarker(cfg, versionToRemember(source, remoteVersion, remoteSource)
                or tostring(os and os.time and os.time() or "1"))
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
             local freshRemote, freshSource = resolveRemoteVersion(cfg)
             local freshVersion = versionToRemember(fresh, freshRemote or remoteVersion, freshSource or remoteSource)
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
    local cfg = withOptions(options)
    --  The version of the file on disk (its own build tag), falling back to the
    --  tag recorded next to it.
    return versionFromSource(readCache(cfg)) or readMarker(cfg)
end

function Loader:CheckForUpdate(options)
    local cfg = withOptions(options)
    local localVersion = versionFromSource(readCache(cfg)) or readMarker(cfg)
    local remoteVersion = resolveRemoteVersion(cfg)
    --  Same rule Load() uses: an update is due when the published version
    --  matches neither the recorded marker nor the tag inside the cached file.
    return remoteVersion, (remoteVersion ~= nil
       and remoteVersion ~= localVersion
       and remoteVersion ~= readMarker(cfg))
end

function Loader:Update(options)
    local cfg = withOptions(options)
    local source = downloadFile(cfg)
    if type(source) ~= "string" then return false end
    local ok = writeCache(cfg, source)
    local remoteVersion, remoteSource = resolveRemoteVersion(cfg)
    local version = versionToRemember(source, remoteVersion, remoteSource)
    if version then writeMarker(cfg, version) end
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