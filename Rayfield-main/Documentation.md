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

The library can also keep a script's features in **separate files on GitHub** and
load them itself, instead of shipping one monolithic `main.lua` (see section 18):

```lua
XClient:InitModules(Window, { Modules = { { Name = "Combat", URL = "URL_TO/modules/combat.lua" } } })
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
	LiveUpdate = false,                      -- true: Callback also fires per keystroke
	Flag = "webhook",
	Callback = function(text) end,           -- fired when the box loses focus
})
-- returned: .CurrentValue, :Set(text), :SetSilent(text)
```

`LiveUpdate` hands every keystroke to `Callback` instead of waiting for the focus
to leave the box (the configuration name field in the settings panel uses it, so
Save / Load always act on the name that is on screen). Nothing is written to disk
per keystroke — the configuration is still saved when the focus leaves.

A box never keeps the keyboard once the player is done with it: pressing Enter or
Escape, clicking anything outside the box (Save included), hiding the menu,
closing the panel and a respawn all release it. See section 14 for why that
matters in a game.

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

### CreateGroupBox
```lua
Tab:CreateGroupBox({
	Name = "Aim",
	Elements = {
		{ Type = "Toggle", Name = "Enabled", Flag = "aimEnabled" },
		{ Type = "Slider", Name = "FOV", Range = { 1, 180 }, Flag = "aimFov" },
		"Advanced",                             -- a plain string is a section
	},
})
-- returned: :Add(e)  :AddMany(list)  :Clear()  :SetTitle(text)
--           :Set({ Name, Elements })  :Serialize()  :Load(values)
```
A Neverlose style card that holds other elements — see **section 19**.

---

## 5. Per module settings (the gear button)

Give any element a non-empty `Settings` table and a gear appears on the right of
its row. **Left click** slides the full height settings flyout in from the
**left** of the window — as tall as the window, scrolling if the rows do not fit.
(The flyout replaces what used to be a second, compact panel; right clicking the
gear now does nothing.) The topbar gear opens the same full height panel.

The panel is wider than it looks: rows get a **stacked slider layout** — the
caption sits on its own line above a full width track, with the value read-out
on the caption line — so a long module name can never end up underneath the
slider's read-out.

Both are built from the same element builders:

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

The rows behind the gear are **built on demand**: the panel is populated the
first time the gear is pressed, so a nested flag does not exist in
`XClient.Flags` — and its `Callback` has not run even once — before that. Drive
a module from its own `Callback`, or open the panel once (press the gear, or
`Window:ShowSettings()` for the built-in panel) before reading
`XClient.Flags["nestedFlag"]`.

Every open rebuilds the rows from scratch. That rebuild is leak-free — the
instances, the signal connections and the input handlers are all released again
when the panel closes; `_devtest.lua` section 26 proves it for the full flyout
by opening and closing the panel a hundred times and comparing the counters, and
section 27 does the same for the reopened gear panel (connections `+0`,
instances `+0`, input handlers `+0`) while also checking that right clicking a
gear is a no-op. So if a menu starts lagging after a
while in a live game, measure before changing the layout: `_leakcheck.lua` prints
the connection / object counts over time, and the row that keeps growing names
the culprit (the interface, the game script's own loops, or a loop restarted on
every respawn).

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
* **Per-module settings are always saved.** A row's `Settings = { ... }` table is
  registered with the configuration system up front, so its nested flags exist
  even when the module's gear flyout was never opened in this session. A config
  loaded before the gear is opened is applied the moment the gear builds its rows.
* Names are sanitised before they reach the filesystem (whitespace runs are
  collapsed, `/ \ : * ? " < > |` and control characters are dropped, trailing
  dots and spaces are trimmed, the result is capped at 64 characters). An empty
  or unusable name is refused with a reason instead of failing silently.
* A value the build cannot express as JSON (a stray `Color3` or Instance left in
  a descriptor, a widget the build does not describe) is **left out of the file**
  rather than aborting the save, so one awkward flag can never cost every other
  setting. The `{{R, G, B}}` colour shape is read back correctly whether a
  descriptor hands over a `Color3` or an already packed table.

