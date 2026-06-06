# TB-3 TouchOSC Layout — Phased Delivery Plan

> **Status as of 2026-06-06.** Phases 0–4 complete. Phase 4 testing/polish ongoing (EFX parameter display, BPM SYNC, disabled slot visualisation, time row layout — all done). Phase 5 (patch management app + parameter assign UI) not yet started.

---

## Context

Building a TouchOSC controller layout for the Roland TB-3 synthesizer, inspired by the Dope Robot Ctrlr panel but redesigned around two BCR2000s and TouchOSC's strengths. The TB-3 uses Roland SysEx for nearly all parameters — TouchOSC receives CCs from the BCR2000s, translates them to SysEx, and sends to the TB-3. The layout supports full patch dump/restore (SysEx dump from hardware; BCR2000 ring sync after receive).

**Not included:** pattern sequencer (externally sequenced), standard CC params for general MIDI use — CC 74/71 are tracked for display only.

Resources: `tb-3/resources/` — Ctrlr `.panel` file, SysEx spec v1.4.1, FX parameter guide HTML.

---

## BCR2000 Channel Routing

**Both units arrive on connection 2. Channel is the differentiator.**

| Channel | Unit | Controls |
|---------|------|----------|
| **CH 1** | BCR2000 #1 | VCO (Grp1), LFO (Grp2), fixed rows VCA/VCF/Tuning, distortion buttons |
| **CH 2** | BCR2000 #2 | EFX1 + EFX2 parameter slots, type select, action buttons |

Both units use the same BC Manager preset template, differing only in channel. Routing is by CC number alone within each channel — no mode state. Encoder group switching on BCR2000 #1 changes which CC range the top-row encoders emit (Grp1: CC1–8/CC33–40 for VCO; Grp2: CC9–16/CC41–48 for LFO), all on CH1.

---

## Current Layout Sections

| Section | Status | Notes |
|---------|--------|-------|
| `vco_group` | ✅ Complete | 8 encoders (SAW/SQR/SIN/WHITE/PINK/RING LVL + VCO LFO + patch vol); SW push per source |
| `lfo_group` | ✅ Complete | 8 encoders (Dope Robot order); BPM SYNC push, RETRIGGER push; **gold** colour |
| `vcf_group` | ✅ Complete | CUTOFF + RESONANCE first (visual + BCR order); full ADSR + ENV/KEY/LFO/ACCENT |
| `vca_group` | ✅ Complete | ADSR + VCA LFO DEPTH |
| `tuning_group` | ✅ Complete | SAW/SQR/RING+SIN tuning (16-bit bipolar ±128); global tuning via CC104 |
| `dist_group` | ✅ Complete | 25 types by name; ON/OFF, COLOR, TYPE ↑/↓; DRIVE/BOTTOM/TONE/EFX/DRY encoders |
| `portamento_group` | ✅ Complete | TIME encoder + SW; LEGATO/ALWAYS radio buttons (default LEGATO) |
| `pitch_bend_group` | ✅ Complete | RANGE encoder (0–17 semitones; raw scaling TBD — see Open Items) |
| `ring_mod_group` | ✅ Complete | 6 encoders; popup via EXTRAS button |
| `cross_mod_group` | ✅ Complete | 8 encoders (signed ±64); popup via EXTRAS button |
| `efx1_section` | ✅ Complete | 10 effect types; 12 parameter slots; 8 action buttons; full display labels |
| `efx2_section` | ✅ Complete | 9 effect types (incl. Reverb); same slot/button structure |

---

## Architecture

### Build Pipeline

`tools/toscbuild.py build tb-3` — injects Lua scripts into `TB3.tosc` per `toscbuild.json` mappings.

- **`scaffold`** subcommand rebuilds layout XML from `toscbuild.json` `layout` section. Used only when adding new UI nodes; preserve the existing `.tosc` otherwise (scaffold cannot recreate nodes not in the layout def — use the Python XML patch approach for targeted additions).
- **`build`** subcommand injects scripts only. Run after any Lua change.

214 scripts injected total across all nodes.

### Key File Locations

