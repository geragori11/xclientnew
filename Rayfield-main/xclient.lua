--[[=========================================================================
	XClient Interface Suite
	Neverlose-style user interface library for Roblox
	-----------------------------------------------------------------------
	Highlights
		* Full custom / self-contained UI (no external Roblox asset needed)
		* Dark "Neverlose" theme with a left tab rail, three palettes and the
		  palette names used by the previous interface
		* Every module row can expose a gear button on the right; pressing it
		  slides a settings flyout in from the LEFT of the window
		* Built-in configuration system (save / load / delete / list / autoload)
		  with an in-window configuration panel behind the topbar gear
		* Procedural gear icon, procedural colour picker, no remote assets

	Compatibility
		The public API is a drop-in match for the interface this project used
		to ship: same Window:CreateTab / Tab:Create* names, same option names
		(CurrentValue, Range, PlaceholderText, CurrentKeybind, MultipleOptions,
		...), the same returned settings tables with :Set(), the same
		XClient.Flags registry and the same .rfld configuration files. See
		Documentation.md section 12 for the exact list.

		Options that are unique to XClient (all optional):
			Description = "..."   small muted line under a row title
			Settings = { ... }    per module settings for the gear flyout

	Usage
		local XClient = loadstring(game:HttpGet("URL_TO/xclient.lua"))()
		local Window  = XClient:CreateWindow({ Name = "XClient" })
		local Tab     = Window:CreateTab("Combat")
		Tab:CreateToggle({ Name = "Aimbot", Flag = "aimbot", Settings = { ... } })
=========================================================================]]

--=========================================================================
--  1. SERVICES
--=========================================================================

local function getService(name)
	local ok, service = pcall(function()
		return game:GetService(name)
	end)
	if ok and service then
		if cloneref then
			local ok2, ref = pcall(cloneref, service)
			if ok2 and ref then return ref end
		end
		return service
	end
	return nil
end

local Players = getService("Players")
local UserInputService = getService("UserInputService")
local TweenService = getService("TweenService")
local RunService = getService("RunService")
local CoreGui = getService("CoreGui")
local HttpService = getService("HttpService")

local LocalPlayer = Players and Players.LocalPlayer or nil

--=========================================================================
--  2. TINY HELPERS
--=========================================================================

local THEME_FONT = Enum.Font.Gotham
local THEME_FONT_BOLD = Enum.Font.GothamBold

local function create(className, props)
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			else
				inst[key] = value
			end
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function addCorner(obj, radius)
	return create("UICorner", {
		CornerRadius = radius or UDim.new(0, 6),
		Parent = obj,
	})
end

local function addStroke(obj, color, thickness, transparency)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = obj,
	})
end

local function addPadding(obj, all, right, bottom, left)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, all or 0),
		PaddingRight = UDim.new(0, right or all or 0),
		PaddingBottom = UDim.new(0, bottom or all or 0),
		PaddingLeft = UDim.new(0, left or right or all or 0),
		Parent = obj,
	})
end

local function addList(obj, props)
	local defaults = {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Parent = obj,
	}
	if props then
		for k, v in pairs(props) do defaults[k] = v end
	end
	return create("UIListLayout", defaults)
end

local function newText(props)
	props = props or {}
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.BorderSizePixel = 0
	props.Font = props.Font or THEME_FONT
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	if props.Text == nil then props.Text = "" end
	return create("TextLabel", props)
end

local function newFrame(props)
	props = props or {}
	props.BorderSizePixel = 0
	props.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(30, 30, 34)
	return create("Frame", props)
end

local function tween(obj, time, props, style)
	local info = TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end

local function callSafe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn("[XClient] callback error: " .. tostring(result))
		return nil
	end
	return result
end

local function round(n)
	return math.floor(n + 0.5)
end

--=========================================================================
--  3. THEMES
--=========================================================================

local Themes = {
	Neverlose = {
		Accent        = Color3.fromRGB(0, 178, 255),
		AccentSoft    = Color3.fromRGB(0, 140, 210),

		Background    = Color3.fromRGB(16, 16, 18),
		Surface       = Color3.fromRGB(22, 22, 25),
		SurfaceAlt    = Color3.fromRGB(28, 28, 32),
		SurfaceHover  = Color3.fromRGB(34, 34, 39),
		Rail          = Color3.fromRGB(13, 13, 15),
		Topbar        = Color3.fromRGB(20, 20, 23),

		Stroke        = Color3.fromRGB(40, 40, 47),
		StrokeSoft    = Color3.fromRGB(32, 32, 37),

		Text          = Color3.fromRGB(233, 233, 238),
		TextMuted     = Color3.fromRGB(140, 140, 150),
		TextDim       = Color3.fromRGB(96, 96, 106),

		ToggleOff     = Color3.fromRGB(50, 50, 57),
		SliderTrack   = Color3.fromRGB(40, 40, 47),

		Danger        = Color3.fromRGB(238, 82, 82),
		Success       = Color3.fromRGB(70, 200, 130),
	},

	Midnight = {
		Accent        = Color3.fromRGB(120, 120, 255),
		AccentSoft    = Color3.fromRGB(96, 96, 210),

		Background    = Color3.fromRGB(14, 14, 24),
		Surface       = Color3.fromRGB(21, 21, 34),
		SurfaceAlt    = Color3.fromRGB(27, 27, 43),
		SurfaceHover  = Color3.fromRGB(35, 35, 54),
		Rail          = Color3.fromRGB(11, 11, 19),
		Topbar        = Color3.fromRGB(18, 18, 30),

		Stroke        = Color3.fromRGB(44, 44, 66),
		StrokeSoft    = Color3.fromRGB(35, 35, 53),

		Text          = Color3.fromRGB(230, 230, 245),
		TextMuted     = Color3.fromRGB(145, 145, 175),
		TextDim       = Color3.fromRGB(100, 100, 128),

		ToggleOff     = Color3.fromRGB(52, 52, 74),
		SliderTrack   = Color3.fromRGB(44, 44, 66),

		Danger        = Color3.fromRGB(238, 90, 110),
		Success       = Color3.fromRGB(90, 210, 190),
	},

	Blood = {
		Accent        = Color3.fromRGB(230, 60, 70),
		AccentSoft    = Color3.fromRGB(190, 45, 55),

		Background    = Color3.fromRGB(17, 13, 13),
		Surface       = Color3.fromRGB(24, 18, 18),
		SurfaceAlt    = Color3.fromRGB(31, 23, 23),
		SurfaceHover  = Color3.fromRGB(40, 30, 30),
		Rail          = Color3.fromRGB(13, 10, 10),
		Topbar        = Color3.fromRGB(21, 15, 15),

		Stroke        = Color3.fromRGB(50, 34, 34),
		StrokeSoft    = Color3.fromRGB(38, 27, 27),

		Text          = Color3.fromRGB(238, 228, 228),
		TextMuted     = Color3.fromRGB(160, 135, 135),
		TextDim       = Color3.fromRGB(110, 92, 92),

		ToggleOff     = Color3.fromRGB(58, 42, 42),
		SliderTrack   = Color3.fromRGB(50, 34, 34),

		Danger        = Color3.fromRGB(238, 82, 82),
		Success       = Color3.fromRGB(90, 200, 130),
	},
}

--=========================================================================
--  4. GLOBAL STATE
--=========================================================================

local XClient = {}
XClient.__index = XClient

XClient.Version = "1.0.0"
XClient.Name = "XClient"
XClient.Themes = Themes
XClient.Flags = {}
XClient.Windows = {}
XClient.Connections = {}
XClient.Unloaded = false
XClient.Watermark = nil
--  Named icons: fill this with icons.lua["48px"] (or any name -> asset id map)
--  to keep older scripts that pass strings such as 'key-round' working.
XClient.Icons = {}

local function resolveTheme(theme)
	if type(theme) == "table" then
		local merged = {}
		for k, v in pairs(Themes.Neverlose) do merged[k] = v end
		for k, v in pairs(theme) do merged[k] = v end
		return merged
	end
	if type(theme) == "string" and Themes[theme] then
		return Themes[theme]
	end
	return Themes.Neverlose
end

--=========================================================================
--  5. VALUE ENCODING (used by the configuration system)
--=========================================================================

local function encodeValue(value)
	local t = typeof(value)
	if t == "Color3" then
		return { __type = "Color3", r = value.R, g = value.G, b = value.B }
	elseif t == "table" and value.__type ~= "Color3" then
		local out = { __type = "array" }
		for i, v in ipairs(value) do out[i] = encodeValue(v) end
		return out
	end
	return value
end

local function decodeValue(value)
	if type(value) == "table" then
		if value.__type == "Color3" then
			return Color3.new(value.r or 0, value.g or 0, value.b or 0)
		elseif value.__type == "array" then
			local out = {}
			for i, v in ipairs(value) do out[i] = decodeValue(v) end
			return out
		end
	end
	return value
end

--=========================================================================
--  6. NOTIFICATIONS
--=========================================================================

local function buildNotifications(gui, themeRef)
	local holder = newFrame({
		Name = "Notifications",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 300, 1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		AnchorPoint = Vector2.new(1, 0),
		Parent = gui,
	})
	holder.ZIndex = 80
	addList(holder, {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	})

	local api = {}

	function api:Push(data)
		data = data or {}
		local theme = themeRef()
		local duration = data.Duration or 5

		local card = newFrame({
			Name = "Notification",
			BackgroundColor3 = theme.Surface,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ClipsDescendants = true,
			Parent = holder,
		})
		card.ZIndex = 81
		addCorner(card, UDim.new(0, 8))
		addStroke(card, theme.Stroke, 1, 0)
		addPadding(card, 12)

		local accent = newFrame({
			Name = "Accent",
			BackgroundColor3 = data.Color or theme.Accent,
			Size = UDim2.new(0, 3, 1, 0),
			Position = UDim2.new(0, -8, 0, 0),
			Parent = card,
		})
		addCorner(accent, UDim.new(1, 0))

		local titleLabel = newText({
			Name = "Title",
			Text = data.Title or "XClient",
			Font = THEME_FONT_BOLD,
			TextSize = 14,
			TextColor3 = theme.Text,
			Size = UDim2.new(1, -8, 0, 16),
			Parent = card,
		})

		local body = newText({
			Name = "Content",
			Text = data.Content or "",
			TextSize = 12,
			TextColor3 = theme.TextMuted,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -8, 0, 0),
			Position = UDim2.new(0, 0, 0, 20),
			Parent = card,
		})

		card.BackgroundTransparency = 1
		card.Position = UDim2.new(1, 30, 0, 0)
		tween(card, 0.3, { BackgroundTransparency = 0, Position = UDim2.new(0, 0, 0, 0) })

		task.delay(duration, function()
			if not card or not card.Parent then return end
			tween(card, 0.25, { BackgroundTransparency = 1, Position = UDim2.new(1, 30, 0, 0) })
			task.delay(0.3, function()
				if card and card.Parent then card:Destroy() end
			end)
		end)

		return card
	end

	return api
end

--=========================================================================
--  7. PROCEDURAL GEAR ICON (no external assets)
--=========================================================================

