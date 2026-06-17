# TB-3 Remaining Features — To-Do Plan

> **Created 2026-06-09. Last updated 2026-06-14.** Phases 0–5 of the original plan are complete. Features 1 and 4 are now also complete (see status below). This document now tracks only the two remaining feature areas.

---

## Context

The TB-3 layout is functionally complete for synthesis control. Five new capability areas remain:

1. Free up BCR1 encoder slots by removing on-panel-knob duplicates, use freed slots to control the morph fader from hardware.
2. Pass Launchkey MK4 notes/pitchbend/mod through to the TB-3 and map its 7 encoders to key synth CCs.
3. Integrate the Launchpad Pro as a physical preset grid controller (store, recall, delete, grab, morph) with LED feedback — same unit as SP-404, used per layout.
4. Improve the preset manager: Python app pulls patches (remove TouchOSC button), restructure UI with banks→patches hierarchy, add patch naming, display recalled bank + preset name via two on-screen labels.
5. Full documentation pass.

---

## Feature 1 — BCR1 Layout Restructure + Morph Fader  ✅ COMPLETE

**Implemented.** All code changes described below are in place as of 2026-06-14: `panel_controls_group` key renames in `enc_map.lua`, `dist_type_enc` special case in `enc_moved`, `morph_enc` replaces `morph_amount_fader`, `send_button.lua` injected, `preset_name_label` combined label with `updatePatchInfoLabel()`, `currentBankName` state variable. Verified in `root.lua` and `toscbuild.json`.

<details>
<summary>Original implementation notes (kept for reference)</summary>

**Layout changes already made by user.** Code changes needed:

### What changed in the layout

1. **`panel_controls_group`** — vcf_cutoff_enc, vcf_resonance_enc, accent_level_enc moved here from vcf_group. Still send SysEx to TB-3 but are no longer BCR-controllable.
2. **`presets_group`** — preset_grid + delete_button + grab_mode_button. `delete_all_presets_button` removed. `bank_name_label` removed; `preset_name_label` is the single combined label.
3. **`send_button`** — new root-level button; sends current TouchOSC state to TB-3.
4. **`morph_group` / `morph_enc`** — patch_volume_enc moved to vca_group; morph_enc replaces the separate morph_button + morph_amount_fader. morph_enc children: `morph_button` (BUTTON, push = toggle mode) and `control_fader` (RADIAL, rotate = amount).
5. **`dist_type_enc`** — replaces dist_type_up / dist_type_dn buttons. Standard enc group (control_fader + value_label + pointer). `distortion_section_label` should just say "DISTORTION" (no type suffix — type shown in dist_type_enc value_label).
6. **`vcf_group`** — cutoff/resonance/accent moved out; still contains vcf_env_depth_enc, vcf_key_follow_enc, ADSR, and LFO MOD. Those ENC_SEND_MAP keys are unchanged.

### BCR CC mapping changes

| CC | Before | After |
|---|---|---|
| 72 | DIST TYPE ↑ (button) | freed |
| 80 | DIST TYPE ↓ (button) | freed |
| 89 | VCF CUTOFF | freed (panel control) |
| 90 | VCF RESONANCE | freed (panel control) |
| 95 | ACCENT LEVEL | **MORPH AMOUNT** |

### Code changes

#### `lua/bcr_map.lua`
- Remove `[89]`, `[90]`, `[95]` from `BCR1_MAP` (addr-based entries). `ADDR_TO_BCR1_CC` is auto-built so no manual change needed there.
- Remove the two comment lines for CC 72, 80 (dist type buttons).
- Add `[95] = { morph = true }` sentinel (no `addr` field → excluded from `ADDR_TO_BCR1_CC`, handled manually in `handleBCR1` and `syncBCR1`).

#### `lua/enc_map.lua`
Four encoder keys must change to match new parent group names (control_fader.lua sends `self.parent.parent.name`):

| Old key | New key |
|---|---|
| `vcf_group,vcf_cutoff_enc` | `panel_controls_group,vcf_cutoff_enc` |
| `vcf_group,vcf_resonance_enc` | `panel_controls_group,vcf_resonance_enc` |
| `vcf_group,accent_level_enc` | `panel_controls_group,accent_level_enc` |
| `vco_group,patch_volume_enc` | `vca_group,patch_volume_enc` |