```
tb-3/
  TB3.tosc                    — built layout (binary zlib-compressed XML)
  toscbuild.json              — build manifest + scaffold definition
  lua/
    root.lua                  — MIDI/OSC entry points, SysEx helpers, BCR routing,
                                enc_moved/sw_toggled/porta_mode_set notify handlers
    bcr_map.lua               — CC→SysEx tables (BCR1_MAP, BCR2 helpers, ADDR_TO_BCR1_CC)
    patch_manager.lua         — REGISTRY + parseBlock(); applyValue(); parseSpecial()
    enc_map.lua               — ENC_SEND_MAP + SW_SEND_MAP (used by root enc_moved/sw_toggled)
    control_fader.lua         — build-injected into all RADIAL 'control_fader' nodes;
                                sends enc_moved notify to root
    sw_button.lua             — build-injected into all 'sw_button' BUTTON nodes;
                                sends sw_toggled notify to root
    pointer.lua               — build-injected into all 'pointer' BOX nodes;
                                drag/double-tap-reset; blocks input on disabled slots
    receive_button.lua        — SYNC FROM TB-3 button
    dist_toggle_button.lua    — DIST ON/OFF and DIST COLOR buttons
    dist_type_button.lua      — DIST TYPE ↑/↓ momentary buttons
    porta_radio_btn.lua       — LEGATO/ALWAYS portamento mode radio buttons
    efx_section.lua           — efx1_section + efx2_section: full EFX engine
    efx_button.lua            — B1–B8 action buttons per EFX section
    efx_chooser_button.lua    — type selector grid buttons (1–10 / 1–9)
  bcr2000/
    bcr2000-1-tone-dist.md    — BCR2000 #1 CC assignment reference (updated)
    bcr2000-2-efx.md          — BCR2000 #2 CC assignment reference
  plans/
    tb3-layout-plan.md        — this file
  resources/
    sysex-examples/           — 4 patch dump files (422 bytes each, 11 SysEx messages)
  screenshots/
    C06.png                   — current layout screenshot (patch C06)
```

### SysEx Protocol

```
F0 41 10 00 00 7B 12  [a1 a2 a3 a4]  [data...]  [checksum]  F7
```
- **Checksum:** `(0x100 - (sum_of_all_addr_and_data_bytes % 256)) % 128`
- **7-bit params:** single data byte `0x00`–`0x7F`
- **16-bit params** (VCF cutoff/resonance/env depth, tuning, accent): MSB = `value // 16`, LSB = `value % 16`
- **Signed params** (LFO depths, cross-mod): offset-encoded — raw 64 = zero, 0 = −64, 127 = +63
- **Bipolar 16-bit** (tuning): raw 0–255, centre 128 = 0; display shows −128…+127

### TouchOSC Lua Constraints (Lua 5.1)

**No bitwise operators** — use arithmetic equivalents:
- `status & 0xF0` → `status - (status % 16)`
- `status & 0x0F` → `status % 16`

**`findByName` is an instance method:**
- Always: `root:findByName("node_name", true)` (second arg = recursive)
- Child lookup: `group.children["child_name"]`

**`self.values`** — node's own values are `self.values.x`, not bare `values`.

**No `\x` hex escapes** — use decimal UTF-8 bytes: `"\194\176"` = degree symbol °.

Full details in `tb-3/lua/README.md`.

### Core Lua Architecture (as built)

**Notify-to-root pattern:** `control_fader.lua` (shared across all 80 RADIAL nodes) sends `enc_moved` to root with `"section,enc,x"`. Root looks up `ENC_SEND_MAP[section..","..enc]` (in `enc_map.lua`) to get the SysEx address, sends SysEx, updates the BCR LED ring via `ADDR_TO_BCR1_CC` reverse lookup, and corrects the value_label for signed/bipolar/custom-max parameters.

**Patch receive:** `onReceiveMIDI` decodes Roland DT1 SysEx → `parseBlock(addr, data)` in `patch_manager.lua`. The `REGISTRY` table maps each block address to a list of `{off, enc, kind, ...}` field descriptors. `applyValue()` sets fader position and value_label for each. EFX blocks are forwarded to `efx1_section`/`efx2_section` via notify as hex CSV strings.

**EFX engine (`efx_section.lua`):** Self-contained per section. Maintains `TYPE_DEFS` (10/9 effect definitions), `patch_data` (raw SysEx bytes), and slot state. On type change or patch receive: remaps 12 slot encoders with correct offsets, names, display functions, and `disabledBy` relationships. BCR2 CC feedback handled internally.

---

## Phased Delivery

### ✅ Phase 0 — BCR2000 Mapping Tables

BCR2000 CC assignment tables created and maintained:
- `bcr2000-1-tone-dist.md` — VCO/LFO dual-mode groups, fixed rows (VCA/VCF/Tuning), distortion buttons
- `bcr2000-2-efx.md` — EFX1/EFX2 parameter slots, type select, SW and action buttons

### ✅ Phase 1 — Foundation + Core Synthesis

