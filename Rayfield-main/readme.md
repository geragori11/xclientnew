# XClientMenu

A self-contained, **Neverlose-style** interface suite for Roblox, written from
scratch in a single file. No remote template asset, no external service — just
`xclient.lua` and `Instance.new`.

The public API is a drop-in match for the interface this project previously
shipped, so **existing scripts keep working**: same `CreateWindow` / `CreateTab` /
`Create*` names, same option names (`CurrentValue`, `Range`, `PlaceholderText`,
`CurrentKeybind`, `MultipleOptions`, …), same returned objects with `:Set()`,
same `XClient.Flags` registry, same `.rfld` configuration files.

## Features

* Dark Neverlose layout: left tab rail, top bar with title, minimise and close.
* Elements: button, toggle, slider, dropdown (single & multi, with a dedicated
  `CreateMultiDropdown`), input, keybind, colour picker, label, paragraph,
  section, divider.
* **Dropdowns follow the page** — an open list stays glued to its row while you
  scroll and dismisses itself when the row leaves the viewport.
* **Colour pickers keep 9 favourite slots** (a 3x3 grid beside the hue /
  saturation pads). Click an empty slot to store the current colour, click a
  filled one to apply it, Shift+click to overwrite, right-click to clear. The
  palette is shared by every picker and saved with the configuration.
* **Extended widgets** — an interactive `PlayerWidget` character, a marker
  `Image` (skin visualisation), a crosshair/FOV pad, a live graph, a
  progress/loader, a stepper, segments, a wheel, an analog stick, a radar and
  chips. All of them also work inside a module's settings flyout.
* **CS style HUD font** by default (condensed), plus `Classic` / `Mono`
  profiles and fully custom ones: `XClient:SetFont("Classic")`.
* **Captions always fit** — every caption is measured and either shrunk or
  wrapped onto a second line, both in tabs and in the narrower settings flyout.
* **Menu open key** — `CreateWindow({ OpenKey = "RightShift" })`, rebindable
  from the settings panel and saved with the configuration. Any casing works
  (`"space"` as well as old saves such as `"ENUM.KEYCODE.SPACE"` are
  canonicalised) and typing in a text field never toggles the menu.
* **Loading animation** — a CS style boot sequence (corner brackets, a bar that
  fills while a shimmer sweeps it, a percentage counter and a stage list) that
  fades out once the interface is up; the window itself slides into place.
* **Per module gear** — give a row a `Settings = { ... }` table and a gear icon
  appears; pressing it slides a settings flyout in from the **left** of the
  window, built from the same element builders and saved like any other flag.
* **Built-in configuration system** — **auto-save is on by default** (a running
  `autocfg` file is created and reloaded on the next join), plus
  save / load / delete / list named configurations and autoload on start, in the
  in-window configuration panel behind the topbar gear (which also holds the
  theme picker, the font picker, the auto-save switch, the menu key and the
  configuration manager).
* Three palettes (Neverlose, Midnight, Blood) plus the theme names old scripts
  use, and custom palette tables.
* Named (Lucide) icons via `icons.lua`, Roblox asset ids, or plain URLs.
* Your open key hides / shows the interface, the top bar drags the window around.

## Quick start

```lua
local XClient = loadstring(game:HttpGet("URL_TO/xclient.lua"))()

local Window = XClient:CreateWindow({
	Name = "My Script",
	Theme = "Default",
	OpenKey = "K",                      -- key that shows / hides the menu
	LoadingTitle = "My Script",         -- optional boot animation
	LoadingDuration = 1.4,
	-- Auto-save to XClient/Configurations/autocfg.rfld is ON by default, so
	-- nothing else is needed.  To use another file (or opt out) pass:
	-- ConfigurationSaving = { Enabled = true, FileName = "My Config" },
})

local Tab = Window:CreateTab("Combat", 4483362458)

Tab:CreateToggle({
	Name = "Aimbot",
	CurrentValue = false,
	Flag = "aimbot",
	Callback = function(value) print(value) end,
	Settings = {
		{ Type = "Slider", Name = "FOV", Range = { 10, 360 }, CurrentValue = 90, Flag = "fov" },
		{ Type = "PlayerWidget", Name = "Skin visualisation", Flag = "skin" },
	},
})

local Skin = Tab:CreatePlayerWidget({ Name = "Skin", Flag = "skin" })
Skin.Highlight.Torso = true               -- the picture reacts immediately

XClient:Notify({ Title = "Loaded", Content = "Have fun." })
```

See `example.lua` for a script that builds every element, and
`Documentation.md` for the complete reference.

### Cached loader (optional)

`loader.lua` is a drop-in replacement for the one-shot HTTP fetch above. Instead
of pulling the whole library on every injection it keeps a local copy on disk and
only asks the repository for a tiny version marker on later runs:

```lua
local XClient = loadstring(game:HttpGet("URL_TO/loader.lua"))()
```

* **first run** — downloads `xclient.lua`, writes it to `XClient/xclient.lua`
  with `writefile` and remembers the remote version;
* **later runs** — fetches only the version / hash with a short request and, when
  it has not changed, loads the saved file straight from disk with `readfile`;
* **a new version** — re-downloads the library and refreshes the cache;
* **offline** — keeps using the cached copy.

Point `Loader.Config.User` / `Repo` / `Branch` in `loader.lua` at your fork.
`Documentation.md` section 17 covers the configuration and the helper methods
(`GetVersion`, `CheckForUpdate`, `Update`, `ClearCache`).

## Files

| File | Purpose |
| --- | --- |
| `xclient.lua` | the whole library |
| `loader.lua` | optional disk-cached auto-loader for `xclient.lua` |
| `example.lua` | example script / compatibility demo |
| `Documentation.md` | API reference |
| `icons.lua` | optional Lucide icon sheets used by `XClient.Icons` |
| `_devtest.lua` | development harness: runs the library inside a small Roblox shim (`lua _devtest.lua`) |
| `LICENSE` | licence |

`_devtest.lua` is a developer tool, not part of the library — it needs plain
Lua 5.1 and does not touch the game.

## Compatibility notes

Implemented: everything listed in `Documentation.md` §12, plus the additions of
§13 (CS font profiles and caption fitting), §14 (menu open key), §15 (loading
animation) and §16 (the extended widgets). Settings that concern features XClient
does not ship (Discord join prompts, the key system, build warnings) are accepted
and ignored, and notification images are ignored instead of being fetched.