```lua
XClient:SaveConfiguration()            -- save to the configured file
XClient:LoadConfiguration()            -- load the configured file
local ok, name = XClient:SaveConfigurationAs("PvP")      -- true, name
local ok, name = XClient:LoadConfigurationAs("PvP")      -- or false, reason
local ok, name = XClient:DeleteConfiguration("PvP")
XClient:ListConfigurations()           -- { "PvP", "Legit", ... }
XClient:SetAutoSave(false)             -- stop the automatic writes
XClient:GetAutoSave()                  -- current auto-save switch
```

`SaveConfigurationAs` / `LoadConfigurationAs` / `DeleteConfiguration` return
`true, <name>` on success and `false, <reason>` on failure (the reason is a short
sentence suitable for a notification). The first value is still the boolean older
scripts check, so existing code keeps working.

The topbar gear opens the built-in panel: theme picker, the auto-save switch, the
configuration manager and the interface keybind. The manager lists every saved
configuration under a `SAVED` heading, with the auto-saved file first and tagged
`AUTO`. Clicking a row selects it (the row is highlighted and its name is copied
into the field above); clicking the selected row again clears the selection. Each
row has its own **Load** and **Delete** buttons, so a configuration can be loaded
or removed without typing its name. **Saving over an existing name and deleting
both open a confirmation dialog** (the deletion button is red), and the result of
every action is reported truthfully — a failed write is never announced as saved.

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
| AvatarPreview (3D) | `Tab:CreateAvatarPreview` | 16.13 |
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
| Group box card | `Tab:CreateGroupBox` | 19 |

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

Key names are canonicalised against `Enum.KeyCode`, which is case sensitive:
whatever you pass — `"K"`, `"space"`, `"SPACE"`, `"RightShift"` or
`Enum.KeyCode.Space` — becomes the member name the Enum really uses (`"Space"`,
`"RightShift"`), and that is what `GetOpenKey()` returns and what the
configuration holds. Saves written by the previous interface are read back the
same way: it stored `tostring(Enum.KeyCode.Space)`, i.e. `"Enum.KeyCode.Space"`,
and upper cased every name (`"SPACE"`), so an old `xclient_open_key` still arms
the bind after loading instead of clearing it. A stored value that is not a key
at all is ignored and the bind that is in force stays — only `""` (or
`Enum.KeyCode.Unknown`) really means "no key bound".

Keystrokes that belong to a text field are never shortcuts: while the
configuration name field or the topbar search box owns the keyboard, the open key
reaches the field instead of toggling the interface and keybind callbacks stay
quiet. Hiding the menu or closing the settings panel releases the field, so the
open key keeps working straight away.

The keyboard is handed back from every side a field can trap it, so nothing has
to be escaped before the game reacts to keys again:

* **Enter / Escape** — the engine's own behaviour, unchanged;
* **any press that misses the field** — a click or tap on Save, a slider, a tab,
  the top bar or any other element of the interface releases it. A press *inside*
  the box (selecting the text) is left alone;
* **a respawn** — `LocalPlayer.CharacterAdded` releases the field, so a half
  typed name cannot follow the player into the next life;
* **hiding the menu / closing the panel**, as described above.

The second one is the one that matters in a game: a field that kept the focus
after a configuration name was typed swallowed *every* later key — the jump key
included — so the character could only jump again after it had died and the
engine cleared the focus for us. Both hooks are registered with the first window
and disconnected again in `XClient:Destroy()`.

While the caret is inside a box, Space types a space: that is what a text field
is for, and configuration names may well contain spaces. Click anything else (or
press Enter) once the name is complete and the key is a shortcut again.

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
`Settings` list — so a viewer such as **PlayerWidget** or the 3D
**AvatarPreview** can be the skin preview of a module. Each of them also defines
`:Serialize()` / `:Set(value)` for the configuration system; a different element
type is saved back in the same `.rfld`.

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
`Tab:CreateAvatar` (AvatarPreview), `Tab:CreateSkinPreview` (Image) and
`Tab:CreateLoader` (Progress).

