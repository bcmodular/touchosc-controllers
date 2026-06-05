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
| `root.lua` | root node | MIDI routing; SysEx send/request helpers; BCR2000 handling |
| `pointer.lua` | all `pointer` BOX nodes | Drag-to-change encoder overlay |
| `receive_button.lua` | `receive_button` BUTTON | Notifies root to send patch dump request |

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
