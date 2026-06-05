# SP-404 MK2 — Lua contributor guide

General TouchOSC/Lua patterns (naming, scoping, `findByName`, Lua 5.1 constraints,
namespace rules, 200-local limit, grid scope, button state) live in the shared
[**`docs/lua-guide.md`**](../../docs/lua-guide.md). Read that first.

End-user documentation (MIDI setup, BCR2000, Launchpad Pro, presets/scenes, backup)
lives in [**../README.md**](../README.md).

---

## MIDI routing (contributor notes)

Perform faders and on/off buttons have **no layout `<midi>` block** — routing is
Lua-only (`root.lua` inbound, per-bus outbound). See [../README.md](../README.md)
for port wiring and CC tables.

**Layout `<connections>` strings** (if re-enabling Editor MIDI): 10 digits,
**right-aligned to connection number** — connection 2 = `0000000010`.
Do not use `0100000000` for port 2.

After layout edits in TouchOSC Editor, strip perform MIDI and rebuild:

```bash
python3 sp404-mk2/tools/patch_sp404_disable_layout_midi.py sp404-mk2/SP404.tosc
python3 tools/toscbuild.py build sp404-mk2
```

Set `BCR_MIDI_DEBUG = false` in `root.lua` and `ON_OFF_DEBUG = false` in
`on_off_button_group.lua` when done tracing.

---

## Prefer direct control over `notify`

See the shared guide for general guidance. SP-404-specific example:

```lua
-- Find bus group and notify directly (scripted button values won't fire onValueChanged)
local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
busGroup:notify("set_fx", { fxIdx, fxName, false })
```

```lua
-- From a child pad: resolve bus from parent.tag, notify bus — not self
local busGroup = root:findByName('bus' .. tostring(self.parent.tag) .. '_group', true)
busGroup:notify('set_fx', { self.tag, self.name, false })
```

---

## Layout backups and bus UI sync

Do not use git to recover `.tosc` layout work — committed snapshots are often stale.

- **`toscbuild`** writes timestamped backups to `backups/SP404_YYYYMMDD_HHMMSS.tosc`
  before each build.
- **`sp404-mk2/tools/sync_bus1_ui_to_buses.py`** copies frames from `bus1_group`
  to buses 2–5 (`control_group` + `effect_chooser`), syncs the `effect_chooser`
  header from bus 1, removes the legacy `background` box on other buses, preserves
  child **order** (z-index), assigns **new node IDs** per bus, and deduplicates
  duplicate IDs. TouchOSC's editor uses node `ID` (not `name`) for selection —
  duplicate IDs cause "jump to wrong bus" when editing.
- **`--diff-only`** lists frame differences vs bus 1 without writing.

After editing bus 1 in TouchOSC Editor, run sync then build:

```bash
python3 sp404-mk2/tools/sync_bus1_ui_to_buses.py sp404-mk2/SP404.tosc
python3 tools/toscbuild.py build sp404-mk2
```

---

## Launchkey MK4 integration

The Launchkey MK4 uses **two separate USB ports**:

| Connection | Index | Direction | Purpose |
|------------|-------|-----------|---------|
| MIDI port  | 4     | in + out  | Keyboard notes, pads, encoders (standalone Custom Modes) |
| DAW port   | 5     | out only  | Pad/encoder mode switching, (future) screen display |

### Pad and encoder mode switching

Mode switches go to **connection 5** (`LAUNCHKEY_DAW_CONNECTION = { false, false, false, false, true }`).

Before each mode select, send feature controls enable: `9F 0B 7F`.

```
Pad mode select:      B6 1D <mode>    (CC on ch7)
  01h = Layout (default drum mode)
  05h = Custom Mode 1   (Hyper Reso pads)
  06h = Custom Mode 2   (Resonator pads)

Encoder mode select:  B6 1E <mode>    (CC on ch7)
  06h = Custom Mode 1   (factory default / reset)
  07h = Custom Mode 2   (Hyper Reso encoder labels)
  08h = Custom Mode 3   (Resonator encoder labels)
  09h = Custom Mode 4   (Vocoder encoder labels)
```

**Standalone mode constraint:** only custom encoder modes (06h–09h) can be
selected without DAW mode. Built-in modes (Plugin = 02h, Mixer = 03h) require
DAW mode and must not be used in standalone.

Functions `switchLaunchkeyDrumCustomMode(n)`, `resetLaunchkeyDrumMode()`,
`switchLaunchkeyEncoderCustomMode(n)`, and `resetLaunchkeyEncoderMode()` live
in `launchkey_led.lua` (included into `root.lua`).

### Encoder CC routing

When a keyboard-mode FX is grabbed, the 6 encoders (CCs 21–26, ch1, connection 4)
control FX parameters:

| Encoder | CC | Hyper Reso (FX 31) | Resonator (FX 2) | Vocoder (FX 44) |
|---------|----|--------------------|-----------------|-----------------|
| 1 | 21 | `note_fader`      | `root_fader`    | `note_fader`    |
| 2 | 22 | `spread_fader`    | `bright_fader`  | `formant_fader` |
| 3 | 23 | `character_fader` | `feedback_fader`| `tone_fader`    |
| 4 | 24 | `scale_fader`     | `chord_fader`   | `scale_fader`   |
| 5 | 25 | `feedback_fader`  | `panning_fader` | `chord_fader`   |
| 6 | 26 | `env_mod_fader`   | `env_mod_fader` | `balance_fader` |

Bidirectional: encoder moves update the SP-404 via `applyFaderCc`; fader changes
push back via `syncEncoderPositionsToLaunchkey` (sends CCs 21–26 on connection 4,
**not** connection 5).

`LAUNCHKEY_MIDI_OUT_CONNECTION = { false, false, false, true }` (connection 4).

### Vocoder pitch bend

Use raw `0xE0` rather than `MIDIMessageType.PITCH_BEND` — the TouchOSC Lua
environment may not define this constant (resulting in silent nil comparisons).

```lua
if msgType == 0xE0 then  -- PITCH_BEND
  sendMIDI({ 0xE0 + SP404_VOCODER_CHANNEL, data1, data2 }, SP404_CONNECTION)
end
```

---

## Hyper Reso keyboard grab (`keys_group` chord pads)

When keyboard grab is active on a bus running **Hyper Reso** (FX 31),
`keys_group.tag.chordGridMode` is `hyper_reso_scale`. Pads **1–16** select scale;
the piano sends **relative NOTE** degrees (middle C = degree 1, ±1 per semitone,
clamped ±18).

| Pad | Role |
|-----|------|
| 1 | Major |
| 2 | *(unused, hidden)* |
| 3–4, 6–8 | Black-key roots (C#, D#, F#, G#, A#) |
| 9 | Minor |
| 10–16 | White-key roots (C–B) |

Constants live in `keyboard_manager.lua` (`HYPER_RESO_PAD_MAP`,
`HYPER_RESO_NOTE_CC_VALUES`, `HYPER_RESO_SCALE_CC_VALUES`).