local function buildGear(parent, size, color, bgColor)
	local gear = newFrame({
		Name = "Gear",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})

	-- Teeth around the ring
	for i = 0, 7 do
		local holder = newFrame({
			Name = "Tooth",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = i * 45,
			Parent = gear,
		})
		local tooth = newFrame({
			BackgroundColor3 = color,
			Size = UDim2.fromOffset(math.max(2, round(size * 0.2)), round(size * 0.3)),
			Position = UDim2.fromScale(0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.1),
			Parent = holder,
		})
		addCorner(tooth, UDim.new(1, 0))
	end

	-- Ring body (hollow -> gives the gear its hole)
	local ring = newFrame({
		Name = "Ring",
		BackgroundColor3 = color,
		Size = UDim2.fromScale(0.72, 0.72),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = gear,
	})
	addCorner(ring, UDim.new(1, 0))
	local hole = newFrame({
		Name = "Hole",
		BackgroundColor3 = bgColor or Color3.fromRGB(30, 30, 34),
		Size = UDim2.fromScale(0.34, 0.34),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = ring,
	})
	addCorner(hole, UDim.new(1, 0))

	return gear, hole
end

--=========================================================================
--  8. ELEMENT FACTORY  (module rows + controls)
--=========================================================================

local ROW_HEIGHT = 46
local ROW_PADDING_X = 14
local GEAR_SIZE = 20
local GEAR_BUTTON = 22
local GEAR_RIGHT = 10
local CONTROL_RIGHT = 12

--  Resolves an icon supplied by a script into an image plus optional sprite
--  rectangle. Accepted forms (all of them used by older scripts):
--      'key-round'                      -- named, looked up in XClient.Icons
--      4483362458                       -- asset id
--      'rbxassetid://4483362458'        -- asset url
--      XClient.Icons[name] = 4483362458 -- named, explicit id
--      XClient.Icons[name] = {4483362458, {48, 48}, {563, 967}}  (icons.lua rows)
local function resolveIcon(icon)
	if icon == nil then return nil end
	local kind = typeof(icon)
	if kind == "number" then
		if icon == 0 then return nil end
		return "rbxassetid://" .. tostring(icon)
	end
	if kind == "string" then
		if icon == "" then return nil end
		if icon:match("^%d+$") then
			return "rbxassetid://" .. icon
		end
		if icon:match("^rbxasset") or icon:match("^http") then
			return icon
		end
		local entry = XClient.Icons and XClient.Icons[icon]
		if type(entry) == "table" then
			local id = entry[1] or entry.Id
			if id ~= nil then
				local image = tostring(id)
				if not image:match("^rbxasset") and not image:match("^http") then
					image = "rbxassetid://" .. image
				end
				local rect = entry[2]
				local offset = entry[3]
				local rectSize = rect and Vector2.new(rect[1] or 0, rect[2] or 0) or nil
				local rectOffset = offset and Vector2.new(offset[1] or 0, offset[2] or 0) or nil
				return image, rectOffset, rectSize
			end
		elseif type(entry) == "number" then
			return "rbxassetid://" .. tostring(entry)
		elseif type(entry) == "string" then
			return entry
		end
	end
	return nil
end

--  Applies an icon (including the sprite rectangle) to an ImageLabel.
local function applyIcon(imageLabel, icon)
	local image, rectOffset, rectSize = resolveIcon(icon)
	if not image then
		imageLabel.Image = ""
		imageLabel.Visible = false
		return false
	end
	imageLabel.Image = image
	if rectOffset then imageLabel.ImageRectOffset = rectOffset end
	if rectSize then imageLabel.ImageRectSize = rectSize end
	imageLabel.Visible = true
	return true
end

