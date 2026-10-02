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
* Elements: button, toggle, slider, dropdown (single & multi), input, keybind,
  colour picker, label, paragraph, section, divider.
* **Per module gear** — give a row a `Settings = { ... }` table and a gear icon
  appears; pressing it slides a settings flyout in from the **left** of the
  window, built from the same element builders and saved like any other flag.
* **Built-in configuration system** — save / load / delete / list named
  configurations, autoload on start, in-window configuration panel behind the
  topbar gear (which also holds the theme picker and the UI keybind).
* Three palettes (Neverlose, Midnight, Blood) plus the theme names old scripts
  use, and custom palette tables.
* Named (Lucide) icons via `icons.lua`, Roblox asset ids, or plain URLs.
* `K` hides / shows the interface, the top bar drags the window around.

## Quick start

```lua
local XClient = loadstring(game:HttpGet("URL_TO/xclient.lua"))()

local Window = XClient:CreateWindow({
	Name = "My Script",
	Theme = "Default",
	ConfigurationSaving = { Enabled = true, FileName = "My Config" },
})

local Tab = Window:CreateTab("Combat", 4483362458)

Tab:CreateToggle({
	Name = "Aimbot",
	CurrentValue = false,
	Flag = "aimbot",
	Callback = function(value) print(value) end,
	Settings = {
		{ Type = "Slider", Name = "FOV", Range = { 10, 360 }, CurrentValue = 90, Flag = "fov" },
	},
})

XClient:Notify({ Title = "Loaded", Content = "Have fun." })
```

See `example.lua` for a script that builds every element, and
`Documentation.md` for the complete reference.

## Files

| File | Purpose |
| --- | --- |
| `xclient.lua` | the whole library |
| `example.lua` | example script / compatibility demo |
| `Documentation.md` | API reference |
| `icons.lua` | optional Lucide icon sheets used by `XClient.Icons` |
| `_devtest.lua` | development harness: runs the library inside a small Roblox shim (`lua _devtest.lua`) |
| `LICENSE` | licence |

`_devtest.lua` is a developer tool, not part of the library — it needs plain
Lua 5.1 and does not touch the game.

## Compatibility notes

Implemented: everything listed in `Documentation.md` §12. Settings that concern
features XClient does not ship (Discord join prompts, the key system, build
warnings) are accepted and ignored, and notification images are ignored instead
of being fetched.
