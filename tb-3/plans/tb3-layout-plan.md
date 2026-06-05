# TB-3 TouchOSC Layout — Phased Delivery Plan

> **Status as of 2026-06-05.** Phase 0 and Phase 1 foundation complete. Major layout redesign done in TouchOSC app. LFO group revision complete. BCR2 EFX mapping updated (SW on B1/B5, TR TYPE to encoder, PH TYPE to dedicated buttons). Phase 2 (LFO+Modulation scripts) is next.

---

## Context

Building a TouchOSC controller layout for the Roland TB-3 synthesizer, inspired by the Dope Robot Ctrlr panel but redesigned around two BCR2000s and TouchOSC's strengths. The TB-3 uses Roland SysEx for nearly all parameters — TouchOSC will receive CCs from the BCR2000s, translate them to SysEx, and send to the TB-3. The layout will also support patch dump/restore (request SysEx dump from hardware; send current state to hardware).

**Not included:** pattern sequencer (user externally sequences), standard CC params (CC 74 etc. — only used for BCR2000 input).

Resources: `tb-3/resources/` — Ctrlr `.panel` file, SysEx spec v1.4.1, FX parameter guide HTML.

---

## BCR2000 Channel Routing

**Both units arrive on connection 2. Channel is the differentiator.**

| Channel | Unit | Group | Controls |
|---------|------|-------|----------|
| **CH 1** | BCR2000 #1 | All groups | VCO (Grp1), LFO (Grp2), fixed rows VCA/VCF/Tuning, buttons |
| **CH 2** | BCR2000 #2 | — | EFX1 + EFX2 |

Both units use the same BC Manager preset template, differing only in channel. Routing is by CC number alone within each channel — no mode state needed. Encoder group switching on BCR2000 #1 changes which CC range the top-row encoders emit (Grp1: CC1–8/CC33–40 for VCO; Grp2: CC9–16/CC41–48 for LFO), all on CH1. CH1/2 avoids clash with SP-404 MK2 (CH6–10) and the TB-3 itself (CH2 for standard MIDI).

---

## Current Layout Sections (in TB3.tosc)

| Section | Status | Notes |
|---------|--------|-------|
| vco_group | Complete | 8 encoders, CCs 1–8 (CH6), SW push CCs 9–14 |
| lfo_group | Complete | 8 encoders (Dope Robot order), CCs 1–8 (CH3), BPM SYNC push CC9, RETRIGGER push CC10 |
| vcf_group | Layout done | Scripts TBD (Phase 2) |
| vca_group | Layout done | Scripts TBD (Phase 2) |
| tuning_group | Layout done | CCs 41–44 (16-bit); CC44 global tuning addr TBD |
| dist_group | Layout done | Scripts TBD (Phase 3) |
| extras_section | Layout done | 3 buttons toggle popups (portamento, ring mod, cross mod) |
| portamento_group | Popup done | TouchOSC-only; scripts TBD (Phase 2) |
| ring_mod_group | Popup done | TouchOSC-only; scripts TBD (Phase 2) |
| cross_mod_group | Popup done | TouchOSC-only; scripts TBD (Phase 2) |
| efx1_section | Layout done | 10-button chooser grid; scripts TBD (Phase 4) |
| efx2_section | Layout done | 9-button chooser grid; scripts TBD (Phase 4) |

**Naming issues still outstanding in TB3.tosc XML:**
- Second `vca_group` (the tuning section) → should be renamed `tuning_group`
- `level_enc` in vco_group → rename to `patch_volume_enc`
- `tuning_enc` tag has `cc:43` (duplicate of `ring_sin_tuning_enc`) → fix to `cc:44,ch:bcr1`
- `porta_time_enc` still has old BCR CC tag → clear it (portamento is TouchOSC-only)
- `porta_mode_button` still has old BCR CC tag → clear it

---

## Architecture

### SysEx Protocol