-- Builds the base module row: icon + title + description + optional gear button.
local function newRow(container, ctx, opts)
	opts = opts or {}
	local theme = ctx.theme()
	local hasGear = type(opts.Settings) == "table" and #opts.Settings > 0
	local hasDesc = opts.Description ~= nil and opts.Description ~= ""

	local row = newFrame({
		Name = opts.Name or "Element",
		BackgroundColor3 = theme.Surface,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Parent = container,
	})
	addCorner(row, UDim.new(0, 6))
	local stroke = addStroke(row, theme.StrokeSoft, 1, 0.3)

	local titleX = ROW_PADDING_X
	if resolveIcon(opts.Icon) then
		local iconLabel = create("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			ImageColor3 = theme.TextMuted,
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.new(0, ROW_PADDING_X, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = row,
		})
		applyIcon(iconLabel, opts.Icon)
		titleX = ROW_PADDING_X + 26
	end

	local base = {
		row = row,
		stroke = stroke,
		opts = opts,
		titleX = titleX,
		hasGear = hasGear,
		hasDesc = hasDesc,
	}

	base.title = newText({
		Name = "Title",
		Text = opts.Name or "",
		TextSize = 14,
		Font = THEME_FONT_BOLD,
		TextColor3 = theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -(titleX + 20), 0, 15),
		Position = UDim2.new(0, titleX, 0.5, hasDesc and -15 or -7),
		AnchorPoint = Vector2.new(0, 0),
		Parent = row,
	})

	if hasDesc then
		base.desc = newText({
			Name = "Description",
			Text = opts.Description,
			TextSize = 11,
			TextColor3 = theme.TextDim,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, -(titleX + 20), 0, 12),
			Position = UDim2.new(0, titleX, 0.5, 1),
			AnchorPoint = Vector2.new(0, 0),
			Parent = row,
		})
	end

	if hasGear then
		local gearButton = create("TextButton", {
			Name = "GearButton",
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(GEAR_BUTTON, GEAR_BUTTON),
			Position = UDim2.new(1, -GEAR_RIGHT, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = row,
		})
		local gear, hole = buildGear(gearButton, GEAR_SIZE, theme.TextDim, theme.Surface)
		gear.Position = UDim2.fromScale(0.5, 0.5)
		gear.AnchorPoint = Vector2.new(0.5, 0.5)
		base.gearButton = gearButton
		base.gear = gear
		base.gearHole = hole

		gearButton.MouseEnter:Connect(function()
			tween(gear, 0.15, { Rotation = 45 })
			gear.Ring.BackgroundColor3 = theme.Text
			gear.Ring.Hole.BackgroundColor3 = theme.Surface
		end)
		gearButton.MouseLeave:Connect(function()
			tween(gear, 0.15, { Rotation = 0 })
			if not (ctx.isSettingsOpen and ctx.isSettingsOpen(base)) then
				gear.Ring.BackgroundColor3 = theme.TextDim
			end
		end)
		gearButton.MouseButton1Click:Connect(function()
			if ctx.toggleSettings then ctx.toggleSettings(base) end
		end)
	end

	return base
end

-- Reserves space for a control of the given width and shrinks the title accordingly.
local function fitControl(base, width)
	local rightOffset = base.hasGear and (GEAR_RIGHT + GEAR_BUTTON + 8) or CONTROL_RIGHT
	base.controlRight = rightOffset
	base.controlWidth = width
	local avail = -(base.titleX + rightOffset + width + 14)
	base.title.Size = UDim2.new(1, avail, 0, 15)
	if base.desc then base.desc.Size = UDim2.new(1, avail, 0, 12) end
end

--  Registers an element under its flag.  The *element table itself* is stored
--  (it is the settings table that the builder returns), which is exactly what
--  the previous interface exposed through its global flags registry:
--      Flags["aimbot"]:Set(true)
--      Flags["aimbot"].CurrentValue
--  The configuration system reads Type / CurrentValue / CurrentOption /
--  CurrentKeybind / Color straight off the same table.
local function registerFlag(ctx, opts, value, elementType, api)
	if not opts.Flag then return end
	opts.Type = opts.Type or elementType
	if opts.Value == nil then opts.Value = value end
	ctx.flags[opts.Flag] = opts
	XClient.Flags[opts.Flag] = opts
end

--=========================================================================
--  9. ELEMENT BUILDERS
--=========================================================================

local builders = {}

--  Backwards compatible option normalisation ---------------------------
--  Scripts written for the previous interface are handed straight to these
--  builders, so every alias below keeps them working untouched:
--    Value                <-> CurrentValue
--    MultipleOptions      <-> Multi
--    RemoveTextAfterFocusLost <-> RemoveTextOnLeave
--    PlaceholderText      <-> Placeholder
--    Range = {min, max}   <-> Min / Max
local function normalizeOpts(opts)
	opts = opts or {}

	if opts.CurrentValue == nil and opts.Value ~= nil then
		opts.CurrentValue = opts.Value
	end
	if opts.Value == nil then
		opts.Value = opts.CurrentValue
	end

	if opts.Multi == nil and opts.MultipleOptions ~= nil then
		opts.Multi = opts.MultipleOptions
	end
	if opts.MultipleOptions == nil then
		opts.MultipleOptions = opts.Multi and true or false
	end

	if opts.RemoveTextOnLeave == nil and opts.RemoveTextAfterFocusLost ~= nil then
		opts.RemoveTextOnLeave = opts.RemoveTextAfterFocusLost
	end
	if opts.RemoveTextAfterFocusLost == nil then
		opts.RemoveTextAfterFocusLost = opts.RemoveTextOnLeave and true or false
	end

	if opts.Placeholder == nil and opts.PlaceholderText ~= nil then
		opts.Placeholder = opts.PlaceholderText
	end

	if type(opts.Range) == "table" then
		opts.Min = opts.Min or opts.Range[1]
		opts.Max = opts.Max or opts.Range[2]
	end
	if type(opts.Range) ~= "table" then
		opts.Range = {opts.Min or 0, opts.Max or 100}
	end

	opts.Min = opts.Min or opts.Range[1] or 0
	opts.Max = opts.Max or opts.Range[2] or 100
	opts.Increment = opts.Increment or 1
	opts.Range = {opts.Min, opts.Max}

	return opts
end

--  Toggle ---------------------------------------------------------------
function builders.Toggle(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base = newRow(container, ctx, opts)

	local width, height, knobSize = 40, 22, 16
	local track = create("TextButton", {
		Name = "Switch",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = theme.ToggleOff,
		Size = UDim2.fromOffset(width, height),
		Parent = base.row,
	})
	addCorner(track, UDim.new(1, 0))
	track.AnchorPoint = Vector2.new(1, 0.5)
	fitControl(base, width)
	track.Position = UDim2.new(1, -(base.controlRight), 0.5, 0)

	local knob = newFrame({
		Name = "Knob",
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		Size = UDim2.fromOffset(knobSize, knobSize),
		Position = UDim2.new(0, 3, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = track,
	})
	addCorner(knob, UDim.new(1, 0))

	local value = opts.CurrentValue and true or false

	--  Backwards compatible contract: the settings table handed in by the
	--  caller *is* the returned element, exactly like before. That means
	--  myToggle.CurrentValue, myToggle.Value and myToggle:Set(v) all work.
	local api = opts
	api.Type = "Toggle"
	api.Value = value
	api.CurrentValue = value
	api.Row = base.row
	api.Base = base

	local function render(animate, fire)
		local onX = width - 3 - knobSize
		api.Value = value
		api.CurrentValue = value
		tween(track, animate and 0.15 or 0, { BackgroundColor3 = value and theme.Accent or theme.ToggleOff })
		tween(knob, animate and 0.15 or 0, { Position = UDim2.new(0, value and onX or 3, 0.5, 0) })
		if fire then callSafe(opts.Callback, value) end
	end

	function api:Set(v)
		value = v and true or false
		api.Value = value
		render(true, true)
	end

	function api:SetSilent(v)
		value = v and true or false
		api.Value = value
		render(false, false)
	end

	track.MouseButton1Click:Connect(function()
		value = not value
		api.Value = value
		render(true, true)
	end)

	render(false, false)
	registerFlag(ctx, opts, value, "Toggle", api)
	return api
end

--  Slider ---------------------------------------------------------------
function builders.Slider(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base = newRow(container, ctx, opts)

	local min = opts.Min or 0
	local max = opts.Max or 100
	local inc = opts.Increment or 1
	local suffix = opts.Suffix or ""
	local value = math.clamp(opts.CurrentValue or min, min, max)

	local width = opts.Width or 160
	local valueBox = newText({
		Name = "Value",
		Text = tostring(value) .. suffix,
		TextSize = 12,
		Font = THEME_FONT_BOLD,
		TextColor3 = theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(46, 20),
		Parent = base.row,
	})
	valueBox.Position = UDim2.new(1, 0, 0.5, 0)
	valueBox.AnchorPoint = Vector2.new(1, 0.5)

	local trackWidth = width - 54
	local track = create("TextButton", {
		Name = "Track",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = theme.SliderTrack,
		Size = UDim2.fromOffset(trackWidth, 5),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Parent = base.row,
	})
	addCorner(track, UDim.new(1, 0))

	local fill = newFrame({
		Name = "Fill",
		BackgroundColor3 = theme.Accent,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = track,
	})
	addCorner(fill, UDim.new(1, 0))

	local knob = newFrame({
		Name = "Knob",
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Parent = track,
	})
	addCorner(knob, UDim.new(1, 0))
	addStroke(knob, theme.Background, 2, 0)

	-- position the slider control group (track + value box) at the right
	local controlWidth = trackWidth + 54
	fitControl(base, controlWidth)
	local rightEdge = -(base.controlRight)
	track.Position = UDim2.new(1, rightEdge + 54, 0.5, 0)
	valueBox.Position = UDim2.new(1, rightEdge, 0.5, 0)

	--  Backwards compatible contract (see Toggle): the settings table handed in
	--  by the caller IS the element that gets returned, so mySlider.CurrentValue,
	--  mySlider.Range, mySlider.Suffix and mySlider:Set(v) all stay valid.
	local api = opts
	api.Type = "Slider"
	api.Value = value
	api.CurrentValue = value
	api.Row = base.row
	api.Base = base

	local function render(fire, fromInput)
		local alpha = (max > min) and ((value - min) / (max - min)) or 0
		api.Value = value
		api.CurrentValue = value
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		valueBox.Text = tostring(value) .. suffix
		if fire then callSafe(opts.Callback, value) end
	end

	local dragging = false

	local function updateFromX(x)
		local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local raw = min + (max - min) * rel
		raw = math.floor((raw / inc) + 0.5) * inc
		raw = math.clamp(raw, min, max)
		if raw ~= value then
			value = raw
			api.Value = value
			render(true)
		else
			render(false)
		end
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromX(input.Position.X)
		end
	end)
	ctx.connections[#ctx.connections + 1] = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromX(input.Position.X)
		end
	end)
	ctx.connections[#ctx.connections + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	function api:Set(v)
		value = math.clamp(v, min, max)
		api.Value = value
		render(true)
	end

	function api:SetSilent(v)
		value = math.clamp(v, min, max)
		api.Value = value
		render(false)
	end

	render(false)
	registerFlag(ctx, opts, value, "Slider", api)
	return api
end

--  Popup helper (shared by dropdown + colour picker) --------------------
local function makeChevron(parent, color, size, up)
	local holder = newFrame({
		Name = "Chevron",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	for i = -1, 1, 2 do
		create("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(1.6, size * 0.62),
			Position = UDim2.new(0.5, i * (size * 0.2), 0.5, up and -2 or 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = i * (up and 45 or -45),
			Parent = holder,
		})
	end
	return holder
end

local function openPopup(ctx, anchor, width, height, builder)
	ctx.closePopup()
	local theme = ctx.theme()
	local root = ctx.root

	local catcher = create("TextButton", {
		Name = "PopupCatcher",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 150,
		Parent = root,
	})

	local popup = newFrame({
		Name = "Popup",
		BackgroundColor3 = theme.SurfaceAlt,
		Size = UDim2.fromOffset(width, height),
		ClipsDescendants = true,
		ZIndex = 152,
		Parent = root,
	})
	addCorner(popup, UDim.new(0, 6))
	addStroke(popup, theme.Stroke, 1, 0)

	local absAnchor = anchor.AbsolutePosition
	local absRoot = root.AbsolutePosition
	popup.Position = UDim2.fromOffset(absAnchor.X - absRoot.X, absAnchor.Y - absRoot.Y + anchor.AbsoluteSize.Y + 4)

	local closed = false
	local function close()
		if closed then return end
		closed = true
		if catcher and catcher.Parent then catcher:Destroy() end
		if popup and popup.Parent then popup:Destroy() end
		if ctx.popup and ctx.popup.close == close then ctx.popup = nil end
	end

	catcher.MouseButton1Click:Connect(close)
	ctx.popup = { close = close, anchor = anchor }

	builder(popup, close)
	return popup, close
end

local function listFind(list, value)
	for i, entry in ipairs(list) do
		if entry == value then return i end
	end
	return nil
end

--  Dropdown -------------------------------------------------------------
--  Contract kept from the previous interface:
--    * CurrentOption is ALWAYS an array of strings
--    * :Set(value) accepts a string or an array and calls Callback(value)
--    * clicking an option calls Callback(CurrentOption)
--    * :Refresh(optionsTable) rebuilds the option list
--    * MultipleOptions switches between single and multi selection
function builders.Dropdown(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base = newRow(container, ctx, opts)

	--  The settings table is the element that gets returned.
	local api = opts
	api.Type = "Dropdown"
	api.Row = base.row
	api.Base = base

	local multi = opts.MultipleOptions and true or false
	api.Multi = multi

	local options = {}
	local selected = {}
	--  Keep the caller's initial selection: api IS the settings table, so the
	--  line below overwrites CurrentOption before we ever read it.
	local initialSelection = opts.CurrentOption
	if initialSelection == nil then initialSelection = opts.CurrentValue end
	api.CurrentOption = selected
	api.Value = selected

	local function setOptions(list)
		options = {}
		for i, value in ipairs(list or {}) do options[i] = tostring(value) end
		api.Options = options
	end

	local function setSelected(value)
		local out = {}
		if type(value) == "table" then
			for i, entry in ipairs(value) do out[i] = tostring(entry) end
		elseif value ~= nil then
			out[1] = tostring(value)
		end
		if not multi and #out > 1 then out = {out[1]} end
		selected = out
		api.CurrentOption = out
		api.Value = out
	end

	setOptions(opts.Options)
	setSelected(initialSelection)

	local boxWidth = opts.Width or 130
	local box = create("TextButton", {
		Name = "Selector",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = theme.SurfaceAlt,
		Size = UDim2.fromOffset(boxWidth, 26),
		Parent = base.row,
	})
	addCorner(box, UDim.new(0, 5))
	addStroke(box, theme.StrokeSoft, 1, 0)
	fitControl(base, boxWidth)
	box.Position = UDim2.new(1, -(base.controlRight), 0.5, 0)
	box.AnchorPoint = Vector2.new(1, 0.5)

	local label = newText({
		Name = "Selected",
		Text = "None",
		TextSize = 12,
		TextColor3 = theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -26, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		Parent = box,
	})

	local chevron = makeChevron(box, theme.TextMuted, 9, false)
	chevron.Position = UDim2.new(1, -8, 0.5, 0)
	chevron.AnchorPoint = Vector2.new(1, 0.5)

	local function display()
		if #selected == 0 then
			label.Text = "None"
		elseif #selected == 1 then
			label.Text = selected[1]
		else
			label.Text = multi and "Various" or selected[1]
		end
	end

	local function choose(name, close)
		if multi then
			local index = listFind(selected, name)
			if index then
				table.remove(selected, index)
			else
				selected[#selected + 1] = name
			end
		else
			selected = {name}
		end
		api.CurrentOption = selected
		api.Value = selected
		display()
		callSafe(opts.Callback, api.CurrentOption)
		ctx.saveConfiguration()
		if not multi and close then close() end
	end

	local function buildList(scroll, close)
		for _, name in ipairs(options) do
			local isOn = listFind(selected, name) ~= nil
			local item = create("TextButton", {
				Name = name,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = isOn and theme.SurfaceHover or theme.Surface,
				Size = UDim2.new(1, 0, 0, 24),
				Parent = scroll,
			})
			addCorner(item, UDim.new(0, 4))
			newText({
				Name = "Title",
				Text = name,
				TextSize = 12,
				TextColor3 = isOn and theme.Accent or theme.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1, -24, 1, 0),
				Position = UDim2.new(0, 8, 0, 0),
				Parent = item,
			})
			if isOn then
				local dot = newFrame({
					Name = "Check",
					BackgroundColor3 = theme.Accent,
					Size = UDim2.fromOffset(6, 6),
					Position = UDim2.new(1, -13, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					Parent = item,
				})
				addCorner(dot, UDim.new(1, 0))
			end
			item.MouseEnter:Connect(function()
				if isOn then return end
				item.BackgroundColor3 = theme.SurfaceHover
			end)
			item.MouseLeave:Connect(function()
				if isOn then return end
				item.BackgroundColor3 = theme.Surface
			end)
			item.MouseButton1Click:Connect(function()
				choose(name, close)
			end)
		end
	end

	box.MouseButton1Click:Connect(function()
		--  clicking the selector while its own list is open just closes it
		if ctx.popup and ctx.popup.anchor == box then
			ctx.closePopup()
			return
		end
		ctx.closePopup()
		local height = math.clamp(#options * 28 + 8, 34, 200)
		openPopup(ctx, box, math.max(boxWidth, 150), height, function(popup, close)
			local scroll = create("ScrollingFrame", {
				Name = "List",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -8, 1, -8),
				Position = UDim2.new(0, 4, 0, 4),
				ScrollBarThickness = 3,
				ScrollBarImageColor3 = theme.Stroke,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				Parent = popup,
			})
			addList(scroll, { Padding = UDim.new(0, 4) })
			buildList(scroll, close)
		end)
	end)

	function api:Set(value)
		setSelected(value)
		display()
		callSafe(opts.Callback, value)
		ctx.saveConfiguration()
		if ctx.popup then ctx.closePopup() end
	end

	function api:Refresh(optionsTable)
		setOptions(optionsTable)
		local kept = {}
		for _, name in ipairs(selected) do
			if listFind(options, name) then kept[#kept + 1] = name end
		end
		selected = kept
		api.CurrentOption = selected
		api.Value = selected
		display()
		if ctx.popup then ctx.closePopup() end
	end

	display()
	registerFlag(ctx, opts, selected, "Dropdown", api)
	return api
end

--  Input ----------------------------------------------------------------
--  Contract kept from the previous interface:
--    * PlaceholderText / CurrentValue / RemoveTextAfterFocusLost
--    * Callback fires with the text when the box loses focus
--    * :Set(text) updates the box and fires Callback(text)
function builders.Input(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base = newRow(container, ctx, opts)

	--  The settings table is the element that gets returned.
	local api = opts
	api.Type = "Input"
	api.Row = base.row
	api.Base = base

	local value = tostring(opts.CurrentValue or "")
	api.CurrentValue = value
	api.Value = value

	local width = opts.Width or 150
	local box = create("TextBox", {
		Name = "InputBox",
		Text = value,
		PlaceholderText = opts.PlaceholderText or opts.Placeholder or "",
		PlaceholderColor3 = theme.TextDim,
		Font = THEME_FONT,
		TextSize = 12,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = theme.SurfaceAlt,
		ClearTextOnFocus = false,
		Size = UDim2.fromOffset(width, 26),
		Parent = base.row,
	})
	addCorner(box, UDim.new(0, 5))
	local stroke = addStroke(box, theme.StrokeSoft, 1, 0)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = box,
	})
	fitControl(base, width)
	box.Position = UDim2.new(1, -(base.controlRight), 0.5, 0)
	box.AnchorPoint = Vector2.new(1, 0.5)

	local function fire()
		value = box.Text
		api.CurrentValue = value
		api.Value = value
		callSafe(opts.Callback, value)
		ctx.saveConfiguration()
	end

	box.Focused:Connect(function()
		stroke.Color = theme.Accent
		box.BackgroundColor3 = theme.SurfaceHover
	end)

	box.FocusLost:Connect(function()
		stroke.Color = theme.StrokeSoft
		box.BackgroundColor3 = theme.SurfaceAlt
		fire()
		if opts.RemoveTextOnLeave or opts.RemoveTextAfterFocusLost then
			box.Text = ""
		end
	end)

	function api:Set(text)
		text = tostring(text or "")
		box.Text = text
		fire()
	end

	function api:SetSilent(text)
		text = tostring(text or "")
		box.Text = text
		value = text
		api.CurrentValue = value
		api.Value = value
	end

	registerFlag(ctx, opts, value, "Input", api)
	return api
end

local function keyName(code)
	local ok, name = pcall(function() return code.Name end)
	if ok and name then return name end
	return (tostring(code):match("%.(%w+)$")) or tostring(code)
end

--  Keybind --------------------------------------------------------------
--  Contract kept from the previous interface:
--    * CurrentKeybind / CurrentKeybind is a plain string such as "Q"
--    * clicking the box and pressing a key rebinds it
--    * HoldToInteract -> Callback(true) while held, Callback(false) on release
--    * otherwise Callback() runs on press (CallOnChange -> Callback(key) on change)
--    * :Set(keybind) rebinds programmatically
function builders.Keybind(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base = newRow(container, ctx, opts)

	--  The settings table is the element that gets returned.
	local api = opts
	api.Type = "Keybind"
	api.Row = base.row
	api.Base = base

	local holdToInteract = opts.HoldToInteract and true or false
	local current = opts.CurrentKeybind
	if current ~= nil then current = tostring(current) end
	api.CurrentKeybind = current
	api.Value = current

	local width = opts.Width or 120
	local box = create("TextButton", {
		Name = "KeybindBox",
		Text = current or "...",
		Font = THEME_FONT_BOLD,
		TextSize = 12,
		TextColor3 = theme.Text,
		AutoButtonColor = false,
		BackgroundColor3 = theme.SurfaceAlt,
		Size = UDim2.fromOffset(width, 26),
		Parent = base.row,
	})
	addCorner(box, UDim.new(0, 5))
	local stroke = addStroke(box, theme.StrokeSoft, 1, 0)
	fitControl(base, width)
	box.Position = UDim2.new(1, -(base.controlRight), 0.5, 0)
	box.AnchorPoint = Vector2.new(1, 0.5)

	local listening = false
	local function display()
		box.Text = listening and "..." or (api.CurrentKeybind or "...")
		stroke.Color = listening and theme.Accent or theme.StrokeSoft
	end

	local function keyCode()
		if not api.CurrentKeybind or api.CurrentKeybind == "" then return nil end
		local ok, code = pcall(function() return Enum.KeyCode[api.CurrentKeybind] end)
		if ok then return code end
		return nil
	end

	box.MouseButton1Click:Connect(function()
		listening = not listening
		display()
	end)

	local held = false
	ctx.connections[#ctx.connections + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if listening then
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				api:Set("")
			elseif input.KeyCode and input.KeyCode ~= Enum.KeyCode.Unknown then
				api:Set(keyName(input.KeyCode))
			end
			return
		end
		if processed or opts.CallOnChange then return end
		local code = keyCode()
		if code and input.KeyCode == code then
			if holdToInteract then
				held = true
				callSafe(opts.Callback, true)
			else
				callSafe(opts.Callback)
			end
		end
	end)

	ctx.connections[#ctx.connections + 1] = UserInputService.InputEnded:Connect(function(input)
		if not held then return end
		local code = keyCode()
		if code and input.KeyCode == code then
			held = false
			callSafe(opts.Callback, false)
		end
	end)

	function api:Set(newKeybind)
		newKeybind = tostring(newKeybind or "")
		if newKeybind == "Enum.KeyCode.Unknown" then newKeybind = "" end
		api.CurrentKeybind = newKeybind
		api.Value = newKeybind
		listening = false
		display()
		if opts.CallOnChange then
			callSafe(opts.Callback, newKeybind)
		end
		ctx.saveConfiguration()
	end

	display()
	registerFlag(ctx, opts, current, "Keybind", api)
	return api
end

--  Colour picker -------------------------------------------------------
--  Contract kept from the previous interface:
--    * { Name, Color, Flag, Callback } - Callback receives a Color3
--    * :Set(color3) updates the picker, .Color always holds the current colour
function builders.ColorPicker(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base = newRow(container, ctx, opts)

	--  The settings table is the element that gets returned.
	local api = opts
	api.Type = "ColorPicker"
	api.Row = base.row
	api.Base = base

	local color = opts.Default or opts.Color
	if typeof(color) ~= "Color3" then color = Color3.fromRGB(255, 255, 255) end
	local hue, sat, val = color:ToHSV()
	api.Color = color
	api.Value = color

	--  Swatch (the clickable control living on the row) ------------------
	local swatchWidth = 46
	local swatch = create("TextButton", {
		Name = "Swatch",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = theme.SurfaceAlt,
		Size = UDim2.fromOffset(swatchWidth, 26),
		Parent = base.row,
	})
	addCorner(swatch, UDim.new(0, 5))
	addStroke(swatch, theme.StrokeSoft, 1, 0)
	fitControl(base, swatchWidth)
	swatch.Position = UDim2.new(1, -(base.controlRight), 0.5, 0)
	swatch.AnchorPoint = Vector2.new(1, 0.5)

	local swatchFill = newFrame({
		Name = "Fill",
		BackgroundColor3 = color,
		Size = UDim2.new(1, -6, 1, -6),
		Position = UDim2.new(0, 3, 0, 3),
		Parent = swatch,
	})
	addCorner(swatchFill, UDim.new(0, 3))

	local popup, sv, svMarker, hueMarker, hueBar, hexBox

	local function render()
		local pure = Color3.fromHSV(hue, 1, 1)
		swatchFill.BackgroundColor3 = color
		if not popup or not popup.Parent then return end
		sv.BackgroundColor3 = pure
		svMarker.Position = UDim2.new(sat, 0, 1 - val, 0)
		hueMarker.Position = UDim2.new(hue, 0, 0.5, 0)
		hueMarker.BackgroundColor3 = pure
		local r = math.floor(color.R * 255 + 0.5)
		local g = math.floor(color.G * 255 + 0.5)
		local b = math.floor(color.B * 255 + 0.5)
		if not hexBox:IsFocused() then
			hexBox.Text = string.format("#%02X%02X%02X", r, g, b)
		end
	end

	local function setHsv(newHue, newSat, newVal, fire)
		hue = math.clamp(newHue, 0, 1)
		sat = math.clamp(newSat, 0, 1)
		val = math.clamp(newVal, 0, 1)
		color = Color3.fromHSV(hue, sat, val)
		api.Color = color
		api.Value = color
		render()
		if fire then callSafe(opts.Callback, color) end
	end

	function api:Set(newColor)
		if typeof(newColor) ~= "Color3" then return end
		color = newColor
		hue, sat, val = color:ToHSV()
		api.Color = color
		api.Value = color
		render()
		callSafe(opts.Callback, color)
		ctx.saveConfiguration()
	end

	function api:SetSilent(newColor)
		if typeof(newColor) ~= "Color3" then return end
		color = newColor
		hue, sat, val = color:ToHSV()
		api.Color = color
		api.Value = color
		render()
	end

	--  Popup that carries the actual picker ------------------------------
	local function buildPopup(popupFrame)
		popup = popupFrame

		sv = create("TextButton", {
			Name = "SaturationValue",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
			Size = UDim2.fromOffset(170, 110),
			Position = UDim2.fromOffset(10, 10),
			Parent = popup,
		})
		addCorner(sv, UDim.new(0, 4))

		local white = newFrame({
			Name = "Saturation",
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			Size = UDim2.fromScale(1, 1),
			Parent = sv,
		})
		create("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			Transparency = NumberSequence.new(0, 1),
			Rotation = 0,
			Parent = white,
		})

		local black = newFrame({
			Name = "Value",
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			Size = UDim2.fromScale(1, 1),
			Parent = sv,
		})
		create("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(0, 0, 0)),
			Transparency = NumberSequence.new(0, 1),
			Rotation = 90,
			Parent = black,
		})

		svMarker = newFrame({
			Name = "Marker",
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			Size = UDim2.fromOffset(8, 8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = sv,
		})
		addCorner(svMarker, UDim.new(1, 0))
		addStroke(svMarker, Color3.fromRGB(20, 20, 20), 1, 0)

		hueBar = create("TextButton", {
			Name = "Hue",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			Size = UDim2.fromOffset(170, 12),
			Position = UDim2.fromOffset(10, 128),
			Parent = popup,
		})
		addCorner(hueBar, UDim.new(1, 0))
		create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
				ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
			}),
			Parent = hueBar,
		})

		hueMarker = newFrame({
			Name = "Marker",
			BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
			Size = UDim2.fromOffset(10, 10),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = hueBar,
		})
		addCorner(hueMarker, UDim.new(1, 0))
		addStroke(hueMarker, Color3.fromRGB(255, 255, 255), 2, 0)

		hexBox = create("TextBox", {
			Name = "Hex",
			Text = "",
			Font = THEME_FONT,
			TextSize = 12,
			TextColor3 = theme.Text,
			PlaceholderText = "#FFFFFF",
			PlaceholderColor3 = theme.TextDim,
			ClearTextOnFocus = false,
			BackgroundColor3 = theme.Surface,
			Size = UDim2.fromOffset(170, 24),
			Position = UDim2.fromOffset(10, 150),
			Parent = popup,
		})
		addCorner(hexBox, UDim.new(0, 4))
		addStroke(hexBox, theme.StrokeSoft, 1, 0)

		hexBox.FocusLost:Connect(function()
			local hex = hexBox.Text:match("%x%x%x%x%x%x")
			if hex then
				local r = tonumber(hex:sub(1, 2), 16) or 255
				local g = tonumber(hex:sub(3, 4), 16) or 255
				local b = tonumber(hex:sub(5, 6), 16) or 255
				local newColor = Color3.fromRGB(r, g, b)
				hue, sat, val = newColor:ToHSV()
				color = newColor
				api.Color = color
				api.Value = color
				callSafe(opts.Callback, color)
				ctx.saveConfiguration()
			end
			render()
		end)

		--  Dragging ----------------------------------------------------
		local function updateSv(x, y)
			local relX = math.clamp((x - sv.AbsolutePosition.X) / math.max(sv.AbsoluteSize.X, 1), 0, 1)
			local relY = math.clamp((y - sv.AbsolutePosition.Y) / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
			setHsv(hue, relX, 1 - relY, false)
		end

		local function updateHue(x)
			local relX = math.clamp((x - hueBar.AbsolutePosition.X) / math.max(hueBar.AbsoluteSize.X, 1), 0, 1)
			setHsv(relX, sat, val, false)
		end

		local function drag(onMove)
			local moved, ended
			moved = UserInputService.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
					local pos = UserInputService:GetMouseLocation()
					onMove(pos.X, pos.Y)
				end
			end)
			ended = UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					moved:Disconnect()
					ended:Disconnect()
					callSafe(opts.Callback, color)
					ctx.saveConfiguration()
				end
			end)
			ctx.connections[#ctx.connections + 1] = moved
			ctx.connections[#ctx.connections + 1] = ended
		end

		sv.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				updateSv(input.Position.X, input.Position.Y)
				drag(updateSv)
			end
		end)

		hueBar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				updateHue(input.Position.X)
				drag(function(x)
					updateHue(x)
				end)
			end
		end)

		render()
	end

	swatch.MouseButton1Click:Connect(function()
		if ctx.popup and ctx.popup.anchor == swatch then
			ctx.closePopup()
			return
		end
		ctx.closePopup()
		openPopup(ctx, swatch, 190, 184, function(popupFrame)
			buildPopup(popupFrame)
		end)
	end)

	render()
	registerFlag(ctx, opts, color, "ColorPicker", api)
	return api
end

--  Button ---------------------------------------------------------------
--  Contract kept from the previous interface:
--    * { Name, Callback } and the returned element exposes :Set(newName)
function builders.Button(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base = newRow(container, ctx, opts)

	local hovered = false
	local interact = create("TextButton", {
		Name = "Interact",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = base.row,
	})

	interact.MouseEnter:Connect(function()
		hovered = true
		tween(base.row, 0.15, { BackgroundColor3 = theme.SurfaceHover })
	end)
	interact.MouseLeave:Connect(function()
		hovered = false
		tween(base.row, 0.15, { BackgroundColor3 = theme.Surface })
	end)

	--  The settings table is the element that gets returned.
	local api = opts
	api.Type = "Button"
	api.Row = base.row
	api.Base = base

	local running = false
	interact.MouseButton1Click:Connect(function()
		if running then return end
		running = true
		local ok = pcall(function() callSafe(opts.Callback) end)
		if not ok then warn("[XClient] button callback error: " .. tostring(opts.Name)) end
		tween(base.row, 0.1, { BackgroundColor3 = theme.Accent })
		task.delay(0.12, function()
			if base.row and base.row.Parent then
				tween(base.row, 0.25, { BackgroundColor3 = hovered and theme.SurfaceHover or theme.Surface })
			end
		end)
		running = false
	end)

	function api:Set(newName)
		newName = tostring(newName or "")
		api.Name = newName
		if base.title then base.title.Text = newName end
		if base.row then base.row.Name = newName end
	end

	return api
end

--  Section --------------------------------------------------------------
--  Contract kept from the previous interface: Tab:CreateSection("Name")
--  and the returned element exposes :Set(newName)
function builders.Section(container, ctx, options)
	local theme = ctx.theme()
	local name = options
	if type(options) == "table" then
		name = options.Name or options.Text or ""
	end
	name = tostring(name or "")

	local holder = newFrame({
		Name = "Section",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 32),
		Parent = container,
	})

	local title = newText({
		Name = "Title",
		Text = string.upper(name),
		TextSize = 11,
		Font = THEME_FONT_BOLD,
		TextColor3 = theme.TextDim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -4, 0, 14),
		Position = UDim2.new(0, 2, 0, 12),
		Parent = holder,
	})

	newFrame({
		Name = "Line",
		BackgroundColor3 = theme.StrokeSoft,
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0, 28),
		Parent = holder,
	})

	local api = {
		Type = "Section",
		Name = name,
		Element = holder,
	}
	function api:Set(newName)
		newName = tostring(newName or "")
		api.Name = newName
		title.Text = string.upper(newName)
	end
	return api
end

--  Divider --------------------------------------------------------------
--  Contract kept from the previous interface: Tab:CreateDivider() and the
--  returned element exposes :Set(visible)
function builders.Divider(container, ctx)
	local theme = ctx.theme()

	local holder = newFrame({
		Name = "Divider",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 9),
		Parent = container,
	})
	local line = newFrame({
		Name = "Line",
		BackgroundColor3 = theme.StrokeSoft,
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = holder,
	})

	local api = {
		Type = "Divider",
		Element = holder,
	}
	function api:Set(visible)
		holder.Visible = visible and true or false
	end
	return api
end

--  Label ----------------------------------------------------------------
--  Contract kept from the previous interface:
--      Tab:CreateLabel("Text")                       -- plain
--      Tab:CreateLabel("Text", icon, Color3, ignoreTheme)
--      returnedElement:Set("New text", icon, Color3)
function builders.Label(container, ctx, text, icon, color, ignoreTheme)
	if type(text) == "table" then
		local o = text
		text, icon, color, ignoreTheme = o.Text or o.Name or "", o.Icon, o.Color, o.IgnoreTheme
	end

	local theme = ctx.theme()
	local holder = newFrame({
		Name = "Label",
		BackgroundColor3 = color or theme.Surface,
		BackgroundTransparency = color and 0.82 or 0,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = container,
	})
	addCorner(holder, UDim.new(0, 6))
	addStroke(holder, color or theme.StrokeSoft, 1, color and 0.7 or 0.3)

	local iconImage = resolveIcon(icon)
	local iconLabel = create("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		ImageColor3 = color or theme.TextMuted,
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = holder,
	})
	applyIcon(iconLabel, icon)

	local title = newText({
		Name = "Title",
		Text = tostring(text or ""),
		TextSize = 12,
		TextColor3 = color or theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, iconImage and -42 or -24, 1, 0),
		Position = UDim2.new(0, iconImage and 32 or 12, 0, 0),
		Parent = holder,
	})

	local api = {
		Type = "Label",
		Name = tostring(text or ""),
		Element = holder,
	}
	function api:Set(newText, newIcon, newColor)
		title.Text = tostring(newText or "")
		api.Name = title.Text
		if typeof(newColor) == "Color3" then
			holder.BackgroundColor3 = newColor
			holder.BackgroundTransparency = 0.82
			iconLabel.ImageColor3 = newColor
			title.TextColor3 = newColor
			if holder.UIStroke then holder.UIStroke.Color = newColor end
		end
		if applyIcon(iconLabel, newIcon) then
			title.Position = UDim2.new(0, 32, 0, 0)
			title.Size = UDim2.new(1, -42, 1, 0)
		end
	end
	return api