Add dist_type_enc entry (populates `ADDR_TO_ENC` so patch-receive can set the fader; actual SysEx send is via special case in `enc_moved`):
```lua
["dist_group,dist_type_enc"] = { addr={0x10,0x00,0x0E,0x01}, bits=7, max=24 },
```
(`DIST_NUM_TYPES = 25`, range 0–24, declared in patch_manager.lua.)

#### `lua/patch_manager.lua` — `parseBlock` dist type display
Replace `distortion_section_label` update (~line 512) with dist_type_enc fader + label update:
```lua
distType = raw
local encGrp = root:findByName("dist_type_enc", true)
if encGrp then
  local fader = encGrp.children["control_fader"]
  if fader then fader.values.x = DIST_NUM_TYPES > 1 and (distType / (DIST_NUM_TYPES - 1)) or 0 end
  local lbl = encGrp.children["value_label"]
  if lbl then lbl.values.text = DIST_TYPE_NAMES[distType + 1] or tostring(distType) end
end
```
Setting `fader.values.x` triggers `enc_moved` → the dist_type special case in root.lua, but the `typeIdx ~= distType` guard prevents a redundant SysEx send.

Also update `PARAM_ID_MAP` (also in patch_manager.lua) for the four moved encoders (same key renames as ENC_SEND_MAP above).

#### `lua/root.lua` — targeted changes

**A. Remove `sendDistType()` function** (~lines 367–376). Logic moves into enc_moved special case.

**B. `handleBCR1()` — remove CC 72/80 state machines (~lines 413–430). Add CC 95 → morph:**
```lua
if cc == 95 then
  morphAmount = ccVal / 127
  applyMorph()
  local enc = root:findByName("morph_enc", true)
  if enc then
    local fader = enc.children["control_fader"]
    if fader then fader.values.x = morphAmount end
  end
  return
end
```

**C. `syncBCR1()` — add morph feedback at end of function:**
```lua
sendMIDI({0xB0, 95, math.floor(morphAmount * 127 + 0.5)}, BCR_CONNECTION)
```

**D. `enc_moved` handler — add two special cases:**

`dist_group,dist_type_enc`:
```lua
if section == "dist_group" and enc == "dist_type_enc" then
  local typeIdx = math.min(math.floor(x * (DIST_NUM_TYPES-1) + 0.5), DIST_NUM_TYPES-1)
  if typeIdx ~= distType then
    distType = typeIdx
    local a = DIST_TYPE_ADDR
    tb3Send7bit(a[1],a[2],a[3],a[4], distType)
    local blk = rawSysexBlocks[string.format("%02X%02X%02X00",a[1],a[2],a[3])]
    if blk then blk.data[a[4]+1] = distType end
  end
  local encGrp = root:findByName("dist_type_enc", true)
  if encGrp then
    local lbl = encGrp.children["value_label"]
    if lbl then lbl.values.text = DIST_TYPE_NAMES[distType+1] or tostring(distType) end
  end
  return
end
```

`morph_group,morph_enc` (replaces `morph_amount_changed` handler):
```lua
if section == "morph_group" and enc == "morph_enc" then
  morphAmount = x
  applyMorph()
  return
end
```

**E. Remove `morph_amount_changed` handler** (~lines 1358–1360). Covered by the enc_moved case above.

**F. Replace all `morph_amount_fader` node lookups** (~line 1315 and elsewhere) with morph_enc child lookup:
```lua
local morphEnc = root:findByName("morph_enc", true)
local fader    = morphEnc and morphEnc.children["control_fader"]
```

**G. Combined `preset_name_label` — replace dual-label updates with single helper.**

Add near other state variables:
```lua
local currentPresetName = ""
```

Add helper function:
```lua
local function updatePatchInfoLabel()
  local lbl = root:findByName("preset_name_label", true)
  if not lbl then return end
  local parts = {}
  if currentBankName   ~= "" then parts[#parts+1] = "Bank: "   .. currentBankName   end
  if currentPresetName ~= "" then parts[#parts+1] = "Preset: " .. currentPresetName end
  lbl.values.text = table.concat(parts, "  ")
end
```