#### Configuration value shapes

| Element | Saved value |
| --- | --- |
| PlayerWidget | array of highlighted regions, e.g. `["Head","Torso"]` |
| AvatarPreview | array of highlighted regions (the camera is not saved) |
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

### 16.13 AvatarPreview — real 3D avatar

A real 3D character inside a `ViewportFrame` (`WorldModel` + `Camera`), not a
picture: **drag to orbit, scroll to zoom**, and the same live `Highlight` /
`Skin` variables `PlayerWidget` exposes. Highlighted parts get an **ESP style
tint** — `Enum.Material.Neon` plus the theme accent colour.

```lua
local Avatar = Tab:CreateAvatarPreview({
	Name = "Target",
	Flag = "target",
	Height = 210,                                  -- viewport height
	Yaw = 24, Pitch = -12, Zoom = 1,               -- initial camera
	Selected = { "Torso" },                        -- initial highlights
	Skin = { Head = Color3.fromRGB(240, 200, 120) },
	Callback = function(region, isOn, widget) end,
})

Avatar.Highlight.Torso = true      -- the part turns neon immediately
Avatar.Highlight.All = false       -- back to the solid skin colour
Avatar:Rotate(35, -12)             -- orbit (yaw, pitch in degrees)
Avatar:SetZoom(0.8)                -- 0.45 (close) .. 2.4 (far)
Avatar:ResetCamera()

--  load a real avatar: a Player, a UserId or a Model
Avatar:SetTarget(Players.LocalPlayer)   -- also watches CharacterAdded
Avatar:SetUserId(1)
Avatar:SetModel(Players.LocalPlayer.Character)
```

A blocky R6 stand-in is built straight away, so the widget always renders; an
actual avatar replaces it once the client can fetch it (`SetTarget` /
`SetUserId` go through `Players:CreateHumanoidModelFromUserId`, which is a no-op
when the executor cannot provide it). `SetModel` maps an avatar's parts onto the
six regions (R6 `"Left Arm"` and R15 `"LeftUpperArm"` / `"LeftUpperLeg"` alike).

| Member | Description |
| --- | --- |
| `Avatar.Highlight` / `Avatar.Skin` | live tables, exactly like PlayerWidget |
| `Avatar:SetRegion` / `:GetRegion` / `:SetSkin` / `:GetSkin` | per region access |
| `Avatar:GetSelection()` / `:Serialize()` / `:Clear()` / `:Refresh()` | as PlayerWidget |
| `Avatar:Rotate(deltaYaw, deltaPitch)` | orbit the camera |
| `Avatar:SetZoom(factor)` / `:GetZoom()` | zoom in / out (clamped 0.45 – 2.4) |
| `Avatar:GetYaw()` | current `yaw, pitch` |
| `Avatar:ResetCamera()` | back to the `Yaw` / `Pitch` / `Zoom` options |
| `Avatar:SetTarget(playerOrUserIdOrModel)` | load a real avatar |
| `Avatar:SetUserId(userId)` / `Avatar:SetModel(model)` | explicit loaders |
| `Avatar.Viewport` | the `ViewportFrame` itself |

The configuration saves the highlighted region array — the camera angle is not
persisted.

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
| Later run, same version | one tiny request for `version.txt`, then the saved file is loaded from disk with `readfile` |
| New version published | re-downloads `xclient.lua`, refreshes the cache and runs the fresh copy |
| Published file does not compile | skipped like an error page: nothing is cached or overwritten and the copy on disk keeps working |
| Version request fails, library reachable | the cached copy is verified against the repository first, so a published fix is never missed |
| Repository unreachable (real offline) | keeps using the cached copy |

