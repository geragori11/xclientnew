--=========================================================================
--  _mkversion.lua - keep version.txt in sync with the library's build tag
--
--  Run:  lua _mkversion.lua            write version.txt from xclient.lua
--        lua _mkversion.lua --check    only verify that both agree (exit 1 if not)
--
--  version.txt is the manual version marker loader.lua fetches instead of
--  asking the GitHub API: one tiny request, no rate limit. It must contain
--  exactly the string xclient.lua declares in its own `XClient.Build = "..."`.
--  Push version.txt together with xclient.lua.
--=========================================================================

local LIBRARY = (arg and arg[1] and not arg[1]:match("^%-%-")) or "xclient.lua"
local MARKER = "version.txt"

local function readFile(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local data = handle:read("*a")
    handle:close()
    return data
end

local source = readFile(LIBRARY)
assert(source, "cannot read " .. LIBRARY)

local build = source:match('XClient%.Build%s*=%s*"([^"]+)"')
assert(build, LIBRARY .. " has no 'XClient.Build = \"...\"' line")

local current = readFile(MARKER)
if current then current = current:gsub("%s+$", "") end

local checkOnly = arg and (arg[1] == "--check" or arg[2] == "--check") or false

if checkOnly then
    if current == build then
        print(string.format("[mkversion] OK: %s and %s both say %s", MARKER, LIBRARY, build))
        os.exit(0)
    end
    print(string.format("[mkversion] MISMATCH: %s says %s, %s declares %s",
        MARKER, tostring(current), LIBRARY, build))
    os.exit(1)
end

if current == build then
    print(string.format("[mkversion] %s is already up to date (%s)", MARKER, build))
    os.exit(0)
end

local handle = assert(io.open(MARKER, "wb"))
handle:write(build, "\n")
handle:close()

print(string.format("[mkversion] %s: %s -> %s (push it together with %s)",
    MARKER, tostring(current), build, LIBRARY))
