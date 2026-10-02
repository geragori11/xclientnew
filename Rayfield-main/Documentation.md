# XClient Interface Suite — documentation

A self-contained, Neverlose-style interface library for Roblox. The UI is drawn
entirely with `Instance.new`, so it does **not** depend on any remote template
asset, and its public API is a drop-in match for the interface this project
used to ship, so existing scripts keep working without edits.

---

## 1. Loading

```lua
local XClient = loadstring(game:HttpGet("URL_TO/xclient.lua"))()
```

The library is also placed in the executor environment as `getgenv().XClient`.

---

## 2. Creating a window

```lua
local Window = XClient:CreateWindow({
	Name = "My Script",              -- window / topbar title
	Icon = 0,                        -- 0, an asset id, or a named icon
	LoadingTitle = "My Script",      -- optional splash title
	LoadingSubtitle = "by me",       -- optional splash subtitle
	Theme = "Default",               -- Neverlose | Midnight | Blood (+ aliases)
	ToggleUIKeybind = "K",           -- hide/show key, string or Enum.KeyCode

	ConfigurationSaving = {
		Enabled = true,
		FileName = "My Config",      -- saved as <folder>/My Config.rfld
		FolderName = nil,            -- optional custom folder
	},
})
```

Unknown keys are ignored, so settings copied from older scripts (`Discord`,
`KeySystem`, `KeySettings`, `Disable...` flags, …) are accepted safely.

`CreateWindow` returns immediately — the script can build its elements on the
very next line.

### Window methods

| Method | Description |
| --- | --- |
| `Window:CreateTab(Name, Image, Ext)` | new tab; `Image` may be an asset id or icon name; `Ext = true` hides it from the rail |
| `Window:Notify(data)` | same as `XClient:Notify` |
| `Window.ModifyTheme(nameOrTable)` | switch theme (dot **and** colon calls work) |
| `Window:SaveConfiguration()` | write the current values to the configured file |
| `Window:LoadConfiguration()` | load the configured file |
| `Window:SetVisibility(bool)` / `Window:IsVisible()` | show / hide the interface |
| `Window:ShowSettings()` / `Window:HideSettings()` | open / close the left settings flyout |
| `Window:Destroy()` | remove the interface |

---

## 3. Tabs

```lua
local Tab    = Window:CreateTab("Combat", 4483362458)
local ExtTab = Window:CreateTab("Internal", nil, true)   -- hidden from the rail
```

Tab helpers: `Tab:Select()`, `Tab:Refresh()` (rebuilds the page), `Tab:Destroy()`.

---

## 4. Elements

Every `Tab:Create*` returns the settings table you passed in, extended with the
live state and a `:Set()` method — exactly like the previous interface:

```lua
local Toggle = Tab:CreateToggle({ Name = "Aimbot", CurrentValue = false, Flag = "aimbot", Callback = function(v) end })
Toggle.CurrentValue   --> false
Toggle.Value          --> same value
Toggle:Set(true)      --> updates the UI and fires Callback(true)
```

`Flag` is optional; supply it to make the element part of configuration saving
and to reach it through `XClient.Flags["aimbot"]`.

### CreateButton
```lua
Tab:CreateButton({ Name = "Reload", Callback = function() end })
-- returned: :Set(newName)
```

### CreateToggle
```lua
Tab:CreateToggle({
	Name = "Aimbot",
	CurrentValue = false,          -- alias: Value
	Flag = "aimbot",
	Description = "optional muted line",   -- new
	Settings = { ... },                     -- new: adds the gear button
	Callback = function(value) end,         -- value is a boolean
})
-- returned: .CurrentValue / .Value, :Set(v), :SetSilent(v)
```

### CreateSlider
```lua
Tab:CreateSlider({
	Name = "Field of view",
	Range = { 10, 360 },           -- aliases: Min / Max
	Increment = 5,
	Suffix = "deg",
	CurrentValue = 90,
	Flag = "fov",
	Callback = function(value) end,         -- value is a number
})
-- returned: .CurrentValue, .Min, .Max, .Range, .Suffix, :Set(v), :SetSilent(v)
```

