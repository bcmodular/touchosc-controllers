# Codebase Complexity & Inconsistency Review

## Context

Periodic architectural review to identify friction points before they compound. The codebase has grown organically across many feature iterations, and several patterns have drifted into inconsistency or unnecessary duplication that will slow future development.

**Parked pending TouchOSC `require` / Shared Scripts exiting beta (introduced in 1.5.1.253). Most high-priority fixes depend on this feature. Resume when stable release ships.**

---

## Finding 1 — Duplicated utility functions across every manager (HIGH IMPACT)

The same three functions are copy-pasted into every file that needs them:

| Function | Files |
|---|---|
| `midiToFloat` / `floatToMIDI` | `bus_group_instance.lua`, `scene_manager.lua`, `preset_grid_manager.lua`, `control_mapper.lua` (inside template string!) |
| `getBusGroup(busNum)` | `backup_manager.lua`, `keyboard_manager.lua`, `scene_manager.lua`, `preset_grid_manager.lua` |
| `scaleHexColor(hex, factor)` | `preset_grid_manager.lua`, `scene_manager.lua`, `root.lua` |

**Problem:** Any edge-case fix or behaviour change must be made in 4 places. `midiToFloat` inside the `control_mapper.lua` template string is particularly hazardous — it's Lua inside a Lua string, invisible to search.

**Fix (once `require` is stable):** Extract into shared scripts — see `require` Assessment section below.

---

## Finding 2 — Bus accent color duplication + awkward string/int key split (MEDIUM)

`BUS_ACCENT_HEX` is defined as an integer-keyed table in `root.lua`, then manually re-serialized as string keys (`"1"`..`"5"`) into `root.tag.busAccentHex` for cross-script reading. `preset_grid_manager.lua` also has its own `FALLBACK_BUS_ACCENT_HEX` as a fallback for when the tag hasn't been written yet.

The integer/string key split is a latent bug: `recent_values.lua` already shows the wound (`buses[i] or buses[tostring(i)]` — a normalization band-aid). Everywhere `root.tag` is used as shared state, consumers have to guess the key type.

**Fix:** Establish a convention: **all tables stored in `.tag` JSON use string keys**. Define `BUS_ACCENT_HEX` in root.lua with string keys from the start, remove the re-serialization step, and eliminate `FALLBACK_BUS_ACCENT_HEX` by ensuring `root.lua` writes the tag in `init()` before any other script reads it. (Can be done now, independent of `require`.)

---

## Finding 3 — `control_mapper.lua`: Lua-in-a-string template is a maintenance trap (HIGH IMPACT)

`performFaderScriptTemplate` is a ~170-line Lua script stored as a `[[...]]` string and formatted with `string.format` before runtime injection. Issues:

- Errors in fader scripts show no useful stack trace — just `[string]:N`
- `midiToFloat`/`floatToMIDI` are re-defined *inside the template string*, making grep useless
- The template uses `%s` positional substitution; adding a new parameter requires counting substitution slots
- Any syntax error in the template silently produces broken fader scripts at runtime

This is the single biggest obstacle to future fader feature development.

**Fix (once `require` is stable):** Fader scripts (runtime-injected) can call `require("midi_utils")` directly — remove the in-template redefinitions. Long-term north star is build-time parameterization in `toscbuild.py` so fader scripts become real `.lua` files.

---

## Finding 4 — `keyboard_manager.lua`: 1916-line monolith wrapped in `_initKeyboard()` (MEDIUM)

The entire module is nested inside a single function to work around Lua's 200-local-variable limit. This:
- Makes the file hard to navigate
- Signals the module has too many responsibilities
- The workaround itself is a code smell that future feature additions will hit again

**Fix:** Identify natural sub-domains within keyboard_manager (e.g., chord logic, key LED management, MIDI routing) and split into separate `.lua` files injected into separate TouchOSC nodes, communicating via `notify`. Larger project; flag for the next keyboard feature pass.

---

## Finding 5 — `NUM_BUSES` and `PRESETS_PER_BUS` defined in 3 files (LOW, easy fix)

```
backup_manager.lua:8    local NUM_BUSES = 5
scene_manager.lua:6     local NUM_BUSES = 5
preset_grid_manager.lua:22  local NUM_BUSES = 5  
preset_grid_manager.lua:23  local PRESETS_PER_BUS = 8
```

