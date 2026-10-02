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
	local self = setmetatable({ props = {}, children = {}, className = className }, instanceMeta)
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

function instanceMethods.GetPropertyChangedSignal(self) return Signal.new() end
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

print("")
print(string.format("%d checks, %d failures", total, failures))
if failures > 0 then
	os.exit(1)
end
print("ALL GOOD")