end

--  Paragraph ------------------------------------------------------------
--  Contract kept from the previous interface: Tab:CreateParagraph({Title = , Content = })
--  and the returned element exposes :Set({Title = , Content = })
function builders.Paragraph(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()

	local holder = newFrame({
		Name = "Paragraph",
		BackgroundColor3 = theme.Surface,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = container,
	})
	addCorner(holder, UDim.new(0, 6))
	addStroke(holder, theme.StrokeSoft, 1, 0.3)
	addPadding(holder, 10)
	addList(holder, { Padding = UDim.new(0, 6) })

	local title = newText({
		Name = "Title",
		Text = tostring(opts.Title or ""),
		TextSize = 13,
		Font = THEME_FONT_BOLD,
		TextColor3 = theme.Text,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		Parent = holder,
	})

	local body = newText({
		Name = "Content",
		Text = tostring(opts.Content or ""),
		TextSize = 12,
		TextColor3 = theme.TextMuted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		Parent = holder,
	})

	local api = {
		Type = "Paragraph",
		Element = holder,
	}
	function api:Set(newSettings)
		if type(newSettings) ~= "table" then return end
		if newSettings.Title ~= nil then title.Text = tostring(newSettings.Title) end
		if newSettings.Content ~= nil then body.Text = tostring(newSettings.Content) end
	end
	return api
end

--=========================================================================
--  10. THEME RESOLUTION (names used by the previous interface still work)
--=========================================================================

local THEME_ALIASES = {
	Default = "Neverlose",
	Neverlose = "Neverlose",
	Dark = "Neverlose",
	Light = "Neverlose",
	Green = "Neverlose",
	Ocean = "Midnight",
	DarkBlue = "Midnight",
	Serenity = "Midnight",
	Amethyst = "Midnight",
	Aqua = "Midnight",
	Midnight = "Midnight",
	Bloom = "Blood",
	AmberGlow = "Blood",
	Blood = "Blood",
	BloodRed = "Blood",
	Pink = "Blood",
	Valentine = "Blood",
}

local currentTheme = Themes.Neverlose

local function themeFromName(name)
	if type(name) == "table" then
		return resolveTheme(name)
	end
	if type(name) == "string" then
		local key = THEME_ALIASES[name] or Themes[name]
		if type(key) == "string" and Themes[key] then return Themes[key] end
		if type(key) == "table" then return key end
		local capitalised = name:sub(1, 1):upper() .. name:sub(2)
		key = THEME_ALIASES[capitalised]
		if key and Themes[key] then return Themes[key] end
	end
	return nil
end

--  Namespace kept for scripts written against the previous interface:
--  XClient.Theme.Default etc.
XClient.Theme = {
	Default = Themes.Neverlose,
	Neverlose = Themes.Neverlose,
	Midnight = Themes.Midnight,
	Blood = Themes.Blood,
	Ocean = Themes.Midnight,
	DarkBlue = Themes.Midnight,
	Serenity = Themes.Midnight,
	Amethyst = Themes.Midnight,
	Aqua = Themes.Midnight,
	AmberGlow = Themes.Blood,
	Bloom = Themes.Blood,
	Pink = Themes.Blood,
	Green = Themes.Neverlose,
	Light = Themes.Neverlose,
}

--=========================================================================
--  11. CONFIGURATION SYSTEM
--  Files keep the same folder names, extension and value shape as the
--  previous interface, so configurations saved before still load:
--      <Folder>/<FileName>.rfld   ->   { "Flag": value, ... }
--      Color3   -> {R = 0..255, G = 0..255, B = 0..255}
--      Dropdown -> array of the selected options
--=========================================================================

local CONFIG_ROOT = "XClient"
--  Folder the previous interface wrote its configurations into. It is only
--  ever read from, so configurations saved before this rewrite still load.
local LEGACY_CONFIG_ROOT = "Rayfield"
local CONFIG_EXTENSION = ".rfld"

local screenGui
local notifications
local notificationQueue = {}

local configState = {
	enabled = false,
	loaded = false,
	fileName = nil,
	folder = CONFIG_ROOT .. "/Configurations",
	disabledNotified = false,
}

local function filesystemAvailable()
	return type(writefile) == "function"
		and type(readfile) == "function"
		and type(isfile) == "function"
		and type(isfolder) == "function"
		and type(makefolder) == "function"
end

local function ensureFolder(path)
	if not filesystemAvailable() then return end
	local segments = {}
	for segment in string.gmatch(path, "[^/]+") do
		segments[#segments + 1] = segment
		local current = table.concat(segments, "/")
		if not isfolder(current) then
			pcall(makefolder, current)
		end
	end
end

local function packColor(color)
	return {
		R = math.floor(color.R * 255 + 0.5),
		G = math.floor(color.G * 255 + 0.5),
		B = math.floor(color.B * 255 + 0.5),
	}
end

local function unpackColor(value)
	if type(value) ~= "table" then return Color3.fromRGB(255, 255, 255) end
	return Color3.fromRGB(tonumber(value.R) or 255, tonumber(value.G) or 255, tonumber(value.B) or 255)
end

--  Collects the current state of every registered flag.
local function serializeFlags()
	local data = {}
	for flag, element in pairs(XClient.Flags) do
		if element.Flag == flag then
			local elementType = element.Type
			if elementType == "ColorPicker" then
				data[flag] = packColor(element.Color or Color3.fromRGB(255, 255, 255))
			elseif elementType == "Toggle" then
				data[flag] = element.CurrentValue and true or false
			elseif elementType == "Dropdown" then
				local copy = {}
				for i, option in ipairs(element.CurrentOption or {}) do copy[i] = option end
				data[flag] = copy
			elseif elementType == "Keybind" then
				data[flag] = tostring(element.CurrentKeybind or "")
			elseif elementType == "Input" then
				data[flag] = tostring(element.CurrentValue or "")
			elseif elementType == "Slider" then
				data[flag] = element.CurrentValue
			end
		end
	end
	return data
end

--  Applies a decoded configuration table onto the live elements.
local function applyFlags(data)
	if type(data) ~= "table" then return false end
	local changed = false
	for flag, element in pairs(XClient.Flags) do
		local value = data[flag]
		if value ~= nil and element.Set then
			if element.Type == "ColorPicker" then
				element:Set(unpackColor(value))
			elseif element.Type == "Dropdown" then
				element:Set(value)
			else
				element:Set(value)
			end
			changed = true
		end
	end
	return changed
end

local function encodeFlags()
	if not HttpService then return nil end
	local ok, encoded = pcall(function() return HttpService:JSONEncode(serializeFlags()) end)
	if ok then return encoded end
	return nil
end

local function decodeFlags(raw)
	if not HttpService or type(raw) ~= "string" or raw == "" then return nil end
	local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if ok and type(data) == "table" then return data end
	return nil
end

local function readConfigFile(name)
	if not filesystemAvailable() or not name then return nil end
	local paths = {
		configState.folder .. "/" .. name .. CONFIG_EXTENSION,
		LEGACY_CONFIG_ROOT .. "/Configurations/" .. name .. CONFIG_EXTENSION,
	}
	for _, path in ipairs(paths) do
		if isfile(path) then
			local ok, contents = pcall(readfile, path)
			if ok and contents and contents ~= "" then
				return contents
			end
		end
	end
	return nil
end

--  Writes the current flags to the file named in
--  CreateWindow({ ConfigurationSaving = { Enabled = true, FileName = "..." } })
local function saveConfiguration()
	if not configState.enabled or not configState.loaded then return false end
	if not configState.fileName or not filesystemAvailable() then return false end
	local encoded = encodeFlags()
	if not encoded then return false end
	ensureFolder(configState.folder)
	return pcall(writefile, configState.folder .. "/" .. configState.fileName .. CONFIG_EXTENSION, encoded)
end

--  Autoload performed right after CreateWindow (same behaviour as before).
local function loadConfiguration(silent)
	if not configState.enabled then return false end
	if not filesystemAvailable() or not HttpService then
		if not configState.disabledNotified then
			configState.disabledNotified = true
			XClient:Notify({
				Title = "XClient Configurations",
				Content = "Configuration saving could not be enabled because this executor has no filesystem support.",
			})
		end
		return false
	end
	local raw = readConfigFile(configState.fileName)
	if not raw then return false end
	local data = decodeFlags(raw)
	if not data then
		warn("[XClient] configuration file could not be decoded: " .. tostring(configState.fileName))
		return false
	end
	local changed = applyFlags(data)
	configState.loaded = true
	if not silent then
		XClient:Notify({
			Title = "XClient Configurations",
			Content = "The configuration file for this script has been loaded from a previous session.",
		})
	end
	return changed
end

--  Explicit configuration manager used by the built in configuration panel.
local function saveConfigurationAs(name)
	if not filesystemAvailable() or not name or name == "" then return false end
	local encoded = encodeFlags()
	if not encoded then return false end
	ensureFolder(configState.folder)
	return pcall(writefile, configState.folder .. "/" .. name .. CONFIG_EXTENSION, encoded)
end

local function loadConfigurationAs(name)
	local raw = readConfigFile(name)
	if not raw then return false end
	local data = decodeFlags(raw)
	if not data then return false end
	applyFlags(data)
	return true
end

local function deleteConfiguration(name)
	if not filesystemAvailable() or type(delfile) ~= "function" or not name then return false end
	local path = configState.folder .. "/" .. name .. CONFIG_EXTENSION
	if isfile(path) then return pcall(delfile, path) end
	return false
end

local function listConfigurations()
	local out = {}
	if not filesystemAvailable() or type(listfiles) ~= "function" then return out end
	local seen = {}
	local folders = { configState.folder, LEGACY_CONFIG_ROOT .. "/Configurations" }
	for _, folder in ipairs(folders) do
		if isfolder(folder) then
			local ok, files = pcall(listfiles, folder)
			if ok and files then
				for _, file in ipairs(files) do
					local name = tostring(file):match("([^/\\]+)$")
					if name then
						name = name:gsub("%.rfld$", "")
						if not seen[name] then
							seen[name] = true
							out[#out + 1] = name
						end
					end
				end
			end
		end
	end
	table.sort(out)
	return out
end

--=========================================================================
--  12. WINDOW + TABS
--=========================================================================

local WINDOW_WIDTH = 560
local WINDOW_HEIGHT = 420
local RAIL_WIDTH = 148
local TOPBAR_HEIGHT = 36
local PANEL_WIDTH = 210
local PANEL_GAP = 8

local activeContext

local function createScreenGui()
	local parent = CoreGui
	if not parent then
		local player = LocalPlayer or (Players and Players.LocalPlayer)
		if player then
			parent = player:FindFirstChildOfClass("PlayerGui")
		end
	end
	if not parent then return nil end

	local ok, gui = pcall(function()
		return create("ScreenGui", {
			Name = "XClient",
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = 10,
			Parent = parent,
		})
	end)
	if ok then return gui end
	return nil
end

--  Entry point matching the previous interface:
--  XClient:Notify({ Title, Content, Duration, Image })
function XClient:Notify(data)
	data = data or {}
	if notifications then
		notifications:Push(data)
	else
		notificationQueue[#notificationQueue + 1] = data
	end
end

--=========================================================================
--  13. CREATE WINDOW
--=========================================================================
function XClient:CreateWindow(settings)
	settings = settings or {}

	if screenGui == nil or not screenGui.Parent then
		screenGui = createScreenGui()
		if not screenGui then
			error("[XClient] unable to create the interface: no CoreGui or PlayerGui available")
		end
		notifications = buildNotifications(screenGui, function() return currentTheme end)
		local queued = notificationQueue
		notificationQueue = {}
		for _, item in ipairs(queued) do
			notifications:Push(item)
		end
	end

	--  Theme ------------------------------------------------------------
	if settings.Theme ~= nil then
		local resolved = themeFromName(settings.Theme)
		if resolved then currentTheme = resolved end
	end

	--  Configuration saving --------------------------------------------
	if type(settings.ConfigurationSaving) == "table" then
		local cfg = settings.ConfigurationSaving
		configState.enabled = cfg.Enabled and true or false
		configState.fileName = cfg.FileName or "XClient"
		configState.folder = cfg.FolderName and tostring(cfg.FolderName) or (CONFIG_ROOT .. "/Configurations")
	end

	--  Window frame ----------------------------------------------------
	local root = create("Frame", {
		Name = "XClientWindow",
		BackgroundColor3 = currentTheme.Background,
		Size = UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ClipsDescendants = false,
		Parent = screenGui,
	})
	root.ZIndex = 10
	addCorner(root, UDim.new(0, 10))
	local rootStroke = addStroke(root, currentTheme.Stroke, 1, 0.25)

	--  Topbar ----------------------------------------------------------
	local topbar = newFrame({
		Name = "Topbar",
		BackgroundColor3 = currentTheme.Topbar,
		Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
		Parent = root,
	})
	topbar.ZIndex = 11
	addCorner(topbar, UDim.new(0, 10))

	local filler = newFrame({
		Name = "Filler",
		BackgroundColor3 = currentTheme.Topbar,
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.new(0, 0, 1, -12),
		Parent = topbar,
	})
	filler.ZIndex = 11

	local title = newText({
		Name = "Title",
		Text = tostring(settings.Name or "XClient"),
		Font = THEME_FONT_BOLD,
		TextSize = 15,
		TextColor3 = currentTheme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -130, 1, 0),
		Position = UDim2.fromOffset(16, 0),
		Parent = topbar,
	})

	local divider = newFrame({
		Name = "Divider",
		BackgroundColor3 = currentTheme.StrokeSoft,
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Parent = topbar,
	})
	divider.ZIndex = 12

	--  Rail + content --------------------------------------------------
	local rail = newFrame({
		Name = "Rail",
		BackgroundColor3 = currentTheme.Rail,
		Size = UDim2.new(0, RAIL_WIDTH, 1, -TOPBAR_HEIGHT),
		Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
		Parent = root,
	})
	rail.ZIndex = 11
	addCorner(rail, UDim.new(0, 10))
	addList(rail, { Padding = UDim.new(0, 3) })
	create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 8),
		Parent = rail,
	})

	local content = newFrame({
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(RAIL_WIDTH + 12), 1, -(TOPBAR_HEIGHT + 12)),
		Position = UDim2.fromOffset(RAIL_WIDTH + 6, TOPBAR_HEIGHT + 6),
		Parent = root,
	})
	content.ZIndex = 12

	--  Shared context handed to every element builder -------------------
	local ctx = {
		root = root,
		flags = {},
		connections = {},
		popup = nil,
		theme = function() return currentTheme end,
		saveConfiguration = function() saveConfiguration() end,
	}

	ctx.closePopup = function()
		local current = ctx.popup
		ctx.popup = nil
		if current and current.close then current.close() end
	end

	activeContext = ctx

	--  Left settings flyout --------------------------------------------
	local flyout = newFrame({
		Name = "SettingsFlyout",
		BackgroundColor3 = currentTheme.Surface,
		Size = UDim2.fromOffset(PANEL_WIDTH, WINDOW_HEIGHT),
		Position = UDim2.fromOffset(-(PANEL_WIDTH + PANEL_GAP), 0),
		Visible = false,
		Parent = root,
	})
	flyout.ZIndex = 30
	addCorner(flyout, UDim.new(0, 10))
	local flyoutStroke = addStroke(flyout, currentTheme.Stroke, 1, 0.25)

	local flyoutTitle = newText({
		Name = "Title",
		Text = "Settings",
		Font = THEME_FONT_BOLD,
		TextSize = 14,
		TextColor3 = currentTheme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(12, 14),
		Parent = flyout,
	})
	flyoutTitle.ZIndex = 31

	local flyoutClose = create("TextButton", {
		Name = "Close",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -10, 0, 14),
		AnchorPoint = Vector2.new(1, 0),
		Parent = flyout,
	})
	flyoutClose.ZIndex = 31
	local closeBarA = newFrame({ BackgroundColor3 = currentTheme.TextMuted, Size = UDim2.fromOffset(10, 1.6), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45, Parent = flyoutClose })
	local closeBarB = newFrame({ BackgroundColor3 = currentTheme.TextMuted, Size = UDim2.fromOffset(10, 1.6), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -45, Parent = flyoutClose })
	closeBarA.ZIndex = 32
	closeBarB.ZIndex = 32

	local flyoutBody = create("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -12, 1, -(TOPBAR_HEIGHT + 14)),
		Position = UDim2.fromOffset(6, TOPBAR_HEIGHT + 6),
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = currentTheme.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = flyout,
	})
	flyoutBody.ZIndex = 31
	addList(flyoutBody, { Padding = UDim.new(0, 6) })

	local flyoutOpen = false
	local settingsTarget

	local function closeFlyout()
		if not flyoutOpen then return end
		flyoutOpen = false
		settingsTarget = nil
		tween(flyout, 0.16, { Position = UDim2.fromOffset(-(PANEL_WIDTH + PANEL_GAP), 0) })
		task.delay(0.18, function()
			if not flyoutOpen and flyout and flyout.Parent then
				flyout.Visible = false
			end
		end)
	end

	local function openFlyout(heading, populate)
		flyoutBody:ClearAllChildren()
		addList(flyoutBody, { Padding = UDim.new(0, 6) })
		flyoutTitle.Text = tostring(heading or "Settings")
		flyout.Visible = true
		flyout.Position = UDim2.fromOffset(-(PANEL_WIDTH + PANEL_GAP), 0)
		flyoutOpen = true
		tween(flyout, 0.2, { Position = UDim2.fromOffset(-(PANEL_WIDTH + PANEL_GAP - 4), 0) })
		if populate then populate(flyoutBody) end
	end

	flyoutClose.MouseButton1Click:Connect(closeFlyout)

	--  Instantiate the per module settings of a row inside the flyout ----
	local function buildModuleSettings(container, base)
		local list = base.opts and base.opts.Settings
		if type(list) ~= "table" then return end
		newText({
			Name = "Heading",
			Text = string.upper(tostring(base.opts.Name or "Module")),
			Font = THEME_FONT_BOLD,
			TextSize = 11,
			TextColor3 = currentTheme.TextDim,
			Size = UDim2.new(1, 0, 0, 15),
			Parent = container,
		})
		for _, descriptor in ipairs(list) do
			if type(descriptor) == "table" then
				local elementType = descriptor.Type or "Toggle"
				local builder = builders[elementType]
				if builder then
					builder(container, ctx, descriptor)
				elseif elementType == "Label" then
					builders.Label(container, ctx, descriptor.Text or descriptor.Name, descriptor.Icon, descriptor.Color)
				end
			elseif type(descriptor) == "string" then
				builders.Section(container, ctx, descriptor)
			end
		end
	end

	ctx.toggleSettings = function(base)
		if settingsTarget == base and flyoutOpen then
			closeFlyout()
			return
		end
		settingsTarget = base
		openFlyout(base.opts and base.opts.Name or "Settings", function(container)
			buildModuleSettings(container, base)
		end)
	end

	ctx.isSettingsOpen = function(base)
		return flyoutOpen and settingsTarget == base
	end

	--  Global settings panel (topbar gear / configuration manager) --------
	local openGlobalSettings
	local repaint
	local toggleKey = settings.ToggleUIKeybind
	if typeof(toggleKey) == "EnumItem" then toggleKey = toggleKey.Name end
	if type(toggleKey) == "string" and toggleKey ~= "" then
		toggleKey = string.upper(toggleKey)
	else
		toggleKey = "K"
	end

	local function currentThemeName()
		for name, palette in pairs(Themes) do
			if palette == currentTheme then return name end
		end
		return "Neverlose"
	end

	local function buildGlobalSettings(container)
		--  Theme ------------------------------------------------------
		builders.Section(container, ctx, "Theme")
		builders.Dropdown(container, ctx, {
			Name = "Interface theme",
			Options = { "Neverlose", "Midnight", "Blood" },
			CurrentOption = currentThemeName(),
			Callback = function(value)
				local name = type(value) == "table" and value[1] or value
				local resolved = themeFromName(name)
				if resolved then
					currentTheme = resolved
					if repaint then repaint() end
				end
			end,
		})

		--  Configuration ----------------------------------------------
		builders.Section(container, ctx, "Configuration")
		local configName = configState.fileName or "Default"
		local refreshConfigList

		builders.Input(container, ctx, {
			Name = "Config file name",
			CurrentValue = configName,
			PlaceholderText = "Config name",
			Callback = function(text) configName = text end,
		})

		builders.Button(container, ctx, {
			Name = "Save configuration",
			Callback = function()
				if saveConfigurationAs(configName) then
					XClient:Notify({ Title = "XClient Configurations", Content = "'" .. tostring(configName) .. "' has been saved." })
					if refreshConfigList then refreshConfigList() end
				else
					XClient:Notify({ Title = "XClient Configurations", Content = "Saving failed - no filesystem support available." })
				end
			end,
		})

		builders.Button(container, ctx, {
			Name = "Load configuration",
			Callback = function()
				if loadConfigurationAs(configName) then
					XClient:Notify({ Title = "XClient Configurations", Content = "'" .. tostring(configName) .. "' has been loaded." })
				else
					XClient:Notify({ Title = "XClient Configurations", Content = "No saved configuration named '" .. tostring(configName) .. "'." })
				end
			end,
		})

		builders.Button(container, ctx, {
			Name = "Delete configuration",
			Callback = function()
				if deleteConfiguration(configName) then
					XClient:Notify({ Title = "XClient Configurations", Content = "'" .. tostring(configName) .. "' has been deleted." })
					if refreshConfigList then refreshConfigList() end
				else
					XClient:Notify({ Title = "XClient Configurations", Content = "No saved configuration named '" .. tostring(configName) .. "'." })
				end
			end,
		})

		local listHolder = newFrame({
			Name = "SavedConfigurations",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = container,
		})
		addList(listHolder, { Padding = UDim.new(0, 4) })

		refreshConfigList = function()
			listHolder:ClearAllChildren()
			addList(listHolder, { Padding = UDim.new(0, 4) })
			local configs = listConfigurations()
			if #configs == 0 then
				newText({
					Name = "Empty",
					Text = "No saved configurations yet",
					TextSize = 11,
					TextColor3 = currentTheme.TextDim,
					Size = UDim2.new(1, 0, 0, 18),
					Parent = listHolder,
				})
				return
			end
			newText({
				Name = "Heading",
				Text = "SAVED",
				Font = THEME_FONT_BOLD,
				TextSize = 11,
				TextColor3 = currentTheme.TextDim,
				Size = UDim2.new(1, 0, 0, 15),
				Parent = listHolder,
			})
			for _, name in ipairs(configs) do
				builders.Button(listHolder, ctx, {
					Name = name,
					Callback = function()
						if loadConfigurationAs(name) then
							XClient:Notify({ Title = "XClient Configurations", Content = "'" .. name .. "' has been loaded." })
						end
					end,
				})
			end
		end
		refreshConfigList()

		--  Interface --------------------------------------------------
		builders.Section(container, ctx, "Interface")
		builders.Keybind(container, ctx, {
			Name = "Toggle interface",
			CurrentKeybind = toggleKey,
			CallOnChange = true,
			Callback = function(key) toggleKey = key end,
		})
	end

	openGlobalSettings = function()
		settingsTarget = nil
		openFlyout("Settings", buildGlobalSettings)
	end

	--  Topbar buttons --------------------------------------------------
	local function drawBar(parent, color, size, rotation)
		local bar = newFrame({
			Name = "Bar",
			BackgroundColor3 = color,
			Size = size,
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = rotation or 0,
			Parent = parent,
		})
		bar.ZIndex = 14
		return bar
	end

	local function makeTopbarButton(name, offsetX, draw)
		local button = create("TextButton", {
			Name = name,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BackgroundColor3 = currentTheme.SurfaceHover,
			Size = UDim2.fromOffset(24, 24),
			Position = UDim2.new(1, offsetX, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = topbar,
		})
		button.ZIndex = 13
		addCorner(button, UDim.new(0, 4))
		draw(button)
		button.MouseEnter:Connect(function()
			tween(button, 0.12, { BackgroundTransparency = 0.7 })
		end)
		button.MouseLeave:Connect(function()
			tween(button, 0.12, { BackgroundTransparency = 1 })
		end)
		return button
	end

	local settingsButton = makeTopbarButton("SettingsButton", -42, function(button)
		local gear = buildGear(button, 15, currentTheme.TextMuted, currentTheme.Topbar)
		gear.Position = UDim2.fromScale(0.5, 0.5)
		gear.AnchorPoint = Vector2.new(0.5, 0.5)
	end)
	settingsButton.MouseButton1Click:Connect(function()
		if flyoutOpen and settingsTarget == nil then
			closeFlyout()
		else
			openGlobalSettings()
		end
	end)

	local minimised = false
	local function setMinimised(state)
		minimised = state and true or false
		if minimised then closeFlyout() end
		rail.Visible = not minimised
		content.Visible = not minimised
		flyout.Size = UDim2.fromOffset(PANEL_WIDTH, minimised and TOPBAR_HEIGHT or WINDOW_HEIGHT)
		tween(root, 0.2, { Size = UDim2.fromOffset(WINDOW_WIDTH, minimised and TOPBAR_HEIGHT or WINDOW_HEIGHT) })
	end

	makeTopbarButton("MinimiseButton", -72, function(button)
		drawBar(button, currentTheme.TextMuted, UDim2.fromOffset(11, 1.6), 0)
		button.MouseButton1Click:Connect(function() setMinimised(not minimised) end)
	end)

	makeTopbarButton("CloseButton", -12, function(button)
		drawBar(button, currentTheme.TextMuted, UDim2.fromOffset(11, 1.6), 45)
		drawBar(button, currentTheme.TextMuted, UDim2.fromOffset(11, 1.6), -45)
		button.MouseButton1Click:Connect(function() XClient:Destroy() end)
	end)

	--  Dragging ---------------------------------------------------------
	local dragging, dragStart, dragOrigin
	topbar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = UserInputService:GetMouseLocation()
			dragOrigin = root.Position
		end
	end)
	ctx.connections[#ctx.connections + 1] = UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local delta = UserInputService:GetMouseLocation() - dragStart
		root.Position = UDim2.new(
			dragOrigin.X.Scale,
			dragOrigin.X.Offset + delta.X,
			dragOrigin.Y.Scale,
			dragOrigin.Y.Offset + delta.Y
		)
	end)
	ctx.connections[#ctx.connections + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	--  Show / hide the interface ---------------------------------------
	local visible = true
	local function setVisible(state)
		visible = state and true or false
		root.Visible = visible
		if not visible then closeFlyout() end
	end
	ctx.setVisible = setVisible
	ctx.isVisible = function() return visible end

	ctx.connections[#ctx.connections + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not toggleKey or toggleKey == "" then return end
		local ok, code = pcall(function() return Enum.KeyCode[toggleKey] end)
		if ok and code and input.KeyCode == code then
			setVisible(not visible)
		end
	end)

	--  Optional icon + loading titles -----------------------------------
	local iconImage = resolveIcon(settings.Icon)
	if iconImage then
		local iconLabel = create("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.fromOffset(16, 9),
			Parent = topbar,
		})
		iconLabel.ZIndex = 13
		applyIcon(iconLabel, settings.Icon)
		title.Position = UDim2.fromOffset(42, 0)
		title.Size = UDim2.new(1, -160, 1, 0)
	end

	if settings.LoadingTitle or settings.LoadingSubtitle then
		local splash = newFrame({
			Name = "Splash",
			BackgroundColor3 = currentTheme.Background,
			BackgroundTransparency = 0.05,
			Size = UDim2.fromScale(1, 1),
			Parent = root,
		})
		splash.ZIndex = 60
		addCorner(splash, UDim.new(0, 10))
		local splashTitle = newText({
			Name = "Title",
			Text = tostring(settings.LoadingTitle or "XClient"),
			Font = THEME_FONT_BOLD,
			TextSize = 18,
			TextColor3 = currentTheme.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.new(0, 0, 0.5, -16),
			Parent = splash,
		})
		local splashSubtitle = newText({
			Name = "Subtitle",
			Text = tostring(settings.LoadingSubtitle or "Interface Suite"),
			TextSize = 12,
			TextColor3 = currentTheme.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.new(0, 0, 0.5, 10),
			Parent = splash,
		})
		splashTitle.ZIndex = 61
		splashSubtitle.ZIndex = 61
		task.delay(1.2, function()
			if not (splash and splash.Parent) then return end
			tween(splash, 0.3, { BackgroundTransparency = 1 })
			tween(splashTitle, 0.3, { TextTransparency = 1 })
			tween(splashSubtitle, 0.3, { TextTransparency = 1 })
			task.delay(0.35, function()
				if splash and splash.Parent then splash:Destroy() end
			end)
		end)
	end

	--  Tabs -------------------------------------------------------------
	local tabs = {}
	local firstTabSelected = false

	local function showTab(target)
		for _, entry in ipairs(tabs) do
			local isTarget = entry.page == target
			entry.page.Visible = isTarget
			entry.button.BackgroundColor3 = isTarget and currentTheme.Surface or currentTheme.Rail
			entry.label.TextColor3 = isTarget and currentTheme.Text or currentTheme.TextMuted
			if entry.icon then
				entry.icon.ImageColor3 = isTarget and currentTheme.Accent or currentTheme.TextMuted
			end
		end
	end

	local Window = {}
	XClient.Windows[#XClient.Windows + 1] = Window

	local function buildRecord(record, container)
		if record.type == "Label" then
			return builders.Label(container, ctx, record.arg1, record.arg2, record.arg3, record.arg4)
		elseif record.type == "Section" then
			return builders.Section(container, ctx, record.name)
		elseif record.type == "Divider" then
			return builders.Divider(container, ctx)
		end
		return builders[record.type](container, ctx, record.opts)
	end

	function Window:CreateTab(name, image, ext)
		name = tostring(name or "Tab")

		local button = create("TextButton", {
			Name = name,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = currentTheme.Rail,
			Size = UDim2.new(1, 0, 0, 30),
			Parent = rail,
		})
		button.ZIndex = 12
		addCorner(button, UDim.new(0, 5))

		local iconImage = resolveIcon(image)
		local label = newText({
			Name = "Title",
			Text = name,
			Font = THEME_FONT_BOLD,
			TextSize = 13,
			TextColor3 = currentTheme.TextMuted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, iconImage and -30 or -18, 1, 0),
			Position = UDim2.fromOffset(iconImage and 30 or 12, 0),
			Parent = button,
		})
		label.ZIndex = 13

		local icon
		if iconImage then
			icon = create("ImageLabel", {
				Name = "Icon",
				BackgroundTransparency = 1,
				ImageColor3 = currentTheme.TextMuted,
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.new(0, 9, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Parent = button,
			})
			icon.ZIndex = 13
			applyIcon(icon, image)
		end

		local page = create("ScrollingFrame", {
			Name = name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = currentTheme.Stroke,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Parent = content,
		})
		page.ZIndex = 13

		local records = {}
		local entry = {
			name = name,
			button = button,
			label = label,
			icon = icon,
			page = page,
			records = records,
			ext = ext and true or false,
		}
		tabs[#tabs + 1] = entry
		if entry.ext then
			button.Visible = false
		end

		local function setupPage()
			page:ClearAllChildren()
			addList(page, { Padding = UDim.new(0, 6) })
			create("UIPadding", {
				PaddingTop = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 6),
				Parent = page,
			})
			page.CanvasPosition = Vector2.new()
		end
		setupPage()

		local function addRecord(record)
			records[#records + 1] = record
			return buildRecord(record, page)
		end

		local tab = {
			Name = name,
			Page = page,
			Records = records,
			Ext = entry.ext,
		}

		function tab:CreateButton(settings) return addRecord({ type = "Button", opts = settings or {} }) end
		function tab:CreateToggle(settings) return addRecord({ type = "Toggle", opts = settings or {} }) end
		function tab:CreateSlider(settings) return addRecord({ type = "Slider", opts = settings or {} }) end
		function tab:CreateDropdown(settings) return addRecord({ type = "Dropdown", opts = settings or {} }) end
		function tab:CreateInput(settings) return addRecord({ type = "Input", opts = settings or {} }) end
		function tab:CreateKeybind(settings) return addRecord({ type = "Keybind", opts = settings or {} }) end
		function tab:CreateColorPicker(settings) return addRecord({ type = "ColorPicker", opts = settings or {} }) end
		function tab:CreateParagraph(settings) return addRecord({ type = "Paragraph", opts = settings or {} }) end
		function tab:CreateDivider() return addRecord({ type = "Divider" }) end
		function tab:CreateSection(sectionName) return addRecord({ type = "Section", name = sectionName }) end

		function tab:CreateLabel(text, icon, color, ignoreTheme)
			return addRecord({ type = "Label", arg1 = text, arg2 = icon, arg3 = color, arg4 = ignoreTheme })
		end

		--  Rebuilds every element of this page (used on theme changes).
		function tab:Refresh()
			setupPage()
			for _, record in ipairs(records) do
				buildRecord(record, page)
			end
		end

		function tab:Select() showTab(page) end

		function tab:Destroy()
			if button and button.Parent then button:Destroy() end
			if page and page.Parent then page:Destroy() end
		end

		button.MouseButton1Click:Connect(function() showTab(page) end)

		if not firstTabSelected and not entry.ext then
			firstTabSelected = true
			showTab(page)
		end
		if entry.ext then
			page.Visible = false
		end

		return tab
	end

	--  Repaint everything when the theme changes -------------------------
	repaint = function()
		local theme = currentTheme
		root.BackgroundColor3 = theme.Background
		rootStroke.Color = theme.Stroke
		topbar.BackgroundColor3 = theme.Topbar
		filler.BackgroundColor3 = theme.Topbar
		divider.BackgroundColor3 = theme.StrokeSoft
		rail.BackgroundColor3 = theme.Rail
		title.TextColor3 = theme.Text
		flyout.BackgroundColor3 = theme.Surface
		flyoutStroke.Color = theme.Stroke
		flyoutTitle.TextColor3 = theme.Text
		flyoutBody.ScrollBarImageColor3 = theme.Stroke
		closeBarA.BackgroundColor3 = theme.TextMuted
		closeBarB.BackgroundColor3 = theme.TextMuted
		for _, entry in ipairs(tabs) do
			entry.page.ScrollBarImageColor3 = theme.Stroke
			entry.button.BackgroundColor3 = entry.page.Visible and theme.Surface or theme.Rail
			entry.label.TextColor3 = entry.page.Visible and theme.Text or theme.TextMuted
			if entry.icon then
				entry.icon.ImageColor3 = entry.page.Visible and theme.Accent or theme.TextMuted
			end
		end
		for _, entry in ipairs(tabs) do
			entry.page:ClearAllChildren()
			addList(entry.page, { Padding = UDim.new(0, 6) })
			create("UIPadding", {
				PaddingTop = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 6),
				Parent = entry.page,
			})
			for _, record in ipairs(entry.records) do
				buildRecord(record, entry.page)
			end
		end
	end

	--  Window methods (names kept from the previous interface) -----------
	function Window:Notify(data)
		XClient:Notify(data)
	end

	function Window:CreateSection(tab, sectionName)
		--  Convenience only: sections belong to tabs.
		if tab and tab.CreateSection then return tab:CreateSection(sectionName) end
	end

	function Window:SaveConfiguration() return saveConfiguration() end
	function Window:LoadConfiguration() return XClient:LoadConfiguration() end
	function Window:SetVisibility(state) setVisible(state) end
	function Window:IsVisible() return visible end
	function Window:Destroy() XClient:Destroy() end
	function Window:ShowSettings() openGlobalSettings() end
	function Window:HideSettings() closeFlyout() end

	--  Deliberately defined with a dot: the previous examples call it as
	--  Window.ModifyTheme("DarkBlue"), colon calls are tolerated as well.
	function Window.ModifyTheme(a, b)
		local newTheme = b or a
		local resolved = themeFromName(newTheme)
		if not resolved then
			XClient:Notify({ Title = "Unable to Change Theme", Content = "We are unable to find a theme on file." })
			return false
		end
		currentTheme = resolved
		repaint()
		XClient:Notify({
			Title = "Theme Changed",
			Content = "Successfully changed theme to " .. (type(newTheme) == "string" and newTheme or "Custom Theme") .. ".",
		})
		return true
	end

	--  Autoload the saved configuration once the script finished building.
	configState.loaded = true
	task.delay(1, function()
		if configState.enabled and not configState.autoLoaded then
			configState.autoLoaded = true
			loadConfiguration()
		end
	end)

	return Window
end

--=========================================================================
--  14. LIBRARY LEVEL API (same entry points the scripts already use)
--=========================================================================

function XClient:LoadConfiguration()
	configState.autoLoaded = true
	local ok, result = pcall(loadConfiguration)
	if not ok then
		warn("[XClient] configuration load failed: " .. tostring(result))
		return false
	end
	return result
end

function XClient:SaveConfiguration()
	return saveConfiguration()
end

function XClient:SaveConfigurationAs(name)
	return saveConfigurationAs(name)
end

function XClient:LoadConfigurationAs(name)
	return loadConfigurationAs(name)
end

function XClient:DeleteConfiguration(name)
	return deleteConfiguration(name)
end

function XClient:ListConfigurations()
	return listConfigurations()
end

function XClient:SetVisibility(state)
	if activeContext and activeContext.setVisible then
		activeContext.setVisible(state)
	end
end

function XClient:IsVisible()
	if activeContext and activeContext.isVisible then
		return activeContext.isVisible()
	end
	return false
end

function XClient:Destroy()
	if activeContext then
		for _, connection in ipairs(activeContext.connections) do
			pcall(function() connection:Disconnect() end)
		end
		activeContext = nil
	end
	if screenGui and screenGui.Parent then
		screenGui:Destroy()
	end
	screenGui = nil
	notifications = nil
	XClient.Flags = {}
	XClient.Windows = {}
end

--  Expose the library globally, the way the previous interface did, so any
--  script that grabbed it from the executor environment keeps working.
if getgenv then
	getgenv().XClient = XClient
end

return XClient