- `toscbuild.json` scaffold + build manifest
- `root.lua`: SysEx helpers (`tb3Send7bit`, `tb3Send16bit`), BCR1/BCR2 routing, distortion type state machine, popup toggle, EFX chooser notify, OSC receiver
- `bcr_map.lua`: full CC→SysEx tables; `ADDR_TO_BCR1_CC` reverse lookup built at load
- `pointer.lua`: drag/double-tap-reset overlay, injected into all `pointer` BOX nodes
- TB3.tosc scaffolded, then reworked in TouchOSC app, then migrated to toscbuild.json scaffold

### ✅ Phase 1.5 — Patch Receive + Map Validation

- `decode_patch.py`: offline SysEx decoder — validated against Dope Robot Ctrlr panel for 4 sample patches
- `patch_manager.lua`: `REGISTRY` + `parseBlock()` covering all 11 synthesis blocks; `applyValue()` handles u7/u16/s7/sw/bipolar/special cases
- `receive_button.lua`: SYNC FROM TB-3 button triggering `requestPatchDump()`
- `enc_map.lua`: `ENC_SEND_MAP` and `SW_SEND_MAP`; `ADDR_TO_ENC` / `ADDR_TO_SW` reverse lookups
- `syncBCR1()`: after patch receive, pushes all fader positions to BCR2000 #1 LED rings; `syncTimer` fallback for split SysEx blocks
- OSC receiver (`/tb3/patch`): same `parseBlock` path as MIDI receive — test harness without live TB-3

**Map validation results (Starter Bass Reso 2 patch):**
- LFO depths: centre 64 confirmed (s7 = raw−64)
- Tuning (CV offset): centre 128 confirmed (bipolar 16-bit = raw−128), NOT centre 64
- DIST BOTTOM/TONE: raw 0–100 display (not ±50 — matching TB-3 panel)
- ACCENT (`14 0E`): confirmed
- VCO RING LEVEL (`08 07`) = Ring Mod "LEVEL" on panel — same byte, confirmed

### ✅ Phase 2 — LFO + Modulation Scripts

- `control_fader.lua`: shared RADIAL script — sends `enc_moved` notify; root routes via `ENC_SEND_MAP`
- `sw_button.lua`: shared sw_button script — sends `sw_toggled` notify; root routes via `SW_SEND_MAP`
- All encoder groups sending correct SysEx: VCF, VCA, LFO, Tuning, Portamento, Ring Mod, Cross Mod
- Value label display: signed (±64), bipolar (±50, ±128), 16-bit (0–255), custom max (0–17, 0–120 etc.)
- Portamento: TIME + SW + LEGATO/ALWAYS radio buttons (`porta_radio_btn.lua`); default LEGATO on load
- `pitch_bend_range_enc`: wired up (raw value; hardware scaling TBD — see Open Items)

### ✅ Phase 3 — Distortion

- `dist_toggle_button.lua`: ON/OFF and COLOR latch buttons
- `dist_type_button.lua`: TYPE ↑/↓ momentary buttons (25 types, named array)
- `patch_manager.lua` `parseSpecial("dist_type")`: updates section header label on patch receive
- All distortion encoders (DRIVE/BOTTOM/TONE/EFX LEVEL/DRY LEVEL) via shared `control_fader.lua` + `ENC_SEND_MAP`
- DIST BOTTOM and TONE: bipolar ±50 display (raw 0–100, centre 50 = 0)

### ✅ Phase 4 — Effects (EFX1 + EFX2)

Full context-sensitive EFX engine complete. Both sections share `efx_section.lua`.

**Core:**
- 10 effect types for EFX1 (COMP, RING MOD, BIT CRUSH, TREMOLO, CHORUS, FLANGER, PHASER, DELAY, PITCH SHIFT, EQ)
- 9 effect types for EFX2 (same minus PITCH SHIFT + EQ; adds REVERB)
- 12 parameter slots per section, dynamically remapped on type change
- Type chooser grid (efx_1_chooser / efx_2_chooser): tap to select, tap active to return to BYPASS
- Action buttons B1–B8: B1 = EFX SW; B2–B4 = BPM SYNC / utility controls; B5–B8 = type-option presets
- Reverb (EFX2): B2–B8 as reverb-type presets (AMBIENT/ROOM/HALL1/HALL2/PLATE/SPRING/MOD)
- BCR2 wired: slot CCs, button CCs, type rotate CC — all forwarded to `efx_section` via notify

**Parameter display:**
- `display(raw)` function field on all slot definitions — converts raw SysEx bytes to human-readable strings (dB, Hz, ms, semitones, beat divisions)
- Display functions: `dispBpmDiv`, `dispThreshold`, `dispDb20/15/40`, `dispBipolar50`, `dispRatio`, `dispKnee`, `dispCsAttack/Release`, `dispHPF`, `dispFLHPF`, `dispLPF`, `dispEQFreq`, `dispEQQ`, `dispTrType`, `dispPhase`, `dispRate`, `dispMs`, `dispPct`, `dispRevTime`, `dispPitchSt`
- Beat division table (`BPM_DIVS`): 21 entries — OFF, 2, 3/2 … 3/128

