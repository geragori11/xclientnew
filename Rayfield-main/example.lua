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
=========================================================================]]

-- 1. load the library -------------------------------------------------------
local XClient = loadstring(game:HttpGet("https://raw.githubusercontent.com/your-name/XClientMenu/main/xclient.lua"))()

--  Running from the file system instead? Use:
--  local XClient = loadstring(readfile("xclient.lua"))()

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

	ToggleUIKeybind = "K",          -- hide / show the interface
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
	},
})

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

