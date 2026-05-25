# Naming Conventions

## Variable and Function Names
- Use camelCase for all variable and function names
- Use PascalCase for class names (if applicable)
- Use UPPER_SNAKE_CASE for constants
- Use snake_case ONLY for control names and UI element identifiers (e.g., 'edit_compressor_sidechain', 'ratio_fader_group')

## Examples
```lua
-- Good
local attackTimeMs = 10
local currentEnvelopeValue = 0
local isEnabled = false

-- Bad
local attack_time_ms = 10
local current_envelope_value = 0
local is_enabled = false

-- Control names (must use snake_case)
local editCompressorSidechain = compressorEditPage:findByName('edit_compressor_sidechain', true)
local ratioFaderGroup = editCompressorSidechain:findByName('ratio_fader_group', true)
```

## Rationale
- camelCase is the standard in JavaScript and many other modern languages
- snake_case for control names matches TouchOSC's internal naming conventions
- Consistent naming improves code readability and maintainability
- Reduces confusion when working with multiple files

## Enforcement
- Review all new code for consistent naming
- Update existing code to follow these conventions when modified
- Use automated tools (like linters) where possible to enforce these rules

## Lua: local function order (read this before adding helpers)

TouchOSC uses Lua 5.x. **`local function foo()` is only visible after its definition line.** If `bar()` calls `foo()` earlier in the file, Lua does not find the local — it looks for a **global** `foo`, gets `nil`, and you get:

`attempt to call global 'foo' (a nil value)`

This has bitten us more than once (e.g. `beginGrabPreset` calling `recallPreset` in `preset_grid_manager.lua` before `recallPreset` was defined).

**Rules when editing manager-style scripts (`preset_grid_manager.lua`, `root.lua`, etc.):**

1. **Define the callee first**, then functions that call it — keep a bottom-up order in the file (low-level helpers → higher-level orchestration → `onReceiveNotify` / `init`).
2. Or **move** the caller below the callee (do not leave the call above the `local function` definition).
3. Or use a **forward declaration** when mutual recursion is required:

```lua
local recallPreset  -- forward declare

local function beginGrabPreset(busNum, presetNum)
  recallPreset(busNum, presetNum)
end

local function recallPreset(busNum, presetNum)
  -- ...
end
```

**Do not** assume `local function` hoists like JavaScript `function` declarations — it does not.

**Quick check:** before committing, grep for `local function` names and confirm every call site is **below** the definition (or behind a forward declare).

## Prefer Direct Control Over `notify`

TouchOSC’s `notify` / `onReceiveNotify` pattern is useful for cross-scope messaging (e.g. root → bus group, modal → button grid), but it can be **less reliable** than working directly with controls:

- **Prefer** finding a control with `findByName` and setting `values` (e.g. `button.values.x = 0`) so `onValueChanged` runs on the target — **but** TouchOSC often does **not** call `onValueChanged` when values are changed from Lua; only real touch/MIDI on that control does. Do not rely on scripted value changes to trigger handlers.
- **Avoid** `self:notify(...)` on the same node that handles the message — delivery to `onReceiveNotify` on `self` is inconsistent.
- **Use `notify`** when the handler lives on a different node and there is no natural value to set (e.g. `bus_group` → `control_mapper` `init_perform`), or for grid parent/child scope where `tag` is required.

Example (MIDI confirm: notify the bus group directly — scripted button values will not fire `onValueChanged`):

```lua
local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
-- Third arg: FX chooser (true = show, false = hide, omit = unchanged). Fourth: sceneLoad (skip recent recall).
busGroup:notify("set_fx", { fxIdx, fxName, false })
```

Example (UI tap: child resolves bus from `parent.tag`, notifies bus — not self):

```lua
local busGroup = root:findByName('bus' .. tostring(self.parent.tag) .. '_group', true)
busGroup:notify('set_fx', { self.tag, self.name, false })
```

## TouchOSC Grid Scope Rules

When working with TouchOSC grids, it's important to understand how scope works:

- In a TouchOSC grid, the parent grid and its child buttons share the same script/object definition
- Each instance (parent and children) operates in its own scope with its own `self` reference
- Child buttons **cannot** access parent variables directly
- The `tag` property is the only way to share state between parent and children
- Therefore, any shared state (like `deleteMode`) must be stored in the parent's `tag` property

Example:
```lua
-- In parent grid:
local tagData = json.toTable(self.tag) or {}
tagData.deleteMode = true
self.tag = json.fromTable(tagData)

-- In child button:
local tagData = json.toTable(self.parent.tag) or {}
local deleteMode = tagData.deleteMode or false
```

This is why the `tag` property is so important in TouchOSC - it's the only reliable way to share state between different scopes in the same grid structure, but remember that it can only store string values, so you'll need to use JSON encoding/decoding to store and retrieve complex data.

## Button State Rules

When working with button states in TouchOSC:

- Always store button states as strings in the button's `name` property
- Use `tostring()` when setting the name to ensure it's a string
- Use `tonumber()` when reading the name to convert back to a number
- Define state constants at the top of your script
- Use the state constants consistently throughout the code

Example:
```lua
local BUTTON_STATE = {
    RECALL = 1,
    DISABLED = 2
}

-- Setting state
child.name = tostring(BUTTON_STATE.RECALL)

-- Reading state
local buttonState = tonumber(self.name) or 0
if buttonState == BUTTON_STATE.RECALL then
    -- handle recall state
end
```

## MIDI routing (Lua only for perform controls)

Perform faders and `on_off_button_group` buttons have **no layout `<midi>` block** (local messages only). All SP-404 / BCR traffic is sent/received from Lua (`root.lua` inbound, per-bus scripts outbound).

| Path | Handler | Ports |
|------|---------|-------|
| Touch → SP-404 params | `control_fader` `syncMIDI()` → `sendSpMidi()` | `{ true, false, false }` |
| Touch → BCR encoders | `control_fader` `syncMIDI()` → `sendBcrMidi()` | `{ false, true, false }` |
| BCR encoder → UI | `root.lua` `handleBcrPerformMidi` → `set_cc_from_bcr` (SP only, no BCR echo) | receive port 2 |

BCR encoder CCs by fader group name (`"1"`–`"6"` = BCR parameter ID): 1→81, 2→89, 3→97, 4→82, 5→90, 6→98 (`{ 81, 89, 97, 82, 90, 98 }`). Set `BCR_MIDI_DEBUG = false` in `root.lua` / `ON_OFF_DEBUG = false` in `on_off_button_group.lua` when done tracing.

Toggle from BCR requires an effect loaded on that bus (`fxNum` ≠ 0); otherwise CC 83 “on” sends value 0 (same as off).

| SP-404 on/off | `on_off_button_group.lua` CC 83 | port 1 |
| BCR buttons | `on_off_button_group.lua` CC 65/66/73/74 | port 2 |
| Launchpad LEDs | `launchpad_led.lua` (RGB `0B` + palette off `0A`) | `{ false, false, true }` |

**Layout `<connections>` strings** (if you re-enable Editor MIDI): 10 digits, **right-aligned to connection number** — connection 2 = `0000000010`, connection 9 = `0100000000`. Do not use `0100000000` for port 2.

After layout edits in TouchOSC Editor, strip perform MIDI again:

```bash
python3 sp404-mk2/tools/patch_sp404_disable_layout_midi.py sp404-mk2/SP404/SP404.tosc
python3 tools/toscbuild.py build sp404-mk2/SP404
```

The patch **removes** `<midi>` from `control_fader` and on/off button nodes entirely (matching bus 1).

BCR on/off inbound (port 2): CC 65 toggle, 66 sync (on release val=0), 73 grab, 74 choose → `on_off_button_group` via `bcr_*` notifies. BCR buttons: **127 = on, 0 = off**.

## Launchpad Pro (Programmer layout, MIDI channel 10)

TouchOSC listens on **port 3** (`{ false, false, true }`). Layout must be **Programmer** mode on the Launchpad (SysEx `0x2C 0x03` from `root.lua` `init`).

