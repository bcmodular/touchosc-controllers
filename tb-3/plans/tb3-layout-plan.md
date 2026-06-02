# TB-3 TouchOSC Layout — Phased Delivery Plan

## Context

Building a TouchOSC controller layout for the Roland TB-3 synthesizer, inspired by the Dope Robot Ctrlr panel but redesigned around two BCR2000s and TouchOSC's strengths. The TB-3 uses Roland SysEx for nearly all parameters — TouchOSC will receive CCs from the BCR2000s, translate them to SysEx, and send to the TB-3. The layout will also support patch dump/restore (request SysEx dump from hardware; send current state to hardware).

**Not included:** pattern sequencer (user externally sequences), standard CC params (CC 74 etc. — only used for BCR2000 input).

Resources: `tb-3/resources/` — Ctrlr `.panel` file, SysEx spec v1.4.1, FX parameter guide HTML.

---

## Architecture

### SysEx Protocol

Every TB-3 parameter change uses:
```
F0 41 10 00 00 7B 12  [addr4] [addr3] [addr2] [addr1]  [data...]  [checksum]  F7
```
- **Checksum:** `(0x100 - (sum_of_all_addr_and_data_bytes % 256)) % 128`  
- **7-bit params:** single data byte `0x00`–`0x7F`  
- **16-bit params** (VCF cutoff, resonance, env depth): MSB = `value // 16`, LSB = `value % 16`  
- **Signed params** (LFO depths): offset-encoded — raw value 64 = zero, 0 = -64, 127 = +63  

SysEx is channel-independent (channel embedded in device ID byte `10`).

### Lua SysEx Helpers (root.lua)

```lua
local TB3_CONNECTION = { true, false, false, false }  -- adjust per setup

local function tb3Checksum(bytes)
    local sum = 0
    for _, b in ipairs(bytes) do sum = sum + b end
    return (0x100 - (sum % 256)) % 128
end

local function tb3Send7bit(a1, a2, a3, a4, value)
    local addr = {a1, a2, a3, a4}
    local cs = tb3Checksum({a1, a2, a3, a4, value})
    sendMIDI({0xF0,0x41,0x10,0x00,0x00,0x7B,0x12, a1,a2,a3,a4, value, cs, 0xF7}, TB3_CONNECTION)
end

local function tb3Send16bit(a1, a2, a3, a4, value)
    local msb = math.floor(value / 16)
    local lsb = value % 16
    local cs = tb3Checksum({a1, a2, a3, a4, msb, lsb})
    sendMIDI({0xF0,0x41,0x10,0x00,0x00,0x7B,0x12, a1,a2,a3,a4, msb,lsb, cs, 0xF7}, TB3_CONNECTION)
end
```

These are globals in root.lua so build-injected per-control scripts can call them directly.

### Build Pipeline

Reuses `tools/toscbuild.py` from sp404-mk2 unchanged.

```
tb-3/
  TB3.tosc              initial scaffold, refined in TouchOSC app
  toscbuild.json        build manifest (mappings + layout scaffold)
  lua/
    root.lua            SysEx helpers, BCR receive routing, dump receive parser
    vcf_controls.lua    one script injected into each VCF fader node
    vco_controls.lua    VCO fader script
    vca_controls.lua    VCA fader script
    lfo_controls.lua    LFO fader script
    dist_section.lua    Distortion controls + type selector logic
    efx_section.lua     EFX1 / EFX2 type selector + context param swapping
    efx_control.lua     Per-slot EFX parameter fader script
    patch_manager.lua   Dump request / receive / send-all logic
    bcr_map.lua         CC-to-address lookup tables (included into root.lua)
```

**Workflow per phase:**
1. Scaffold skeleton `.tosc` nodes (correctly named, rough positions) via `toscbuild.json layout`
2. User refines visual layout in TouchOSC app
3. Write Lua scripts, add `mappings` entries in `toscbuild.json`
4. `python3 tools/toscbuild.py build tb-3` injects scripts
5. Test MIDI output with a monitor

### Screen & Layout Structure

- **Canvas:** 1920×1080 (matches SP-404 layout)
- **Single-screen, no tabs** — all main synthesis and effects parameters visible simultaneously
- Rough column split: VCO | VCF+VCA | LFO+Mod | Distortion | EFX1 | EFX2
- Distortion and EFX sections use context-sensitive slot panels (no hidden tabs)
- **Settings modal popup** (not always-visible): on-device BCR2000 CC mapping configuration, MIDI channel

### BCR2000 Mapping

**BCR2000 #1 — Tone + Dist** (from user diagram, CC assignments TBD per encoder layout):

