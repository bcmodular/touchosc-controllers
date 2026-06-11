# TB-3: 16-Slot Patch Grid + Bank Support in Preset Manager

## Status: **COMPLETE** (implementation shipped; doc divergences below)

All three parts implemented and shipped. See commit history for details.

> **Doc divergences (2026-06 remediation):** This plan predates several UI changes. When reading implementation details below, prefer the live layout and `tb-3/CLAUDE.md` over this file for:
>
> - **Morph amount** — `morph_amount_fader` was replaced by **`morph_enc`** (RADIAL encoder in `morph_group`). Morph is armed via the **MORPH** button inside `morph_group`, not a third mode button beside the grid.
> - **Mode buttons** — `delete_button`, `grab_mode_button`, and `morph_button` now share **`mode_button.lua`** (mode derived from `self.name`). Only **DEL. MODE** and **GRAB MODE** sit beside the preset grid.
> - **DELETE ALL** — `delete_all_presets_button` and its `patch_clear_all` handler were removed.
> - **SAVE TO LIBRARY** — removed from TouchOSC; patch export is app-driven via **Pull Patch** (`/tb3/request_patch_export` → `/tb3/backup`). **SYNC TO TB-3** (`send_button`) pushes TouchOSC state *to* the hardware.
> - **Bank format** — now **v2**: `{"version": 2, "slots": {"1": {"name": "...", "blocks": [...]}, ...}}` (per-slot `name` field added).

---

## What was built

### Part A — Snapshot + block-level diff engine

Rather than a full REGISTRY-based field-level diff engine (the original stretch goal),
a simpler and proven **block-level diff** approach was implemented:

- **`snapshotCurrentPatch()`** — assembles a `{"blocks": [...11 hex strings...]}` JSON
  object from `rawSysexBlocks` (for the 9 synthesis blocks) and from the EFX section
  node tags (for EFX1/EFX2 blocks, each of which maintains its own `rawData` mirror).
  Returns a JSON string suitable for storing in `preset_grid.tag` slots.

- **`applySnapshotDiff(targetJson, baseJson)`** — compares the 11 block hex strings
  between two snapshots. Only sends (via `sendMIDI` + `handleTB3SysEx`) the blocks whose
  hex string has changed. Because each hex string includes the Roland checksum, any
  single byte change produces a different string — the comparison is exact with no false
  positives. Non-EFX blocks are handled by `parseBlock`/REGISTRY; EFX blocks are
  forwarded to their section node via `efxSection:notify("patch_data", ...)`.

- **`blockToHexString(addr, data)`** — helper that builds a well-formed SysEx hex string
  (with address, data and recomputed Roland checksum) from raw address and data byte
  arrays.

This approach is simpler than field-level REGISTRY diffing and handles all three modes
cleanly. Field-level diffing remains a future enhancement for cases where only a single
byte within a block changes (sending one 15-byte SysEx vs. one full 100-byte block).

### Part B — 16-slot Patch Grid

**UI nodes** (all pre-existed in layout):

```
GROUP 'preset_grid'             — holds all slot data in tag as JSON
  BUTTON 'back_1'–'back_16'    — visual fill indicator (BFBFBFFF when empty)
  BUTTON '1'–'16'              — tap targets
  GRID 'perform_preset_label_grid'
    LABEL '1'–'16'             — slot number labels
BUTTON 'morph_button'           — morph mode toggle
GROUP 'morph_group'
  LABEL 'morph_target_label'   — shows active morph target slot number
  FADER 'morph_amount_fader'   — 0.0–1.0 blend amount
BUTTON 'delete_button'          — delete mode toggle
BUTTON 'delete_all_presets_button'
BUTTON 'grab_mode_button'       — grab mode toggle
```

**Scripts injected** (all in `lua/`, all mapped in `toscbuild.json`):

| Script | Target | Notes |
|--------|--------|-------|
| `preset_grid.lua` | `preset_grid` node | `refresh_preset_ui` → updates `back_N` colours |
| `preset_grid_slot_btn.lua` | slots `1`–`16` under `preset_grid` | sends `patch_slot_pressed`/`patch_slot_released` to root |
| `morph_button.lua` | `morph_button` | `local MODE = "morph"`; mutual-exclusion pattern |
| `morph_amount_fader.lua` | `morph_amount_fader` | sends raw 0.0–1.0 float via `morph_amount_changed` |
| `delete_button.lua` | `delete_button` | `local MODE = "delete"`; mutual-exclusion pattern |
| `grab_mode_button.lua` | `grab_mode_button` | `local MODE = "grab"`; mutual-exclusion pattern |
| `delete_all_presets_button.lua` | `delete_all_presets_button` | sends `patch_clear_all` on release |

