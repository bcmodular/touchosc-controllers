# TB-3 — Lua contributor guide

General TouchOSC/Lua patterns (naming, scoping, `findByName`, Lua 5.1 constraints,
namespace rules, 200-local limit, grid scope, button state) live in the shared
[**`docs/lua-guide.md`**](../../docs/lua-guide.md). Read that first.

For architecture detail — root chunk include order, notify message contract,
dual data model, SysEx protocol, and connection constants — see
[**`tb-3/CLAUDE.md`**](../CLAUDE.md).

---

## Build pipeline

```bash
python3 tools/toscbuild.py build tb-3           # inject scripts into TB3.tosc
python3 tools/toscbuild.py build tb-3 --dry-run # check without writing
python3 tools/toscbuild.py tree tb-3/TB3.tosc   # inspect node hierarchy
```

Scripts are concatenated and injected at build time per `toscbuild.json`.
The root chunk is **five** files sharing one Lua scope. `toscbuild` *prepends* each
`include`, so the runtime execution order is the **reverse** of the JSON `include`
list. JSON list `["bcr_map.lua", "patch_manager.lua", "enc_map.lua", "param_defs.lua"]`
→ actual execution order:

`param_defs.lua` → `enc_map.lua` → `patch_manager.lua` → `bcr_map.lua` → `root.lua`

Two ordering facts are load-bearing: **`param_defs.lua` runs first** (the other three
derive their tables from `Params.LIST`), and **`root.lua` runs last** (it references the
namespace tables). See [`../CLAUDE.md`](../CLAUDE.md) "Root chunk — include order
contract" for the full rationale.

Each of the four includes exposes exactly one top-level `local` namespace table
(`Params`, `BCR`, `PatchManager`, `EncMap`); `root.lua` references only those four.
Variables declared in earlier files are visible to later ones (shared chunk scope) —
e.g. `PatchManager.distType` is set in `patch_manager.lua` and mutated by `root.lua`.
**Do not re-declare any of the four namespace tables in `root.lua`** — a shadowing
`local` silently breaks the cross-file linkage.

> **Single source of truth (Task 2.2a).** SysEx address, encoding, BCR CC/NRPN, and
> param-assign-ID facts for all ~50 synthesis parameters live in `Params.LIST`
> (`param_defs.lua`) **only**. `bcr_map.lua`, `enc_map.lua`, and `patch_manager.lua`
> derive their primary tables from it at load time in `do…end` blocks. Edit a
> parameter's facts in `Params.LIST`; the derived tables update on the next build.
> (EFX slot/type data is **not** in `Params.LIST` — it has its own single source
> of truth, the `efx_defs` Shared Script; see below.)

> **EFX single source of truth (Task 2.2b).** The EFX type/slot/button layout lives
> in **one** place: `lua/shared/efx_defs.lua`, a TouchOSC **Shared Script** loaded via
> `require("efx_defs")`. The root chunk (`patch_manager.lua`) derives
> `PatchManager.EFX_SLOT_OFFSETS_*` (offsets only) from it; `efx_section.lua` rebuilds
> `TYPE_DEFS` from it, resolving each slot's `display` **string key** to a local display
> function via `DISPLAY_FNS` (display fns + lookup tables stay local — the sp404
> `controls_info.lua` pattern). Edit a slot's `off`/`name`/`max`/`display`/`default` in
> `efx_defs.lua` only; both chunks pick it up on the next build. Shared Scripts are
> independent chunks: no shared `local`s, no nested `require`, cross-chunk only via the
> returned table — so do **not** try to put `Params`/`BCR`/`PatchManager`/`EncMap`
> (the 2.2a shared-`local` namespaces) behind `require`.

---

## Script table

Injection order is the reverse of the JSON `include` list (see Build pipeline above):
`param_defs` → `enc_map` → `patch_manager` → `bcr_map` → `root`.