Files (inside the executor's workspace folder):

| Path | Purpose |
| --- | --- |
| `XClient/xclient.lua` | the cached library |
| `XClient/.version` | the version the loader matched: the build tag of the cached file, or the commit hash when the version came from the API |

### Configuration

Edit `Loader.Config` at the top of `loader.lua`:

| Key | Default | Description |
| --- | --- | --- |
| `User`, `Repo`, `Branch`, `File` | placeholder | where the library lives on GitHub |
| `VersionFile` | `"version.txt"` | tiny published marker holding the manual build tag, next to `File` |
| `VersionURL` | `nil` | optional explicit marker URL (overrides the URL derived from `VersionFile`) |
| `Folder` | `"XClient"` | cache folder |
| `CacheFile` | `"xclient.lua"` | cached library name |
| `MarkerFile` | `".version"` | cached build tag name |
| `Cache` | `true` | `false` always re-downloads (handy while editing) |
| `Offline` | `false` | `true` never touches the network and uses the cached copy only |
| `VerifyCache` | `true` | `false` trusts the cached copy when the build tag cannot be read (old behaviour) |

**Manual version, no API.** `version.txt` next to the library holds one short
token, e.g. `1.7.0`. The very same token is declared inside the library as
`XClient.Build = "1.7.0"`, so there are two things the loader can compare:

* the tag published on GitHub (`version.txt`, a few bytes from the same host
  that serves `xclient.lua`), and
* the tag of the copy **on disk** — read straight out of the cached file's own
  `XClient.Build` line.

The cache is reused only when those two agree (or when the stored
`XClient/.version` already matches); a mismatch re-downloads `xclient.lua`.
Nothing here needs the GitHub API, so a rate limit or a blocked `api.github.com`
can no longer freeze an old copy: with `VersionFile` set, the API is not asked
at all. The API hash is only a fallback for when no marker file is published —
in that mode the loader records the commit hash it matched, because that is the
only value that can confirm the cache next time. Set `VersionFile = ""` to force
that fallback.

Because the file on disk is identified by its own build tag, a marker written by
an older loader (a commit hash) can no longer pin a stale cache — the tag of the
file wins.

**Bumping the version.** Change `XClient.Build` in `xclient.lua`, then run

```bash
lua _mkversion.lua          # writes version.txt from the build tag
lua _mkversion.lua --check  # exit 1 when the two disagree (useful before pushing)
```

and push `xclient.lua` + `version.txt` together. If the two are out of sync the
loader still works — it runs what it downloaded — but it warns
`version.txt says 'X' but the published file declares 'Y'` and keeps refreshing
until both are bumped.

When the marker request fails the loader does **not** silently keep the old
file: it re-downloads `xclient.lua`, refreshes the cache and runs the fresh
copy, and only falls back to the stored copy when the repository is genuinely
unreachable. Set `VerifyCache = false` to trust the cache without checking, or
`Offline = true` to skip the network entirely.

**A published file that does not compile cannot take the menu down.** Every
downloaded body has to compile before the loader does anything with it: a body
`loadstring` rejects is treated exactly like an error page, so it is never
written into the cache and never replaces the copy that works. The loader tries
the next URL instead and, when none of them compiles, it keeps running the file
on disk and warns `the published file does not compile; using the copy on
disk`. The only case that still fails is *nothing cached **and** the published
file broken* — and then the error quotes the real parser message instead of
claiming the repository was unreachable. That is what turns a bad push (a bare
`XClient.Build = 1.7.0` without the quotes, say) into a non-event for everybody
who already has a working copy.

`Loader.Version` (`getgenv().XClientLoader.Version`) tells you which loader is
running — useful to confirm that a newly pushed `loader.lua` actually reached
the executor. The cache decisions above are covered offline by
`_loadertest.lua` (`lua _loadertest.lua`).

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
Loader:GetVersion()        -- build tag of the file in the cache
Loader:CheckForUpdate()    -- remoteVersion, hasUpdate
Loader:Update()            -- force a re-download into the cache (does not run it)
Loader:ClearCache()        -- remove the cached library and its marker
Loader:Load()              -- run the whole load sequence again
```

**Clearing the cache.** The cached library and its marker are two plain files.
`Loader:ClearCache()` removes both, and the next load downloads a fresh copy:

```lua
getgenv().XClientLoader:ClearCache()                 -- true when something was removed
local url = "URL_TO/loader.lua?t=" .. os.time()      -- also cache-bust the loader itself
loadstring(game:HttpGet(url))()                      -- auto-run downloads the library again
print(getgenv().XClient.Build)                       -- e.g. 1.7.0
```

The same files can be deleted by hand, without the loader (paths are relative to
the executor's workspace folder, built from `Folder` / `CacheFile` / `MarkerFile`):

```lua
for _, path in ipairs({ "XClient/xclient.lua", "XClient/.version" }) do
    if isfile(path) then delfile(path) end
end
```

To force a refresh without deleting anything, either update in place with
`Loader:Update()`, or skip the cache entirely for one run:

```lua
getgenv().XClientLoaderOptions = { Cache = false }   -- always downloads, writes nothing
local XClient = loadstring(game:HttpGet("URL_TO/loader.lua"))()
getgenv().XClientLoaderOptions = nil                 -- back to normal on the next run
```

---

## 18. Module loader (external modules)

Section 1 loads a single file and section 17 keeps that file on disk. The module
loader goes one step further: it lets a script keep its actual features in
**separate files on GitHub** and pull them in with one call, instead of shipping
one monolithic `main.lua`. It is part of `xclient.lua` itself (source section
`15b`), so there is nothing extra to download.

```lua
local XClient = loadstring(game:HttpGet("URL_TO/xclient.lua"))()

XClient:InitModules(Window, { Modules = {
    { Name = "Combat",  URL = "URL_TO/modules/combat.lua"  },
    { Name = "Visuals", URL = "URL_TO/modules/visuals.lua" },
}})
```

A module is an ordinary Lua chunk that returns one of:

| It returns | Meaning |
| --- | --- |
| `function(XClient, Window, Options)` | the entry point, run for the window |
| `{ Name = "Combat", Init = function(XClient, Window) ... end }` | a named module; `Run`, `Setup` and `Load` work as the entry point too |
| nothing at all | a pure side-effect module: running the chunk *is* the load |

A `Name` declared inside the module wins over the file name, so `combat.lua` may
call itself `Combat` — that becomes the key used in the registry and in the cache.

### 18.1 Loading and registering

| Call | Purpose |
| --- | --- |
| `XClient:InitModules(window, opts)` | obtain every module and run its entry point; returns `loaded, failed` |
| `XClient:LoadModule(url, opts)` | register one module immediately (download, compile, run its top-level chunk); returns `true, info` or `false, info` |

| `InitModules` option | Default | Description |
| --- | --- | --- |
| `Modules` | the registry | list of `{ Name, URL }` (bare URL strings work too); omit it to run everything `LoadModule` registered |
| `BundleURL` / `Bundle` | `ModuleOptions.BundleURL` | optional bundle file; `Bundle = false` skips it |
| `Loading` | `true` | `false` skips the loading overlay |
| `OnDone(loaded, failed)` | `nil` | called once when the run is over |

`window` is optional — its `Root` (or `Frame` / `Container`) hosts the overlay and
it is handed to every entry point.

### 18.2 Configuration

The loader keeps its settings in `XClient.ModuleOptions`; change them in place at
any time with `XClient:SetModuleOptions(opts)`:

| Key | Default | Description |
| --- | --- | --- |
| `Folder` | `"XClient/modules"` | cache folder inside the executor workspace |
| `BundleURL` | `nil` | optional bundle file holding many modules |
| `BundlePath` | `"XClient/modules/bundle.lua"` | where the bundle is cached |
| `Retries` | `3` | download attempts per module |
| `RetryDelay` | `0.6` | seconds; every attempt waits longer (`RetryDelay × attempt`) |
| `FallbackRetries` | `5` | whole-module attempts (load + init) before skipping it |
| `FallbackDelay` | `2` | seconds between those attempts |
| `Offline` | `false` | never touch the network, use the cache only |
| `Log` | `true` | print progress and failures to the console |

```lua
XClient:SetModuleOptions({ Folder = "XClient/modules", Log = false })
```

`LoadModule` / `InitModules` also accept per-module overrides, so one flaky module
can be treated differently from the rest — `Name`, `Mirrors` (extra URLs tried in
order), `Retries`, `RetryDelay`, `FallbackRetries`, `FallbackDelay`.

### 18.3 Cache and integrity

Every module is one plain file plus a checksum file, both inside `Folder`:

| Path | Purpose |
| --- | --- |
| `XClient/modules/combat.lua` | the cached module source |
| `XClient/modules/combat.hash` | its DJB2 checksum |

The checksum is not a security feature — it only tells a freshly written cache file
apart from a truncated one (a half-finished write, a disk hiccup, a stray editor
save). Reading a module validates the pair, so a cache file whose checksum
disagrees counts as **absent** and the module is downloaded again instead of being
compiled from a corrupt copy.

| Situation | What happens |
| --- | --- |
| First load | the source is downloaded, compiled, cached and its top-level chunk is run |
| Download fails, cached copy valid | the cached copy is used and counted as `Cached` — a handful of bytes saved and an offline client still works |
| Download fails, no cache | the module is skipped; the rest of the list keeps loading |
| Cache file truncated or edited by hand | the checksum disagrees, so it is treated as if it did not exist |
| `Offline = true` | no request at all: cache only, and a module with no cache is skipped |

On the retry path the URL is cache-busted (`?t=<time>`), so a stale CDN copy cannot
pin an old module, and the body still has to compile before it is accepted — a
truncated download is retried instead of being cached as a broken module.

### 18.4 Bundle

Instead of one request per module, a **bundle** is a single file that returns a
table of modules — handy for a whole feature set:

```lua
-- modules/bundle.lua
return {
    Combat  = function(XClient, Window) ... end,
    Visuals = { Name = "Visuals", Init = function(XClient, Window) ... end },
}
```

```lua
XClient:SetModuleOptions({ BundleURL = "URL_TO/modules/bundle.lua" })
XClient:InitModules(Window)                     -- the whole bundle in one request
```

Bundled entries are registered exactly like individually loaded modules, only
marked as bundled (counted in `ModuleStats.Bundle`, cached as `BundlePath`), and
they are already in memory when their turn comes so they never hit the network
twice. The bundle is optional: when it cannot be reached the modules registered
individually still load.

### 18.5 Loading overlay

While the modules are being prepared a small overlay based on the boot HUD
(section 15) is shown over the window — the same corner brackets, a status line
(`Combat (1/3)`) and a percentage — and it closes itself when the last module is
done:

```lua
XClient:InitModules(Window, { Loading = false })  -- no overlay at all
```

It is built inside a `pcall`, so a client that refuses the UI can never stop the
modules from loading, and the shimmer animates inside the engine (no Lua loop is
left running for the duration of the module phase).

### 18.6 Inspecting and maintaining

| Member | Description |
| --- | --- |
| `XClient.Modules` | `name -> { fn, url, opts, source }` for everything registered |
| `XClient.ModuleOrder` | the names, in registration order |
| `XClient.ModuleStats` | `{ Updated, Cached, Bundle, Failed }` |
| `XClient:SetModuleOptions(opts)` | merge options; returns the live table |
| `XClient:LoadModule(url, opts)` | load one module now |
| `XClient:InitModules(window, opts)` | load and run everything; returns `loaded, failed` |
| `XClient:ListModules()` | `{ Name, URL, Source }` per module, in order |
| `XClient:ClearModuleCache()` | delete the cached `.lua` / `.hash` files; returns how many were removed |
| `XClient:PrintModuleStats()` | log the four counters and return the table |

```lua
XClient:SetModuleOptions({ Log = true })
local loaded, failed = XClient:InitModules(Window)
XClient:PrintModuleStats()          -- Updated=4 Cached=1 Bundle=2 Failed=0
XClient:ClearModuleCache()          -- next run downloads everything again
```

Everything the loader registers lives in `XClient.Modules`, and the loader only
ever appends to it, so a script may pre-seed a module or read the registry at any
time. Nothing in this section is mandatory: a script that never calls it behaves
exactly as before.

The cache decisions above (checksum rejection, offline mode, the two retry
stages, the bundle and the overlay) are covered offline by `_moduletest.lua`
(`lua _moduletest.lua`) — 54 checks against a fake file system and a stub
`game:HttpGet`.

---

## 19. GroupBox (Neverlose style card)

`Tab:CreateGroupBox` builds a card — a bluish tinted container with a caption and
a hairline header that holds other elements. Every `Type` the builders know goes
inside, and so does a plain string (which becomes a section):

```lua
local Aim = Tab:CreateGroupBox({
	Name = "Aim",
	Elements = {
		{ Type = "Toggle", Name = "Enabled", Flag = "aimEnabled" },
		{ Type = "Slider", Name = "FOV", Range = { 1, 180 }, Increment = 5, Flag = "aimFov" },
		"Advanced",                                  -- a plain string = a section
		{ Type = "Toggle", Name = "Auto fire", Flag = "aimAutoFire" },
		{   -- a card inside the card
			Type = "GroupBox", Name = "Prediction",
			Elements = {
				{ Type = "Slider", Name = "Lead", Range = { 0, 1 }, CurrentValue = 0.15, Flag = "aimLead" },
			},
		},
	},
})
```

The card sizes itself to its content — it grows when a caption wraps — and the
children keep the exact same contract they have on a tab: each returns its own
settings table, registers its own flag and is saved / loaded by the
configuration system without any extra work. The nested rows sit on the card's
own surface, so they are drawn flat: no second background and no second border.
There is no depth limit, so a card can hold another card; the nested card is
drawn flat, one level in.

Filling the card later and reading it back:

```lua
Aim:Add({ Type = "Toggle", Name = "Team check", Flag = "aimTeam" })
Aim:AddMany({ "Extras",
	{ Type = "Dropdown", Name = "Hitbox", Options = { "Head", "Torso" }, Flag = "aimHitbox" } })

Aim:SetTitle("Aim assist")                     -- renames the card
Aim:Set({ Name = "Aim", Elements = { ... } })  -- rename and / or replace the children
Aim:Clear()                                    -- remove every child and free its flag
```

| Card method | Effect |
| --- | --- |
| `:Add(element)` | append one child (a table descriptor or a section string) |
| `:AddMany(list)` | append a list of children |
| `:Clear()` | remove every child and unregister the flags they had registered |
| `:SetTitle(text)` | rename the card |
| `:Set({ Name = ..., Elements = ... })` | rename and / or replace the children |
| `:Serialize()` | snapshot of every flagged child (nested cards included), `flag -> value` |
| `:Load(values)` | apply such a snapshot through the normal `:Set` entry points |

`Serialize` / `Load` speak the same language as the configuration system
(section 7) and walk nested cards too, which makes them handy for named presets
of a single card:

```lua
local preset = Aim:Serialize()   -- { aimEnabled = true, aimFov = 90, ... }
Aim:Load(preset)                 -- callbacks fire and auto-save runs as usual
```

Inside a module's settings panel the card is a descriptor like any other, and
`Elements` may also be spelled `Settings`, so it reads naturally in the list:

```lua
Tab:CreateToggle({
	Name = "Aimbot",
	Settings = {
		{ Type = "GroupBox", Name = "Rage", Elements = {
			{ Type = "Toggle", Name = "Auto fire", Flag = "rageAuto" },
			{ Type = "Slider", Name = "Speed", Range = { 1, 20 }, Flag = "rageSpeed" },
		} },
	},
})
```

The bluish tint is derived from the active palette (the elevated surface pulled
towards the theme accent and nudged towards blue), so the three themes keep their
own identity while every card still reads as the Neverlose style widget.

---