Replace the 4 write callsites (slot recall ~1334, patch_clear_all ~1366, /tb3/patchgrid/restore ~1421) to use `currentPresetName` and call `updatePatchInfoLabel()`.

**H. Add `send_patch_to_device` handler.** New helper function (same pattern as `snapshotCurrentPatch` but sends raw MIDI instead of building JSON):
```lua
local function sendCurrentPatchToDevice()
  local efx1Node = root:findByName("efx1_section", true)
  local efx2Node = root:findByName("efx2_section", true)
  local efx1Data = efx1Node and json.toTable(efx1Node.tag)
  local efx2Data = efx2Node and json.toTable(efx2Node.tag)
  for _, k in ipairs(EXPORT_BLOCK_ORDER) do
    local addr, data
    if k == EFX1_KEY then
      if efx1Data and #efx1Data > 0 then addr=EFX1_ADDR; data=efx1Data
      elseif rawSysexBlocks[k] then addr=rawSysexBlocks[k].addr; data=rawSysexBlocks[k].data end
    elseif k == EFX2_KEY then
      if efx2Data and #efx2Data > 0 then addr=EFX2_ADDR; data=efx2Data
      elseif rawSysexBlocks[k] then addr=rawSysexBlocks[k].addr; data=rawSysexBlocks[k].data end
    else
      if rawSysexBlocks[k] then addr=rawSysexBlocks[k].addr; data=rawSysexBlocks[k].data end
    end
    if addr and data then sendDT1(addr, data) end
  end
end
```

In `onReceiveNotify`:
```lua
if key == "send_patch_to_device" then
  sendCurrentPatchToDevice()
  return
end
```

**I. `TB3_CC_DISPLAY_MAP` — update group prefixes for moved encoders (cosmetic):**
```lua
[16] = "panel_controls_group,accent_level_enc",
[71] = "panel_controls_group,vcf_resonance_enc",
[74] = "panel_controls_group,vcf_cutoff_enc",
```

#### `lua/send_button.lua` — new file
Mirror of `receive_button.lua`:
```lua
function onValueChanged(key)
  if key ~= "x" then return end
  if self.values.x < 0.5 then return end
  self.parent:notify("send_patch_to_device", 1)
end
```

#### `toscbuild.json`

| Action | Entry |
|---|---|
| Remove | `delete_all_presets_button.lua` mapping |
| Remove | `dist_type_button.lua` → `["dist_type_up","dist_type_dn"]` |
| Remove | `morph_amount_fader.lua` → `"morph_amount_fader"` (node gone) |
| Add | `send_button.lua` → `node_name: "send_button"` |

`morph_button.lua` → `"morph_button"` **stays** — node still exists inside morph_enc.

### Verification
1. `python3 tools/toscbuild.py build tb-3` — zero errors
2. Load in TouchOSC, Sync From TB-3: panel encoders (cutoff/resonance/accent) update; dist_type_enc shows type name; patch_volume in vca_group works
3. Move dist_type_enc — TB-3 distortion type changes; value_label shows name from DIST_TYPE_NAMES
4. BCR NRPN 8 rotary — morphAmount changes
5. send_button — change a fader, restart TB-3, press Send → TB-3 updates
6. Preset recall — `preset_name_label` shows "Bank: X  Preset: Y"

</details>

---

## Feature 4 — Preset Manager Improvements  ✅ COMPLETE

**Implemented as of 2026-06-14.** All four sub-tasks are in place:

- **4a:** `save_to_library_btn.lua` removed from `toscbuild.json`; `/tb3/request_patch_export` OSC handler live in `root.lua`; Python "Pull Patch" button exists.
- **4b:** Python app restructured to two-pane layout (`bank_list` left, `slot_list` right) with `QSplitter`.
- **4c:** Bank JSON v2 format with per-slot `name` field; `QInputDialog` rename; backward-compat v1 loader.
- **4d:** `currentBankName`, `updatePatchInfoLabel()`, and `preset_name_label` in `root.lua`; label cleared on `patch_clear_all`.

---

## Feature 2 — Launchkey MK4 Passthrough  ✅ COMPLETE

