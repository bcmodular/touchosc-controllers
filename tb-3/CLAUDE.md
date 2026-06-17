# TB-3 TouchOSC Controller — Agent Guide

## Navigation rules

- **Never read `.tosc` files directly** — they are zlib-compressed XML blobs that will burn your context window for zero benefit. Use `python3 tools/toscbuild.py tree tb-3/TB3.tosc` to inspect the node hierarchy.
- **Ignore `backups/` and `resources/`** — binary build artifacts. `backups/` holds one `.tosc.bak` per build (133+ files). Neither directory contains source files.
- **Source of truth**: `lua/*.lua` + `toscbuild.json`. The `.tosc` file is the build artifact.

## Directory layout

```
tb-3/
  TB3.tosc              — build output (do not edit directly)
  toscbuild.json        — build manifest: script → node mappings
  lua/                  — Lua source (see script table below)
  preset-manager/       — PyQt5 desktop app for patch backup/restore
  tools/                — layout maintenance scripts (see below)
  plans/                — design docs and this remediation plan
  backups/              — build-tool backups (gitignored)
  resources/            — binary assets (gitignored)
  screenshots/          — layout reference images
```

## Build

```bash
python3 tools/toscbuild.py build tb-3          # inject Lua into TB3.tosc
python3 tools/toscbuild.py build tb-3 --dry-run
python3 tools/toscbuild.py tree tb-3/TB3.tosc  # inspect node hierarchy
python3 tools/toscbuild.py dev tb-3            # watch mode (macOS)
```

See [`lua/README.md`](lua/README.md) for the root chunk include order, the luac parse-check command, and instructions for adding new encoders or synthesis parameters.

## Root chunk — critical constraints

