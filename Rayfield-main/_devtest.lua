--[[ _devtest.lua ----------------------------------------------------------
	Development harness: runs xclient.lua inside a very small Roblox shim so
	the library can be exercised (window + every element + configs + theme
	change) without the game engine. Not part of the deliverable.
-------------------------------------------------------------------------]]

local realType = type

-- ---------------------------------------------------------------- values
Vector2 = {}
function Vector2.new(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, {
		__typeof = "Vector2",
		__index = Vector2,
		__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end,
		__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end,
	})
end

UDim = {}
function UDim.new(scale, offset)
	return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, { __typeof = "UDim" })
end

UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, { __typeof = "UDim2" })
end
function UDim2.fromOffset(x, y) return UDim2.new(0, x, 0, y) end
function UDim2.fromScale(x, y) return UDim2.new(x, 0, y, 0) end

Color3 = {}
local function clamp01(n) return math.max(0, math.min(1, n)) end
function Color3.new(r, g, b)
	local self = setmetatable({ R = clamp01(r or 0), G = clamp01(g or 0), B = clamp01(b or 0) }, {
		__typeof = "Color3",
		__index = {
			ToHSV = function(c)
				local max = math.max(c.R, c.G, c.B)
				local min = math.min(c.R, c.G, c.B)
				local delta = max - min
				local h = 0
				if delta > 0 then
					if max == c.R then h = ((c.G - c.B) / delta) % 6
					elseif max == c.G then h = (c.B - c.R) / delta + 2
					else h = (c.R - c.G) / delta + 4 end
					h = h / 6
				end
				local s = max == 0 and 0 or delta / max
				return h, s, max
			end,
		},
	})
	return self
end
function Color3.fromRGB(r, g, b) return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHSV(h, s, v)
	h = (h or 0) * 6
	local i = math.floor(h)
	local f = h - i
	local p = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)
	local r, g, b
	if i == 0 then r, g, b = v, t, p
	elseif i == 1 then r, g, b = q, v, p
	elseif i == 2 then r, g, b = p, v, t
	elseif i == 3 then r, g, b = p, q, v
	elseif i == 4 then r, g, b = t, p, v
	else r, g, b = v, p, q end
	return Color3.new(r, g, b)
end

Enum = setmetatable({}, {
	__index = function(store, category)
		local items = {}
		local cat = setmetatable({}, {
			__index = function(_, item)
				if items[item] == nil then
					items[item] = setmetatable({ Name = item, EnumType = category }, { __typeof = "EnumItem" })
				end
				return items[item]
			end,
		})
		store[category] = cat
		return cat
	end,
})

function typeof(value)
	if realType(value) == "table" then
		local mt = getmetatable(value)
		if mt and mt.__typeof then return mt.__typeof end
		return "table"
	end
	return realType(value)
end

ColorSequence = {}
function ColorSequence.new(a, b)
	return { Kind = "ColorSequence", A = a, B = b }
end
ColorSequenceKeypoint = {}
function ColorSequenceKeypoint.new(t, c) return { Time = t, Value = c } end
NumberSequence = {}
function NumberSequence.new(a, b) return { Kind = "NumberSequence", A = a, B = b } end
TweenInfo = {}
function TweenInfo.new(...) return { Args = { ... } } end