**Implemented 2026-06-14. Bug fixed 2026-06-15.** Notes/pitchbend pass through. 7 encoders (CC 74/71/16/17/12/13/104) + morph (CC 105) + mod wheel (CC 1) are mapped. LED ring feedback working via `syncLaunchkey()` and per-change mirrors in `enc_moved`. Assign-slot CCs (17/12/13) update correctly for both regular encoder params and EFX slot params via `getEfxSlotParamId` / `getFaderXForParamId`. Morph snap-back fixed (removed per-step CC 105 echo; `syncTimer` debounced to 40 ticks / ~667ms).

**Mod wheel fix (2026-06-15):** Added `[1] = { assignCC=1 }` to `LAUNCHKEY_CC_MAP`. CC 1 was falling into the unmapped-CC `else` branch (forwarded to TB-3 but no UI update). Now routes through the `assignCC` branch which calls `handleTB3CC(1, ccVal)` → `updateUIForParamId(assignedParamIds["xy_mod"], ccVal)`. `syncLaunchkey` correctly skips CC 1 (not in `LAUNCHKEY_ASSIGN_CC_REVERSE`, so no erroneous feedback to the physical mod wheel).

### Launchkey encoder CC assignments
| Encoder | CC | TB-3 parameter |
|---------|-----|----------------|
| 1 | 74 | VCF Cutoff |
| 2 | 71 | VCF Resonance |
| 3 | 16 | Accent Level |
| 4 | 17 | Effect Knob (assign control) |
| 5 | 12 | XY PAD X (assign control) |
| 6 | 13 | XY PAD Y (assign control) |
| 7 | 104 | Global Tuning |

All 7 are already in `TB3_CC_DISPLAY_MAP` or handled by existing CC receive logic (CC 17, 12, 13 via `ASSIGN_CC_SLOTS`; CC 104 via the global tuning special case). So the UI update path already exists — we just need to route Launchkey input through it.

### Tasks
- [ ] **root.lua** — Add `LAUNCHKEY_CONNECTION = {false,false,false,true}` (connection 4 — confirmed) and `LAUNCHKEY_CHANNEL = 1` (Launchkey sends on ch 1; translate to `TB3_MIDI_CHANNEL` when forwarding).
- [ ] **root.lua `onReceiveMIDI()`** — Add branch for `LAUNCHKEY_CONNECTION`:
  - Note on (0x90) / Note off (0x80): translate channel to `TB3_MIDI_CHANNEL`, forward to `TB3_CONNECTION`.
  - Pitch bend (0xE0): translate channel, forward to `TB3_CONNECTION`.
  - CC (0xB0): for each of the 7 encoder CCs, forward to `TB3_CONNECTION` on `TB3_MIDI_CHANNEL` **and** call `handleTB3CC(cc, ccVal)` to update the on-screen fader + labels. CC 104 needs the global tuning display update path (same as the BCR1 branch).
- [ ] No SysEx logic needed. The TB-3 hardware responds to all 7 CCs directly.
- [ ] **root.lua `syncLaunchkey()`** — After a patch receive (same call sites as `syncBCR1()`) and in `init()`, send the 7 encoder CCs (74, 71, 16, 17, 12, 13, 104) back to the Launchkey on `LAUNCHKEY_CONNECTION` with the current fader positions so its encoder LED rings stay in sync. Read positions from the same on-screen encoder nodes that `handleTB3CC` updates. CC 104 (global tuning) uses the tuning encoder fader value × 127.

---

## Feature 3 — Launchpad Pro Preset Control

**Goal:** Mirror the SP-404 MK2 Launchpad Pro integration. 16 pads control the 16 preset grid slots (store/recall/delete/grab/morph). Mode buttons select the active mode. LED feedback reflects slot state. Same physical Launchpad unit, used exclusively when TB-3 layout is loaded.

### Sub-tasks

#### 3a — Connection + programmer mode
- [ ] **root.lua** — Add `LAUNCHPAD_CONNECTION = {false,false,true}` (connection 3 — confirmed).
- [ ] **root.lua `init()`** — Send SysEx to enter Launchpad Pro Programmer mode (`F0 00 20 29 02 0E 0E 01 F7`). Blank all LEDs, then call `syncLaunchpadLEDs()`.

