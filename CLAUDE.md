# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Collection of TouchOSC controllers for hardware synthesizers/samplers, primarily the Roland SP-404 MK2. The main controller ([`sp404-mk2/SP404.tosc`](sp404-mk2/SP404.tosc)) is a complex TouchOSC layout with extensive Lua scripting that provides:

- Full effects parameter control across 5 buses (46 effects supported)
- Preset save/recall system with 8 slots per effect
- Launchpad Pro integration via SysEx for pad LED feedback
- BCR2000 MIDI controller mapping
- Default value management and recent value recall

## Architecture

### TouchOSC + Lua Model

TouchOSC `.tosc` files are zlib-compressed XML layout files. The Lua scripts in `sp404-mk2/lua/` are the source of truth for all controller logic. Scripts are injected into `.tosc` nodes at **build time** using `tools/toscbuild.py`, which performs string-level regex replacement to preserve CDATA and non-script XML byte-for-byte.

Some scripts (e.g., `control_mapper.lua`) still use a **runtime injection** pattern where a "manager" node's `init()` distributes string templates to child nodes. On/off button scripts are build-time injected (`on_off_button_group.lua`, `toggle_button.lua`, etc.).

### SP404 MK2 Lua Script Architecture

Scripts are organized by responsibility and communicate via TouchOSC's `notify`/`onReceiveNotify` message-passing system:

- **`root.lua`** — Root-level MIDI handler. Routes incoming MIDI from Launchpad Pro (note-on for preset triggers, CC for delete mode). Sends SysEx for Launchpad layout and LED control. Injected into the root node at build time.
- **`bus_group_instance.lua`** — Per-bus script injected at build time into all 5 bus group nodes (`bus1_group` through `bus5_group`). Each bus self-discovers its number from `self.name:match("bus(%d+)_group")`, manages effect selection, fader setup, preset grid, and recent value storage.
- **`control_mapper.lua`** — The core fader engine. Generates per-fader scripts dynamically using `string.format` with templates. Handles MIDI CC mapping, value display labels, sync toggles, and double-tap-to-reset. Still uses runtime injection (manager pattern).
- **`controls_info.lua`** — Data definition for all 46 effects. Each entry maps CC numbers, fader names, label formats, mapping functions, grid configurations, and sync relationships. The array structure has 16 positional fields (documented in the file header).
- **`preset_grid_manager.lua`** — Centralized preset grid manager (8 presets per bus). Handles store/recall/delete across all buses, Launchpad LED synchronization, and color-coded bus identification.
- **`preset_grid.lua`** / **`preset_pad.lua`** — Build-injected notify relay on each `preset_grid` group and pads `1`–`8` (bus number from `tag` / parent `tag`).
- **`preset_manager.lua`** — Persistent preset storage. Each of the 46 effect slots stores its presets as JSON in the element's `tag` property. Supports OSC export/import.
- **`default_manager.lua`** — Stores default fader values per effect.
- **`recent_values.lua`** — MRU stack (max 16) of recently used effect parameters per bus.
- **`fx_selector_group.lua`** / **`fx_selector_button_group.lua`** — Effect chooser UI. Shows available effects per bus (availability depends on MIDI channel mapping).
- **`on_off_button_group.lua`** / **`toggle_button.lua`** etc. — Effect on/off, grab, sync, choose (build-time injected). Legacy `on_off_button_scripts` manager node is a stub.

### Data Flow

1. User selects effect → `fx_selector_button_group` → `bus_group.set_fx` → `control_mapper.init_perform` (generates fader scripts)
2. Fader moved → dynamically generated script calls mapping function → updates label, sends MIDI CC
3. Preset store → `preset_grid_manager` captures current fader values → stores in `preset_manager` tag as JSON
4. Preset recall → `preset_grid_manager` reads from `preset_manager` → notifies faders with `new_value`

### Key TouchOSC Patterns

- **`tag` property as shared state**: The only way to pass data between parent/child scopes in grids. Always JSON-encoded via `json.toTable()`/`json.fromTable()`.
- **Build-time script injection**: Lua files are injected into `.tosc` nodes by `toscbuild.py` during build. The `toscbuild.json` manifest maps each `.lua` file to one or more target nodes. This replaces the older runtime injection pattern.
- **Runtime script injection (legacy)**: `control_mapper.lua` still uses `init()` to set per-fader scripts from `string.format` templates. Build-time migration for those requires parameterized template expansion.
- **`notify`/`onReceiveNotify`**: The IPC mechanism between TouchOSC elements. All cross-element communication uses this pattern.
- **MIDI values are 0-127**, but TouchOSC faders use 0.0-1.0 floats. Conversion helpers `midiToFloat`/`floatToMIDI` appear throughout.
- **Mapping functions**: Convert MIDI values to display strings (e.g., `getFreq`, `getDelayTimes`). Defined as string snippets in `control_mapper.lua` and injected into fader scripts via `string.format`.

## Build Pipeline

### toscbuild.py (`tools/toscbuild.py`)

Python 3 CLI tool (no external dependencies) for the code-first build pipeline. Subcommands:

- **`build <dir>`** — Inject Lua scripts into `.tosc` based on `toscbuild.json`. Flags: `--dry-run`, `--no-backup`, `--quiet`.
- **`scaffold <dir>`** — Generate a `.tosc` file from a `layout` definition in `toscbuild.json`. Creates nodes with correct properties, values, and structure.
- **`extract <file>`** — Extract all scripts from a `.tosc` file to individual `.lua` files. Useful for bootstrapping and verifying round-trips.
- **`tree <file>`** — Print the node hierarchy with script/tag/MIDI annotations. Read-only inspection using ElementTree.
- **`dev <dir>`** — Watch mode: builds, opens TouchOSC (macOS), polls `.lua` files every 1s, rebuilds on change.

