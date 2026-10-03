--=========================================================================
--  _loadertest.lua - offline test for loader.lua cache/version handling
--
--  Run:  lua _loadertest.lua [path\to\loader.lua]
--
--  Every scenario fakes the whole executor surface (readfile/writefile/isfile
--  /makefolder + game:HttpGet + HttpService), so nothing touches the network or
--  the real disk. The library itself is replaced by a marker chunk carrying an
--  'XClient.Build = "..."' line, so the test only exercises the loader's
--  decision of which source it runs and which version it records.
--
--  Covered:
--    * the manual version file (version.txt) - including that a 6 byte marker
--      is accepted at all (the shared request helper used to reject <50 bytes);
--    * the file on disk is recognised by its own build tag, so a legacy commit
--      hash in .version can no longer pin the cache;
--    * "version unknown" means verify, never "reuse the stale file";
--    * the fast path, Offline, VerifyCache = false and real offline behaviour;
--    * a published file that does not compile is never cached and never
--      replaces a working copy on disk (the broken-push case), and such a copy
--      that still matches the published tag re-downloads itself instead of
--      failing on every injection.
--=========================================================================

local LOADER = (arg and arg[1]) or "loader.lua"

local checks, failures = 0, 0
local function check(name, ok, detail)
    checks = checks + 1
    if ok then
        print("  ok   " .. name)
    else
        failures = failures + 1
        print("  FAIL " .. name .. (detail and ("  -> " .. tostring(detail)) or ""))
    end
end

--  Fake library sources. They must be longer than 50 bytes (short bodies are
--  rejected as error pages) and must contain the build tag line the loader
--  reads with versionFromSource.
local PAD = string.rep("-- padding padding padding padding\n", 3)
local function chunkSource(name, build)
    return PAD
        .. "local XClient = {}\n"
        .. string.format('XClient.Build = "%s"\n', build)
        .. string.format('return { Version = "%s", Build = "%s" }\n', name, build)
end
local CACHED = chunkSource("CACHED", "1.0.3")
local REMOTE = chunkSource("REMOTE", "1.0.4")

local function jsonStub()
    return {
        JSONDecode = function(_, body)
            local sha = type(body) == "string" and body:match('"sha"%s*:%s*"([0-9a-fA-F]+)"')
            if sha then return { { sha = sha } } end
            return {}
        end,
    }
end

