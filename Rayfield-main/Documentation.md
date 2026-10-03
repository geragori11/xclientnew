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

On repeat injections the whole file is fetched again every time. `loader.lua`
ships a lighter, disk-cached entry point instead — it keeps a local copy of the
library and only asks the repository for a tiny version marker (see section 17):

```lua
local XClient = loadstring(game:HttpGet("URL_TO/loader.lua"))()
```

---

## 2. Creating a window

```lua
local Window = XClient:CreateWindow({
	Name = "My Script",              -- window / topbar title
	Icon = 0,                        -- 0, an asset id, or a named icon
	LoadingTitle = "My Script",      -- optional boot animation title
	LoadingSubtitle = "by me",       -- optional boot animation subtitle
	LoadingDuration = 1.5,           -- boot animation length (false disables it)
	Theme = "Default",               -- Neverlose | Midnight | Blood (+ aliases)
	OpenKey = "K",                   -- default key that shows/hides the menu
	ToggleUIKeybind = "K",           -- legacy alias of OpenKey, still accepted

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
| `Window:SetOpenKey(key)` / `Window:GetOpenKey()` | change / read the menu open key (section 14) |
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

### CreateMultiDropdown
The multi-select list is the same (`MultipleOptions = true`); `CreateMultiDropdown`
just turns it on for you and the selector shows how many entries are ticked
(`"3 selected"`). The list stays open while you toggle entries.

```lua
Tab:CreateMultiDropdown({
	Name = "ESP parts",
	Options = { "Head", "Torso", "Arms", "Legs" },
	CurrentOption = { "Torso" },   -- array of selected names
	Flag = "espParts",
	Callback = function(options) end,
})
-- returned: .CurrentOption (array), .Options, :Set(value), :Refresh(newOptions)
```

Dropdown lists keep up with the row while the page is scrolled (and close once
the row scrolls out of view, the tab is switched or a rebuild happens).

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
hex field. The popup is **wider** than before and carries a 3x3 grid of
**favourite colour slots** (9 slots) to the right of the picker:

| Action on a slot | Result |
| --- | --- |
| Left click, empty slot | store the current colour |
| Left click, filled slot | apply the stored colour to the picker |
| Shift + left click, filled slot | overwrite the slot with the current colour |
| Right click | clear the slot |

The palette is shared by every picker, saved with the configuration under the
reserved key `__favorite_colors` and can also be driven from code:

```lua
XClient.FavoriteSlots                       -- 9
XClient:GetFavoriteColor(1)                 -- Color3 or nil
XClient:GetFavoriteColors()                 -- array of 9 (holes allowed)
XClient:SetFavoriteColor(1, Color3.fromRGB(255, 0, 0))
XClient:ClearFavoriteColor(1)
```

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
  arrays for dropdowns and `{R, G, B}` (0-255) for colour pickers. The shared
  favourite-colour palette is stored under the reserved key `__favorite_colors`.
* **Auto-save is on by default.** `CreateWindow` keeps a running configuration in
  `XClient/Configurations/autocfg.rfld`: it is created on the first run and
  loaded right after `CreateWindow`, so the menu comes back exactly as it was
  left. Pass a `ConfigurationSaving` table to pick another file, or
  `ConfigurationSaving = { Enabled = false }` to opt out.
* Every flagged element change (toggle, slider, dropdown, colour picker, input,
  keybind and the extended widgets) is written back automatically, debounced by
  roughly 0.4 s so a slider drag only writes once.
* The in-menu switch *Settings → Configuration → Auto-save (autocfg)* turns the
  automatic writes off/on. That choice is remembered on its own in
  `XClient/Preferences.rfld`, so it survives while auto-save is off; the manual
  named configuration buttons keep working either way.
* Configurations saved by the previous interface are read from the old
  `Configurations` folder too, and their exact value shape is understood.

```lua
XClient:SaveConfiguration()            -- save to the configured file
XClient:LoadConfiguration()            -- load the configured file
XClient:SaveConfigurationAs("PvP")     -- named snapshot
XClient:LoadConfigurationAs("PvP")
XClient:DeleteConfiguration("PvP")
XClient:ListConfigurations()           -- { "PvP", "Legit", ... }
XClient:SetAutoSave(false)             -- stop the automatic writes
XClient:GetAutoSave()                  -- current auto-save switch
```

The topbar gear opens the built-in panel: theme picker, the auto-save switch,
save / load / delete for the named configuration, the list of saved
configurations and the interface keybind.

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

Elements added on top of the previous interface (all backwards compatible):

| Element | Create call | Section |
| --- | --- | --- |
| PlayerWidget | `Tab:CreatePlayerWidget` | 16.1 |
| Image with markers | `Tab:CreateImage` | 16.2 |
| Crosshair / FOV pad | `Tab:CreateCrosshair` | 16.3 |
| Graph | `Tab:CreateGraph` | 16.4 |
| Progress / loader | `Tab:CreateProgress` | 16.5 |
| Stepper | `Tab:CreateStepper` | 16.6 |
| Segmented control | `Tab:CreateSegment` | 16.7 |
| Wheel | `Tab:CreateWheel` | 16.8 |
| Analog stick | `Tab:CreateAnalog` | 16.9 |
| Radar | `Tab:CreateRadar` | 16.10 |
| Chips | `Tab:CreateChips` | 16.11 |

---

## 13. Fonts (CS style by default)

The interface ships with three font profiles; the default is **CS** — the
condensed, squared off HUD face competitive shooters use.

| Profile | Text | Titles | Size offset |
| --- | --- | --- | --- |
| `CS` (default) | `RobotoCondensed` | `Oswald` | +1 |
| `Classic` | `Gotham` | `GothamBold` | 0 |
| `Mono` | `RobotoMono` | `Code` | -1 |

```lua
XClient:SetFont("Classic")     -- CS | Classic | Mono
XClient:GetFont()              -- "CS"
XClient.Fonts                  -- every profile