#### 3b — Pad → slot mapping
- [ ] Define `LAUNCHPAD_NOTE_CHANNEL = 10` (Programmer mode sends notes on MIDI ch 10, same as SP-404).
- [ ] Define `LAUNCHPAD_PAD_TO_SLOT` table: pads 81–88 (top row) = slots 1–8; pads 71–78 (second row) = slots 9–16. Matches the 8×2 TouchOSC preset grid layout exactly.
- [ ] Define `SLOT_TO_LAUNCHPAD_PAD` reverse table (built at load time).

#### 3c — Mode buttons (side column CCs, same as SP-404)
- [ ] Copy SP-404 side-column CC constants verbatim, trimmed to the three modes the TB-3 needs:
  - `DELETE_CC = 50` (side row 5 = Delete mode)
  - `GRAB_CC = 60` (side row 6 = Grab mode; SP-404 uses this as UNDO)
  - `MORPH_CC = 40` (side row 7 = Morph mode; SP-404 uses this as QUANTISE)
- [ ] Side-column buttons arrive as CC messages (not note-on) on `LAUNCHPAD_NOTE_CHANNEL`. Handle in the Launchpad CC branch of `onReceiveMIDI`.
- [ ] Pressing a mode CC: toggle the corresponding `patchGridMode` (reuse `handlePatchModeSet` extracted function). Update the mode button LED to confirm active state.

#### 3d — LED feedback helper
- [ ] `syncLaunchpadLEDs()` in root.lua: for each slot pad (81–88, 71–78), send RGB LED SysEx via the same helper pattern as SP-404's `sendLaunchpadLedRgb`:
  - Empty slot → off
  - Filled slot → white (dim)
  - Active morph target → amber
- [ ] Mode button LEDs: after each mode change, send LED update for DELETE_CC, GRAB_CC, MORPH_CC (active = lit colour, inactive = dim).
- [ ] Call `syncLaunchpadLEDs()` from: `setPatchGridSlots()`, `broadcastPatchMode()`, after `syncBCR1()`.

#### 3e — MIDI receive routing
- [ ] **root.lua `onReceiveMIDI()`** — Add branch for `LAUNCHPAD_CONNECTION`. Route by message type (ch 10):
  - Note-on (velocity > 0): pad in `LAUNCHPAD_PAD_TO_SLOT` → `handlePatchSlotPress(slotNum)`.
  - Note-off (velocity 0 or 0x80): pad in `LAUNCHPAD_PAD_TO_SLOT` → `handlePatchSlotRelease(slotNum)`.
  - Polyphonic aftertouch (0xA0): if `patchGridMode == "morph"` and the note maps to the active `morphTargetSlot`, set `morphAmount = pressure / 127` and call `applyMorph()`. This matches the SP-404 pattern — holding a pad and pressing harder drives the blend in real time.
  - CC: DELETE_CC / GRAB_CC / MORPH_CC → `handlePatchModeSet(modeStr)`.
- [ ] Refactor `patch_slot_pressed`, `patch_slot_released`, and `patch_mode_set` blocks in `onReceiveNotify` to delegate to extracted local functions `handlePatchSlotPress`, `handlePatchSlotRelease`, `handlePatchModeSet` (no behaviour change, avoids duplication).

---

## Feature 5 — Documentation Review  ✅ COMPLETE

**Updated 2026-06-16.** All documentation passes complete.

- [x] **plans/tb3-layout-plan.md** — No standalone plan file existed; tb3-remaining-features.md serves as the full history. No action needed.
- [x] **README.md** — Added Connections 3+4 to MIDI Setup table; added Launchkey MK4 section (encoder CC map, note/pitchbend passthrough, LED ring sync); added Launchpad Pro section (pad→slot mapping, control buttons, brightness profiles, LED colour scheme); updated Morph section (orange colour, hardware control via NRPN 8 and Launchpad CC 40).
- [x] **lua/README.md** — Added Connection constants table; added Launchpad Pro constants section; added Launchkey MK4 constants section; added `handlePatchSlotPress/Release`, `handlePatchModeSet`, `syncLaunchpadLEDs`, `syncLaunchkey`, `updatePatchInfoLabel` to key helpers table; updated slot colour table (grab → `E6E6E6FF`, morph → `FF7F00FF`).
- [x] **bcr2000/bcr2000-1-tone-dist.md** — Already reflects correct post-Feature-1 state: CC 89 = PATCH VOLUME, CC 95 = DIST BOTTOM, VCF CUTOFF/RESONANCE/ACCENT in NRPN-only section, NRPN 8 = MORPH AMOUNT. No changes needed.
- [x] **CLAUDE.md** — Added `LAUNCHPAD_CONNECTION` and `LAUNCHKEY_CONNECTION` (+ `LAUNCHKEY_CHANNEL`) to Connection / channel constants table.
- [x] **preset-manager/README.md** — Already reflects pull-based workflow, two-pane layout, patch naming, and OSC protocol. No changes needed.

