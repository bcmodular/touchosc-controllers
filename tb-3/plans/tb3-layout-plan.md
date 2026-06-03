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
- Split down the middle: left = EFX1, right = EFX2
- **Top-row encoder 1 (EFX1) / encoder 5 (EFX2):** rotate to cycle effect type, **push to toggle on/off** — dedicated type-select + SW, separate from the parameter block. Top-row encoders 2–4 / 6–8 are not used for EFX parameters.
- **Bottom 3 rows (4×3 block per side = 12 slots):** all effect parameters — 11 slots active for EQ (maximum), 1 spare slot hidden for all other types
- 8 buttons per side: entirely dedicated to discrete param modes (BPM SYNC, waveform type, mode, polarity etc.) since on/off is handled by encoder push

### Effects Context-Switch (same pattern as SP-404 fx_selector)

EFX1 and EFX2 each have a `type` selector with 10/9 choices. When type changes:
- `efx_section.lua` updates each of the 11 parameter slot labels and SysEx address targets
- Slots with no parameter for the current type are hidden/disabled
- BCR2000 #2 encoder labels update via same notify path

### Effects Hardware Layout — Buttons vs Encoders

**BCR2000 #2 gives us 8 buttons + 12 encoders per effect side.**

Three tiers of discreteness drive the button assignments:

**`SW` on/off is removed from the button budget** — handled by pushing the type-select encoder (encoder 1 / encoder 5). The 8 buttons per effect are now entirely for discrete parameter modes.

**BPM SYNC dual-mode (TR, CH, FL, PH, DD):**
- BPM SYNC toggle → button 1. When ON, the RATE encoder repurposes as the beat-division selector (21 values: OFF, 2 bars … 3/128). When OFF, RATE controls milliseconds. Handled in Lua by the efx_section context switcher.

**Effect-specific mode buttons:**
Small-choice enums (≤7) map to dedicated buttons; large enums (10+) and continuous ranges stay as encoders.

Per-effect breakdown (8 buttons available, SW handled by encoder push):

| Effect | Buttons | Encoder count | Notes |
|--------|---------|---------------|-------|
| **CS** Compressor | RATIO presets (e.g. 1:2, 1:4, 1:INF) — optional 3 buttons | 7 | RATIO (14) + KNEE (10) stay as encoders; buttons are convenience shortcuts |
| **RM** Ring Mod | POLARITY toggle (UP/DOWN) | 6 | |
| **BC** Bitcrusher | — | 5 | No useful discrete params |
| **TR** Tremolo | BPM SYNC, TYPE ↑/↓ (6 waveforms, 2 cycle buttons), PAN/TRE select | 5 | 4 buttons used; PHASE, SHAPE, DEPTH, RATE/DIV, LEVEL as encoders |
| **CH** Chorus | BPM SYNC, MODE × 3 (MONO/S1/S2 dedicated) | 6 | 4 buttons used |
| **FL** Flanger | BPM SYNC | 8 | 1 button used; most params continuous |
| **PH** Phaser | BPM SYNC, TYPE ↑ (4 stages, cycle), STEP RATE on/off | 6 | 3 buttons used |
| **DD** Delay | BPM SYNC, TYPE × 3 (SINGLE/PAN/STEREO dedicated) | 6 | 4 buttons used |
| **PS** Pitch Shifter | VOICE × 3 (1MONO/2MONO/2STEREO dedicated) | 8 | 3 buttons used; EFX1 only |
| **EQ** Equalizer | — | 11 | Maximum; all params continuous or high-cardinality |
| **RV** Reverb | TYPE × 7 (one per reverb type: AMB/ROOM/HALL1/HALL2/PLATE/SPRING/MOD) | 8 | 7 buttons used; EFX2 only — instant one-touch type switching |

**Maximum encoder requirement: 11 (EQ).** The 12-slot parameter block per effect (bottom 3 rows) accommodates this with one spare slot. Type selection and SW are handled separately by the top-row push encoders and never occupy a parameter slot.

**HPF/LPF frequency** selectors (CH, FL, DD, RV, EQ) have 15–18 choices — stay as encoders.

**EQ Q** (6 choices: 0.5–16) — kept as encoder given EQ already hits the 11-slot ceiling.

### Per-Effect Parameter Grid Layout (4×3)

Each row is a logical functional group. Unused slots within a row are left blank/inactive — **grouping takes priority over contiguous fill.** These layouts define the CC-to-parameter mapping in `bcr_map.lua` and the BCR2000 preset files.

Notation: `—` = unused slot

**EQ (11 params — drives the 12-slot maximum):**
```
Row 1:  LOW CUT    LOW GAIN   HIGH CUT   HIGH GAIN    ← outer band pair
Row 2:  LM FREQ    LM Q       LM GAIN    —            ← low mid band
Row 3:  HM FREQ    HM Q       HM GAIN    LEVEL        ← high mid band + output
```

**CS — Compressor (7 params):**
```
Row 1:  THRESHOLD  RATIO      ATTACK     RELEASE      ← dynamics chain
Row 2:  KNEE       GAIN       BALANCE    —            ← colour
Row 3:  —          —          —          —
```

**RM — Ring Modulator (6 params):**
```
Row 1:  FREQUENCY  SENS       BALANCE    LEVEL        ← modulator + output
Row 2:  EQ LOW     EQ HIGH    —          —            ← tone shaping
Row 3:  —          —          —          —
```

