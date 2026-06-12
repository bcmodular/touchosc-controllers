# TB-3 Implementation Plan — Review Remediation

> **Status:** Implementation plan — upgraded from the 2026 remediation-review triage list. Each in-scope task below has a defined scope, acceptance criteria, and a recommended model class (see [Model choice guidance](#model-choice-guidance)). Work Phase 1 before Phase 2.
>
> **Progress (2026-06-11):**
> - Phase 1 (Tasks 1.1–1.5) — ✅ committed `b380a9f`.
> - Task 2.1 (namespace the root chunk) — ✅ done and hardware-verified, committed `1bf2298`.
> - Task 2.2a (canonical synth-param table) — ✅ done (2026-06-12). `param_defs.lua` added; `bcr_map.lua`, `enc_map.lua`, `patch_manager.lua` now derive their 7 primary tables from it. Value-identity harness PASS (zero diffs), `luac -p` PASS, build clean (241/241). Hardware regression pending.
> - Task 2.2b (shared EFX defs) — open. Scope: new `efx_defs.lua` included into root AND both EFX sections; `EFX_SLOT_OFFSETS_*` derived in root, `TYPE_DEFS` rebuilt in `efx_section.lua` via string-key dispatch table.
> - Task 2.3 — open.
> - Out-of-plan fix shipped in `1bf2298`: chunked the preset-manager bank pull/push OSC transfer (was hanging on banks >~8 KB due to macOS's ~9 KB UDP datagram cap + python-osc's 8192-byte recv buffer). See the new entry under [Out-of-plan fixes](#out-of-plan-fixes).

---

## Decision log

| Original finding | Decision |
|------------------|----------|
| BCR cache staleness | **Done** — Task 1.1 (`b380a9f`) |
| BCR tuning range mismatch | **Already fixed** — resolved by the NRPN migration. The seven 16-bit params now travel as NRPN absolute/14 with Min/Max = the raw SysEx range (0–151 tuning, 0–255 others), so the BCR and on-screen UI share one range by construction. No task. |
| EFX type encoder asymmetry | **Done** — Task 1.2 (`b380a9f`) |
| Morph interpolates everything | **Known issue (won't fix)** — see below |
| Store-to-empty-slot double press | **Done** — Task 1.3 (`b380a9f`) |
| Panel CC labels | **Known issue (open risk)** — see below |
| Double-tap reset defaults | **Done** — Task 1.4 defaults audit (`b380a9f`) |
| Duplicate `assign_xy_mod_status` labels | **Done** — Task 1.5 (`b380a9f`) |
| Unverified display curves | **Known issue (open)** — see below |
| Namespace the root chunk | **Done** — Task 2.1 (`1bf2298`) |
| Single source of truth for parameter data | **2.2a done** (`param_defs.lua`, 2026-06-12) — 2.2b (EFX defs) open |
| Standardize lookup and messaging idioms | **In scope** — Task 2.3 |

### Known issues (documented, no task)

- **Morph interpolates everything.** `applyMorph()` (`root.lua`) linearly blends all data bytes in all 11 blocks, including effect type bytes, switch states, and parameter-assign IDs. Kept deliberately unrestricted — blending "non-continuous" bytes may occasionally be musically useful, and limiting it would foreclose that. **User workaround:** treat mid-blend positions across type/switch boundaries as transient; settle the AMOUNT encoder at 0.0 or 1.0 (or re-sync from the TB-3) rather than leaving the unit mid-blend.
- **Panel CC labels.** `handleTB3CC` (`root.lua`) hardcodes `floor(x * 255)` for CC 16 (Accent), 71 (Resonance), and 74 (Cutoff). If the TB-3's CC transmit curve is not linear 0–255, live-knob feedback shows wrong values. Left open: we cannot verify the hardware curve without an on-device readout to compare against.
- **Unverified display curves.** Flanger HPF, RATE, EQ freq/Q, and Compressor attack/release display curves are approximations (already flagged in `tb3-layout-plan.md` Open Items). Left open for the same reason as above.

---

## Phase 1 — Behavioral fixes

Independent, small diffs. Land and hardware-verify these before starting Phase 2 refactors — they change the code Phase 2 will move, and verifying them against the current (familiar) structure is much cheaper.

### Task 1.1 — BCR cache staleness

**Problem.** `sendFromEntry()` (`lua/root.lua` ~380) sends SysEx to the TB-3 but does not update `rawSysexBlocks`. BCR-only edits therefore leave patch-grid snapshots, morph base snapshots, and `/tb3/backup` exports stale until the next full sync.

**Fix.** Add the cache write-back inside `sendFromEntry()`, mirroring the logic that already exists in the two correct paths:

- `sendFromEntryFloat()` (`root.lua` ~230–245): computes `blockKey = "%02X%02X%02X00"` from `entry.addr`, then writes either the MSB/LSB nibble pair (`bits == 16`: `data[a[4]+1] = floor(raw/16)`, `data[a[4]+2] = raw % 16`) or the single byte (`data[a[4]+1] = raw`).
- The NRPN dispatch path in `handleBCR1` (`root.lua` ~453–457): same nibble convention.

`sendFromEntry()` already computes the scaled raw value in both branches (`val16` and `scaled`) — the write-back slots in directly after each `tb3Send*` call. Guard with `if blk then` as the existing paths do (the block may not be cached yet before the first sync).

Once fixed, update the stale-cache comments: the "BCR-only edits leave snapshots stale" caveat in `tb-3/CLAUDE.md` (Dual data model section) and any equivalent comment near `rawSysexBlocks` in `root.lua`.

**Acceptance.**
- Turn a BCR1 plain-CC encoder (e.g. CUTOFF KF, not an NRPN param) without touching the screen → store to an empty slot → recall the slot after changing the parameter → the BCR edit is restored.
- Pull Patch from the desktop preset manager after a BCR-only edit reflects the edit.

**Model:** fast/mid-tier (Composer / Sonnet class). Small, fully specified diff.

---

### Task 1.2 — EFX type encoder symmetry

**Problem.** Type→CC on BCR sync and CC→type on receive are not inverse functions (`lua/efx_section.lua`):

- Encode (~603): `floor(typeIdx / MAX_TYPE * 127 + 0.5)`
- Decode (~770, `type_cc` handler): `floor(cc / 10)`

A round-trip through the BCR type encoder can land on a different type index (e.g. EFX2, `MAX_TYPE = 9`: type 7 encodes to CC 99, which decodes to type 9).

**Fix.** Make the decode the exact inverse of the encode:

```lua
local typeIdx = math.min(math.floor(ccVal / 127 * MAX_TYPE + 0.5), MAX_TYPE)
```

Keep the encode as-is. Note that `efx_section.lua` is injected into both `efx1_section` and `efx2_section`, and `MAX_TYPE` differs per section (top-level constant: 10 for EFX1, 9 for EFX2 — `efx_section.lua` ~28) — the formula must stay in terms of `MAX_TYPE`, no hardcoded divisors.

**Acceptance.**
- For every type index 0..MAX_TYPE on both EFX sections: encode → decode returns the same index (verifiable by inspection or a scratch Lua loop outside TouchOSC).
- On hardware: select each EFX type on screen, nudge nothing, observe the BCR type-knob LED ring; turning the BCR knob by the smallest detent that changes the CC past a boundary selects the adjacent type, and syncing a patch does not silently change the displayed type.

**Model:** fast/mid-tier (Composer / Sonnet class).

---

### Task 1.3 — Store-to-empty-slot auto-store

**Problem.** Tapping an empty preset slot when `snapshotCurrentPatch()` returns nil (blocks not yet cached) triggers `requestPatchDump()` but does not store after the dump completes (`root.lua` ~1518–1528). The user must tap the slot a second time.

**Fix.** Auto-complete the store once the dump finishes:

1. Add one root-chunk local, `pendingStoreSlot` (mind the 200-local budget — see Phase 2.1; if the chunk is tight, fold it into an existing state table instead of a new top-level local).
2. In the `patch_slot_pressed` empty-slot branch (`root.lua` ~1518–1528): when the snapshot is nil, set `pendingStoreSlot = slotKey` before calling `requestPatchDump()`.
3. Completion hook: where the `awaitingBlocks` countdown reaches 0 and sets `triggerSync` (`root.lua` ~749–752), and in the `syncTimer` fallback in `update()`, attempt the store: if `pendingStoreSlot` is set and `snapshotCurrentPatch()` now returns non-nil, write the slot via `getPatchGridSlots()` / `setPatchGridSlots()` and refresh the grid UI; clear `pendingStoreSlot` either way.
4. Clear `pendingStoreSlot` on any other slot press or mode change so a stale pending store cannot fire later.

**Acceptance.**
- Fresh layout load (no sync yet) → tap an empty slot once → after SYNC FROM TB-3 traffic finishes, the slot turns blue (filled) without a second tap.
- The fallback path also completes the store when one of the 11 blocks goes missing (simulate by tapping during a partial dump): the slot fills (or stays empty if blocks are still missing), and no spurious store happens on the *next* unrelated dump.

**Model:** mid-tier (Sonnet class). Slightly more state to reason about (two completion paths, cancellation), but well-bounded.

---

### Task 1.4 — Double-tap default values audit

**Problem.** Double-tap on an encoder resets the fader to its layout `DEFAULT` value field (`lua/pointer.lua` ~49, `controlFader:getValueField("x", ValueField.DEFAULT)`). These defaults were never reviewed against each parameter's encoding.

**Rule.** A fader default should be:
- **0.0** for unipolar parameters (plain `bits=7` / `bits=16` ranges), and
- **0.5** (center) for bipolar parameters — entries with `signed=true`, `bipolar=true`, or `semitoneRange=true` in `ENC_SEND_MAP` (`lua/enc_map.lua`).

(Center for a signed param maps to raw 64 = 0 offset; for `semitoneRange` the center is the smallest range — confirm the desired center against the display function during the audit.)

**Fix.**
1. Write a read-only audit script `tb-3/tools/audit_fader_defaults.py`: walk `TB3.tosc` (zlib-decompress, ElementTree — see `tools/update_colors.py` for the I/O pattern), find every `control_fader` RADIAL, extract its `x` value `default`, join against the encodings in `lua/enc_map.lua` (parse the `ENC_SEND_MAP` table textually or maintain a small lookup in the script), and print a violations report.
2. Review the report — some defaults may be intentionally non-zero (e.g. VCF CUTOFF at full, EFX levels at 100%). Flag, don't blind-fix; decide per parameter.
3. Apply agreed fixes with a one-shot write script following the `tools/update_colors.py` pattern (string-level or careful ET round-trip; rebuild afterwards and spot-check with `toscbuild.py tree`).

**Acceptance.**
- Audit script runs clean against the rebuilt `.tosc` (no remaining unintentional violations).
- On device: double-tap a signed encoder (e.g. LFO CV offset) → display reads 0 / center; double-tap a unipolar encoder → display reads its agreed default.

**Model:** fast (Composer class) for the audit script; the per-parameter review step needs human judgment regardless of model.

---

### Task 1.5 — Duplicate `assign_xy_mod_status` labels

**Problem.** The layout contains **five** LABEL nodes named `assign_xy_mod_status` inside `assign_group` (tree output): one in the canonical per-slot set (`assign_xy_mod_status`, `assign_effect_knob_status`, `assign_pad_x_status`, `assign_pad_y_status`) plus four trailing duplicates after `assign_section_label`. They look like copy-paste leftovers from when the other three status labels were created. Both `updateAssignDisplay()` (`lua/patch_manager.lua` ~274) and `refreshAssignLabel()` (`lua/root.lua` ~56) use `root:findByName(..., true)`, which returns only the first match — which may or may not be the visible, correctly-positioned node.

**Fix.**
1. Inspect the five nodes' frames and visibility (extend `toscbuild.py tree` output or a scratch ET script) to determine which node actually sits beneath `assign_xy_mod_btn` and is visible.
2. Delete the four stale duplicates from the layout (one-shot script, cf. the historical `tools/rename_retrig_label.py` precedent). If any duplicate turns out to be load-bearing (e.g. positioned under a different button), rename it to its correct `assign_<key>_status` name instead.
3. No Lua change expected — `findByName` becomes unambiguous once names are unique. Verify `ASSIGN_STATUS_LABELS` (`patch_manager.lua` ~264) matches the surviving node names.

**Acceptance.**
- `toscbuild.py tree TB3.tosc | grep assign_.*_status` shows exactly four uniquely-named labels.
- On device: entering assign mode on the XY MOD slot shows "tap encoder" on the label under the XY MOD button; after assigning, the parameter name appears there (not on an invisible duplicate).

**Model:** fast/mid-tier (Composer / Sonnet class). Investigation plus a mechanical layout edit.

---

## Phase 2 — Code-health refactors

Deliberate architectural improvements. **Sequential — one task per session**, each followed by a full build and hardware verification before the next. These rewrite the root chunk's structure; running them concurrently with Phase 1 or each other multiplies risk for no benefit.

### Task 2.1 — Namespace the root chunk

> **✅ Done (2026-06-11, `1bf2298`).** Implemented as specified: `bcr_map.lua` → `BCR`, `patch_manager.lua` → `PatchManager`, `enc_map.lua` → `EncMap`; `root.lua` references only those three (87 references rewritten). Cross-file surface cut from ~20 shared upvalues to 3; ~21 local slots freed. Purely file-local helpers (`REGISTRY`, `applyValue`, `parseSpecial`, the `*_OFF_NAMES` lookups) kept local. The include-order contract in `tb-3/CLAUDE.md` was rewritten to describe the three tables. Build clean (241/241), full hardware regression passed.
>
> **Decision — namespace-table exception.** Namespace tables are otherwise banned in this repo (`sp404-mk2/lua/README.md`, "No Namespace Tables"). The user explicitly approved this single exception: the root chunk is the only place four files genuinely share scope, and the flat-locals approach was pushing the chunk toward Lua 5.1's 200-local limit (a constraint not known when the general ban was stated). Recorded in agent memory (`feedback-lua-no-namespace`); do **not** propagate the pattern to single-node scripts.

**Problem.** The concatenated root chunk (`bcr_map.lua` + `patch_manager.lua` + `enc_map.lua` + `root.lua`, ~2,500 lines) shares top-level locals with no declared ownership and approaches Lua 5.1's 200-local-per-chunk limit. Cross-file linkage is by shared upvalue: re-declaring a name in a later file silently shadows the earlier one.

**Fix.** Each include exposes exactly one top-level local table:

- `bcr_map.lua` → `BCR = { MAP = ..., NRPN_MAP = ..., ... }`
- `patch_manager.lua` → `PatchManager = { parseBlock = ..., PARAM_ID_MAP = ..., ... }`
- `enc_map.lua` → `EncMap = { ENC_SEND_MAP = ..., SW_SEND_MAP = ..., ADDR_TO_ENC = ..., ... }`

`root.lua` references only those three namespaces. This reduces the cross-file surface from ~20 shared locals to 3, makes the include-order contract explicit, and frees local slots.

**Constraints and follow-ups.**
- Include order in `toscbuild.json` is still load-bearing — do not change it.
- The cross-file dependency table in `tb-3/CLAUDE.md` ("Root chunk — include order contract") must be rewritten to describe the three namespace tables.
- `efx_section.lua` is a separate chunk and unaffected, but its duplicated constants (`TB3_CONN`, `BCR_CONN`, `tb3Checksum`, `sendParam`) must remain byte-identical with root — do not "helpfully" namespace those.
- Functions called from TouchOSC callbacks (`init`, `update`, `onReceiveNotify`, `onReceiveMIDI`, `onReceiveOSC`) stay global in `root.lua`.

**Acceptance.** Build succeeds; full regression on hardware: patch dump/restore, BCR1 + BCR2 round-trips (CC and NRPN), assign mode, all patch-grid modes (store/recall/delete/grab/morph), EFX type changes, OSC backup/restore with the desktop preset manager.

**Model:** high-reasoning model with extended thinking (Opus / GPT-Codex class). The shared-upvalue contract, the 200-local limit, and silent-shadowing failure modes make this the riskiest change in the repo. Do not use a fast model.

---

### Task 2.2a — Single source of truth for synthesis parameter data

> **✅ Done (2026-06-12).** `param_defs.lua` added as include #4 (runs first). `bcr_map.lua`, `enc_map.lua`, and `patch_manager.lua` derive their 7 primary tables (`BCR.MAP`, `BCR.NRPN_MAP`, `EncMap.ENC_SEND_MAP`, `EncMap.SW_SEND_MAP`, `PatchManager.PARAM_ID_MAP`, `PatchManager.SW_PARAM_ID_MAP`, and the file-local `REGISTRY`) from `Params.LIST` in `do…end` blocks. All reverse lookups cascade from those. Value-identity harness: PASS (zero diffs across all 15 tables). `luac -p` PASS. Build clean (241/241, -6,576 bytes). `tb-3/CLAUDE.md` include-order contract rewritten. Hardware regression pending.

---

### Task 2.2b — EFX shared defs (try TouchOSC Shared Scripts first)

**Problem.** `PatchManager.EFX_SLOT_OFFSETS_SHARED` / `_SPECIAL` (in `patch_manager.lua`, root chunk) manually mirror the slot layouts in `TYPE_DEFS` (in `efx_section.lua`, a separate per-node chunk). The same EFX data lives in two chunks that cannot see each other; any edit to one without the other causes silent assign-mode or BCR-routing bugs. This is the same class of forced duplication as `tb3Checksum` / `sendParam` / connection constants, which are kept byte-identical between root and `efx_section.lua` only by discipline and "keep in sync" comments.

**New option — TouchOSC Shared Scripts (`require`).** As of ~v1.5.1.255 (well-established by v1.9.x), TouchOSC ships a native shared-library mechanism: a Shared Script included into a control script via the global `require("name")`. This is *exactly* the primitive the old "no shared library mechanism" constraint said didn't exist. **We want to try this first** for 2.2b — a shared `efx_defs` (and potentially a shared `tb3_sysex` for the checksum/sendParam/connection helpers) `require`d by `root`, `efx1_section`, and `efx2_section` would eliminate the duplication at its source rather than mitigating it.

**Scoping caveats (decide the design):** Shared Scripts are *independent chunks* — they **cannot** read the requiring control's `local`s, **cannot** `require` each other, and `require` takes no arguments. The only cross-chunk channels are **globals** and the script's **return value**. So a shared `efx_defs` that other scripts must read either returns its table (`local EfxDefs = require("efx_defs")`) or sets a global. Per-node globals are acceptable here (each node has its own global env), unlike the root chunk where 2.2a deliberately uses shared `local`s — **do not** retrofit 2.2a onto `require`; the no-nested-require rule would force `Params`/`BCR`/`PatchManager`/`EncMap` to become globals for no gain. (The one orthogonal upside of `require` everywhere — each chunk gets its own Lua 200-local budget — is a "when we hit the wall" tool, not a reason to refactor now.)

**Two experiments to run before committing (cheap, decisive):**
1. **Is a Shared Script a `toscbuild`-injectable XML node?** — ✅ **ANSWERED YES (2026-06-12).** A comment-only Shared Script saved from the editor lands in the `.tosc` XML as: `lexml > node[ROOT] > includes > include[]`, each `<include>` = `<name>` CDATA + `<source>` CDATA — *identical encoding to the control scripts we already inject.* It is a single document-level collection attached to the **root node** (first child, before `<properties>`), **not** per-control. The `require("name")` call lives separately in each consumer's `<property script>` value; `<includes>` is just the library storage. Rebuild-safe: toscbuild's injection regex (toscbuild.py:70) targets only `<property type='s'>`/key `script`, so `build` preserves `<includes>` byte-for-byte. **Code-first source-of-truth is preserved** → no dealbreaker.
   **toscbuild enhancement needed (small):** a new injection path writing `lua/shared/<name>.lua` into the `<source>` CDATA of the matching `<include>` (keyed by `<name>`), plus an `extract` counterpart (today's `extract` walks only `<property script>` and would not round-trip shared scripts).
2. **Does a node that `require`s it still load on the deployment device?** — OPEN. Confirm the TouchOSC install on the actual TB-3/BCR rig is ≥ the version that ships `require` (~v1.5.1.255). Hardware check.

**Fallback (if Shared Scripts fail either experiment) — shared `efx_defs.lua` via the existing `include:` mechanism.** Confirmed reachable with no `toscbuild.py` change: the `include:` handler (toscbuild.py:501-507) works for any mapping kind, so `efx_defs.lua` can be injected into *both* the root node and the `efx_section` nodes. Root derives `EFX_SLOT_OFFSETS_SHARED/_SPECIAL` (offsets only — keeps root lean); `efx_section.lua` rebuilds `TYPE_DEFS` from it, resolving display functions by **string key** via a local dispatch table (display fns stay local to `efx_section`; the sp404 `controls_info.lua` pattern).

**Scope guard.** 2.2b is **EFX slot/type defs only** (`EFX_SLOT_OFFSETS_*` ↔ `TYPE_DEFS`). The `tb3Checksum`/`sendParam`/connection-constant duplication is a *separate, smaller* dedup that the Shared Scripts mechanism also enables — do **not** bundle it into 2.2b. If the Shared Scripts route proves out here, spin the SysEx-helper dedup into its own follow-on task to keep each session's hardware-regression surface bounded (the "one Phase-2 task per session" rule).

**Boundary note.** A shared script **cannot** read root's `Params` (2.2a's shared `local`). This is fine: EFX params are *not* in `Params.LIST` (2.2a was synthesis params only), so `efx_defs` is self-contained. Do not try to fold EFX data into `Params.LIST` — different chunk, different scope model.

**Implementation outline (Shared Scripts route — the preferred path):**
1. **toscbuild enhancement.** Add a shared-script injection path: a new `_SOURCE_CDATA_RE` (mirror of the script regex at toscbuild.py:70 but matching `<include><name><![CDATA[<name>]]></name><source><![CDATA[...]]></source>`), and a new `toscbuild.json` mapping kind (e.g. `{"shared": "efx_defs.lua", "include_name": "efx_defs"}`) that injects `lua/shared/efx_defs.lua` into the matching `<include>`'s `<source>`. The placeholder Shared Script must already exist in the `.tosc` (created in the editor) for the regex to find — toscbuild *updates* `<source>`, it does not create `<include>` nodes. Add an `extract` counterpart so shared scripts round-trip to `lua/shared/`. Unit-check with `--dry-run`.
2. **Author `lua/shared/efx_defs.lua`.** Returns one table (e.g. `return { SLOT_OFFSETS_SHARED = {...}, SLOT_OFFSETS_SPECIAL = {...} }`) — the canonical EFX slot-offset data, lifted verbatim from the current `PatchManager.EFX_SLOT_OFFSETS_*`. Pure data, no display fns.
3. **Consume in root.** `patch_manager.lua` (or root): `local EfxDefs = require("efx_defs")`; derive/assign `PatchManager.EFX_SLOT_OFFSETS_SHARED/_SPECIAL` from it. Drop the literal tables.
4. **Consume in `efx_section.lua`.** `local EfxDefs = require("efx_defs")`; rebuild `TYPE_DEFS`'s slot-offset rows from `EfxDefs`, keeping display functions local (string-key dispatch table, sp404 `controls_info.lua` pattern). This removes the `TYPE_DEFS` ↔ `EFX_SLOT_OFFSETS_*` mirror.
5. **Verify.** Value-identity harness (HEAD `EFX_SLOT_OFFSETS_*` + reconstructed `TYPE_DEFS` vs working tree) → `luac -p` on both the root chunk and `efx_section` chunk → `build` → hardware regression.

**Acceptance.** Build succeeds; value-identity-harness discipline for both `EFX_SLOT_OFFSETS_*` and the reconstructed `TYPE_DEFS` (same as 2.2a). Hardware regression: EFX type changes, EFX slots, BCR2 round-trips, assign-mode EFX slots, EFX patch receive.

**Model:** high-reasoning with extended thinking (Opus / GPT-Codex class). Cross-chunk data model + the new Shared Scripts evaluation; subtle display-fn dispatch.

---

### Task 2.2 — Single source of truth for parameter data (original entry, superseded by 2.2a/2.2b)

**Problem.** SysEx address, range, and scaling facts are hand-maintained in at least four places:

| Location | Contents |
|----------|----------|
| `enc_map.lua` | `ENC_SEND_MAP`, `SW_SEND_MAP` |
| `bcr_map.lua` | `BCR1_MAP`, `BCR1_NRPN_MAP`, BCR2 helpers |
| `patch_manager.lua` | `REGISTRY`, `PARAM_ID_MAP`, `EFX_SLOT_OFFSETS_*` |
| `efx_section.lua` | `TYPE_DEFS` per effect |

`EFX_SLOT_OFFSETS_*` manually mirrors the slot layouts in `efx_section.lua` `TYPE_DEFS`; any edit to one without the others causes silent assign-mode or BCR routing bugs.

**Fix.** One canonical parameter table (the sp404 `controls_info.lua` pattern): each row carries address, bits, max, encoding flags, display function key, UI path (`"section,enc"`), BCR CC / NRPN number, and param-assign ID. Derive `ENC_SEND_MAP`, `SW_SEND_MAP`, `BCR1_MAP`/`BCR1_NRPN_MAP`, the reverse `ADDR_TO_*` lookups, `REGISTRY` field lists, and `EFX_SLOT_OFFSETS_*` from it at load time (inside the namespaced modules from Task 2.1).

**Constraints.**
- **Depends on Task 2.1** — namespacing decides where the canonical table and the derivation code live.
- `efx_section.lua` is a separate chunk and cannot read root's table at runtime. Either keep `TYPE_DEFS` as the EFX source and derive `EFX_SLOT_OFFSETS_*` in root from a mirrored copy with a structural comment contract, or move toward build-time codegen (a future `toscbuild.py` enhancement). Prefer the former for now; codegen is out of scope.
- Derivation runs once at chunk load — watch for ordering (the canonical table must be defined before any deriver runs).

**Acceptance.** Build succeeds; the derived tables are value-identical to the previous hand-written ones (write a throwaway comparison dump before deleting the old tables); same hardware regression suite as 2.1.

**Model:** high-reasoning model with extended thinking (Opus / GPT-Codex class). Large mechanical surface with subtle per-row exceptions (NRPN params, `sp="global_tuning"`, standalone buttons, the `saw_enc` collision).

---

### Task 2.3 — Standardize lookup and messaging idioms

**Problem / Fix.** Two consistency passes, mechanical once 2.1/2.2 have settled:

1. Replace global `root:findByName(name, true)` with section-scoped `group.children[name]` wherever a parent group is already in hand. The `saw_enc` name collision (`ring_mod_group` vs `vco_group`) already forced the two-level `ENC_SEND_MAP` key; scoped lookup removes the class of bug. Keep `findByName` only where no scope is available (e.g. top-level section resolution at init).
2. Pick one notify convention — child scripts currently mix `self.parent:notify` relays and direct `root:notify`. Standardize on **direct `root:notify` for root-bound messages** and parent-relay only where the parent transforms the payload. Document the rule in `lua/README.md` and the notify contract table in `tb-3/CLAUDE.md`.

**Acceptance.** Build succeeds; grep shows no remaining unscoped `findByName` calls except documented exceptions; notify contract table in `CLAUDE.md` matches the code; smoke-test all notify paths (encoders, switches, EFX buttons, patch grid, assign mode).

**Model:** mid-tier (Sonnet class). Do last.

---

## Out-of-plan fixes

Issues found and fixed during this work that were not part of the original triage.

### Bank pull/push OSC transfer hung on larger banks — ✅ Fixed (2026-06-11, `1bf2298`)

**Symptom.** Pulling a bank from the PyQt5 preset manager stalled at "Requested bank from TouchOSC…", or returned a bank missing some presets.

**Cause.** Two stacked UDP limits. A full 16-slot bank serialises to ~15 KB, but macOS caps a single UDP datagram at `net.inet.udp.maxdgram` (~9 KB), and `python-osc`'s `BlockingOSCUDPServer` inherits `socketserver.UDPServer.max_packet_size = 8192`, so `recvfrom(8192)` truncated even ~8.5 KB banks → the OSC packet failed to parse → no handler fired → the app hung. The single-datagram design had a hard ~9 KB ceiling. (TouchOSC's send side was correct — the full JSON appeared in its OSC log.)

**Fix.** Chunked, one slot per OSC message so no datagram approaches the limit:
- **Pull (manifest-driven):** app → `/tb3/patchgrid/request_manifest`; root returns `/tb3/patchgrid/manifest` (`{version,name,slots:[keys]}`); app then requests each slot via `/tb3/patchgrid/request_slot` → root replies `/tb3/patchgrid/slot` (`{slot,data}`). Python side is a Qt state machine with a 4 s timeout.
- **Push:** app sends `/tb3/patchgrid/restore_begin` → one `/tb3/patchgrid/restore_slot` per preset → `/tb3/patchgrid/restore_end` (root stages then commits).
- Receive buffer also raised to 65535 defensively.

Replaces the old `/tb3/patchgrid/{request_backup,backup,restore}` addresses. Docs updated in `tb-3/CLAUDE.md` (OSC interface table), the preset-manager README, and the module docstring. Verified end-to-end (wire-level round-trip simulation + hardware).

## Model choice guidance

| Task | Model class | Rationale |
|------|-------------|-----------|
| 1.1 BCR cache staleness | Fast/mid (Composer, Sonnet) | Fully specified small diff; existing correct code to copy from |
| 1.2 EFX type symmetry | Fast/mid (Composer, Sonnet) | One-line formula fix plus verification |
| 1.3 Auto-store | Mid (Sonnet) | Two completion paths + cancellation state |
| 1.4 Defaults audit | Fast (Composer) for tooling; human review of the report | Mechanical script; judgment calls are per-parameter |
| 1.5 Duplicate labels | Fast/mid (Composer, Sonnet) | Investigation + one-shot layout edit |
| 2.1 Namespacing | **High-reasoning with thinking (Opus, GPT-Codex)** | Shared-upvalue contract, 200-local limit, silent shadowing — riskiest change in the repo |
| 2.2a Canonical synth-param table | ✅ **Done** | Value-identical derivers, zero harness diffs |
| 2.2b Shared EFX defs | **High-reasoning with thinking (Opus, GPT-Codex)** | Cross-chunk data model; efx_section isolation; display-fn dispatch |
| 2.3 Idiom standardization | Mid (Sonnet) | Mechanical after 2.1/2.2 |

General rules:
- Phase 1 tasks can run in any order and in cheap sessions — this document carries the context a smaller model needs.
- Phase 2 tasks are **one per session**, sequential (2.1 → 2.2 → 2.3), each gated on a full hardware regression. Never combine a Phase 2 task with other changes in the same session.
- Whatever the model: start every session by reading `tb-3/CLAUDE.md` and this plan's task entry.

---

## Verification appendix

Common steps for every task:

```bash
python3 tools/toscbuild.py build tb-3 --dry-run   # sanity-check the mapping
python3 tools/toscbuild.py build tb-3             # real build
python3 tools/toscbuild.py tree tb-3/TB3.tosc     # spot-check layout edits (1.4, 1.5)
```

Then reload the layout in TouchOSC. **Always rebuild and reload the layout before loading BCR presets** (the NRPN preset and the Lua map are coupled — see `tb-3/CLAUDE.md`).

Hardware checks by task:

| Task | Check |
|------|-------|
| 1.1 | BCR-only edit → store slot → recall reflects edit; desktop Pull Patch reflects edit |
| 1.2 | On-screen type select ↔ BCR type knob round-trips to the same type on both EFX sections |
| 1.3 | Fresh load → single tap on empty slot → slot fills after sync, no second tap |
| 1.4 | Double-tap signed encoder → center/0 display; unipolar → agreed default |
| 1.5 | Assign-mode prompt and assigned-name text appear on the visible XY MOD label |
| 2.1 / 2.2 | Full regression: dump/restore, BCR1 CC + NRPN, BCR2, assign mode, all five patch-grid modes, EFX types, OSC backup/restore |
| 2.3 | Smoke-test every notify path; grep for unscoped `findByName` |
