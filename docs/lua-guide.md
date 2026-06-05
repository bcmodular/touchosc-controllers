# TouchOSC Lua Developer Guide

General reference for all TouchOSC controller projects in this repo.
Project-specific notes live in each project's `lua/README.md`.

---

## Lua version: 5.1

TouchOSC uses **Lua 5.1**. Several Lua 5.3 features are syntax errors here.

### No bitwise operators

`&`, `|`, `~`, `<<`, `>>` are not valid. Use arithmetic/modulo equivalents:

| Intent | Lua 5.3 | Lua 5.1 (use this) |
|--------|---------|---------------------|
| Mask upper nibble | `x & 0xF0` | `x - (x % 16)` |
| Extract lower nibble | `x & 0x0F` | `x % 16` |
| Set channel bits | `0xB0 \| ch` | `0xB0 + ch` *(safe when upper byte's lower nibble is 0)* |

The symptom when `|` appears inside a table constructor is:
`SYNTAX ERROR: N: '}' expected near '|'`

### `goto` is not available

Use `break`, early `return`, or refactor into helper functions.

---

## TouchOSC Lua API

### `findByName` is an instance method, not a global

**Wrong:** `findByName("vcf_cutoff_enc")`
**Right:** `root:findByName("vcf_cutoff_enc", true)`

`root` is a TouchOSC-provided global for the layout's root node. The second
argument `true` enables recursive (deep) search — required because most nodes
are grandchildren or deeper, not direct children of root.

For child lookup within a known parent, use the `children` dictionary:

```lua
local group = root:findByName("lfo_rate_enc", true)
local fader  = group.children["control_fader"]
local swBtn  = group.children["sw_button"]
```

From a non-root node's script, use `root:findByName(...)` to search globally,
or `self:findByName(name, true)` to search only within the current node's subtree.

### `self.values`, not bare `values`

In a node's own script, the node's values are `self.values.x`, not bare `values`
(which is nil in TouchOSC's Lua 5.1 environment).

```lua
-- Wrong:
if values.x == 1 then ...

-- Right:
if self.values.x == 1 then ...
```

### `self` is callback-scoped

`self` is set by the TouchOSC runtime for the duration of each callback
(`onValueChanged`, `onReceiveMIDI`, `onReceiveOSC`, `onReceiveNotify`, `init`).
Do not store it at module level expecting it to persist between calls. Use the
`root` global for layout-wide node access.

### `onValueChanged` from Lua is unreliable

TouchOSC often does **not** call `onValueChanged` when a node's `values` are
changed from Lua — only genuine touch/MIDI input reliably fires it. Do not rely
on scripted value changes to trigger handlers on the same or other nodes.

---

## Naming conventions

| Thing | Convention | Example |
|-------|-----------|---------|
| Variables and functions | camelCase | `attackTimeMs`, `handleMidi` |
| Constants | UPPER_SNAKE_CASE | `DIST_NUM_TYPES`, `BCR1_CHANNEL` |
| TouchOSC node names | snake_case | `vcf_cutoff_enc`, `lfo_rate_enc` |

```lua
-- Good
local attackTimeMs = 10
local function handleMidi(msg) ... end
local BCR1_CHANNEL = 1

-- Bad
local attack_time_ms = 10      -- snake_case for Lua vars
local HandleMidi = function()  -- PascalCase for functions
```

---

## `local function` order — define callees before callers

TouchOSC uses Lua 5.x. `local function foo()` is only visible **after** its
definition line. If `bar()` calls `foo()` and `bar` is defined first, Lua looks
for a global `foo`, gets `nil`, and you get:

`attempt to call global 'foo' (a nil value)`

**Rule:** Keep a bottom-up order — low-level helpers first, higher-level
orchestration later, lifecycle callbacks (`init`, `onReceiveNotify`, etc.) last.

When mutual recursion makes strict ordering impossible, use a **forward declaration**:

```lua
local recallPreset  -- forward declare

local function beginGrabPreset(busNum, presetNum)
  recallPreset(busNum, presetNum)  -- calls the not-yet-defined function
end

recallPreset = function(busNum, presetNum)  -- plain assignment, NOT 'local function'
  -- ...
end
```

**Critical:** the assignment filling a forward declaration must use
`name = function(...)`, **not** `local function name(...)`. Using
`local function` creates a *new* local that shadows the forward declaration —
the original stays `nil` and closures that captured it fail at runtime.

**Quick check before committing:** grep for `local function` names and confirm
every call site is below the definition (or behind a forward declaration).

---

## No namespace tables

TouchOSC runs each node's script in its own isolated Lua environment. Scripts
concatenated via `toscbuild.json` `"include"` share one chunk for that node.
Module-style namespace tables add verbosity with no isolation benefit.

```lua
-- Bad: unnecessary namespace table
TB3 = {}
TB3.DIST_TYPES = 25
function TB3.sendDistType() ... end

-- Good: plain locals
local DIST_TYPES = 25
local function sendDistType() ... end
```

---

## The 200-local limit and the setup-function pattern

Lua enforces a hard limit of **200 local variables per chunk** (or per function).
Because all `"include"` files and the main `.lua` are concatenated into one chunk,
every `local` across all files counts toward the same 200. A project with many
helper files can exhaust this silently.

**Solution:** wrap large included files in a setup function. Each function has its
own independent 200-local budget, and locals inside become upvalues captured by
the closures defined within.

```lua
-- In a large included file:
function _initMyModule()

  local SOME_CONSTANT = 64
  local moduleState = nil  -- survives as an upvalue after _initMyModule() returns

  local function helperA() ... end

  -- Public entry points: NO 'local' — writes to global env so other scripts can call them
  function publicEntryPoint()
    helperA()
  end

end
_initMyModule()  -- run immediately; the function itself is a global (no 'local')
```

Files with fewer than ~40 locals don't need this pattern.

---

## Prefer direct node access over `notify`

`notify` / `onReceiveNotify` is useful for cross-scope messaging (root → bus
group, modal → button grid). Prefer direct access where possible:

```lua
-- Preferred: find the node and set its value directly
local btn = root:findByName("dist_on_off", true)
if btn then btn.values.x = 1 end

-- Use notify when the handler lives on a different node
-- and there is no natural value to set
busGroup:notify("set_fx", { fxIdx, fxName })
```

Avoid `self:notify(...)` on the same node that handles the message — delivery to
`onReceiveNotify` on `self` is inconsistent.

---

## Grid scope and `tag` as shared state

In a TouchOSC grid, the parent and each child button run in their own `self`
scope. Children **cannot** access parent variables directly. The `tag` property
(a string) is the only reliable channel for parent ↔ child state sharing.
Use JSON encoding for structured data:

```lua
-- Parent writes:
local tagData = json.toTable(self.tag) or {}
tagData.deleteMode = true
self.tag = json.fromTable(tagData)

-- Child reads:
local tagData = json.toTable(self.parent.tag) or {}
local deleteMode = tagData.deleteMode or false
```

---

## Button state pattern

Store button states as integers, accessed via `name` (cast to/from string):

```lua
local BUTTON_STATE = { RECALL = 1, DISABLED = 2 }

-- Setting:
child.name = tostring(BUTTON_STATE.RECALL)

-- Reading:
local state = tonumber(self.name) or 0
if state == BUTTON_STATE.RECALL then ... end
```

---

## Build pipeline (all projects)

```bash
# Inject Lua scripts into .tosc
python3 tools/toscbuild.py build <project-dir>

# Dry run — check without writing
python3 tools/toscbuild.py build <project-dir> --dry-run

# Inspect node hierarchy with scripts/tags annotated
python3 tools/toscbuild.py tree <project-dir>/<Layout.tosc>
```

The build manifest `toscbuild.json` in each project directory defines which
`.lua` files map to which node names. Scripts listed under `"include"` are
concatenated before the main file. Build order within includes matters for
shared state (see local scoping rules above).

---

## See also

- [`docs/tosc-format.md`](tosc-format.md) — `.tosc` XML schema, node types,
  property types, scaffold layout format, programmatic modification techniques
- [`sp404-mk2/lua/README.md`](../sp404-mk2/lua/README.md) — SP-404 MK2 specific:
  MIDI routing, Launchkey MK4, layout backup/sync tools
- [`tb-3/lua/README.md`](../tb-3/lua/README.md) — TB-3 specific:
  SysEx protocol, script responsibilities, encoder script template
