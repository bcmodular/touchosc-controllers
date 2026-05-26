---
name: BCR FX Selector MIDI
overview: "Add inbound BCR2000 MIDI control for the effect selector modal: 8 encoder turns (CC 1–8) cycle highlights per column, 8 encoder pushes (CC 9–16) confirm selection, with TouchOSC-only color coding for the bus’s current effect vs the pending choice."
todos:
  - id: column-model
    content: Add 8-column effect lists, highlight state, and paintAllButtons() with current/pending/available colors in fx_selector_button_group.lua
    status: completed
  - id: midi-handlers
    content: Implement midi_column_tick (2's complement + 10-tick accumulator), midi_column_confirm, midi_reset; init highlight from bus fxNum on setup_ui
    status: completed
  - id: root-bcr-in
    content: Extend root.lua onReceiveMIDI for BCR port 2, ch 6, CC 1-16 when fx_selector_group visible
    status: completed
  - id: modal-reset
    content: Clear MIDI highlight state on modal hide in fx_selector_group.lua
    status: completed
  - id: build-test
    content: Run toscbuild and verify encoder turn/push + colors on device
    status: pending
isProject: false
---

# BCR2000 Effect Selector MIDI Control

## Confirmed layout (from screenshot)

The modal is **8 columns × 6 rows**, row-major. The existing [`effects`](sp404-mk2/lua/fx_selector_button_group.lua) array already matches this order, so column mapping is deterministic:

```lua
-- Column col (1–8), row row (1–6): effect index = (row - 1) * 8 + col
-- Col 1: 1,9,17,25,33,41 | Col 7: 7,14,21,28,35 | Col 8: 8,16,24,32,40,46
-- Row 6 cols 7–8 are empty (no buttons)
```

| Encoder | Column | Effects in column (max 6) |
|---------|--------|-------------------------|
| 1 | 1 | Filter+Drive → Back Spin |
| 2 | 2 | Resonator → DJFX Delay |
| … | … | … |
| 7 | 7 | Downer → SX Delay (5 items) |
| 8 | 8 | Ha-Dou → Cloud Delay (5 items) |

Gray buttons in row 6 (cols 3–6) are **unavailable** for the active bus (`allMidiValues[i][midiIndex] == 0`); encoder cycling should **skip** them.

## Current behavior (unchanged path)

```mermaid
sequenceDiagram
  participant BCR as BCR2000_Ch6
  participant Root as root.lua
  participant Modal as fx_selector_group
  participant Grid as fx_selector_button_group
  participant Bus as busN_group

  Note over BCR,Bus: Today: no BCR inbound; UI tap only
  Grid->>Bus: set_fx fxNum, fxName
  Bus->>Modal: toggle_visibility close
```

Touch path stays: button release → `set_fx` → [`bus_group_instance.lua`](sp404-mk2/lua/bus_group_instance.lua) `showBus()` + modal close.

## Target behavior

**Only when** [`fx_selector_group`](sp404-mk2/lua/fx_selector_group.lua) is visible:

| MIDI (Ch 6) | CC | Action |
|-------------|-----|--------|
| Encoder turn | 1–8 | Accumulate ticks, then step highlight (see **Encoder stepping** below) |
| Encoder push | 9–16 | Confirm highlighted effect in column `cc - 8` → same as UI tap (`set_fx`) |

- **Ch 6** = TouchOSC channel index **5** (`MIDIMessageType.CONTROLCHANGE + 5`), fixed for the BCR top row (independent of which bus opened the modal).
- **MIDI port**: BCR = connection 2 (`{ false, true }`), same as outbound fader sync in [`control_mapper.lua`](sp404-mk2/lua/control_mapper.lua).

No conflict with perform-fader BCR mapping: faders use CC **81, 82, 89, 90, 97, 98** on the bus-specific channel (6–10), not CC 1–16.

## Encoder stepping (2's complement + accumulation)

Your BCR top-row encoders are in **2's complement** relative mode:

| Turn | CC value | Direction |
|------|----------|-----------|
| Right (CW) | `1` | +1 |
| Left (CCW) | `127` | -1 |

Each physical detent sends one message — stepping one effect per tick would feel fiddly (up to 6 slots per column).

**Approach:** accumulate ticks per column; only advance the highlight after **N** ticks in the same direction. Start with **`ENCODER_STEPS_PER_SLOT = 10`** as a named constant at the top of `fx_selector_button_group.lua` for easy tuning.

```lua
local ENCODER_STEPS_PER_SLOT = 10
local columnAccumulator = {}  -- [1..8], signed int per column

local function encoderValueToDirection(value)
  if value == 0 then return 0 end
  if value == 1 then return 1 end
  if value == 127 then return -1 end
  -- Fallback for other 2's complement values (1–63 = +, 65–127 = -)
  if value >= 64 then return -1 end
  return 1
end

local function accumulateColumnTick(col, direction)
  if direction == 0 then return end
  columnAccumulator[col] = (columnAccumulator[col] or 0) + direction
  if columnAccumulator[col] >= ENCODER_STEPS_PER_SLOT then
    stepColumnHighlight(col, 1)
    columnAccumulator[col] = 0
  elseif columnAccumulator[col] <= -ENCODER_STEPS_PER_SLOT then
    stepColumnHighlight(col, -1)
    columnAccumulator[col] = 0
  end
end
```

**Behavior details:**

- Accumulator is **per column** (independent encoders).
- After a successful step, accumulator **resets to 0** (no carry-over of leftover ticks).
- Reversing direction before threshold reduces the accumulator (natural “undo” of partial turns).
- On `midi_reset` / modal hide: zero all accumulators.
- `root.lua` forwards raw CC value; decoding + accumulation live in `fx_selector_button_group.lua`.

**Test tuning:** If 10 feels too slow/fast, adjust only `ENCODER_STEPS_PER_SLOT` (try 6–15).

## TouchOSC color coding (your choice)

Apply **only on modal buttons** (not BCR LEDs):

| State | Suggested color | Source |
|-------|-----------------|--------|
| Unavailable | `8D8D8AFF` (existing gray) | `allMidiValues` |
| Available (default) | `F79000FF` (existing orange) | `setupUI` |
| **Current bus effect** | Bus accent hex | [`BUS_ACCENT_HEX`](sp404-mk2/lua/root.lua) via `root.tag.busAccentHex` |
| **Pending (encoder highlight)** | High-contrast distinct color, e.g. `FFFFFFFF` or `00FF88FF` | New constant in `fx_selector_button_group.lua` |

Paint priority: base availability → current effect → pending (pending wins if same cell).

## Implementation plan

### 1. Column model + highlight state — [`fx_selector_button_group.lua`](sp404-mk2/lua/fx_selector_button_group.lua)

Add at module scope:

- `NUM_COLUMNS = 8`, `buildColumnEffectLists()` — per column, ordered list of effect indices (1–46) that exist in the grid.
- `columnHighlight[1..8]` — 1-based index into that column’s **available-only** list (not raw row).
- `columnAccumulator[1..8]` — signed tick counter per column (see **Encoder stepping**).
- `ENCODER_STEPS_PER_SLOT = 10` — tunable constant.
- `getPendingFxIndex(col)` — returns global effect index for current highlight.

Refactor `setupUI()`:

- Call new `paintAllButtons()` that applies the four visual states above.
- On `setup_ui`: read current `fxNum` from `bus{busNum}_group` tag; for the column containing that effect, set `columnHighlight[col]` to that row; default other columns to `1` (first available in column).

New notify handlers:

- `midi_column_tick` — `{ col, ccValue }` → `encoderValueToDirection` → `accumulateColumnTick`
- `midi_column_confirm` — `{ col }` → if pending effect is available, `notify('set_fx', { fxNum, fxName })` (same as button script)
- `midi_reset` — clear `columnAccumulator` and optional highlight defaults

Helper `stepColumnHighlight(col, delta)`:

- Build filtered list (skip `allMidiValues[i][midiIndex] == 0`).
- Wrap index; call `paintAllButtons()`.

### 2. Inbound MIDI routing — [`root.lua`](sp404-mk2/lua/root.lua)

Extend `onReceiveMIDI` (pattern from [`p6-granular/BCR2000_P6/lua/root.lua`](p6-granular/BCR2000_P6/lua/root.lua)):

```lua
local FX_SELECTOR_BCR_CHANNEL = 5  -- MIDI ch 6
local FX_SELECTOR_TURN_CC = { 1,2,3,4,5,6,7,8 }
local FX_SELECTOR_PUSH_CC = { 9,10,11,12,13,14,15,16 }

local function midiFromBcr(connections)
  return type(connections) == "table" and connections[2] == true
end
```

Logic:

1. If SysEx → return (existing).
2. If Launchpad port 3 → existing preset/delete handling.
3. Else if BCR port 2 **and** `fx_selector_group.visible`:
   - Parse CC on channel 5.
   - CC 1–8: `midi_column_tick` with `{ col = cc, ccValue = value }` (accumulation in button group).
   - CC 9–16 with `value > 0`: `midi_column_confirm` with `{ col = cc - 8 }`.
   - Forward via `fx_selector_button_group:notify(...)`.
4. Else return.

Keep Launchpad and BCR paths mutually exclusive per message.

### 3. Modal lifecycle — [`fx_selector_group.lua`](sp404-mk2/lua/fx_selector_group.lua)

On `hide` / `hideSelector()`: optional `selectorButtons:notify('midi_reset')` to clear pending highlights (prevents stale state if reopened).

No `.tosc` layout changes required.

### 4. Build + test

```bash
python3 tools/toscbuild.py build sp404-mk2
```

**Manual test checklist:**

- Open FX modal for bus 1 (BCR ch 6) and bus 3 (still ch 6 encoders; availability changes per `midiIndex`).
- Turn encoders 1–8: ~10 detents per slot change; reversing direction cancels partial accumulation; unavailable cells never selected.
- Cols 7–8: only 5 steps; no crash on row 6 empties.
- Push encoders 9–16: loads effect, closes modal, faders init (same as tap).
- Current effect shows bus accent; pending shows second color; both visible when different.
- Modal closed: BCR CC 1–16 ignored; perform faders still work outbound on CC 81+.

## Files to change

| File | Change |
|------|--------|
| [`fx_selector_button_group.lua`](sp404-mk2/lua/fx_selector_button_group.lua) | Column lists, highlight state, `paintAllButtons`, MIDI notify handlers |
| [`root.lua`](sp404-mk2/lua/root.lua) | BCR inbound CC routing when modal visible |
| [`fx_selector_group.lua`](sp404-mk2/lua/fx_selector_group.lua) | Reset highlight on hide (small) |

No `toscbuild.json` mapping changes (scripts already injected).

## Design notes

- **Encoder 8 / empty cells**: Columns 7–8 simply have shorter lists; no special case beyond list length.
- **2's complement**: Primary mapping is `1` = CW, `127` = CCW; generic fallback handles other relative values if the template changes.
- **Tuning**: Only `ENCODER_STEPS_PER_SLOT` should need changing after hands-on feel test (default 10).
- **Future**: Inbound BCR for perform faders (CC 81+) can reuse the same `root.lua` pattern but must be gated when modal is open to avoid cross-talk.