| File | Injected into | Purpose |
|------|--------------|---------|
| `param_defs.lua` | root (runs first) | `Params` namespace: `Params.LIST` — canonical one-row-per-parameter source of truth for all synthesis params (load-only; the three tables below derive from it) |
| `bcr_map.lua` | root | `BCR` namespace: `BCR.MAP` / `BCR.NRPN_MAP` (derived from `Params.LIST`); reverse `ADDR_TO_CC` / `ADDR_TO_NRPN`; EFX slot/button index helpers |
| `patch_manager.lua` | root | `PatchManager` namespace: `parseBlock`; `PARAM_ID_MAP` / `SW_PARAM_ID_MAP` and file-local `REGISTRY` (derived from `Params.LIST`); `EFX_SLOT_OFFSETS_*`; dist type state |
| `enc_map.lua` | root | `EncMap` namespace: `ENC_SEND_MAP` / `SW_SEND_MAP` (derived from `Params.LIST`); reverse `ADDR_TO_ENC` / `ADDR_TO_SW` lookup tables |
| `shared/efx_defs.lua` | **Shared Script** — `require("efx_defs")` from root + both EFX sections | `EfxDefs`: canonical EFX type/slot/button layout (single source of truth). Pure data; slot `display` is a string key. Injected by the `shared` mapping kind, not concatenated into the root chunk. |
| `root.lua` | root node (runs last) | MIDI routing; SysEx helpers; BCR handling; patch grid; assign mode |
| `pointer.lua` | all `pointer` BOX nodes | Drag-to-change encoder overlay; sends `enc_touched` on finger-down |
| `receive_button.lua` | `receive_button` BUTTON | Press → `root:notify("request_patch_dump", 1)` |
| `send_button.lua` | `send_button` BUTTON | Press → sends current state to TB-3 |
| `control_fader.lua` | all `control_fader` nodes | Slider value → sends `enc_moved` notify via parent group |
| `sw_button.lua` | all `sw_button` nodes | Toggle → sends `sw_toggled`; LFO BPM SYNC / RETRIG overlay labels flip to black when lit |
| `porta_radio_btn.lua` | `porta_legato_btn`, `porta_always_btn` | Mutual-exclusion radio; sends `porta_mode_set` |
| `dist_toggle_button.lua` | `dist_on_off`, `dist_color` | Toggle with assign-mode intercept; sends `sw_touched` / `sw_toggled` |
| `efx_section.lua` | `efx1_section`, `efx2_section` | EFX type/slot/button state machine; raw SysEx byte cache in `self.tag` |
| `efx_button.lua` | `efx1_b1`–`efx1_b8`, `efx2_b1`–`efx2_b8` | Button press relay → `efx_section:notify("btn_press", ...)` |
| `efx_chooser_button.lua` | buttons `1`–`10` under `efx_1_chooser`; `1`–`9` under `efx_2_chooser` | Type direct-select → `root:notify("efx_type_select", "N,M")` |
| `assign_slot_btn.lua` | `assign_xy_mod_btn`, `assign_effect_knob_btn`, `assign_pad_x_btn`, `assign_pad_y_btn` | Assign slot select → `root:notify("assign_slot_select", key)` |
| `preset_grid.lua` | `preset_grid` group | Receives `refresh_preset_ui` / `patch_mode_changed` → updates `back_N` slot colors (blue filled default; red/orange/cyan when delete/grab/morph mode active) |
| `preset_grid_slot_btn.lua` | slots `1`–`16` under `preset_grid` | Press/release relay → `root:notify("patch_slot_pressed/released", N)` |
| `mode_button.lua` | `morph_button`, `delete_button`, `grab_mode_button` | Mode toggle → `root:notify("patch_mode_set", MODE)` where MODE is derived from `self.name` |

**Orphaned files (not in `toscbuild.json` — do not use or reference):**
`dist_type_button.lua`, `delete_all_presets_button.lua`, `save_to_library_btn.lua`,
`morph_amount_fader.lua`, `porta_mode_button.lua`

---

## Notify convention

**Use `root:notify` for root-bound messages; parent relay only where the parent owns or transforms the payload.**

- **`root:notify(key, value)`** — the standard channel for all messages root handles: `enc_moved`, `sw_toggled`, `enc_touched`, `sw_touched`, `patch_mode_set`, `patch_slot_pressed`, `patch_slot_released`, `assign_slot_select`, `porta_mode_set`, `efx_type_select`, `efx_type_step`, `request_patch_dump`, `send_patch_to_device`.
- **`self.parent:notify(key, value)`** — only when the parent genuinely owns the message: `efx_button.lua` → `efx_section` (`btn_press`); `receive_button.lua` / `send_button.lua` → root (these buttons are direct children of root, so `self.parent` IS root).
- **No `self.parent.parent:notify`** — use `root:notify` instead. Grandparent relays bypass root's routing logic and couple the button to its position in the tree.