--  state: cachedSource, cachedVersion, markerVersion, markerBlocked, apiBlocked,
--         rawBlocked, malformedMarker, options (table handed to Loader:Load)
local function run(state)
    local FS = {}
    local context = { files = FS, apiHits = 0, rawHits = 0, markerHits = 0, warned = {}, urls = {} }

    readfile  = function(path)
        if FS[path] == nil then error("no such file: " .. tostring(path), 0) end
        return FS[path]
    end
    writefile  = function(path, data) FS[path] = data end
    delfile    = function(path) FS[path] = nil end
    isfile     = function(path) return FS[path] ~= nil end
    isfolder   = function(path) return path == "XClient" or FS[path .. "/"] ~= nil end
    makefolder = function(path) FS[path .. "/"] = true end
    warn       = function(message) context.warned[#context.warned + 1] = tostring(message) end

    if state.cachedSource then FS["XClient/xclient.lua"] = state.cachedSource end
    if state.cachedVersion then FS["XClient/.version"] = state.cachedVersion end

    game = {
        GetService = function(_, name)
            if name == "HttpService" then return jsonStub() end
        end,
        HttpGet = function(_, url)
            if type(url) ~= "string" then return "" end
            context.urls[#context.urls + 1] = url

            --  version.txt first: its URL lives on the same raw host as the
            --  library, so it has to be matched before the download branch.
            if url:find("version.txt", 1, true) then
                context.markerHits = context.markerHits + 1
                if state.markerBlocked then return "" end
                if state.malformedMarker then return "<html>oops, not a version</html>" end
                --  Deliberately tiny: the real marker is a few bytes and must
                --  still be accepted by the loader.
                return (state.markerVersion or "1.0.4") .. "\n"
            end

            if url:find("api.github.com", 1, true) then
                context.apiHits = context.apiHits + 1
                if state.apiBlocked then return "" end
                return string.format('[{"sha":"%s"}]%s', state.remoteVersion or "aabb", string.rep(" ", 60))
            end

            context.rawHits = context.rawHits + 1
            if state.rawBlocked then return "" end
            --  rawBodies gives every download attempt its own body (the last
            --  one repeats): that is how "the first URL is broken, the next one
            --  is fine" is simulated. remoteBody replaces the good one.
            if state.rawBodies then
                return state.rawBodies[math.min(context.rawHits, #state.rawBodies)]
            end
            return state.remoteBody or REMOTE
        end,
    }

    local env = { XClientLoaderOptions = state.options }
    getgenv = function() return env end

    local chunk, compileError = loadfile(LOADER)
    if not chunk then error("cannot load " .. LOADER .. ": " .. tostring(compileError), 0) end

    local ok, loadError = pcall(chunk)
    context.ok        = ok
    context.error     = tostring(loadError or "")
    context.version   = env.XClient and env.XClient.Version or nil
    context.loader    = env.XClientLoader and env.XClientLoader.Version or nil
    context.cache     = FS["XClient/xclient.lua"]
    context.marker    = FS["XClient/.version"]
    context.warnedMsg = table.concat(context.warned, " | ")
    return context
end

local function warned(result, needle)
    return result.warnedMsg:lower():find(needle:lower(), 1, true) ~= nil
end

print(string.format("[loadertest] loader = %s", LOADER))

--=========================================================================
--  1. The manual version file drives the update (no GitHub API at all)
--=========================================================================
do
    print("\nversion.txt says 1.0.4, the file on disk is 1.0.3")
    local r = run({ cachedSource = CACHED, cachedVersion = "1.0.3", markerVersion = "1.0.4", apiBlocked = true })

    check("runs the freshly downloaded copy", r.version == "REMOTE", "ran " .. tostring(r.version))
    check("fetches the tiny marker file", r.markerHits >= 1, r.markerHits .. " marker request(s)")
    check("never asks the rate limited GitHub API", r.apiHits == 0, r.apiHits .. " API request(s)")
    check("records the new build tag", r.marker == "1.0.4", tostring(r.marker))
    check("refreshes the cached file", r.cache == REMOTE)
    check("loaded the 1.0.6 loader itself", r.loader == "1.0.6", tostring(r.loader))
end

--=========================================================================
--  2. The file on disk is identified by its own build tag
--=========================================================================
do
    print("\nno .version marker, marker file matches the build tag of the cached file")
    local r = run({ cachedSource = CACHED, markerVersion = "1.0.3", apiBlocked = true })

    check("runs the cached copy", r.version == "CACHED", "ran " .. tostring(r.version))
    check("downloads nothing", r.rawHits == 0, r.rawHits .. " download(s)")
    check("asks no API", r.apiHits == 0, r.apiHits .. " API request(s)")
end

--=========================================================================
--  3. A legacy commit-hash marker does not pin the cache
--=========================================================================
do
    print("\n.version still holds a commit hash, build tag matches")
    local r = run({ cachedSource = CACHED, cachedVersion = "9f2a1c8be4d5f607", markerVersion = "1.0.3", apiBlocked = true })

    check("runs the cached copy", r.version == "CACHED", "ran " .. tostring(r.version))
    check("downloads nothing", r.rawHits == 0, r.rawHits .. " download(s)")
end

--=========================================================================
--  4. THE REGRESSION: version unknown, file reachable, stale cache
--=========================================================================
do
    print("\nversion.txt and the API are both unreachable, the file is not")
    local r = run({ cachedSource = CACHED, cachedVersion = "1.0.3", markerBlocked = true, apiBlocked = true })

    check("verifies instead of trusting the stale cache", r.version == "REMOTE", "ran " .. tostring(r.version))
    check("refreshes the cached file", r.cache == REMOTE)
    check("explains why it verified", warned(r, "verifying the cached copy"))
    check("still loads without error", r.ok, r.error)
end

--=========================================================================
--  5. Genuinely offline: nothing reachable
--=========================================================================
do
    print("\neverything unreachable + cache present (real offline)")
    local r = run({
        cachedSource = CACHED, cachedVersion = "1.0.3",
        markerBlocked = true, apiBlocked = true, rawBlocked = true,
    })

    check("falls back to the cached copy", r.version == "CACHED", "ran " .. tostring(r.version))
    check("keeps the cached file untouched", r.cache == CACHED)
    check("does not error out", r.ok, r.error)
end

--=========================================================================
--  6. Offline = true - no network at all
--=========================================================================
do
    print("\nOffline = true")
    local r = run({ cachedSource = CACHED, cachedVersion = "1.0.3", options = { Offline = true } })

    check("runs the cached copy", r.version == "CACHED", "ran " .. tostring(r.version))
    check("never touches the network", r.markerHits + r.apiHits + r.rawHits == 0,
        r.markerHits + r.apiHits + r.rawHits .. " request(s)")
end

--=========================================================================
--  7. VerifyCache = false keeps the old behaviour available
--=========================================================================
do
    print("\nVerifyCache = false + version unreachable")
    local r = run({
        cachedSource = CACHED, cachedVersion = "1.0.3",
        markerBlocked = true, apiBlocked = true,
        options = { VerifyCache = false },
    })

    check("trusts the cached copy without asking", r.version == "CACHED", "ran " .. tostring(r.version))
    check("downloads nothing", r.rawHits == 0, r.rawHits .. " download(s)")
end

--=========================================================================
--  8. Junk answer to the marker request is never treated as a version
--=========================================================================
do
    print("\nversion.txt returns an HTML error page")
    local r = run({
        cachedSource = CACHED, cachedVersion = "1.0.3",
        malformedMarker = true, apiBlocked = true,
    })

    check("ignores it and verifies instead", r.version == "REMOTE", "ran " .. tostring(r.version))
    check("says the version could not be read", warned(r, "could not be read"))
end

--=========================================================================
--  9. Mismatch between version.txt and the published file is reported
--=========================================================================
do
    print("\nversion.txt says 1.0.9 but the published file declares 1.0.4")
    local r = run({
        cachedSource = chunkSource("CACHED", "1.0.8"), cachedVersion = "1.0.8",
        markerVersion = "1.0.9", apiBlocked = true,
    })

    check("runs the published copy", r.version == "REMOTE", "ran " .. tostring(r.version))
    check("warns that the two tags disagree", warned(r, "push both"), r.warnedMsg)
    check("stores the build tag of what it actually has", r.marker == "1.0.4", tostring(r.marker))
end

--=========================================================================
--  10. Nothing cached and nothing reachable - must fail loudly
--=========================================================================
do
    print("\nno cache + nothing reachable")
    local r = run({ markerBlocked = true, apiBlocked = true, rawBlocked = true })

    check("raises a clear error", (not r.ok) and r.error:find("could not obtain", 1, true) ~= nil, r.error)
end

--=========================================================================
--  11. Corrupt cache + version unreachable - self-heal still works
--=========================================================================
do
    print("\ncorrupt cached copy + version unreachable")
    local r = run({
        cachedSource = PAD .. "error('broken cached copy')\n",
        cachedVersion = "1.0.3", markerBlocked = true, apiBlocked = true,
    })

    check("re-downloads and runs the fresh copy", r.version == "REMOTE", "ran " .. tostring(r.version))
end

--=========================================================================
--  12. The GitHub API fallback (no version.txt published) still caches
--=========================================================================
do
    print("\nVersionFile disabled: the API hash is the version")
    local apiSha = "aabbccdd00112233"
    local r = run({ apiBlocked = false, remoteVersion = apiSha, options = { VersionFile = "" } })

    check("downloads the library", r.version == "REMOTE", "ran " .. tostring(r.version))
    check("probes the API", r.apiHits >= 1, r.apiHits .. " API request(s)")
    check("asks no marker file", r.markerHits == 0, r.markerHits .. " marker request(s)")
    check("remembers the commit hash", r.marker == apiSha, tostring(r.marker))

    local again = run({
        cachedSource = REMOTE, cachedVersion = apiSha,
        apiBlocked = false, remoteVersion = apiSha, options = { VersionFile = "" },
    })

    check("the next run reuses the cache", again.version == "REMOTE", "ran " .. tostring(again.version))
    check("and downloads nothing", again.rawHits == 0, again.rawHits .. " download(s)")
end

--=========================================================================
--  13. The marker URL really points next to the library
--=========================================================================
do
    print("\nthe first request the loader makes")
    local r = run({ markerBlocked = true, apiBlocked = true, rawBlocked = true })

    check("asks for version.txt next to File",
        table.concat(r.urls, "\n"):find(
            "raw.githubusercontent.com/geragori11/xclientnew/refs/heads/main/Rayfield-main/version.txt",
            1, true) ~= nil,
        table.concat(r.urls, "\n"))
    check("cache-busts the marker request", r.urls[1] and r.urls[1]:find("?t=", 1, true) ~= nil,
        tostring(r.urls[1]))
end

--=========================================================================
--  14. The shipped files: version.txt must match xclient.lua's build tag
--=========================================================================
do
    print("\nshipped files")
    local function readShipped(path)
        local handle = io.open(path, "rb")
        if not handle then return nil end
        local data = handle:read("*a")
        handle:close()
        return data
    end

    local library = readShipped("xclient.lua")
    local marker = readShipped("version.txt")
    local build = library and library:match('XClient%.Build%s*=%s*"([^"]+)"')

    check("xclient.lua declares a build tag", build ~= nil, tostring(build))
    check("version.txt exists", marker ~= nil)
    check("version.txt matches the build tag",
        build ~= nil and marker ~= nil and marker:gsub("%s+$", "") == build,
        string.format("version.txt=%s build=%s", tostring(marker):gsub("%s+$", ""), tostring(build)))
end

--=========================================================================
--  15. Cache = false - always fresh, nothing written to disk
--=========================================================================
do
    print("\nCache = false with a stale copy on disk")
    local r = run({
        cachedSource = CACHED, cachedVersion = "1.0.3", markerVersion = "1.0.4",
        apiBlocked = true, options = { Cache = false },
    })

    check("runs the downloaded copy", r.version == "REMOTE", "ran " .. tostring(r.version))
    check("ignores the stale file on disk", r.rawHits == 1, r.rawHits .. " download(s)")
    check("writes nothing into the cache", r.cache == CACHED)
    check("leaves the marker alone", r.marker == "1.0.3", tostring(r.marker))
end

--=========================================================================
--  16. A published file that does not compile (the broken-push case)
--=========================================================================
do
    print("\nthe published file does not compile, a working copy is on disk")
    --  Seen in the wild: the tag was pushed as a bare number ('XClient.Build =
    --  1.0.9'), so the parser reads 1.0 and then chokes on '.9'. The body is
    --  long enough and the request succeeds - only the parser knows it is junk.
    local brokenPublish = PAD
        .. "XClient.Build = 1.0.9\n"
        .. "return { Version = 'BROKEN' }\n"

    local r = run({
        cachedSource = CACHED, cachedVersion = "1.0.3",
        markerVersion = "1.0.9", apiBlocked = true,
        remoteBody = brokenPublish,
    })

    check("still runs the menu", r.ok and r.version == "CACHED", r.error)
    check("keeps the working copy on disk", r.cache == CACHED)
    check("warns that the published file does not compile",
        warned(r, "does not compile"), r.warnedMsg)
end

do
    print("\nthe published file does not compile and nothing is cached")
    local r = run({
        markerVersion = "1.0.9", apiBlocked = true,
        remoteBody = PAD .. "XClient.Build = 1.0.9\n",
    })

    check("reports the parser error instead of 'unreachable'",
        (not r.ok)
        and r.error:find("compile error", 1, true) ~= nil
        and r.error:find("could not obtain", 1, true) == nil, r.error)
end

do
    print("\nthe first URL serves a broken body, a later one works")
    local r = run({
        cachedSource = CACHED, cachedVersion = "1.0.3",
        markerVersion = "1.0.4", apiBlocked = true,
        rawBodies = { PAD .. "XClient.Build = 1.0.4\n", REMOTE },
    })

    check("skips the broken body and runs the working one",
        r.version == "REMOTE", "ran " .. tostring(r.version))
    check("caches the body that compiles", r.cache == REMOTE)
    check("tried more than one URL", r.rawHits >= 2, r.rawHits .. " download(s)")
end

do
    print("\nthe cached copy is broken but its tag matches the published one")
    --  The poisoned state: the loader had already saved the bad body, so the
    --  fast path (published tag == tag on disk) would run it forever. Failing
    --  to compile has to trigger the re-download instead.
    local poisoned = PAD
        .. 'XClient.Build = "1.0.4"\n'
        .. "local = oops\n"

    local r = run({
        cachedSource = poisoned, cachedVersion = "1.0.4",
        markerVersion = "1.0.4", apiBlocked = true,
    })

    check("re-downloads and heals", r.ok and r.version == "REMOTE", r.error)
    check("replaces the broken cache", r.cache == REMOTE)
end

print(string.format("\n%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
