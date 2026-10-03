--[[ _leakcheck.lua ---------------------------------------------------------
	"why does the script start lagging after a while?" - measured, not guessed.

	Copy this file into an executor and run it AFTER injecting the script you
	want to inspect.  It changes nothing: every few seconds it prints how many
	live connections hang off the engine's signals, how many objects the
	garbage collector still holds, how many windows / flags the interface has
	and how big the local character is.  Read it as a trend line - the row that
	keeps growing is the leak.

	While it runs:
	  1. open and close a module's gear (Settings) ten times;
	  2. switch a big module (ESP / Fling) on and off ten times;
	  3. die and respawn three or four times;
	  4. then sit still for a minute.

	A counter that only grows while the interface is being used points at
	`xclient.lua`; one that grows on respawn, or while a game loop is running,
	points at the game script.  The classic script-side leak is a loop that is
	started on every respawn or on every toggle-on and never stopped - one
	`while task.wait(0.001) do ... end` driver hurts on its own, three of them
	hurt three times as much.

	Nothing here is needed to run XClient; it is a developer tool.  Plain Lua
	5.1 compiles it (luac -p _leakcheck.lua), but it can only run inside an
	executor, where `game`, `getgenv` and `getconnections` exist.
---------------------------------------------------------------------------]]

local CONFIG = {
	Interval = 5,   -- seconds between samples
	Samples = 12,   -- how many samples to print (12 x 5 s = one minute)
}

local Services = {}
do
	local env = (type(getgenv) == "function" and getgenv()) or _G
	for _, name in ipairs({ "UserInputService", "RunService", "Players" }) do
		local ok, service = pcall(function() return game:GetService(name) end)
		Services[name] = ok and service or nil
	end
	Services.Environment = env
end

--  #getconnections(<signal>) is the executor's view of "who is listening":
--  a signal whose count only ever grows is exactly the "lag after a while".
--  Everything is pcall'd, because executors differ in what they expose.
local function connectionCount(signal)
	if type(getconnections) ~= "function" then return nil end
	if signal == nil then return nil end
	local ok, list = pcall(getconnections, signal)
	if not ok or type(list) ~= "table" then return nil end
	return #list
end

local function collect()
	local rows = {}
	local function add(name, value)
		if value ~= nil then rows[#rows + 1] = { name = name, value = value } end
	end

	local uis = Services.UserInputService
	if uis then
		add("UIS.InputBegan", connectionCount(uis.InputBegan))
		add("UIS.InputChanged", connectionCount(uis.InputChanged))
		add("UIS.InputEnded", connectionCount(uis.InputEnded))
	end

	local run = Services.RunService
	if run then
		add("RS.RenderStepped", connectionCount(run.RenderStepped))
		add("RS.Heartbeat", connectionCount(run.Heartbeat))
		add("RS.Stepped", connectionCount(run.Stepped))
		add("RS.PreRender", connectionCount(run.PreRender))
		add("RS.PreSimulation", connectionCount(run.PreSimulation))
		add("RS.PostSimulation", connectionCount(run.PostSimulation))
	end

	local players = Services.Players
	local player = players and players.LocalPlayer
	if player then
		add("LocalPlayer.CharacterAdded", connectionCount(player.CharacterAdded))
		local ok, character = pcall(function() return player.Character end)
		character = ok and character or nil
		add("character descendants", character and #character:GetDescendants() or 0)
	end

	if type(getgc) == "function" then
		local ok, objects = pcall(getgc, true)
		if ok and type(objects) == "table" then add("getgc(true) objects", #objects) end
	end

	local ok, children = pcall(function() return workspace:GetChildren() end)
	if ok and children then add("workspace children", #children) end

	--  the interface's own bookkeeping, when it is loaded in this environment
	local xclient = Services.Environment and Services.Environment.XClient
	if type(xclient) == "table" then
		if xclient.Build ~= nil then add("XClient.Build", tostring(xclient.Build)) end
		add("XClient windows", type(xclient.Windows) == "table" and #xclient.Windows or 0)
		local flags = 0
		for _ in pairs(type(xclient.Flags) == "table" and xclient.Flags or {}) do
			flags = flags + 1
		end
		add("XClient flags", flags)
		local loader = Services.Environment and Services.Environment.XClientLoader
		if type(loader) == "table" and loader.Version ~= nil then
			add("XClientLoader.Version", tostring(loader.Version))
		end
	end

	return rows
end

print(string.format("[leakcheck] sampling every %ds, %d samples - see the header for what to do meanwhile",
	CONFIG.Interval, CONFIG.Samples))

local previous = {}
for sample = 1, CONFIG.Samples do
	local rows = collect()
	local line, grown = {}, {}
	for _, row in ipairs(rows) do
		local value = row.value
		if type(value) == "number" then
			local before = previous[row.name]
			local delta = before and (value - before) or 0
			line[#line + 1] = string.format("%s=%d", row.name, value)
			if delta > 0 then grown[#grown + 1] = string.format("%s+%d", row.name, delta) end
			previous[row.name] = value
		else
			line[#line + 1] = string.format("%s=%s", row.name, tostring(value))
		end
	end
	print(string.format("[leakcheck #%d] %s", sample, table.concat(line, "  ")))
	if #grown > 0 then
		print("             grew since the last sample: " .. table.concat(grown, ", "))
	end
	if sample < CONFIG.Samples then task.wait(CONFIG.Interval) end
end
print("[leakcheck] done - the rows that kept growing are the ones to fix")