**BC — Bitcrusher (5 params):**
```
Row 1:  FILTER     SAMP RATE  LEVEL      —
Row 2:  EQ LOW     EQ HIGH    —          —
Row 3:  —          —          —          —
```

**TR — Tremolo (5 encoder params; TYPE/PAN/BPM SYNC on buttons):**
```
Row 1:  RATE/DIV   DEPTH      SHAPE      LEVEL
Row 2:  PHASE      —          —          —
Row 3:  —          —          —          —
```

**CH — Chorus (6 encoder params; BPM SYNC/MODE on buttons):**
```
Row 1:  RATE/DIV   DEPTH      PRE DELAY  LEVEL
Row 2:  HPF        LPF        —          —
Row 3:  —          —          —          —
```

**FL — Flanger (8 encoder params; BPM SYNC on button):**
```
Row 1:  RATE/DIV   DEPTH      MANUAL     RESONANCE
Row 2:  SEPARATION HPF        EFX LVL    DIRECT LVL
Row 3:  —          —          —          —
```

**PH — Phaser (6 encoder params; BPM SYNC/TYPE/STEP RATE on buttons):**
```
Row 1:  RATE/DIV   DEPTH      MANUAL     RESONANCE
Row 2:  EFX LVL    DIRECT LVL —          —
Row 3:  —          —          —          —
```

**DD — Delay (6 encoder params; BPM SYNC/TYPE on buttons):**
```
Row 1:  TIME/DIV   TAP TIME   FEEDBACK   LPF
Row 2:  EFX LVL    DIRECT LVL —          —
Row 3:  —          —          —          —
```

**PS — Pitch Shifter (8 params; VOICE on buttons; EFX1 only):**
```
Row 1:  PITCH 1    PRE DLY 1  EFX LVL 1  FEEDBACK
Row 2:  PITCH 2    PRE DLY 2  EFX LVL 2  DIRECT LVL
Row 3:  —          —          —          —
```

**RV — Reverb (8 params; TYPE on buttons; EFX2 only):**
```
Row 1:  TIME       PRE DELAY  DENSITY    SPRING SENS
Row 2:  HPF        LPF        EFX LVL    DIRECT LVL
Row 3:  —          —          —          —
```

These grid positions map directly to fixed CC numbers on the BCR2000. When the effect type changes, `efx_section.lua` remaps each slot's label and SysEx target address — the CC number assigned to each physical encoder never changes.

### BCR2000 MIDI Mapping Reference

**Create this before any implementation.** The mapping table is the contract that both `bcr_map.lua` (TouchOSC side) and the physical BCR2000 preset agree on. Created as markdown in `tb-3/bcr2000/` for version control; the BCR2000 itself is programmed to match.

**Files to create:**
```
tb-3/bcr2000/
  bcr2000-1-tone-dist.md    CC assignment table for BCR2000 #1
  bcr2000-2-efx.md          CC assignment table for BCR2000 #2
```

**Suggested CC organisation:**
- BCR2000 #1: MIDI CH 3, CCs 1–64 (encoders + buttons, top row first then middle then bottom)
- BCR2000 #2: MIDI CH 4, CCs 1–64 (same layout convention)
- Using a dedicated channel per BCR2000 avoids CC number collisions and makes routing in `onReceiveMIDI` straightforward (`midiFromBcr1` / `midiFromBcr2` checks by connection/channel)

**BCR2000 #2 CC layout (EFX1 left / EFX2 right):**

| Control | CC (EFX1) | CC (EFX2) | Function |
|---------|-----------|-----------|---------|
| Top row encoder 1 / 5 | 1 | 5 | EFX type select (rotate) + on/off (push → CC or Note) |
| Top row encoders 2–4 / 6–8 | 2–4 | 6–8 | Param slots 1–3 |
| Middle group 1 encoders (4) | 9–12 | 25–28 | Param slots 4–7 |
| Middle group 2 encoders (4) | 13–16 | 29–32 | Param slots 8–11 |
| Buttons 1–8 (left) | 33–40 | — | EFX1 discrete modes |
| Buttons 1–8 (right) | — | 41–48 | EFX2 discrete modes |

*(Exact CC numbers TBD — the above illustrates the convention; finalize from BCR2000 bank layout.)*

**Push-button handling:** BCR2000 encoder push buttons can be configured to send either Note On or CC. We'll use CC (e.g., CC 1 with value 127 = push down, 0 = release) so `onReceiveMIDI` can handle everything uniformly as CC messages without special Note handling.

---

## Phased Delivery

### Phase 0 — BCR2000 Mapping Tables (prerequisite)

**Goal:** Complete CC assignment tables for both BCR2000s before any Lua code is written. These are the reference contract for all subsequent phases.

**Deliverables:**
- `tb-3/bcr2000/bcr2000-1-tone-dist.md` — full CC table for BCR2000 #1 (VCO/VCF/VCA/LFO/Dist), derived from the user's diagram (IMG_2885.JPG) and confirmed against available bank slots
- `tb-3/bcr2000/bcr2000-2-efx.md` — full CC table for BCR2000 #2 (EFX1/EFX2), detailing type-select encoders, 11 param slots, and 8 discrete-mode buttons per side

**Outcome:** Once approved, these tables drive `bcr_map.lua` in Phase 1 and the physical BCR2000 programming.

---

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
