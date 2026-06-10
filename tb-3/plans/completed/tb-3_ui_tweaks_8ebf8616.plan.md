---
name: TB-3 UI tweaks
overview: "Three UI tweaks to the TB-3 TouchOSC layout: disable the morph encoder until usable, tint stored preset slots by active mode (with grab recoloured to orange), and flip LFO BPM SYNC / RETRIG button labels to black when lit."
todos:
  - id: morph-enc-disable
    content: "root.lua: morph encoder disable/enable state (tag + dim labels), clear stale morph target on mode toggle, gate BCR CC 8"
    status: completed
  - id: slot-mode-colors
    content: "preset_grid.lua + root.lua: mode-coloured filled slots via patch_mode_changed notify"
    status: completed
  - id: grab-orange
    content: "update_colors.py: recolour grab_mode_button to orange and run it"
    status: completed
  - id: retrig-rename
    content: "One-off tool: rename RETRIG overlay name_label to retrig_label in layout"
    status: completed
  - id: sw-label-color
    content: "sw_button.lua: black/white overlay label textColor on toggle"
    status: completed
  - id: build
    content: Rebuild TB3.tosc and verify tree
    status: completed
isProject: false
---

# TB-3 UI Tweaks

> **Status:** Completed 2026-06-10 (`051f965`). Follow-up: *Pick Preset* value label stays white while the encoder is disabled (name label still dims).

## 1. Disable morph encoder when unusable

Enabled only when `patchGridMode == "morph"` **and** `morphTargetSlot ~= nil`.

- [tb-3/lua/root.lua](tb-3/lua/root.lua): add a `updateMorphEncState()` helper that sets `morph_enc.tag = "disabled"` / `""` and dims its `value_label` + `name_label` text colours (reuse the existing `777777FF` dim / `FFFFFFFF` lit pattern from `efx_section.lua`). `pointer.lua` already rejects input when `self.parent.tag == "disabled"` — no change needed there.
- Call the helper from:
  - `broadcastPatchMode()` (mode enter/exit)
  - the `patch_slot_pressed` morph branch (after a target slot is picked)
  - `init()` (encoder starts disabled)
- In the `patch_mode_set` handler, clear `morphTargetSlot` / `morphBaseSnapshot` when entering or leaving morph mode — currently a stale target persists across mode toggles, which would otherwise re-enable the encoder with an old target.
- Gate the `handleBCR1` CC 8 (hardware morph amount) path on the same condition so the BCR encoder can't move the disabled on-screen fader.

## 2. Mode-coloured preset slots + orange grab

When delete / grab / morph mode is active, **filled** slots take the mode colour; empty slots stay grey.

- [tb-3/lua/root.lua](tb-3/lua/root.lua): in `broadcastPatchMode()`, also notify the `preset_grid` group with `("patch_mode_changed", modeStr)`.
- [tb-3/lua/preset_grid.lua](tb-3/lua/preset_grid.lua): track `local currentMode = ""`; on `patch_mode_changed` update it and call `refreshUI()`. In `refreshUI()`, filled slots use:

```lua
local MODE_COLORS = {
  delete = "E70000FF",  -- matches delete_button red
  grab   = "FF9500FF",  -- new orange
  morph  = "00E6FFFF",  -- matches morph_button cyan
}
```

- Recolour `grab_mode_button` from white (0.9, 0.9, 0.9) to orange (1.0, 0.584, 0.0): add it to [tb-3/tools/update_colors.py](tb-3/tools/update_colors.py) (designed to be re-runnable) and run it.

## 3. Black labels on lit BPM SYNC / RETRIG buttons

Both buttons are yellow `sw_button`s in `lfo_group` with white overlay labels (`bpm_sync_label1`/`bpm_sync_label2` in `lfo_rate_enc`; an overlay label in `lfo_cv_offset_enc`).

- Layout fix first: `lfo_cv_offset_enc` has **two** children named `name_label` (the real title at y=89 and the RETRIG overlay at y=126). Write a small one-off script in `tb-3/tools/` (using `tools/tosc_layout_utils.py`) to rename the y=126 one to `retrig_label`, resolving the collision.
- [tb-3/lua/sw_button.lua](tb-3/lua/sw_button.lua): on `x` change (before the `updating` guard, so assign-revert and programmatic patch-receive writes are covered too) and in `init()`, set the textColor of sibling labels `bpm_sync_label1`, `bpm_sync_label2`, `retrig_label` (whichever exist) to black (`000000FF`) when lit, white (`FFFFFFFF`) when off. VCO/PORTA `sw_button`s have none of these siblings, so they are unaffected.

## Build & verify

```bash
python3 tb-3/tools/rename_retrig_label.py   # one-off layout rename
python3 tb-3/tools/update_colors.py         # grab button orange
python3 tools/toscbuild.py build tb-3       # inject updated Lua
python3 tools/toscbuild.py tree tb-3/TB3.tosc  # confirm retrig_label rename
```