The root node runs a **single concatenated Lua chunk** from five files. Full rationale and execution order are in [`lua/README.md`](lua/README.md#build-pipeline). Two constraints that will silently break things if missed:

**Namespace-table exception.** Module-style namespace tables (`Foo = {}`) are banned everywhere else in this codebase because TouchOSC isolates each node's script. The root chunk is the one place that rationale fails — five files share scope and the flat-locals approach would exhaust the 200-local limit. The four namespace tables (`Params`, `BCR`, `PatchManager`, `EncMap`) are the sanctioned exception; do **not** propagate the pattern to other scripts.

| Namespace table | Declared in | Role |
|-----------------|-------------|------|
| `Params` | `param_defs.lua` | Canonical source of truth — one row per synthesis param; load-only |
| `BCR` | `bcr_map.lua` | `MAP`, `NRPN_MAP` derived from `Params.LIST`; EFX slot/btn helpers |
| `PatchManager` | `patch_manager.lua` | `PARAM_ID_MAP`, `SW_PARAM_ID_MAP` derived from `Params.LIST`; mutable state fields |
| `EncMap` | `enc_map.lua` | `ENC_SEND_MAP`, `SW_SEND_MAP` derived from `Params.LIST`; reverse lookup tables |

**Mutable table fields.** `distType`, `efxCurType`, and `assignedParamIds` are read **and mutated** from `root.lua` as fields on the namespace tables (a scalar `local` could not be shared by reference). Do not re-declare any of the four namespace tables in `root.lua` — a shadowing `local` silently breaks the linkage.

## Connection / channel constants

→ See [`lua/README.md`](lua/README.md#connection-constants-rootlua) for the full table.

`efx_section.lua` duplicates `TB3_CONN` and `BCR_CONN` as local constants — **keep them byte-identical with root.lua**. TouchOSC has no shared-library mechanism; this duplication is forced.

### NRPN on BCR1 (channel 1)

The seven 16-bit params (3× tuning, VCF env depth / cutoff / resonance, accent) plus MORPH AMOUNT are controlled via **NRPN** (param MSB 0, LSB 1–8 — see `BCR.NRPN_MAP` in `bcr_map.lua`). The four BCR1 fixed-row-3 encoders (pos 1,2,3,5) are programmed as NRPN absolute/14 with Min/Max = the raw SysEx range (0–151 tuning, 0–255 others), so the 14-bit data value IS the raw value. NRPN 8 (morph, group-1 pos 8 rotate, 0–1000 → `morphAmount` 0.0–1.0) is address-less and special-cased in the NRPN dispatch and `syncBCR1`; its push stays plain CC 40. Consequences:

- **CC 6/38/98/99 are reserved** on channel 1 (NRPN status bytes) — never map them as plain CCs, and never send them as plain CCs to `BCR_CONNECTION` (the BCR's receive parser would misread them). VCO RING LEVEL/SW moved to CC 17/49 because of this.
- CC 96 (DIST TONE) and CC 100 (GLOBAL TUNING) overlap MIDI-spec Data Increment / RPN LSB — intentional; root's parser only consumes 6/38/98/99.
- Receive path: `nrpnState` machine at the top of `handleBCR1`; dispatches on CC 38, updates `rawSysexBlocks` nibbles and the on-screen fader.
- Feedback path: `sendNRPNToBCR()` (4-message packet) used by `syncBCR1()` and the `enc_moved` mirror via `BCR.ADDR_TO_NRPN`.
- The BCR preset and the `.tosc` build are coupled: **rebuild/reload the layout before loading the new BCR preset** (old Lua + NRPN preset slams tuning params via the old CC 98/99 map entries).

## SysEx protocol

→ See [`lua/README.md`](lua/README.md#sysex-protocol-quick-reference) for the DT1/RQ1 format.

`tb3Checksum` / `sendParam` / connection constants appear in both `root.lua` and `efx_section.lua`. The blocks must stay byte-identical; add a "keep in sync with root.lua" comment if you touch them.

## MIDI value scaling

| Encoding | `bits` / flags | Raw range | UI range |
|----------|---------------|-----------|---------|
| 7-bit unsigned | `bits=7` | 0–127 (or custom `max`) | 0.0–1.0 fader |
| 16-bit nibble-packed | `bits=16` | 0–255 (or custom `max`) | 0.0–1.0 fader |
| Signed offset | `signed=true` | 0–127 | display −64…+63 |
| Bipolar 7-bit | `bipolar=true` | 0–`max` | display ±(max/2) |
| Semitone range | `semitoneRange=true` | 0–23 | display ±1…±24 st |
| Global tuning | `sp="global_tuning"` | CC 104 plain MIDI | lookup table |

`sendFromEntry` / `sendFromEntryFloat` in root.lua implement all these paths; `PatchManager.parseBlock` in patch_manager.lua is the mirror receive path.

## Dual data model — critical design constraint

Root's `rawSysexBlocks` cache stores the last received DT1 block per 8-hex address key (e.g. `"10000000"`). It covers **synthesis blocks only** (LFO, VCO, VCF, VCA, Distortion, Param Assign, etc.). **EFX blocks (`10001000` / `10001200`) are NOT stored in `rawSysexBlocks`.**

EFX state lives in each section's `self.tag` as a JSON byte array (see `efx_section.lua`). `snapshotCurrentPatch()` assembles the full 11-block snapshot by combining `rawSysexBlocks` (9 blocks) with the two EFX section tags.

Both `sendFromEntry()` and `sendFromEntryFloat()` write back to `rawSysexBlocks` after sending SysEx, so BCR-only edits keep patch snapshots and exports up to date (write-back is guarded by `if blk then` — no effect before the first full sync).

## `self.tag` conventions

`efx_section.lua` overloads `self.tag` for two purposes:
- **`"prog"` guard string**: set during all programmatic button value writes. `efx_button.lua` / `efx_chooser_button.lua` check for this string to distinguish user presses from re-entrant programmatic changes. Tag is reset to `""` after the write is done.
- **Raw byte cache**: for EFX sections, `self.tag` stores the raw SysEx bytes of the last received EFX block as a JSON array (e.g. `[0,0,0,...]`). `snapshotCurrentPatch()` reads this.

These two uses are mutually exclusive in time (the `"prog"` guard is cleared before the byte cache is written), but be aware when modifying either path.

## Script responsibilities

→ See [`lua/README.md`](lua/README.md#script-table) for the full script-to-node table.

**Orphaned (not in toscbuild.json — do not use):** `dist_type_button.lua`, `delete_all_presets_button.lua`, `save_to_library_btn.lua`, `morph_amount_fader.lua`, `porta_mode_button.lua`.

## Notify message contract

All cross-element IPC uses `node:notify(key, value)`. The table below covers every key in the system; payload is always a string.

### Root receives (senders → root `onReceiveNotify`)

| Key | Payload format | Sender | Action |
|-----|---------------|--------|--------|
| `enc_moved` | `"section,enc,x"` — section group name, encoder group name, float 0–1 as string | `control_fader.lua` via parent | Lookup `EncMap.ENC_SEND_MAP`; send SysEx; update label; mirror to BCR1 |
| `sw_toggled` | `"section,enc,v"` — v = `"0"` or `"1"` | `sw_button.lua`, `porta_radio_btn.lua` | Lookup `EncMap.SW_SEND_MAP`; send SysEx; mirror to BCR1 |
| `sw_touched` | `"section,enc"` | `sw_button.lua`, `dist_toggle_button.lua` | Assign-mode intercept: assigns parameter, sends `assign_revert` back |
| `enc_touched` | `"section,enc"` | `pointer.lua` on finger-down | Assign-mode intercept: resolves param ID from `PatchManager.PARAM_ID_MAP` or `PatchManager.EFX_SLOT_OFFSETS_*` |
| `porta_mode_set` | `"0"` (LEGATO) or `"1"` (ALWAYS) | `porta_radio_btn.lua` | Send SysEx; broadcast `porta_mode_updated` to both radio buttons |
| `patch_mode_set` | `"delete"` \| `"grab"` \| `"morph"` | mode buttons | Toggle `patchGridMode`; broadcast `patch_mode_changed` |
| `patch_slot_pressed` | `"N"` (slot 1–16) | `preset_grid_slot_btn.lua` | Store / recall / delete / grab / morph depending on `patchGridMode` |
| `patch_slot_released` | `"N"` | `preset_grid_slot_btn.lua` | Grab mode: restore pre-grab snapshot |
| `patch_clear_all` | `""` | *(dead handler — `delete_all_presets_button.lua` deleted)* | Clears all 16 slots |
| `save_to_library` | `""` | *(dead handler — replaced by OSC `/tb3/request_patch_export`)* | Sends `/tb3/backup` OSC |
| `assign_slot_select` | slot key string or `""` | `assign_slot_btn.lua` | Activate / cancel assign mode for that slot |
| `efx_type_select` | `"N,M"` — EFX num, type index (button name == type index; 1=COMP, 2=RING MOD, …) | `efx_chooser_button.lua` | Forward `type_set` to efx section |
| `efx_type_step` | `"N,D"` — EFX num, direction (+1/-1) | on-screen PREV/NEXT buttons | Forward `type_step` to efx section |
| `request_patch_dump` | `1` | `receive_button.lua` | Call `requestPatchDump()` |
| `dist_type_up` / `dist_type_dn` | `""` | *(dead handlers — `dist_type_button.lua` deleted)* | Increments/decrements `PatchManager.distType`; calls undefined `sendDistType()` |
| `efx_type_changed` | `"N,T"` — EFX num, type index | `efx_section.lua` | Update `PatchManager.efxCurType[N]` for assign-mode EFX slot resolution |
| `efx_sw_touched` | `"efxNum,swOff"` | `efx_section.lua` B1 press handler | Assign-mode: assigns EFX SW parameter to pending slot |

### Efx section receives (`efx1_section` / `efx2_section` `onReceiveNotify`)

| Key | Payload format | Sender | Action |
|-----|---------------|--------|--------|
| `type_set` | `"N"` — type index (0-based) | root | Apply type; remap slots; update buttons |
| `type_step` | `"D"` — direction int | root | Step type by D; wrap around MAX_TYPE |
| `type_cc` | CC value string 0–127 | root `handleBCR2` | Convert CC → type index; call `type_set` path |
| `slot_moved` | `"encName,x"` — encoder node name, float string | root `enc_moved` handler | Move slot fader; send SysEx via `sendSlotFromFloat` |
| `slot_cc` | `"slotIdx,ccVal"` | root `handleBCR2` | BCR slot encoder change; scale and send SysEx |
| `btn_press` | `"btnIdx"` or `"btnIdx,bcr"` | `efx_button.lua` / root `handleBCR2` | Activate radio button; send SysEx; sync BCR |
| `patch_data` | hex CSV string of raw SysEx bytes | root `handleTB3SysEx` | Parse incoming EFX block; store in tag; call `applyType` |

### Mode buttons receive (broadcast from root)

| Key | Payload | Receiver | Action |
|-----|---------|----------|--------|
| `patch_mode_changed` | `"delete"` \| `"grab"` \| `"morph"` \| `""` | `delete_button`, `grab_mode_button`, `morph_button`, `preset_grid` | Mode buttons: set lit state (`updating` guard). `preset_grid`: tint filled slot colours by mode |

### Assign slot buttons receive

| Key | Payload | Receiver | Action |
|-----|---------|----------|--------|
| `assign_mode_changed` | active slot key or `""` | `assign_*_btn` nodes | Update lit state |
| `assign_revert` | `""` | `sw_button` / standalone button | Revert visual state after assign-mode intercept |

### Radio buttons receive

| Key | Payload | Receiver | Action |
|-----|---------|----------|--------|
| `porta_mode_updated` | `"0"` or `"1"` | `porta_legato_btn`, `porta_always_btn` | Update lit state |

## Patch grid architecture

→ See [`lua/README.md`](lua/README.md#patch-grid-architecture) for state variables, key helper functions, slot colours, mode button pattern, and slot data format.

## OSC interface (preset manager ↔ TouchOSC)

| Address | Direction | Purpose |
|---------|-----------|---------|
| `/tb3/request_dump` | → root | Trigger full patch dump request |
| `/tb3/request_patch_export` | → root | Root responds with current patch on `/tb3/backup` |
| `/tb3/backup` | root → | JSON snapshot of current patch (11 hex blocks) |
| `/tb3/restore` | → root | Hex CSV SysEx block; root forwards to TB-3 and updates UI |
| `/tb3/patchgrid/request_manifest` | → root | Root responds with bank manifest on `/tb3/patchgrid/manifest` |
| `/tb3/patchgrid/manifest` | root → | `{"version":2,"name":<bank>,"slots":["1","2",…]}` — filled slot keys only |
| `/tb3/patchgrid/request_slot` | → root | arg = slot key string; root responds with `/tb3/patchgrid/slot` |
| `/tb3/patchgrid/slot` | root → | `{"slot":"N","data":{"blocks":[…],"name":"…"}}` — one slot |
| `/tb3/patchgrid/restore_begin` | → root | arg = `{"version":2,"name":<bank>}`; resets the push staging buffer |
| `/tb3/patchgrid/restore_slot` | → root | arg = `{"slot":"N","data":{…}}`; stages one slot |
| `/tb3/patchgrid/restore_end` | → root | Commits the staged bank to the grid (replaces all 16 slots) |

**Why chunked:** a full 16-slot bank is ~15 KB, but macOS caps a single UDP datagram at `net.inet.udp.maxdgram` (~9 KB). Bank pull/push therefore transfer one slot per message (manifest-driven pull, begin/slot/end push) so no datagram approaches the limit. The Python side also raises `socketserver.UDPServer.max_packet_size` to 65535 defensively.

## Tools index

**Reusable:**
- `tools/decode_patch.py` — decode a raw `.syx` file to human-readable parameter values
- `tools/send_patch_osc.py` — send a `.syx` patch file to TouchOSC via OSC `/tb3/restore`
- `tools/update_colors.py` — update button/label colours across the `.tosc` layout
- `tools/fix_value_label_frames.py` — correct value-label frame sizes in the layout

**Historical one-offs (do not re-run):**
- `tools/add_efx_scripts.py` — bootstrapped EFX script injection (superseded by toscbuild)
- `tools/add_efx_button_labels.py` — one-time button label addition pass
- `tools/fix_b_labels_placement.py` — one-time label placement fix
- `tools/rename_retrig_label.py` — renamed duplicate `name_label` → `retrig_label` in `lfo_cv_offset_enc`

## Known design constraints

- **Shared Scripts (`require`) — in use for EFX defs only (Task 2.2b).** TouchOSC ships a native shared-library primitive: a Shared Script included into a control script via the global `require("name")` (since ~v1.5.1.255). Since Task 2.2b, the EFX type/slot/button layout lives in **one** Shared Script, `lua/shared/efx_defs.lua` (`require("efx_defs")` from the root chunk and both EFX sections), ending the old `EFX_SLOT_OFFSETS_*` ↔ `TYPE_DEFS` cross-chunk duplication. Shared Scripts are stored in the `.tosc` `<includes>` collection on the root node and injected code-first by toscbuild's `shared` mapping kind (create-or-update). Semantics: independent chunk — no shared `local`s, no nested `require`, `require` takes no args, cross-chunk sharing only via the script's return value (or globals). This is why it does **not** fit the root chunk's shared-`local` model (2.2a) — do not retrofit `Params`/`BCR`/`PatchManager`/`EncMap` onto `require`.
- **Remaining forced duplication (not yet deduped).** `tb3Checksum`, `sendParam`, and the connection constants are still duplicated between the root chunk and `efx_section.lua`; keep them byte-identical. The Shared Scripts mechanism could dedup these too (a `tb3_sysex` shared script), but that is a deliberately separate follow-on task — not bundled into 2.2b — to keep each session's hardware-regression surface bounded.
- **200-local limit** (Lua 5.1 per-chunk). The concatenated root chunk (~2,500 lines) is approaching this. Avoid adding new top-level locals without removing others.
- **`root:findByName(name, true)`** does a global depth-first search. The `saw_enc` name exists in both `ring_mod_group` and `vco_group` — the `EncMap.ENC_SEND_MAP` two-level key (`"section,enc"`) was added specifically to avoid this collision. Prefer `group.children[name]` for section-scoped lookups.
- **`.claude/settings.local.json`** contains machine-specific absolute paths — leave it in place, it is local config and not committed.
