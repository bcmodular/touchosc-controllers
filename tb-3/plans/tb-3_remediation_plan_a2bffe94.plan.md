---
name: TB-3 Remediation Plan
overview: Clean up dead code, sync all documentation with the actual implementation, add agent-facing docs tuned for Claude Sonnet 4.6, and produce a verified backlog of behavioral issues to review.
todos:
  - id: dead-code
    content: Delete 5 orphaned lua scripts and remove dead handlers/stale comments in root.lua and bcr_map.lua
    status: pending
  - id: claude-md
    content: Create tb-3/CLAUDE.md with architecture, include-order contract, notify message table, and tag conventions
    status: pending
  - id: root-claude
    content: Add TB-3 section/pointer to repo-root CLAUDE.md
    status: pending
  - id: lua-readme
    content: Regenerate lua/README.md script table to match toscbuild.json
    status: pending
  - id: user-readme
    content: Sync tb-3/README.md with actual UI per screenshot (SYNC TO TB-3, morph AMOUNT encoder, drop DELETE ALL, TYPE encoder, add missing sections)
    status: pending
  - id: pm-readme
    content: Update preset-manager/README.md for tabbed UI, button names, and bank format v2
    status: pending
  - id: plans-status
    content: Add divergence/status headers to both plans docs and a tools/ script index
    status: pending
  - id: code-health
    content: Merge mode-toggle buttons into one script, fix accidental globals, mark forced duplication, comment rot pass
    status: pending
  - id: backlog
    content: Write plans/review-backlog.md with behavioral findings and code-health refactor follow-ups
    status: pending
  - id: hygiene
    content: Gitignore tb-3/backups and .tosc.bak files; delete TB3.tosc.bak_naming
    status: pending
  - id: verify
    content: Rebuild with toscbuild.py and verify clean diff and doc/manifest consistency
    status: pending
isProject: false
---

# TB-3 Remediation Plan

## Context

Review of [tb-3](tb-3) found three categories of problems: (1) orphaned/dead code from superseded UI iterations, (2) documentation that describes the old UI rather than the current one, and (3) zero agent-facing guidance — the repo-root `CLAUDE.md` covers only sp404-mk2. Behavioral bugs found during review are captured as a review backlog, not fixed in this pass.

## 1. Dead code removal

Per your answers, all five orphaned scripts are dropped:

- Delete [lua/dist_type_button.lua](tb-3/lua/dist_type_button.lua), [lua/delete_all_presets_button.lua](tb-3/lua/delete_all_presets_button.lua), [lua/save_to_library_btn.lua](tb-3/lua/save_to_library_btn.lua), [lua/morph_amount_fader.lua](tb-3/lua/morph_amount_fader.lua), [lua/porta_mode_button.lua](tb-3/lua/porta_mode_button.lua). None are in `toscbuild.json`; verified `morph_enc` (root.lua ~1040) and `porta_radio_btn.lua` fully replace the fader/toggle paths.
- In [lua/root.lua](tb-3/lua/root.lua): remove the `dist_type_up`/`dist_type_dn` handlers (~1177–1187) which call the **undefined** `sendDistType()`; remove the now-orphaned `save_to_library` handler (~1324) and `patch_clear_all` handler (~1457) if nothing else reaches them; fix stale comments ("Grab / Morph: stubbed" ~1378; `control_fader.lua:15` "silently ignored" claim).
- Remove the empty `BCR2_MAP` placeholder in [lua/bcr_map.lua](tb-3/lua/bcr_map.lua) (~154) or annotate why it's reserved; fix the wrong CC header comment (~37: says CC 79/80 = DIST TYPE, map says CC 79 = DIST COLOR).
- Rebuild with `python3 tools/toscbuild.py build tb-3` and verify a clean diff (script-only changes).

## 2. Agent-facing documentation (Claude Sonnet tuning)

The biggest drag on AI-assisted development is implicit knowledge. Create:

- **`tb-3/CLAUDE.md`** — the primary deliverable. Contents:
  - Architecture summary: root chunk = `bcr_map.lua` + `patch_manager.lua` + `enc_map.lua` + `root.lua` concatenated in that order (shared upvalues like `distType`, `rawSysexBlocks`, `assignedParamIds` depend on this order — currently undocumented and silently breakable).
  - **Notify message contract**: table of all ~25 notify keys with payload formats (`"section,enc,x"`, `"slot,bcr"`, etc.), sender → receiver. This is the IPC backbone and currently requires grepping `onReceiveNotify` across files.
  - `self.tag` conventions: EFX sections overload tag as both `"prog"` guard string and JSON raw-byte cache ([lua/efx_section.lua](tb-3/lua/efx_section.lua) ~613/719/849).
  - Dual data model warning: `rawSysexBlocks` in root excludes EFX blocks; EFX state lives in each section's tag.
  - Build commands, connection constants (Connection 2 = BCR, 6 = TB-3), MIDI value scaling conventions.
- **Repo-root [CLAUDE.md](CLAUDE.md)**: add a short TB-3 section pointing at `tb-3/CLAUDE.md` (currently zero TB-3 coverage).
- **[lua/README.md](tb-3/lua/README.md)**: regenerate the script table to match `toscbuild.json` (10 mapped scripts are missing from it; 2 documented scripts are being deleted; include order is wrong — omits `enc_map.lua`).

## 3. User documentation sync

