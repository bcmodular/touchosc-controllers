# TB-3 TouchOSC Controller — Agent Guide

## Navigation rules

- **Never read `.tosc` files directly** — they are zlib-compressed XML blobs that will burn your context window for zero benefit. Use `python3 tools/toscbuild.py tree tb-3/TB3.tosc` to inspect the node hierarchy.
- **Ignore `backups/` and `resources/`** — binary build artifacts. `backups/` holds one `.tosc.bak` per build (133+ files). Neither directory contains source files.
- **Source of truth**: `lua/*.lua` + `toscbuild.json`. The `.tosc` file is the build artifact.

## Directory layout

```
tb-3/
  TB3.tosc              — build output (do not edit directly)
  toscbuild.json        — build manifest: script → node mappings
  lua/                  — Lua source (see script table below)
  preset-manager/       — PyQt5 desktop app for patch backup/restore
  tools/                — layout maintenance scripts (see below)
  plans/                — design docs and this remediation plan
  backups/              — build-tool backups (gitignored)
  resources/            — binary assets (gitignored)
  screenshots/          — layout reference images
```

## Build

```bash
python3 tools/toscbuild.py build tb-3          # inject Lua into TB3.tosc
python3 tools/toscbuild.py build tb-3 --dry-run
python3 tools/toscbuild.py tree tb-3/TB3.tosc  # inspect node hierarchy
python3 tools/toscbuild.py dev tb-3            # watch mode (macOS)
```

## Root chunk — include order contract

`toscbuild.json` injects four files into the root node as a single concatenated Lua chunk, **in this exact order**:

1. `bcr_map.lua`
2. `patch_manager.lua`
3. `enc_map.lua`
4. `root.lua`

Variables declared `local` at the top level in earlier files are visible to later files because they share one chunk scope. **This order is load-bearing.** Key cross-file dependencies:

| Variable / function | Declared in | Used in |
|---------------------|-------------|---------|
| `BCR1_MAP`, `BCR1_NRPN_MAP`, `ADDR_TO_BCR1_NRPN`, `efx1SlotIndex` etc. | `bcr_map.lua` | `root.lua` |
| `distType`, `DIST_TYPE_NAMES`, `DIST_NUM_TYPES` | `patch_manager.lua` | `root.lua` |
| `parseBlock`, `updateAssignDisplay` | `patch_manager.lua` | `root.lua` |
| `PARAM_ID_MAP`, `SW_PARAM_ID_MAP` | `patch_manager.lua` | `root.lua` |
| `ENC_SEND_MAP`, `SW_SEND_MAP`, `ADDR_TO_ENC`, `ADDR_TO_SW` | `enc_map.lua` | `root.lua` |
| `EFX_SLOT_OFFSETS_SHARED`, `EFX_SLOT_OFFSETS_SPECIAL`, `EFX_BASE_PARAM` | `patch_manager.lua` | `root.lua` |

Do not re-declare these in `root.lua` — that creates a new shadowing local and silently breaks the linkage.

## Connection / channel constants

| Constant | Value | Hardware |
|----------|-------|----------|
| `TB3_CONNECTION` | `{false,false,false,false,false,true}` | TB-3 on connection 6 |
| `BCR_CONNECTION` | `{false,true}` | BCR2000 #1 and #2 both on connection 2 |
| `BCR1_CHANNEL` | `1` | BCR2000 #1 MIDI channel |
| `BCR2_CHANNEL` | `2` | BCR2000 #2 MIDI channel |
| `TB3_MIDI_CHANNEL` | `2` | TB-3 receive channel (user-configured) |

`efx_section.lua` duplicates `TB3_CONN` and `BCR_CONN` as local constants — **keep them byte-identical with root.lua**. TouchOSC has no shared-library mechanism; this duplication is forced.

### NRPN on BCR1 (channel 1)

The seven 16-bit params (3× tuning, VCF env depth / cutoff / resonance, accent) are controlled via **NRPN** (param MSB 0, LSB 1–7 — see `BCR1_NRPN_MAP` in `bcr_map.lua`). The four BCR1 fixed-row-3 encoders (pos 1,2,3,5) are programmed as NRPN absolute/14 with Min/Max = the raw SysEx range (0–151 tuning, 0–255 others), so the 14-bit data value IS the raw value. Consequences:

