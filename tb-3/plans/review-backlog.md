# TB-3 Review Backlog

> **Status:** Topics only — verified during the 2026 remediation review. No fixes applied here; use this as a triage list for future sessions.

---

## Behavioral findings

### BCR cache staleness

`sendFromEntry()` (`root.lua` ~350) sends SysEx to the TB-3 but does **not** update `rawSysexBlocks`. BCR-only edits therefore leave patch-grid snapshots and `/tb3/backup` exports stale until the next full sync. The on-screen UI path (`enc_moved` → `sendFromEntry` + label update) has the same gap for synthesis blocks; EFX blocks are mirrored in section tags separately.

**Impact:** Store/recall, morph base snapshot, and desktop Pull Patch can diverge from what the BCR2000 last wrote.

---

### BCR tuning range mismatch

`bcr_map.lua` uses `max=255` for 16-bit tuning encoders; `enc_map.lua` / on-screen UI uses `max=151`. The BCR2000 can therefore send out-of-range values that the TouchOSC faders cannot represent faithfully.

**Impact:** BCR ring position and displayed value may disagree; hardware may receive values outside the intended UI range.

---

### EFX type encoder asymmetry

Type index → CC on sync: `floor(typeIdx / MAX_TYPE * 127)` (`efx_section.lua` ~606). CC → type index on receive: `floor(cc / 10)` (`efx_section.lua` ~771). These are not inverse functions — round-trip through BCR type encoder can land on a different type index.

**Impact:** BCR2000 type knob may not match the on-screen type after a patch receive or preset recall.

---

### Morph interpolates everything

`applyMorph()` (`root.lua` ~905) linearly blends **all** data bytes in all 11 blocks, including effect type bytes, switch states, and parameter-assign IDs. Intermediate blend positions can produce invalid or nonsensical patches (e.g. half of a distortion type index, blended bypass flags).

**Impact:** Morphing through the AMOUNT encoder may briefly (or permanently, if left mid-blend) put the TB-3 in an undefined state.

---

### Store-to-empty-slot double press

When tapping an empty preset slot and `snapshotCurrentPatch()` returns nil (blocks not yet cached), root triggers `requestPatchDump()` but does **not** auto-store into the slot after the dump completes (`root.lua` ~1397–1407). The user must tap the slot again after SYNC FROM TB-3 finishes.

**Impact:** First tap on an empty slot after a fresh load appears to do nothing until sync completes and the slot is tapped a second time.

---

### Panel CC labels

`handleTB3CC` (`root.lua` ~620) hardcodes `floor(x * 255)` for CC 16 (Accent), 71 (Resonance), and 74 (Cutoff) regardless of each parameter's actual encoding or range in `ENC_SEND_MAP` / `REGISTRY`.

**Impact:** Live hardware knob feedback on the panel-controls encoders may show wrong values if the TB-3 CC curve does not match a linear 0–255 scale.

---

### Data duplication drift risk

SysEx address, range, and scaling facts are hand-maintained in at least four places:

| Location | Contents |
|----------|----------|
| `enc_map.lua` | `ENC_SEND_MAP`, `SW_SEND_MAP` |
| `bcr_map.lua` | `BCR1_MAP`, BCR2 helpers |
| `patch_manager.lua` | `REGISTRY`, `PARAM_ID_MAP`, `EFX_SLOT_OFFSETS_*` |
| `efx_section.lua` | `TYPE_DEFS` per effect |

`EFX_SLOT_OFFSETS_*` in `patch_manager.lua` manually mirrors slot layouts in `efx_section.lua` `TYPE_DEFS`. Any edit to one without the others causes silent assign-mode or BCR routing bugs.

**Candidate fix:** Single parameter data table (sp404 `controls_info.lua` pattern) with maps derived at init or via codegen.

---

### Minor items

- **`pointer.lua` double-tap reset:** Edge cases when slot is disabled (`tag == "disabled"`) or when assign mode is active — not fully verified.
- **Duplicate `assign_xy_mod_status` labels:** The layout contains multiple label nodes named `assign_xy_mod_status` (tree shows four duplicates). `findByName` may update only the first match.
- **Unverified display curves:** Flanger HPF, RATE, EQ freq/Q, and Compressor attack/release curves are approximations — already flagged in `tb3-layout-plan.md` Open Items; no on-device readout to verify against.

---

## Code-health refactor follow-ups

These are deliberate architectural improvements, not bugs. Deferred from the remediation pass to avoid scope creep.

### Namespace the root chunk

The concatenated root chunk (`bcr_map.lua` + `patch_manager.lua` + `enc_map.lua` + `root.lua`, ~2,500 lines) shares top-level locals with no declared ownership and approaches Lua 5.1's 200-local-per-scope limit.

**Proposal:** Each include exposes exactly one table (`BCR = {...}`, `PatchManager = {...}`, `EncMap = {...}`); `root.lua` references only those namespaces.

### Single source of truth for parameter data

Consolidate SysEx facts into one data table; derive `ENC_SEND_MAP`, `BCR1_MAP`, `REGISTRY` field lists, and EFX slot offsets from it at load time.

### Standardize lookup and messaging idioms

- Replace global `root:findByName(name, true)` with section-scoped `group.children[name]` where possible (the `saw_enc` name collision in `ring_mod_group` vs `vco_group` already required a two-level `ENC_SEND_MAP` key).
- Pick one notify convention: `self.parent:notify` vs `root:notify` — document and enforce consistently.