### CreateDropdown
```lua
Tab:CreateDropdown({
	Name = "Hitbox",
	Options = { "Head", "Torso" },
	CurrentOption = "Head",        -- string or table
	MultipleOptions = false,       -- alias: Multi
	Flag = "hitbox",
	Callback = function(options) end,       -- always a table of selected names
})
-- returned: .CurrentOption (array), .Options, :Set(value), :Refresh(newOptions)
```

### CreateInput
```lua
Tab:CreateInput({
	Name = "Webhook",
	CurrentValue = "",
	PlaceholderText = "https://...",         -- alias: Placeholder
	RemoveTextAfterFocusLost = false,        -- alias: RemoveTextOnLeave
	Flag = "webhook",
	Callback = function(text) end,           -- fired when the box loses focus
})
-- returned: .CurrentValue, :Set(text), :SetSilent(text)
```

### CreateKeybind
```lua
Tab:CreateKeybind({
	Name = "Toggle aimbot",
	CurrentKeybind = "Q",          -- a plain string such as "Q" or "LeftShift"
	HoldToInteract = false,        -- true -> Callback(true) while held, Callback(false) on release
	CallOnChange = false,          -- true -> Callback(keyName) whenever the bind changes
	Flag = "aimbotKey",
	Callback = function(state) end,
})
-- returned: .CurrentKeybind, :Set("E")
```
Click the box and press a key to rebind. Mouse button 2 clears the bind.

### CreateColorPicker
```lua
Tab:CreateColorPicker({
	Name = "Highlight",
	Color = Color3.fromRGB(255, 255, 255),
	Flag = "highlight",
	Callback = function(color) end,          -- color is a Color3
})
-- returned: .Color, :Set(color3), :SetSilent(color3)
```
The row shows a swatch; clicking it opens a hue / saturation-value popup with a
hex field.

### CreateLabel
```lua
Tab:CreateLabel("Simple label")
Tab:CreateLabel("Warning", 4483362458, Color3.fromRGB(255, 159, 49), true)
-- returned: :Set(newText, icon, color)
```

### CreateParagraph
```lua
Tab:CreateParagraph({ Title = "Info", Content = "Wrapped text." })
-- returned: :Set({ Title = "...", Content = "..." })
```

### CreateSection / CreateDivider
```lua
Tab:CreateSection("Aim")        -- returned: :Set(newName)
Tab:CreateDivider()             -- returned: :Set(visible)
```

---

## 5. Per module settings (the gear button)

Give any element a non-empty `Settings` table and a gear appears on the right of
its row. Clicking it slides a settings panel in from the **left** of the window,
built from the same element builders:

```lua
Tab:CreateToggle({
	Name = "Aimbot",
	Callback = function(v) end,
	Settings = {
		{ Type = "Slider",  Name = "FOV",     Range = { 10, 360 }, CurrentValue = 90, Flag = "fov" },
		{ Type = "Toggle",  Name = "Visible", CurrentValue = true,  Flag = "visible" },
		{ Type = "Dropdown", Name = "Bone",   Options = { "Head", "Torso" }, CurrentOption = "Head", Flag = "bone" },
		{ Type = "ColorPicker", Name = "Colour", Color = Color3.fromRGB(255, 60, 60), Flag = "colour" },
		{ Type = "Keybind", Name = "Hold",    CurrentKeybind = "C", HoldToInteract = true, Flag = "hold" },
		{ Type = "Button",  Name = "Reset",   Callback = function() end },
		"Section name",                 -- a plain string creates a section
	},
})
```

Nested settings register their own flags, so they are saved and loaded with the
rest of the configuration.

---

## 6. The flag registry

```lua
XClient.Flags["aimbot"]              -- the element table itself
XClient.Flags["aimbot"].CurrentValue -- its current value
XClient.Flags["aimbot"]:Set(true)    -- same as Toggle:Set(true)
```

---

## 7. Configuration system