--  register your own
XClient:SetFont({
	Name = "Navy",
	Primary = Enum.Font.Sarpanch,
	Strong = Enum.Font.Sarpanch,
	Mono = Enum.Font.Code,
	Offset = 1,
})
```

`SetFont` rebuilds every open window straight away, so the switch is visible
immediately. The player can do the same from the settings panel
(`Font → Interface font`).

### Using a real CS font file

Roblox only ships its own font families, so the `CS` profile uses the closest
built-in condensed faces. If you have the Counter-Strike face (or any other)
uploaded, hand XClient its asset through a profile — it is applied as `FontFace`
through a safety check, so a client without that property simply keeps the
`Enum.Font` families of the profile:

```lua
XClient:SetFont({
	Name = "CS Real",
	Primary = Enum.Font.RobotoCondensed,
	Strong = Enum.Font.Oswald,
	Face = "rbxasset://fonts/families/GothamSSm.json",  -- or "rbxassetid://<font>"
	Offset = 1,
})
```

### Captions always fit

Every caption is measured (`TextService:GetTextSize`) and fitted into the space
it really has:

* long row titles are stepped down to `TextSize` 10;
* if even that is too wide the row **grows** and the caption wraps onto a second
  line, so nothing is cut off mid-word;
* control labels (keybinds, selectors, slider values, wheel entries, option
  lists) shrink and finally receive an ellipsis, because their boxes have a
  fixed height.

This applies inside tabs **and** inside the narrower settings flyout — the
window tells the row builders the smaller width while it populates the flyout.

---

## 14. Menu open key

The key that shows / hides the whole menu is a first class setting: pick a
default in `CreateWindow` and the player can rebind it from the settings panel.

```lua
local Window = XClient:CreateWindow({ Name = "My Script", OpenKey = "RightShift" })
```

Accepted option names (the first one found wins): `OpenKey`, `DefaultOpenKey`,
`DefaultKey`, `MenuKey`, `OpenKeybind`, `ToggleKey`, `ToggleUIKeybind` (the name
the previous interface used), then `XClient.OpenKey`, then `"K"`. Values may be
strings (`"K"`, `"RightShift"`) or `Enum.KeyCode.K`.

```lua
XClient:SetOpenKey("F5")             -- default for every window, incl. open ones
XClient:SetOpenKey(Enum.KeyCode.G)
XClient:GetOpenKey()                 -- "G"
Window:SetOpenKey("K") / Window:GetOpenKey()
```

Inside the interface: **settings gear → Interface → "Menu open key"**. The row is
a normal keybind (click it and press a key, mouse button 2 clears it), a hint
line under it always shows the current bind and a `Reset open key to K` button
restores the default.

The bind is stored in the configuration under the flag `xclient_open_key`, so it
survives `SaveConfiguration()` / `LoadConfiguration()` like any other element.

---

## 15. Loading animation

Creating the window plays a short CS style boot sequence over the interface:
HUD corner brackets, the title, a bar that fills up while a shimmer sweeps it, a
percentage counter and a status line that steps through the loading stages. When
it is done the overlay fades out and removes itself. The window itself slides and
scales into place instead of popping in.

```lua
local Window = XClient:CreateWindow({
	Name = "My Script",
	Loading = true,                     -- false turns the animation off
	LoadingTitle = "My Script",         -- big line
	LoadingSubtitle = "by me",          -- line under it
	LoadingSteps = { "Loading modules", "Building interface", "Ready" },
	LoadingDuration = 1.5,              -- seconds
})
```

* `Loading = false` — no animation at all.
* `Loading = <number>` (or `LoadingDuration`) — length in seconds.
* `Loading = { Title = ..., Subtitle = ..., Steps = ..., Duration = ... }` —
  table form, the same keys as above.
* Without any of these options nothing is shown, so old scripts behave exactly
  as before.

---

## 16. Extra widgets

Every widget below follows the same contract as the classic elements: it is
created on a tab, returns the settings table, supports `Flag`, `Description`,
`Settings` (the gear flyout) and `:Set(...)`, and it can be used inside a module's
`Settings` list — so a viewer such as **PlayerWidget** can be the skin preview of
a module. Each of them also defines `:Serialize()` / `:Set(value)` for the
configuration system; a different element type is saved back in the same `.rfld`.

### 16.1 PlayerWidget — interactive character

```lua
local Widget = Tab:CreatePlayerWidget({
	Name = "Skin preview",
	Flag = "skin",
	Description = "Click a body part to highlight it",
	Selected = { "Torso" },                      -- initial highlights
	Skin = { Head = Color3.fromRGB(240, 200, 120) },  -- or a single Color3
	AllowMultiple = true,                        -- false -> only one part at a time
	Callback = function(region, isOn, widget) end,
})
```

The character (head, torso, two arms, two legs) is drawn procedurally and every
part is both a picture and a variable:

```lua
Widget.Highlight.Torso = true     -- picture repaints immediately
Widget.Highlight.torso = true     -- lower case works as well
Widget.Highlight["left arm"] = true
Widget.Highlight.All = false      -- clears everything
Widget.Skin.Head = Color3.fromRGB(255, 210, 80)   -- recolour the picture
print(Widget.Highlight.Torso, Widget:GetRegion("Torso"))
```

| Member | Description |
| --- | --- |
| `Widget.Highlight` | live table: `Widget.Highlight.Torso = true/false` |
| `Widget.Skin` | live table of `Color3` per region |
| `Widget.Regions` | the six region names |
| `Widget.Selected` | array of the highlighted regions |
| `Widget:SetRegion(name, on)` / `:GetRegion(name)` | programmatic access, name above (`"torso"`, `"left arm"`, `"all"`) |
| `Widget:SetSkin(name, color)` / `:GetSkin(name)` | recolour one part |
| `Widget:GetSelection()` | copy of `Selected` |
| `Widget:Clear()` / `:Refresh()` | clear / repaint |
| `Widget:Set(arrayOrTable)` | `{ "Head", "Torso" }`, a name, or `{ Regions = ..., Skin = ... }` |
| `Widget.Stage` | the frame the character is drawn in |

`Serialize()` stores the array of highlighted regions, which is what a
configuration writes into the `.rfld` file.

### 16.2 Image with markers — skin / UI visualisation

```lua
local Picture = Tab:CreateImage({
	Name = "Skin picture",
	Flag = "skinMarker",
	Image = 4483362458,                          -- asset id, url or named icon
	Height = 140,
	Points = { Gun = { 0.8, 0.3 } },             -- extra marker points (0 - 1)
})