```
F0 41 10 00 00 7B 12  [a1 a2 a3 a4]  [data...]  [checksum]  F7
```
- **Checksum:** `(0x100 - (sum_of_all_addr_and_data_bytes % 256)) % 128`
- **7-bit params:** single data byte `0x00`–`0x7F`
- **16-bit params** (VCF cutoff, resonance, env depth, tuning): MSB = `value // 16`, LSB = `value % 16`
- **Signed params** (LFO depths, VCO/VCF LFO depth): offset-encoded — raw 64 = zero, 0 = −64, 127 = +63

### Build Pipeline

`tools/toscbuild.py build tb-3` — injects Lua scripts into TB3.tosc per `toscbuild.json` mappings.

Current injections: `root.lua` (includes `bcr_map.lua`) into root node; `pointer.lua` into all 79+ BOX nodes named `pointer`.

### Key File Locations

```
tb-3/
  TB3.tosc                  — main layout (user edits in TouchOSC app)
  toscbuild.json            — build manifest + scaffold definition
  lua/
    root.lua                — SysEx helpers, BCR routing, popup/EFX notify handling
    bcr_map.lua             — CC→SysEx address tables for both BCR2000 units
    pointer.lua             — build-injected into all 'pointer' BOX nodes
  bcr2000/
    bcr2000-1-tone-dist.md  — BCR2000 #1 CC assignment reference
    bcr2000-2-efx.md        — BCR2000 #2 CC assignment reference
  plans/
    tb3-layout-plan.md      — this file
  resources/
    sysex-examples/         — 4 patch dump files (422 bytes each, 11 SysEx messages)
```

---

## Phased Delivery

### ✅ Phase 0 — BCR2000 Mapping Tables

BCR2000 CC assignment tables created:
- `bcr2000-1-tone-dist.md` — VCO/LFO dual-mode Row 0, Rows 1–3, distortion buttons
- `bcr2000-2-efx.md` — EFX1/EFX2 parameter slots, type select, SW buttons, per-effect button maps

### ✅ Phase 1 — Foundation + Core Synthesis

Completed:
- `toscbuild.json` with scaffold layout + build mappings
- `root.lua`: SysEx helpers, BCR routing (CH3/CH6/CH7), distortion state, popup toggle, EFX chooser notify
- `bcr_map.lua`: full CC→SysEx tables for BCR1 (VCO + LFO + Dist + VCF + VCA + Tuning) and BCR2 (EFX)
- `pointer.lua`: build-injected drag/double-tap-reset overlay for all encoder groups
- TB3.tosc scaffolded, then extensively reworked in TouchOSC app by user
- lfo_group added with Dope Robot ordering and BPM SYNC/RETRIGGER push functions
- BCR1 LFO group uses CH3 for stateless channel-based routing

### Phase 1.5 — Patch Receive + Map Validation (NEW — do this first)

**Rationale:** A single patch dump exercises *every* SysEx address at once. By
decoding a dump and comparing against the Dope Robot Ctrlr panel (load the same
`.syx` in both), we validate the entire address map — offsets, 16-bit packing,
signed centers — *before* writing any send-side scripts. The address registry
this produces is the single source of truth that later drives both send and the
Phase 5 parameter-assign feature, so the work is foundational, not throwaway.

**Done:**
- `tools/decode_patch.py` — offline decoder for the 422-byte dump (11 blocks).
  Decodes LFO/Tuning/XMod/RingMod/VCO/VCF/VCA/Dist/ParamAssign by name; EFX1/EFX2
  dumped as raw indexed bytes (type-dependent). All 4 sample dumps checksum-OK.

**Validated against Dope Robot panel (Starter Bass Reso 2, 2026-06-05):**
Near-total match across all three panel pages — VCO/VCF/VCA/LFO/Dist/RingMod
values all identical. Resolutions:
- **LFO depths (VCO/VCF/VCA): center 64 CONFIRMED.** Panel VCF LFO MOD = 63 ↔
  raw 127; VCA/VCO LFO MOD = 0 ↔ raw 64. Decoder `s7` (raw−64) is correct.
