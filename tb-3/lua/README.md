# TB-3 — Lua contributor guide

General TouchOSC/Lua patterns (naming, scoping, `findByName`, Lua 5.1 constraints,
namespace rules, 200-local limit, grid scope, button state) live in the shared
[**`docs/lua-guide.md`**](../../docs/lua-guide.md). Read that first.

---

## Build pipeline

```bash
python3 tools/toscbuild.py build tb-3           # inject scripts into TB3.tosc
python3 tools/toscbuild.py build tb-3 --dry-run # check without writing
python3 tools/toscbuild.py tree tb-3/TB3.tosc   # inspect node hierarchy
```

Scripts are concatenated and injected at build time per `toscbuild.json`.
The root script injection order is: `bcr_map.lua` → `patch_manager.lua` → `root.lua`.
Variables declared in earlier files are visible to later ones (shared chunk scope),
which is intentional — e.g. `distType` is declared in `patch_manager.lua` and used
in `root.lua`.

---

## Script responsibilities

| File | Injected into | Purpose |
|------|--------------|---------|
| `bcr_map.lua` | root (include) | CC→SysEx address table; EFX slot/button index helpers |
| `patch_manager.lua` | root (include) | SysEx receive registry; `parseBlock`; shared dist type state |
| `root.lua` | root node | MIDI routing; SysEx send/request helpers; BCR2000 handling; patch grid orchestration |
| `pointer.lua` | all `pointer` BOX nodes | Drag-to-change encoder overlay |
| `receive_button.lua` | `receive_button` BUTTON | Notifies root to send patch dump request |
| `preset_grid.lua` | `preset_grid` group | Handles `refresh_preset_ui` — updates `back_N` slot colours |
| `preset_grid_slot_btn.lua` | slots `1`–`16` under `preset_grid` | Sends `patch_slot_pressed`/`patch_slot_released` to root |
| `delete_button.lua` | `delete_button` | Delete mode toggle; mutual-exclusion via `patch_mode_set`/`patch_mode_changed` |
| `delete_all_presets_button.lua` | `delete_all_presets_button` | Sends `patch_clear_all` on release |
| `grab_mode_button.lua` | `grab_mode_button` | Grab mode toggle; same mutual-exclusion pattern |
| `morph_button.lua` | `morph_button` | Morph mode toggle; same mutual-exclusion pattern |
| `morph_amount_fader.lua` | `morph_amount_fader` | Sends raw 0.0–1.0 float via `morph_amount_changed` notify |

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
local morphAmount       = 0.0   -- 0.0–1.0 float from fader
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
  "1":  {"blocks": ["F041...F7", "F041...F7", ... /* 11 hex strings */]},
  "2":  null,
  ...
  "16": {"blocks": [...]}
}
```

Each hex string is a complete Roland DT1 SysEx message including `F0` header and `F7`
terminator, with a valid checksum. Generated by `blockToHexString(addr, data)`.

---

## Adding a new encoder script

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

Encoder scripts typically follow this pattern:

```lua
-- my_enc.lua — injected into <node_name>
function init()
  -- optional setup
end

function onValueChanged(key)
  if key ~= "x" then return end
  local raw = math.floor(self.values.x * MAX + 0.5)
  -- call root helpers via notify or direct SysEx from root.lua functions
end
```

Because encoder scripts run in their own node scope (not root), they cannot call
`tb3Send7bit` directly. Use `self.parent:notify(...)` to reach the root or a
parent group that has the SysEx helpers.
