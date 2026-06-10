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
The root script injection order is:
`bcr_map.lua` → `patch_manager.lua` → `enc_map.lua` → `root.lua`

Variables declared in earlier files are visible to later ones (shared chunk scope),
which is intentional — e.g. `distType` is declared in `patch_manager.lua` and used
in `root.lua`. Do not re-declare them.

---

## Script table

| File | Injected into | Purpose |
|------|--------------|---------|
| `bcr_map.lua` | root (include #1) | `BCR1_MAP` / `BCR2_MAP` CC→SysEx tables; EFX slot/button index helpers |
| `patch_manager.lua` | root (include #2) | `parseBlock`; `PARAM_ID_MAP`; `SW_PARAM_ID_MAP`; `EFX_SLOT_OFFSETS_*`; dist type state |
| `enc_map.lua` | root (include #3) | `ENC_SEND_MAP` / `SW_SEND_MAP`; reverse `ADDR_TO_ENC` / `ADDR_TO_SW` lookup tables |
| `root.lua` | root node | MIDI routing; SysEx helpers; BCR handling; patch grid; assign mode |
| `pointer.lua` | all `pointer` BOX nodes | Drag-to-change encoder overlay; sends `enc_touched` on finger-down |
| `receive_button.lua` | `receive_button` BUTTON | Press → `root:notify("request_dump", "")` |
| `send_button.lua` | `send_button` BUTTON | Press → sends current state to TB-3 |
| `control_fader.lua` | all `control_fader` nodes | Slider value → sends `enc_moved` notify via parent group |
| `sw_button.lua` | all `sw_button` nodes | Toggle → sends `sw_toggled` |
| `porta_radio_btn.lua` | `porta_legato_btn`, `porta_always_btn` | Mutual-exclusion radio; sends `porta_mode_set` |
| `dist_toggle_button.lua` | `dist_on_off`, `dist_color` | Toggle with assign-mode intercept; sends `sw_touched` / `sw_toggled` |
| `efx_section.lua` | `efx1_section`, `efx2_section` | EFX type/slot/button state machine; raw SysEx byte cache in `self.tag` |
| `efx_button.lua` | `efx1_b1`–`efx1_b8`, `efx2_b1`–`efx2_b8` | Button press relay → `efx_section:notify("btn_press", ...)` |
| `efx_chooser_button.lua` | buttons `1`–`10` under `efx_1_chooser`; `1`–`9` under `efx_2_chooser` | Type direct-select → `root:notify("efx_type_select", "N,M")` |
| `assign_slot_btn.lua` | `assign_xy_mod_btn`, `assign_effect_knob_btn`, `assign_pad_x_btn`, `assign_pad_y_btn` | Assign slot select → `root:notify("assign_slot_select", key)` |
| `preset_grid.lua` | `preset_grid` group | Receives `refresh_preset_ui` → updates `back_N` slot colors |
| `preset_grid_slot_btn.lua` | slots `1`–`16` under `preset_grid` | Press/release relay → `root:notify("patch_slot_pressed/released", N)` |
| `mode_button.lua` | `morph_button`, `delete_button`, `grab_mode_button` | Mode toggle → `root:notify("patch_mode_set", MODE)` where MODE is derived from `self.name` |

**Orphaned files (not in `toscbuild.json` — do not use or reference):**
`dist_type_button.lua`, `delete_all_presets_button.lua`, `save_to_library_btn.lua`,
`morph_amount_fader.lua`, `porta_mode_button.lua`

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
| `refreshPatchGridUI()` | Broadcasts `refresh_preset_ui` to `preset_grid` node |

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
otherwise sets it. Broadcasts `patch_mode_changed` to all three buttons so they stay
in sync.

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
SysEx helpers, or add the parameter to `ENC_SEND_MAP` / `SW_SEND_MAP` in `enc_map.lua`
and let `control_fader.lua` / `sw_button.lua` handle it automatically.
