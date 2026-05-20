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

## Prefer Direct Control Over `notify`

TouchOSC’s `notify` / `onReceiveNotify` pattern is useful for cross-scope messaging (e.g. root → bus group, modal → button grid), but it can be **less reliable** than working directly with controls:

- **Prefer** finding a control with `findByName` and setting `values` (e.g. `button.values.x = 0`) so `onValueChanged` runs on the target — **but** TouchOSC often does **not** call `onValueChanged` when values are changed from Lua; only real touch/MIDI on that control does. Do not rely on scripted value changes to trigger handlers.
- **Avoid** `self:notify(...)` on the same node that handles the message — delivery to `onReceiveNotify` on `self` is inconsistent.
- **Use `notify`** when the handler lives on a different node and there is no natural value to set (e.g. `bus_group` → `control_mapper` `init_perform`), or for grid parent/child scope where `tag` is required.

Example (MIDI confirm: notify the bus group directly — scripted button values will not fire `onValueChanged`):

```lua
local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
busGroup:notify("set_fx", { fxIdx, fxName })
```

Example (UI tap: child resolves bus from `parent.tag`, notifies bus — not self):

```lua
local busGroup = root:findByName('bus' .. tostring(self.parent.tag) .. '_group', true)
busGroup:notify('set_fx', { self.tag, self.name })
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
| Launchpad LEDs | `root.lua` / `preset_grid_manager.lua` SysEx | `{ false, false, true }` |

**Layout `<connections>` strings** (if you re-enable Editor MIDI): 10 digits, **right-aligned to connection number** — connection 2 = `0000000010`, connection 9 = `0100000000`. Do not use `0100000000` for port 2.

After layout edits in TouchOSC Editor, strip perform MIDI again:

```bash
python3 sp404-mk2/tools/patch_sp404_disable_layout_midi.py sp404-mk2/SP404/SP404.tosc
python3 tools/toscbuild.py build sp404-mk2/SP404
```

The patch **removes** `<midi>` from `control_fader` and on/off button nodes entirely (matching bus 1).

BCR on/off inbound (port 2): CC 65 toggle, 66 sync (on release val=0), 73 grab, 74 choose → `on_off_button_group` via `bcr_*` notifies. BCR buttons: **127 = on, 0 = off**.

## Launchpad Pro preset grid

In Programmer layout (MIDI channel 10), preset pads use columns 1–5 (one column per bus, preset 1 at the top). Columns 6–8 are unused. Note map is built in `preset_grid_manager.lua` and `root.lua` — keep both in sync.

## Layout backups and bus UI sync

Do not use git to recover `.tosc` layout work — committed snapshots are often stale.

- **`toscbuild`** writes timestamped backups to `SP404/backups/SP404_YYYYMMDD_HHMMSS.tosc` before each build.
- **`tools/sync_bus1_ui_to_buses.py`** copies frames from `bus1_group` to buses 2–5 (`control_group` + `effect_chooser`), with its own timestamped backup first.
- **`tools/sync_bus1_ui_to_buses.py --diff-only`** lists frame differences vs bus1 without writing.

After editing bus 1 in TouchOSC Editor, run sync then build:

```bash
python3 tools/sync_bus1_ui_to_buses.py sp404-mk2/SP404/SP404.tosc
python3 tools/toscbuild.py build sp404-mk2/SP404
```