**Node lookups:** prefer `parent.children["name"]` over `root:findByName("name", true)` when the parent group is already in scope. Use `findByName` only when no scope is available (e.g. top-level section resolution at init, or the node's parent is unknown). This avoids name-collision bugs (e.g. `saw_enc` exists in both `ring_mod_group` and `vco_group`).

---

### Connection constants (root.lua)

All connection arrays are defined as chunk-level locals in `root.lua`:

| Constant | Value | Device |
|----------|-------|--------|
| `BCR_CONNECTION` | `{false,true}` | BCR2000 #1 and #2 (connection 2) |
| `LAUNCHPAD_CONNECTION` | `{false,false,true}` | Launchpad Pro (connection 3) |
| `LAUNCHKEY_CONNECTION` | `{false,false,false,true}` | Launchkey MK4 (connection 4) |
| `TB3_CONNECTION` | `{false,false,false,false,false,true}` | TB-3 (connection 6) |

### Launchpad Pro constants (root.lua)

```lua
LAUNCHPAD_PAD_TO_SLOT  -- note → slot: [81–88] → 1–8, [71–78] → 9–16
SLOT_TO_LAUNCHPAD_PAD  -- reverse map: slot → note (built from LAUNCHPAD_PAD_TO_SLOT)
LAUNCHPAD_HOLD_CC      -- {[50]="delete",[80]="grab"} — momentary-hold modes
-- CC 40 = morph toggle, CC 70 = sync from TB-3 (LP_SYNC), CC 98 = brightness cycle
```

`launchpadBrightnessKey` (`"very_dim"` / `"night"` / `"normal"` / `"day"`, default `"night"`) persists to `root.tag.launchpadBrightnessProfile`. CC 98 (User button) cycles through profiles and calls `syncLaunchpadLEDs()`.

### Launchkey MK4 constants (root.lua)

```lua
LAUNCHKEY_CONNECTION = {false,false,false,true}  -- connection 4
LAUNCHKEY_CHANNEL    = 1                          -- Launchkey default channel
LAUNCHKEY_CC_MAP     -- CC → {assignCC?} or {morph?}: maps encoder CCs 74/71/16/17/12/13/104 + mod wheel CC 1
```

`syncLaunchkey()` is called from `init()` and after every patch receive (same call sites as `syncBCR1()`).

---

## SysEx protocol quick reference

```
Send (DT1):    F0 41 10 00 00 7B 12  [addr×4]  [data…]  [checksum]  F7
Request (RQ1): F0 41 10 00 00 7B 11  [addr×4]  [size×4] [checksum]  F7
Checksum: (0x100 − (sum of addr+data bytes % 256)) % 128
7-bit param:  single byte 0x00–0x7F
16-bit param: MSB = value // 16, LSB = value % 16 (nibble-packed)
Signed param: raw 64 = 0; range 0–127 → −64 to +63
```

---

## Patch grid architecture

Root orchestrates all patch grid behaviour. Child scripts are thin relays — they only
forward events upward via `root:notify`.

### State in root.lua

```lua
local patchGridMode     = nil   -- nil | "delete" | "grab" | "morph"
local grabSnapshot      = nil   -- JSON string; saved when grab press begins
local morphTargetSlot   = nil   -- slot number of morph target
local morphBaseSnapshot = nil   -- JSON string of patch at morph-target selection time
local morphLastBlocks   = nil   -- block hex strings last sent by applyMorph (diff guard)
local morphAmount       = 0.0   -- 0.0–1.0 float from morph_enc control_fader
local morphing          = false -- true while applyMorph send loop runs; suppresses BCR1
```

### Key helpers in root.lua

| Function | Purpose |
|----------|---------|
| `snapshotCurrentPatch()` | Returns `{"blocks":[...11 hex strings...]}` JSON from `rawSysexBlocks` + EFX section tags |
| `applySnapshotDiff(targetJson, baseJson)` | Block-level diff: sends only blocks whose hex string differs |
| `applyMorph()` | Byte-interpolates all 11 blocks at `morphAmount`; sends changed blocks; sets `morphing` flag to suppress BCR1 flood |
| `getPatchGridSlots()` / `setPatchGridSlots(t)` | Read/write `preset_grid.tag` as a Lua table |
| `updateMorphEncState()` | Enables `morph_enc` only when morph mode is on and a target slot is selected (`tag = "disabled"` otherwise); value label stays white for *Pick Preset* |
| `refreshPatchGridUI()` | Broadcasts `refresh_preset_ui` to `preset_grid` node |
| `handlePatchSlotPress(slotNum)` | Store / recall / delete / grab / morph for slot N; called by both `patch_slot_pressed` notify and the Launchpad Pro note-on handler |
| `handlePatchSlotRelease(slotNum)` | Grab-mode restore on pad/note release |
| `handlePatchModeSet(modeStr)` | Toggles `patchGridMode`; broadcasts `patch_mode_changed`; called by mode buttons and Launchpad CC handler |
| `syncLaunchpadLEDs()` | Repaints all Launchpad Pro pad LEDs (slots 81–88, 71–78) and mode-button LEDs to match current grid + mode state; scaled by `launchpadBrightnessKey` |
| `syncLaunchkey()` | Sends current fader values for 7 encoder CCs (74, 71, 16, 17, 12, 13, 104) to the Launchkey on `LAUNCHKEY_CONNECTION` for LED ring sync; called after patch receive |
| `updatePatchInfoLabel()` | Writes `"Bank: X  Preset: Y"` to `preset_name_label`; called whenever `currentBankName` or `currentPresetName` changes |

### Preset slot colours (`preset_grid.lua`)

| State | Colour | Hex |
|-------|--------|-----|
| Empty slot | Light grey | `BFBFBFFF` |
| Filled (default) | Blue | `4A90D9FF` |
| Filled + delete mode | Red | `E70000FF` |
| Filled + grab mode | Light grey-white | `E6E6E6FF` |
| Filled + morph mode | Orange | `FF7F00FF` |
| Morph target slot | Bright orange | `FF7F00FF` (full brightness) |

Only **filled** slots take the mode tint; empty slots stay grey. Pressing a slot
brightens it (grab press → full white `FFFFFFFF`; delete/morph/default → full colour).
The same colour scheme applies to the Launchpad Pro pad LEDs (scaled by the active
brightness profile).

### Morph encoder gating

`morph_enc` is disabled (`tag = "disabled"`, name label dimmed) until morph mode is on **and** a target preset slot is selected. The value label stays white while showing *Pick Preset*. `pointer.lua` rejects drag input when the parent group tag is `"disabled"`. Root also gates on-screen `enc_moved` and BCR1 NRPN 8 on the same condition. `morphTargetSlot` is cleared when entering or leaving morph mode (UI mode buttons and BCR CC 40).

### `receivingPatch` guard

Set around `PatchManager.parseBlock()` and the EFX section `patch_data` notify to prevent re-entrant SysEx sends back to the TB-3. `enc_moved`, `sw_toggled`, and `slot_moved` handlers all check this flag and skip their SysEx send (but still update labels / BCR LED rings). Cleared synchronously after all processing. `receivingPatchTimer` provides a frame-count backstop (cleared in `update()`) in case of mid-function errors.

### Mode button pattern

All three mode buttons (`delete_button`, `grab_mode_button`, `morph_button`) use the
same mutual-exclusion pattern:

```lua
local MODE = "grab"   -- or "delete" / "morph"
local updating = false

function onValueChanged(key)
  if key ~= 'x' then return end
  if updating then return end
  root:notify("patch_mode_set", MODE)   -- always notify; root handles toggle-off
end

function onReceiveNotify(key, value)
  if key == "patch_mode_changed" then
    updating = true
    self.values.x = (value == MODE) and 1 or 0
    updating = false
  end
end
```

Root's `patch_mode_set` handler: if `value == patchGridMode`, clears it (toggle off);
otherwise sets it. Broadcasts `patch_mode_changed` to all three mode buttons and
`preset_grid` (slot colour tint). Clears `morphTargetSlot` when entering or leaving
morph mode. `updateMorphEncState()` runs from `broadcastPatchMode()` and after a
morph target slot is picked.

### Slot data format

`preset_grid.tag` holds a JSON object with string keys `"1"`–`"16"`:

```jsonc
{
  "1":  {"blocks": ["F041...F7", "F041...F7", ... /* 11 hex strings */], "name": "My Patch"},
  "2":  null,
  ...
  "16": {"blocks": [...]}
}
```

Each hex string is a complete Roland DT1 SysEx message including `F0` header and `F7`
terminator, with a valid checksum. Generated by `blockToHexString(addr, data)`.

---

## Adding a new encoder

1. Create `lua/<name>.lua`
2. Add a mapping to `toscbuild.json`:
   ```json
   {"lua": "<name>.lua", "node_name": "<node_name>"}
   ```
   or for multiple nodes sharing the same script:
   ```json
   {"lua": "<name>.lua", "node_names": ["node_a", "node_b"]}
   ```
3. Run `python3 tools/toscbuild.py build tb-3`

Because node scripts run in their own scope (not root), they cannot call `tb3Send7bit`
directly. Use `self.parent:notify(...)` to reach root or a parent group that has the
SysEx helpers.

### Adding a new synthesis parameter (the SysEx-mapped controls)

Since Task 2.2a, **do not** hand-edit `ENC_SEND_MAP` / `SW_SEND_MAP` / `BCR.MAP` /
`BCR.NRPN_MAP` / `PARAM_ID_MAP` / `SW_PARAM_ID_MAP` / `REGISTRY` — they are **derived**.
Add **one row to `Params.LIST` in `param_defs.lua`** and let the derivers build all
seven tables. The row schema (fields, defaults, and the per-row exceptions) is
documented in the header of `param_defs.lua`. After editing, build and verify:

```bash
python3 tools/toscbuild.py build tb-3
# concatenate root chunk in execution order and parse-check (catches >200 locals);
# requires lua (brew install lua):
cat tb-3/lua/param_defs.lua tb-3/lua/enc_map.lua tb-3/lua/patch_manager.lua \
    tb-3/lua/bcr_map.lua tb-3/lua/root.lua > /tmp/tb3_chunk.lua && luac -p /tmp/tb3_chunk.lua
```

`control_fader.lua` / `sw_button.lua` then route the new parameter automatically via
the derived maps.