- **CV OFFSET tuning: center 128 CONFIRMED, NOT 64** (my earlier guess was
  wrong). Panel SQR −64 ↔ raw 64 (exact); SAW/RING within ±2 (panel rounding).
  Decoder now uses `s16` (raw−128). Panel's 4th "TUNING" knob (=62) is the
  separate **global tune (CC104)**, not in this block.
- **DIST BOTTOM/TONE: display RAW 0–100** (panel shows 59 / 25 raw, not signed
  ±50). Decoder reverted to `u7`. Layout encoders should show raw 0–100 to match.
- **ACCENT (`14 0E`): CONFIRMED** = 5 ↔ panel VCF ACCENT = 5.
- **VCO RING LEVEL (`08 07`) = RING MOD "LEVEL"** on panel (=79). Same byte,
  different section label — value matches.

**Still open:**
- **BENDER RANGE (`14 03`):** decoder reads raw **23** (0x17), panel shows
  **17**. Mapping unresolved (note the hex/decimal coincidence). Offsets around
  it all validate (PORTA SW/TIME/MODE match panel exactly), so it IS at `14 03`.
  Need a second patch with a different bender value, or a hardware test, to
  derive the scaling. Store/recall raw for now.
- **Global TUNING (CC104):** panel shows 62; not located in the dump. Likely a
  device-global setting (not restorable from patch). Confirm it's absent.
- **PARAM ID assignments (`14 04`–`14 0B`):** decode to 16-bit IDs (74/69/56/58);
  not shown on the panel pages provided. Build the spec's `(*1)` ID→name table
  for the Phase 5 assign UI.

#### OSC patch-restore as test harness (folded into Phase 1.5)

Embed an OSC receiver in the layout that accepts patch data and feeds the **same
parse path** as MIDI receive. This doubles as the Phase 5 restore-from-backup
feature *and* a fast test loop (push a `.syx` from the Python app over OSC, watch
faders populate — no TB-3 or MIDI round-trip needed).

**Single-parser architecture (critical):**
- One `parseBlock(addrBytes, dataBytes)` routine drives fader/label updates.
- `onReceiveMIDI` accumulates each complete `F0…F7` SysEx message → `parseBlock`.
- `onReceiveOSC` reconstructs the **identical raw bytes** from the OSC payload →
  same `parseBlock`. Because both entry points hand over raw SysEx bytes, the
  formats are equal by construction.
- Python app: read `.syx`, split into the 11 block messages, send each over OSC
  (e.g. `/tb3/patch` with the raw bytes). TODO: confirm TouchOSC OSC arg
  encoding (blob vs int-array vs hex string) and that MIDI-received SysEx is
  delivered whole (per message) by `onReceiveMIDI`.

**Remaining:**
- Master parameter **registry** (addr → {param name, decode rule, target encoder
  node name}) — keyed so it serves parse-in, send-out, and assign lookup.
- `patch_manager.lua`: parse incoming dump → `setValue` on each encoder/fader via
  the registry; request-dump button (Roland data-request SysEx).
- EFX1/EFX2 per-type slot decoding (deferred until Phase 4 effect maps are firm).

### Phase 2 — LFO + Modulation Scripts

**Goal:** Encoder groups in the layout sending correct SysEx. Popup panels working.

**Deliverables:**
- Per-encoder build-injected scripts for: vcf_group, vca_group, lfo_group, tuning_group
- Popup panel scripts: portamento (SW/TIME/MODE), ring_mod_group, cross_mod_group
- Each script reads its `tag` (CC + channel) and calls `tb3Send7bit` / `tb3Send16bit` from root
- Display label updates (value_label) for signed params, scaled params, and 16-bit params