- **CC 6/38/98/99 are reserved** on channel 1 (NRPN status bytes) — never map them as plain CCs, and never send them as plain CCs to `BCR_CONNECTION` (the BCR's receive parser would misread them). VCO RING LEVEL/SW moved to CC 17/49 because of this.
- CC 96 (DIST TONE) and CC 100 (GLOBAL TUNING) overlap MIDI-spec Data Increment / RPN LSB — intentional; root's parser only consumes 6/38/98/99.
- Receive path: `nrpnState` machine at the top of `handleBCR1`; dispatches on CC 38, updates `rawSysexBlocks` nibbles (NRPN edits do NOT go stale, unlike `sendFromEntry`) and the on-screen fader.
- Feedback path: `sendNRPNToBCR()` (4-message packet) used by `syncBCR1()` and the `enc_moved` mirror via `ADDR_TO_BCR1_NRPN`.
- The BCR preset and the `.tosc` build are coupled: **rebuild/reload the layout before loading the new BCR preset** (old Lua + NRPN preset slams tuning params via the old CC 98/99 map entries).

## SysEx protocol

```
Send (DT1):    F0 41 10 00 00 7B 12  [addr×4]  [data…]  [checksum]  F7
Request (RQ1): F0 41 10 00 00 7B 11  [addr×4]  [size×4] [checksum]  F7
Checksum: (0x100 − (sum of addr+data bytes % 256)) % 128
7-bit param:  single data byte, 0x00–0x7F
16-bit param: MSB = value // 16, LSB = value % 16  (nibble-packed; MSB at addr, LSB at addr+1)
Signed param: raw 64 = 0; display range −64…+63
```

`tb3Checksum` / `sendParam` / connection constants appear in both `root.lua` and `efx_section.lua`. The blocks must stay byte-identical; add a "keep in sync with root.lua" comment if you touch them.

## MIDI value scaling

| Encoding | `bits` / flags | Raw range | UI range |
|----------|---------------|-----------|---------|
| 7-bit unsigned | `bits=7` | 0–127 (or custom `max`) | 0.0–1.0 fader |
| 16-bit nibble-packed | `bits=16` | 0–255 (or custom `max`) | 0.0–1.0 fader |
| Signed offset | `signed=true` | 0–127 | display −64…+63 |
| Bipolar 7-bit | `bipolar=true` | 0–`max` | display ±(max/2) |
| Semitone range | `semitoneRange=true` | 0–23 | display ±1…±24 st |
| Global tuning | `sp="global_tuning"` | CC 104 plain MIDI | lookup table |

`sendFromEntry` / `sendFromEntryFloat` in root.lua implement all these paths; `parseBlock` in patch_manager.lua is the mirror receive path.

## Dual data model — critical design constraint

Root's `rawSysexBlocks` cache stores the last received DT1 block per 8-hex address key (e.g. `"10000000"`). It covers **synthesis blocks only** (LFO, VCO, VCF, VCA, Distortion, Param Assign, etc.). **EFX blocks (`10001000` / `10001200`) are NOT stored in `rawSysexBlocks`.**

EFX state lives in each section's `self.tag` as a JSON byte array (see `efx_section.lua`). `snapshotCurrentPatch()` assembles the full 11-block snapshot by combining `rawSysexBlocks` (9 blocks) with the two EFX section tags.

This split means: BCR-only edits via `sendFromEntry()` update the synthesis blocks but do **not** update `rawSysexBlocks` — BCR-only edits leave patch snapshots/exports stale until the next full sync.

## `self.tag` conventions

`efx_section.lua` overloads `self.tag` for two purposes:
- **`"prog"` guard string**: set during all programmatic button value writes. `efx_button.lua` / `efx_chooser_button.lua` check for this string to distinguish user presses from re-entrant programmatic changes. Tag is reset to `""` after the write is done.
- **Raw byte cache**: for EFX sections, `self.tag` stores the raw SysEx bytes of the last received EFX block as a JSON array (e.g. `[0,0,0,...]`). `snapshotCurrentPatch()` reads this.

These two uses are mutually exclusive in time (the `"prog"` guard is cleared before the byte cache is written), but be aware when modifying either path.

## Script responsibilities

| File | Injected into | Purpose |
|------|--------------|---------|
| `bcr_map.lua` | root (include #1) | `BCR1_MAP` CC→SysEx table; `BCR1_NRPN_MAP` NRPN→SysEx table; EFX slot/button index helpers |
| `patch_manager.lua` | root (include #2) | `parseBlock`; `PARAM_ID_MAP`; `SW_PARAM_ID_MAP`; `EFX_SLOT_OFFSETS_*`; dist type state |
| `enc_map.lua` | root (include #3) | `ENC_SEND_MAP` / `SW_SEND_MAP`; reverse `ADDR_TO_ENC` / `ADDR_TO_SW` lookup tables |
| `root.lua` | root node | MIDI routing; SysEx helpers; BCR handling; patch grid; assign mode |
| `pointer.lua` | all `pointer` BOX nodes | Drag-to-change encoder overlay; sends `enc_touched` |
| `receive_button.lua` | `receive_button` BUTTON | Press → `root:notify("request_dump", "")` |
| `send_button.lua` | `send_button` BUTTON | Press → sends current state to TB-3 via OSC /tb3/restore sequence |
| `control_fader.lua` | all `control_fader` nodes | Slider value → sends `enc_moved` to root (via parent group notify) |
| `sw_button.lua` | all `sw_button` nodes | Toggle → sends `sw_toggled`; LFO BPM SYNC / RETRIG overlay labels flip to black when lit |
| `porta_radio_btn.lua` | `porta_legato_btn`, `porta_always_btn` | Mutual-exclusion radio; sends `porta_mode_set` |
| `dist_toggle_button.lua` | `dist_on_off`, `dist_color` | Toggle with assign-mode intercept; sends `sw_touched` / `sw_toggled` |
| `efx_section.lua` | `efx1_section`, `efx2_section` | EFX type/slot/button state machine; raw SysEx byte cache in tag |
| `efx_button.lua` | `efx1_b1`–`efx1_b8`, `efx2_b1`–`efx2_b8` | Button press relay → `efx_section:notify("btn_press", ...)` |
| `efx_chooser_button.lua` | buttons `1`–`10` under `efx_1_chooser`; `1`–`9` under `efx_2_chooser` | Type direct-select → `root:notify("efx_type_select", "N,M")` |
| `assign_slot_btn.lua` | `assign_xy_mod_btn`, `assign_effect_knob_btn`, `assign_pad_x_btn`, `assign_pad_y_btn` | Assign slot select → `root:notify("assign_slot_select", key)` |
| `preset_grid.lua` | `preset_grid` group | Receives `refresh_preset_ui` / `patch_mode_changed` → updates `back_N` slot colors (blue filled default; red/orange/cyan when delete/grab/morph mode active) |
| `preset_grid_slot_btn.lua` | slots `1`–`16` under `preset_grid` | Press/release relay → `root:notify("patch_slot_pressed/released", N)` |
| `mode_button.lua` | `morph_button`, `delete_button`, `grab_mode_button` | Mode toggle → `root:notify("patch_mode_set", MODE)` where MODE is derived from `self.name` |

**Orphaned (not in toscbuild.json — do not use):** `dist_type_button.lua`, `delete_all_presets_button.lua`, `save_to_library_btn.lua`, `morph_amount_fader.lua`, `porta_mode_button.lua`.

## Notify message contract

All cross-element IPC uses `node:notify(key, value)`. The table below covers every key in the system; payload is always a string.

### Root receives (senders → root `onReceiveNotify`)

| Key | Payload format | Sender | Action |
|-----|---------------|--------|--------|
| `enc_moved` | `"section,enc,x"` — section group name, encoder group name, float 0–1 as string | `control_fader.lua` via parent | Lookup `ENC_SEND_MAP`; send SysEx; update label; mirror to BCR1 |
| `sw_toggled` | `"section,enc,v"` — v = `"0"` or `"1"` | `sw_button.lua`, `porta_radio_btn.lua` | Lookup `SW_SEND_MAP`; send SysEx; mirror to BCR1 |
| `sw_touched` | `"section,enc"` | `sw_button.lua`, `dist_toggle_button.lua` | Assign-mode intercept: assigns parameter, sends `assign_revert` back |
| `enc_touched` | `"section,enc"` | `pointer.lua` on finger-down | Assign-mode intercept: resolves param ID from `PARAM_ID_MAP` or `EFX_SLOT_OFFSETS_*` |
| `porta_mode_set` | `"0"` (LEGATO) or `"1"` (ALWAYS) | `porta_radio_btn.lua` | Send SysEx; broadcast `porta_mode_updated` to both radio buttons |
| `patch_mode_set` | `"delete"` \| `"grab"` \| `"morph"` | mode buttons | Toggle `patchGridMode`; broadcast `patch_mode_changed` |
| `patch_slot_pressed` | `"N"` (slot 1–16) | `preset_grid_slot_btn.lua` | Store / recall / delete / grab / morph depending on `patchGridMode` |
| `patch_slot_released` | `"N"` | `preset_grid_slot_btn.lua` | Grab mode: restore pre-grab snapshot |
| `patch_clear_all` | `""` | *(dead handler — `delete_all_presets_button.lua` deleted)* | Clears all 16 slots |
| `save_to_library` | `""` | *(dead handler — replaced by OSC `/tb3/request_patch_export`)* | Sends `/tb3/backup` OSC |
| `assign_slot_select` | slot key string or `""` | `assign_slot_btn.lua` | Activate / cancel assign mode for that slot |
| `efx_type_select` | `"N,M"` — EFX num, button index (1-based) | `efx_chooser_button.lua` | Forward `type_set` to efx section |
| `efx_type_step` | `"N,D"` — EFX num, direction (+1/-1) | on-screen PREV/NEXT buttons | Forward `type_step` to efx section |
| `request_dump` | `""` | `receive_button.lua` | Call `requestPatchDump()` |
| `dist_type_up` / `dist_type_dn` | `""` | *(dead handlers — `dist_type_button.lua` deleted)* | Increments/decrements `distType`; calls undefined `sendDistType()` |
| `efx_type_changed` | `"N,T"` — EFX num, type index | `efx_section.lua` | Update `efxCurType[N]` for assign-mode EFX slot resolution |
| `efx_sw_touched` | `"efxNum,swOff"` | `efx_section.lua` B1 press handler | Assign-mode: assigns EFX SW parameter to pending slot |

### Efx section receives (`efx1_section` / `efx2_section` `onReceiveNotify`)

| Key | Payload format | Sender | Action |
|-----|---------------|--------|--------|
| `type_set` | `"N"` — type index (0-based) | root | Apply type; remap slots; update buttons |
| `type_step` | `"D"` — direction int | root | Step type by D; wrap around MAX_TYPE |
| `type_cc` | CC value string 0–127 | root `handleBCR2` | Convert CC → type index; call `type_set` path |
| `slot_moved` | `"encName,x"` — encoder node name, float string | root `enc_moved` handler | Move slot fader; send SysEx via `sendSlotFromFloat` |
| `slot_cc` | `"slotIdx,ccVal"` | root `handleBCR2` | BCR slot encoder change; scale and send SysEx |
| `btn_press` | `"btnIdx"` or `"btnIdx,bcr"` | `efx_button.lua` / root `handleBCR2` | Activate radio button; send SysEx; sync BCR |
| `patch_data` | hex CSV string of raw SysEx bytes | root `handleTB3SysEx` | Parse incoming EFX block; store in tag; call `applyType` |

### Mode buttons receive (broadcast from root)

| Key | Payload | Receiver | Action |
|-----|---------|----------|--------|
| `patch_mode_changed` | `"delete"` \| `"grab"` \| `"morph"` \| `""` | `delete_button`, `grab_mode_button`, `morph_button`, `preset_grid` | Mode buttons: set lit state (`updating` guard). `preset_grid`: tint filled slot colours by mode |

### Assign slot buttons receive

| Key | Payload | Receiver | Action |
|-----|---------|----------|--------|
| `assign_mode_changed` | active slot key or `""` | `assign_*_btn` nodes | Update lit state |
| `assign_revert` | `""` | `sw_button` / standalone button | Revert visual state after assign-mode intercept |

### Radio buttons receive

| Key | Payload | Receiver | Action |
|-----|---------|----------|--------|
| `porta_mode_updated` | `"0"` or `"1"` | `porta_legato_btn`, `porta_always_btn` | Update lit state |

## Patch grid architecture

Root orchestrates all preset grid behaviour. Child scripts are thin relays.

### Patch grid state (root.lua)

```lua
local patchGridMode     = nil   -- nil | "delete" | "grab" | "morph"
local grabSnapshot      = nil   -- JSON; saved on grab press, restored on release
local morphTargetSlot   = nil
local morphBaseSnapshot = nil   -- JSON of patch at morph-target selection time
local morphLastBlocks   = nil   -- block hex strings last sent (diff guard)
local morphAmount       = 0.0   -- 0.0–1.0, driven by morph_enc control_fader
local morphing          = false -- true while applyMorph batch-sends; suppresses BCR1
```

### Preset slot format (`preset_grid.tag`)

```jsonc
{
  "1": {"blocks": ["F041...F7", .../* 11 hex strings */], "name": "My Patch"},
  "2": null,
  ...
  "16": {"blocks": [...]}
}
```

### Key root helpers

| Function | Purpose |
|----------|---------|
| `snapshotCurrentPatch()` | Assembles 11-block JSON from `rawSysexBlocks` (9 synth blocks) + two EFX section tags |
| `applySnapshotDiff(targetJson, baseJson)` | Block-level diff: sends only changed blocks to the TB-3 |
| `applyMorph()` | Byte-interpolates all 11 blocks at `morphAmount`; sends changed blocks; sets `morphing` |
| `getPatchGridSlots()` / `setPatchGridSlots(t)` | Read/write `preset_grid.tag` as Lua table |
| `updateMorphEncState()` | Sets `morph_enc.tag` to `"disabled"` / `""` and dims encoder labels; enabled only when `patchGridMode == "morph"` and `morphTargetSlot ~= nil` |
| `syncBCR1()` | Pushes all BCR1 fader positions to BCR2000 #1 after patch restore |

### Preset slot colours (`preset_grid.lua`)

| State | Colour | Hex |
|-------|--------|-----|
| Empty slot | Light grey | `BFBFBFFF` |
| Filled (default) | Blue | `4A90D9FF` |
| Filled + delete mode | Red | `E70000FF` |
| Filled + grab mode | Orange | `FF9500FF` |
| Filled + morph mode | Cyan | `00E6FFFF` |

`grab_mode_button` layout colour matches grab orange (`update_colors.py`). Empty slots stay grey in all modes.

### Morph encoder gating

`morph_enc` is disabled (`tag = "disabled"`, name label dimmed) until morph mode is on **and** a target preset slot is selected. The value label stays white while showing *Pick Preset*. `pointer.lua` rejects drag input when the parent group tag is `"disabled"`. Root also gates on-screen `enc_moved` and BCR1 CC 8 (morph amount) on the same condition. `morphTargetSlot` is cleared when entering or leaving morph mode (UI mode buttons and BCR CC 40).

### `receivingPatch` guard

Set around `parseBlock()` and the EFX section `patch_data` notify to prevent re-entrant SysEx sends back to the TB-3. `enc_moved`, `sw_toggled`, and `slot_moved` handlers all check this flag and skip their SysEx send (but still update labels / BCR LED rings). Cleared synchronously after all processing. `receivingPatchTimer` provides a frame-count backstop (cleared in `update()`) in case of mid-function errors.

## OSC interface (preset manager ↔ TouchOSC)

| Address | Direction | Purpose |
|---------|-----------|---------|
| `/tb3/request_dump` | → root | Trigger full patch dump request |
| `/tb3/request_patch_export` | → root | Root responds with current patch on `/tb3/backup` |
| `/tb3/backup` | root → | JSON snapshot of current patch (11 hex blocks) |
| `/tb3/restore` | → root | Hex CSV SysEx block; root forwards to TB-3 and updates UI |
| `/tb3/patchgrid/request_backup` | → root | Root responds with bank JSON on `/tb3/patchgrid/backup` |
| `/tb3/patchgrid/backup` | root → | JSON bank: `{"version":2,"slots":{"1":{...},...}}` |
| `/tb3/patchgrid/restore` | → root | JSON bank; root restores all 16 slots |

## Tools index

**Reusable:**
- `tools/decode_patch.py` — decode a raw `.syx` file to human-readable parameter values
- `tools/send_patch_osc.py` — send a `.syx` patch file to TouchOSC via OSC `/tb3/restore`
- `tools/update_colors.py` — update button/label colours across the `.tosc` layout
- `tools/fix_value_label_frames.py` — correct value-label frame sizes in the layout

**Historical one-offs (do not re-run):**
- `tools/add_efx_scripts.py` — bootstrapped EFX script injection (superseded by toscbuild)
- `tools/add_efx_button_labels.py` — one-time button label addition pass
- `tools/fix_b_labels_placement.py` — one-time label placement fix
- `tools/rename_retrig_label.py` — renamed duplicate `name_label` → `retrig_label` in `lfo_cv_offset_enc`

## Known design constraints

- **No shared library mechanism** in TouchOSC. `tb3Checksum`, `sendParam`, and connection constants are duplicated between root chunk and `efx_section.lua`. Keep them byte-identical.
- **200-local limit** (Lua 5.1 per-chunk). The concatenated root chunk (~2,500 lines) is approaching this. Avoid adding new top-level locals without removing others.
- **`root:findByName(name, true)`** does a global depth-first search. The `saw_enc` name exists in both `ring_mod_group` and `vco_group` — the `ENC_SEND_MAP` two-level key (`"section,enc"`) was added specifically to avoid this collision. Prefer `group.children[name]` for section-scoped lookups.
- **`.claude/settings.local.json`** contains machine-specific absolute paths — leave it in place, it is local config and not committed.