### Build Manifest (`toscbuild.json`)

Lives alongside the `.tosc` file (e.g., `sp404-mk2/toscbuild.json`). Format:

```json
{
  "source": "SP404.tosc",
  "output": "SP404.tosc",
  "lua_dir": "lua",
  "mappings": [
    {"lua": "root.lua", "node_id": "root"},
    {"lua": "bus_group_instance.lua", "node_names": ["bus1_group", "bus2_group", "bus3_group", "bus4_group", "bus5_group"]},
    {"lua": "control_mapper.lua", "node_name": "control_mapper"}
  ],
  "layout": { ... }
}
```

Mapping types:
- **`node_name`** (string) — Target a single uniquely-named node.
- **`node_names`** (array) — One-to-many: inject the same script into every layout node with that name.
- **`under_name`** + **`node_names`** — Inject into direct children only: for each parent node named `under_name`, update each child whose name is in `node_names` (e.g. preset pads `1`–`8` under `preset_grid`, avoiding global name collisions).
- **`node_id: "root"`** — Special case targeting the root `<node>` (first child of `<lexml>`).
- **`shared`** + **`include_name`** — Inject a Lua file into a TouchOSC **Shared Script** (`require`-able library) rather than a node script. Writes the source into the `<include>` named `include_name` in the root node's `<includes>` collection (create-or-update — creates the `<include>`, and the `<includes>` container, if absent). Used by TB-3 for `shared/efx_defs.lua` (`require("efx_defs")`). `extract` round-trips Shared Scripts to a `shared/` subdirectory.

The `layout` section (optional) defines nodes for the `scaffold` command to generate.

### CDATA Preservation

The build tool uses **string-level regex replacement** (not XML DOM) to modify scripts. This is critical because Python's `xml.etree.ElementTree` strips CDATA markers on parse, which would corrupt string properties. The regex approach preserves all non-script XML byte-for-byte.

### Development Workflow

```bash
# Edit Lua files, then build
python3 tools/toscbuild.py build sp404-mk2

# Or use watch mode for continuous rebuilds
python3 tools/toscbuild.py dev sp404-mk2

# Inspect .tosc structure
python3 tools/toscbuild.py tree sp404-mk2/SP404.tosc

# Generate a new .tosc from layout definition
python3 tools/toscbuild.py scaffold sp404-mk2
```

### Migrating Runtime Injection to Build-Time

To convert a manager script from runtime to build-time injection:

1. Extract the template string (the `[[...]]` content inside the manager's `local xxxScript = [[...]]`) into a new standalone `.lua` file.
2. Add a `node_names` mapping in `toscbuild.json` targeting all the nodes the manager previously injected into.
3. Remove the old manager mapping from `toscbuild.json`.
4. Optionally remove the manager node from the `.tosc` layout if it has no other purpose.

**Constraint**: Scripts that use `string.format` substitution in their templates (e.g., `control_mapper.lua` injects per-fader scripts with parameterized CC numbers) require build-time parameterization support, which is a future enhancement.

## Naming Conventions

- **Lua variables/functions**: camelCase (`controlFader`, `refreshPresets`)
- **Constants**: UPPER_SNAKE_CASE (`BUTTON_STATE_COLORS`, `DELETE_BUTTON_LED`)
- **TouchOSC control names**: snake_case (`preset_grid`, `control_fader`, `bus1_group`)

## Reference Documentation

- **`docs/tosc-format.md`** — Complete .tosc file format reference: XML schema, node types, property types, values, messages, Lua scripting environment/API, scaffold layout definition format, and programmatic modification techniques.
- **`sp404-mk2/README.md`** — End-user guide: MIDI setup, BCR2000, Launchpad Pro, presets/scenes/backup.
- **`sp404-mk2/lua/README.md`** — Contributor guide: naming conventions, grid scope rules, tag-based state sharing, layout tooling.

## Other Components

- **`sp404-mk2/preset-manager/python/`** — PyQt5 desktop app for OSC preset backup/restore. Requires `python-osc`, `psutil`, `PyQt5`.
- **`sp404-mk2/tools/`** — SP404-specific layout maintenance scripts (`sync_bus1_ui_to_buses.py`, `inject_*.py`, etc.). Shared build tooling remains in repo `tools/`.
- **`utils/`** — Launchkey Mini InControl mode scripts and MIDI tester layouts.
- **`s-1/`** — Separate TouchOSC layout for Roland S-1 synth.

## TB-3 Controller

**`tb-3/`** — TouchOSC controller for the Roland TB-3 synthesizer. Separate architecture from the SP-404 MK2 controller. Full documentation is in **[`tb-3/CLAUDE.md`](tb-3/CLAUDE.md)**; read that before touching any TB-3 files.

Key differences from the SP-404 layout:
- Roland SysEx protocol (DT1/RQ1) rather than plain MIDI CC for all tone parameters.
- Two BCR2000 units: BCR2000 #1 (MIDI CH 1) for tone/distortion; BCR2000 #2 (MIDI CH 2) for EFX1+EFX2.
- Root script is a **concatenated chunk** of four files (`bcr_map.lua` + `patch_manager.lua` + `enc_map.lua` + `root.lua`) — include order is load-bearing (shared upvalues).
- EFX state lives in element tags (`efx1_section.tag`, `efx2_section.tag`), not in root's `rawSysexBlocks`.
- Patch preset grid stores 16 slots as complete 11-block SysEx snapshots in `preset_grid.tag`.
- PyQt5 preset manager in `tb-3/preset-manager/` uses bank format v2 (`{"version":2,"slots":{...}}`) and communicates via OSC.

Build: `python3 tools/toscbuild.py build tb-3`