### Programmer grid (canonical)

- **Square pads** → Note on ch 10; pad label = `10 * row + col` (**row 1 = bottom**, **row 8 = top**, **col 1 = left**).
- **Round buttons** → CC on ch 10; label = CC number.
- **Square-pad LEDs** → RGB SysEx `F0 … 0B <note> <R> <G> <B> F7` (helpers in `launchpad_led.lua`). **Note number = LED index.**
- **Round-button LEDs** → same RGB path; **CC number = LED index** (e.g. CC 50 → LED `0x32`).

```
        [Setup]  91  92  93  94  95  96  97  98     ← top CC row (FX bus 1–5)
         80 │ 81  82  83  84  85  86  87  88 │ 89   ← row 8; Shift = CC 80 (left)
         70 │ 71  72  73  74  75  76  77  78 │ 79
         60 │ 61  62  63  64  65  66  67  68 │ 69
         50 │ 51  52  53  54  55  56  57  58 │ 59   ← Delete = CC 50 (left)
         40 │ 41  42  43  44  45  46  47  48 │ 49
         30 │ 31  32  33  34  35  36  37  38 │ 39
         20 │ 21  22  23  24  25  26  27  28 │ 29
         10 │ 11  12  13  14  15  16  17  18 │ 19   ← row 1 (bottom)
              1   2   3   4   5   6   7   8        ← bottom CC row (unmapped; lock planned)
```

### Surface allocation

| Region | Col / CC | Notes (top→bottom) | Handler |
|--------|----------|-------------------|---------|
| **Presets** | Square cols **1–5** | 81…11 per column | `preset_grid_manager.lua`, `root.lua` |
| **Scenes** | Square cols **7–8** | 87…17, 88…18 | `scene_manager.lua`, `root.lua` |
| **Shift** | CC **80** (left, row 8) | 127/0 | `root.lua` → `launchpadShiftHeld` on `root.tag` |
| **Click** | CC **70** (left, row 7) | 127/0 | `root.lua` → bus defaults via `preset_grid` `store_defaults` |
| **Undo** | CC **60** (left) | 127/0 | `root.lua` → bus defaults via `preset_grid` `recall_defaults` |
| **Delete** | CC **50** (left) | 127/0 | `delete_button` + preset/scene delete mode |
| **FX bus** | CC **91–95** | 127/0 | `root.lua` → `on_off_button_group` (toggle / Shift+grab / Click+store / Undo+recall) |
| **Spare** | Col **6**, CC 6–8, 96–98, side 19–89 | — | — |
| **Bus lock** | CC **1–5** (bottom) | — | Not implemented yet |

### Note formulas (keep code in sync)

Presets — `preset_grid_manager.lua` and `root.lua`:

```lua
-- bus 1..5 = col 1..5; preset 1 = top (row 8), preset 8 = bottom (row 1)
note = 81 + (bus - 1) - (preset - 1) * 10
```

Scenes — `launchpadSceneNote()` in `launchpad_led.lua`; inbound map `buildLaunchpadSceneNoteToSceneMap()` in `root.lua`:

```lua
-- scenes 1–8 = col 7, 9–16 = col 8; slot 1 = top
local col = (sceneNum <= 8) and 7 or 8
local slot = ((sceneNum - 1) % 8) + 1
note = col + 80 - (slot - 1) * 10   -- 87,77,…,17 and 88,78,…,18
```

### Gestures (implemented)

| Control | Gesture | Action |
|---------|---------|--------|
| **Preset pad** | Tap empty / stored | Store / recall (per bus, per current FX) |
| **Preset pad** | Delete mode + tap | Delete |
| **Preset pad** | Shift+stored or GRAB MODE | Momentary preview; restore on release |
| **Scene pad** | Same as presets | Global 5-bus snapshot (FX, on/off, CC, sync) |
| **Scene pad** | Shift+stored | Momentary scene preview; restore full performance on release |
| **CC 91–95** | Tap | Toggle FX bus on/off (no-op if bus has no effect loaded) |
| **CC 91–95** | Delete+tap | Clear bus (same as TouchOSC clear button) |
| **CC 91–95** | Shift+hold | Momentary grab (no-op if no effect) |
| **CC 91–95** | Click+hold | Store effect defaults (no-op if no effect) |
| **CC 91–95** | Undo+hold | Recall effect defaults (no-op if no effect) |