---

## Feature 6 — Launchpad/preset UX parity with SP-404 (+ SP-404 grab fix)

**Created 2026-06-16. ✅ Implemented + hardware-tested 2026-06-16.** Feature 3
(Launchpad Pro preset control) is functionally complete; this was its hardware-feedback
follow-up, bringing the TB-3 Launchpad + on-screen preset grid in line with the SP-404,
porting the SP-404 brightness-profile (User button) feature, and fixing a latent SP-404
grab-from-Launchpad bug. Goal: one consistent preset-grid mental model across both
layouts and both control surfaces.

**Implementation notes (as built):**
- All TB-3 changes in `lua/root.lua` + `lua/preset_grid.lua`; SP-404 in `lua/root.lua`
  + `lua/preset_grid_manager.lua`. No `toscbuild.json` changes.
- **Two additions beyond the original plan:**
  - **Click (CC 70) → "sync from TB-3"**, lit **green** (`LP_SYNC`). Drives the on-screen
    `receive_button` (via `sync_group.children`) like the BCR1 sync button, so it flashes
    for visual feedback and its own handler calls `requestPatchDump()`.
  - **`init()` now blanks the full programmer-layout LED range (index 1–98)** — the first
    pass only cleared 10–89, leaving the top-row (Session/Device/User) and bottom-row
    (Record Arm/etc.) buttons lit when switching from the SP-404 layout.
- The "sync_to_controllers doesn't update the EFX BCR" report was a **hardware** issue
  (BCR operating modes had drifted); fixed by resetting BCR1→U4, BCR2→S3. No code change.

> **Model guidance:** implement with **Opus 4.8** (current model). This edits the
> load-bearing concatenated root chunk on *both* layouts, adds momentary-hold state
> machines, colour-scaling maths, and a behaviour-preserving SP-404 refactor —
> high-stakes, context-heavy Lua. Fast mode is fine; do **not** drop to Sonnet for this.

### Confirmed decisions
- **Morph colour** (shared SP-404 + TB-3 + Launchpad + Quantise button): **orange `FF7F00`**.
- **Grab-mode filled-preset colour**: **`E6E6E6`** (matches the grab button); a press in
  grab mode goes to **full white `FFFFFF`**. Empty stays grey `BFBFBF`; filled blue `4A90D9`.
- **Delete + Grab on the Launchpad**: **momentary hold** (held = active, release = off) —
  matches the SP-404 (`DELETE_CC` / `SHIFT_CC` are already momentary). Morph (Quantise
  CC 40) stays a **toggle**. On-screen delete/grab buttons stay toggles.

### Standard Launchpad control-button CC map (both layouts, ch 10)
| Button | CC | TB-3 role |
|--------|----|-----------|
| Quantise | 40 | Morph (toggle) |
| Delete | 50 | Delete (momentary hold) |
| Undo | 60 | disabled — LED dark (no defaults concept) |
| Click | 70 | Sync from TB-3 (green LED) — drives on-screen receive_button |
| Shift | 80 | Grab (momentary hold) |
| User | 98 | Brightness cycle (new) |

Change vs current TB-3 F3: grab CC 60→80; delete+grab momentary (not toggle); CC 60
no-op (dark); CC 70 = sync-from-TB-3 (green); CC 98 added.

### Part A — TB-3 (`lua/root.lua`, `lua/preset_grid.lua`, `lua/preset_grid_slot_btn.lua`)
- **A1/A4** — Replace `LAUNCHPAD_MODE_CC` with `LAUNCHPAD_HOLD_CC = {[50]="delete",[80]="grab"}`
  (momentary enter on val>0 / exit on val 0); CC 40 morph toggle; CC 98 User. Track
  `launchpadDeleteHeld`/`launchpadShiftHeld` so a release clears only its own mode;
  grab-exit restores any active `grabSnapshot`. CC 60 no-op + dark; CC 70 = sync from
  TB-3 (green `LP_SYNC`, drives the on-screen `receive_button`).