**Data model** — `preset_grid.tag` holds JSON:
```jsonc
{ "1": {"blocks": ["F041...F7", ... /* 11 hex strings */]}, "2": null, ... "16": {...} }
```

**Mode behaviour:**

| Mode | Tap empty slot | Tap filled slot | Release filled slot |
|------|---------------|-----------------|---------------------|
| nil (default) | Store current patch | Recall (block diff) | — |
| delete | Clear slot | Clear slot | — |
| grab | — | Preview slot (diff-apply); restore on release | Restore base snapshot |
| morph | — | Set as morph target; reset fader to 0.0 | — |

**Morph implementation:**
- On target selection: snapshot current patch as `morphBaseSnapshot`; record initial block
  hex strings as `morphLastBlocks`; reset fader to 0.0.
- On fader movement (`morph_amount_changed`): `applyMorph()` byte-interpolates all 11
  blocks between `morphBaseSnapshot` and target slot data at blend factor `t` (0.0–1.0).
  Formula: `floor(base_byte + (target_byte − base_byte) * t + 0.5)`. Only sends blocks
  whose blended hex string differs from `morphLastBlocks[i]`.
- **BCR flood prevention:** a `morphing` flag is set around the send loop. While set,
  per-fader BCR1 CC mirrors in `onReceiveNotify("enc_moved")` are suppressed. EFX section
  forwarding is NOT suppressed (so EFX faders update live). `syncBCR1()` fires once per
  morph step (after the loop) and again when morph mode exits.

**Key implementation lessons:**
- `onValueChanged(key, value)`: `value` is the **previous** value. Always use `self.values.x`
  for current state.
- Mode button tags in the layout were numeric (`"1"/"0"`) — hardcode `local MODE = "..."`.
- Grab mode disengage: always send `patch_mode_set` regardless of press/release direction;
  root's same-mode toggle handles deactivation.
- `applyMorph` must be defined **after** `getPatchGridSlots` and `setPatchGridSlots` to
  avoid Lua forward-reference errors (local functions are only visible after their definition).

**`root.lua` state variables added:**
```lua
local patchGridMode   = nil   -- nil | "delete" | "grab" | "morph"
local grabSnapshot    = nil   -- JSON string saved on grab press
local morphTargetSlot = nil
local morphBaseSnapshot = nil -- JSON string of patch at morph-target selection time
local morphLastBlocks   = nil -- block hex strings last sent by applyMorph (for diff)
local morphAmount     = 0.0  -- 0.0–1.0 float from fader
local morphing        = false -- true while applyMorph is running; suppresses BCR1 sends
```

### Part C — Banks in the desktop Preset Manager

**New OSC paths** (handled in `root.lua`):

| Path | Direction | Payload |
|------|-----------|---------|
| `/tb3/patchgrid/request_backup` | app → TouchOSC | (no args) |
| `/tb3/patchgrid/backup` | TouchOSC → app | JSON string: `{"version":1,"slots":{...}}` |
| `/tb3/patchgrid/restore` | app → TouchOSC | same JSON string |

**Bank file format** — `.tb3bank.json` in `<patches_dir>/banks/`:
```jsonc
{
  "version": 1,
  "name": "Live Set 1",
  "createdAt": "2026-01-01T12:00:00",
  "slots": {
    "1": {"blocks": ["F041...F7", ... ]},
    "2": null,
    ...
    "16": {"blocks": [...]}
  }
}
```

**Preset Manager** (`preset-manager.py`) additions:
- Window resized to 1020×500 to accommodate three panels.
- New **Banks** panel (right): `QListWidget` + Pull / Push / Delete / Rename / Import / Export.
- `_banks_dir()`: returns `<patches_dir>/banks/`, creates on demand.
- `_pull_bank()`: sends `/tb3/patchgrid/request_backup` OSC message.
- `_handle_bank_backup_received(json_str)`: saves `.tb3bank.json`, prompts for name.
- `_push_bank()`: loads selected bank JSON, sends to `/tb3/patchgrid/restore`.
- `OSCListenerThread` extended to dispatch `/tb3/patchgrid/backup` → `bank_backup_received` signal.

---

## What remains for a future pass

- **Field-level diff engine**: instead of sending a whole block when any byte changes,
  walk REGISTRY fields and send individual `tb3Send7bit`/`tb3Send16bit` calls for only
  the fields that differ. Requires EFX special-casing (type byte must be applied first).
- **EFX BCR2 flood suppression during morph**: EFX section still sends all BCR2 CCs
  when it receives a `patch_data` notify during morph. Suppressing requires a morphing
  flag mechanism in `efx_section.lua`.
- **Assemble a bank from individually-saved `.syx` files** / extract a bank slot as a
  standalone patch — natural follow-ons, not yet requested.
