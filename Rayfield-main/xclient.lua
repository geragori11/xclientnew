--[[=========================================================================
	XClient Interface Suite
	Neverlose-style user interface library for Roblox
	-----------------------------------------------------------------------
	Highlights
		* Full custom / self-contained UI (no external Roblox asset needed)
		* Dark "Neverlose" theme with a left tab rail, three palettes and the
		  palette names used by the previous interface
		* CS style condensed HUD font by default, with switchable profiles
		  (CS / Classic / Mono / custom): XClient:SetFont("Classic")
		* Captions are measured and fitted, so a title shrinks or wraps onto a
		  second line instead of being clipped - in tabs and in the flyout
		* A default menu open key set in CreateWindow, rebindable from the
		  settings panel and saved with the configuration
		* Animated loading screen: HUD brackets, a filling bar with a shimmer,
		  a percentage counter and a stage list (Loading = false disables it)
		* Extended widgets (section 9b): PlayerWidget, Image markers,
		  Crosshair/FOV pad, Graph, Progress, Stepper, Segment, Wheel, Analog,
		  Radar and Chips - all of them usable inside module settings too
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
			OpenKey = "K"         default key that shows / hides the menu
			                      (aliases: DefaultOpenKey, MenuKey,
			                      OpenKeybind, ToggleKey, ToggleUIKeybind)
			Loading = true|false|<seconds>   boot animation of the window
			LoadingTitle / LoadingSubtitle / LoadingSteps / LoadingDuration

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
local TextService = getService("TextService")

local LocalPlayer = Players and Players.LocalPlayer or nil

--=========================================================================
--  2. TINY HELPERS
--=========================================================================

--  Font profiles -----------------------------------------------------------
--  "CS" is the default look: condensed, squared-off HUD type, the kind of
--  lettering competitive shooters (and Steam's overlay) use. "Classic" brings
--  back the rounded geometric font the previous interface used and "Mono" is
--  a terminal font. Switch at runtime with XClient:SetFont("Classic") or from
--  the settings panel; every element is rebuilt with the new face.
local FONT_PROFILES = {
	CS      = { Primary = Enum.Font.RobotoCondensed, Strong = Enum.Font.Oswald,     Mono = Enum.Font.RobotoMono, Offset = 1 },
	Classic = { Primary = Enum.Font.Gotham,          Strong = Enum.Font.GothamBold, Mono = Enum.Font.Code,       Offset = 0 },
	Mono    = { Primary = Enum.Font.RobotoMono,      Strong = Enum.Font.Code,       Mono = Enum.Font.Code,       Offset = -1 },
}
local FONT_PROFILE = "CS"
local THEME_FONT = FONT_PROFILES[FONT_PROFILE].Primary
local THEME_FONT_BOLD = FONT_PROFILES[FONT_PROFILE].Strong
local THEME_FONT_MONO = FONT_PROFILES[FONT_PROFILE].Mono
--  Optional custom font face (a Roblox font asset / family url) for the active
--  profile. Leave it nil to use the Enum.Font families above; set it in a
--  profile to plug in a real Counter-Strike style face, e.g.
--      Face = "rbxasset://fonts/families/GothamSSm.json"
local THEME_FACE = FONT_PROFILES[FONT_PROFILE].Face
--  Condensed faces read smaller than the rounded one, so text sizes are
--  nudged by the profile (applied once, inside create()).
local FONT_SIZE_OFFSET = FONT_PROFILES[FONT_PROFILE].Offset
local FONT_MIN_SIZE = 10

local function create(className, props)
	--  Single choke point for the font size offset of the active font profile
	--  (see FONT_PROFILES above), so every single text in the interface grows
	--  or shrinks together with the font family.
	if props and props.TextSize and (className == "TextLabel" or className == "TextButton" or className == "TextBox") then
		props.TextSize = props.TextSize + FONT_SIZE_OFFSET
	end
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
	--  A font profile may point at a real font asset (see THEME_FACE). This is
	--  attempted through pcall, so a client without FontFace support simply
	--  keeps the Enum.Font family that was set above.
	if THEME_FACE and (className == "TextLabel" or className == "TextButton" or className == "TextBox") then
		pcall(function()
			if typeof(Font) == "table" and Font.new then
				inst.FontFace = Font.new(THEME_FACE)
			else
				inst.FontFace = THEME_FACE
			end
		end)
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

--  Text measuring and fitting ---------------------------------------------
--  Everything below keeps a caption inside the width it was given: the font is
--  stepped down until the string fits and, when even the smallest size is too
--  wide, the caption wraps onto a second line (rows grow) instead of being
--  clipped in the middle of a word.
local function measureText(text, size, font)
	text = tostring(text or "")
	if text == "" then return 0 end
	if TextService and TextService.GetTextSize then
		local ok, bounds = pcall(function()
			return TextService:GetTextSize(text, size, font or THEME_FONT, Vector2.new(10000, 10000))
		end)
		if ok and typeof(bounds) == "Vector2" then
			return bounds.X
		end
	end
	--  Fallback estimate for executors without a usable TextService:
	--  condensed sans, roughly 0.53em per character.
	return #text * size * 0.53
end

local function ellipsize(text, size, font, width)
	text = tostring(text or "")
	if width <= 0 or measureText(text, size, font) <= width then return text end
	local cut = #text
	while cut > 1 and measureText(string.sub(text, 1, cut) .. "...", size, font) > width do
		cut = cut - 1
	end
	return string.sub(text, 1, cut) .. "..."
end

--  Fits a label into `width` pixels.
--      opts.MaxSize   starting size (defaults to the label's own size)
--      opts.MinSize   smallest size that is still readable
--      opts.Wrap      wrap instead of using an ellipsis (keeps the full text)
--  Returns the size that was applied plus whether the label ended up wrapped.
local function fitLabel(label, width, opts)
	if not label or not width or width <= 0 then return nil, false end
	opts = opts or {}
	local text = tostring(label.Text or "")
	if text == "" then return nil, false end
	local font = label.Font
	local maxSize = opts.MaxSize or label.TextSize or 14
	local minSize = opts.MinSize or FONT_MIN_SIZE
	if maxSize < minSize then maxSize = minSize end
	local size = maxSize
	while size > minSize and measureText(text, size, font) > width do
		size = size - 1
	end
	if measureText(text, size, font) <= width then
		label.TextSize = size
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.None
		return size, false
	end
	if opts.Wrap then
		label.TextSize = minSize
		label.TextWrapped = true
		label.TextTruncate = Enum.TextTruncate.None
		return minSize, true
	end
	label.TextSize = minSize
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ellipsize(text, minSize, font, width)
	return minSize, false
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

--  Element builders hand their global input handlers to the interface through
--  ctx.connections so XClient:Destroy() can drop them.  A few of them live
--  only for the duration of a drag (the colour picker) and disconnect
--  themselves as soon as the button comes up - those should also take their
--  entry back out of the list, otherwise every single drag would leave a dead
--  closure (and the widgets it captured) behind for the rest of the session.
local function trackConnection(ctx, connection)
	ctx.connections[#ctx.connections + 1] = connection
	return connection
end

local function untrackConnection(ctx, connection)
	local list = ctx.connections
	for index = #list, 1, -1 do
		if list[index] == connection then
			table.remove(list, index)
		end
	end
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

--  Number of favourite-colour slots shown to the right of every colour picker
--  (shared palette, see XClient.FavoriteColors below).
local FAVORITE_SLOTS = 9

local XClient = {}
XClient.__index = XClient

XClient.Version = "1.6.0"
--  Manual build tag. It is the number loader.lua compares against the one
--  published in version.txt next to this file, so bump it whenever you push a
--  change and then run `lua _mkversion.lua` to keep both in sync (the loader
--  warns when they disagree).
XClient.Build = "1.6."0
XClient.Name = "XClient"
XClient.Themes = Themes
XClient.Flags = {}
--  Shared palette of favourite colours (the FAVORITE_SLOTS slots shown to the
--  right of every colour picker).  Clicking an empty slot stores the current
--  colour, clicking a filled slot applies it back to the picker and the whole
--  palette is saved with the configuration under the reserved key
--  __favorite_colors, so it survives a rejoin together with the menu.
XClient.FavoriteColors = {}
XClient.FavoriteSlots = FAVORITE_SLOTS
XClient.Windows = {}
XClient.Connections = {}
XClient.Unloaded = false
XClient.Watermark = nil
--  Named icons: fill this with icons.lua["48px"] (or any name -> asset id map)
--  to keep older scripts that pass strings such as 'key-round' working.
XClient.Icons = {}
--  Active font profile name plus every available profile (see FONT_PROFILES
--  at the top of the file). XClient:SetFont("Classic") switches at runtime.
XClient.Font = FONT_PROFILE
XClient.Fonts = FONT_PROFILES
--  Default key that shows / hides the menu; CreateWindow({ OpenKey = "K" })
--  overrides it per window and the settings panel lets the player rebind it.
XClient.OpenKey = "K"

--  Internal registries: every live window registers its repaint function and
--  its menu key setter, so library wide calls (SetFont / SetOpenKey) reach the
--  interface that is currently on screen.
local repainters = {}
local openKeySetters = {}
local function registerRepainter(fn)
	if type(fn) == "function" then repainters[#repainters + 1] = fn end
end
local function clearRegistries()
	repainters = {}
	openKeySetters = {}
end

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

--  Row text fitting --------------------------------------------------------
--  Controls are right aligned, so the space a caption may use shrinks by
--  whatever the control (and the gear button) needs. When even the smallest
--  font size is too wide the row grows and the caption wraps instead of being
--  clipped - this is what keeps the settings flyout readable.
local ROW_WIDTH = 386   -- default page width, CreateWindow overwrites ctx.rowWidth

local function rowTextWidth(base, rowWidth)
	local right = base.hasGear and (GEAR_RIGHT + GEAR_BUTTON + 8) or CONTROL_RIGHT
	local control = base.controlWidth or 0
	return math.max(48, (rowWidth or ROW_WIDTH) - (base.titleX + right + control + 14))
end

local function fitRowText(base, rowWidth)
	if not base or not base.title then return end
	local baseHeight = base.rowHeight or ROW_HEIGHT
	local available = rowTextWidth(base, rowWidth or base.rowWidth)
	--  MaxSize is left out on purpose: the label's own size already carries the
	--  font profile offset (CS = +1), so the profile keeps the last word.
	local _, wrapped = fitLabel(base.title, available, { MinSize = FONT_MIN_SIZE, Wrap = true })
	if base.desc then
		fitLabel(base.desc, available, { MinSize = FONT_MIN_SIZE - 1, Wrap = true })
	end
	if wrapped then
		--  two lines: give the title more height and push the description down
		base.title.TextYAlignment = Enum.TextYAlignment.Top
		base.title.Size = UDim2.new(1, -(base.titleX + 20), 0, 28)
		base.title.Position = UDim2.new(0, base.titleX, 0.5, base.hasDesc and -18 or -13)
		if base.desc then
			base.desc.Position = UDim2.new(0, base.titleX, 0.5, 13)
		end
		base.row.Size = UDim2.new(1, 0, 0, baseHeight + 14)
		base.wrappedRow = true
	elseif base.wrappedRow then
		base.wrappedRow = nil
		base.title.TextYAlignment = Enum.TextYAlignment.Center
		base.title.Size = UDim2.new(1, -(base.titleX + 20), 0, 15)
		base.title.Position = UDim2.new(0, base.titleX, 0.5, base.hasDesc and -15 or -7)
		if base.desc then
			base.desc.Position = UDim2.new(0, base.titleX, 0.5, 1)
		end
		base.row.Size = UDim2.new(1, 0, 0, baseHeight)
	end
end

-- Builds the base module row: icon + title + description + optional gear button.
local function newRow(container, ctx, opts)
	opts = opts or {}
	local theme = ctx.theme()
	local hasGear = type(opts.Settings) == "table" and #opts.Settings > 0
	local hasDesc = opts.Description ~= nil and opts.Description ~= ""
	local rowHeight = tonumber(opts.Height) or ROW_HEIGHT
	--  Rows built inside a GroupBox (or asked for it with OnCard = true) sit on
	--  top of the card's own bluish surface instead of nesting a second card:
	--  they drop their background and keep only a hairline outline.
	local onCard = opts.OnCard == true or ctx.onCard == true

	local row = newFrame({
		Name = opts.Name or "Element",
		BackgroundColor3 = theme.Surface,
		BackgroundTransparency = onCard and 1 or 0,
		Size = UDim2.new(1, 0, 0, rowHeight),
		Parent = container,
	})
	addCorner(row, UDim.new(0, 6))
	local stroke = addStroke(row, theme.StrokeSoft, 1, onCard and 0.6 or 0.3)

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
		rowWidth = tonumber(ctx.rowWidth) or ROW_WIDTH,
		rowHeight = rowHeight,
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
		--  Right click opens the compact, auto height panel instead.
		gearButton.MouseButton2Click:Connect(function()
			if ctx.toggleCompactSettings then ctx.toggleCompactSettings(base) end
		end)
	end

	fitRowText(base, base.rowWidth)

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
	--  re-run the caption fitting now that the control width is known
	fitRowText(base, base.rowWidth)
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
		ctx.saveConfiguration()
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
		ctx.saveConfiguration()
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

	--  Slider geometry.  The knob is 24px wide, so it pokes 12px out of the
	--  track at both ends; that bleed has to stay clear of the caption on the
	--  left and of the value read-out on the right, otherwise the knob (and
	--  the fill behind it) lands on top of the label text - the "the caption
	--  is hidden behind the slider" report.
	local SLIDER_KNOB_W = 24
	local SLIDER_KNOB_R = SLIDER_KNOB_W / 2
	local SLIDER_VALUE_W = 46
	--  gap >= knob radius keeps the knob clear of the value box
	local SLIDER_VALUE_GAP = 14
	local SLIDER_MIN_TRACK = 28
	local SLIDER_MIN_CAPTION = 48        -- matches rowTextWidth's floor

	--  The control is right aligned, so its width is capped by whatever the
	--  caption (and the gear, when the row has one) leaves free.  Inside the
	--  narrow settings panel the requested 160px does not fit, so the track is
	--  shortened here instead of spilling over the caption.
	local rowWidth = tonumber(ctx.rowWidth) or ROW_WIDTH
	local rightOffset = base.hasGear and (GEAR_RIGHT + GEAR_BUTTON + 8) or CONTROL_RIGHT
	local minControl = SLIDER_KNOB_R + SLIDER_MIN_TRACK + SLIDER_VALUE_GAP + SLIDER_VALUE_W
	local maxControl = rowWidth - (base.titleX + rightOffset + SLIDER_MIN_CAPTION + 14)
	local width = math.max(math.min(opts.Width or 160, maxControl), minControl)

	local valueBox = newText({
		Name = "Value",
		Text = tostring(value) .. suffix,
		TextSize = 12,
		Font = THEME_FONT_BOLD,
		TextColor3 = theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(SLIDER_VALUE_W, 20),
		Parent = base.row,
	})
	valueBox.Position = UDim2.new(1, 0, 0.5, 0)
	valueBox.AnchorPoint = Vector2.new(1, 0.5)

	local trackWidth = width - SLIDER_KNOB_R - SLIDER_VALUE_GAP - SLIDER_VALUE_W
	local track = create("TextButton", {
		Name = "Track",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = theme.SliderTrack,
		--  A thicker "pill" track (was 5px tall) so it clearly reads as a slider.
		Size = UDim2.fromOffset(trackWidth, 10),
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
		--  Bigger knob (was 12x12) to match the thicker track.
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Parent = track,
	})
	addCorner(knob, UDim.new(1, 0))
	addStroke(knob, theme.Background, 2, 0)

	-- position the slider control group (track + value box) at the right
	local controlWidth = width
	fitControl(base, controlWidth)
	local rightEdge = -(base.controlRight)
	--  The whole control group (track + value box) is right aligned: the value
	--  box hugs the row's right edge and the track sits one control width to
	--  its left.  The track is inset on the left by the knob radius so the
	--  knob's leftmost pixel never reaches into the caption band fitControl
	--  just reserved.  Keep the offset negative so the slider is on screen.
	track.Position = UDim2.new(1, rightEdge - controlWidth + SLIDER_KNOB_R, 0.5, 0)
	valueBox.Position = UDim2.new(1, rightEdge, 0.5, 0)
	--  keep long values (decimals, suffixes, "Infinity") inside the value box
	fitLabel(valueBox, SLIDER_VALUE_W - 2, { MinSize = 9 })

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
			--  Persist once the drag finished (not on every intermediate step).
			if dragging then ctx.saveConfiguration() end
			dragging = false
		end
	end)

	function api:Set(v)
		value = math.clamp(v, min, max)
		api.Value = value
		render(true)
		ctx.saveConfiguration()
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

--  Nearest scrollable viewport above an element (a tab page or the settings
--  flyout).  Used to keep popups glued to their anchor while the page scrolls
--  and to dismiss them once the row scrolls out of view.
local function enclosingScroller(object)
	local node = object and object.Parent
	while node do
		if node:IsA("ScrollingFrame") then return node end
		node = node.Parent
	end
	return nil
end

local function anchorInView(anchor, scroller)
	if not scroller then return true end
	if not scroller.Parent or not scroller.Visible then return false end
	local top = scroller.AbsolutePosition.Y
	local bottom = top + scroller.AbsoluteSize.Y
	local center = anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y * 0.5
	return center >= top - 4 and center <= bottom + 4
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

	--  The popup is parented to the window (not to the row) so it has to be
	--  positioned by hand.  Recomputed every frame rather than once, so it stays
	--  glued to its selector while the page scrolls - that is the "the dropdown
	--  stays behind when I scroll" report.  The same routine keeps the popup
	--  inside the window and follows a window drag.
	local scroller = enclosingScroller(anchor)
	local function reposition()
		local absAnchor = anchor.AbsolutePosition
		local absRoot = root.AbsolutePosition
		local x = absAnchor.X - absRoot.X
		local y = absAnchor.Y - absRoot.Y + anchor.AbsoluteSize.Y + 4
		local maxX = root.AbsoluteSize.X - width
		local maxY = root.AbsoluteSize.Y - height
		if x > maxX then x = maxX end
		if x < 0 then x = 0 end
		if y > maxY then y = maxY end
		if y < 0 then y = 0 end
		popup.Position = UDim2.fromOffset(x, y)
	end
	reposition()

	--  Click shield.  The popup itself is a plain Frame and the gaps between
	--  the option rows (plus the few pixels of padding around the list) are not
	--  covered by any button, so a click there used to fall through to the
	--  catcher below and dismiss the popup WITHOUT selecting anything - which
	--  is exactly the "dropdown closes before I can pick" report.  This
	--  transparent button covers the popup's own background and swallows those
	--  stray clicks.  It is placed under the popup's contents (ZIndex 0 vs the
	--  default 1) and, thanks to ZIndexBehaviour.Sibling, still renders above
	--  the catcher.
	create("TextButton", {
		Name = "PopupShield",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = popup,
	})

	local closed = false
	local tracker
	local function close()
		if closed then return end
		closed = true
		if tracker then
			tracker:Disconnect()
			tracker = nil
		end
		if catcher and catcher.Parent then catcher:Destroy() end
		if popup and popup.Parent then popup:Destroy() end
		if ctx.popup and ctx.popup.close == close then ctx.popup = nil end
	end

	--  Follow the anchor every frame: this is what keeps the popup attached to
	--  its row while the page scrolls (or the window is dragged) and dismisses
	--  it once the row scrolled out of view or its page was rebuilt / switched.
	local function track()
		if closed then return end
		if not (anchor and anchor.Parent) then
			close()
			return
		end
		if not anchorInView(anchor, scroller) then
			close()
			return
		end
		reposition()
	end
	if RunService then
		--  RenderStepped is client-only (this is a client UI); fall back to
		--  Heartbeat should it ever be unavailable.
		local ok, connection = pcall(function() return RunService.RenderStepped:Connect(track) end)
		if not ok then
			ok, connection = pcall(function() return RunService.Heartbeat:Connect(track) end)
		end
		if ok then tracker = connection end
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
			--  Multi-select: show how many options are ticked ("3 selected")
			--  instead of the old "Various", and fall back to the first option
			--  for a single-selection list.
			label.Text = multi and (#selected .. " selected") or selected[1]
		end
		--  the selector is narrow, so the caption is fitted (never clipped)
		fitLabel(label, boxWidth - 28, { MaxSize = 13, MinSize = 9 })
	end

	--  Every row currently built in an open list, kept so a selection change
	--  can repaint the rows the user is looking at.
	local rows = {}

	local function paintRow(row)
		local isOn = listFind(selected, row.name) ~= nil
		--  an unselected row keeps its hover highlight while the pointer rests
		--  on it (otherwise clicking a row to uncheck it dropped the highlight)
		local hot = isOn or row.hovered
		row.item.BackgroundColor3 = hot and theme.SurfaceHover or theme.Surface
		row.label.TextColor3 = isOn and theme.Accent or theme.Text
		row.check.Visible = isOn
	end

	--  Repaint the open list after a toggle.  The row colours and the tick used
	--  to be captured once in buildList, so a multi-select row only caught up
	--  the next time the list was rebuilt and the click looked ignored.
	local function paintRows()
		for _, row in ipairs(rows) do
			if row.item.Parent then paintRow(row) end
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
		paintRows()
		callSafe(opts.Callback, api.CurrentOption)
		ctx.saveConfiguration()
		if not multi and close then close() end
	end

	local function buildList(scroll, close)
		rows = {}
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
			local optionLabel = newText({
				Name = "Title",
				Text = name,
				TextSize = 12,
				TextColor3 = isOn and theme.Accent or theme.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1, -24, 1, 0),
				Position = UDim2.new(0, 8, 0, 0),
				Parent = item,
			})
			fitLabel(optionLabel, math.max(60, (opts.Width or 130) - 24), { MinSize = 9 })
			--  The tick is always built and only shown/hidden, so repainting a
			--  row never has to create or destroy instances.
			local dot = newFrame({
				Name = "Check",
				BackgroundColor3 = theme.Accent,
				Size = UDim2.fromOffset(6, 6),
				Position = UDim2.new(1, -13, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Visible = isOn,
				Parent = item,
			})
			addCorner(dot, UDim.new(1, 0))
			local row = { name = name, item = item, label = optionLabel, check = dot }
			rows[#rows + 1] = row
			item.MouseEnter:Connect(function()
				row.hovered = true
				paintRow(row)
			end)
			item.MouseLeave:Connect(function()
				row.hovered = false
				paintRow(row)
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
			--  Hand the popup a way to repopulate itself in place.  A script that
			--  polls :Refresh() on this dropdown (very common for player lists)
			--  then no longer slams the list shut every tick - it just repaints
			--  the rows the user is currently looking at.
			if ctx.popup and ctx.popup.anchor == box then
				ctx.popup.rebuild = function()
					scroll:ClearAllChildren()
					addList(scroll, { Padding = UDim.new(0, 4) })
					buildList(scroll, close)
				end
			end
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
		--  Only touch a popup THIS dropdown owns.  Closing whatever happened to
		--  be open - another list, the colour picker, a keybind box - on every
		--  poll is what made dropdowns appear to flicker shut.
		if ctx.popup and ctx.popup.anchor == box then
			if ctx.popup.rebuild then
				ctx.popup.rebuild()
			else
				ctx.closePopup()
			end
		end
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

	--  Live update: hand every keystroke over instead of waiting for the focus
	--  to leave the box.  The settings panel reads the name of a configuration
	--  the moment Save / Load is pressed, and clicking a button does not always
	--  take the focus away from the field.  Nothing is written to disk here -
	--  only fire() does that - and :Set() keeps firing the callback just once.
	local programmatic = false
	if opts.LiveUpdate then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if programmatic then return end
			value = box.Text
			api.CurrentValue = value
			api.Value = value
			callSafe(opts.Callback, value)
		end)
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
		programmatic = true
		box.Text = text
		programmatic = false
		fire()
	end

	function api:SetSilent(text)
		text = tostring(text or "")
		programmatic = true
		box.Text = text
		programmatic = false
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

--  Enum.KeyCode members are case sensitive: single letters and digit codes are
--  upper case ("K", "F5") while every other code is CamelCase ("Space",
--  "LeftShift", "RightShift", "Up", ...).  Upper casing a name therefore
--  silently breaks the bind, because Enum.KeyCode["SPACE"] is not a member of
--  the Enum.  This resolves whatever the caller passed - a string in any
--  casing or an EnumItem - to the canonical member name, and returns nil for
--  values that are not a usable KeyCode (Enum.KeyCode.Unknown included).
local keyCodeLookup
local function resolveKeyName(value)
	if type(value) == "string" then
		value = value:match("^%s*(.-)%s*$") or ""
	elseif typeof(value) == "EnumItem" then
		local ok, name = pcall(function() return value.Name end)
		value = (ok and type(name) == "string") and name or nil
	end
	if type(value) ~= "string" or value == "" then return nil end

	if keyCodeLookup == nil then
		keyCodeLookup = {}
		local ok, items = pcall(function() return Enum.KeyCode:GetEnumItems() end)
		if ok and type(items) == "table" then
			for _, item in ipairs(items) do
				local okItem, itemName = pcall(function() return item.Name end)
				if okItem and type(itemName) == "string" then
					keyCodeLookup[string.lower(itemName)] = itemName
				end
			end
		end
	end

	local canonical = keyCodeLookup[string.lower(value)]
	if canonical == nil then
		--  tostring(EnumItem) is "Enum.KeyCode.Space" - exactly what the
		--  previous interface wrote into its configuration files (and what
		--  SetOpenKey(Enum.KeyCode.Space) stored) - and "KeyCode.Space" is
		--  the short form of the same thing.  Both are stripped down to the
		--  member name, so an old save still arms the bind instead of
		--  clearing it.
		local member = string.lower(value)
		member = member:match("^enum%.[%w]+%.(%w+)$") or member:match("^keycode%.(%w+)$")
		if member then canonical = keyCodeLookup[member] end
	end
	if canonical == nil then
		--  Codes added after this build, or environments that cannot
		--  enumerate the Enum, still resolve by their exact member name.
		local ok, code = pcall(function() return Enum.KeyCode[value] end)
		if ok and code then
			local okName, codeName = pcall(function() return code.Name end)
			if okName and type(codeName) == "string" then canonical = codeName end
		end
	end
	if canonical == nil or canonical == "Unknown" then return nil end
	return canonical
end

--  Keyboard ownership ----------------------------------------------------
--  While a TextBox owns the keyboard the menu must keep its hands off it:
--  typing the name of a configuration - including the spaces in it - has to
--  reach the field and nothing else.  The engine flags such keystrokes as
--  processed, but that flag is not reliable in every environment, so the
--  service is asked directly.
local function textBoxFocused()
	local ok, box = pcall(function()
		return UserInputService and UserInputService:GetFocusedTextBox()
	end)
	return ok and box ~= nil
end

--  Hands the keyboard back when the field that owned it goes away (the menu
--  is hidden, the settings flyout closes).  A box that is off screen but
--  still focused would swallow every keystroke, the open key included.
local function releaseTextBoxFocus()
	local ok, box = pcall(function()
		return UserInputService and UserInputService:GetFocusedTextBox()
	end)
	if ok and box then
		pcall(function() box:ReleaseFocus() end)
	end
end

--  A press that misses the field belongs to the interface, not to the text:
--  pressing Save (or a slider, or the window) has to hand the keyboard back.
--  A field that kept it swallowed every later keystroke - the open key and the
--  jump key included - until the engine cleared the focus on the next respawn,
--  which is why the game only became playable again after dying.
local function pressInsideTextBox(box, position)
	if not box or not position then return false end
	local ok, inside = pcall(function()
		local origin, size = box.AbsolutePosition, box.AbsoluteSize
		if not origin or not size then return false end
		--  a few pixels of slack, so the very edge still counts as the field
		local slack = 4
		return position.X >= origin.X - slack and position.X <= origin.X + size.X + slack
			and position.Y >= origin.Y - slack and position.Y <= origin.Y + size.Y + slack
	end)
	return ok and inside == true
end

--  The two moments that hand the keyboard back, so that neither dying nor
--  clicking the world is needed for the keys to reach the game again.  They are
--  registered with the first window and dropped in XClient:Destroy(), so a
--  destroyed interface never touches anybody's focus.
local focusWatchConnections = {}

local function watchKeyboardOwnership()
	if #focusWatchConnections > 0 or not UserInputService then return end

	local ok, connection = pcall(function()
		return UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch then return end
			local okBox, box = pcall(function()
				return UserInputService:GetFocusedTextBox()
			end)
			if not okBox or not box then return end
			--  a press in the text itself is the player selecting it: the
			--  field keeps the keyboard
			if pressInsideTextBox(box, input.Position) then return end
			pcall(function() box:ReleaseFocus() end)
		end)
	end)
	if ok and connection then
		focusWatchConnections[#focusWatchConnections + 1] = connection
	end

	--  A respawn hands the keyboard back as well: a field the player was typing
	--  into must not follow them into the next life.
	if LocalPlayer then
		local okPlayer, playerConnection = pcall(function()
			return LocalPlayer.CharacterAdded:Connect(releaseTextBoxFocus)
		end)
		if okPlayer and playerConnection then
			focusWatchConnections[#focusWatchConnections + 1] = playerConnection
		end
	end
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
	--  A string in any casing ("Q", "Space", "space") or an EnumItem is
	--  accepted; the canonical Enum.KeyCode member name is what gets stored.
	local current = resolveKeyName(opts.CurrentKeybind)
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
		fitLabel(box, width - 16, { MaxSize = 13, MinSize = 9 })
	end

	local function matches(input)
		local bind = api.CurrentKeybind
		if not bind or bind == "" then return false end
		return resolveKeyName(input.KeyCode) == bind
	end

	--  A bind is stored as the canonical Enum.KeyCode member name ("Q",
	--  "Space").  Values that are not KeyCodes are kept verbatim, the way they
	--  always were, and the "no key" placeholders collapse to an empty string.
	local function canonicalBind(value)
		local resolved = resolveKeyName(value)
		if resolved ~= nil then return resolved end
		if typeof(value) == "EnumItem" then return "" end
		local text = tostring(value or "")
		if text == "Enum.KeyCode.Unknown" then text = "" end
		return text
	end

	box.MouseButton1Click:Connect(function()
		--  Clicking the box starts a rebind, so the keyboard belongs to the
		--  menu again even if a text field had it a moment ago.
		releaseTextBoxFocus()
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
		--  A keystroke that is being typed into a text field (the name of a
		--  configuration, the search bar) is not a shortcut.
		if textBoxFocused() then return end
		if matches(input) then
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
		if matches(input) then
			held = false
			callSafe(opts.Callback, false)
		end
	end)

	function api:Set(newKeybind)
		newKeybind = canonicalBind(newKeybind)
		api.CurrentKeybind = newKeybind
		api.Value = newKeybind
		listening = false
		display()
		if opts.CallOnChange then
			callSafe(opts.Callback, newKeybind)
		end
		ctx.saveConfiguration()
	end

	--  updates the shown key without firing the callback and without saving;
	--  used when the bind is changed from somewhere else (XClient:SetOpenKey)
	function api:SetSilent(newKeybind)
		newKeybind = canonicalBind(newKeybind)
		api.CurrentKeybind = newKeybind
		api.Value = newKeybind
		listening = false
		display()
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
		--  UIGradient.Rotation is a clockwise rotation of the default
		--  left-to-right direction, so 90 runs top -> bottom: t=0 sits on the
		--  top edge.  The marker reads value 1 at the top (1 - val), so the
		--  shade has to be invisible up there and turn opaque black at the
		--  bottom.  The old 0 -> 1 sequence put the black at the top, which
		--  made the colour under the marker disagree with the picked value.
		create("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(0, 0, 0)),
			Transparency = NumberSequence.new(1, 0),
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

		--  Favourite colour slots (shared 3x3 palette) -------------------
		--  Clicking an empty slot stores the current colour; clicking a filled
		--  slot applies it back to the picker; Shift+click overwrites a filled
		--  slot with the current colour and right-click clears it.  The palette
		--  is shared by every picker and saved with the configuration.
		local slotSize, slotGap = 18, 6
		local slotOriginX, slotOriginY = 190, 24
		local slotFill = {}
		local function renderSlots()
			for i = 1, FAVORITE_SLOTS do
				local saved = XClient.FavoriteColors[i]
				local fillFrame = slotFill[i]
				if fillFrame then
					if typeof(saved) == "Color3" then
						fillFrame.BackgroundColor3 = saved
						fillFrame.Visible = true
					else
						fillFrame.Visible = false
					end
				end
			end
		end
		newText({
			Name = "FavoritesTitle",
			Text = "SAVED",
			Font = THEME_FONT_BOLD,
			TextSize = 10,
			TextColor3 = theme.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(slotSize * 3 + slotGap * 2, 12),
			Position = UDim2.fromOffset(slotOriginX, 8),
			Parent = popup,
		})
		for i = 1, FAVORITE_SLOTS do
			local col = (i - 1) % 3
			local row = math.floor((i - 1) / 3)
			local slot = create("TextButton", {
				Name = "Favorite" .. i,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = theme.Surface,
				Size = UDim2.fromOffset(slotSize, slotSize),
				Position = UDim2.fromOffset(slotOriginX + col * (slotSize + slotGap), slotOriginY + row * (slotSize + slotGap)),
				Parent = popup,
			})
			addCorner(slot, UDim.new(0, 4))
			addStroke(slot, theme.StrokeSoft, 1, 0)
			local fillFrame = newFrame({
				Name = "Fill",
				BackgroundColor3 = theme.Surface,
				Size = UDim2.new(1, -4, 1, -4),
				Position = UDim2.fromOffset(2, 2),
				Visible = false,
				Parent = slot,
			})
			addCorner(fillFrame, UDim.new(0, 3))
			slotFill[i] = fillFrame

			slot.MouseButton1Click:Connect(function()
				local saved = XClient.FavoriteColors[i]
				if typeof(saved) == "Color3" then
					local overwriting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
						or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
					if not overwriting then
						api:Set(saved)
						return
					end
				end
				XClient.FavoriteColors[i] = color
				renderSlots()
				ctx.saveConfiguration()
			end)
			slot.MouseButton2Click:Connect(function()
				XClient.FavoriteColors[i] = nil
				renderSlots()
				ctx.saveConfiguration()
			end)
		end
		renderSlots()

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
					--  the drag is over: stop listening and forget the handlers
					untrackConnection(ctx, moved)
					untrackConnection(ctx, ended)
					moved:Disconnect()
					ended:Disconnect()
					callSafe(opts.Callback, color)
					ctx.saveConfiguration()
				end
			end)
			trackConnection(ctx, moved)
			trackConnection(ctx, ended)
		end

		sv.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				--  Read the cursor from GetMouseLocation (the same source the drag
				--  uses) instead of input.Position.  input.Position for the mouse
				--  is shifted by the topbar inset, so the first click landed the
				--  marker ~36px below the actual cursor.
				local pos = UserInputService:GetMouseLocation()
				updateSv(pos.X, pos.Y)
				drag(updateSv)
			end
		end)

		hueBar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local pos = UserInputService:GetMouseLocation()
				updateHue(pos.X)
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
		openPopup(ctx, swatch, 266, 184, function(popupFrame)
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
	fitLabel(title, (tonumber(ctx.rowWidth) or ROW_WIDTH) - 12, { MinSize = 9 })

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
		fitLabel(title, (tonumber(ctx.rowWidth) or ROW_WIDTH) - 12, { MaxSize = 12, MinSize = 9 })
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
	fitLabel(title, (tonumber(ctx.rowWidth) or ROW_WIDTH) - (iconImage and 46 or 28), { MinSize = 9, Wrap = true })

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
		fitLabel(title, (tonumber(ctx.rowWidth) or ROW_WIDTH) - (iconLabel.Visible and 46 or 28), { MaxSize = 13, MinSize = 9, Wrap = true })
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

--  GroupBox --------------------------------------------------------------
--  A Neverlose style card: a bluish tinted container with a caption and a
--  hairline header that lays out the elements added to it.  It is a
--  *container*, not a row - everything a tab can build goes inside:
--
--      local Group = Tab:CreateGroupBox({
--          Name = "Aim",
--          Elements = {
--              { Type = "Toggle", Name = "Enabled",  Flag = "aimEnabled" },
--              { Type = "Slider", Name = "FOV", Range = { 1, 180 }, Flag = "aimFov" },
--              "Advanced",                       -- a plain string is a section
--              { Type = "Toggle", Name = "Auto fire", Flag = "aimAutoFire" },
--          },
--      })
--      Group:Add({ Type = "Toggle", Name = "Extra", Flag = "aimExtra" })
--
--  The nested elements keep the exact same contract they have on a tab: they
--  return their settings table, register their own flag and are picked up by
--  the configuration system on their own.  The whole group works inside a
--  module's settings flyout too, and there is no depth limit, so a GroupBox
--  can hold another GroupBox (the sub-cards are drawn flat, one level in).
local GROUPBOX_PADDING = 8
local GROUPBOX_GAP = 6
local GROUPBOX_HEADER = 22
--  Horizontal space a nested element loses to the card (padding on both sides
--  plus a hair of breathing room), so captions wrapped inside the group are
--  fitted against the narrower width instead of the page width.
local GROUPBOX_INSET = GROUPBOX_PADDING * 2 + 4

--  The bluish card tint: the palette's elevated surface pulled 12% towards its
--  accent and then nudged towards blue.  The three themes keep their own
--  identity (Neverlose reads blue, Midnight purple-blue, Blood a muted maroon)
--  while every group still reads as the Neverlose style card.
local function groupBoxColor(theme)
	local base = theme.SurfaceAlt or theme.Surface
	local accent = theme.Accent or base
	local r = base.R + (accent.R - base.R) * 0.12
	local g = base.G + (accent.G - base.G) * 0.12
	local b = base.B + (accent.B - base.B) * 0.12
	return Color3.new(
		math.clamp(r * 0.92 + 0.012, 0, 1),
		math.clamp(g * 0.96 + 0.030, 0, 1),
		math.clamp(b * 0.98 + 0.060, 0, 1)
	)
end

function builders.GroupBox(container, ctx, opts)
	opts = opts or {}
	local theme = ctx.theme()
	local title = tostring(opts.Name or opts.Title or "")

	local holder = newFrame({
		Name = "GroupBox",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = container,
	})

	local card = newFrame({
		Name = "Card",
		BackgroundColor3 = groupBoxColor(theme),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = holder,
	})
	addCorner(card, UDim.new(0, 8))
	addStroke(card, theme.Stroke, 1, 0.2)
	addPadding(card, GROUPBOX_PADDING)
	addList(card, { Padding = UDim.new(0, GROUPBOX_GAP) })

	local header = newFrame({
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, GROUPBOX_HEADER),
		Parent = card,
	})
	local headerText = newText({
		Name = "Title",
		Text = title,
		TextSize = 13,
		Font = THEME_FONT_BOLD,
		TextColor3 = theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 15),
		Position = UDim2.new(0, 2, 0, 0),
		Parent = header,
	})
	--  Hairline separating the caption from the body.  It lives inside the
	--  header (not the card) so the card's UIListLayout never lays it out.
	newFrame({
		Name = "Line",
		BackgroundColor3 = theme.StrokeSoft,
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -2),
		Parent = header,
	})
	local function fitTitle()
		fitLabel(headerText, math.max(48, (tonumber(ctx.rowWidth) or ROW_WIDTH) - GROUPBOX_INSET), { MinSize = 10 })
	end
	fitTitle()

	local body = newFrame({
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	addList(body, { Padding = UDim.new(0, GROUPBOX_GAP) })

	local api = {
		Type = "GroupBox",
		Name = title,
		Element = holder,   -- what the topbar search shows / hides
		Holder = holder,
		Card = card,
		Body = body,
		Title = headerText,
		Elements = {},
	}

	--  Every element that registered a flag is reached through the built
	--  element tables (nested groups included), which is exactly what a
	--  snapshot of the group needs to walk.
	local function forEachFlagged(elements, fn)
		for _, element in ipairs(elements or {}) do
			if type(element) == "table" then
				if element.Flag then fn(element) end
				if element.Elements then forEachFlagged(element.Elements, fn) end
			end
		end
	end

	--  Reads an element's saved value using the same shapes serializeFlags()
	--  writes to the configuration (see section 7), so a group snapshot and a
	--  configuration file speak the same language.
	local function elementValue(element)
		local elementType = element.Type
		if elementType == "ColorPicker" then
			local color = element.Color or Color3.fromRGB(255, 255, 255)
			return {
				R = math.floor(color.R * 255 + 0.5),
				G = math.floor(color.G * 255 + 0.5),
				B = math.floor(color.B * 255 + 0.5),
			}
		elseif elementType == "Toggle" then
			return element.CurrentValue and true or false
		elseif elementType == "Dropdown" then
			local copy = {}
			for i, option in ipairs(element.CurrentOption or {}) do copy[i] = option end
			return copy
		elseif elementType == "Keybind" then
			return tostring(element.CurrentKeybind or "")
		elseif elementType == "Input" then
			return tostring(element.CurrentValue or "")
		elseif elementType == "Slider" then
			return element.CurrentValue
		elseif type(element.Serialize) == "function" then
			local ok, serialized = pcall(element.Serialize, element)
			if ok then return serialized end
		end
		return nil
	end

	--  Builds one child descriptor the same way buildModuleSettings resolves a
	--  Settings entry: a table with a Type (defaulting to Toggle) or a plain
	--  string for a section.  The page width is swapped for the card's inner
	--  width - and OnCard is raised - while the child is built, so caption
	--  fitting (and therefore wrapping) uses the narrower space and the row
	--  lands flat on the card.
	local function buildChild(child)
		local previousWidth = ctx.rowWidth
		local previousOnCard = ctx.onCard
		ctx.rowWidth = math.max(120, (previousWidth or ROW_WIDTH) - GROUPBOX_INSET)
		ctx.onCard = true
		local ok, built
		if type(child) == "string" then
			ok, built = pcall(builders.Section, body, ctx, child)
		elseif type(child) == "table" then
			local elementType = child.Type or "Toggle"
			local builder = builders[elementType]
			if type(builder) == "function" then
				ok, built = pcall(builder, body, ctx, child)
			else
				ok, built = false, "unsupported element type '" .. tostring(elementType) .. "'"
			end
		else
			ok, built = false, "unsupported group entry (" .. type(child) .. ")"
		end
		ctx.rowWidth = previousWidth
		ctx.onCard = previousOnCard
		if not ok then
			warn("[XClient] GroupBox: " .. tostring(built))
			return nil
		end
		if type(built) == "table" then
			api.Elements[#api.Elements + 1] = built
		end
		return built
	end

	function api:Add(child)
		return buildChild(child)
	end

	function api:AddMany(list)
		local added = {}
		if type(list) ~= "table" then return added end
		for _, child in ipairs(list) do
			added[#added + 1] = buildChild(child)
		end
		return added
	end

	--  Removes every nested element and forgets the flags they had registered,
	--  so a cleared group stops writing values for rows that no longer exist.
	function api:Clear()
		forEachFlagged(api.Elements, function(element)
			if ctx.flags[element.Flag] == element then ctx.flags[element.Flag] = nil end
			if XClient.Flags[element.Flag] == element then XClient.Flags[element.Flag] = nil end
		end)
		body:ClearAllChildren()
		addList(body, { Padding = UDim.new(0, GROUPBOX_GAP) })
		api.Elements = {}
		return api
	end

	function api:SetTitle(newTitle)
		newTitle = tostring(newTitle or "")
		api.Name = newTitle
		headerText.Text = newTitle
		fitTitle()
		return api
	end

	function api:Set(newSettings)
		if type(newSettings) ~= "table" then return api end
		if newSettings.Name ~= nil or newSettings.Title ~= nil then
			api:SetTitle(newSettings.Name or newSettings.Title)
		end
		if type(newSettings.Elements) == "table" then
			api:Clear()
			api:AddMany(newSettings.Elements)
		end
		return api
	end

	--  Snapshot of every flagged element in the group as a flat flag -> value
	--  map, e.g. to keep named presets of a single card.  :Load applies it
	--  back through the normal :Set entry point, so callbacks and auto-save
	--  behave exactly like a manual change.
	function api:Serialize()
		local data = {}
		forEachFlagged(api.Elements, function(element)
			local value = elementValue(element)
			if value ~= nil then data[element.Flag] = value end
		end)
		return data
	end

	function api:Load(values)
		if type(values) ~= "table" then return api end
		forEachFlagged(api.Elements, function(element)
			if type(element.Set) == "function" and values[element.Flag] ~= nil then
				local value = values[element.Flag]
				if element.Type == "ColorPicker" and type(value) == "table" then
					value = Color3.fromRGB(
						tonumber(value.R) or 255,
						tonumber(value.G) or 255,
						tonumber(value.B) or 255
					)
				end
				callSafe(function() return element:Set(value) end)
			end
		end)
		return api
	end

	--  Children may be handed over up front through Elements; Settings is
	--  accepted as well, so a GroupBox reads naturally when dropped into a
	--  module's Settings list.  Add / AddMany fill the card later.
	api:AddMany(opts.Elements or opts.Settings or {})

	return api
end


--=========================================================================
--  9b. EXTRA WIDGETS
--  Interactive viewers that go beyond plain controls: a character readout
--  (PlayerWidget), a picture with markers (Image), a crosshair / FOV pad, a
--  live graph, progress, a stepper, segments, a wheel, an analog stick, a
--  radar and chips.
--  Every builder below keeps the contract of the ones above: it is called as
--  (container, ctx, opts), returns the settings table and registers its flag,
--  so these widgets also work inside a module's Settings flyout.
--=========================================================================

--  Canonical character regions shared by PlayerWidget / Image.
local PLAYER_REGIONS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local REGION_ALIASES = {
	head = "Head",
	torso = "Torso", chest = "Torso", body = "Torso", core = "Torso", upper = "Torso",
	leftarm = "LeftArm", la = "LeftArm", armleft = "LeftArm", left = "LeftArm",
	rightarm = "RightArm", ra = "RightArm", armright = "RightArm", right = "RightArm",
	leftleg = "LeftLeg", ll = "LeftLeg", legleft = "LeftLeg",
	rightleg = "RightLeg", rl = "RightLeg", legright = "RightLeg",
	all = "*", every = "*", everything = "*", any = "*",
}
local function canonicalRegion(name)
	local key = tostring(name or ""):gsub("[%s_%-]", ""):lower()
	return REGION_ALIASES[key] or tostring(name or "")
end

--  Nested option tables such as
--      widget.Highlight.Torso = true
--      widget.Skin.Head = Color3.fromRGB(240, 200, 60)
--      picture.Marker.Torso = true
--  write into a backing store and notify the widget, which repaints itself.
--  That is what makes the picture react to the variable.
local function reactiveWidgetTable(store, onChange)
	local proxy = {}
	setmetatable(proxy, {
		__index = function(_, key)
			local resolved = canonicalRegion(key)
			if store[resolved] ~= nil then return store[resolved] end
			return store[key]
		end,
		__newindex = function(_, key, value)
			local resolved = canonicalRegion(key)
			store[resolved] = value
			if onChange then onChange(resolved, value) end
		end,
	})
	return proxy
end

--  Default normalised marker points for the Image widget (rough R6 layout).
local IMAGE_MARKER_POINTS = {
	Head = { 0.5, 0.12 },
	Torso = { 0.5, 0.42 },
	LeftArm = { 0.24, 0.42 },
	RightArm = { 0.76, 0.42 },
	LeftLeg = { 0.4, 0.82 },
	RightLeg = { 0.6, 0.82 },
}

--  Every viewer widget is a module row plus a stage below it.
local function widgetStage(container, ctx, opts, stageHeight)
	local theme = ctx.theme()
	local wrapper = newFrame({
		Name = opts.Name or "Widget",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT + stageHeight + 6),
		Parent = container,
	})
	local base = newRow(wrapper, ctx, opts)
	local stage = newFrame({
		Name = "Stage",
		BackgroundColor3 = theme.SurfaceAlt,
		Size = UDim2.new(1, 0, 0, stageHeight),
		Position = UDim2.fromOffset(0, ROW_HEIGHT + 6),
		Parent = wrapper,
	})
	addCorner(stage, UDim.new(0, 6))
	addStroke(stage, theme.StrokeSoft, 1, 0.3)
	--  handy for scripts: widget.Stage is the frame under the module row
	opts.Stage = stage
	return base, stage, wrapper
end

--  Shared caption label inside a stage (status / hint lines).
local function stageCaption(stage, text, ctx)
	local label = newText({
		Name = "Caption",
		Text = tostring(text or ""),
		TextSize = 11,
		TextColor3 = ctx.theme().TextMuted,
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.new(0, 10, 1, -22),
		Parent = stage,
	})
	fitLabel(label, (tonumber(ctx.rowWidth) or ROW_WIDTH) - 24, { MaxSize = 12, MinSize = 9 })
	return label
end
--  PlayerWidget -----------------------------------------------------------
--  An interactive R6 style character: every body part is a picture *and* a
--  variable, so a module can drive anything from it and the picture follows.
--      local widget = Tab:CreatePlayerWidget({ Name = "Skin", Flag = "skin" })
--      widget.Highlight.Torso = true          -- widget.Highlight.torso too
--      widget.Skin.Head = Color3.fromRGB(255, 210, 80)
--      widget:SetRegion("LeftLeg", true)
--      widget.Highlight.All = false           -- clears every highlight
--      print(widget.Highlight.Torso, widget:GetSelection()[1])
function builders.PlayerWidget(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base, stage = widgetStage(container, ctx, opts, tonumber(opts.Height) or 166)

	--  The settings table handed in by the caller is the element (as always).
	local api = opts
	api.Type = "PlayerWidget"
	api.Row = base.row
	api.Base = base
	api.Element = stage
	api.Regions = {}
	for index, region in ipairs(PLAYER_REGIONS) do api.Regions[index] = region end
	--  grab the requested selection before api.Selected is replaced, because
	--  the settings table handed in by the caller *is* the element (api == opts)
	local initialSelection = opts.Selected or opts.CurrentValue
	api.Selected = {}

	local allowMultiple = opts.AllowMultiple ~= false
	local state = {}     -- region -> true
	local colors = {}    -- region -> Color3
	local parts = {}     -- region -> button
	local strokes = {}   -- region -> stroke

	local function applySkinValue(name, color)
		local target = canonicalRegion(name)
		if target == "*" then
			for _, region in ipairs(PLAYER_REGIONS) do colors[region] = color end
		else
			colors[target] = color
		end
	end

	if opts.Skin ~= nil then
		if typeof(opts.Skin) == "Color3" then
			applySkinValue("*", opts.Skin)
		elseif type(opts.Skin) == "table" then
			for key, value in pairs(opts.Skin) do
				if typeof(value) == "Color3" then applySkinValue(key, value) end
			end
		end
	end
	for _, region in ipairs(PLAYER_REGIONS) do
		if colors[region] == nil then colors[region] = theme.Surface end
	end

	local rig = newFrame({
		Name = "Rig",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(132, 116),
		Position = UDim2.new(0.5, 0, 0, 6),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = stage,
	})

	--  x, y, width, height inside the 132 x 116 rig
	local LAYOUT = {
		Head     = { 49, 0, 34, 30 },
		Torso    = { 45, 34, 42, 44 },
		LeftArm  = { 25, 36, 16, 42 },
		RightArm = { 91, 36, 16, 42 },
		LeftLeg  = { 47, 82, 18, 34 },
		RightLeg = { 67, 82, 18, 34 },
	}

	for _, region in ipairs(PLAYER_REGIONS) do
		local spec = LAYOUT[region]
		local part = create("TextButton", {
			Name = region,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = colors[region],
			Size = UDim2.fromOffset(spec[3], spec[4]),
			Position = UDim2.fromOffset(spec[1], spec[2]),
			Parent = rig,
		})
		addCorner(part, UDim.new(0, region == "Head" and 8 or 5))
		strokes[region] = addStroke(part, theme.Stroke, 1, 0.2)
		parts[region] = part

		part.MouseEnter:Connect(function()
			tween(part, 0.1, { BackgroundTransparency = 0.3 })
		end)
		part.MouseLeave:Connect(function()
			tween(part, 0.1, { BackgroundTransparency = state[region] and 0.15 or 0 })
		end)
		part.MouseButton1Click:Connect(function()
			local on = not (state[region] and true or false)
			api:SetRegion(region, on)
			callSafe(opts.Callback, region, on, api)
			callSafe(opts.OnRegionChanged, region, on, api)
			ctx.saveConfiguration()
		end)
	end

	local caption = stageCaption(stage, "Selected: none", ctx)

	local function paint()
		local selected = api.Selected
		for index = #selected, 1, -1 do selected[index] = nil end
		for _, region in ipairs(PLAYER_REGIONS) do
			local on = state[region] and true or false
			local part = parts[region]
			part.BackgroundColor3 = on and theme.Accent or colors[region]
			part.BackgroundTransparency = on and 0.15 or 0
			local stroke = strokes[region]
			stroke.Color = on and theme.Accent or theme.Stroke
			stroke.Thickness = on and 2 or 1
			stroke.Transparency = on and 0 or 0.2
			if on then selected[#selected + 1] = region end
		end
		api.Selected = selected
		api.CurrentValue = selected
		api.Value = selected
		caption.Text = #selected > 0 and ("Selected: " .. table.concat(selected, ", ")) or "Selected: none"
		fitLabel(caption, (tonumber(ctx.rowWidth) or ROW_WIDTH) - 24, { MaxSize = 12, MinSize = 9 })
	end
	--  Live variables: writing to them repaints the character straight away.
	api.Highlight = reactiveWidgetTable(state, function(region, value)
		if region == "*" then
			for _, entry in ipairs(PLAYER_REGIONS) do state[entry] = value and true or nil end
		end
		paint()
	end)
	api.Skin = reactiveWidgetTable(colors, function(region, value)
		if region == "*" then
			for _, entry in ipairs(PLAYER_REGIONS) do colors[entry] = value end
		end
		paint()
	end)

	function api:SetRegion(name, on)
		local region = canonicalRegion(name)
		if region == "*" then
			for _, entry in ipairs(PLAYER_REGIONS) do state[entry] = on and true or nil end
		elseif LAYOUT[region] then
			if on and not allowMultiple then
				for _, entry in ipairs(PLAYER_REGIONS) do state[entry] = nil end
			end
			state[region] = on and true or nil
		end
		paint()
		return api
	end

	function api:GetRegion(name)
		return state[canonicalRegion(name)] and true or false
	end

	function api:SetSkin(name, color)
		applySkinValue(name, color)
		paint()
		return api
	end

	function api:GetSkin(name)
		return colors[canonicalRegion(name)]
	end

	function api:GetSelection()
		local copy = {}
		for index, region in ipairs(api.Selected) do copy[index] = region end
		return copy
	end

	function api:Clear()
		for _, region in ipairs(PLAYER_REGIONS) do state[region] = nil end
		paint()
		return api
	end

	function api:Refresh()
		paint()
		return api
	end

	function api:Serialize()
		return api:GetSelection()
	end

	--  :Set accepts the array a configuration stores, a single region name or
	--  { Regions = { ... } / Highlight = { ... }, Skin = { ... } }
	function api:ApplyValue(value)
		local list = value
		if type(value) == "table" then
			if value.Regions ~= nil then
				list = value.Regions
			elseif value.Highlight ~= nil then
				list = value.Highlight
			end
			if type(value.Skin) == "table" then
				for key, color in pairs(value.Skin) do
					if typeof(color) == "Color3" then applySkinValue(key, color) end
				end
			end
		end
		if list ~= nil then
			for _, region in ipairs(PLAYER_REGIONS) do state[region] = nil end
			if type(list) == "string" then list = { list } end
			if type(list) == "table" then
				for key, entry in pairs(list) do
					local name = type(key) == "number" and entry or key
					local on = type(key) == "number" and true or (entry and true or false)
					local region = canonicalRegion(name)
					if region == "*" then
						for _, item in ipairs(PLAYER_REGIONS) do state[item] = on and true or nil end
					elseif LAYOUT[region] then
						state[region] = on and true or nil
					end
				end
			end
		end
		paint()
		return api
	end

	function api:SetSilent(value)
		api:ApplyValue(value)
		return api
	end

	function api:Set(value)
		api:ApplyValue(value)
		callSafe(opts.Callback, api:GetSelection(), nil, api)
		ctx.saveConfiguration()
		return api
	end

	api:ApplyValue(initialSelection)
	registerFlag(ctx, opts, api.Selected, "PlayerWidget", api)
	return api
end
--  Crosshair / FOV pad ----------------------------------------------------
--      Tab:CreateCrosshair({ Name = "Aim FOV", Flag = "fov", FOV = 90,
--          MaxFOV = 360, Dot = { X = 0.1, Y = -0.2 },
--          Callback = function(value) end })   -- { FOV = , X = , Y = }
--      crosshair.FOV = 120      crosshair:SetOffset(0, 0.5)
--      crosshair:Set({ FOV = 45, X = 0, Y = 0 })
--  Drag inside the pad to move the dot, the circle is the field of view.
function builders.Crosshair(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base, stage = widgetStage(container, ctx, opts, tonumber(opts.Height) or 156)
	local padSize = tonumber(opts.PadSize) or 108

	local pad = newFrame({
		Name = "Pad",
		BackgroundColor3 = theme.Surface,
		Size = UDim2.fromOffset(padSize, padSize),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = stage,
	})
	addCorner(pad, UDim.new(0, 6))
	addStroke(pad, theme.StrokeSoft, 1, 0.2)

	local ring = newFrame({
		Name = "FOV",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = pad,
	})
	addCorner(ring, UDim.new(1, 0))
	addStroke(ring, theme.Accent, 1, 0.35)

	--  procedural crosshair: four ticks around the centre
	local ticks = {}
	for index = 1, 4 do
		local vertical = index <= 2
		ticks[index] = newFrame({
			Name = "Tick" .. index,
			BackgroundColor3 = theme.Text,
			Size = vertical and UDim2.fromOffset(1.5, 9) or UDim2.fromOffset(9, 1.5),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = pad,
		})
	end
	local dot = newFrame({
		Name = "Dot",
		BackgroundColor3 = theme.Accent,
		Size = UDim2.fromOffset(6, 6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = pad,
	})
	addCorner(dot, UDim.new(1, 0))

	local caption = stageCaption(stage, "", ctx)

	--  The settings table handed in by the caller is the element (as always).
	local api = opts
	api.Type = "Crosshair"
	api.Row = base.row
	api.Base = base
	api.Element = pad
	api.MaxFOV = tonumber(opts.MaxFOV) or 360
	api.FOV = math.clamp(tonumber(opts.FOV) or 90, 0, api.MaxFOV)
	--  read the requested dot before api.Dot replaces it (api == opts)
	local initialDot = type(opts.Dot) == "table" and opts.Dot or nil
	api.Dot = { X = 0, Y = 0 }
	if initialDot then
		api.Dot.X = math.clamp(tonumber(initialDot.X) or 0, -1, 1)
		api.Dot.Y = math.clamp(tonumber(initialDot.Y) or 0, -1, 1)
	end
	api.CurrentValue = { FOV = api.FOV, X = api.Dot.X, Y = api.Dot.Y }
	api.Value = api.CurrentValue

	local function paint()
		local ratio = api.MaxFOV > 0 and (api.FOV / api.MaxFOV) or 0
		local diameter = math.max(12, 12 + ratio * (padSize - 26))
		ring.Size = UDim2.fromOffset(diameter, diameter)
		local spread = 6 + ratio * 13
		for index, tick in ipairs(ticks) do
			local sign = (index % 2 == 0) and 1 or -1
			if index <= 2 then
				tick.Position = UDim2.new(0.5, 0, 0.5, sign * spread)
			else
				tick.Position = UDim2.new(0.5, sign * spread, 0.5, 0)
			end
		end
		dot.Position = UDim2.new(0.5, api.Dot.X * (padSize / 2 - 10), 0.5, api.Dot.Y * (padSize / 2 - 10))
		api.CurrentValue = { FOV = api.FOV, X = api.Dot.X, Y = api.Dot.Y }
		api.Value = api.CurrentValue
		caption.Text = string.format("FOV %d | X %.2f | Y %.2f", math.floor(api.FOV + 0.5), api.Dot.X, api.Dot.Y)
		fitLabel(caption, (tonumber(ctx.rowWidth) or ROW_WIDTH) - 24, { MaxSize = 12, MinSize = 9 })
	end

	local dragging = false
	local function updateFromPosition(position)
		local abs = pad.AbsolutePosition or Vector2.new(0, 0)
		local size = pad.AbsoluteSize
		local width = (size and size.X and size.X > 0) and size.X or padSize
		local height = (size and size.Y and size.Y > 0) and size.Y or padSize
		local x = math.clamp(((position.X - abs.X) / width - 0.5) * 2, -1, 1)
		local y = math.clamp(((position.Y - abs.Y) / height - 0.5) * 2, -1, 1)
		api:SetOffset(x, y)
	end

	pad.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromPosition(input.Position)
		end
	end)
	ctx.connections[#ctx.connections + 1] = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromPosition(input.Position)
		end
	end)
	ctx.connections[#ctx.connections + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	function api:SetFOV(value, silent)
		api.FOV = math.clamp(tonumber(value) or 0, 0, api.MaxFOV)
		paint()
		if not silent then
			callSafe(opts.Callback, api.CurrentValue)
			ctx.saveConfiguration()
		end
		return api
	end

	function api:SetOffset(x, y, silent)
		api.Dot = {
			X = math.clamp(tonumber(x) or 0, -1, 1),
			Y = math.clamp(tonumber(y) or 0, -1, 1),
		}
		paint()
		if not silent then
			callSafe(opts.Callback, api.CurrentValue)
			ctx.saveConfiguration()
		end
		return api
	end

	function api:GetFOV()
		return api.FOV
	end

	function api:Serialize()
		return { FOV = api.FOV, X = api.Dot.X, Y = api.Dot.Y }
	end

	function api:Set(value, silent)
		if type(value) == "table" then
			if value.FOV ~= nil then api.FOV = math.clamp(tonumber(value.FOV) or 0, 0, api.MaxFOV) end
			if value.X ~= nil or value.Y ~= nil then
				api.Dot = {
					X = math.clamp(tonumber(value.X) or api.Dot.X, -1, 1),
					Y = math.clamp(tonumber(value.Y) or api.Dot.Y, -1, 1),
				}
			end
		elseif type(value) == "number" then
			api.FOV = math.clamp(value, 0, api.MaxFOV)
		end
		paint()
		if not silent then
			callSafe(opts.Callback, api.CurrentValue)
			ctx.saveConfiguration()
		end
		return api
	end

	function api:SetSilent(value)
		return api:Set(value, true)
	end

	paint()
	registerFlag(ctx, opts, api.CurrentValue, "Crosshair", api)
	return api
end
--  Live graph -------------------------------------------------------------
--      local graph = Tab:CreateGraph({ Name = "Ping", Max = 300, Samples = 40 })
--      graph:Push(42)      graph:Set(120)      graph:Clear()
--      print(graph.CurrentValue, graph:GetValues()[1])
function builders.Graph(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base, stage = widgetStage(container, ctx, opts, tonumber(opts.Height) or 76)
	local samples = math.max(4, tonumber(opts.Samples) or 40)
	local min = tonumber(opts.Min) or 0
	local max = tonumber(opts.Max) or 100
	if max <= min then max = min + 1 end
	local height = tonumber(opts.GraphHeight) or 44
	local gap = 2

	local plot = newFrame({
		Name = "Plot",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, height),
		Position = UDim2.fromOffset(10, 8),
		Parent = stage,
	})

	local bars = {}
	for index = 1, samples do
		local bar = newFrame({
			Name = "Bar" .. index,
			BackgroundColor3 = theme.Accent,
			Size = UDim2.new(1 / samples, -gap, 0, 2),
			Position = UDim2.new((index - 1) / samples, gap * 0.5, 1, 0),
			AnchorPoint = Vector2.new(0, 1),
			Parent = plot,
		})
		addCorner(bar, UDim.new(0, 2))
		bars[index] = bar
	end

	local caption = stageCaption(stage, "", ctx)
	local values = {}
	for index = 1, samples do values[index] = min end

	--  The settings table handed in by the caller is the element (as always).
	local api = opts
	api.Type = "Graph"
	api.Row = base.row
	api.Base = base
	api.Element = plot
	api.Samples = samples
	api.Min = min
	api.Max = max

	local function paint()
		local span = max - min
		for index, bar in ipairs(bars) do
			local ratio = math.clamp((values[index] - min) / span, 0, 1)
			local pixels = math.max(1, math.floor(ratio * height + 0.5))
			bar.Size = UDim2.new(1 / samples, -gap, 0, pixels)
			bar.BackgroundColor3 = ratio > 0.66 and theme.Danger or (ratio > 0.33 and theme.Accent or theme.Success)
		end
		api.CurrentValue = values[samples]
		api.Value = api.CurrentValue
		caption.Text = string.format("now %.2f | range %s - %s | %d samples", api.CurrentValue or 0, tostring(min), tostring(max), samples)
		fitLabel(caption, (tonumber(ctx.rowWidth) or ROW_WIDTH) - 24, { MaxSize = 12, MinSize = 9 })
	end

	local function shift(newValue)
		for index = 1, samples - 1 do values[index] = values[index + 1] end
		values[samples] = math.clamp(tonumber(newValue) or min, min, max)
		paint()
	end

	function api:Push(newValue)
		shift(newValue)
		callSafe(opts.Callback, api.CurrentValue)
		ctx.saveConfiguration()
		return api
	end

	function api:Set(newValue)
		return api:Push(newValue)
	end

	function api:SetSilent(newValue)
		shift(newValue)
		return api
	end

	function api:Clear()
		for index = 1, samples do values[index] = min end
		paint()
		return api
	end

	function api:GetValues()
		local copy = {}
		for index = 1, samples do copy[index] = values[index] end
		return copy
	end

	function api:Serialize()
		return api.CurrentValue
	end

	paint()
	registerFlag(ctx, opts, api.CurrentValue, "Graph", api)
	return api
end
--  Progress / loader ------------------------------------------------------
--      local loader = Tab:CreateProgress({ Name = "Loading", Flag = "load",
--          Min = 0, Max = 100, Indeterminate = true })
--      loader:Set(40)     loader:Tween(100, 0.6)     loader:Stop()
--  Without Min/Max the value is a plain 0 - 1 fraction.
function builders.Progress(container, ctx, opts)
	local rawMin, rawMax = opts and opts.Min, opts and opts.Max
	if opts and type(opts.Range) == "table" then
		rawMin = rawMin or opts.Range[1]
		rawMax = rawMax or opts.Range[2]
	end
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base, stage = widgetStage(container, ctx, opts, tonumber(opts.Height) or 86)
	local min = tonumber(rawMin) or 0
	local max = tonumber(rawMax) or 1
	if max <= min then max = min + 1 end
	local value = math.clamp(tonumber(opts.CurrentValue) or min, min, max)
	local width = tonumber(opts.Width) or 210
	local barHeight = tonumber(opts.BarHeight) or 8

	local track = newFrame({
		Name = "Track",
		BackgroundColor3 = theme.SliderTrack,
		Size = UDim2.fromOffset(width, barHeight),
		Position = UDim2.fromOffset(10, 18),
		Parent = stage,
	})
	addCorner(track, UDim.new(1, 0))
	local fill = newFrame({
		Name = "Fill",
		BackgroundColor3 = theme.Accent,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = track,
	})
	addCorner(fill, UDim.new(1, 0))
	local shimmer = newFrame({
		Name = "Shimmer",
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.5,
		Size = UDim2.new(0, 46, 1, 0),
		Position = UDim2.new(0, -60, 0, 0),
		Parent = track,
	})
	addCorner(shimmer, UDim.new(1, 0))
	local percentText = newText({
		Name = "Percent",
		Text = "0%",
		TextSize = 12,
		Font = THEME_FONT_BOLD,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(70, 16),
		Position = UDim2.new(1, -10, 0, 14),
		Parent = stage,
	})
	local caption = stageCaption(stage, "", ctx)

	--  The settings table handed in by the caller is the element (as always).
	local api = opts
	api.Type = "Progress"
	api.Row = base.row
	api.Base = base
	api.Element = track
	api.Min = min
	api.Max = max
	api.CurrentValue = value
	api.Value = value
	api.Running = false

	local shimmerTween
	local function paintText()
		local alpha = math.clamp((value - min) / (max - min), 0, 1)
		api.CurrentValue = value
		api.Value = value
		percentText.Text = string.format("%d%%", math.floor(alpha * 100 + 0.5))
		caption.Text = api.Running and "loading..." or string.format("%s / %s", tostring(value), tostring(max))
		fitLabel(caption, (tonumber(ctx.rowWidth) or ROW_WIDTH) - 24, { MaxSize = 12, MinSize = 9 })
	end

	local function paint(animate, time)
		local alpha = math.clamp((value - min) / (max - min), 0, 1)
		if animate then
			tween(fill, time or 0.25, { Size = UDim2.new(alpha, 0, 1, 0) })
		else
			fill.Size = UDim2.new(alpha, 0, 1, 0)
		end
		paintText()
	end

	--  indeterminate mode keeps a bright segment sweeping the bar; the tween
	--  loops inside the engine, so no Lua loop is left running
	function api:Start()
		if shimmerTween or not TweenService then return api end
		api.Running = true
		pcall(function()
			local info = TweenInfo.new(1.1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false)
			shimmerTween = TweenService:Create(shimmer, info, { Position = UDim2.new(1, 10, 0, 0) })
			shimmerTween:Play()
		end)
		paintText()
		return api
	end

	function api:Stop()
		api.Running = false
		if shimmerTween then
			pcall(function() shimmerTween:Cancel() end)
			shimmerTween = nil
		end
		shimmer.Position = UDim2.new(0, -60, 0, 0)
		paintText()
		return api
	end

	function api:Set(newValue, silent)
		value = math.clamp(tonumber(newValue) or min, min, max)
		paint(true, 0.25)
		if not silent then
			callSafe(opts.Callback, value)
			ctx.saveConfiguration()
		end
		return api
	end

	function api:SetSilent(newValue)
		return api:Set(newValue, true)
	end

	function api:SetRatio(alpha, silent)
		return api:Set(min + (max - min) * math.clamp(tonumber(alpha) or 0, 0, 1), silent)
	end

	function api:Tween(target, time, silent)
		local targetValue = math.clamp(tonumber(target) or min, min, max)
		local alpha = math.clamp((targetValue - min) / (max - min), 0, 1)
		value = targetValue
		tween(fill, tonumber(time) or 0.4, { Size = UDim2.new(alpha, 0, 1, 0) })
		paintText()
		if not silent then
			callSafe(opts.Callback, value)
			ctx.saveConfiguration()
		end
		return api
	end

	function api:Serialize()
		return api.CurrentValue
	end

	paint(false)
	if opts.Indeterminate or opts.Animated then api:Start() end
	registerFlag(ctx, opts, value, "Progress", api)
	return api
end
--  Stepper ----------------------------------------------------------------
--      local step = Tab:CreateStepper({ Name = "Delay", Flag = "delay",
--          Min = 0, Max = 1000, Increment = 25, Suffix = " ms" })
--      step:Step(1)   step:Set(300)   print(step.CurrentValue)
function builders.Stepper(container, ctx, opts)
	local rawMin, rawMax = opts and opts.Min, opts and opts.Max
	if opts and type(opts.Range) == "table" then
		rawMin = rawMin or opts.Range[1]
		rawMax = rawMax or opts.Range[2]
	end
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base = newRow(container, ctx, opts)
	local min = tonumber(rawMin) or 0
	local max = tonumber(rawMax) or 100
	local inc = tonumber(opts.Increment) or 1
	local wrap = opts.Wrap and true or false
	local suffix = opts.Suffix or ""
	local value = math.clamp(tonumber(opts.CurrentValue) or min, min, max)
	if max <= min then max = min + 1 end

	local width = tonumber(opts.Width) or 132
	local holder = newFrame({
		Name = "Stepper",
		BackgroundColor3 = theme.SurfaceAlt,
		Size = UDim2.fromOffset(width, 26),
		Parent = base.row,
	})
	addCorner(holder, UDim.new(0, 5))
	addStroke(holder, theme.StrokeSoft, 1, 0)
	fitControl(base, width)
	holder.Position = UDim2.new(1, -(base.controlRight), 0.5, 0)
	holder.AnchorPoint = Vector2.new(1, 0.5)

	local minus = create("TextButton", {
		Name = "Minus",
		Text = "-",
		Font = THEME_FONT_BOLD,
		TextSize = 15,
		TextColor3 = theme.TextMuted,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(30, 26),
		Parent = holder,
	})
	local plus = create("TextButton", {
		Name = "Plus",
		Text = "+",
		Font = THEME_FONT_BOLD,
		TextSize = 15,
		TextColor3 = theme.TextMuted,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(30, 26),
		Position = UDim2.new(1, -30, 0, 0),
		Parent = holder,
	})
	local valueText = newText({
		Name = "Value",
		Text = tostring(value) .. suffix,
		TextSize = 12,
		Font = THEME_FONT_BOLD,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(30, 0),
		Parent = holder,
	})

	--  The settings table handed in by the caller is the element (as always).
	local api = opts
	api.Type = "Stepper"
	api.Row = base.row
	api.Base = base
	api.Element = holder
	api.Min = min
	api.Max = max
	api.Increment = inc
	api.CurrentValue = value
	api.Value = value

	local function render()
		api.CurrentValue = value
		api.Value = value
		valueText.Text = tostring(value) .. suffix
		fitLabel(valueText, width - 66, { MaxSize = 13, MinSize = 9 })
	end

	function api:Set(newValue, silent)
		value = math.clamp(tonumber(newValue) or min, min, max)
		render()
		if not silent then
			callSafe(opts.Callback, value)
			ctx.saveConfiguration()
		end
		return api
	end

	function api:SetSilent(newValue)
		return api:Set(newValue, true)
	end

	function api:Step(direction, silent)
		direction = tonumber(direction) or 1
		local target = value + direction * inc
		if wrap then
			if target > max then target = min elseif target < min then target = max end
		end
		value = math.clamp(target, min, max)
		render()
		if not silent then
			callSafe(opts.Callback, value)
			ctx.saveConfiguration()
		end
		return api
	end

	function api:Increment(silent)
		return api:Step(1, silent)
	end

	function api:Decrement(silent)
		return api:Step(-1, silent)
	end

	function api:SetValue(newValue, silent)
		return api:Set(newValue, silent)
	end

	function api:Serialize()
		return api.CurrentValue
	end

	minus.MouseButton1Click:Connect(function() api:Step(-1) end)
	plus.MouseButton1Click:Connect(function() api:Step(1) end)

	render()
	registerFlag(ctx, opts, value, "Stepper", api)
	return api
end
--  Segmented control ------------------------------------------------------
--      local mode = Tab:CreateSegment({ Name = "Mode", CurrentOption = "Legit",
--          Options = { "Legit", "Rage", "Auto" } })
--      mode:Set("Rage")     print(mode.CurrentOption)
--      -- Multi = true turns it into a row of toggle chips below the caption
function builders.Segment(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local options = opts.Options or {}
	local multi = opts.Multi and true or false
	local base = newRow(container, ctx, opts)
	local rowWidth = base.rowWidth or ROW_WIDTH
	local perLine = math.max(1, math.min(#options > 0 and #options or 1, tonumber(opts.PerLine) or 3))
	local lines = math.max(1, math.ceil((#options > 0 and #options or 1) / perLine))
	local stripHeight = lines * 24 + (lines - 1) * 6
	base.row.Size = UDim2.new(1, 0, 0, (base.rowHeight or ROW_HEIGHT) + stripHeight + 6)

	local strip = newFrame({
		Name = "Strip",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, stripHeight),
		Position = UDim2.new(0, 10, 0, base.rowHeight or ROW_HEIGHT),
		Parent = base.row,
	})

	--  The settings table handed in by the caller is the element (as always).
	local api = opts
	api.Type = "Segment"
	api.Row = base.row
	api.Base = base
	api.Element = strip
	api.Multi = multi

	local buttons = {}
	local selected = {}

	local function isSelected(name)
		if multi then return listFind(selected, name) ~= nil end
		return api.CurrentOption == name
	end

	local function paint()
		for name, button in pairs(buttons) do
			local on = isSelected(name)
			button.BackgroundColor3 = on and theme.Accent or theme.Surface
			button.TextColor3 = on and theme.Background or theme.TextMuted
		end
		if multi then
			local list = {}
			for position, name in ipairs(selected) do list[position] = name end
			api.CurrentOption = list
			api.CurrentOptions = list
		end
		api.Value = api.CurrentOption
	end

	local function choose(name, silent)
		if multi then
			local position = listFind(selected, name)
			if position then
				table.remove(selected, position)
			else
				selected[#selected + 1] = name
			end
		elseif api.CurrentOption == name and opts.AllowDeselect then
			api.CurrentOption = nil
		else
			api.CurrentOption = name
		end
		paint()
		if not silent then
			callSafe(opts.Callback, api.CurrentOption)
			ctx.saveConfiguration()
		end
	end

	local cell = 0
	for _, name in ipairs(options) do
		local line = math.floor(cell / perLine)
		local column = cell % perLine
		local button = create("TextButton", {
			Name = tostring(name),
			Text = tostring(name),
			Font = THEME_FONT_BOLD,
			TextSize = 12,
			AutoButtonColor = false,
			BackgroundColor3 = theme.Surface,
			Size = UDim2.new(1 / perLine, -6, 0, 24),
			Position = UDim2.new(column / perLine, 3, 0, line * 30),
			Parent = strip,
		})
		addCorner(button, opts.Pill and UDim.new(1, 0) or UDim.new(0, 5))
		fitLabel(button, (rowWidth - 20) / perLine - 14, { MaxSize = 13, MinSize = 9 })
		buttons[name] = button
		cell = cell + 1
		button.MouseButton1Click:Connect(function() choose(name) end)
	end

	function api:Set(newValue, silent)
		if multi then
			for position = #selected, 1, -1 do selected[position] = nil end
			if type(newValue) == "table" then
				for _, name in ipairs(newValue) do
					if buttons[name] then selected[#selected + 1] = name end
				end
			elseif newValue ~= nil and buttons[newValue] then
				selected[#selected + 1] = newValue
			end
		else
			api.CurrentOption = buttons[newValue] and newValue or nil
		end
		paint()
		if not silent then
			callSafe(opts.Callback, api.CurrentOption)
		end
		return api
	end

	function api:SetSilent(newValue)
		return api:Set(newValue, true)
	end

	function api:Toggle(name, silent)
		choose(name, silent)
		return api
	end

	function api:GetSelection()
		if multi then
			local copy = {}
			for position, name in ipairs(selected) do copy[position] = name end
			return copy
		end
		return api.CurrentOption
	end

	function api:GetOptions()
		local copy = {}
		for position, name in ipairs(options) do copy[position] = name end
		return copy
	end

	function api:Serialize()
		if multi then return api:GetSelection() end
		return api.CurrentOption
	end

	if multi then
		local initial = opts.CurrentOption
		if type(initial) == "table" then
			for _, name in ipairs(initial) do
				if buttons[name] then selected[#selected + 1] = name end
			end
		elseif initial ~= nil and buttons[initial] then
			selected[#selected + 1] = initial
		end
	else
		api.CurrentOption = (opts.CurrentOption ~= nil and buttons[opts.CurrentOption]) and opts.CurrentOption or options[1]
	end

	paint()
	registerFlag(ctx, opts, api.CurrentOption, "Segment", api)
	return api
end
--  Wheel ------------------------------------------------------------------
--      local wheel = Tab:CreateWheel({ Name = "Hitbox", CurrentOption = "Head",
--          Options = { "Head", "Torso", "Nearest" } })
--      wheel:Next()   wheel:Previous()   wheel:Set("Torso")
--  Three options are visible at once, the middle one is the active choice.
function builders.Wheel(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base = newRow(container, ctx, opts)
	local options = opts.Options or {}
	local index = 1
	for position, name in ipairs(options) do
		if name == opts.CurrentOption then index = position end
	end

	local width = tonumber(opts.Width) or 150
	local holder = newFrame({
		Name = "Wheel",
		BackgroundColor3 = theme.SurfaceAlt,
		Size = UDim2.fromOffset(width, 64),
		Parent = base.row,
	})
	addCorner(holder, UDim.new(0, 5))
	addStroke(holder, theme.StrokeSoft, 1, 0)
	fitControl(base, width)
	holder.Position = UDim2.new(1, -(base.controlRight), 0.5, 0)
	holder.AnchorPoint = Vector2.new(1, 0.5)

	local entries = {}
	for slot = 1, 3 do
		entries[slot] = newText({
			Name = "Slot" .. slot,
			Text = "-",
			TextSize = 12,
			Font = THEME_FONT_BOLD,
			TextColor3 = theme.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -30, 0, 18),
			Position = UDim2.new(0, 15, 0, 5 + (slot - 1) * 19),
			Parent = holder,
		})
	end

	local up = create("TextButton", {
		Name = "Up",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(16, 64),
		Parent = holder,
	})
	local down = create("TextButton", {
		Name = "Down",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(16, 64),
		Position = UDim2.new(1, -16, 0, 0),
		Parent = holder,
	})
	local upChevron = makeChevron(up, theme.TextMuted, 9, true)
	upChevron.Position = UDim2.fromScale(0.5, 0.5)
	upChevron.AnchorPoint = Vector2.new(0.5, 0.5)
	local downChevron = makeChevron(down, theme.TextMuted, 9, false)
	downChevron.Position = UDim2.fromScale(0.5, 0.5)
	downChevron.AnchorPoint = Vector2.new(0.5, 0.5)

	--  The settings table handed in by the caller is the element (as always).
	local api = opts
	api.Type = "Wheel"
	api.Row = base.row
	api.Base = base
	api.Element = holder
	api.Options = options

	local function paint()
		local count = #options
		for slot = -1, 1 do
			local entry = entries[slot + 2]
			local middle = slot == 0
			local position = index + slot
			if count == 0 then
				entry.Text = "-"
			else
				while position < 1 do position = position + count end
				while position > count do position = position - count end
				entry.Text = tostring(options[position])
			end
			entry.TextColor3 = middle and theme.Accent or theme.TextDim
			entry.TextSize = middle and 13 or 11
			fitLabel(entry, width - 40, { MaxSize = middle and 14 or 12, MinSize = 9 })
		end
		api.CurrentOption = options[index]
		api.Value = api.CurrentOption
	end

	local function step(direction, silent)
		local count = #options
		if count == 0 then return api end
		index = index + direction
		while index < 1 do index = index + count end
		while index > count do index = index - count end
		paint()
		if not silent then
			callSafe(opts.Callback, api.CurrentOption)
			ctx.saveConfiguration()
		end
		return api
	end

	function api:Next(silent)
		return step(1, silent)
	end

	function api:Previous(silent)
		return step(-1, silent)
	end

	function api:Set(name, silent)
		for position, option in ipairs(options) do
			if option == name then index = position end
		end
		paint()
		if not silent then
			callSafe(opts.Callback, api.CurrentOption)
			ctx.saveConfiguration()
		end
		return api
	end

	function api:SetSilent(name)
		return api:Set(name, true)
	end

	function api:SetIndex(position, silent)
		index = math.clamp(tonumber(position) or 1, 1, math.max(1, #options))
		paint()
		if not silent then
			callSafe(opts.Callback, api.CurrentOption)
			ctx.saveConfiguration()
		end
		return api
	end

	function api:GetIndex()
		return index
	end

	function api:GetOptions()
		local copy = {}
		for position, option in ipairs(options) do copy[position] = option end
		return copy
	end

	function api:Serialize()
		return api.CurrentOption
	end

	up.MouseButton1Click:Connect(function() step(-1) end)
	down.MouseButton1Click:Connect(function() step(1) end)

	paint()
	registerFlag(ctx, opts, api.CurrentOption, "Wheel", api)
	return api
end
--  Analog stick -----------------------------------------------------------
--      local stick = Tab:CreateAnalog({ Name = "Movement", Flag = "move",
--          Deadzone = 0.1 })
--      stick:Set(0, 1)      stick:Center()      print(stick.CurrentValue.Magnitude)
function builders.Analog(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base, stage = widgetStage(container, ctx, opts, tonumber(opts.Height) or 156)
	local padSize = tonumber(opts.PadSize) or 108
	local deadzone = tonumber(opts.Deadzone) or 0.08

	local pad = newFrame({
		Name = "Pad",
		BackgroundColor3 = theme.Surface,
		Size = UDim2.fromOffset(padSize, padSize),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = stage,
	})
	addCorner(pad, UDim.new(1, 0))
	addStroke(pad, theme.StrokeSoft, 1, 0.2)
	newFrame({
		Name = "GuideX",
		BackgroundColor3 = theme.StrokeSoft,
		Size = UDim2.new(1, -18, 0, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = pad,
	})
	newFrame({
		Name = "GuideY",
		BackgroundColor3 = theme.StrokeSoft,
		Size = UDim2.fromOffset(1, padSize - 18),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = pad,
	})
	local knob = newFrame({
		Name = "Knob",
		BackgroundColor3 = theme.Accent,
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = pad,
	})
	addCorner(knob, UDim.new(1, 0))
	local caption = stageCaption(stage, "", ctx)

	--  The settings table handed in by the caller is the element (as always).
	local api = opts
	api.Type = "Analog"
	api.Row = base.row
	api.Base = base
	api.Element = pad
	api.Deadzone = deadzone
	--  read the requested position before api.CurrentValue replaces it
	local initialAnalog = type(opts.CurrentValue) == "table" and opts.CurrentValue or nil
	api.CurrentValue = { X = 0, Y = 0, Magnitude = 0 }
	api.Value = api.CurrentValue
	if initialAnalog then
		api.CurrentValue.X = math.clamp(tonumber(initialAnalog.X) or 0, -1, 1)
		api.CurrentValue.Y = math.clamp(tonumber(initialAnalog.Y) or 0, -1, 1)
	end

	local function paint()
		local value = api.CurrentValue
		local magnitude = math.min(1, math.sqrt(value.X * value.X + value.Y * value.Y))
		value.Magnitude = magnitude
		api.Value = value
		local travel = padSize / 2 - 14
		knob.Position = UDim2.new(0.5, value.X * travel, 0.5, value.Y * travel)
		knob.BackgroundColor3 = magnitude > deadzone and theme.Accent or theme.TextMuted
		caption.Text = string.format("X %.2f | Y %.2f | magnitude %.2f", value.X, value.Y, magnitude)
		fitLabel(caption, (tonumber(ctx.rowWidth) or ROW_WIDTH) - 24, { MaxSize = 12, MinSize = 9 })
	end

	local function commit(x, y, silent)
		local value = api.CurrentValue
		value.X = math.clamp(tonumber(x) or 0, -1, 1)
		value.Y = math.clamp(tonumber(y) or 0, -1, 1)
		paint()
		if not silent then
			callSafe(opts.Callback, value)
			ctx.saveConfiguration()
		end
	end

	local dragging = false
	local function updateFromPosition(position)
		local abs = pad.AbsolutePosition or Vector2.new(0, 0)
		local size = pad.AbsoluteSize
		local width = (size and size.X and size.X > 0) and size.X or padSize
		local height = (size and size.Y and size.Y > 0) and size.Y or padSize
		local x = math.clamp(((position.X - abs.X) / width - 0.5) * 2, -1, 1)
		local y = math.clamp(((position.Y - abs.Y) / height - 0.5) * 2, -1, 1)
		commit(x, y)
	end

	pad.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromPosition(input.Position)
		end
	end)
	ctx.connections[#ctx.connections + 1] = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromPosition(input.Position)
		end
	end)
	ctx.connections[#ctx.connections + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	function api:Set(x, y, silent)
		if type(x) == "table" then
			commit(tonumber(x.X) or 0, tonumber(x.Y) or 0, silent or y)
		else
			commit(x, y, silent)
		end
		return api
	end

	function api:SetSilent(x, y)
		return api:Set(x, y, true)
	end

	function api:Center()
		return api:Set(0, 0)
	end

	function api:GetMagnitude()
		return api.CurrentValue.Magnitude or 0
	end

	function api:IsActive()
		return (api.CurrentValue.Magnitude or 0) > deadzone
	end

	function api:Serialize()
		return { X = api.CurrentValue.X, Y = api.CurrentValue.Y }
	end

	paint()
	registerFlag(ctx, opts, api.CurrentValue, "Analog", api)
	return api
end
--  Chips ------------------------------------------------------------------
--      local chips = Tab:CreateChips({ Name = "Bones", Flag = "bones",
--          Options = { "Head", "Torso", "Arms" }, CurrentOptions = { "Head" } })
--      chips:Toggle("Arms")     chips:Set({ "Head", "Torso" })
--  A compact multi select strip: the same engine as Segment with Multi = true
--  drawn as rounded pills, plus the chips style option names.
function builders.Chips(container, ctx, opts)
	opts = opts or {}
	if opts.Multi == nil then opts.Multi = true end
	opts.Pill = true
	opts.PerLine = opts.PerLine or 3
	if opts.CurrentOptions ~= nil and opts.CurrentOption == nil then
		opts.CurrentOption = opts.CurrentOptions
	end

	local api = builders.Segment(container, ctx, opts)
	api.Type = "Chips"
	api.Chips = true
	api.Options = opts.Options or {}
	api.CurrentOptions = api.CurrentOption
	return api
end
--  Radar ------------------------------------------------------------------
--      local radar = Tab:CreateRadar({ Name = "Radar", Max = 24 })
--      radar:Push({ X = 0.2, Y = -0.4, Color = Color3.fromRGB(255, 90, 90) })
--      radar:SetBlips({ { X = 0, Y = 0.6 } })     radar:Clear()
--  Blips are normalised: X / Y of 1 sits on the outer ring.
function builders.Radar(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base, stage = widgetStage(container, ctx, opts, tonumber(opts.Height) or 156)
	local size = tonumber(opts.PadSize) or 108

	local pad = newFrame({
		Name = "Pad",
		BackgroundColor3 = theme.Surface,
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = stage,
	})
	addCorner(pad, UDim.new(1, 0))
	addStroke(pad, theme.StrokeSoft, 1, 0.2)

	for ringIndex = 1, 2 do
		local scale = ringIndex == 1 and 0.66 or 0.33
		local ring = newFrame({
			Name = "Ring" .. ringIndex,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size * scale, size * scale),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = pad,
		})
		addCorner(ring, UDim.new(1, 0))
		addStroke(ring, theme.StrokeSoft, 1, 0.4)
	end
	newFrame({
		Name = "CrossX",
		BackgroundColor3 = theme.StrokeSoft,
		Size = UDim2.new(1, -18, 0, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = pad,
	})
	newFrame({
		Name = "CrossY",
		BackgroundColor3 = theme.StrokeSoft,
		Size = UDim2.fromOffset(1, size - 18),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = pad,
	})

	--  the sweep turns inside a square holder, so it rotates about the centre
	local sweepHolder = newFrame({
		Name = "SweepHolder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = pad,
	})
	newFrame({
		Name = "Sweep",
		BackgroundColor3 = theme.Accent,
		BackgroundTransparency = 0.2,
		Size = UDim2.fromOffset(size / 2 - 8, 1.6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = sweepHolder,
	})
	local blipHolder = newFrame({
		Name = "Blips",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = pad,
	})
	local caption = stageCaption(stage, "", ctx)

	--  the sweep loops inside the engine, so nothing keeps ticking in Lua
	if TweenService and opts.Sweep ~= false then
		pcall(function()
			local info = TweenInfo.new(tonumber(opts.SweepTime) or 2.4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false)
			TweenService:Create(sweepHolder, info, { Rotation = 360 }):Play()
		end)
	end

	--  The settings table handed in by the caller is the element (as always).
	local api = opts
	api.Type = "Radar"
	api.Row = base.row
	api.Base = base
	api.Element = pad
	api.Max = tonumber(opts.Max) or 24
	--  capture the requested blips before api.Blips replaces the table
	local initialBlips = opts.Blips
	api.Blips = {}
	api.CurrentValue = api.Blips
	api.Value = api.Blips

	local dots = {}
	local function paint()
		local span = size / 2 - 12
		for index, blip in ipairs(api.Blips) do
			local dot = dots[index]
			if not dot then
				dot = newFrame({
					Name = "Blip" .. index,
					BackgroundColor3 = theme.Danger,
					Size = UDim2.fromOffset(8, 8),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Parent = blipHolder,
				})
				addCorner(dot, UDim.new(1, 0))
				addStroke(dot, theme.Background, 1, 0.2)
				dots[index] = dot
			end
			local x = math.clamp(tonumber(blip.X) or 0, -1, 1)
			local y = math.clamp(tonumber(blip.Y) or 0, -1, 1)
			dot.Position = UDim2.new(0.5, x * span, 0.5, y * span)
			dot.BackgroundColor3 = typeof(blip.Color) == "Color3" and blip.Color or theme.Danger
			local dotSize = tonumber(blip.Size) or 8
			dot.Size = UDim2.fromOffset(dotSize, dotSize)
			dot.Visible = true
		end
		for index = #api.Blips + 1, #dots do
			if dots[index] then dots[index].Visible = false end
		end
		caption.Text = string.format("%d blip(s) | limit %d", #api.Blips, api.Max)
		fitLabel(caption, (tonumber(ctx.rowWidth) or ROW_WIDTH) - 24, { MaxSize = 12, MinSize = 9 })
	end

	function api:SetBlips(list)
		api.Blips = {}
		if type(list) == "table" then
			for _, blip in ipairs(list) do
				if type(blip) == "table" then api.Blips[#api.Blips + 1] = blip end
			end
		end
		api.CurrentValue = api.Blips
		api.Value = api.Blips
		paint()
		return api
	end

	function api:Push(blip)
		if type(blip) ~= "table" then return api end
		api.Blips[#api.Blips + 1] = blip
		while #api.Blips > api.Max do table.remove(api.Blips, 1) end
		api.CurrentValue = api.Blips
		api.Value = api.Blips
		paint()
		callSafe(opts.Callback, blip)
		return api
	end

	function api:GetBlips()
		local copy = {}
		for index, blip in ipairs(api.Blips) do copy[index] = blip end
		return copy
	end

	function api:Clear()
		api.Blips = {}
		api.CurrentValue = api.Blips
		api.Value = api.Blips
		paint()
		return api
	end

	api:SetBlips(initialBlips)
	registerFlag(ctx, opts, api.Blips, "Radar", api)
	return api
end
--  Image with markers -----------------------------------------------------
--      local skin = Tab:CreateImage({ Name = "Skin preview", Flag = "skin",
--          Image = 4483362458, Height = 140,
--          Points = { Torso = { 0.5, 0.38 } } })
--      skin.Marker.Torso = true        skin.Marker.head = true
--      skin:SetMarker("LeftLeg", true) skin:AddPoint("Gun", 0.8, 0.3)
--      skin:SetTint(Color3.fromRGB(200, 220, 255))
--  Anything written into skin.Marker / skin.Points repaints the picture, which
--  makes it perfect to visualise a skin while other variables change.
function builders.Image(container, ctx, opts)
	opts = normalizeOpts(opts)
	local theme = ctx.theme()
	local base, stage = widgetStage(container, ctx, opts, tonumber(opts.Height) or 150)

	local picture = create("ImageLabel", {
		Name = "Picture",
		BackgroundColor3 = theme.Surface,
		BackgroundTransparency = 0.15,
		ImageColor3 = theme.Text,
		Size = UDim2.new(1, -20, 1, -34),
		Position = UDim2.fromOffset(10, 8),
		Parent = stage,
	})
	addCorner(picture, UDim.new(0, 6))
	addStroke(picture, theme.StrokeSoft, 1, 0.3)
	applyIcon(picture, opts.Image or opts.Icon or opts.Url)

	local holder = newFrame({
		Name = "Markers",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = picture,
	})
	local caption = stageCaption(stage, "", ctx)

	--  normalised marker points (0 - 1 across the picture)
	local points = {}
	for _, region in ipairs(PLAYER_REGIONS) do
		local point = IMAGE_MARKER_POINTS[region]
		points[region] = { point[1], point[2] }
	end
	if type(opts.Points) == "table" then
		for key, value in pairs(opts.Points) do
			if type(value) == "table" then
				points[canonicalRegion(key)] = { tonumber(value[1]) or 0.5, tonumber(value[2]) or 0.5 }
			end
		end
	end

	local markers = {}   -- region -> dot
	local active = {}    -- region -> true | Color3

	local function ensureMarker(region)
		if markers[region] then return markers[region] end
		local point = points[region] or { 0.5, 0.5 }
		local dot = newFrame({
			Name = "Marker_" .. tostring(region),
			BackgroundColor3 = theme.Accent,
			Size = UDim2.fromOffset(10, 10),
			Position = UDim2.fromScale(point[1], point[2]),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = holder,
		})
		addCorner(dot, UDim.new(1, 0))
		addStroke(dot, theme.Background, 1.5, 0)
		markers[region] = dot
		return dot
	end

	--  The settings table handed in by the caller is the element (as always).
	local api = opts
	api.Type = "Image"
	api.Row = base.row
	api.Base = base
	api.Element = picture
	api.Points = points
	--  capture the requested markers before api.Marked replaces the table
	local initialMarkers = opts.Marked or opts.CurrentValue
	api.Marked = {}

	local function paint()
		local marked = {}
		for region, state in pairs(active) do
			if state then
				local dot = ensureMarker(region)
				local point = points[region] or { 0.5, 0.5 }
				dot.Position = UDim2.fromScale(point[1], point[2])
				dot.BackgroundColor3 = typeof(state) == "Color3" and state or theme.Accent
				dot.Visible = true
				marked[#marked + 1] = region
			elseif markers[region] then
				markers[region].Visible = false
			end
		end
		table.sort(marked)
		api.Marked = marked
		api.CurrentValue = marked
		api.Value = marked
		caption.Text = #marked > 0 and ("marked: " .. table.concat(marked, ", ")) or "no markers"
		fitLabel(caption, (tonumber(ctx.rowWidth) or ROW_WIDTH) - 24, { MaxSize = 12, MinSize = 9 })
	end

	--  live variables: writing to them repaints the picture straight away
	api.Marker = reactiveWidgetTable(active, function(region, value)
		if region == "*" then
			for _, entry in ipairs(PLAYER_REGIONS) do active[entry] = value end
		end
		paint()
	end)

	function api:SetImage(icon)
		applyIcon(picture, icon)
		return api
	end

	function api:SetTint(color)
		if typeof(color) == "Color3" then picture.ImageColor3 = color end
		return api
	end

	function api:SetTransparency(value)
		picture.ImageTransparency = math.clamp(tonumber(value) or 0, 0, 1)
		return api
	end

	function api:AddPoint(name, x, y)
		points[canonicalRegion(name)] = {
			math.clamp(tonumber(x) or 0.5, 0, 1),
			math.clamp(tonumber(y) or 0.5, 0, 1),
		}
		paint()
		return api
	end

	function api:RemovePoint(name)
		points[canonicalRegion(name)] = nil
		return api
	end

	function api:SetMarker(name, state, silent)
		local region = canonicalRegion(name)
		if region == "*" then
			for _, entry in ipairs(PLAYER_REGIONS) do active[entry] = state end
		else
			active[region] = state
		end
		paint()
		if not silent then
			callSafe(opts.Callback, region, state, api)
			ctx.saveConfiguration()
		end
		return api
	end

	function api:IsMarked(name)
		return active[canonicalRegion(name)] and true or false
	end

	function api:ClearMarkers()
		for region in pairs(active) do active[region] = nil end
		for _, dot in pairs(markers) do dot.Visible = false end
		paint()
		return api
	end

	function api:GetMarked()
		local copy = {}
		for index, region in ipairs(api.Marked) do copy[index] = region end
		return copy
	end

	function api:SetMarkers(list, silent)
		for region in pairs(active) do active[region] = nil end
		if type(list) == "table" then
			for _, name in ipairs(list) do active[canonicalRegion(name)] = true end
		elseif list ~= nil then
			active[canonicalRegion(list)] = true
		end
		paint()
		if not silent then
			callSafe(opts.Callback, api.Marked, nil, api)
			ctx.saveConfiguration()
		end
		return api
	end

	function api:Set(list, silent)
		return api:SetMarkers(list, silent)
	end

	function api:SetSilent(list)
		return api:SetMarkers(list, true)
	end

	function api:Serialize()
		return api:GetMarked()
	end

	api:SetMarkers(initialMarkers, true)
	registerFlag(ctx, opts, api.Marked, "Image", api)
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
	autoSave = true,
	loaded = false,
	fileName = nil,
	folder = CONFIG_ROOT .. "/Configurations",
	disabledNotified = false,
}

--  The in-menu "auto-save" switch is remembered in its own tiny file, because
--  once auto-saving is turned off the configuration file is no longer written.
local PREFERENCES_FILE = CONFIG_ROOT .. "/Preferences" .. CONFIG_EXTENSION

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

--  User preferences (currently just the auto-save switch) ------------------
local function readPreferences()
	if not filesystemAvailable() or not HttpService then return nil end
	if not isfile(PREFERENCES_FILE) then return nil end
	local ok, contents = pcall(readfile, PREFERENCES_FILE)
	if not ok or not contents or contents == "" then return nil end
	local ok2, data = pcall(function() return HttpService:JSONDecode(contents) end)
	if ok2 and type(data) == "table" then return data end
	return nil
end

local function writePreferences()
	if not filesystemAvailable() or not HttpService then return false end
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode({ AutoSave = configState.autoSave and true or false })
	end)
	if not ok or not encoded then return false end
	ensureFolder(CONFIG_ROOT)
	return pcall(writefile, PREFERENCES_FILE, encoded)
end

--  Whether the auto-saved configuration file already exists on disk.
local function configFileExists()
	if not filesystemAvailable() or not configState.fileName then return false end
	local path = configState.folder .. "/" .. configState.fileName .. CONFIG_EXTENSION
	if isfile(path) then return true end
	return isfile(LEGACY_CONFIG_ROOT .. "/Configurations/" .. configState.fileName .. CONFIG_EXTENSION)
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
			elseif type(element.Serialize) == "function" then
				--  The extended widgets (section 9b) describe their own saved
				--  shape: PlayerWidget -> region list, Crosshair -> { FOV, X, Y },
				--  Analog -> { X, Y }, Stepper / Graph / Progress -> number, ...
				local ok, serialized = pcall(element.Serialize, element)
				if ok then data[flag] = serialized end
			end
		end
	end
	--  The shared favourite colour palette rides along under a reserved key so
	--  it survives a rejoin exactly like any flagged element.
	local favorites = {}
	for i = 1, FAVORITE_SLOTS do
		local entry = XClient.FavoriteColors[i]
		favorites[i] = (typeof(entry) == "Color3") and packColor(entry) or false
	end
	data.__favorite_colors = favorites
	return data
end

--  Applies a decoded configuration table onto the live elements.
local function applyFlags(data)
	if type(data) ~= "table" then return false end
	--  Restore the shared favourite colour palette first, then the elements.
	local favorites = XClient.FavoriteColors
	for i = #favorites, 1, -1 do favorites[i] = nil end
	if type(data.__favorite_colors) == "table" then
		for i = 1, FAVORITE_SLOTS do
			local entry = data.__favorite_colors[i]
			if type(entry) == "table" then favorites[i] = unpackColor(entry) end
		end
	end
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

--  Debounced auto-save used by every element setter (ctx.saveConfiguration).
--  It coalesces the flurry of changes a slider drag produces into a single
--  write a fraction of a second later and honours the in-menu auto-save switch
--  (configState.autoSave).  Explicit saves go through saveConfiguration above.
local autoSaveScheduled = false
local function requestAutoSave()
	if not configState.enabled or not configState.autoSave or not configState.loaded then return false end
	if not configState.fileName or not filesystemAvailable() then return false end
	if autoSaveScheduled then return true end
	autoSaveScheduled = true
	task.delay(0.4, function()
		autoSaveScheduled = false
		saveConfiguration()
	end)
	return true
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
--  Compact settings popup.  Right clicking a module gear opens this instead
--  of the full height flyout: it is narrower, hugs its rows and stops growing
--  at COMPACT_MAX_HEIGHT (the body scrolls from there on).
local COMPACT_WIDTH = 190
local COMPACT_MAX_HEIGHT = 300
local COMPACT_MIN_HEIGHT = 96

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
	--  Auto-save is on by default: the interface keeps a running "autocfg"
	--  file so the menu comes back exactly as it was left last session.  Pass
	--  ConfigurationSaving = { Enabled = false } to opt out again.
	if type(settings.ConfigurationSaving) == "table" then
		local cfg = settings.ConfigurationSaving
		configState.enabled = cfg.Enabled and true or false
		configState.fileName = cfg.FileName or "autocfg"
		configState.folder = cfg.FolderName and tostring(cfg.FolderName) or (CONFIG_ROOT .. "/Configurations")
	else
		configState.enabled = true
		configState.fileName = "autocfg"
		configState.folder = CONFIG_ROOT .. "/Configurations"
	end
	--  The in-menu auto-save switch is remembered in its own preferences file,
	--  so it still works as a user choice even while saving is switched off.
	local storedPreferences = readPreferences()
	if storedPreferences and storedPreferences.AutoSave ~= nil then
		configState.autoSave = storedPreferences.AutoSave and true or false
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

	--  The window slides + scales into place instead of popping in.
	local rootScale = create("UIScale", { Scale = 0.94, Parent = root })
	root.Position = UDim2.new(0.5, 0, 0.5, 16)
	tween(rootScale, 0.3, { Scale = 1 })
	tween(root, 0.3, { Position = UDim2.new(0.5, 0, 0.5, 0) })

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
	--  The rail carries one button per tab.  When a script registers more tabs
	--  than fit in the window the list used to simply spill past the bottom of
	--  the menu and paint over everything underneath, so the rail is a
	--  ScrollingFrame now: extra tabs scroll instead of overflowing.
	local rail = create("ScrollingFrame", {
		Name = "Rail",
		BackgroundColor3 = currentTheme.Rail,
		BorderSizePixel = 0,
		Size = UDim2.new(0, RAIL_WIDTH, 1, -TOPBAR_HEIGHT),
		Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = currentTheme.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
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
		--  connections created while the settings flyout is populated live
		--  here, so the whole panel can be rebuilt without leaking them
		flyoutConnections = {},
		popup = nil,
		theme = function() return currentTheme end,
		saveConfiguration = function() requestAutoSave() end,
		--  width available to a module row (used to fit captions); the flyout
		--  swaps this for its own narrower width while it is being populated
		rowWidth = WINDOW_WIDTH - RAIL_WIDTH - 26,
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

	--  Rows inside the flyout are torn down and rebuilt every time the panel
	--  is opened.  The element builders register global input connections
	--  while they run (slider / keybind / colour picker drag handlers).  Those
	--  used to be appended to the window wide list and never removed, so
	--  every mouse move walked an ever growing list and every destroyed row
	--  stayed referenced in the process.  While the flyout is populated the
	--  builders file their connections into this private bucket instead; the
	--  previous bucket is dropped as soon as the panel is rebuilt or closed.
	local function releaseFlyoutConnections()
		local bucket = ctx.flyoutConnections
		for index = #bucket, 1, -1 do
			local connection = bucket[index]
			bucket[index] = nil
			pcall(function() connection:Disconnect() end)
		end
	end

	local function closeFlyout()
		if not flyoutOpen then return end
		flyoutOpen = false
		settingsTarget = nil
		--  the rows inside are hidden with the panel, so stop listening for the
		--  input they were handling; their content is rebuilt on the next open
		releaseFlyoutConnections()
		--  Any dropdown / colour picker opened inside the flyout must go too.
		ctx.closePopup()
		--  The configuration name field lives in here: closing the panel has
		--  to hand the keyboard back, otherwise an invisible box keeps
		--  eating every keystroke.
		releaseTextBoxFocus()
		tween(flyout, 0.16, { Position = UDim2.fromOffset(-(PANEL_WIDTH + PANEL_GAP), 0) })
		task.delay(0.18, function()
			if not flyoutOpen and flyout and flyout.Parent then
				flyout.Visible = false
			end
		end)
	end

	local function openFlyout(heading, populate)
		--  the rows about to be thrown away registered input connections of
		--  their own - drop those before building the replacements
		releaseFlyoutConnections()
		flyoutBody:ClearAllChildren()
		ctx.closePopup()
		addList(flyoutBody, { Padding = UDim.new(0, 6) })
		flyoutTitle.Text = tostring(heading or "Settings")
		fitLabel(flyoutTitle, PANEL_WIDTH - 46, { MinSize = 10 })
		flyout.Visible = true
		flyout.Position = UDim2.fromOffset(-(PANEL_WIDTH + PANEL_GAP), 0)
		flyoutOpen = true
		tween(flyout, 0.2, { Position = UDim2.fromOffset(-(PANEL_WIDTH + PANEL_GAP - 4), 0) })
		--  rows inside the flyout are much narrower than tab rows, so the
		--  caption fitting is told about that smaller width while populating.
		--  While the rows are built their input connections are filed into the
		--  flyout bucket (see releaseFlyoutConnections) so rebuilding the
		--  panel can never pile them up on the window wide list.
		local previousWidth = ctx.rowWidth
		local previousConnections = ctx.connections
		ctx.rowWidth = PANEL_WIDTH - 12
		ctx.connections = ctx.flyoutConnections
		--  populate is pcall'd so a broken row cannot leave the context
		--  pointing at the flyout bucket / narrower width; the error is
		--  re-raised afterwards to keep the old reporting behaviour
		local ok, err = pcall(populate or function() end, flyoutBody)
		ctx.connections = previousConnections
		ctx.rowWidth = previousWidth
		if not ok then error(err, 0) end
	end

	flyoutClose.MouseButton1Click:Connect(closeFlyout)

	--  Compact settings popup ------------------------------------------
	--  Right clicking a module gear opens this instead of the full height
	--  flyout: the same rows, but the panel hugs its content, stops growing at
	--  COMPACT_MAX_HEIGHT and scrolls past that.  It sits in the same spot on
	--  the left of the window.
	local compact = newFrame({
		Name = "SettingsCompact",
		BackgroundColor3 = currentTheme.Surface,
		Size = UDim2.fromOffset(COMPACT_WIDTH, COMPACT_MIN_HEIGHT),
		Position = UDim2.fromOffset(-(COMPACT_WIDTH + PANEL_GAP), 0),
		Visible = false,
		Parent = root,
	})
	compact.ZIndex = 30
	addCorner(compact, UDim.new(0, 10))
	local compactStroke = addStroke(compact, currentTheme.Stroke, 1, 0.25)

	local compactTitle = newText({
		Name = "Title",
		Text = "Settings",
		Font = THEME_FONT_BOLD,
		TextSize = 14,
		TextColor3 = currentTheme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(12, 14),
		Parent = compact,
	})
	compactTitle.ZIndex = 31

	local compactClose = create("TextButton", {
		Name = "Close",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -10, 0, 14),
		AnchorPoint = Vector2.new(1, 0),
		Parent = compact,
	})
	compactClose.ZIndex = 31
	local compactBarA = newFrame({ BackgroundColor3 = currentTheme.TextMuted, Size = UDim2.fromOffset(10, 1.6), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45, Parent = compactClose })
	local compactBarB = newFrame({ BackgroundColor3 = currentTheme.TextMuted, Size = UDim2.fromOffset(10, 1.6), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -45, Parent = compactClose })
	compactBarA.ZIndex = 32
	compactBarB.ZIndex = 32

	local compactBody = create("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -12, 0, COMPACT_MIN_HEIGHT - (TOPBAR_HEIGHT + 14)),
		Position = UDim2.fromOffset(6, TOPBAR_HEIGHT + 6),
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = currentTheme.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = compact,
	})
	compactBody.ZIndex = 31
	addList(compactBody, { Padding = UDim.new(0, 6) })

	local compactOpen = false
	local compactTarget

	--  Classes that are GuiObjects.  Instance:IsA("GuiObject") answers this in
	--  the engine; the dev harness shim compares class names exactly, so the
	--  list keeps the measuring below working on both.
	local COMPACT_GUI_CLASSES = {
		Frame = true, TextLabel = true, TextButton = true, TextBox = true,
		ImageLabel = true, ImageButton = true, ScrollingFrame = true,
		CanvasGroup = true, ViewportFrame = true, VideoFrame = true,
	}
	local function compactIsGui(child)
		local ok, result = pcall(function() return child:IsA("GuiObject") end)
		if ok and result then return true end
		return COMPACT_GUI_CLASSES[child.ClassName] == true
	end

	--  Sums the row heights the populator laid down (plus the list padding) so
	--  the panel can be sized to fit them without waiting for a layout pass.
	local function compactContentHeight(container)
		local total, count = 0, 0
		for _, child in ipairs(container:GetChildren()) do
			if compactIsGui(child) then
				local size = child.Size
				total = total + (size and size.Y and size.Y.Offset or 0)
				count = count + 1
			end
		end
		return total + math.max(0, count - 1) * 6
	end

	local function closeCompact()
		if not compactOpen then return end
		compactOpen = false
		compactTarget = nil
		releaseFlyoutConnections()
		ctx.closePopup()
		releaseTextBoxFocus()
		tween(compact, 0.16, { Position = UDim2.fromOffset(-(COMPACT_WIDTH + PANEL_GAP), 0) })
		task.delay(0.18, function()
			if not compactOpen and compact and compact.Parent then
				compact.Visible = false
			end
		end)
	end

	local function openCompact(heading, populate)
		releaseFlyoutConnections()
		compactBody:ClearAllChildren()
		ctx.closePopup()
		addList(compactBody, { Padding = UDim.new(0, 6) })
		compactTitle.Text = tostring(heading or "Settings")
		fitLabel(compactTitle, COMPACT_WIDTH - 46, { MinSize = 10 })
		local previousWidth = ctx.rowWidth
		local previousConnections = ctx.connections
		ctx.rowWidth = COMPACT_WIDTH - 12
		ctx.connections = ctx.flyoutConnections
		local ok, err = pcall(populate or function() end, compactBody)
		ctx.connections = previousConnections
		ctx.rowWidth = previousWidth
		if not ok then error(err, 0) end
		--  auto height: hug the rows, but never pass the cap - past it the
		--  body keeps a fixed viewport and scrolls (AutomaticCanvasSize)
		local bodyMin = COMPACT_MIN_HEIGHT - (TOPBAR_HEIGHT + 14)
		local bodyMax = COMPACT_MAX_HEIGHT - (TOPBAR_HEIGHT + 14)
		local bodyHeight = math.clamp(compactContentHeight(compactBody) + 6, bodyMin, bodyMax)
		compactBody.Size = UDim2.new(1, -12, 0, bodyHeight)
		compact.Size = UDim2.fromOffset(COMPACT_WIDTH, bodyHeight + TOPBAR_HEIGHT + 14)
		compact.Visible = true
		compact.Position = UDim2.fromOffset(-(COMPACT_WIDTH + PANEL_GAP), 0)
		compactOpen = true
		tween(compact, 0.2, { Position = UDim2.fromOffset(-(COMPACT_WIDTH + PANEL_GAP - 4), 0) })
	end

	compactClose.MouseButton1Click:Connect(closeCompact)

	--  Instantiate the per module settings of a row inside the flyout ----
	local function buildModuleSettings(container, base)
		local list = base.opts and base.opts.Settings
		if type(list) ~= "table" then return end
		local heading = newText({
			Name = "Heading",
			Text = string.upper(tostring(base.opts.Name or "Module")),
			Font = THEME_FONT_BOLD,
			TextSize = 11,
			TextColor3 = currentTheme.TextDim,
			Size = UDim2.new(1, 0, 0, 15),
			Parent = container,
		})
		fitLabel(heading, PANEL_WIDTH - 24, { MinSize = 9, Wrap = true })
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
		--  only one panel at a time: the compact popup gives way
		closeCompact()
		settingsTarget = base
		openFlyout(base.opts and base.opts.Name or "Settings", function(container)
			buildModuleSettings(container, base)
		end)
	end

	--  Right click on a module gear: the compact, auto height panel.
	ctx.toggleCompactSettings = function(base)
		if compactTarget == base and compactOpen then
			closeCompact()
			return
		end
		--  the full height flyout gives way to the compact popup
		closeFlyout()
		compactTarget = base
		openCompact(base.opts and base.opts.Name or "Settings", function(container)
			buildModuleSettings(container, base)
		end)
	end

	ctx.isSettingsOpen = function(base)
		return (flyoutOpen and settingsTarget == base) or (compactOpen and compactTarget == base)
	end

	--  Global settings panel (topbar gear / configuration manager) --------
	local openGlobalSettings
	local repaint

	--  Topbar search box.  The widgets are created further down (once the tabs
	--  infrastructure exists) but the settings panel and the drag handler need
	--  to see them, so the names are forward declared here.
	local searchHolder, searchBox, searchClear, applySearch, setSearchEnabled
	local searchStroke, searchGlassStroke, searchGlassHandle, searchClearBarA, searchClearBarB
	local searchEnabled = settings.Search ~= false and settings.SearchBar ~= false
	local searchQuery = ""

	--  Menu open key ----------------------------------------------------
	--  Resolution order:
	--      CreateWindow{ OpenKey = "K" }   (aliases: DefaultOpenKey,
	--      DefaultKey, MenuKey, OpenKeybind, ToggleKey, ToggleUIKeybind)
	--          -> XClient.OpenKey (library default)
	--              -> "K"
	--  The bind appears in the settings panel as "Menu open key", is stored in
	--  the configuration like any other flag and can be changed with
	--  XClient:SetOpenKey("K") or Window:SetOpenKey("K").
	--  Key names are canonicalised against Enum.KeyCode (see resolveKeyName),
	--  so "Space", "space" and Enum.KeyCode.Space all become "Space" and the
	--  bind keeps working whatever casing it was stored with.
	local normalizeKey = resolveKeyName

	local toggleKey = normalizeKey(settings.OpenKey)
		or normalizeKey(settings.DefaultOpenKey)
		or normalizeKey(settings.DefaultKey)
		or normalizeKey(settings.MenuKey)
		or normalizeKey(settings.OpenKeybind)
		or normalizeKey(settings.ToggleKey)
		or normalizeKey(settings.ToggleUIKeybind)
		or normalizeKey(XClient.OpenKey)
		or "K"

	local openKeyRow
	local openKeyHint

	--  The menu key is registered as a flag element up front, so a saved
	--  configuration can restore the bind even when the settings panel was
	--  never opened in this session.
	local openKeyElement = {
		Type = "Keybind",
		Flag = "xclient_open_key",
		Name = "Menu open key",
		CurrentKeybind = toggleKey,
		Value = toggleKey,
	}

	local function setOpenKey(value)
		local key = normalizeKey(value)
		if key == nil then
			--  "No key bound" is asked for with an empty string (or with
			--  Unknown); any other value this build cannot read - an old
			--  configuration may hold "Enum.KeyCode.Space" - must never throw
			--  the bind that is in force away, or the interface would become
			--  impossible to open.
			local text = tostring(value or "")
			local enumItem = typeof(value) == "EnumItem"
			if text ~= "" and text ~= "Enum.KeyCode.Unknown" then return false end
			if enumItem and text == "" then return false end
			key = ""
		end
		toggleKey = key
		openKeyElement.CurrentKeybind = key
		openKeyElement.Value = key
		XClient.OpenKey = key
		if openKeyRow and openKeyRow.SetSilent then openKeyRow:SetSilent(key) end
		if openKeyHint then
			openKeyHint.Text = key ~= ""
				and ("Press " .. key .. " to show or hide the interface")
				or "No menu key bound"
			fitLabel(openKeyHint, PANEL_WIDTH - 24, { MaxSize = 12, MinSize = 9, Wrap = true })
		end
		return true
	end

	function openKeyElement:Set(value) setOpenKey(value) end
	function openKeyElement:SetSilent(value) setOpenKey(value) end
	function openKeyElement:Get() return toggleKey end

	registerFlag(ctx, openKeyElement, toggleKey, "Keybind", openKeyElement)
	openKeySetters[#openKeySetters + 1] = setOpenKey
	ctx.setOpenKey = setOpenKey

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
			--  Save / Load / Delete act on the name that is on screen, even if
			--  the field still has the focus when the button is pressed.
			LiveUpdate = true,
			Callback = function(text) configName = text end,
		})

		--  Auto-save switch.  While it is on the reserved "autocfg" file is
		--  rewritten (debounced) whenever an element changes, so the menu comes
		--  back exactly as it was left.  Turn it off to keep only the manual,
		--  named configurations.  The switch itself is remembered in
		--  XClient/Preferences.rfld so it survives while auto-save is off.
		builders.Toggle(container, ctx, {
			Name = "Auto-save (autocfg)",
			Description = "Remember the menu automatically between sessions",
			CurrentValue = configState.autoSave,
			Callback = function(state)
				configState.autoSave = state and true or false
				writePreferences()
				if configState.autoSave then
					saveConfiguration()
					XClient:Notify({
						Title = "XClient Configurations",
						Content = "Auto-save enabled - the menu now remembers its state as '" .. tostring(configState.fileName or "autocfg") .. "'.",
					})
				else
					XClient:Notify({
						Title = "XClient Configurations",
						Content = "Auto-save disabled - use Save / Load for named configurations.",
					})
				end
			end,
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
			local savedHeading = newText({
				Name = "Heading",
				Text = "SAVED",
				Font = THEME_FONT_BOLD,
				TextSize = 11,
				TextColor3 = currentTheme.TextDim,
				Size = UDim2.new(1, 0, 0, 15),
				Parent = listHolder,
			})
			fitLabel(savedHeading, PANEL_WIDTH - 24, { MinSize = 9 })
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

		openKeyRow = builders.Keybind(container, ctx, {
			Name = "Menu open key",
			Description = "Shows and hides the whole menu",
			CurrentKeybind = toggleKey,
			CallOnChange = true,
			Callback = function(key) setOpenKey(key) end,
		})

		openKeyHint = newText({
			Name = "OpenKeyHint",
			Text = toggleKey ~= "" and ("Press " .. toggleKey .. " to show or hide the interface") or "No menu key bound",
			TextSize = 11,
			TextColor3 = currentTheme.TextDim,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 26),
			Parent = container,
		})
		fitLabel(openKeyHint, PANEL_WIDTH - 24, { MinSize = 9, Wrap = true })

		builders.Button(container, ctx, {
			Name = "Reset open key to K",
			Callback = function()
				setOpenKey("K")
				XClient:Notify({ Title = "XClient", Content = "Menu open key reset to K." })
			end,
		})

		builders.Toggle(container, ctx, {
			Name = "Search bar",
			Description = "Filter modules and tabs from the topbar",
			CurrentValue = searchEnabled,
			Callback = function(state)
				if setSearchEnabled then setSearchEnabled(state) end
			end,
		})

		--  Font -------------------------------------------------------
		builders.Section(container, ctx, "Font")
		builders.Dropdown(container, ctx, {
			Name = "Interface font",
			Description = "CS = condensed HUD type",
			Options = { "CS", "Classic", "Mono" },
			CurrentOption = XClient.Font,
			Callback = function(value)
				local name = type(value) == "table" and value[1] or value
				if XClient:SetFont(name) then
					XClient:Notify({ Title = "XClient", Content = "Interface font set to " .. tostring(name) .. "." })
				end
			end,
		})
	end

	openGlobalSettings = function()
		--  the topbar panel is the full height one; any compact popup gives way
		closeCompact()
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
		if minimised then
			closeFlyout()
			closeCompact()
		end
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
		if not visible then
			--  Popups live on the window, so dismiss any open one with it.
			ctx.closePopup()
			closeFlyout()
			closeCompact()
			--  A hidden interface must not keep the keyboard: the open key
			--  would be typed into an invisible field instead of toggling the
			--  menu back on.
			releaseTextBoxFocus()
		end
	end
	ctx.setVisible = setVisible
	ctx.isVisible = function() return visible end

	--  Handing the keyboard back (see watchKeyboardOwnership): a press that
	--  misses the field, or a respawn.  Registered with the window so
	--  XClient:Destroy() can drop them again.
	watchKeyboardOwnership()

	ctx.connections[#ctx.connections + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not toggleKey or toggleKey == "" then return end
		--  Both sides are canonical member names, so "Space" (and every other
		--  CamelCase code) matches whatever casing the bind was stored with.
		--  While a text field owns the keyboard the key belongs to the field:
		--  typing "my config" must not make the interface disappear.
		if textBoxFocused() then return end
		if resolveKeyName(input.KeyCode) == toggleKey then
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
	--  the topbar title must never run underneath the three window buttons
	fitLabel(title, WINDOW_WIDTH - (iconImage and 168 or 118), { MinSize = 11 })

	--  Loading animation -------------------------------------------------
	--  CS style boot sequence over the interface: HUD brackets, the title, a
	--  bar with a moving shimmer and a percentage counter, then a fade out.
	--      Loading = true | false | <seconds>     (defaults to on as soon as a
	--                                             title or subtitle is given)
	--      LoadingTitle, LoadingSubtitle, LoadingSteps = { "Loading", ... },
	--      LoadingDuration = 1.5
	local loadData = type(settings.Loading) == "table" and settings.Loading or nil
	local loadingRequested = settings.Loading ~= false
		and (settings.Loading == true or type(settings.Loading) == "number"
			or loadData ~= nil or settings.LoadingTitle ~= nil or settings.LoadingSubtitle ~= nil)

	if loadingRequested then
		local duration = tonumber(settings.LoadingDuration)
			or (type(settings.Loading) == "number" and settings.Loading)
			or (loadData and tonumber(loadData.Duration))
			or 1.5
		if duration < 0.2 then duration = 0.2 end
		local titleText = settings.LoadingTitle or (loadData and loadData.Title) or tostring(settings.Name or "XClient")
		local subtitleText = settings.LoadingSubtitle or (loadData and loadData.Subtitle) or "Interface Suite"
		local stepList = settings.LoadingSteps or (loadData and loadData.Steps) or {
			"Loading modules",
			"Building interface",
			"Applying configuration",
			"Ready",
		}
		if type(stepList) ~= "table" or #stepList == 0 then stepList = { subtitleText } end
		local theme = currentTheme

		local splash = newFrame({
			Name = "Loading",
			BackgroundColor3 = theme.Background,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = root,
		})
		splash.ZIndex = 60
		addCorner(splash, UDim.new(0, 10))

		--  HUD corner brackets (procedural, no assets)
		for _, spec in ipairs({ { 0, 0, 1, 1 }, { 0, 0, -1, 1 }, { 0, 1, 1, -1 }, { 0, 1, -1, -1 } }) do
			local anchorX = spec[3] > 0 and 0 or 1
			local anchorY = spec[4] > 0 and 0 or 1
			local horizontal = newFrame({
				Name = "Bracket",
				BackgroundColor3 = theme.Accent,
				Size = UDim2.fromOffset(16, 2),
				Position = UDim2.new(spec[1], spec[3] * 12, spec[2], spec[4] * 12),
				AnchorPoint = Vector2.new(anchorX, anchorY),
				Parent = splash,
			})
			horizontal.ZIndex = 61
			local vertical = newFrame({
				Name = "Bracket",
				BackgroundColor3 = theme.Accent,
				Size = UDim2.fromOffset(2, 16),
				Position = UDim2.new(spec[1], spec[3] * 12, spec[2], spec[4] * 12),
				AnchorPoint = Vector2.new(anchorX, anchorY),
				Parent = splash,
			})
			vertical.ZIndex = 61
		end
		local splashTitle = newText({
			Name = "Title",
			Text = tostring(titleText),
			Font = THEME_FONT_BOLD,
			TextSize = 20,
			TextColor3 = theme.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -60, 0, 24),
			Position = UDim2.new(0, 30, 0.5, -30),
			Parent = splash,
		})
		splashTitle.ZIndex = 62
		local splashSubtitle = newText({
			Name = "Subtitle",
			Text = tostring(stepList[1] or subtitleText),
			TextSize = 12,
			TextColor3 = theme.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -60, 0, 16),
			Position = UDim2.new(0, 30, 0.5, 4),
			Parent = splash,
		})
		splashSubtitle.ZIndex = 62

		local track = newFrame({
			Name = "BarTrack",
			BackgroundColor3 = theme.SliderTrack,
			Size = UDim2.fromOffset(math.floor(WINDOW_WIDTH * 0.5), 4),
			Position = UDim2.new(0.5, 0, 0.5, 30),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = splash,
		})
		track.ZIndex = 61
		addCorner(track, UDim.new(1, 0))

		local fill = newFrame({
			Name = "BarFill",
			BackgroundColor3 = theme.Accent,
			Size = UDim2.new(0, 0, 1, 0),
			Parent = track,
		})
		fill.ZIndex = 62
		addCorner(fill, UDim.new(1, 0))

		local shimmer = newFrame({
			Name = "Shimmer",
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.5,
			Size = UDim2.fromOffset(70, 4),
			Position = UDim2.new(0, -80, 0, 0),
			Parent = track,
		})
		shimmer.ZIndex = 63
		addCorner(shimmer, UDim.new(1, 0))

		local percent = newText({
			Name = "Percent",
			Text = "0%",
			TextSize = 11,
			Font = THEME_FONT_BOLD,
			TextColor3 = theme.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(70, 14),
			Position = UDim2.new(1, 0, 0, -18),
			Parent = track,
		})
		percent.ZIndex = 62

		fitLabel(splashTitle, WINDOW_WIDTH - 120, { MaxSize = 20, MinSize = 12 })
		fitLabel(splashSubtitle, WINDOW_WIDTH - 120, { MaxSize = 12, MinSize = 10 })
		--  fade the overlay in and grow the bar across the whole duration
		tween(splash, 0.18, { BackgroundTransparency = 0.02 })
		tween(fill, duration * 0.92, { Size = UDim2.new(1, 0, 1, 0) })

		--  the shimmer sweeps the bar while the interface loads (repeats in the
		--  engine itself, so no Lua loop is left running)
		if TweenService then
			pcall(function()
				local info = TweenInfo.new(0.9, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false)
				TweenService:Create(shimmer, info, { Position = UDim2.new(1, 10, 0, 0) }):Play()
			end)
		end

		--  percentage + status text step along with the bar (a bounded chain of
		--  delays, so nothing keeps ticking once the interface is up)
		local steps = 20
		local index = 0
		local function tick()
			if not (splash and splash.Parent) then return end
			if index >= steps then return end
			index = index + 1
			local ratio = index / steps
			percent.Text = string.format("%d%%", math.floor(ratio * 100 + 0.5))
			local stepName = stepList[math.min(#stepList, math.floor(ratio * #stepList) + 1)]
			if stepName then
				splashSubtitle.Text = tostring(stepName)
				fitLabel(splashSubtitle, WINDOW_WIDTH - 120, { MaxSize = 12, MinSize = 10 })
			end
			if index < steps then
				task.delay(duration / steps, tick)
			end
		end
		task.delay(duration / steps, tick)

		--  fade everything out and drop the overlay
		task.delay(duration, function()
			if not (splash and splash.Parent) then return end
			tween(splash, 0.3, { BackgroundTransparency = 1 })
			tween(splashTitle, 0.3, { TextTransparency = 1 })
			tween(splashSubtitle, 0.3, { TextTransparency = 1 })
			tween(percent, 0.3, { TextTransparency = 1 })
			tween(track, 0.3, { BackgroundTransparency = 1 })
			tween(fill, 0.3, { BackgroundTransparency = 1 })
			tween(shimmer, 0.3, { BackgroundTransparency = 1 })
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
		local built
		if record.type == "Label" then
			built = builders.Label(container, ctx, record.arg1, record.arg2, record.arg3, record.arg4)
		elseif record.type == "Section" then
			built = builders.Section(container, ctx, record.name)
		elseif record.type == "Divider" then
			built = builders.Divider(container, ctx)
		else
			built = builders[record.type](container, ctx, record.opts)
		end
		--  Remember the built element so the topbar search can show/hide the
		--  exact instance a record produced (rows expose .Row, labels, sections
		--  and dividers expose .Element).
		record.built = built
		return built
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
		--  rail is narrow: shrink, then wrap, so tab names are never cut off
		fitLabel(label, RAIL_WIDTH - (iconImage and 42 or 28), { MinSize = 10, Wrap = true })

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
		--  Multi-select dropdown: a CreateDropdown with MultipleOptions forced
		--  on, so the list stays open while several options are ticked and the
		--  selector shows the number of selected entries.
		function tab:CreateMultiDropdown(settings)
			settings = settings or {}
			settings.MultipleOptions = true
			settings.Multi = true
			return addRecord({ type = "Dropdown", opts = settings })
		end
		function tab:CreateInput(settings) return addRecord({ type = "Input", opts = settings or {} }) end
		function tab:CreateKeybind(settings) return addRecord({ type = "Keybind", opts = settings or {} }) end
		function tab:CreateColorPicker(settings) return addRecord({ type = "ColorPicker", opts = settings or {} }) end
		function tab:CreateParagraph(settings) return addRecord({ type = "Paragraph", opts = settings or {} }) end
		--  A Neverlose style card that holds other elements (see section 18).
		function tab:CreateGroupBox(settings) return addRecord({ type = "GroupBox", opts = settings or {} }) end
		function tab:CreateDivider() return addRecord({ type = "Divider" }) end
		function tab:CreateSection(sectionName) return addRecord({ type = "Section", name = sectionName }) end

		function tab:CreateLabel(text, icon, color, ignoreTheme)
			return addRecord({ type = "Label", arg1 = text, arg2 = icon, arg3 = color, arg4 = ignoreTheme })
		end

		--  Extended widgets (section 9b): viewers and input pads that also
		--  work inside a module's Settings flyout.
		function tab:CreatePlayerWidget(settings) return addRecord({ type = "PlayerWidget", opts = settings or {} }) end
		function tab:CreateImage(settings) return addRecord({ type = "Image", opts = settings or {} }) end
		function tab:CreateCrosshair(settings) return addRecord({ type = "Crosshair", opts = settings or {} }) end
		function tab:CreateGraph(settings) return addRecord({ type = "Graph", opts = settings or {} }) end
		function tab:CreateProgress(settings) return addRecord({ type = "Progress", opts = settings or {} }) end
		function tab:CreateStepper(settings) return addRecord({ type = "Stepper", opts = settings or {} }) end
		function tab:CreateSegment(settings) return addRecord({ type = "Segment", opts = settings or {} }) end
		function tab:CreateWheel(settings) return addRecord({ type = "Wheel", opts = settings or {} }) end
		function tab:CreateAnalog(settings) return addRecord({ type = "Analog", opts = settings or {} }) end
		function tab:CreateRadar(settings) return addRecord({ type = "Radar", opts = settings or {} }) end
		function tab:CreateChips(settings) return addRecord({ type = "Chips", opts = settings or {} }) end
		--  friendly aliases
		function tab:CreatePlayerPreview(settings) return tab:CreatePlayerWidget(settings) end
		function tab:CreateSkinPreview(settings) return tab:CreateImage(settings) end
		function tab:CreateLoader(settings) return tab:CreateProgress(settings) end

		--  Rebuilds every element of this page (used on theme changes).
		function tab:Refresh()
			setupPage()
			for _, record in ipairs(records) do
				buildRecord(record, page)
			end
			if searchQuery ~= "" and applySearch then applySearch() end
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
		compact.BackgroundColor3 = theme.Surface
		compactStroke.Color = theme.Stroke
		compactTitle.TextColor3 = theme.Text
		compactBody.ScrollBarImageColor3 = theme.Stroke
		compactBarA.BackgroundColor3 = theme.TextMuted
		compactBarB.BackgroundColor3 = theme.TextMuted
		for _, entry in ipairs(tabs) do
			entry.page.ScrollBarImageColor3 = theme.Stroke
			entry.button.BackgroundColor3 = entry.page.Visible and theme.Surface or theme.Rail
			entry.label.TextColor3 = entry.page.Visible and theme.Text or theme.TextMuted
			if entry.icon then
				entry.icon.ImageColor3 = entry.page.Visible and theme.Accent or theme.TextMuted
			end
		end
		--  Topbar search box colours: it sits outside the tab pages, so the
		--  per-page rebuild below does not reach it.
		if searchHolder then
			searchHolder.BackgroundColor3 = theme.Surface
			if searchStroke then searchStroke.Color = theme.StrokeSoft end
			if searchGlassStroke then searchGlassStroke.Color = theme.TextDim end
			if searchGlassHandle then searchGlassHandle.BackgroundColor3 = theme.TextDim end
			if searchClearBarA then searchClearBarA.BackgroundColor3 = theme.TextMuted end
			if searchClearBarB then searchClearBarB.BackgroundColor3 = theme.TextMuted end
			if searchBox then
				searchBox.TextColor3 = theme.Text
				searchBox.PlaceholderColor3 = theme.TextDim
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
		--  rebuilding the rows resets their visibility, so re-apply the filter
		if applySearch then applySearch() end
	end

	--=========================================================================
	--  Topbar search
	--=========================================================================
	--  A slim module filter that lives on the title bar, level with the window
	--  name.  Typing hides every row that does not match, hides sections that
	--  lost all of their rows and jumps to the first tab that still has a hit;
	--  clearing the box restores the whole menu.  A tab whose *name* matches
	--  keeps all of its rows, so typing a tab name shows that tab in full.
	local SEARCH_WIDTH = 200
	local SEARCH_RIGHT = 96    -- room kept free for the three window buttons

	searchHolder = newFrame({
		Name = "Search",
		BackgroundColor3 = currentTheme.Surface,
		Size = UDim2.fromOffset(SEARCH_WIDTH, 24),
		Position = UDim2.new(1, -SEARCH_RIGHT, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Visible = searchEnabled,
		Parent = topbar,
	})
	searchHolder.ZIndex = 14
	addCorner(searchHolder, UDim.new(0, 6))
	searchStroke = addStroke(searchHolder, currentTheme.StrokeSoft, 1, 0.1)

	--  Hand-drawn magnifier so the bar needs no image assets.
	local glass = newFrame({
		Name = "Glass",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(9, 9),
		Position = UDim2.new(0, 8, 0.5, -1),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = searchHolder,
	})
	glass.ZIndex = 15
	addCorner(glass, UDim.new(1, 0))
	searchGlassStroke = addStroke(glass, currentTheme.TextDim, 1.4, 0)
	searchGlassHandle = newFrame({
		Name = "Handle",
		BackgroundColor3 = currentTheme.TextDim,
		Size = UDim2.fromOffset(4, 1.4),
		Position = UDim2.new(0, 6, 0, 6),
		AnchorPoint = Vector2.new(0, 0.5),
		Rotation = 45,
		Parent = glass,
	})
	searchGlassHandle.ZIndex = 16

	searchBox = create("TextBox", {
		Name = "Box",
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "Search",
		PlaceholderColor3 = currentTheme.TextDim,
		TextColor3 = currentTheme.Text,
		Font = THEME_FONT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, -52, 1, 0),
		Position = UDim2.fromOffset(24, 0),
		Parent = searchHolder,
	})
	searchBox.ZIndex = 15

	searchClear = create("TextButton", {
		Name = "Clear",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(1, -5, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Visible = false,
		Parent = searchHolder,
	})
	searchClear.ZIndex = 15
	searchClearBarA = newFrame({ BackgroundColor3 = currentTheme.TextMuted, Size = UDim2.fromOffset(7, 1.4), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45, Parent = searchClear })
	searchClearBarB = newFrame({ BackgroundColor3 = currentTheme.TextMuted, Size = UDim2.fromOffset(7, 1.4), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -45, Parent = searchClear })
	searchClearBarA.ZIndex = 16
	searchClearBarB.ZIndex = 16
	--  Case folding that also understands Cyrillic (string.lower only touches
	--  ASCII), so "кол" matches "Количество" however it was typed.
	local function foldCase(text)
		text = string.lower(tostring(text or ""))
		text = text:gsub("\208([\144-\175])", function(second)
			local n = string.byte(second)
			if n <= 0x9F then return "\208" .. string.char(n + 0x20) end
			return "\209" .. string.char(n - 0x20)
		end)
		text = text:gsub("\208\129", "\209\145")
		text = text:gsub("^%s+", "")
		text = text:gsub("%s+$", "")
		return text
	end

	--  Rows expose .Row, everything else (label / section / divider / paragraph)
	--  exposes .Element - reach whichever one the record produced.
	local function recordRow(built)
		if type(built) ~= "table" then return nil end
		return built.Row or built.Element
	end

	local function recordName(record, built)
		if type(built) == "table" and built.Name ~= nil and built.Name ~= "" then
			return tostring(built.Name)
		end
		local o = record.opts
		if o and o.Name ~= nil then return tostring(o.Name) end
		return ""
	end

	applySearch = function()
		local query = foldCase(searchQuery)
		local searching = query ~= ""

		local function matchesRow(name, wholeTab)
			if not searching then return true end
			if wholeTab then return true end
			if name == "" then return false end
			return string.find(foldCase(name), query, 1, true) ~= nil
		end

		local firstMatch, currentHasMatch
		for _, entry in ipairs(tabs) do
			local records = entry.records
			local wholeTab = searching and string.find(foldCase(entry.name), query, 1, true) ~= nil
			local rowMatch = {}
			for i = 1, #records do
				rowMatch[i] = matchesRow(recordName(records[i], records[i].built), wholeTab)
			end

			local tabHas = false
			for i = 1, #records do
				local record = records[i]
				local row = recordRow(record.built)
				if row then
					local t = record.type
					if t == "Section" then
						-- resolved in the pass below
					elseif t == "Divider" or t == "Label" or t == "Paragraph" then
						row.Visible = not searching
					else
						row.Visible = rowMatch[i]
						if rowMatch[i] then tabHas = true end
					end
				end
			end

			--  A section only stays while at least one of ITS rows is visible.
			for i = 1, #records do
				if records[i].type == "Section" then
					local row = recordRow(records[i].built)
					local keep = not searching
					if searching and row then
						for j = i + 1, #records do
							local t = records[j].type
							if t == "Section" then break end
							if t ~= "Label" and t ~= "Paragraph" and t ~= "Divider" and rowMatch[j] then
								keep = true
								break
							end
						end
					end
					if row then row.Visible = keep end
				end
			end

			if searching then
				if wholeTab and #records > 0 then tabHas = true end
				entry.searchMatch = tabHas
				if tabHas and not firstMatch and not entry.ext then firstMatch = entry end
				if entry.page.Visible and tabHas then currentHasMatch = true end
			end
		end

		--  Don't leave the user staring at an empty page: hop to the first tab
		--  that still has a matching row.
		if searching and not currentHasMatch and firstMatch then
			showTab(firstMatch.page)
		end
	end




	--  Re-fit the caption so it never runs underneath the search box.
	--  The caption starts at x = 16 and the three window buttons take the last
	--  130 px of the bar (that is what its Size above reserves), so without the
	--  search bar that is the width it gets; with the bar on it stops short of
	--  it.  The label itself is narrowed as well, so even a forced ellipsis can
	--  never paint over the search field.
	local TOPBAR_TITLE_X = 16
	local TOPBAR_TITLE_RESERVE = 130
	--  Remember the size the caption was born with, so turning the search bar
	--  off again restores its full size instead of freezing the shrunk one.
	local TOPBAR_TITLE_MAX = title.TextSize or 15
	local function fitTopbarTitle()
		local width = WINDOW_WIDTH - TOPBAR_TITLE_X - TOPBAR_TITLE_RESERVE
		if searchEnabled then
			width = (WINDOW_WIDTH - SEARCH_RIGHT - SEARCH_WIDTH) - TOPBAR_TITLE_X - 10
		end
		if width < 48 then width = 48 end
		title.Size = UDim2.new(0, width, 1, 0)
		fitLabel(title, width, { MaxSize = TOPBAR_TITLE_MAX, MinSize = 11 })
	end

	setSearchEnabled = function(state)
		searchEnabled = state and true or false
		if searchHolder then searchHolder.Visible = searchEnabled end
		if not searchEnabled and searchBox and searchBox.Text ~= "" then
			searchBox.Text = ""
		end
		searchQuery = (searchBox and searchBox.Text) or ""
		if applySearch then applySearch() end
		fitTopbarTitle()
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		searchQuery = searchBox.Text
		searchClear.Visible = foldCase(searchQuery) ~= ""
		applySearch()
	end)

	searchClear.MouseButton1Click:Connect(function()
		searchBox.Text = ""
		searchQuery = ""
		searchClear.Visible = false
		applySearch()
	end)

	--  The topbar drag handler also catches clicks that land on the search box
	--  (it is a child of the topbar); undo that on the next step so selecting
	--  or editing text never drags the window around.  Hooked on both the bar
	--  and the box so it works no matter which object the input targets.
	local function guardDrag(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			task.defer(function() dragging = false end)
		end
	end
	searchHolder.InputBegan:Connect(guardDrag)
	searchBox.InputBegan:Connect(guardDrag)

	--  Apply the initial state (also re-fits the title bar caption).
	setSearchEnabled(searchEnabled)


	--  The library keeps a handle on this window's repaint, so SetFont()
	--  reaches every interface that is currently on screen.
	registerRepainter(function() repaint() end)

	--  Window methods (names kept from the previous interface) -----------
	function Window:Notify(data)
		XClient:Notify(data)
	end

	--  Menu open key of this window (see the "Menu open key" row in settings)
	function Window:SetOpenKey(key)
		setOpenKey(key)
		return toggleKey
	end

	function Window:GetOpenKey()
		return toggleKey
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
	function Window:HideSettings()
		closeFlyout()
		closeCompact()
	end

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

	--  Autoload the saved configuration once the script finished building and
	--  create the auto-save file on the first run, so the menu starts
	--  remembering its state right away.
	configState.loaded = true
	task.delay(1, function()
		if configState.enabled and not configState.autoLoaded then
			configState.autoLoaded = true
			loadConfiguration()
			if configState.autoSave and not configFileExists() then
				saveConfiguration()
			end
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

--  Favourite colours ------------------------------------------------------
--  Shared palette rendered to the right of every colour picker (3x3 grid).
--    XClient:SetFavoriteColor(index, Color3)   -- index 1 .. XClient.FavoriteSlots
--    XClient:GetFavoriteColor(index) -> Color3?
--    XClient:GetFavoriteColors()      -> array
--    XClient:ClearFavoriteColor(index)
--  The palette is stored inside the configuration (reserved key
--  __favorite_colors) and auto-saved like any other element.
function XClient:GetFavoriteColor(index)
	index = tonumber(index)
	if not index then return nil end
	return XClient.FavoriteColors[index]
end

function XClient:GetFavoriteColors()
	local out = {}
	for i = 1, FAVORITE_SLOTS do out[i] = XClient.FavoriteColors[i] end
	return out
end

function XClient:SetFavoriteColor(index, color)
	index = tonumber(index)
	if not index or index < 1 or index > FAVORITE_SLOTS then return false end
	if typeof(color) ~= "Color3" then return false end
	XClient.FavoriteColors[index] = color
	requestAutoSave()
	return true
end

function XClient:ClearFavoriteColor(index)
	index = tonumber(index)
	if not index or index < 1 or index > FAVORITE_SLOTS then return false end
	XClient.FavoriteColors[index] = nil
	requestAutoSave()
	return true
end

--  Auto-save --------------------------------------------------------------
--  XClient:SetAutoSave(false) keeps the menu from overwriting its stored
--  state while leaving the manual Save / Load panel fully usable.
function XClient:SetAutoSave(state)
	configState.autoSave = state and true or false
	writePreferences()
	if configState.autoSave then
		saveConfiguration()
	end
	return configState.autoSave
end

function XClient:GetAutoSave()
	return configState.autoSave
end

--  Font ------------------------------------------------------------------
--  XClient:SetFont("CS") / ("Classic") / ("Mono") or a full profile table
--      { Primary = Enum.Font.Oswald, Strong = Enum.Font.Oswald,
--        Mono = Enum.Font.RobotoMono, Offset = 1 }
--  Every open interface is rebuilt with the new face straight away.
function XClient:SetFont(profile)
	profile = profile or "CS"
	local name
	if type(profile) == "table" then
		name = profile.Name or "Custom"
		FONT_PROFILES[name] = profile
	elseif type(profile) == "string" then
		name = profile
	end
	local resolved = name and FONT_PROFILES[name]
	if not resolved then return false end
	FONT_PROFILE = name
	THEME_FONT = resolved.Primary or THEME_FONT
	THEME_FONT_BOLD = resolved.Strong or resolved.Primary or THEME_FONT_BOLD
	THEME_FONT_MONO = resolved.Mono or THEME_FONT_MONO
	FONT_SIZE_OFFSET = tonumber(resolved.Offset) or 0
	THEME_FACE = resolved.Face
	XClient.Font = name
	for _, repaint in ipairs(repainters) do callSafe(repaint) end
	return true
end

function XClient:GetFont()
	return XClient.Font
end

--  Menu open key ---------------------------------------------------------
--  Sets the default bind for every window, including the ones already open.
function XClient:SetOpenKey(key)
	local normalized = resolveKeyName(key)
	if normalized == nil then return false end
	XClient.OpenKey = normalized
	for _, setter in ipairs(openKeySetters) do callSafe(setter, normalized) end
	return true
end

function XClient:GetOpenKey()
	return XClient.OpenKey
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
		--  the settings flyout files the connections of its rows separately
		if activeContext.flyoutConnections then
			for _, connection in ipairs(activeContext.flyoutConnections) do
				pcall(function() connection:Disconnect() end)
			end
		end

	activeContext = nil
	end
	--  the focus watchers belong to the interface that just went away; the next
	--  window registers its own pair again
	for index = #focusWatchConnections, 1, -1 do
		local connection = focusWatchConnections[index]
		focusWatchConnections[index] = nil
		pcall(function() connection:Disconnect() end)
	end
	if screenGui and screenGui.Parent then
		screenGui:Destroy()
	end
	screenGui = nil
	notifications = nil
	XClient.Flags = {}
	XClient.Windows = {}
	--  drop the repaint / open key handles of the windows that just died
	clearRegistries()
end

--  Expose the library globally, the way the previous interface did, so any
--  script that grabbed it from the executor environment keeps working.
if getgenv then
	getgenv().XClient = XClient
end

return XClient