- **A2** — `preset_grid.lua` `MODE_COLORS`: morph `FF7F00FF`, grab `E6E6E6FF`, delete
  `E70000FF`; morph target gets a distinct full-bright orange. `syncLaunchpadLEDs` tints
  filled pads by mode (delete→red, grab→white, morph→orange, target→bright orange) +
  mode-button LEDs (40 orange / 50 red / 80 white; 60/70 dark).
- **A3** — Brighten-on-press both surfaces: `scaleHexColor(hex,factor)` (idle ~0.78 /
  press 1.0; grab special-cased `E6E6E6`→`FFFFFF`). Slot press/release visual relay via
  `back_N`; Launchpad `lightSlotPad(slot,pressed)` on note-on/off.
- **A5** — Port brightness profiles from `sp404-mk2/lua/launchpad_led.lua`
  (`very_dim/night/normal/day`, default `night`) into the TB-3 root chunk as locals;
  `launchpadRgb255`-equiv; CC 98 cycles + repaints; persist `root.tag.launchpadBrightnessProfile`
  (TB-3 `root.tag` is unused); load in `init()` before first `syncLaunchpadLEDs()`. Root
  chunk is at 94/200 top-level locals — ample headroom.

### Part B — SP-404 (`lua/root.lua`, `lua/preset_grid_manager.lua`)
- **B1** — Grab-from-Launchpad fix: `SHIFT_CC` handler (root.lua:585) never calls
  `setLaunchpadGrabMode` (only ever called with `false`). Add
  `setLaunchpadGrabMode(launchpadShiftHeld)` there, mirroring `DELETE_CC` →
  `setLaunchpadDeleteMode`. Verify `toggleGrabMode(false)` restores on early Shift release.
  Needs on-hardware verification.
- **B2** — Morph colour `FF44CCFF` → `FF7F00FF` (orange) in `preset_grid_manager.lua`
  (`MORPH_SELECT` / `BUTTON_STATE_COLORS.MORPH_SELECT`) and the Launchpad morph RGB site.
  Orange is clear of `LAUNCHPAD_BUS_RGB` and `FALLBACK_BUS_ACCENT_HEX`.
- **B3** — SP-404 grab pad colour stays per-bus (deliberate; buses carry meaning there).

No `toscbuild.json` changes (all into existing nodes). TB-3 grab button colour
(`E6E6E6FF`) already changed in the layout by the user.

### Verification
1. `build tb-3` + `build sp404-mk2` zero errors; luac-check the TB-3 root chunk.
2. TB-3 hardware: colours match screen↔Launchpad (morph orange, grab grey→white);
   press brightens both (grab press→full white); morph target stands out; **hold** Shift
   → grab, **hold** Delete → delete; morph toggles; Click/Undo dark no-ops; User cycles
   brightness and persists across reload.
3. SP-404 hardware: hold Shift + tap stored preset → preview, release → restore;
   grab_mode_button lights while held; morph colour no longer clashes with buses.

---

## Suggested Implementation Order

| Step | Feature | Prereq | Status |
|------|---------|--------|--------|
| ~~1~~ | ~~F4a + F4b + F4c~~ | — | ✅ Done |
| ~~2~~ | ~~F1 (BCR + morph + send)~~ | — | ✅ Done |
| ~~3~~ | ~~F4d (name labels in TouchOSC)~~ | — | ✅ Done |
| ~~4~~ | ~~F2 (Launchkey passthrough)~~ | — | ✅ Done |
| 5 | F3 (Launchpad Pro) | `LAUNCHPAD_CONNECTION = {false,false,true}` (conn 3) — confirmed 2026-06-14 | ✅ Functionally complete (hardware-tested; see F6 follow-ups) |
| 6 | F6 (Launchpad/preset SP-404 parity + SP-404 grab fix) | F3 complete | ✅ Implemented + hardware-tested 2026-06-16 |
| 7 | F5 (docs) | All above complete | ✅ Done |