| Row | Cols 1–4 | Col 5 | Col 6 | Col 7 | Col 8 |
|-----|----------|-------|-------|-------|-------|
| Enc 1 | SAW / SQR / SIN / WHITE on-off | PINK on-off | PORTA TIME + on-off | VCO LFO MOD | VCO LEVEL |
| Btn  | — | — | PORTA MODE | DIST TYPE ↑ | DIST TYPE ↓ / COLOR |
| Enc 2 | VCA A / D / S / R | VCA LFO MOD | DRIVE | BOTTOM | TONE |
| Enc 3 | VCF A / D / S / R | CUTOFF | RES | ACCENT | DIST LEVEL |
| Enc 4 | SAW / SQR / RING+SIN LEVEL | TUNING? | VCF ENV DEPTH | KEY FOLLOW | VCF LFO MOD | DRY LVL |

**BCR2000 #2 — EFX1 + EFX2:**
- Two 4×3 encoder blocks split down the middle (12 slots each)
- Left block (encoders 1–12): EFX1 — type selector + up to 11 context-sensitive param slots
- Right block (encoders 13–24 or 17–28): EFX2 — same structure
- Remaining encoders/buttons: effect on/off, type ↑/↓, spare
- 12 slots neatly covers the maximum (EQ at 11 params)

### Effects Context-Switch (same pattern as SP-404 fx_selector)

EFX1 and EFX2 each have a `type` selector with 10/9 choices. When type changes:
- `efx_section.lua` updates each of the 12 parameter slot labels and SysEx address targets
- Slots with no parameter for the current type are hidden/disabled
- BCR2000 #2 encoder labels (if screen display supported) update via same notify path

Effect types and max param counts:
| Type | EFX1 | EFX2 | Params |
|------|------|------|--------|
| CS (Compressor) | ✓ | ✓ | 7 |
| RM (Ring Mod) | ✓ | ✓ | 7 |
| BC (Bitcrusher) | ✓ | ✓ | 5 |
| TR (Tremolo) | ✓ | ✓ | 8 |
| CH (Chorus) | ✓ | ✓ | 7 |
| FL (Flanger) | ✓ | ✓ | 8 |
| PH (Phaser) | ✓ | ✓ | 9 |
| DD (Delay) | ✓ | ✓ | 7 |
| PS (Pitch Shifter) | ✓ | — | 8 |
| RV (Reverb) | — | ✓ | 8 |
| EQ | ✓ | ✓ | 11 |

12 slots covers the maximum (EQ at 11).

---

## Phased Delivery

### Phase 1 — Foundation + Core Synthesis

**Goal:** Working skeleton with VCO, VCF, VCA controls sending correct SysEx. BCR2000 #1 CCs routed through for core params.

**Deliverables:**
- `tb-3/` directory, `toscbuild.json`, `lua/` folder
- `root.lua`: `tb3Send7bit`, `tb3Send16bit`, `tb3Checksum`; `onReceiveMIDI` routing skeleton (BCR vs TB-3 source); `bcr_map.lua` included
- `bcr_map.lua`: CC→SysEx address table for all BCR2000 #1 parameters
- VCO controls: 6 source on/off toggles, 6 level faders (build-injected scripts using `tb3Send7bit` with `10 00 08 xx` addresses)
- VCF controls: cutoff + resonance + env depth (16-bit, `tb3Send16bit`), ADSR (7-bit), key follow
- VCA controls: ADSR, master volume
- Scaffold `.tosc` with correctly named nodes; user refines visual layout

**SysEx addresses used:**
- VCO levels/switches: `10 00 08 00`–`10 00 08 0D`
- VCF: `10 00 0A 00`–`10 00 0A 0A`
- VCA: `10 00 0C 00`–`10 00 0C 04`

**BCR routing in onReceiveMIDI:**
```lua
-- BCR CC → look up address in bcr_map → call tb3Send7bit/16bit → update fader value
```

### Phase 2 — LFO + Modulation

**Goal:** LFO section + modulation routing (cross mod, ring mod, CV offset, portamento).

**Deliverables:**
- `lfo_controls.lua`: rate, delay, 4 waveform levels (SAW/SQR/TRI/SIN), depths for VCO/VCF/VCA (signed, offset-encoded: display −64…+63, send 0…127)
- Cross Modulation section (10 params, `10 00 04 xx`)
- Ring Modulation section (14 params, `10 00 06 xx`)
- CV Offset + Parameter Assign (portamento rate/mode, bender range, accent level)
- LFO waveforms visible on SYNTHESIS tab, modulation amounts in a MOD sub-panel or expandable section

**SysEx addresses:**
- LFO: `10 00 00 00`–`10 00 00 0A`
- Cross Mod: `10 00 02 xx`
- Ring Mod: `10 00 03 xx` (check spec)
- CV Offset: `10 00 01 xx`

### Phase 3 — Distortion

**Goal:** Full distortion section on SYNTHESIS tab, BCR2000 #1 type selector buttons working.