Picture.Marker.Torso = true      -- draws the dot, repaints immediately
Picture.Marker.head = true
Picture:SetMarker("LeftLeg", Color3.fromRGB(255, 90, 90))
Picture:SetTint(Color3.fromRGB(200, 220, 255))
```

| Member | Description |
| --- | --- |
| `Picture.Marker` | live table — any truthy value shows the marker at that point |
| `Picture.Points` | live table of normalised points (`{ x, y }`), edit or extend it |
| `Picture:SetMarker(name, state)` / `:IsMarked(name)` | programmatic access |
| `Picture:SetMarkers(array)` / `:GetMarked()` | all markers at once |
| `Picture:AddPoint(name, x, y)` / `:RemovePoint(name)` | extra points (gun, backpack, …) |
| `Picture:SetImage(icon)` / `:SetTint(color)` / `:SetTransparency(n)` | picture controls |
| `Picture:ClearMarkers()` | remove every marker |

Default points are the six character regions, so `Marker.Torso = true` marks the
torso of a skin render without any extra setup. `Serialize()` stores the marked
region names.

### 16.3 Crosshair / FOV pad

```lua
local Crosshair = Tab:CreateCrosshair({
	Name = "Aim FOV", Flag = "fov", FOV = 90, MaxFOV = 360,
	Dot = { X = 0.1, Y = -0.2 },                 -- -1 - 1 inside the pad
	Callback = function(value) end,              -- { FOV = , X = , Y = }
})
Crosshair:SetFOV(120)      Crosshair:SetOffset(0, 0.5)
Crosshair:Set({ FOV = 45, X = 0, Y = 0 })
print(Crosshair.FOV, Crosshair.Dot.X, Crosshair.Dot.Y)
```

The circle is the field of view and drags the dot inside the pad. `MaxFOV`
clamps `FOV`; `Serialize()` returns `{ FOV = , X = , Y = }`.

### 16.4 Graph

```lua
local Graph = Tab:CreateGraph({ Name = "Ping", Flag = "ping", Max = 300, Samples = 40 })
Graph:Push(42)        -- shift in one sample
Graph:Set(120)        -- same as :Push
Graph:Clear()
print(Graph.CurrentValue, Graph:GetValues()[1])
```

Bars are colour coded (green → accent → red) and grow with the value between
`Min` (default 0) and `Max`. `Serialize()` returns the newest sample.

### 16.5 Progress / loader

```lua
local Loader = Tab:CreateProgress({
	Name = "Loading", Flag = "load", Min = 0, Max = 100,
	Indeterminate = true,             -- sweeping shimmer (default: off)
})
Loader:Set(40)          Loader:SetRatio(0.4)      -- 0 - 1 fraction
Loader:Tween(100, 0.6)  Loader:Stop()   Loader:Start()
```

Without `Min` / `Max` the value is a `0 - 1` fraction. `Serialize()` returns the
current value; `Running` tells whether the shimmer is active.

### 16.6 Stepper

```lua
local Step = Tab:CreateStepper({
	Name = "Delay", Flag = "delay", Min = 0, Max = 1000,
	Increment = 25, Suffix = " ms", Wrap = false,
})
Step:Step(1)     Step:Increment()     Step:Decrement()     Step:Set(300)
print(Step.CurrentValue)      -- number
```

### 16.7 Segmented control

```lua
local Mode = Tab:CreateSegment({
	Name = "Mode", Flag = "mode", CurrentOption = "Legit",
	Options = { "Legit", "Rage", "Auto" }, PerLine = 3,
})
Mode:Set("Rage")      print(Mode.CurrentOption)
Mode:Toggle("Auto")   -- Multi = true for a multi select strip
```

`CurrentOption` is a string for a single choice and an array when `Multi = true`
(`AllowDeselect` also allows clearing it). `Serialize()` follows the same shape,
and `:GetOptions()` returns a copy of the option list.

### 16.8 Wheel

```lua
local Wheel = Tab:CreateWheel({
	Name = "Hitbox", Flag = "hitbox", CurrentOption = "Head",
	Options = { "Head", "Torso", "Nearest" },
})
Wheel:Next()      Wheel:Previous()      Wheel:Set("Torso")     Wheel:SetIndex(1)
```

Three rows are visible at once and the middle one is the active choice; the
chevrons and the option rows are clickable. `GetIndex()` returns the position.

### 16.9 Analog stick

```lua
local Stick = Tab:CreateAnalog({ Name = "Movement", Flag = "move", Deadzone = 0.1 })
Stick:Set(0.5, -0.5)      Stick:Set({ X = 0, Y = 1 })      Stick:Center()
print(Stick.CurrentValue.X, Stick.CurrentValue.Magnitude, Stick:IsActive())
```

`CurrentValue` holds `X`, `Y` (each `-1 - 1`) and the computed `Magnitude`;
`IsActive()` is true once the stick leaves the `Deadzone`.

### 16.10 Radar

```lua
local Radar = Tab:CreateRadar({ Name = "Radar", Max = 24, SweepTime = 2.4 })
Radar:Push({ X = 0.2, Y = -0.4, Color = Color3.fromRGB(255, 90, 90), Size = 9 })
Radar:SetBlips({ { X = 0, Y = 0.6 } })     Radar:Clear()
```

Blips are normalised (`1` = outer ring), the sweep line rotates on its own and
the list is capped at `Max`. Radar is a pure viewer, so it is not written to
configurations.

### 16.11 Chips

```lua
local Chips = Tab:CreateChips({
	Name = "Bones", Flag = "bones", Options = { "Head", "Torso", "Arms" },
	CurrentOptions = { "Head" },
})
Chips:Toggle("Arms")      Chips:Set({ "Head", "Torso" })
print(#Chips:GetSelection())
```

A compact multi select strip (rounded pills) for tight layouts;
`CurrentOptions` / `GetSelection()` / `Serialize()` are arrays.

### 16.12 Inside a module's settings (skin visualisation)

Every widget works inside the gear flyout, so a module can show its own skin
preview and let it drive (or follow) the module's settings:

```lua
local Aimbot = Tab:CreateToggle({
	Name = "Aimbot",
	Flag = "aimbot",
	Settings = {
		"Skin",
		{
			Type = "PlayerWidget",
			Name = "Skin visualisation",
			Flag = "aimbotSkin",
			Skin = { Torso = Color3.fromRGB(255, 90, 90) },
			Callback = function(region, isOn)
				--  whatever should follow the picture, e.g. the aim part
				print("aim part:", region, isOn)
			end,
		},
		{ Type = "Crosshair", Name = "FOV",       FOV = 90, Flag = "aimbotFov" },
		{ Type = "Stepper",   Name = "Smoothing", Min = 1, Max = 20, CurrentValue = 5, Flag = "aimbotSmooth" },
		{ Type = "Chips",     Name = "Bones",     Options = { "Head", "Torso", "Arms" }, Flag = "aimbotBones" },
		{ Type = "Progress",  Name = "Charge",    CurrentValue = 0.4, Flag = "aimbotCharge" },
		{ Type = "Segment",   Name = "Mode",      Options = { "Legit", "Rage" }, CurrentOption = "Legit" },
		{ Type = "Image",     Name = "Preview",   Image = 4483362458, Flag = "aimbotPreview" },
	},
})
```

Friendly aliases: `Tab:CreatePlayerPreview` (PlayerWidget),
`Tab:CreateSkinPreview` (Image) and `Tab:CreateLoader` (Progress).

#### Configuration value shapes

| Element | Saved value |
| --- | --- |
| PlayerWidget | array of highlighted regions, e.g. `["Head","Torso"]` |
| Image | array of marked region names |
| Chips / Segment (`Multi`) | array of the selected options |
| Segment (single) / Wheel | the selected option name |
| Crosshair | `{ FOV = 90, X = 0, Y = 0 }` |
| Analog | `{ X = 0, Y = 1 }` |
| Graph / Progress / Stepper | number |
| Keybind / Toggle / Dropdown / Slider / Input / ColorPicker | unchanged |

The widgets restore themselves through the same `:Set(value)` entry point the
classic elements use, so `LoadConfiguration()` re-applies them without any extra
code.

---

## 17. Auto-loader (disk cache)

`loader.lua` is an optional, lightweight replacement for the one-shot HTTP fetch
in section 1. It keeps a local copy of the library on disk and, on later runs,
only asks the repository for a tiny version marker instead of re-downloading the
whole file.

```lua
local XClient = loadstring(game:HttpGet("URL_TO/loader.lua"))()
```

The loader returns the same library table `xclient.lua` returns, so the rest of a
script is unchanged.

Behaviour:

| Situation | What happens |
| --- | --- |
| First run (no cache) | downloads `xclient.lua`, runs it and writes it to the cache with `writefile` |
| Later run, same version | one short version request, then the saved file is loaded from disk with `readfile` |
| New version published | re-downloads `xclient.lua`, refreshes the cache and runs the fresh copy |
| Version request fails / offline | keeps using the cached copy |

Files (inside the executor's workspace folder):

| Path | Purpose |
| --- | --- |
| `XClient/xclient.lua` | the cached library |
| `XClient/.version` | the last seen remote version / hash |

### Configuration

Edit `Loader.Config` at the top of `loader.lua`:

| Key | Default | Description |
| --- | --- | --- |
| `User`, `Repo`, `Branch`, `File` | placeholder | where the library lives on GitHub |
| `VersionURL` | `nil` | optional tiny marker file (e.g. `version.txt`) used instead of the GitHub API |
| `Folder` | `"XClient"` | cache folder |
| `CacheFile` | `"xclient.lua"` | cached library name |
| `MarkerFile` | `".version"` | cached version marker name |
| `Cache` | `true` | `false` always re-downloads (handy while editing) |
| `Offline` | `true` never touches the network | use the cached copy only |

**Version source.** With `VersionURL = nil` the loader asks the GitHub API for the
hash of the latest commit that touched `File`
(`/repos/<User>/<Repo>/commits?path=<File>&per_page=1`) — it changes on its own
every time the library is pushed, so there is nothing to keep in sync by hand.
Point `VersionURL` at a small published marker (the loader fetches it instead)
for a shorter request and no API rate limit.

**Overriding without editing the file.** Set `getgenv().XClientLoaderOptions`
before loading it:

```lua
getgenv().XClientLoaderOptions = { User = "me", Repo = "MyHub", Branch = "main" }
local XClient = loadstring(game:HttpGet("URL_TO/loader.lua"))()
```

### Utilities

The loader is also exposed as `getgenv().XClientLoader`:

```lua
local Loader = getgenv().XClientLoader
Loader:GetVersion()        -- the version stored in the cache
Loader:CheckForUpdate()    -- remoteVersion, hasUpdate
Loader:Update()            -- force a re-download into the cache (does not run it)
Loader:ClearCache()        -- remove the cached library and its marker
Loader:Load()              -- run the whole load sequence again
```

---


