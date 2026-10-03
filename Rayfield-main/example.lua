--[[=========================================================================
	XClient Interface Suite - example script
	-------------------------------------------------------------------------
	This file doubles as a compatibility demonstration: every element below
	uses the exact option names the previous interface used (CurrentValue,
	Range, PlaceholderText, CurrentKeybind, MultipleOptions, ...), so a script
	written for the old menu keeps working after swapping only the line that
	loads the library.

	Optional extras the older interface did not have:
		Description = "..."   -- small muted line under the row title
		Settings = { ... }    -- per module settings, opened by the row's gear
		                         icon in the left flyout
		OpenKey = "K"         -- default key that shows / hides the menu
		LoadingTitle/LoadingDuration -- the boot animation of the window

	The extended widgets (PlayerWidget, Image, Crosshair, Graph, Progress,
	Stepper, Segment, Wheel, Analog, Radar, Chips) are shown further down.
=========================================================================]]

-- 1. load the library -------------------------------------------------------
local XClient = loadstring(game:HttpGet("https://raw.githubusercontent.com/your-name/XClientMenu/main/xclient.lua"))()

--  Running from the file system instead? Use:
--  local XClient = loadstring(readfile("xclient.lua"))()

--  Prefer not to re-download the whole library on every injection? loader.lua
--  caches it on disk and only checks a short version marker afterwards:
--  local XClient = loadstring(game:HttpGet(".../loader.lua"))()

--  Optional: enable the named (Lucide) icons that longer scripts pass as
--  strings, e.g. Window:CreateTab("Combat", "swords"). Grab icons.lua from
--  this repository and hand its "48px" table over once.
if typeof(isfile) == "function" and typeof(readfile) == "function" and isfile("icons.lua") then
	local ok, icons = pcall(function()
		return loadstring(readfile("icons.lua"))()["48px"]
	end)
	if ok and icons then
		XClient.Icons = icons
	end
end

-- 2. create the window ------------------------------------------------------
local Window = XClient:CreateWindow({
	Name = "XClient Example Window",
	Icon = 0,                       -- 0 = no icon, or an asset id / icon name
	LoadingTitle = "XClient Interface Suite",
	LoadingSubtitle = "by XClient",
	LoadingDuration = 1.4,          -- length of the boot animation in seconds
	Theme = "Default",              -- Neverlose / Midnight / Blood

	ConfigurationSaving = {
		Enabled = true,
		FolderName = nil,           -- custom folder for your hub/game
		FileName = "Big Hub",
	},

	Discord = {                     -- accepted for compatibility, unused
		Enabled = false,
		Invite = "noinvitelink",
		RememberJoins = true,
	},

	KeySystem = false,              -- accepted for compatibility, unused
	KeySettings = { Title = "Untitled" },

	ToggleUIKeybind = "K",          -- legacy name of OpenKey, both work
	--  OpenKey = "K",               -- the key that shows / hides the menu; the
	--                               -- player can rebind it in the settings panel
})

-- 3. tabs -------------------------------------------------------------------
local Tab = Window:CreateTab("Tab Example", 4483362458)        -- title, image
local SecondTab = Window:CreateTab("Second Tab")               -- image optional

-- 4. everything the old interface could build -------------------------------
local Section = Tab:CreateSection("Section Example")

local Button = Tab:CreateButton({
	Name = "Change theme",
	Callback = function()
		-- Window.ModifyTheme("Midnight") and Window:ModifyTheme("Midnight") are
		-- both accepted, exactly like before.
		Window.ModifyTheme("Midnight")
	end,
})

local Toggle = Tab:CreateToggle({
	Name = "Toggle Example",
	CurrentValue = false,
	Flag = "Toggle1",              -- the identifier used by configuration saving
	Description = "Extra description line (new)",
	Callback = function(Value)
		print("toggle is now", Value)
	end,
})

local Slider = Tab:CreateSlider({
	Name = "Slider Example",
	Range = { 0, 100 },
	Increment = 10,
	Suffix = "Bananas",
	CurrentValue = 40,
	Flag = "Slider1",
	Callback = function(Value)
		print("slider is now", Value)
	end,
})