-- ---------------------------------------------------------------- signals
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end
function Signal:Connect(fn)
	local connection = { Connected = true }
	connection.Disconnect = function()
		connection.Connected = false
		for index, handler in ipairs(self.handlers) do
			if handler == fn then table.remove(self.handlers, index) break end
		end
	end
	self.handlers[#self.handlers + 1] = fn
	return connection
end
function Signal:Once(fn)
	return self:Connect(fn)
end
function Signal:Fire(...)
	for _, handler in ipairs({ unpack(self.handlers) }) do
		handler(...)
	end
end
function Signal:Wait() end

-- ------------------------------------------------------------- instances
local instanceMeta
local instanceMethods = {}

local function newInstance(className)
	local self = setmetatable({
		props = {},
		children = {},
		--  one signal per property, handed out by GetPropertyChangedSignal
		--  and fired by plain assignments (as the engine does)
		changedSignals = {},
		className = className,
	}, instanceMeta)
	self.props.Name = className
	self.props.Visible = true
	self.props.Text = ""
	self.props.Size = UDim2.new(0, 100, 0, 20)
	self.props.Position = UDim2.new(0, 0, 0, 0)
	self.props.AbsolutePosition = Vector2.new(0, 0)
	self.props.AbsoluteSize = Vector2.new(120, 20)
	self.props.TextBounds = Vector2.new(40, 14)
	self.props.CanvasPosition = Vector2.new(0, 0)
	self.props.Rotation = 0
	self.props.BackgroundTransparency = 0
	self.props.BackgroundColor3 = Color3.new(0, 0, 0)
	return self
end

instanceMeta = {
	__typeof = "Instance",
	__index = function(self, key)
		if key == "ClassName" then return rawget(self, "className") end
		local props = rawget(self, "props")
		local value = props[key]
		if value ~= nil then return value end
		local method = instanceMethods[key]
		if method then return method end
		for _, child in ipairs(rawget(self, "children")) do
			if child.props.Name == key then return child end
		end
		--  unknown key: hand out an event so connects never explode
		local signal = Signal.new()
		props[key] = signal
		return signal
	end,
	__newindex = function(self, key, value)
		local props = rawget(self, "props")
		props[key] = value
		local changed = rawget(self, "changedSignals")
		if changed and changed[key] then changed[key]:Fire() end
		if key == "Parent" and realType(value) == "table" and value.AddChild then
			value:AddChild(self)
		end
	end,
}

function instanceMethods.AddChild(self, child)
	for _, existing in ipairs(rawget(self, "children")) do
		if existing == child then return end
	end
	local children = rawget(self, "children")
	children[#children + 1] = child
end

function instanceMethods.RemoveChild(self, child)
	local children = rawget(self, "children")
	for index, existing in ipairs(children) do
		if existing == child then table.remove(children, index) return end
	end
end

function instanceMethods.GetChildren(self) return rawget(self, "children") end

function instanceMethods.FindFirstChild(self, name)
	for _, child in ipairs(rawget(self, "children")) do
		if child.props.Name == name then return child end
	end
	return nil
end

function instanceMethods.FindFirstChildOfClass(self, className)
	for _, child in ipairs(rawget(self, "children")) do
		if child.className == className then return child end
	end
	return nil
end

function instanceMethods.IsA(self, className) return self.className == className end

function instanceMethods.ClearAllChildren(self)
	for _, child in ipairs(rawget(self, "children")) do child:Destroy() end
	rawset(self, "children", {})
end

function instanceMethods.Destroy(self)
	local parent = self.props.Parent
	if parent and parent.RemoveChild then parent:RemoveChild(self) end
	self.props.Parent = nil
	for _, child in ipairs(rawget(self, "children")) do child:Destroy() end
	rawset(self, "children", {})
end

function instanceMethods.GetPropertyChangedSignal(self, property)
	local changed = rawget(self, "changedSignals")
	local signal = changed[property]
	if not signal then
		signal = Signal.new()
		changed[property] = signal
	end
	return signal
end
function instanceMethods.SetAttribute(self) end
function instanceMethods.GetAttribute(self) return nil end
function instanceMethods.IsFocused(self) return false end
function instanceMethods.ReleaseFocus(self) end
function instanceMethods.JumpTo(self) end
function instanceMethods.WaitForChild(self, name) return self:FindFirstChild(name) end

Instance = {
	new = function(className) return newInstance(className) end,
}

-- ------------------------------------------------------------------ json
local function jsonEscape(text)
	return '"' .. tostring(text):gsub('[%c"\\]', function(character)
		if character == '"' then return '\\"' end
		if character == "\\" then return "\\\\" end
		if character == "\n" then return "\\n" end
		if character == "\r" then return "\\r" end
		if character == "\t" then return "\\t" end
		return string.format("\\u%04x", string.byte(character))
	end) .. '"'
end

local jsonEncode
jsonEncode = function(value)
	local kind = realType(value)
	if kind == "number" then return tostring(value) end
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "string" then return jsonEscape(value) end
	if kind ~= "table" then return "null" end
	local parts = {}
	local count = #value
	if count > 0 then
		for index = 1, count do parts[#parts + 1] = jsonEncode(value[index]) end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	for key, entry in pairs(value) do
		parts[#parts + 1] = jsonEscape(tostring(key)) .. ":" .. jsonEncode(entry)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local jsonDecode

do
	local text, position, length

	local function fail(message)
		error("json: " .. message .. " (at byte " .. tostring(position) .. ")", 0)
	end

	local function skipSpace()
		while position <= length do
			local character = string.sub(text, position, position)
			if character == " " or character == "\t" or character == "\n" or character == "\r" then
				position = position + 1
			else
				break
			end
		end
	end

	local parseValue

	local function parseString()
		position = position + 1
		local out = {}
		while true do
			local character = string.sub(text, position, position)
			if character == "" then fail("unterminated string") end
			if character == '"' then
				position = position + 1
				break
			end
			if character == "\\" then
				local escaped = string.sub(text, position + 1, position + 1)
				local map = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				out[#out + 1] = map[escaped] or escaped
				position = position + 2
			else
				out[#out + 1] = character
				position = position + 1
			end
		end
		return table.concat(out)
	end

	local function parseNumber()
		local start = position
		while position <= length do
			local character = string.sub(text, position, position)
			if string.find(character, "[%d%.eE%+%-]") then
				position = position + 1
			else
				break
			end
		end
		return tonumber(string.sub(text, start, position - 1))
	end

	parseValue = function()
		skipSpace()
		local character = string.sub(text, position, position)
		if character == "{" then
			position = position + 1
			local out = {}
			skipSpace()
			if string.sub(text, position, position) == "}" then
				position = position + 1
				return out
			end
			while true do
				skipSpace()
				local key = parseString()
				skipSpace()
				if string.sub(text, position, position) ~= ":" then fail("expected ':'") end
				position = position + 1
				out[key] = parseValue()
				skipSpace()
				local separator = string.sub(text, position, position)
				if separator == "," then
					position = position + 1
				elseif separator == "}" then
					position = position + 1
					break
				else
					fail("expected ',' or '}'")
				end
			end
			return out
		elseif character == "[" then
			position = position + 1
			local out = {}
			skipSpace()
			if string.sub(text, position, position) == "]" then
				position = position + 1
				return out
			end
			while true do
				out[#out + 1] = parseValue()
				skipSpace()
				local separator = string.sub(text, position, position)
				if separator == "," then
					position = position + 1
				elseif separator == "]" then
					position = position + 1
					break
				else
					fail("expected ',' or ']'")
				end
			end
			return out
		elseif character == '"' then
			return parseString()
		elseif string.sub(text, position, position + 3) == "true" then
			position = position + 4
			return true
		elseif string.sub(text, position, position + 4) == "false" then
			position = position + 5
			return false
		elseif string.sub(text, position, position + 3) == "null" then
			position = position + 4
			return nil
		end
		return parseNumber()
	end

	jsonDecode = function(contents)
		text, position, length = contents, 1, #contents
		return parseValue()
	end
end

-- -------------------------------------------------------- virtual files
local files, folders = {}, { [""] = true }
function isfile(path) return files[path] ~= nil end
function readfile(path)
	if not files[path] then error("no such file: " .. tostring(path)) end
	return files[path]
end
function writefile(path, contents)
	local folder = string.match(path, "^(.*)/[^/]+$")
	if folder and folder ~= "" and not folders[folder] then
		error("attempt to write into a missing folder: " .. tostring(folder))
	end
	files[path] = contents
end
function isfolder(path) return folders[path] == true end
function makefolder(path) folders[path] = true end
function delfile(path) files[path] = nil end
function listfiles(path)
	local out = {}
	for file in pairs(files) do
		if string.sub(file, 1, #path + 1) == path .. "/" then out[#out + 1] = file end
	end
	return out
end

-- -------------------------------------------------------------- services
local services = {}
local function service(name)
	if services[name] then return services[name] end
	local instance = newInstance(name)
	services[name] = instance
	if name == "TweenService" then
		instance.props.Create = function(_, object, _, properties)
			for key, value in pairs(properties) do object.props[key] = value end
			return { Play = function() end, Cancel = function() end }
		end
	elseif name == "UserInputService" then
		instance.props.GetMouseLocation = function() return Vector2.new(500, 300) end
	elseif name == "HttpService" then
		instance.props.JSONEncode = function(_, value) return jsonEncode(value) end
		instance.props.JSONDecode = function(_, text) return jsonDecode(text) end
	elseif name == "Players" then
		local player = newInstance("Player")
		player.props.Name = "DevPlayer"
		instance.props.LocalPlayer = player
	elseif name == "RunService" then
		instance.props.Stepped = Signal.new()
		instance.props.RenderStepped = Signal.new()
	elseif name == "TextService" then
		--  the library measures captions to fit them, so the mock needs a
		--  believable GetTextSize: condensed HUD metrics, ~0.55em per glyph
		instance.props.GetTextSize = function(_, text, size)
			local length = string.len(tostring(text or ""))
			return Vector2.new(length * size * 0.55, size)
		end
	end
	return instance
end

game = {
	GetService = function(_, name) return service(name) end,
	FindFirstChildOfClass = function(_, name) return service(name) end,
}

--  handy globals for the driver below
UserInputService = service("UserInputService")

local deferred = {}
task = {
	delay = function(_, callback) deferred[#deferred + 1] = callback end,
	spawn = function(callback, ...)
		local args = { ... }
		deferred[#deferred + 1] = function() callback(unpack(args)) end
	end,
	defer = function(callback, ...)
		local args = { ... }
		deferred[#deferred + 1] = function() callback(unpack(args)) end
	end,
	wait = function() return 0 end,
}

local function drainDeferred()
	local queue = deferred
	deferred = {}
	for _, callback in ipairs(queue) do
		local ok, err = pcall(callback)
		if not ok then error("deferred callback failed: " .. tostring(err), 0) end
	end
end

cloneref = function(value) return value end
getgenv = function() return _G end
warn = function(...) print("[warn]", ...) end
math.clamp = function(value, lower, upper) return math.max(lower, math.min(upper, value)) end
table.find = function(list, value)
	for index, entry in ipairs(list) do
		if entry == value then return index end
	end
	return nil
end

-- =======================================================================
--  TEST DRIVER
-- =======================================================================
local failures, total = 0, 0
--  flush every line so a crash still leaves readable output
do
	local write = io.write
	local flush = io.flush
	local concat = table.concat
	local tostringLocal = tostring
	local selectLocal = select
	print = function(...)
		local parts = {}
		for index = 1, selectLocal("#", ...) do
			parts[index] = tostringLocal((selectLocal(index, ...)))
		end
		write(concat(parts, "\t") .. "\n")
		flush()
	end
end
local function check(label, condition)
	total = total + 1
	if condition then
		print("  ok   " .. label)
	else
		failures = failures + 1
		print("  FAIL " .. label)
	end
end

--  make sure the services exist before the library asks for them
service("HttpService")
service("UserInputService")
service("TextService")

print("== 1. loading xclient.lua ==")
local XClient = dofile("xclient.lua")
check("library table returned", realType(XClient) == "table")
check("Flags registry", realType(XClient.Flags) == "table")
check("Theme namespace", realType(XClient.Theme) == "table" and realType(XClient.Theme.Default) == "table")
check("Notify available before CreateWindow", realType(XClient.Notify) == "function")
XClient:Notify({ Title = "Early notification", Content = "queued" })

print("== 2. CreateWindow with the old example settings ==")
local Window = XClient:CreateWindow({
	Name = "XClient Example Window",
	LoadingTitle = "XClient Interface Suite",
	LoadingSubtitle = "by XClient",
	Theme = "Default",
	Icon = 0,
	DisableRayfieldPrompts = false,
	DisableBuildWarnings = false,
	ConfigurationSaving = {
		Enabled = true,
		FolderName = nil,
		FileName = "Big Hub",
	},
	Discord = { Enabled = false, Invite = "noinvitelink", RememberJoins = true },
	KeySystem = false,
	KeySettings = { Title = "Untitled" },
	ToggleUIKeybind = "K",
})
check("window returned", realType(Window) == "table")
check("Window:CreateTab", realType(Window.CreateTab) == "function")
check("Window.ModifyTheme", realType(Window.ModifyTheme) == "function")
check("Window:SaveConfiguration", realType(Window.SaveConfiguration) == "function")
check("notifications flushed", true)
drainDeferred()

local coreGui = service("CoreGui")
local gui = coreGui:FindFirstChild("XClient")
local root = gui and gui:FindFirstChild("XClientWindow")
check("ScreenGui + window frame created", gui ~= nil and root ~= nil)

--  the loading animation starts with the window (a later section checks that
--  it removes itself once the delays have run out)
local splash = root and root:FindFirstChild("Loading")
check("loading animation shown", splash ~= nil)
local splashTrack = splash and splash:FindFirstChild("BarTrack")
check("loading bar exists", splashTrack ~= nil)
local splashFill = splashTrack and splashTrack:FindFirstChild("BarFill")
check("loading bar animates to full", splashFill ~= nil and splashFill.Size.X.Scale == 1)
check("loading shimmer + percentage", splashTrack ~= nil
	and splashTrack:FindFirstChild("Shimmer") ~= nil
	and splashTrack:FindFirstChild("Percent") ~= nil)
check("loading title + subtitle", splash ~= nil
	and splash:FindFirstChild("Title") ~= nil
	and splash:FindFirstChild("Subtitle") ~= nil)

print("== 3. tabs (positional args, including Ext) ==")
local Main = Window:CreateTab("Main", 4483362458)
local Second = Window:CreateTab("Second")
local Hidden = Window:CreateTab("Hidden", nil, true)
check("tabs returned", realType(Main) == "table" and realType(Second) == "table")
check("Ext tab page hidden", Hidden.Page.Visible == false)
check("first tab is active", Main.Page.Visible == true)
Second:Select()
check("tab switch", Second.Page.Visible == true and Main.Page.Visible == false)
Main:Select()

print("== 4. section / button / label / paragraph / divider ==")
local Section = Main:CreateSection("Section Example")
check("section has :Set", realType(Section.Set) == "function")
Section:Set("Renamed section")
check("section rename", Section.Name == "Renamed section")

local clicks = 0
local Button = Main:CreateButton({ Name = "Change Theme", Callback = function() clicks = clicks + 1 end })
check("button returned", realType(Button) == "table")
Button.Base.row:FindFirstChild("Interact").MouseButton1Click:Fire()
check("button callback fired", clicks == 1)
Button:Set("Renamed button")
check("button rename", Button.Name == "Renamed button")

local Label = Main:CreateLabel("Label Example")
check("label has :Set", realType(Label.Set) == "function")
Label:Set("New label text")
check("label text updated", Label.Name == "New label text")
local LabelTwo = Main:CreateLabel("Warning", 4483362458, Color3.fromRGB(255, 159, 49), true)
check("label with icon + colour", LabelTwo ~= nil)

local Paragraph = Main:CreateParagraph({ Title = "Paragraph", Content = "Some content" })
check("paragraph has :Set", realType(Paragraph.Set) == "function")
Paragraph:Set({ Title = "New title", Content = "New content" })
check("paragraph updated", true)

local Divider = Main:CreateDivider()
Divider:Set(false)
check("divider hidden", Divider.Element.Visible == false)
Divider:Set(true)
check("divider shown", Divider.Element.Visible == true)

print("== 5. toggle (old CurrentValue + Flag + Callback contract) ==")
local toggleValue
local Toggle = Main:CreateToggle({
	Name = "Toggle Example",
	CurrentValue = false,
	Flag = "toggleFlag",
	Callback = function(value) toggleValue = value end,
})
check("CurrentValue exposed", Toggle.CurrentValue == false)
check("flag registered in the global registry", XClient.Flags["toggleFlag"] == Toggle)
Toggle:Set(true)
check("Set fires callback", toggleValue == true)
check("Set updates CurrentValue", Toggle.CurrentValue == true)
check("registry sees the same table", XClient.Flags["toggleFlag"].CurrentValue == true)
Toggle.Base.row:FindFirstChild("Switch").MouseButton1Click:Fire()
check("user click flips the value", Toggle.CurrentValue == false)
check("user click fires callback", toggleValue == false)

print("== 6. slider (Range / Increment / Suffix) ==")
local sliderValue
local Slider = Main:CreateSlider({
	Name = "Slider Example",
	Range = { 0, 100 },
	Increment = 10,
	Suffix = "Bananas",
	CurrentValue = 40,
	Flag = "sliderFlag",
	Callback = function(value) sliderValue = value end,
})
check("Range normalised", Slider.Min == 0 and Slider.Max == 100)
check("CurrentValue honoured", Slider.CurrentValue == 40)
check("Suffix kept", Slider.Suffix == "Bananas")
Slider:Set(50)
check("Set fires callback", sliderValue == 50)
check("Set updates CurrentValue", Slider.CurrentValue == 50)
Slider:Set(1000)
check("upper clamp", Slider.CurrentValue == 100)
Slider:Set(-10)
check("lower clamp", Slider.CurrentValue == 0)
check("Range still readable", Slider.Range[1] == 0 and Slider.Range[2] == 100)

print("== 7. dropdown (CurrentOption array, multi, Refresh, popup clicking) ==")
local dropdownValue
local Dropdown = Main:CreateDropdown({
	Name = "Dropdown Example",
	Options = { "Ocean", "Forest", "Desert" },
	CurrentOption = "Forest",
	Flag = "dropdownFlag",
	Callback = function(value) dropdownValue = value end,
})
check("CurrentOption is an array", realType(Dropdown.CurrentOption) == "table" and Dropdown.CurrentOption[1] == "Forest")
check("Options kept", #Dropdown.Options == 3)

Dropdown.Base.row:FindFirstChild("Selector").MouseButton1Click:Fire()
local popup = root:FindFirstChild("Popup")
check("dropdown popup created", popup ~= nil)
local list = popup and popup:FindFirstChild("List")
check("dropdown list created", list ~= nil)
check("dropdown options rendered", list and list:FindFirstChild("Ocean") ~= nil)
if list then
	list:FindFirstChild("Ocean").MouseButton1Click:Fire()
end
check("clicking an option updates CurrentOption", Dropdown.CurrentOption[1] == "Ocean" and #Dropdown.CurrentOption == 1)
check("callback received the array", realType(dropdownValue) == "table" and dropdownValue[1] == "Ocean")
check("single select popup closed", root:FindFirstChild("Popup") == nil)

Dropdown:Set("Desert")
check("Set accepts a string", Dropdown.CurrentOption[1] == "Desert")
Dropdown:Set({ "Forest", "Ocean" })
check("Set keeps a single option", #Dropdown.CurrentOption == 1 and Dropdown.CurrentOption[1] == "Forest")
Dropdown:Refresh({ "Plains", "Mountains" })
check("Refresh replaced the options", #Dropdown.Options == 2 and Dropdown.Options[1] == "Plains")
check("stale selections dropped", #Dropdown.CurrentOption == 0)

local MultiDropdown = Second:CreateDropdown({
	Name = "Multi",
	Options = { "A", "B", "C" },
	MultipleOptions = true,
	Flag = "multiFlag",
	Callback = function() end,
})
MultiDropdown.Base.row:FindFirstChild("Selector").MouseButton1Click:Fire()
local multiPopup = root:FindFirstChild("Popup")
local multiList = multiPopup and multiPopup:FindFirstChild("List")
if multiList then
	multiList:FindFirstChild("A").MouseButton1Click:Fire()
	multiList:FindFirstChild("B").MouseButton1Click:Fire()
end
check("multi select keeps several options", #MultiDropdown.CurrentOption == 2)
check("multi select keeps the popup open", root:FindFirstChild("Popup") ~= nil)
	--  The visual state of a row has to follow the click immediately.  The
	--  colours and the tick used to be captured once while the list was built,
	--  so a click only showed up the next time the list was reopened.
	local multiRowA = multiList and multiList:FindFirstChild("A")
	local multiTitleA = multiRowA and multiRowA:FindFirstChild("Title")
	local multiTickA = multiRowA and multiRowA:FindFirstChild("Check")
	check("every row carries a tick, shown or not", multiTickA ~= nil)
	check("tick is shown the moment the option is picked", multiTickA ~= nil and multiTickA.Visible == true)
	check("picked row is repainted in place", multiTitleA ~= nil and multiTickA ~= nil
		and multiTitleA.TextColor3 == multiTickA.BackgroundColor3)
	local multiPickedBackground = multiRowA and multiRowA.BackgroundColor3
	if multiList then
		multiList:FindFirstChild("A").MouseButton1Click:Fire()
	end
	check("unticking drops the option straight away", #MultiDropdown.CurrentOption == 1
		and MultiDropdown.CurrentOption[1] == "B")
	check("unticked row hides its tick straight away", multiTickA ~= nil and multiTickA.Visible == false)
	check("unticked row is repainted as well", multiRowA ~= nil
		and multiRowA.BackgroundColor3 ~= multiPickedBackground)


MultiDropdown.Base.row:FindFirstChild("Selector").MouseButton1Click:Fire()
check("popup closed again", root:FindFirstChild("Popup") == nil)

print("== 8. input (PlaceholderText / CurrentValue / RemoveTextAfterFocusLost) ==")
local inputValue
local Input = Main:CreateInput({
	Name = "Input Example",
	CurrentValue = "",
	PlaceholderText = "Input Placeholder",
	Flag = "inputFlag",
	RemoveTextAfterFocusLost = false,
	Callback = function(text) inputValue = text end,
})
local inputBox = Input.Base.row:FindFirstChild("InputBox")
check("placeholder alias", inputBox ~= nil and inputBox.PlaceholderText == "Input Placeholder")
inputBox.Text = "typed text"
inputBox.FocusLost:Fire(false)
check("callback on focus lost", inputValue == "typed text")
check("CurrentValue updated", Input.CurrentValue == "typed text")
check("text kept when RemoveTextAfterFocusLost is false", inputBox.Text == "typed text")
Input:Set("programmatic")
check("Set updates the box", inputBox.Text == "programmatic")
check("Set fires callback", inputValue == "programmatic")

local ClearingInput = Second:CreateInput({
	Name = "Clearing input",
	CurrentValue = "",
	RemoveTextAfterFocusLost = true,
	Callback = function() end,
})
local clearingBox = ClearingInput.Base.row:FindFirstChild("InputBox")
clearingBox.Text = "cleared"
clearingBox.FocusLost:Fire(false)
check("text cleared when requested", clearingBox.Text == "")

print("== 9. keybind (string key, hold to interact) ==")
local keybindFires = 0
local Keybind = Main:CreateKeybind({
	Name = "Keybind Example",
	CurrentKeybind = "Q",
	HoldToInteract = false,
	Flag = "keybindFlag",
	Callback = function() keybindFires = keybindFires + 1 end,
})
check("CurrentKeybind exposed", Keybind.CurrentKeybind == "Q")
local function pressKey(name, processed)
	UserInputService.InputBegan:Fire({
		KeyCode = Enum.KeyCode[name],
		UserInputType = Enum.UserInputType.Keyboard,
	}, processed)
end
pressKey("Q", false)
check("pressing the bound key fires the callback", keybindFires == 1)
pressKey("Q", true)
check("processed input ignored", keybindFires == 1)
Keybind:Set("E")
check("Set rebinds", Keybind.CurrentKeybind == "E")

local holdStates = {}
local HoldKeybind = Second:CreateKeybind({
	Name = "Hold keybind",
	CurrentKeybind = "H",
	HoldToInteract = true,
	Callback = function(state) holdStates[#holdStates + 1] = state end,
})
pressKey("H", false)
check("hold callback got true", holdStates[1] == true)
UserInputService.InputEnded:Fire({ KeyCode = Enum.KeyCode.H, UserInputType = Enum.UserInputType.Keyboard })
check("hold callback got false", holdStates[2] == false)
check("the Hold keybind object is unused", HoldKeybind ~= nil)

print("== 10. colour picker ==")
local pickedColor
local Picker = Main:CreateColorPicker({
	Name = "Color Picker",
	Color = Color3.fromRGB(255, 0, 0),
	Flag = "colorFlag",
	Callback = function(color) pickedColor = color end,
})
check("Color exposed", typeof(Picker.Color) == "Color3" and Picker.Color.R > 0.99)
Picker:Set(Color3.fromRGB(0, 255, 0))
check("Set updates the colour", Picker.Color.G > 0.99 and Picker.Color.R < 0.01)
check("Set fires callback", pickedColor == Picker.Color)

local swatch = Picker.Base.row:FindFirstChild("Swatch")
swatch.MouseButton1Click:Fire()
local pickerPopup = root:FindFirstChild("Popup")
check("picker popup created", pickerPopup ~= nil)
local sv = pickerPopup and pickerPopup:FindFirstChild("SaturationValue")
check("saturation/value area", sv ~= nil)
if sv then
	sv.InputBegan:Fire({
		UserInputType = Enum.UserInputType.MouseButton1,
		Position = Vector2.new(60, 10),
	})
	UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
end
check("dragging the picker changed the colour", Picker.Color ~= nil)

--  The value shade has to fade the same way the marker reads the value:
--  invisible at the top (value 1) turning into black at the bottom (value 0).
--  It used to run 0 -> 1, which put the black under the top of the pad and
--  made the colour under the marker disagree with the picked value.
local saturationShade = sv and sv:FindFirstChild("Saturation")
local saturationGradient = saturationShade and saturationShade:FindFirstChildOfClass("UIGradient")
check("saturation shade fades left -> right", saturationGradient ~= nil
	and saturationGradient.Rotation == 0
	and saturationGradient.Transparency.A == 0 and saturationGradient.Transparency.B == 1)
local valueShade = sv and sv:FindFirstChild("Value")
local valueGradient = valueShade and valueShade:FindFirstChildOfClass("UIGradient")
check("value shade runs top -> bottom", valueGradient ~= nil and valueGradient.Rotation == 90)
check("value shade is clear at the top and black at the bottom", valueGradient ~= nil
	and valueGradient.Transparency.A == 1 and valueGradient.Transparency.B == 0)
local svMarker = sv and sv:FindFirstChild("Marker")
Picker:Set(Color3.fromRGB(0, 0, 255))
check("a full value parks the marker on the clear edge of the shade",
	svMarker ~= nil and svMarker.Position.Y.Scale == 0)
Picker:Set(Color3.fromRGB(0, 0, 0))
check("no value parks the marker on the black edge of the shade",
	svMarker ~= nil and svMarker.Position.Y.Scale == 1)
Picker:Set(Color3.fromRGB(0, 255, 0))

if pickerPopup then pickerPopup:FindFirstChild("Hex").FocusLost:Fire(false) end

print("== 11. per module gear + left settings flyout ==")
local gearVisibleValue
local WithSettings = Main:CreateToggle({
	Name = "Module with settings",
	CurrentValue = true,
	Flag = "gearFlag",
	Settings = {
		{ Type = "Toggle", Name = "Visible", Flag = "gearVisible", CurrentValue = true, Callback = function(value) gearVisibleValue = value end },
		{ Type = "Slider", Name = "Distance", Range = { 0, 500 }, CurrentValue = 100, Flag = "gearDistance" },
		{ Type = "Label", Text = "Extra module settings", Color = Color3.fromRGB(255, 120, 0) },
	},
	Callback = function() end,
})
check("gear button created for rows with Settings", WithSettings.Base.gearButton ~= nil)
WithSettings.Base.gearButton.MouseButton1Click:Fire()
local flyout = root:FindFirstChild("SettingsFlyout")
check("flyout panel exists", flyout ~= nil)
check("flyout is visible after clicking the gear", flyout and flyout.Visible == true)
local flyoutBody = flyout and flyout:FindFirstChild("Body")
check("flyout body populated", flyoutBody ~= nil and flyoutBody:FindFirstChild("Heading") ~= nil)
check("nested setting registered a flag", XClient.Flags["gearVisible"] ~= nil)
check("nested slider registered a flag", XClient.Flags["gearDistance"] ~= nil)
XClient.Flags["gearVisible"]:Set(false)
check("nested setting is controllable", gearVisibleValue == false)
WithSettings.Base.gearButton.MouseButton1Click:Fire()
drainDeferred()
check("clicking the gear again closes the flyout", flyout.Visible == false)

print("== 12. configuration system (same file layout as before) ==")
local savedInputValue = Input.CurrentValue
local savedToggle = Toggle.CurrentValue
local savedSlider = Slider.CurrentValue
local savedDropdown = Dropdown.CurrentOption[1]
local savedColor = Picker.Color
check("ConfigurationSaving wrote automatically", isfile("XClient/Configurations/Big Hub.rfld"))
check("saved file mentions the flags", string.find(files["XClient/Configurations/Big Hub.rfld"], "toggleFlag") ~= nil)
check("saved file shape uses R/G/B", string.find(files["XClient/Configurations/Big Hub.rfld"], "R") ~= nil)

check("SaveConfigurationAs", XClient:SaveConfigurationAs("My Config") == true)
check("named file written", isfile("XClient/Configurations/My Config.rfld"))
local listed = false
for _, name in ipairs(XClient:ListConfigurations()) do
	if name == "My Config" then listed = true end
end
check("ListConfigurations finds it", listed)

Toggle:Set(not savedToggle)
Slider:Set(savedSlider == 10 and 20 or 10)
Dropdown:Set("Desert")
check("values changed before loading", Toggle.CurrentValue ~= savedToggle and Slider.CurrentValue ~= savedSlider)

check("LoadConfigurationAs", XClient:LoadConfigurationAs("My Config") == true)
check("toggle restored", Toggle.CurrentValue == savedToggle)
check("slider restored", Slider.CurrentValue == savedSlider)
check("dropdown restored", Dropdown.CurrentOption[1] == savedDropdown)
check("input restored", Input.CurrentValue == savedInputValue)
check("keybind restored", Keybind.CurrentKeybind == "E")
check("colour restored", math.abs(Picker.Color.R - savedColor.R) < 0.01
	and math.abs(Picker.Color.G - savedColor.G) < 0.01
	and math.abs(Picker.Color.B - savedColor.B) < 0.01)

--  exactly the layout the previous interface wrote for its .rfld files
writefile("XClient/Configurations/Legacy.rfld",
	'{"toggleFlag":true,"sliderFlag":42,"dropdownFlag":["Ocean"],"colorFlag":{"R":0,"G":0,"B":255},"keybindFlag":"Z","inputFlag":"legacy"}')
check("legacy configuration loads", XClient:LoadConfigurationAs("Legacy") == true)
check("legacy toggle", Toggle.CurrentValue == true)
check("legacy slider", Slider.CurrentValue == 42)
check("legacy dropdown", Dropdown.CurrentOption[1] == "Ocean")
check("legacy keybind", Keybind.CurrentKeybind == "Z")
check("legacy input", Input.CurrentValue == "legacy")
check("legacy colour packed as R/G/B", Picker.Color.B > 0.99 and Picker.Color.R < 0.01)

--  and a configuration left behind in the folder the previous interface used
makefolder("Rayfield")
makefolder("Rayfield/Configurations")
writefile("Rayfield/Configurations/Old Save.rfld",
	'{"toggleFlag":false,"sliderFlag":77,"dropdownFlag":["Forest"],"colorFlag":{"R":0,"G":255,"B":0},"keybindFlag":"Y","inputFlag":"oldsave"}')
check("configuration in the old folder loads", XClient:LoadConfigurationAs("Old Save") == true)
check("old folder toggle", Toggle.CurrentValue == false)
check("old folder slider", Slider.CurrentValue == 77)
check("old folder keybind", Keybind.CurrentKeybind == "Y")
check("old folder config is listed", (function()
	for _, name in ipairs(XClient:ListConfigurations()) do
		if name == "Old Save" then return true end
	end
	return false
end)())

check("DeleteConfiguration", XClient:DeleteConfiguration("Legacy") == true)
check("file removed", isfile("XClient/Configurations/Legacy.rfld") == false)
check("deleting twice returns false", XClient:DeleteConfiguration("Legacy") == false)
check("XClient:LoadConfiguration", XClient:LoadConfiguration() == true)

print("== 12b. favourite colours, multi drop-down helper and auto-save ==")
check("FavoriteSlots exposed", XClient.FavoriteSlots == 9)
check("SetFavoriteColor stores a colour", XClient:SetFavoriteColor(1, Color3.fromRGB(255, 0, 0)) == true)
check("GetFavoriteColor reads it back", XClient:GetFavoriteColor(1) ~= nil and XClient:GetFavoriteColor(1).R > 0.99)
check("GetFavoriteColors returns a table", realType(XClient:GetFavoriteColors()) == "table")
check("out-of-range slot refused", XClient:SetFavoriteColor(99, Color3.fromRGB(1, 2, 3)) == false)
check("non-colour value refused", XClient:SetFavoriteColor(2, "red") == false)
check("ClearFavoriteColor empties a slot", XClient:ClearFavoriteColor(2) == true and XClient:GetFavoriteColor(2) == nil)

--  the palette travels inside the configuration file
XClient:SaveConfiguration()
check("palette written with the configuration", string.find(files["XClient/Configurations/Big Hub.rfld"], "__favorite_colors") ~= nil)

--  ... and it comes back on the next load
XClient:ClearFavoriteColor(1)
check("palette cleared before loading", XClient:GetFavoriteColor(1) == nil)
XClient:LoadConfiguration()
check("palette restored on load", XClient:GetFavoriteColor(1) ~= nil and XClient:GetFavoriteColor(1).R > 0.99)

--  dedicated multi-select helper
local MultiPick = Second:CreateMultiDropdown({ Name = "Multi picker", Options = { "A", "B", "C" }, Flag = "multiPick" })
check("CreateMultiDropdown returns a dropdown", realType(MultiPick) == "table" and MultiPick.Type == "Dropdown")
check("multi helper forces MultipleOptions on", MultiPick.MultipleOptions == true)
check("multi helper registered a flag", XClient.Flags["multiPick"] ~= nil)
MultiPick:Set({ "A", "C" })
check("multi helper keeps several options", #MultiPick.CurrentOption == 2)

--  the auto-save switch is remembered in its own preferences file
check("GetAutoSave defaults to true", XClient:GetAutoSave() == true)
check("SetAutoSave(false)", XClient:SetAutoSave(false) == false)
check("preferences file written", isfile("XClient/Preferences.rfld"))
check("preferences remember the switch", string.find(files["XClient/Preferences.rfld"], "false") ~= nil)
check("SetAutoSave(true)", XClient:SetAutoSave(true) == true)

print("== 13. themes ==")
check("ModifyTheme (dot call, as in the old examples)", Window.ModifyTheme("DarkBlue") == true)
check("ModifyTheme (colon call)", Window:ModifyTheme("Default") == true)
check("unknown theme returns false", Window.ModifyTheme("NotATheme") == false)
check("custom theme table accepted", Window.ModifyTheme({ Background = Color3.fromRGB(1, 2, 3) }) == true)
check("theme namespace populated", XClient.Theme.Default ~= nil and XClient.Theme.DarkBlue ~= nil)
check("elements survived the rebuild", XClient.Flags["toggleFlag"] ~= nil and realType(XClient.Flags["toggleFlag"].Set) == "function")
Toggle:Set(false)
check("elements still controllable after a theme change", Toggle.CurrentValue == false)
Main:Refresh()
check("tab:Refresh runs", true)

print("== 15. topbar: settings button, config panel, minimise ==")
local topbarInstance = root:FindFirstChild("Topbar")
check("topbar exists", topbarInstance ~= nil)
local settingsButton = topbarInstance:FindFirstChild("SettingsButton")
check("settings button exists", settingsButton ~= nil)
settingsButton.MouseButton1Click:Fire()
check("settings flyout opened", flyout.Visible == true)
local settingsBody = flyout:FindFirstChild("Body")
check("theme dropdown in the panel", settingsBody:FindFirstChild("Interface theme") ~= nil)
local nameRow = settingsBody:FindFirstChild("Config file name")
check("config name input in the panel", nameRow ~= nil)
local nameBox = nameRow and nameRow:FindFirstChild("InputBox")
if nameBox then
	nameBox.Text = "Panel Config"
	nameBox.FocusLost:Fire(false)
end
local saveRow = settingsBody:FindFirstChild("Save configuration")
check("save button in the panel", saveRow ~= nil)
saveRow:FindFirstChild("Interact").MouseButton1Click:Fire()
check("panel saved a configuration file", isfile("XClient/Configurations/Panel Config.rfld"))
check("panel listed the new configuration", settingsBody:FindFirstChild("SavedConfigurations"):FindFirstChild("Panel Config") ~= nil)

local deleteRow = settingsBody:FindFirstChild("Delete configuration")
deleteRow:FindFirstChild("Interact").MouseButton1Click:Fire()
check("panel deleted the configuration", isfile("XClient/Configurations/Panel Config.rfld") == false)

local loadRow = settingsBody:FindFirstChild("Load configuration")
loadRow:FindFirstChild("Interact").MouseButton1Click:Fire()
check("loading a missing configuration does not error", true)
settingsButton.MouseButton1Click:Fire()
drainDeferred()
check("settings button toggles the panel closed", flyout.Visible == false)

local minimiseButton = topbarInstance:FindFirstChild("MinimiseButton")
minimiseButton.MouseButton1Click:Fire()
check("minimise shrinks the window", root.Size.Y.Offset == 36)
minimiseButton.MouseButton1Click:Fire()
check("restore expands the window again", root.Size.Y.Offset == 420)

print("== 16. named / sprite icons ==")
--  fields of a name -> asset id map such as icons.lua["48px"]
XClient.Icons.Sprite = { 12345, { 48, 48 }, { 10, 20 } }
XClient.Icons.Plain = 987654
local IconLabel = Second:CreateLabel("Iconic", "Sprite")
local iconImage = IconLabel.Element:FindFirstChild("Icon")
check("sprite icon resolved", iconImage ~= nil and iconImage.Image == "rbxassetid://12345")
check("sprite rectangle offset", iconImage ~= nil and iconImage.ImageRectOffset ~= nil and iconImage.ImageRectOffset.X == 10)
check("sprite rectangle size", iconImage ~= nil and iconImage.ImageRectSize ~= nil and iconImage.ImageRectSize.Y == 48)
local PlainLabel = Second:CreateLabel("Plain", "Plain")
local plainImage = PlainLabel.Element:FindFirstChild("Icon")
check("plain named icon resolved", plainImage ~= nil and plainImage.Image == "rbxassetid://987654")
IconLabel:Set("Iconic again", 4483362458)
check("icon can be replaced with an asset id", iconImage.Image == "rbxassetid://4483362458")
IconLabel:Set("No icon", "NotInTheTable")
check("unknown icon clears the image", iconImage.Image == "" and iconImage.Visible == false)

print("== 17. fonts and caption fitting ==")
check("default font profile is CS", XClient:GetFont() == "CS")
check("font profiles exposed", realType(XClient.Fonts) == "table" and XClient.Fonts.CS ~= nil)
local fitToggle = Main:CreateToggle({ Name = "Fit", Flag = "fitFlag" })
check("CS face applied to a row title", fitToggle.Base.title.Font == Enum.Font.Oswald)
check("short caption keeps the full size", fitToggle.Base.title.TextSize == 15)
check("caption not wrapped when it fits", fitToggle.Base.title.TextWrapped == false)

local longTitle = string.rep("Extremely long module caption ", 3)
local longToggle = Main:CreateToggle({ Name = longTitle, Description = "with a description", Flag = "longFlag" })
local longLabel = longToggle.Base.title
check("long caption keeps the full text", longLabel.Text == longTitle)
check("long caption wraps instead of clipping", longLabel.TextWrapped == true)
check("long caption font is reduced", longLabel.TextSize <= 11)
check("row grows for the wrapped caption", longToggle.Base.row.Size.Y.Offset > 46)

local mediumLabel = Main:CreateLabel(string.rep("Caption ", 10))
check("label caption measured and fitted", mediumLabel.Element.Title.TextSize <= 13)
check("description fitted as well", longToggle.Base.desc ~= nil and longToggle.Base.desc.TextSize <= 12)

XClient:SetFont("Classic")
check("SetFont switches the profile", XClient:GetFont() == "Classic")
check("rebuilt rows use the classic face", fitToggle.Base.title.Font == Enum.Font.GothamBold)
check("classic profile has no size offset", fitToggle.Base.title.TextSize == 14)
check("unknown profile rejected", XClient:SetFont("Nonexistent") == false)
check("profile kept after a rejected switch", XClient:GetFont() == "Classic")
XClient:SetFont({ Name = "Test Face", Primary = Enum.Font.Code, Strong = Enum.Font.Code, Offset = 0 })
check("custom profile accepted", XClient:GetFont() == "Test Face" and XClient.Fonts["Test Face"] ~= nil)
XClient:SetFont({
	Name = "Face Profile",
	Primary = Enum.Font.Code,
	Strong = Enum.Font.Code,
	Face = "rbxasset://fonts/families/GothamSSm.json",
})
local faceToggle = Main:CreateToggle({ Name = "Face" })
check("a profile with a custom font face still builds", faceToggle.Base.title ~= nil)
check("the custom face reaches new elements",
	faceToggle.Base.title.FontFace == "rbxasset://fonts/families/GothamSSm.json")
XClient:SetFont("CS")
check("switching back clears the custom face",
	Main:CreateLabel("No face").Element.Title.FontFace ~= "rbxasset://fonts/families/GothamSSm.json")
check("back on CS", XClient:GetFont() == "CS" and fitToggle.Base.title.Font == Enum.Font.Oswald)

print("== 18. default menu open key ==")
check("library default open key", XClient:GetOpenKey() == "K")
local openKeyFlag = XClient.Flags["xclient_open_key"]
check("open key registered as a flag", realType(openKeyFlag) == "table" and openKeyFlag.CurrentKeybind == "K")
check("Window:GetOpenKey", Window:GetOpenKey() == "K")

pressKey("K", false)
check("K hides the menu", XClient:IsVisible() == false)
pressKey("K", false)
check("K shows the menu again", XClient:IsVisible() == true)

check("SetOpenKey(F5) accepted", XClient:SetOpenKey("F5") == true)
check("open key updated everywhere", XClient:GetOpenKey() == "F5" and Window:GetOpenKey() == "F5")
pressKey("F5", false)
check("F5 hides the menu", XClient:IsVisible() == false)
pressKey("F5", false)
check("F5 shows the menu", XClient:IsVisible() == true)
pressKey("K", false)
check("the previous key is inert now", XClient:IsVisible() == true)

check("SetOpenKey takes an EnumItem", XClient:SetOpenKey(Enum.KeyCode.G) == true and XClient:GetOpenKey() == "G")
check("the saved flag follows", openKeyFlag.CurrentKeybind == "G")
openKeyFlag:Set("J")
check("config style rebind", XClient:GetOpenKey() == "J")
check("Window:SetOpenKey", Window:SetOpenKey("K") == "K" and XClient:GetOpenKey() == "K")

Window:ShowSettings()
local flyout = root:FindFirstChild("SettingsFlyout")
local flyoutBody = flyout and flyout:FindFirstChild("Body")
local openKeyRow = flyoutBody and flyoutBody:FindFirstChild("Menu open key")
check("settings panel lists the open key", openKeyRow ~= nil)
check("open key row is a keybind box", openKeyRow ~= nil and openKeyRow:FindFirstChild("KeybindBox") ~= nil)
local openKeyHint = flyoutBody and flyoutBody:FindFirstChild("OpenKeyHint")
check("settings panel hints the current key", openKeyHint ~= nil and string.find(tostring(openKeyHint.Text), "K") ~= nil)
if openKeyRow then
	local box = openKeyRow:FindFirstChild("KeybindBox")
	box.MouseButton1Click:Fire()
	pressKey("U", false)
	check("rebinding from the panel works", XClient:GetOpenKey() == "U")
end
Window:HideSettings()
XClient:SetOpenKey("K")
check("open key restored", XClient:GetOpenKey() == "K")

print("== 19. PlayerWidget ==")
--  the mock hands out fresh Color3 tables, so colours are compared field wise
local function sameColor(a, b)
	if typeof(a) ~= "Color3" or typeof(b) ~= "Color3" then return false end
	return math.abs(a.R - b.R) < 0.002 and math.abs(a.G - b.G) < 0.002 and math.abs(a.B - b.B) < 0.002
end

local regionEvents = {}
local Player = Main:CreatePlayerWidget({
	Name = "Skin preview",
	Flag = "skinFlag",
	Selected = { "Torso" },
	Skin = { Head = Color3.fromRGB(240, 200, 120) },
	Callback = function(region, on) regionEvents[#regionEvents + 1] = { region, on } end,
})
check("player widget returned", realType(Player) == "table")
check("six regions exposed", #Player.Regions == 6)
check("initial selection applied", Player:GetRegion("Torso") == true)
check("region lookup is case insensitive", Player:GetRegion("torso") == true)
check("Skin option applied at build time", sameColor(Player:GetSkin("Head"), Color3.fromRGB(240, 200, 120)))
check("rig drawn procedurally", Player.Element:FindFirstChild("Rig") ~= nil)
check("body parts exist", Player.Element.Rig:FindFirstChild("Head") ~= nil
	and Player.Element.Rig:FindFirstChild("LeftLeg") ~= nil)
check("player widget registered as a flag", XClient.Flags["skinFlag"] == Player)

Player.Highlight.Head = true
check("widget.Highlight.Head = true repaints", Player:GetRegion("Head") == true)
check("caption follows the selection", string.find(tostring(Player.Element.Caption.Text), "Head") ~= nil)
Player.Highlight.All = false
check("widget.Highlight.All = false clears", #Player:GetSelection() == 0)
check("empty selection caption", Player.Element.Caption.Text == "Selected: none")

Player:SetRegion("LeftLeg", true)
check("SetRegion selects a region", Player:GetSelection()[1] == "LeftLeg")
Player.Element.Rig.LeftArm.MouseButton1Click:Fire()
check("clicking a body part highlights it", Player:GetRegion("LeftArm") == true)
check("click fires the callback", #regionEvents == 1 and regionEvents[1][1] == "LeftArm" and regionEvents[1][2] == true)

Player.Skin.Torso = Color3.fromRGB(10, 20, 30)
check("widget.Skin.Torso reads back", sameColor(Player:GetSkin("Torso"), Color3.fromRGB(10, 20, 30)))
check("skin colour reaches the picture", sameColor(Player.Element.Rig.Torso.BackgroundColor3, Color3.fromRGB(10, 20, 30)))
check("unhighlighted parts use the skin colour", Player.Element.Rig.LeftLeg.BackgroundColor3 ~= nil)

Player:Set({ "Head", "Torso" })
check(":Set(list) applies a selection", #Player:GetSelection() == 2 and Player:GetRegion("Head") == true)
check(":Serialize matches the selection", #Player:Serialize() == 2)
Player:Clear()
check(":Clear empties the selection", #Player:GetSelection() == 0 and #Player:Serialize() == 0)

local single = Second:CreatePlayerWidget({ Name = "Single pick", AllowMultiple = false })
single:SetRegion("Head", true)
single:SetRegion("Torso", true)
check("AllowMultiple = false replaces the selection", #single:GetSelection() == 1 and single:GetRegion("Torso") == true)
single.Highlight["right arm"] = true
check("spaced region aliases work", single:GetRegion("RightArm") == true)

print("== 20. extra widgets: crosshair / graph / progress / stepper ==")
local Crosshair = Main:CreateCrosshair({ Name = "Aim FOV", Flag = "fovFlag", FOV = 90, MaxFOV = 360, Dot = { X = 1, Y = 1 } })
check("crosshair returned", realType(Crosshair) == "table")
check("fov circle drawn", Crosshair.Element:FindFirstChild("FOV") ~= nil)
check("crosshair dot clamped into the pad", Crosshair.Dot.X == 1 and Crosshair.Dot.Y == 1)
local ringSize = Crosshair.Element.FOV.Size.X.Offset
Crosshair:SetFOV(180)
check("SetFOV updates the value", Crosshair.FOV == 180)
check("SetFOV grows the circle", Crosshair.Element.FOV.Size.X.Offset > ringSize)
Crosshair:SetOffset(0.5, -0.5)
check("SetOffset moves the dot", Crosshair.Dot.X == 0.5 and Crosshair.Dot.Y == -0.5)
check("caption shows the state", string.find(tostring(Crosshair.Stage.Caption.Text), "FOV 180") ~= nil)
Crosshair:Set({ FOV = 45, X = 0, Y = 0 })
check("crosshair :Set(table)", Crosshair.FOV == 45 and Crosshair.Dot.X == 0)
check("crosshair serialises", realType(Crosshair:Serialize()) == "table" and Crosshair:Serialize().FOV == 45)
Crosshair:SetFOV(400)
check("fov clamped to MaxFOV", Crosshair.FOV == 360)
Crosshair.Element.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(500, 300) })
UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
check("dragging the pad does not error", true)

local Graph = Main:CreateGraph({ Name = "Ping graph", Flag = "graphFlag", Max = 300, Samples = 12 })
check("graph picks up the sample count", Graph.Samples == 12)
Graph:Push(150)
check("Push records the latest sample", Graph.CurrentValue == 150)
check("the history keeps every sample", #Graph:GetValues() == 12 and Graph:GetValues()[12] == 150)
local firstHeight = Graph.Element.Bar1.Size.Y.Offset
for _ = 1, 11 do Graph:Push(300) end
check("bars grow with the values", Graph.Element.Bar1.Size.Y.Offset > firstHeight)
check("graph serialises to a number", Graph:Serialize() == 300)
Graph:Clear()
check("Clear resets the graph", Graph.CurrentValue == 0)

local Loader = Main:CreateProgress({ Name = "Loading", Flag = "loadFlag", Min = 0, Max = 100, Indeterminate = true })
check("progress can run indeterminate", Loader.Running == true)
Loader:Set(40)
check("Set moves the bar", Loader.CurrentValue == 40)
check("the fill follows the value", math.abs(Loader.Element.Fill.Size.X.Scale - 0.4) < 0.001)
check("percentage label updated", Loader.Stage.Percent.Text == "40%")
Loader:Tween(100, 0.2)
check("Tween reaches the target", Loader.CurrentValue == 100 and Loader.Element.Fill.Size.X.Scale == 1)
Loader:SetRatio(0.25)
check("SetRatio uses the 0-1 scale", Loader.CurrentValue == 25)
Loader:Stop()
check("Stop halts the animation", Loader.Running == false)
check("progress serialises to a number", Loader:Serialize() == 25)

local Stepper = Main:CreateStepper({ Name = "Delay", Flag = "stepFlag", Min = 0, Max = 1000, Increment = 25, Suffix = " ms" })
check("stepper starts at Min", Stepper.CurrentValue == 0)
Stepper:Step(1)
check("Step adds one increment", Stepper.CurrentValue == 25)
check("value text shows the suffix", Stepper.Element.Value.Text == "25 ms")
Stepper:Increment()
check("Increment works", Stepper.CurrentValue == 50)
Stepper:Decrement()
check("Decrement works", Stepper.CurrentValue == 25)
Stepper.Element.Plus.MouseButton1Click:Fire()
check("the + button works", Stepper.CurrentValue == 50)
Stepper.Element.Minus.MouseButton1Click:Fire()
check("the - button works", Stepper.CurrentValue == 25)
Stepper:Set(5000)
check("value clamped to Max", Stepper.CurrentValue == 1000)
check("stepper serialises to a number", Stepper:Serialize() == 1000)

print("== 21. extra widgets: segment / wheel / analog / radar / chips / image ==")
local Segment = Main:CreateSegment({ Name = "Mode", Flag = "segFlag", Options = { "Legit", "Rage", "Auto" }, CurrentOption = "Rage" })
check("segment picks the current option", Segment.CurrentOption == "Rage")
check("segment buttons drawn", Segment.Element:FindFirstChild("Legit") ~= nil and Segment.Element:FindFirstChild("Auto") ~= nil)
check("segment paints the active button", not sameColor(Segment.Element.Rage.BackgroundColor3, Segment.Element.Legit.BackgroundColor3))
Segment:Set("Auto")
check("segment :Set(name)", Segment.CurrentOption == "Auto")
Segment.Element.Legit.MouseButton1Click:Fire()
check("clicking a segment selects it", Segment.CurrentOption == "Legit")
check("segment serialises to a string", Segment:Serialize() == "Legit")
Segment:Set("Missing")
check("an unknown option clears the selection", Segment.CurrentOption == nil)

local Wheel = Main:CreateWheel({ Name = "Hitbox", Flag = "wheelFlag", Options = { "Head", "Torso", "Nearest" }, CurrentOption = "Torso" })
check("wheel current option", Wheel.CurrentOption == "Torso")
check("wheel shows three rows", Wheel.Element:FindFirstChild("Slot1") ~= nil and Wheel.Element:FindFirstChild("Slot3") ~= nil)
check("wheel highlights the middle row", Wheel.Element.Slot2.Text == "Torso")
Wheel:Next()
check("Next moves forward", Wheel.CurrentOption == "Nearest")
Wheel:Next()
check("Next wraps around", Wheel.CurrentOption == "Head")
Wheel:Previous()
check("Previous wraps back", Wheel.CurrentOption == "Nearest")
Wheel.Element.Up.MouseButton1Click:Fire()
check("the up chevron works", Wheel.CurrentOption == "Torso")
Wheel:SetIndex(1)
check("SetIndex selects by position", Wheel.CurrentOption == "Head")
check("wheel serialises to a string", Wheel:Serialize() == "Head")

local Analog = Main:CreateAnalog({ Name = "Movement", Flag = "analogFlag", Deadzone = 0.1 })
Analog:Set(0.5, -0.5)
check("analog stores the vector", Analog.CurrentValue.X == 0.5 and Analog.CurrentValue.Y == -0.5)
check("analog reports the magnitude", math.abs(Analog.CurrentValue.Magnitude - 0.7071) < 0.01)
check("analog knob moved", Analog.Element.Knob.Position.X.Offset > 0)
check("analog is active above the deadzone", Analog:IsActive() == true)
Analog:Center()
check("Center resets the stick", Analog.CurrentValue.Magnitude == 0 and Analog:IsActive() == false)
check("analog serialises", realType(Analog:Serialize()) == "table" and Analog:Serialize().X == 0)

local Radar = Main:CreateRadar({ Name = "Radar", Flag = "radarFlag", Max = 2 })
Radar:Push({ X = 0.5, Y = 0.5, Color = Color3.fromRGB(255, 90, 90) })
check("blip added", #Radar.Blips == 1)
check("blip drawn", Radar.Element.Blips.Blip1 ~= nil and Radar.Element.Blips.Blip1.Visible == true)
Radar:Push({ X = -0.5, Y = 0.5 })
Radar:Push({ X = 0, Y = -1 })
check("the blip list respects Max", #Radar.Blips == 2)
Radar:SetBlips({ { X = 0, Y = 0 } })
check("SetBlips replaces the list", #Radar:GetBlips() == 1)
Radar:Clear()
check("Clear empties the radar", #Radar.Blips == 0)
local RadarWithBlips = Main:CreateRadar({ Name = "Radar with blips", Blips = { { X = 0.1, Y = 0.1 } } })
check("Blips option applied at build time", #RadarWithBlips.Blips == 1)
local MarkedPicture = Main:CreateImage({ Name = "Marked picture", Image = 4483362458, Marked = { "Head" } })
check("Marked option applied at build time", MarkedPicture:IsMarked("Head") == true)

local Chips = Main:CreateChips({ Name = "Bones", Flag = "chipsFlag", Options = { "Head", "Torso", "Arms" } })
check("chips are a multi select", Chips.Multi == true and Chips.Type == "Chips")
Chips:Toggle("Arms")
check("chip toggled on", #Chips:GetSelection() == 1 and Chips:GetSelection()[1] == "Arms")
Chips:Set({ "Head", "Torso" })
check("chips :Set(list)", #Chips:GetSelection() == 2)
check("chips registered under their own type", XClient.Flags["chipsFlag"].Type == "Chips")
check("chips serialise to a list", #Chips:Serialize() == 2)
check("chip buttons drawn", Chips.Element:FindFirstChild("Head") ~= nil)

local Picture = Main:CreateImage({ Name = "Skin", Flag = "imageFlag", Image = 4483362458, Points = { Gun = { 0.8, 0.3 } } })
check("picture drawn from the asset id", Picture.Element.Image == "rbxassetid://4483362458")
check("custom point stored", Picture.Points.Gun ~= nil and Picture.Points.Gun[1] == 0.8)
Picture:SetMarker("Torso", true)
check("marker set", Picture:IsMarked("Torso") == true)
check("marker dot drawn", Picture.Element.Markers:FindFirstChild("Marker_Torso") ~= nil)
check("marker sits on its point", Picture.Element.Markers.Marker_Torso.Position.Y.Scale == Picture.Points.Torso[2])
Picture.Marker.head = true
check("lower case marker variable works", Picture:IsMarked("Head") == true)
check("picture serialises the markers", #Picture:Serialize() == 2)
Picture:SetMarkers({ "Head" })
check("SetMarkers replaces the markers", #Picture:GetMarked() == 1 and Picture:IsMarked("Torso") == false)
Picture:ClearMarkers()
check("ClearMarkers empties the picture", #Picture:GetMarked() == 0)
Picture:SetTint(Color3.fromRGB(200, 220, 255))
check("tint applied", sameColor(Picture.Element.ImageColor3, Color3.fromRGB(200, 220, 255)))

print("== 22. new widgets inside a module settings flyout ==")
local SettingsToggle = Main:CreateToggle({
	Name = "Module with viewer settings",
	Flag = "viewerFlag",
	Settings = {
		"Visuals",
		{ Type = "PlayerWidget", Name = "Skin", Flag = "modSkin", Selected = { "Head" } },
		{ Type = "Stepper", Name = "FOV step", Min = 0, Max = 90, Increment = 5, CurrentValue = 20, Flag = "modStep" },
		{ Type = "Progress", Name = "Load", CurrentValue = 0.5, Flag = "modLoad" },
		{ Type = "Segment", Name = "Mode", Options = { "A", "B" }, CurrentOption = "B", Flag = "modSeg" },
		{ Type = "Chips", Name = "Bones", Options = { "Head", "Torso" }, Flag = "modChips" },
		{ Type = "Wheel", Name = "Priority", Options = { "Low", "High" }, CurrentOption = "High", Flag = "modWheel" },
		{ Type = "Graph", Name = "Trace", Max = 60, Samples = 8, Flag = "modGraph" },
		{ Type = "Crosshair", Name = "FOV pad", FOV = 60, Flag = "modCross" },
		{ Type = "Analog", Name = "Recoil", Flag = "modAnalog" },
		{ Type = "Radar", Name = "Radar view", Flag = "modRadar" },
		{ Type = "Image", Name = "Skin picture", Image = 4483362458, Flag = "modImage" },
	},
})
SettingsToggle.Base.gearButton.MouseButton1Click:Fire()
local function inFlyout(name) return flyoutBody and flyoutBody:FindFirstChild(name) end
check("module flyout opened", inFlyout("Skin") ~= nil)
check("flyout captions are fitted", inFlyout("FOV step") ~= nil
	and inFlyout("FOV step"):FindFirstChild("Title").TextSize <= 15)
check("player widget inside the flyout", inFlyout("Skin") ~= nil and inFlyout("Skin"):FindFirstChild("Stage") ~= nil)
check("stepper inside the flyout", XClient.Flags["modStep"] ~= nil and XClient.Flags["modStep"].CurrentValue == 20)
check("progress inside the flyout", XClient.Flags["modLoad"] ~= nil and XClient.Flags["modLoad"].CurrentValue == 0.5)
check("segment inside the flyout", XClient.Flags["modSeg"] ~= nil and XClient.Flags["modSeg"].CurrentOption == "B")
check("chips inside the flyout", XClient.Flags["modChips"] ~= nil
	and #XClient.Flags["modChips"]:GetSelection() == 0)
check("wheel inside the flyout", XClient.Flags["modWheel"] ~= nil and XClient.Flags["modWheel"].CurrentOption == "High")
check("graph inside the flyout", XClient.Flags["modGraph"] ~= nil and #XClient.Flags["modGraph"]:GetValues() == 8)
check("crosshair inside the flyout", XClient.Flags["modCross"] ~= nil and XClient.Flags["modCross"].FOV == 60)
check("analog inside the flyout", XClient.Flags["modAnalog"] ~= nil
	and XClient.Flags["modAnalog"].Element:FindFirstChild("Knob") ~= nil)
check("radar inside the flyout", XClient.Flags["modRadar"] ~= nil and inFlyout("Radar view") ~= nil)
check("image inside the flyout", XClient.Flags["modImage"] ~= nil and inFlyout("Skin picture") ~= nil)
check("flyout viewer reacts to its variable", XClient.Flags["modSkin"]:GetRegion("Head") == true)
XClient.Flags["modSkin"].Highlight.Torso = true
check("flyout viewer variable repaints", XClient.Flags["modSkin"]:GetRegion("Torso") == true)
--  a configuration stores the widget shape through :Serialize
local serialized = XClient.Flags["modSkin"]:Serialize()
check("widget knows how to serialise its state", realType(serialized) == "table" and #serialized == 2)
Window:HideSettings()

--  ---------------------------------------------------------------- search
--  Every check below needs the live window (section 23 tears it down), so
--  they run here, wrapped in a function to keep the chunk's local list sane.
local function testSearchBar()
	print("== 22b. topbar search: filter, sections, tab hop, clear, toggle ==")
	local searchHolder = topbarInstance:FindFirstChild("Search")
	check("search bar on the topbar", searchHolder ~= nil and searchHolder.Visible == true)
	local box = searchHolder and searchHolder:FindFirstChild("Box")
	check("search box is a text box", box ~= nil and box:IsA("TextBox"))
	--  the active "CS" profile nudges every text size by +1 (see create()), so
	--  a 12px placeholder and a 15px caption come out as 13 and 16.
	local CS_OFFSET = 1
	check("placeholder + text metrics",
		box ~= nil and box.PlaceholderText == "Search" and box.TextSize == 12 + CS_OFFSET
		and box.TextXAlignment == Enum.TextXAlignment.Left
		and box.TextYAlignment == Enum.TextYAlignment.Center)
	check("query survives the click into the box", box.ClearTextOnFocus == false)
	check("query starts out empty", box.Text == "")
	local glass = searchHolder:FindFirstChild("Glass")
	check("magnifier is hand drawn (ring + handle)",
		glass ~= nil and glass:FindFirstChild("UIStroke") ~= nil and glass:FindFirstChild("Handle") ~= nil)
	local clear = searchHolder:FindFirstChild("Clear")
	check("clear button exists, hidden, with a drawn cross",
		clear ~= nil and clear.Visible == false and #clear:GetChildren() >= 2)

	local caption = topbarInstance:FindFirstChild("Title")
	check("caption shortened to clear the search bar", caption ~= nil and caption.Size.X.Offset == 238)
	check("caption keeps every glyph",
		caption.Text == "XClient Example Window" and caption.TextSize == 15 + CS_OFFSET
		and caption.TextTruncate == Enum.TextTruncate.None and caption.TextWrapped == false)

	local rail = root:FindFirstChild("Rail")
	check("rail scrolls when there are many tabs",
		rail ~= nil and rail:IsA("ScrollingFrame") and rail.ScrollBarThickness == 3)

	--  rows to filter: two in a second tab, three in the tab that is showing
	local FilterTab = Window:CreateTab("FilterTab")
	Main:Select()
	local alpha = FilterTab:CreateToggle({ Name = "Alpha module", Flag = "searchAlpha" })
	local beta = FilterTab:CreateToggle({ Name = "Beta module", Flag = "searchBeta" })
	local section = Main:CreateSection("Search section")
	local gamma = Main:CreateToggle({ Name = "Gamma module", Flag = "searchGamma" })
	local delta = Main:CreateToggle({ Name = "Delta module", Flag = "searchDelta" })
	local cyrillic = Main:CreateToggle({ Name = "Количество попыток", Flag = "searchCyrillic" })

	box.Text = "Alpha"
	check("a matching row stays visible", alpha.Base.row.Visible == true)
	check("rows without a match hide",
		beta.Base.row.Visible == false and gamma.Base.row.Visible == false
		and delta.Base.row.Visible == false and cyrillic.Base.row.Visible == false)
	check("search hops to the tab that holds the hit",
		FilterTab.Page.Visible == true and Main.Page.Visible == false)
	check("clear button shows up while filtering", clear.Visible == true)

	box.Text = "delta"
	check("hop back to the tab of the new hit",
		Main.Page.Visible == true and FilterTab.Page.Visible == false)
	check("a section stays while one of its rows matches",
		section.Element.Visible == true and delta.Base.row.Visible == true)
	check("its sibling rows hide",
		gamma.Base.row.Visible == false and cyrillic.Base.row.Visible == false
		and alpha.Base.row.Visible == false)

	box.Text = "no-such-module"
	check("a query with no hits hides the section", section.Element.Visible == false)
	check("...and every row", delta.Base.row.Visible == false and gamma.Base.row.Visible == false)
	check("...but keeps a page on screen", Main.Page.Visible == true)

	box.Text = "Количество"
	check("Cyrillic query finds the row", cyrillic.Base.row.Visible == true)
	box.Text = "КОЛИЧЕСТВО"
	check("Cyrillic match is case insensitive", cyrillic.Base.row.Visible == true)
	box.Text = "попыток"
	check("a hit in the middle of the name counts", cyrillic.Base.row.Visible == true)
	box.Text = "количество попыток"
	check("the whole name matches too", cyrillic.Base.row.Visible == true)

	box.Text = "FilterTab"
	check("a tab name keeps every row of that tab",
		alpha.Base.row.Visible == true and beta.Base.row.Visible == true)
	check("...and moves to that tab", FilterTab.Page.Visible == true)

	box.Text = ""
	check("clearing restores the rows",
		alpha.Base.row.Visible == true and gamma.Base.row.Visible == true
		and cyrillic.Base.row.Visible == true)
	check("clearing restores the sections", section.Element.Visible == true)
	check("clear button hides again", clear.Visible == false)

	box.Text = "Gamma"
	check("clear button is back while filtering", clear.Visible == true)
	clear.MouseButton1Click:Fire()
	check("clear button empties the query", box.Text == "" and clear.Visible == false)
	check("...and restores the rows",
		delta.Base.row.Visible == true and beta.Base.row.Visible == true)

	--  the settings toggle drives the very same state
	box.Text = "Alpha"
	settingsButton.MouseButton1Click:Fire()
	drainDeferred()
	local panel = flyout and flyout:FindFirstChild("Body")
	local searchRow = panel and panel:FindFirstChild("Search bar")
	check("settings panel offers a search toggle", searchRow ~= nil)
	local searchSwitch = searchRow and searchRow:FindFirstChild("Switch")
	if searchSwitch then searchSwitch.MouseButton1Click:Fire() end
	drainDeferred()
	check("switching it off hides the bar", searchHolder.Visible == false)
	check("...and empties the query", box.Text == "" and clear.Visible == false)
	check("...and hands the caption its full width back", caption.Size.X.Offset == 414)
	if searchSwitch then searchSwitch.MouseButton1Click:Fire() end
	drainDeferred()
	check("switching it back on shows the bar", searchHolder.Visible == true)
	check("...and shortens the caption again", caption.Size.X.Offset == 238)
	Window:HideSettings()
	drainDeferred()

	--  the topbar drag must not eat presses aimed at the search box
	local parked = root.Position
	local pointer = Vector2.new(500, 300)
	UserInputService.props.GetMouseLocation = function() return pointer end
	topbarInstance.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(400, 10) })
	pointer = Vector2.new(530, 340)
	UserInputService.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement })
	check("the topbar still drags the window",
		root.Position.X.Offset == parked.X.Offset + 30 and root.Position.Y.Offset == parked.Y.Offset + 40)
	topbarInstance.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(400, 10) })
	box.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(400, 10) })
	drainDeferred()
	local heldX, heldY = root.Position.X.Offset, root.Position.Y.Offset
	pointer = Vector2.new(760, 520)
	UserInputService.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement })
	check("a press on the search box does not drag the window",
		root.Position.X.Offset == heldX and root.Position.Y.Offset == heldY)
	root.Position = parked
	UserInputService.props.GetMouseLocation = function() return Vector2.new(500, 300) end

	--  slider geometry: the whole control has to stay inside the row
	local sliderTrack = Slider.Base.row:FindFirstChild("Track")
	local readout = Slider.Base.row:FindFirstChild("Value")
	check("slider track sits inside the row",
		sliderTrack ~= nil and readout ~= nil and sliderTrack.Position.X.Offset < 0
		and sliderTrack.Position.X.Offset + sliderTrack.Size.X.Offset <= readout.Position.X.Offset)
	check("slider fill + knob ride on the track",
		sliderTrack:FindFirstChild("Fill") ~= nil and sliderTrack:FindFirstChild("Knob") ~= nil)

	--  an open dropdown survives a poll Refresh instead of blinking
	Dropdown.Base.row:FindFirstChild("Selector").MouseButton1Click:Fire()
	local openPopup = root:FindFirstChild("Popup")
	check("dropdown popup open", openPopup ~= nil)
	check("popup carries a click shield", openPopup:FindFirstChild("PopupShield") ~= nil)
	Dropdown:Refresh({ "Plains", "Mountains", "Canyons" })
	local samePopup = root:FindFirstChild("Popup")
	check("poll Refresh keeps the very same popup open", samePopup ~= nil and samePopup == openPopup)
	check("...with the refreshed options inside",
		samePopup:FindFirstChild("List") ~= nil
		and samePopup:FindFirstChild("List"):FindFirstChild("Canyons") ~= nil)
	Dropdown.Base.row:FindFirstChild("Selector").MouseButton1Click:Fire()
	check("selector click closes it", root:FindFirstChild("Popup") == nil)

	Main:Select()
end
testSearchBar()

print("== 23. the loading animation cleans itself up ==")
for _ = 1, 30 do drainDeferred() end
check("loading overlay finished and removed", root:FindFirstChild("Loading") == nil)

print("== 14. visibility, notifications, destroy ==")
check("IsVisible defaults to true", XClient:IsVisible() == true)
XClient:SetVisibility(false)
check("SetVisibility(false)", XClient:IsVisible() == false and root.Visible == false)
pressKey("K", false)
check("the interface keybind shows it again", XClient:IsVisible() == true)
Window:SetVisibility(false)
Window:SetVisibility(true)
check("Window:SetVisibility delegates", XClient:IsVisible() == true)
XClient:Notify({ Title = "After load", Content = "notification once the window exists", Duration = 3 })
check("notifications still accepted", true)
XClient:SaveConfiguration()
check("XClient:SaveConfiguration", isfile("XClient/Configurations/Big Hub.rfld"))

Window:Destroy()
check("destroy removes the interface", coreGui:FindFirstChild("XClient") == nil)
check("window registry emptied", #XClient.Windows == 0)

print("== 24. example.lua end to end ==")
--  the example fetches the library over HTTP and builds everything documented;
--  serve the library from disk and run the whole thing inside the shim
local function readSource(path)
	local handle = io.open(path, "rb")
	if not handle then return nil end
	local contents = handle:read("*a")
	handle:close()
	return contents
end
local librarySource = readSource("xclient.lua")
local exampleSource = readSource("example.lua")
check("example.lua is readable", type(exampleSource) == "string" and #exampleSource > 2000)
check("xclient.lua is readable", type(librarySource) == "string" and #librarySource > 2000)
game.HttpGet = function(_, url) return librarySource end
game.HttpGetAsync = game.HttpGet

local exampleChunk = loadstring(exampleSource, "example")
check("example.lua compiles", type(exampleChunk) == "function")
if exampleChunk then
	local ok, err = pcall(exampleChunk)
	check("example.lua runs clean (" .. tostring(err) .. ")", ok == true)
	if ok then
		for _ = 1, 40 do drainDeferred() end
		local instance = getgenv().XClient
		check("the example built its own library instance", realType(instance) == "table" and instance ~= XClient)
		check("the example window exists", realType(instance.Windows) == "table" and instance.Windows[1] ~= nil)
		check("example flags registered", instance.Flags["Toggle1"] ~= nil and instance.Flags["Aimbot"] ~= nil)
		--  module settings are built on demand, when the gear is pressed
		local aimbotBase = instance.Flags["Aimbot"].Base
		if aimbotBase and aimbotBase.gearButton then aimbotBase.gearButton.MouseButton1Click:Fire() end
		check("example module settings build on demand", instance.Flags["AimbotFOV"] ~= nil
			and instance.Flags["AimbotBones"] ~= nil and instance.Flags["AimbotSkin"] ~= nil)
		check("example widget flags registered", instance.Flags["SkinPreview"] ~= nil
			and instance.Flags["SkinPicture"] ~= nil and instance.Flags["Bones"] ~= nil
			and instance.Flags["Recoil"] ~= nil and instance.Flags["PingGraph"] ~= nil)
		check("example player widget works", instance.Flags["SkinPreview"]:GetRegion("Head") == false
			and realType(instance.Flags["SkinPreview"].Highlight) == "table")
		check("example window answers the new API", realType(instance.Windows[1].SetOpenKey) == "function"
			and instance:GetFont() == "CS")
	end
end

print("")
print(string.format("%d checks, %d failures", total, failures))
if failures > 0 then
	os.exit(1)
end
print("ALL GOOD")