**Deliverables:**
- `dist_section.lua`: on/off toggle, type up/down buttons (cycle through 25 types, display name), drive/bottom/tone/effect level/dry level faders, color on/off
- Type names array in Lua (25 distortion types from FX guide)
- BCR2000 #1 DIST TYPE ↑/↓ buttons → increment/decrement type, send SysEx, update display
- Distortion addresses: `10 00 10 xx` (verify from spec)

### Phase 4 — Effects (EFX1 + EFX2)

**Goal:** EFFECTS tab with context-sensitive 12-slot parameter display. BCR2000 #2 wired up.

**Deliverables:**
- `efx_section.lua`: type selector for EFX1 and EFX2; on type change, re-label + re-target all 12 slots; hide unused slots
- `efx_control.lua`: build-injected into each slot node — reads its current address/range from parent tag, sends SysEx
- `bcr_map.lua` extended: BCR2000 #2 CCs mapped to EFX1/EFX2 slots (parameterized — slot N maps to whatever the current type puts there)
- EFX1 on/off, EFX2 on/off buttons
- EFX addresses: `10 00 14 xx` (EFX1), `10 00 18 xx` (EFX2) — verify exact ranges from spec

### Phase 5 — Patch Management + Python Qt App

**Goal:** Full preset workflow — save/recall patches within the layout, dump/restore via OSC to a desktop app (like the SP-404 preset manager).

**Deliverables:**

*TouchOSC side (`patch_manager.lua`):*
- **Dump request:** sends Roland SysEx all-data request to TB-3 (`F0 41 10 00 00 7B 11 ...`)
- **Receive parser:** `onReceiveMIDI` hands incoming SysEx to parser; maps address bytes to control nodes via lookup table, calls `setValue` to populate faders
- **Send all to TB-3:** iterates all known controls, sends each as SysEx — initializes hardware from layout state
- **Patch storage:** current values stored as JSON in a dedicated element's `tag` property (same pattern as SP-404 preset_manager). Supports multiple named patch slots within the layout.
- **OSC export:** layout sends current patch state as OSC messages to the Python app
- **OSC import:** layout receives patch state from Python app, populates controls, then sends SysEx to TB-3

*Python Qt app (`tb-3/preset-manager/`):*
- Modelled on `sp404-mk2/preset-manager/python/`
- Receives OSC from TouchOSC layout, stores as JSON patch files
- Sends OSC back to layout to recall a patch
- UI: patch list, save/load/rename/delete, bulk export/import
- Dependencies: `python-osc`, `PyQt5` (same as SP-404 app)

*UI in layout:*
- DUMP FROM TB-3 button, SEND TO TB-3 button
- EXPORT PATCH / IMPORT PATCH buttons (trigger OSC to/from Python app)
- Patch name label, status indicator

---

## Verification

**Per phase:**
1. `python3 tools/toscbuild.py build tb-3` — exits with no errors
2. Load `TB3.tosc` in TouchOSC on Mac
3. Move a fader → capture MIDI output in a monitor (e.g. MIDI Monitor app) — verify correct SysEx frame, address, and checksum
4. BCR2000 encoder turn → verify fader in TouchOSC moves AND correct SysEx sent
5. Phase 5: press DUMP REQUEST → verify TB-3 responds and layout faders update

**Checksum sanity test** (can be done in `lua/` unit-test style before hardware):  
LFO RATE address `10 00 00 00`, value `40` (hex) → expected checksum = `(0x100 - (0x10+0x00+0x00+0x00+0x40) % 256) % 128 = (0x100 - 0x50) % 128 = 0xB0 % 128 = 48`.

---

## Design Note: Preset Storage Strategy

Two approaches are viable for Phase 5 — decide when we get there:

**A — Raw SysEx dump (simpler):** TB-3 sends a bulk SysEx dump → TouchOSC captures raw bytes → sends to Python app as OSC → Python stores the blob. Recall is the reverse: Python sends blob back via OSC → TouchOSC forwards to TB-3. The layout still parses the dump to populate its own faders for display, but storage is opaque — no per-parameter JSON needed. Aligns naturally with how the TB-3 dump receive already works.

**B — Per-parameter JSON (more flexible):** Parse all parameters into a structured dict, store in the layout `tag` and/or in the Python app. Enables partial recall, parameter inspection, and patch diffing, but more code.

Approach A is the likely choice if the TB-3 supports a clean all-parameters dump response. Confirm once we have hardware testing in Phase 5.

---

## Open Questions / Decisions for Later

- Exact CC assignments for BCR2000 #1 and #2 (user will confirm from BCR2000 bank config)
- Whether to show Cross Mod / Ring Mod / CV Offset on SYNTHESIS tab or a third tab
- Confirm exact SysEx addresses for EFX1/EFX2 blocks (spec doc needs careful re-read for those sections)
- Whether a MIDI channel config control is needed in the layout (TB-3 defaults to ch1; mostly irrelevant for SysEx)
