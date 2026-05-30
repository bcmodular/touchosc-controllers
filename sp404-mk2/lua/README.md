# SP-404 MKII — Lua contributor guide

End-user documentation (MIDI setup, BCR2000, Launchpad Pro, presets/scenes, backup) lives in [**../README.md**](../README.md).

## Naming Conventions

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

recallPreset = function(busNum, presetNum)  -- assign to the forward-declared local
  -- ...
end
```

**Critical:** the function that fills the forward declaration **must** use `name = function(...)` (plain assignment), **not** `local function name(...)`. Using `local function` creates a *new* local that shadows the forward declaration — the original stays `nil` and any closure that captured it will fail at runtime with "attempt to call upvalue (a nil value)".

**Do not** assume `local function` hoists like JavaScript `function` declarations — it does not.

**Quick check:** before committing, grep for `local function` names and confirm every call site is **below** the definition (or behind a forward declare).

## No Namespace Tables

TouchOSC runs each node's script in its own isolated Lua environment. Scripts included together via `toscbuild.json` `"include"` are concatenated into one script for that node. **Module-style namespace tables add verbosity with no isolation benefit.**

```lua
-- Bad: unnecessary table namespace
Keyboard = {}
Keyboard.SUSTAIN_CC = 64
function Keyboard.handleMidi(msg) ... end

-- Good: plain locals
local SUSTAIN_CC = 64
local function handleMidi(msg) ... end
```

### The 200-local limit and the setup-function pattern

Lua enforces a hard limit of **200 local variables per function** (or per top-level chunk). Because all `"include"` files and the main `.lua` file share one concatenated chunk, every `local` across all files counts toward the same 200. A file with many functions can easily exhaust this.

**Solution:** wrap large included files in a named setup function. Each Lua function has its own independent 200-local budget. All locals defined inside the setup function become upvalues captured by the public closures — so state variables survive after the setup function returns.

```lua
function _initKeyboard()

  local SUSTAIN_CC = 64
  local keyboardAttachedBus = nil  -- survives as an upvalue

  local function handleMidi(msg) ... end

  -- Public entry points: assigned as globals (no 'local') so root.lua can call them.
  -- They close over all the locals above.
  function handleKeyboardMidi(message, connections)
    ...
  end

end
_initKeyboard()
```

The setup function itself is a global (no `local`), contributing 0 locals to the chunk. Public functions are assigned without `local` inside the setup function — Lua writes non-local assignments to the global environment even inside a function body.

`keyboard_manager.lua` uses this pattern. Files with fewer than ~40 locals (most helper scripts) don't need it.

### Rules

1. **Module-internal functions and variables**: `local` (inside an IIFE if the file is large).
2. **TouchOSC lifecycle callbacks** (`init`, `onReceiveMIDI`, `onReceiveNotify`, `onValueChanged`, `update`): plain globals — TouchOSC calls these by name.
3. **Cross-file entry points** in included files (called by name from the main script): plain globals — assigned without `local`, even inside an IIFE.
4. **Debug flags**: `local KEYBOARD_DEBUG = false` — easy to find and toggle.
5. Forward-declare with `local name` when mutual references are required (see section above).

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

## Hyper Reso keyboard grab (`keys_group` chord pads)

When keyboard grab is active on a bus running **Hyper Reso** (FX 31), `keys_group.tag.chordGridMode` is `hyper_reso_scale`. Pads **1–16** (names stay generic; top row 1–8, bottom row 9–16) select scale; the piano sends **relative NOTE** degrees (middle C = degree 1, ±1 per semitone, clamped ±18).

| Pad | Role |
|-----|------|
| 1 | Major |
| 2 | *(unused, hidden)* |
| 3–4, 6–8 | Black-key roots (C#, D#, F#, G#, A#) |
| 9 | Minor |
| 10–16 | White-key roots (C–B) |

Resonator/Vocoder/Harmony use `chord_pads` mode on the same pad indices (chord/harmony values). Constants live in `keyboard_manager.lua` (`HYPER_RESO_PAD_MAP`, `HYPER_RESO_NOTE_CC_VALUES`, `HYPER_RESO_SCALE_CC_VALUES`).

## MIDI routing (contributor notes)

Perform faders and on/off buttons have **no layout `<midi>` block** — routing is Lua-only (`root.lua` inbound, per-bus outbound). See [../README.md](../README.md) for port wiring and CC tables.

**Layout `<connections>` strings** (if re-enabling Editor MIDI): 10 digits, **right-aligned to connection number** — connection 2 = `0000000010`. Do not use `0100000000` for port 2.

After layout edits in TouchOSC Editor, strip perform MIDI and rebuild:

```bash
python3 sp404-mk2/tools/patch_sp404_disable_layout_midi.py sp404-mk2/SP404.tosc
python3 tools/toscbuild.py build sp404-mk2
```

Set `BCR_MIDI_DEBUG = false` in `root.lua` and `ON_OFF_DEBUG = false` in `on_off_button_group.lua` when done tracing.

## Layout backups and bus UI sync

Do not use git to recover `.tosc` layout work — committed snapshots are often stale.

- **`toscbuild`** writes timestamped backups to `backups/SP404_YYYYMMDD_HHMMSS.tosc` before each build.
- **`sp404-mk2/tools/sync_bus1_ui_to_buses.py`** copies frames from `bus1_group` to buses 2–5 (`control_group` + `effect_chooser`), syncs the `effect_chooser` header from bus 1, removes the legacy `background` box on other buses, preserves child **order** (z-index), assigns **new node IDs** per bus, and deduplicates duplicate IDs. TouchOSC’s editor uses node `ID` (not `name`) for selection — duplicate IDs cause “jump to wrong bus” when editing.
- **`sp404-mk2/tools/sync_bus1_ui_to_buses.py --diff-only`** lists frame differences vs bus1 without writing.

After editing bus 1 in TouchOSC Editor, run sync then build:

```bash
python3 sp404-mk2/tools/sync_bus1_ui_to_buses.py sp404-mk2/SP404.tosc
python3 tools/toscbuild.py build sp404-mk2
```