# TB-3 Lua Contributor Guide

## Build pipeline

```bash
python3 tools/toscbuild.py build tb-3      # inject scripts into TB3.tosc
python3 tools/toscbuild.py build tb-3 --dry-run  # check without writing
python3 tools/toscbuild.py tree tb-3/TB3.tosc    # inspect node hierarchy
```

Scripts are concatenated and injected at build time per `toscbuild.json`.
The root script injection order is: `bcr_map.lua` → `patch_manager.lua` → `root.lua`.
This means variables declared in earlier files are visible to later ones (shared
chunk scope), which is intentional for shared state like `distType`.

---

## TouchOSC Lua environment — known gotchas

### Lua version: 5.1 (no bitwise operators)

TouchOSC uses **Lua 5.1**. The Lua 5.3 bitwise operators (`&`, `|`, `~`, `<<`,
`>>`) are **syntax errors**. Use arithmetic/modulo equivalents:

| Lua 5.3        | Lua 5.1 equivalent               | Notes |
|----------------|----------------------------------|-------|
| `x & 0xF0`     | `x - (x % 16)`                  | upper nibble (mask low 4 bits) |
| `x & 0x0F`     | `x % 16`                        | lower nibble |
| `0xB0 \| ch`   | `0xB0 + ch`                     | safe when `0xB0` lower nibble = 0 |

The symptom when `|` appears inside a table constructor is exactly:
`SYNTAX ERROR: N: '}' expected near '|'`.

### `findByName` is an instance method, not a global

**Wrong:** `findByName("vcf_cutoff_enc")`  
**Right:** `root:findByName("vcf_cutoff_enc", true)`

`root` is a TouchOSC-provided global referring to the root layout node.
The second argument `true` enables recursive (deep) search — required because
most nodes are grandchildren or deeper, not direct children of root.

For child lookup within a known parent, use the `children` dictionary:
```lua
local group = root:findByName("lfo_rate_enc", true)
local fader = group.children["control_fader"]
local swBtn = group.children["sw_button"]
```

### `self.values`, not bare `values`

In a node's own script, access the node's values as `self.values.x`, not the
bare global `values` (which is nil in Lua 5.1 TouchOSC).

```lua
-- Wrong:
if values.x == 1 then ...

-- Right:
if self.values.x == 1 then ...
```

### `self` is the current node in callbacks

`self` is set by the TouchOSC runtime for the duration of each callback
(`onValueChanged`, `onReceiveMIDI`, `onReceiveOSC`, etc.). It is **not** a
persistent global between calls — do not store it at module level expecting
it to be available later. Use `root` for persistent cross-script references.

---

## Naming conventions

- **Lua variables/functions:** camelCase (`parseBlock`, `sendDistType`)
- **Constants:** UPPER_SNAKE_CASE (`DIST_NUM_TYPES`, `BCR1_CHANNEL`)
- **TouchOSC node names:** snake_case (`vcf_cutoff_enc`, `lfo_rate_enc`)
- Encoder groups follow pattern `<param>_enc`; switches follow `<param>_button`

## Script responsibilities

| File | Injected into | Purpose |
|------|--------------|---------|
| `bcr_map.lua` | root (include) | CC→SysEx address table; EFX slot/button index helpers |
| `patch_manager.lua` | root (include) | SysEx receive registry; `parseBlock`; shared dist type state |
| `root.lua` | root node | MIDI routing; SysEx send helpers; RQ1 dump request |
| `pointer.lua` | all `pointer` BOX nodes | Drag-to-change encoder overlay |
| `receive_button.lua` | `receive_button` BUTTON | Notifies root to send patch dump request |

## Adding a new encoder script

1. Create `lua/<name>.lua`
2. Add a mapping to `toscbuild.json`:
   ```json
   {"lua": "<name>.lua", "node_name": "<node_name>"}
   ```
3. Run `python3 tools/toscbuild.py build tb-3` to inject