**SysEx addresses:**
- VCF: `10 00 0A 00`–`10 00 0A 0A`
- VCA: `10 00 0C 00`–`10 00 0C 04`
- LFO: `10 00 00 00`–`10 00 00 0C`
- Tuning (CV offset): `10 00 02 00`–`10 00 02 05`; CC44 global tuning addr TBD
- Portamento: `10 00 14 00`–`10 00 14 02`
- Ring Mod: `10 00 06 xx`
- Cross Mod: `10 00 04 xx`

### Phase 3 — Distortion

**Goal:** Full distortion section sending correct SysEx. BCR TYPE ↑/↓ buttons working.

Distortion type state machine already in `root.lua` (types 0–24, named array). Remaining work:
- Fader scripts for dist_group encoders (DRIVE/BOTTOM/TONE/EFFECT LEVEL/DRY LEVEL)
- DIST ON/OFF and DIST COLOR button scripts
- Connect dist_group faders to root.lua via notify or build-injected scripts

### Phase 4 — Effects (EFX1 + EFX2)

**Goal:** Context-sensitive 12-slot parameter display for each effect chain. BCR2 wired up.

**Deliverables:**
- `efx_section.lua`: handles type_cc (rotate), btn_press (B1=SW, B2+=effect-specific), type_set; remaps slot labels/addresses on type change; hides unused slots
- `efx_control.lua`: build-injected into each of the 12 slot encoder nodes — reads current address/range from parent tag, sends SysEx
- Per-effect button handling (BPM SYNC, type selects, mode toggles) per `bcr2000-2-efx.md`
- SW toggling on `btn_press = 1` (B1/CC31 for EFX1, B1/CC61 for EFX2)

**BCR2 EFX design (current):**
- SW on B1 (CC31) EFX1 and B1 (CC61) EFX2 — physical buttons 1 and 5 across the 8-button row
- Encoder push (CC2/CC6) spare
- TR TYPE: encoder slot S03 (range 0–5)
- PH TYPE: 4 dedicated buttons B4–B7 (4Stage/8Stage/12Stage/Bi-Phase)

### Phase 5 — Patch Management, Parameter Assign + Python Qt App

**Goal:** Full preset workflow — dump/restore patches to/from hardware; parameter assign UI; desktop app for backup.

**TouchOSC side (`patch_manager.lua`):**
- Send Roland SysEx all-data request to TB-3
- Parse incoming 422-byte dump → populate faders via setValue
- Store current state as JSON in element tag; export/import via OSC

**Python Qt app (`tb-3/preset-manager/`):**
- Modelled on `sp404-mk2/preset-manager/python/`
- Receives OSC from TouchOSC, stores as JSON patch files
- Sends OSC back to layout for recall

---

#### Parameter Assign UI (Phase 5)

Assigns synthesis parameters to the TB-3's four hardware controls: EFFECT knob, PAD X, PAD Y, PAD Z. SysEx: `10 00 14 04–0B` (four 16-bit parameter IDs).

**UX flow (reverse of Ctrlr panel):**
1. User clicks one of four assign buttons ([EFFECT] / [PAD X] / [PAD Y] / [PAD Z]) in a dedicated assign section of the layout
2. Layout enters assign mode for that slot; button highlights; a status label reads e.g. "Tap encoder to assign to EFFECT knob"
3. User can drag any encoder to audition what they're about to assign (normal fader behaviour still works)
4. User taps any encoder → that parameter gets assigned to the selected slot; mode exits; button un-highlights

**Architecture — root-centric (no param IDs in encoder tags):**

`root.lua` owns all param ID knowledge. `pointer.lua` stays simple.