Clearing/unloading a bus turns the effect off on the SP-404, BCR2000 (FX toggle CC), and Launchpad bus LED via `on_off_button_group` `set_state` / `set_grab_state`.

Scene recall uses `bus_group:notify('set_fx', { fxNum, fxName, false, true })` — 3rd arg closes chooser, 4th `sceneLoad` skips recent-value recall; then all stored fader CCs via `new_value` + `sync_current_bus` (full state reload; preset exclude-tuning does not apply). Storage: `scene_manager` children `01`–`16` label tags (JSON per scene).

### LED colors

| Target | Empty / off | Stored / on |
|--------|-------------|-------------|
| Preset pads | Off | Bus color via `launchpadBusRgb()` |
| Scene pads | Off | White via `launchpadSceneRgb()` |
| FX bus CC 91–95 | Bus color × `LAUNCHPAD_BUS_OFF_BRIGHTNESS` (~0.02) | Full bus color |
| Delete / Shift / Click / Undo CC | Dim RGB | Bright RGB when active (Click = green, Undo = magenta) |

Constants in `launchpad_led.lua`: `LAUNCHPAD_IDLE_BRIGHTNESS`, `LAUNCHPAD_ON_BRIGHTNESS`, `LAUNCHPAD_BUS_OFF_BRIGHTNESS`.

## Unified OSC backup (`/sp404/backup`)

`backup_manager.lua` exports and imports a single JSON blob with:

| Section | Source |
|---------|--------|
| `presets` | `preset_manager` children `1`–`46` |
| `scenes` | `scene_manager` children `01`–`16` |
| `defaults` | `default_manager.tag` |
| `recent` | `recent_values.tag` |
| `buses` | Each `busN_group.tag` (current FX selection per bus) |

On **import**, buses with a loaded FX are forced **off** (toggle, grab, SP-404 CC 83, BCR) because on/off is not stored in backups. Use **scenes** to recall performance snapshots including on/off.

**TouchOSC:** All presets panel → **Export** / **Import** (opens `backup_import_group`, then confirm after OSC receive). Incoming `/sp404/backup` is handled in `root.lua` `onReceiveOSC` (root is always called first), then forwarded to `backup_import_group`.

**Mac utility:** `preset-manager/python/preset-manager.py` listens for `/sp404/backup`, saves to `dumps/{name}_{timestamp}.json`, and can replay dumps to TouchOSC. Match TouchOSC OSC receive/send ports to the utility’s listen/send fields.

Scenes always store and recall **full** bus state (no preset-style exclude-tuning).

## Layout backups and bus UI sync

Do not use git to recover `.tosc` layout work — committed snapshots are often stale.

- **`toscbuild`** writes timestamped backups to `SP404/backups/SP404_YYYYMMDD_HHMMSS.tosc` before each build.
- **`tools/sync_bus1_ui_to_buses.py`** copies frames from `bus1_group` to buses 2–5 (`control_group` + `effect_chooser`), syncs the `effect_chooser` header (`choose_button`, `label`, `clear_*`) from bus 1, removes the legacy `background` box on other buses, preserves child **order** (z-index), assigns **new node IDs** per bus, and deduplicates any remaining duplicate IDs. TouchOSC’s editor uses node `ID` (not `name`) for selection — duplicate IDs cause “jump to wrong bus” when editing; duplicate `name`s are fine for Lua (`findByName` under a parent).
- **`tools/sync_bus1_ui_to_buses.py --diff-only`** lists frame differences vs bus1 without writing.

After editing bus 1 in TouchOSC Editor, run sync then build:

```bash
python3 tools/sync_bus1_ui_to_buses.py sp404-mk2/SP404/SP404.tosc
python3 tools/toscbuild.py build sp404-mk2/SP404
```