**BPM SYNC / time row layout:**
- Slots S01–S04 reserved exclusively for time/BPM parameters; S05+ for all other params
- `disabledBy` field: RATE/TIME slots greyed and input-blocked when BPM SYNC is non-zero
- `refreshDisabledLabels(def)`: iterates ALL 12 slots on each type/value change; clears stale grey from previous effect
- `pointer.lua`: rejects drag input when `self.parent.tag == "disabled"`

**Effect-specific:**
- Ring Mod POLARITY: two radio buttons (UP/DOWN) in action button row
- Phaser STEP RATE at S03; RATE disabled when either BPM SYNC or STEP RATE is non-zero
- Delay: TIME disabled when BPM SYNC on; BPM SYNC range 0–13 (14 divisions)
- Flanger HPF: condensed 11-step table `FL_HPF_FREQS` (Flat→800 Hz; exact values need hardware verification)

**BCR sync:** `sendBCRcc()` called for all slots in `applyType()` so BCR2 LED rings update on patch receive.

### 🔲 Phase 5 — Patch Management, Parameter Assign + Python Qt App

Not yet started.

**TouchOSC side:**
- OSC export/import of current patch state (JSON via element tag)
- `/tb3/request_dump` OSC trigger for remote dump request already implemented

**Python Qt app (`tb-3/preset-manager/`):**
- Modelled on `sp404-mk2/preset-manager/python/`
- Receives OSC from TouchOSC, stores as JSON patch files
- Sends OSC back to layout for recall

**Parameter Assign UI:**

Assigns synthesis parameters to the TB-3's four hardware controls (EFFECT knob, PAD X/Y/Z). SysEx: `10 00 14 04`–`10 00 14 0B` (four 16-bit parameter IDs).

UX flow:
1. User taps one of four assign buttons [EFFECT] / [PAD X] / [PAD Y] / [PAD Z]
2. Layout enters assign mode; status label reads e.g. "Tap encoder to assign to EFFECT knob"
3. User taps any encoder → that parameter assigned, mode exits

Root-centric architecture: `root.lua` owns the full `PARAM_ID` table (encoder name → 16-bit ID); `pointer.lua` sends `encoder_tapped` notify and stays parameter-agnostic.

---

## Verification Checklist (per phase)

1. `python3 tools/toscbuild.py build tb-3` exits clean (214/214 scripts)
2. Load `TB3.tosc` in TouchOSC
3. Move a fader → MIDI monitor shows correct SysEx frame, address, checksum
4. BCR2000 encoder turn → fader moves in TouchOSC AND correct SysEx sent
5. Press SYNC FROM TB-3 → faders and BCR LED rings populate from hardware

**Checksum sanity:** LFO RATE `10 00 00 00`, value `0x40` → checksum = `(0x100 − (0x10+0x00+0x00+0x00+0x40) % 256) % 128 = 48`.

---

## Open Items

| Item | Status | Notes |
|------|--------|-------|
| **BENDER RANGE scaling** | ⚠️ Unresolved | Raw `0x17`=23 at hardware, panel shows 17. Offset? Scale? Needs second patch with different value or hardware test. Stored/sent as raw for now. |
| **Flanger HPF table** | ⚠️ Needs verify | `FL_HPF_FREQS` (11 steps, Flat→800 Hz) is a best-guess approximation. Hardware test needed for exact frequencies. |
| **RATE display curve** | ⚠️ Needs verify | `dispRate` uses a linear approximation of the 8000ms→20ms log curve. |
| **EQ frequency mapping** | ⚠️ Needs verify | `dispEQFreq` / `dispEQQ` are estimates; hardware measurement needed. |
| **Compressor attack/release** | ⚠️ Needs verify | Linear approximation of actual curves. |
| **Phase 5** | 🔲 Not started | Python preset manager + parameter assign UI |
| **CC16/CC17 (Accent, Effect)** | 🔲 Deferred | TB-3 hardware knobs send these; depend on parameter assign (Phase 5) |
| **Global TUNING (CC104)** | ✅ Resolved | BCR1 CC100 sends plain MIDI CC 104 to TB-3 CH2 (not SysEx). Device-global, not in patch dumps. |
| **TB3.tosc naming fixes** | ✅ Resolved | All naming issues from early planning resolved in final layout. |
