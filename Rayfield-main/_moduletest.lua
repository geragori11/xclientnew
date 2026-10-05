--[[ _moduletest.lua ---------------------------------------------------------
	Offline harness for the "15b. MODULE LOADER" section of xclient.lua.

	It lifts that section straight out of the library, drops it into a tiny
	environment (HTTP + file system + UI stubs) and drives every public entry
	point: LoadModule, InitModules (including the retry/skip fallback), the
	disk cache with its DJB2 integrity check, the optional bundle, the
	loading overlay wiring, ClearModuleCache and PrintModuleStats.

	Run it with:  lua _moduletest.lua
---------------------------------------------------------------------------]]

local failures, total = 0, 0
local function check(label, condition)
	total = total + 1
	if condition then
		print("  ok   " .. label)
	else
		print("  FAIL " .. label)
		failures = failures + 1
	end
end

local function readSource(path)
	local handle = assert(io.open(path, "rb"), "cannot open " .. path)
	local content = handle:read("*a")
	handle:close()
	return content
end

-- ========================================================================
--  1. UI + engine stubs the section expects from the library
-- ========================================================================
local created = {}
local function makeInstance(className, props)
	local inst = { ClassName = className, Children = {} }
	for key, value in pairs(props or {}) do inst[key] = value end
	if inst.Parent and inst.Parent.Children then
		table.insert(inst.Parent.Children, inst)
	end
	created[#created + 1] = inst
	return inst
end

newFrame = function(props) return makeInstance("Frame", props) end
newText = function(props)
	props = props or {}
	if props.Text == nil then props.Text = "" end
	return makeInstance("TextLabel", props)
end
addCorner = function(obj, radius) return makeInstance("UICorner", { Parent = obj, CornerRadius = radius }) end
tween = function(obj, _, props)
	for key, value in pairs(props or {}) do obj[key] = value end
	return obj
end
fitLabel = function(label) return label end

UDim2 = {
	fromScale = function(x, y) return { x, y } end,
	fromOffset = function(x, y) return { x, y } end,
	new = function(...) return { ... } end,
}
UDim = { new = function(...) return { ... } end }
Vector2 = { new = function(x, y) return { x, y, X = x, Y = y } end }
Color3 = { fromRGB = function(r, g, b) return { r, g, b } end }
Enum = {
	EasingStyle = { Linear = "Linear", Quad = "Quad" },
	EasingDirection = { Out = "Out" },
	TextXAlignment = { Left = "Left", Center = "Center", Right = "Right" },
	TextYAlignment = { Center = "Center" },
}
TweenInfo = { new = function(...) return { ... } end }
TweenService = { Create = function() return { Play = function() end } end }

warn = function(...) print("[warn]", ...) end
callSafe = function(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, result = pcall(fn, ...)
	if not ok then warn("[XClient] callback error: " .. tostring(result)) end
	return result
end

local delayed = {}
task = {
	spawn = function(callback, ...)
		local args = { ... }
		table.insert(delayed, function() callback(unpack(args)) end)
	end,
	delay = function(_, callback) table.insert(delayed, callback) end,
	wait = function() end,
}

currentTheme = {
	Background = Color3.fromRGB(16, 16, 18),
	Accent = Color3.fromRGB(0, 178, 255),
	Text = Color3.fromRGB(233, 233, 238),
	TextMuted = Color3.fromRGB(140, 140, 150),
	SliderTrack = Color3.fromRGB(40, 40, 47),
}
Themes = { Neverlose = currentTheme }
THEME_FONT_BOLD = "Bold"
THEME_FONT_MONO = "Mono"
WINDOW_WIDTH = 560
screenGui = makeInstance("ScreenGui", {})

XClient = { Name = "XClient", Windows = {} }

-- ========================================================================
--  2. File system stubs (an in-memory disk)
-- ========================================================================
local fs = { files = {}, folders = {} }
isfile = function(path) return fs.files[path] ~= nil end
readfile = function(path)
	if fs.files[path] == nil then error("no such file: " .. tostring(path)) end
	return fs.files[path]
end
writefile = function(path, contents) fs.files[path] = contents end
isfolder = function(path) return fs.folders[path] == true end
makefolder = function(path) fs.folders[path] = true end
delfile = function(path) fs.files[path] = nil end
listfiles = function(folder)
	local out = {}
	local prefix = folder .. "/"
	for path in pairs(fs.files) do
		if path:sub(1, #prefix) == prefix then out[#out + 1] = path end
	end
	return out
end

filesystemAvailable = function()
	return type(writefile) == "function" and type(readfile) == "function"
		and type(isfile) == "function" and type(isfolder) == "function"
		and type(makefolder) == "function"
end

ensureFolder = function(path)
	local segments = {}
	for segment in tostring(path):gmatch("[^/]+") do
		segments[#segments + 1] = segment
		local current = table.concat(segments, "/")
		if not isfolder(current) then pcall(makefolder, current) end
	end
end

-- ========================================================================
--  3. HTTP stub (the test sets `httpReply` before every call)
-- ========================================================================
local httpReply do
	local handler
	httpReply = function(url)
		if handler then return handler(url) end
		return nil
	end
	setHandler = function(fn) handler = fn end
end
game = {
	HttpGet = function(_, url)
		local body = httpReply(url)
		if body == nil then error("HTTP failure for " .. tostring(url)) end
		return body
	end,
}
-- ========================================================================
--  4. Lift the "15b. MODULE LOADER" section out of xclient.lua and run it
-- ========================================================================
local library = readSource("xclient.lua")
local lines = {}
for line in (library:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
	lines[#lines + 1] = line
end

local first, last
for index, line in ipairs(lines) do
	if line == "--  15b. MODULE LOADER" then first = index - 1 end
	if line == "return XClient" then last = index - 2 break end
end
assert(first and last, "could not locate the 15b MODULE LOADER section")
local section = table.concat(lines, "\n", first, last)

print("== 1. the section loads into the environment ==")
local chunk, compileError = loadstring(section, "@xclient-modules")
check("the section compiles (" .. tostring(compileError) .. ")", type(chunk) == "function")
local ranSection, sectionError = pcall(chunk)
check("the section runs (" .. tostring(sectionError) .. ")", ranSection == true)

check("the public tables were created", type(XClient.Modules) == "table"
	and type(XClient.ModuleOrder) == "table"
	and type(XClient.ModuleStats) == "table"
	and type(XClient.ModuleOptions) == "table")

local defaults = XClient.ModuleOptions
check("the documented option defaults are in place",
	defaults.Folder == "XClient/modules"
	and defaults.BundlePath == "XClient/modules/bundle.lua"
	and defaults.Retries == 3
	and defaults.RetryDelay == 0.6
	and defaults.FallbackRetries == 5
	and defaults.FallbackDelay == 2
	and defaults.Offline == false
	and defaults.Log == true)

check("every public entry point exists", type(XClient.SetModuleOptions) == "function"
	and type(XClient.LoadModule) == "function"
	and type(XClient.InitModules) == "function"
	and type(XClient.ListModules) == "function"
	and type(XClient.ClearModuleCache) == "function"
	and type(XClient.PrintModuleStats) == "function")

check("SetModuleOptions merges and returns the table", (function()
	XClient:SetModuleOptions({ Retries = 1, RetryDelay = 0, FallbackRetries = 3, FallbackDelay = 0, Log = false })
	return defaults.Retries == 1 and defaults.Log == false and XClient:SetModuleOptions(nil) == defaults
end)())
-- ========================================================================
--  5. The module sources served over the fake network
-- ========================================================================
local FUNCTION_MODULE = [[
	return function(XClient, Window, Options)
		LOADED_ORDER = LOADED_ORDER or {}
		table.insert(LOADED_ORDER, "Net")
		return true
	end
]]
local NAMED_MODULE = 'return { Name = "NamedMod", Init = function() NAMED_RAN = true end }'
--  `usableBody` refuses anything shorter than 50 bytes, so pad the stub.
local SIDE_MODULE = 'SIDE_EFFECT_RAN = true -- long enough to pass the length guard'
local FLAKY_MODULE = [[
	return {
		Name = "Flaky",
		Init = function()
			FLAKY_RUNS = (FLAKY_RUNS or 0) + 1
			if FLAKY_RUNS < 3 then error("boom " .. FLAKY_RUNS) end
		end,
	}
]]
local BROKEN_INIT = 'return { Name = "Broken", Init = function() error("always") end }'
local BUNDLE = [[
	return {
		BundleA = function() BUNDLE_RUNS = (BUNDLE_RUNS or 0) + 1 end,
		BundleBee = { Name = "BundleBee", Init = function() BUNDLE_RUNS = (BUNDLE_RUNS or 0) + 1 end },
	}
]]

local served, networkDown = {}, false
setHandler(function(url)
	if networkDown then return nil end
	return served[(url:gsub("[?&]t=%d+$", ""))]
end)

--  The same DJB2 the loader uses, so the fixtures can forge a valid checksum.
local function djb2(text)
	local hash = 5381
	for index = 1, #text do hash = (hash * 33 + text:byte(index)) % 4294967296 end
	return string.format("%.0f", hash)
end

local function stats()
	local s = XClient.ModuleStats
	return { Updated = s.Updated, Cached = s.Cached, Bundle = s.Bundle, Failed = s.Failed }
end

-- ========================================================================
--  6. Tests against the first loader instance
-- ========================================================================
print("== 2. LoadModule downloads, registers and caches ==")
served["https://raw/net.lua"] = FUNCTION_MODULE
local ok, info = XClient:LoadModule("https://raw/net.lua", { Name = "Net" })
check("LoadModule reports success", ok == true and type(info) == "table" and info.Name == "Net")
check("the entry point was captured", type(XClient.Modules.Net) == "table" and type(XClient.Modules.Net.fn) == "function")
check("the registration order was recorded", XClient.ModuleOrder[1] == "Net")
check("the network copy counted as an update", XClient.ModuleStats.Updated == 1)
check("the source was written to the cache", fs.files["XClient/modules/Net.lua"] == FUNCTION_MODULE)
check("a checksum file was written beside it", fs.files["XClient/modules/Net.hash"] == djb2(FUNCTION_MODULE))

print("== 3. a corrupted cache file is rejected, not trusted ==")
fs.files["XClient/modules/Net.lua"] = FUNCTION_MODULE .. "\n-- truncated by a half finished write"
networkDown = true
local before = stats()
local okCorrupt = XClient:LoadModule("https://raw/net.lua", { Name = "Net" })
check("the corrupt copy was not used", okCorrupt == false)
local _, corruptInfo = XClient:LoadModule("https://raw/net.lua", { Name = "Net" })
check("the reason mentions the download", tostring(corruptInfo.Error):find("download") ~= nil)
check("both misses were counted as failures", XClient.ModuleStats.Failed == before.Failed + 2)

print("== 4. a valid cached copy carries the load when the network is down ==")
fs.files["XClient/modules/Cached.lua"] = NAMED_MODULE
fs.files["XClient/modules/Cached.hash"] = djb2(NAMED_MODULE)
before = stats()
local okCache, infoCache = XClient:LoadModule("https://raw/cached.lua", { Name = "Cached" })
check("the cached copy loaded", okCache == true and infoCache.Source == "cache")
check("the name declared inside the module wins", infoCache.Name == "NamedMod")
check("the cached counter moved", XClient.ModuleStats.Cached == before.Cached + 1)
check("no download failure was recorded", XClient.ModuleStats.Failed == before.Failed)

print("== 5. Offline mode never touches the network ==")
XClient:SetModuleOptions({ Offline = true })
before = stats()
local okOffline = XClient:LoadModule("https://raw/missing.lua", { Name = "Missing" })
check("a module with no cache fails offline", okOffline == false)
check("the failure was counted", XClient.ModuleStats.Failed == before.Failed + 1)
XClient:SetModuleOptions({ Offline = false })
networkDown = false

print("== 6. a module that returns nothing is still a valid module ==")
served["https://raw/side.lua"] = SIDE_MODULE
SIDE_EFFECT_RAN = false
local okSide = XClient:LoadModule("https://raw/side.lua", { Name = "Side" })
check("it reported success", okSide == true)
check("its chunk ran for its side effect", SIDE_EFFECT_RAN == true)
check("it has no entry point", XClient.Modules.Side.fn == nil)

print("== 7. the URL tail gives a module its name ==")
served["https://raw/some/deep/path/mirror.lua"] = SIDE_MODULE
local okDerived = XClient:LoadModule("https://raw/some/deep/path/mirror.lua")
check("the name came from the file name", okDerived == true and XClient.Modules["mirror"] ~= nil)
print("== 8. InitModules retries a flaky module instead of giving up ==")
served["https://raw/flaky.lua"] = FLAKY_MODULE
FLAKY_RUNS = 0
XClient:SetModuleOptions({ Retries = 1, RetryDelay = 0, FallbackRetries = 3, FallbackDelay = 0 })
before = stats()
local loaded, failed = XClient:InitModules({ Root = makeInstance("Frame", {}) }, {
	Modules = { { Name = "Flaky", URL = "https://raw/flaky.lua" } },
	Loading = false,
})
check("the flaky module ended up loaded", loaded == 1 and failed == 0)
check("its Init ran three times (two failures, one success)", FLAKY_RUNS == 3)
check("the retries were not counted as failures", XClient.ModuleStats.Failed == before.Failed)

print("== 9. a module that always throws is skipped, not fatal ==")
served["https://raw/broken.lua"] = BROKEN_INIT
before = stats()
local loaded2, failed2 = XClient:InitModules({ Root = makeInstance("Frame", {}) }, {
	Modules = { { Name = "Broken", URL = "https://raw/broken.lua" } },
	Loading = false,
})
check("it is reported as failed", loaded2 == 0 and failed2 == 1)
check("the failure counter moved by one", XClient.ModuleStats.Failed == before.Failed + 1)

print("== 10. a module that cannot be downloaded is skipped ==")
before = stats()
local loaded3, failed3 = XClient:InitModules(nil, {
	Modules = { { Name = "Ghost", URL = "https://raw/ghost.lua" } },
	Loading = false,
})
check("it is reported as failed", loaded3 == 0 and failed3 == 1)
check("the run completed", XClient.ModuleStats.Failed == before.Failed + 1)

print("== 11. a bare list of URL strings works, and OnDone fires ==")
LOADED_ORDER = {}
local doneLoaded, doneFailed
local loaded4, failed4 = XClient:InitModules({ Root = makeInstance("Frame", {}) }, {
	Modules = { "https://raw/net.lua" },
	Loading = false,
	OnDone = function(l, f) doneLoaded, doneFailed = l, f end,
})
check("the URL string was loaded", loaded4 == 1 and failed4 == 0)
check("its entry point ran", LOADED_ORDER[1] == "Net")
check("OnDone received the counts", doneLoaded == 1 and doneFailed == 0)

print("== 12. ListModules reports what was registered ==")
local list = XClient:ListModules()
local byName = {}
for _, entry in ipairs(list) do byName[entry.Name] = entry end
check("the list covers every registered module", #list == #XClient.ModuleOrder)
check("entries carry Name / URL / Source", byName["Net"] ~= nil
	and byName["Net"].URL == "https://raw/net.lua"
	and byName["Net"].Source == "network")
check("a module's own Name overrides the file name", byName["NamedMod"] ~= nil and byName["Cached"] == nil)
check("cached modules say so", byName["NamedMod"] ~= nil and byName["NamedMod"].Source == "cache")

print("== 13. PrintModuleStats returns the four counters ==")
local printed = XClient:PrintModuleStats()
check("it returns the live stats table", printed == XClient.ModuleStats
	and printed.Updated == XClient.ModuleStats.Updated
	and printed.Cached == XClient.ModuleStats.Cached
	and printed.Bundle == XClient.ModuleStats.Bundle
	and printed.Failed == XClient.ModuleStats.Failed)

print("== 14. ClearModuleCache deletes the cached copies ==")
local removed = XClient:ClearModuleCache()
check("files were removed", removed > 0)
check("the module cache is gone", fs.files["XClient/modules/Net.lua"] == nil
	and fs.files["XClient/modules/Net.hash"] == nil
	and fs.files["XClient/modules/Cached.lua"] == nil)
check("the registry survived", XClient.Modules.Net ~= nil and #XClient.ModuleOrder > 0)
-- ========================================================================
--  7. A second, independent loader instance: the bundle + ModuleOrder path
-- ========================================================================
print("== 15. a second instance starts from a clean slate ==")
XClient = { Name = "XClient", Windows = {} }
fs = { files = {}, folders = {} }
local chunk2 = assert(loadstring(section, "@xclient-modules-2"))
chunk2()
check("its tables are empty", #XClient.ModuleOrder == 0
	and next(XClient.Modules) == nil
	and XClient.ModuleStats.Updated == 0 and XClient.ModuleStats.Failed == 0)
XClient:SetModuleOptions({ Retries = 1, RetryDelay = 0, FallbackRetries = 2, FallbackDelay = 0, Log = false })

print("== 16. an optional bundle registers several modules in one request ==")
served["https://raw/bundle.lua"] = BUNDLE
BUNDLE_RUNS = 0
XClient:InitModules(nil, { BundleURL = "https://raw/bundle.lua", Modules = {}, Loading = false })
check("both bundled modules were counted", XClient.ModuleStats.Bundle == 2)
check("both are registered", XClient.Modules.BundleA ~= nil
	and XClient.Modules.BundleA.source == "bundle"
	and XClient.Modules.BundleBee ~= nil
	and XClient.Modules.BundleBee.fn ~= nil)
check("the bundle file was cached", fs.files["XClient/modules/bundle.lua"] == BUNDLE
	and fs.files["XClient/modules/bundle.lua.hash"] == djb2(BUNDLE))

print("== 17. InitModules with no list runs everything registered so far ==")
local loaded5, failed5 = XClient:InitModules({ Root = makeInstance("Frame", {}) }, { Loading = false })
check("both bundled modules ran", loaded5 == 2 and failed5 == 0)
check("their entry points were invoked", BUNDLE_RUNS == 2)
check("no failures were recorded", XClient.ModuleStats.Failed == 0)

print("== 18. the loading overlay attaches to Window.Root ==")
local rootInstance = makeInstance("Frame", {})
local overlayLoaded, overlayFailed
local loaded6, failed6 = XClient:InitModules({ Root = rootInstance }, {
	Modules = {},
	Loading = true,
	OnDone = function(l, f) overlayLoaded, overlayFailed = l, f end,
})
local overlayFrame
for _, child in ipairs(rootInstance.Children) do
	if child.Name == "ModuleLoader" then overlayFrame = child end
end
check("an overlay was created inside the window root", overlayFrame ~= nil)
check("it carries a title and a progress bar", overlayFrame ~= nil and (function()
	local hasTitle, hasBar = false, false
	for _, child in ipairs(overlayFrame.Children) do
		if child.Name == "Title" then hasTitle = true end
		if child.Name == "BarTrack" then hasBar = true end
	end
	return hasTitle and hasBar
end)())
check("the run reported clean numbers", loaded6 == 0 and failed6 == 0
	and overlayLoaded == 0 and overlayFailed == 0)

print("== 19. ClearModuleCache also removes the bundle cache ==")
XClient:ClearModuleCache()
check("the bundle cache is gone", fs.files["XClient/modules/bundle.lua"] == nil
	and fs.files["XClient/modules/bundle.lua.hash"] == nil)

-- ========================================================================
--  Summary
-- ========================================================================
print("")
print(string.format("_moduletest: %d checks, %d failed", total, failures))
if failures > 0 then
	os.exit(1)
end
print("ALL MODULE LOADER CHECKS PASSED")