local Dropdown = Tab:CreateDropdown({
	Name = "Dropdown Example",
	Options = { "Ocean", "Forest", "Desert" },
	CurrentOption = "Forest",      -- string or table; CurrentOption is always a table
	Flag = "Dropdown1",
	Callback = function(Value)
		-- Value is the table of currently selected options
		print("selected", Value[1])
	end,
})

local MultiDropdown = Tab:CreateDropdown({
	Name = "Multi dropdown",
	Options = { "Aimbot", "Silent aim", "Wall check" },
	MultipleOptions = true,        -- "Multi" does the same thing
	Flag = "Dropdown2",
	Callback = function(Value)
		print("selected", #Value, "options")
	end,
})

local Input = Tab:CreateInput({
	Name = "Input Example",
	CurrentValue = "",
	PlaceholderText = "Input Placeholder",
	Flag = "Input1",
	RemoveTextAfterFocusLost = false,
	Callback = function(Text)
		print("input is now", Text)
	end,
})

local Keybind = Tab:CreateKeybind({
	Name = "Keybind Example",
	CurrentKeybind = "Q",
	HoldToInteract = false,        -- true gives Callback(true) / Callback(false)
	Flag = "Keybind1",
	Callback = function()
		print("keybind pressed")
	end,
})

local ColorPicker = Tab:CreateColorPicker({
	Name = "Color Picker",
	Color = Color3.fromRGB(255, 255, 255),
	Flag = "ColorPicker1",
	Callback = function(Value)
		-- Value is a Color3
		print("colour is now", Value)
	end,
})

local Label = Tab:CreateLabel("Label Example")
local Warning = Tab:CreateLabel("Warning", 4483362458, Color3.fromRGB(255, 159, 49), true)

local Paragraph = Tab:CreateParagraph({
	Title = "Paragraph Example",
	Content = "Paragraph content is wrapped automatically and the row grows to fit it.",
})

local Divider = Tab:CreateDivider()

--  Every element exposes :Set(...) and keeps its state readable, e.g.
--      Toggle:Set(true)
--      Slider:Set(75)
--      Dropdown:Set("Ocean")
--      Input:Set("text")
--      Keybind:Set("F")
--      ColorPicker:Set(Color3.fromRGB(0, 255, 0))
--      XClient.Flags["Toggle1"]:Set(false)

-- 5. the new per module gear (left flyout) ----------------------------------
local CombatModule = SecondTab:CreateToggle({
	Name = "Aimbot",
	CurrentValue = false,
	Flag = "Aimbot",
	Callback = function(Value)
		print("aimbot", Value)
	end,
	--  A non empty Settings table adds a gear button on the right of the row.
	--  Pressing it slides a settings panel in from the left of the window.
	Settings = {
		{ Type = "Slider", Name = "Field of view", Range = { 10, 360 }, CurrentValue = 90, Flag = "AimbotFOV" },
		{ Type = "Toggle", Name = "Visible check", CurrentValue = true, Flag = "AimbotVisible" },
		{ Type = "Dropdown", Name = "Hitbox", Options = { "Head", "Torso", "Closest" }, CurrentOption = "Head", Flag = "AimbotHitbox" },
		{ Type = "ColorPicker", Name = "Highlight", Color = Color3.fromRGB(255, 60, 60), Flag = "AimbotColour" },
		{ Type = "Keybind", Name = "Hold key", CurrentKeybind = "C", HoldToInteract = true, Flag = "AimbotHold" },
		--  the extended widgets work in here exactly like they do on a tab
		{
			Type = "PlayerWidget",
			Name = "Skin visualisation",
			Flag = "AimbotSkin",
			Skin = { Torso = Color3.fromRGB(255, 90, 90) },
			Callback = function(region, isOn)
				print("aim part", region, isOn)   -- drive the module from the picture
			end,
		},
		{ Type = "Crosshair", Name = "FOV pad", FOV = 90, MaxFOV = 360, Flag = "AimbotFOVPad" },
		{ Type = "Chips", Name = "Bones", Options = { "Head", "Torso", "Arms" }, Flag = "AimbotBones" },
		{ Type = "Segment", Name = "Mode", Options = { "Legit", "Rage" }, CurrentOption = "Legit" },
		{ Type = "Progress", Name = "Charge", CurrentValue = 0.3, Flag = "AimbotCharge" },
		{ Type = "Image", Name = "Preview", Image = 4483362458, Flag = "AimbotPreview" },
	},
})

-- 5b. extended widgets -------------------------------------------------------
--  Every widget below keeps the same contract as the classic elements: it is
--  built on a tab, returns its settings table, supports Flag / Description /
--  Settings, and reacts the moment a variable changes.

--  interactive character: every body part is a picture *and* a variable
local Skin = SecondTab:CreatePlayerWidget({
	Name = "Skin visualisation",
	Description = "Click a body part, or drive it from code",
	Flag = "SkinPreview",
	Selected = { "Torso" },
	Skin = { Head = Color3.fromRGB(240, 200, 120) },
	Callback = function(region, isOn)
		print("skin region", region, isOn)
	end,
})
Skin.Highlight.Head = true                      -- repaints immediately
Skin.Highlight["left leg"] = true               -- aliases and spaces work
Skin.Skin.Torso = Color3.fromRGB(255, 90, 90)   -- recolour the picture
print(Skin:GetRegion("Torso"), Skin.Highlight.Torso)
Skin.Highlight.All = false                      -- clear every highlight

--  a picture with markers (skin / UI visualisation)
local Picture = SecondTab:CreateImage({
	Name = "Skin picture",
	Flag = "SkinPicture",
	Image = 4483362458,                         -- replace with your own render
	Height = 140,
	Points = { Gun = { 0.82, 0.42 } },          -- extra marker points (0 - 1)
})
Picture.Marker.Torso = true
Picture:SetMarker("Head", Color3.fromRGB(255, 90, 90))
Picture:SetTint(Color3.fromRGB(210, 225, 255))

--  crosshair / FOV pad (drag the dot inside the pad)
local Crosshair = SecondTab:CreateCrosshair({ Name = "Aim FOV", Flag = "AimFOV", FOV = 90, MaxFOV = 360 })
Crosshair:SetFOV(140)

--  live graph, progress bar and stepper
local Graph = SecondTab:CreateGraph({ Name = "Ping", Flag = "PingGraph", Max = 300, Samples = 40 })
Graph:Push(42)

local Loader = SecondTab:CreateProgress({ Name = "Charge", Flag = "Charge", Min = 0, Max = 100 })
Loader:Set(35)

local Step = SecondTab:CreateStepper({
	Name = "Delay", Flag = "Delay", Min = 0, Max = 1000, Increment = 25, Suffix = " ms",
})
Step:Set(300)

--  segments, wheel, analog stick, radar and chips
local Mode = SecondTab:CreateSegment({
	Name = "Mode", Flag = "Mode",
	Options = { "Legit", "Rage", "Auto" }, CurrentOption = "Legit",
})
Mode:Set("Rage")

local Wheel = SecondTab:CreateWheel({
	Name = "Hitbox", Flag = "Hitbox",
	Options = { "Head", "Torso", "Nearest" }, CurrentOption = "Head",
})
Wheel:Next()

local Stick = SecondTab:CreateAnalog({ Name = "Recoil control", Flag = "Recoil" })
Stick:Set(0, -0.4)

local Radar = SecondTab:CreateRadar({ Name = "Radar", Max = 24 })
Radar:Push({ X = 0.2, Y = -0.4, Color = Color3.fromRGB(255, 90, 90) })

local Bones = SecondTab:CreateChips({
	Name = "Bones", Flag = "Bones",
	Options = { "Head", "Torso", "Arms", "Legs" },
})
Bones:Set({ "Head", "Torso" })

--  switched any time, no reload needed
--  XClient:SetFont("Classic")          -- CS (default) | Classic | Mono | table
--  XClient:SetOpenKey("RightShift")    -- the default is "K"

-- 6. notifications ----------------------------------------------------------
XClient:Notify({
	Title = "XClient",
	Content = "Interface loaded. Press K to hide or show it.\n\nThe theme, the interface keybind and every saved configuration live behind the gear in the top bar.",
	Duration = 8,
})

-- 7. configuration ----------------------------------------------------------
--  The file named in ConfigurationSaving (here "Big Hub") is loaded
--  automatically shortly after CreateWindow, exactly like before. Call this
--  yourself if you prefer to control the moment.
XClient:LoadConfiguration()