**Fix (once `require` is stable):** Move into a `"constants"` shared script. Until then, add `-- must match all other NUM_BUSES definitions` comment to each.

---

## Finding 6 — Inconsistent debug patterns (LOW, stylistic)

5 different debug flag patterns:
- Flag names: `MORPH_DEBUG`, `KEYBOARD_DEBUG`, `BCR_DEBUG`, `LAUNCHPAD_DEBUG`...
- Function names: `debugMorph()`, `debugKeyboard()`, `debugBcr()`...
- Some print with `[Tag]` prefix, some without

**Fix:** Standardize on `local DEBUG = false` and `local function dbg(msg) if DEBUG then print('[' .. self.name .. ']', msg) end end`. Apply during next touch of each file.

---

## `require` Beta Assessment (TouchOSC 1.5.1.253)

TouchOSC's new beta `require()` function loads named **Shared Scripts** stored at the document root level. A shared script can return a value (table of functions, constants, etc.) — a real module pattern. Limitations:

- Shared Scripts **cannot call `require`** themselves (no nesting)
- Names are flat strings; must be unique within the document
- Still beta — API may change

**How this directly fixes Finding 1:**

| Shared Script | Exports | Replaces duplication in |
|---|---|---|
| `"midi_utils"` | `midiToFloat`, `floatToMIDI` | `bus_group_instance`, `scene_manager`, `preset_grid_manager`, `control_mapper` template |
| `"node_utils"` | `getBusGroup` | `backup_manager`, `keyboard_manager`, `scene_manager`, `preset_grid_manager` |
| `"color_utils"` | `scaleHexColor` | `preset_grid_manager`, `scene_manager`, `root` |
| `"constants"` | `NUM_BUSES`, `PRESETS_PER_BUS`, `BUS_ACCENT_HEX` | 3+ files |

**Usage pattern:**
```lua
local mu = require("midi_utils")   -- returns { midiToFloat=..., floatToMIDI=... }
local floatVal = mu.midiToFloat(64)
```

**Build tool changes needed (`toscbuild.py`):**

Shared scripts live at a different XML location than node scripts (somewhere under `<lexml>`, not inside `<node>`). `toscbuild.py` needs:

1. A new mapping type in `toscbuild.json`: `{"lua": "midi_utils.lua", "shared_script_name": "midi_utils"}`
2. A write path that inserts/updates the shared script XML at `<lexml>` level
3. The exact XML structure is unknown until a beta `.tosc` with a shared script is inspected — create one in TouchOSC, then `zlib decompress` to see the format before implementing

**Note:** `docs/tosc-format.md` currently lists `require` as unavailable — update once stable.

---

## Prioritized Action List (resume when `require` exits beta)

| Priority | Finding | Effort | Risk |
|---|---|---|---|
| 1 | Inspect beta `.tosc` shared script XML format; extend `toscbuild.py` to support `shared_script_name` mapping | Medium | Low |
| 2 | Create `midi_utils`, `node_utils`, `color_utils`, `constants` shared scripts; replace all local duplicates with `require()` | Medium | Low |
| 3 | Remove `midiToFloat`/`floatToMIDI` from `control_mapper.lua` template string; use `require("midi_utils")` in fader scripts | Small | Low |
| 4 | Standardize `root.tag` shared state to string keys consistently (can be done now) | Small–Medium | Low |
| 5 | Add `-- must match` comments to duplicate `NUM_BUSES` definitions (interim until `constants` shared script) | Trivial | None |
| 6 | Design build-time parameterization for `control_mapper.lua` templates | Large | Medium |
| 7 | Split `keyboard_manager.lua` into sub-modules | Large | Medium |
| 8 | Standardize debug flag pattern (apply during next touch of each file) | Trivial | None |

## Verification

- After any change to `control_mapper.lua`: run `python3 tools/toscbuild.py build sp404-mk2` and confirm no build errors; load in TouchOSC and move a fader on each bus to confirm MIDI output
- After `root.tag` key convention change: confirm preset recall and scene recall still apply correct values (the main consumers of `root.tag.busAccentHex`)
- After any refactor: `python3 tools/toscbuild.py tree sp404-mk2/SP404.tosc` to confirm node scripts are still present