* Files live in `XClient/Configurations/<FileName>.rfld`
  (`FolderName` replaces `XClient/Configurations` entirely).
* Format: a flat `{ "Flag": value, ... }` map — booleans, numbers, strings,
  arrays for dropdowns and `{R, G, B}` (0-255) for colour pickers.
* The file named in `ConfigurationSaving` is loaded automatically right after
  `CreateWindow`; call `XClient:LoadConfiguration()` to force it manually.
* Everything is written again whenever a flagged element changes.
* Configurations saved by the previous interface are read from the old
  `Configurations` folder too, and their exact value shape is understood.

```lua
XClient:SaveConfiguration()            -- save to the configured file
XClient:LoadConfiguration()            -- load the configured file
XClient:SaveConfigurationAs("PvP")     -- named snapshot
XClient:LoadConfigurationAs("PvP")
XClient:DeleteConfiguration("PvP")
XClient:ListConfigurations()           -- { "PvP", "Legit", ... }
```

The topbar gear opens the built-in panel: theme picker, save / load / delete for
the named configuration, the list of saved configurations and the interface
keybind.

---

## 8. Themes

Names: `Neverlose` (default), `Midnight`, `Blood`, plus the aliases the older
interface used (`Default`, `Dark`, `Light`, `Green`, `Ocean`, `DarkBlue`,
`Serenity`, `Amethyst`, `Aqua`, `Bloom`, `AmberGlow`, `BloodRed`, `Pink`,
`Valentine`).

```lua
Window.ModifyTheme("Midnight")
Window:ModifyTheme("Midnight")                                   -- same
Window.ModifyTheme({ Background = Color3.fromRGB(12, 12, 12) })  -- custom overrides
```

A custom table is merged on top of the default palette; unknown names simply
return `false` and raise a notification. Changing the theme repaints the window
and rebuilds every element, keeping all current values.

---

## 9. Icons

`Icon`, tab images and label icons accept:

* a number — Roblox asset id;
* `"rbxassetid://..."` or a URL;
* a name such as `"key-round"`, resolved through `XClient.Icons`.

`icons.lua` in this repository holds the Lucide sheets; hand its `48px` table
over once and string icons keep working:

```lua
XClient.Icons = loadstring(readfile("icons.lua"))()["48px"]
```

Sprite rectangles (`{ id, { width, height }, { x, y } }`) are applied
automatically.

---

## 10. Notifications

```lua
XClient:Notify({ Title = "Loaded", Content = "All good.", Duration = 5 })
Window:Notify({ Title = "Hello" })
```

`Image` is accepted and ignored — XClient draws notifications without remote
assets.

---

## 11. Visibility and teardown

```lua
XClient:SetVisibility(false)   -- hide
XClient:IsVisible()            -- boolean
XClient:Destroy()              -- tear the interface down (the X button does this)
```

---

## 12. Compatibility summary

| Previous behaviour | Status |
| --- | --- |
| Every `Create*` name, option name and `:Set` method | kept |
| Elements return the settings table (`CurrentValue`, `CurrentOption`, `CurrentKeybind`, `Color`) | kept |
| `Window.ModifyTheme`, `Window:CreateTab(Name, Image, Ext)`, positional `CreateLabel` / `CreateSection` / `CreateDivider` | kept |
| `XClient.Flags[flag]` registry | kept |
| `.rfld` configuration files, folder layout and value shape | kept (the old folder is read too) |
| Keybind strings such as `"Q"`, `HoldToInteract`, `CallOnChange` | kept |
| Dropdown callbacks receiving a table | kept |
| Theme names used by the old scripts | mapped onto the three palettes |
| Discord join prompts, the key system, build warnings | not implemented — the settings are accepted and ignored |
| Notification `Image` | accepted and ignored |
| Remote template asset | replaced by a fully procedural UI |
| Named icons | work once `XClient.Icons` is filled (section 9) |

New in XClient: the per module gear with the left settings flyout, the
`Description` line, the in-window configuration panel and the theme picker.