```lua
-- pointer.lua: single extra branch at PointerState.END
local as = findByName("assign_state")
if as and as.tag ~= "" then
    findByName("root"):notify("encoder_tapped", self.parent.name)
    return   -- skip double-tap logic
end
-- else: normal double-tap behaviour

-- root.lua: central lookup table (16-bit param IDs from spec §*1 table)
local PARAM_ID = {
    lfo_rate_enc        = {0x00, 0x00},
    lfo_cv_offset_enc   = {0x00, 0x06},
    lfo_delay_enc       = {0x00, 0x01},
    lfo_wave_tri_enc    = {0x00, 0x04},
    lfo_wave_saw_enc    = {0x00, 0x02},
    lfo_wave_sqr_enc    = {0x00, 0x03},
    lfo_wave_sin_enc    = {0x00, 0x05},
    lfo_wave_sh_enc     = {0x00, 0x07},
    -- VCO depths, VCF, VCA, etc. — all encoders that are XY-assignable
}
-- onReceiveNotify "encoder_tapped":
--   look up PARAM_ID[value], send assignment SysEx, clear assign_state.tag
```

**Shared state:** a hidden LABEL element named `assign_state` whose `tag` stores `""` | `"effect"` | `"pad_x"` | `"pad_y"` | `"pad_z"`. Root writes it; pointer.lua reads it. No cross-script function calls or injected tags needed.

**Why root-centric is simpler than encoder-centric:**
- `pointer.lua` needs zero knowledge of param IDs — nothing extra injected at build time
- The full assignment map is auditable and editable in one place (`root.lua`)
- Encoders with no assignable parameter are handled by simply omitting them from `PARAM_ID` — the tap is silently ignored
- The same table can drive a "currently assigned to:" display label

**Layout additions needed:**
- 4 assign mode buttons (EFFECT / PAD X / PAD Y / PAD Z) with highlight state
- `assign_state` hidden LABEL element
- Status label showing current assign mode and currently-assigned parameter name
- BENDER RANGE encoder (`10 00 14 03`, 0–17 semitones) placed next to portamento section

---

## Verification Checklist (per phase)

1. `python3 tools/toscbuild.py build tb-3` exits clean
2. Load `TB3.tosc` in TouchOSC
3. Move a fader → MIDI monitor shows correct SysEx frame, address, checksum
4. BCR2000 encoder turn → fader moves in TouchOSC AND correct SysEx sent
5. Phase 5: DUMP REQUEST button → TB-3 responds, faders populate

**Checksum sanity:** LFO RATE `10 00 00 00`, value `0x40` → checksum = `(0x100 − (0x10+0x00+0x00+0x00+0x40) % 256) % 128 = (0x100 − 0x50) % 128 = 48`.

---

## Open Items

- **GLOBAL TUNING (CC44)**: Resolved. BCR1 CC44 sends plain MIDI CC 104 to TB-3 (CH2, connection 6) via special handler in `root.lua` — not SysEx. Device-global setting, not in patch dumps. `bcr_map.lua` updated with note; `tuning_enc` script (Phase 2) should do the same.
- **PORTAMENTO SW**: Missing from layout. The `porta_time_enc` group has a `sw_button` which is the on/off switch (`10 00 14 00`). Label convention: static label ("PORTA"), color encodes state (bright = on, dim = off) — consistent with VCO source switches. No text switching.
- **BENDER RANGE**: Now in layout as `pitch_bend_group` / `pitch_bend_range_enc` (SysEx `10 00 14 03`, range 0–17 semitones). Script needed in Phase 2. Not on BCR2000 — TouchOSC-only.
- **BCR2000 #1 physical programming**: All groups on CH1 (same BC Manager template as BCR2).
- **BCR2000 #2 physical programming**: CH2 (same template, different channel).
- **TB3.tosc naming fixes**: see "Naming issues still outstanding" above
- **Popup scripts**: Phase 2 work
- **EFX type numbering in `efx_section.lua`**: EFX2 type 9 = RV; EFX1 type 9 = PS; EFX1 type 10 = EQ (EFX2 has no PS, no type 10)
