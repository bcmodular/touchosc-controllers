# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Collection of TouchOSC controllers for hardware synthesizers/samplers, primarily the Roland SP-404 MK2. The main controller (`sp404-mk2/SP404/SP404.tosc`) is a complex TouchOSC layout with extensive Lua scripting that provides:

- Full effects parameter control across 5 buses (46 effects supported)
- Preset save/recall system with 16 slots per effect
- Launchpad Pro integration via SysEx for pad LED feedback
- BCR2000 MIDI controller mapping
- Default value management and recent value recall

## Architecture

### TouchOSC + Lua Model

TouchOSC `.tosc` files are binary layout files edited in the TouchOSC app. The Lua scripts in `sp404-mk2/SP404/lua/` are injected into UI elements at runtime via `init()` functions that set `.script` properties. You cannot edit `.tosc` files directly as code.

### SP404 MK2 Lua Script Architecture

Scripts are organized by responsibility and communicate via TouchOSC's `notify`/`onReceiveNotify` message-passing system:

- **`root.lua`** — Root-level MIDI handler. Routes incoming MIDI from Launchpad Pro (note-on for preset triggers, CC for delete mode). Sends SysEx for Launchpad layout and LED control.
- **`bus_group.lua`** — Defines the per-bus script (injected into 5 bus groups). Each bus has its own MIDI channel (0-4), manages effect selection, fader setup, preset grid, and recent value storage.
- **`control_mapper.lua`** — The core fader engine. Generates per-fader scripts dynamically using `string.format` with templates. Handles MIDI CC mapping, value display labels, sync toggles, and double-tap-to-reset.
- **`controls_info.lua`** — Data definition for all 46 effects. Each entry maps CC numbers, fader names, label formats, mapping functions, grid configurations, and sync relationships. The array structure has 16 positional fields (documented in the file header).
- **`preset_grids.lua`** — Centralized preset grid manager. Handles store/recall/delete across all buses, Launchpad LED synchronization, and color-coded bus identification.
- **`preset_manager.lua`** — Persistent preset storage. Each of the 46 effect slots stores its presets as JSON in the element's `tag` property. Supports OSC export/import.
- **`default_manager.lua`** — Stores default fader values per effect.
- **`recent_values.lua`** — MRU stack (max 16) of recently used effect parameters per bus.
- **`fx_selector_group.lua`** / **`fx_selector_button_group.lua`** — Effect chooser UI. Shows available effects per bus (availability depends on MIDI channel mapping).
- **`on_off_button_scripts.lua`** — Effect on/off toggle, grab (momentary), and sync-to-device buttons.

### Data Flow

1. User selects effect → `fx_selector_button_group` → `bus_group.set_fx` → `control_mapper.init_perform` (generates fader scripts)
2. Fader moved → dynamically generated script calls mapping function → updates label, sends MIDI CC
3. Preset store → `preset_grids` captures current fader values → stores in `preset_manager` tag as JSON
4. Preset recall → `preset_grids` reads from `preset_manager` → notifies faders with `new_value`

### Key TouchOSC Patterns

- **`tag` property as shared state**: The only way to pass data between parent/child scopes in grids. Always JSON-encoded via `json.toTable()`/`json.fromTable()`.
- **Dynamic script injection**: Most scripts are string templates in "manager" files that get injected into UI elements during `init()`. The actual UI elements in the `.tosc` file are mostly blank shells.
- **`notify`/`onReceiveNotify`**: The IPC mechanism between TouchOSC elements. All cross-element communication uses this pattern.
- **MIDI values are 0-127**, but TouchOSC faders use 0.0-1.0 floats. Conversion helpers `midiToFloat`/`floatToMIDI` appear throughout.
- **Mapping functions**: Convert MIDI values to display strings (e.g., `getFreq`, `getDelayTimes`). Defined as string snippets in `control_mapper.lua` and injected into fader scripts via `string.format`.

## Naming Conventions

- **Lua variables/functions**: camelCase (`controlFader`, `refreshPresets`)
- **Constants**: UPPER_SNAKE_CASE (`BUTTON_STATE_COLORS`, `DELETE_BUTTON_LED`)
- **TouchOSC control names**: snake_case (`preset_grid`, `control_fader`, `bus1_group`)

## Other Components

- **`preset-manager/python/`** — PyQt5 desktop app for OSC preset backup/restore. Requires `python-osc`, `psutil`, `PyQt5`.
- **`utils/`** — Launchkey Mini InControl mode scripts and MIDI tester layouts.
- **`s-1/`** — Separate TouchOSC layout for Roland S-1 synth.