- **[README.md](tb-3/README.md)** — corrections verified against the current layout screenshot:
  - **SYNC FROM TB-3** label is correct as-is (no rename needed despite the `receive_button` node name).
  - Replace **SAVE TO LIBRARY** with **SYNC TO TB-3** and correct its semantics: pushes the current patch *to* the TB-3, not to the desktop app. Patch export to the desktop app is app-driven (Pull Patch) — move that into the preset-manager section.
  - Morph: it's a **MORPH group with an AMOUNT encoder** (shows `--` when no target), not a fader. Update the mode-buttons table too: only **GRAB MODE** and **DEL. MODE** sit beside the preset grid; morph is armed via the MORPH group, not a third grid mode button.
  - Delete the **DELETE ALL** paragraph (feature dropped).
  - Distortion: TYPE ↑/↓ buttons → **TYPE encoder** (steps through the 25 types).
  - The grid is headed **PRESETS** in the UI — align terminology ("Patch Grid" vs "Presets") with the layout.
  - Add missing sections visible in the layout: **PANEL CONTROLS** (CUTOFF/RESONANCE/ACCENT — mirrors the TB-3's panel encoders via CC), **PARAMETER ASSIGNMENT** (EFX KNOB / PAD X / PAD Y / PAD Z slot-assign buttons with status labels), and **OTHER** (BEND RANGE; PORTAMENTO group with TIME + LEGATO/ALWAYS radios).
  - Add a short contributor section (build command, link to `lua/README.md` and `plans/`).
  - Optionally refresh `screenshots/C06.png` with the updated layout screenshot you provided (saved at `/Users/willellis/.cursor/projects/Users-willellis-Documents-Development-Github-touchosc-controllers-tb-3/assets/Screenshot_2026-06-10_at_18.08.03-72c7ceff-e4dd-4de3-ae3a-f69c471fa388.png`), since the README image predates the current UI.
- **[preset-manager/README.md](tb-3/preset-manager/README.md)**: update to match `preset-manager.py` — Pull Bank / Send Bank / Send Patch button names, tabbed UI (900×560), bank format **v2** (`{"version": 2, "slots": {"1": {"name", "blocks"}}}`), Pull Patch via `/tb3/request_patch_export`.
- **[plans/](tb-3/plans)**: add a status header to both plan docs noting divergences (morph encoder replaced the fader, DELETE ALL / SAVE TO LIBRARY dropped, bank format now v2) so future agents don't treat them as current specs.
- **`tools/`**: add a brief index (in `tb-3/CLAUDE.md` or a small `tools/README.md`) marking `decode_patch.py`, `send_patch_osc.py`, `update_colors.py`, `fix_value_label_frames.py` as reusable and `add_efx_scripts.py`, `add_efx_button_labels.py`, `fix_b_labels_placement.py` as historical one-offs.

## 4. Code health cleanups (this pass)

Low-risk, non-functional improvements to do alongside the dead-code removal:

- **Deduplicate mode-toggle buttons**: [lua/delete_button.lua](tb-3/lua/delete_button.lua), [lua/grab_mode_button.lua](tb-3/lua/grab_mode_button.lua), [lua/morph_button.lua](tb-3/lua/morph_button.lua) are identical except a `MODE` string. Merge into one `mode_button.lua` that derives its mode from `self.name`, mapped via a single `node_names` entry in `toscbuild.json` (same pattern as `porta_radio_btn.lua`).
- **Fix accidental globals**: make `tb3Send7bit` / `tb3Send16bit` ([lua/root.lua](tb-3/lua/root.lua) ~176–192) `local` — root-chunk globals leak into every script environment and can mask typos.
- **Mark forced duplication**: `tb3Checksum` / `sendParam` / connection constants are duplicated between root and [lua/efx_section.lua](tb-3/lua/efx_section.lua) (TouchOSC has no shared-library mechanism). Make the blocks byte-identical and add a "keep in sync with root.lua" header so drift is detectable.
- **Comment rot pass**: fix all comments that contradict the code (grab/morph "stubbed", bcr_map CC header, `control_fader.lua` routing claim). Add a rule to `tb-3/CLAUDE.md`: header comments describe contracts, never implementation status; payload formats documented once at the sender.

## 5. Behavioral review backlog (topics only, no fixes)

Create `tb-3/plans/review-backlog.md` listing the verified findings for later investigation:

- **BCR cache staleness**: `sendFromEntry()` (root.lua ~350) sends SysEx but doesn't update `rawSysexBlocks`, so BCR-only edits leave patch-grid snapshots/exports stale (UI path does update it).
- **BCR tuning range mismatch**: bcr_map uses `max=255` for 16-bit tuning, enc_map/UI uses `max=151` — BCR can send out-of-range values.
- **EFX type encoder asymmetry**: sync sends `floor(typeIdx/MAX_TYPE*127)`, receive decodes `floor(cc/10)` (efx_section.lua ~606 vs ~771) — inconsistent round-trip.
- **Morph interpolates everything**: `applyMorph()` (root.lua ~905) linearly blends all block bytes including types/switches/assign IDs — can produce invalid intermediates.
- **Store-to-empty-slot double press**: when no snapshot exists, the slot press triggers a dump request but doesn't auto-store after sync (root.lua ~1418).
- **Panel CC labels**: `handleTB3CC` (root.lua ~620) hardcodes `floor(x*255)` for CC 16/71/74 regardless of the parameter's actual range/encoding.
- **Data duplication drift risk**: `EFX_SLOT_OFFSETS_*` in patch_manager.lua manually mirrors `TYPE_DEFS` in efx_section.lua; same SysEx addresses also appear in bcr_map, enc_map, and the REGISTRY. Candidate for consolidation/codegen.
- Minor: pointer.lua double-tap edge cases; duplicate `assign_xy_mod_status` label nodes in the layout; unverified flanger HPF / rate / compressor curves (already flagged in plans).

Plus larger **code-health refactors** (deliberate follow-ups, not this pass):

- **Namespace the root chunk**: the concatenated root chunk (`bcr_map` + `patch_manager` + `enc_map` + `root.lua`, ~2,500 lines) communicates via shared top-level locals with no declared ownership, and accumulates toward Lua 5.1's 200-locals-per-scope limit. Adopt a convention where each include exposes exactly one table (`BCR = {...}`, `PatchManager = {...}`) and root references only those namespaces.
- **Single source of truth for parameter data**: SysEx address/range/scaling facts are hand-maintained in 4 places (`enc_map`, `bcr_map`, patch_manager REGISTRY + `EFX_SLOT_OFFSETS_*`, efx_section `TYPE_DEFS`). Consolidate into one data table (sp404's `controls_info.lua` pattern) with the maps derived at init.
- **Standardize lookup/messaging idioms**: replace global `root:findByName(name, true)` searches (already needed a `saw_enc` collision workaround) with section-scoped `group.children[name]` lookups, and pick one of `self.parent:notify` vs `root:notify` as the convention.

## 6. Repo hygiene

- Add `tb-3/backups/` (133 files, 9.5 MB, build tool writes one per build) and `tb-3/*.tosc.bak*` to [.gitignore](.gitignore), mirroring the existing `sp404-mk2/backups/` entry.
- Delete `TB3.tosc.bak_naming` (the build tool's backups supersede it).
- Note in `tb-3/CLAUDE.md` that `.claude/settings.local.json` contains machine-specific absolute paths (leave the file, it's local config).

## Verification

After all edits: `python3 tools/toscbuild.py build tb-3` succeeds, `git status` shows only intended changes, and every script referenced in any README exists in `lua/` and `toscbuild.json`.

## Execution notes (Claude Code Pro plan + Cursor)

Run as **four focused sessions**, `/clear` (or a fresh Cursor chat) between each. Start every session with: "Execute session N of `tb-3_remediation_plan_a2bffe94.plan.md`". The plan file is the persistent state between sessions; one long session will snowball context and trigger auto-compaction right when the risky edits need full fidelity.

**Tool split** — Claude Code (Anthropic $20 plan) and Cursor (Composer) bill against separate subscriptions, so route judgment-heavy work to Sonnet and mechanical work to Composer to preserve the Anthropic quota:

- **Claude Code + Sonnet 4.6**: Session 1's CLAUDE.md authoring (a spec future agents treat as ground truth — prose precision matters) and all of Session 2 (contract verification across the concatenated root chunk; Composer's act-first tuning is riskier where comments lie).
- **Cursor + Composer**: Session 1's hygiene half, Session 3 (corrections are fully specified in Section 3 — little judgment left), and Session 4 (pure search/build/diff loops — Composer is faster with no quality difference).
- Whichever tool starts a session runs the **whole** session including its verification loop; don't split one session across tools.

### Session order and model per phase

- **Session 1 — Section 2 (agent docs) + Section 6 (repo hygiene)**
  - Tool/model: Claude Code + Sonnet 4.6, thinking **off** (default mode — no Tab toggle, no "think" keywords). If splitting, the Section 6 hygiene items can go to a separate Cursor/Composer chat.
  - Do this first: once `tb-3/CLAUDE.md` exists (notify table, include-order contract, tag conventions), every later session inherits that knowledge instead of re-reading `root.lua` (~64 KB) to rediscover it.
  - Include in the CLAUDE.md: "never read `.tosc` files directly — use `python3 tools/toscbuild.py tree`" and ignore `backups/` and `resources/` (binary blobs that torch tokens if read).
- **Session 2 — Section 1 (dead code) + Section 4 (code health)**
  - Tool/model: Claude Code + Sonnet 4.6, thinking **off by default**; escalate **per-prompt** with the "think hard" keyword for exactly two steps: (a) verifying nothing reaches `save_to_library` / `patch_clear_all` before deleting them from `root.lua`, and (b) the mode-button merge (touches notify protocol + `toscbuild.json` together). Do not set a session-wide thinking level — it would apply the budget to every trivial turn.
  - Verify in-session: `python3 tools/toscbuild.py build tb-3` then `git diff` — script-only changes expected.
- **Session 3 — Section 3 (user docs) + Section 5 (review backlog)**
  - Tool/model: Cursor + Composer (or Sonnet if preferred), thinking off. Pure text edits, fully specified in Sections 3 and 5; no code risk. Cheapest session; can batch freely.
- **Session 4 — final verification pass**
  - Tool/model: Cursor + Composer, thinking off. Rebuild, `git status`, cross-check every script name mentioned in any README against `lua/` and `toscbuild.json`. Short session of search/build/diff loops.

### Settings

- **Do not use Opus** — it burns Pro quota ~5x faster and nothing in this plan needs it.
- **Thinking policy**: off by default everywhere; thinking tokens count as output tokens against quota. Escalate per-prompt with keywords only for the two flagged Session 2 steps — never set a session-wide "high" level.
- Pre-approve in `.claude/settings.local.json`: `python3 tools/toscbuild.py build tb-3`, `git diff`, `git status` — verification loops shouldn't stall on permission prompts.
- Add a `.claudeignore` (or CLAUDE.md rule) covering `*.tosc`, `backups/`, `resources/`, `screenshots/` before Session 2.