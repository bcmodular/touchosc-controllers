---
name: Launchkey Keyboard Feature Plan
overview: "Bus-attached keyboard subsystem: chromatic + effect-mapped profiles (Resonator, Hyper Reso, Vocoder live), sustain/panic, Launchkey keybed + drum pads on MIDI connection 4. Encoders and Launchkey preset recall deferred. Auto Pitch and Harmony keyboard control dropped as out of scope."
todos:
  - id: design-keyboard-manager
    content: keyboard_manager state model, notify contract, root tag schema
    status: completed
  - id: wire-ui-ownership
    content: keyboard_grab / chromatic buttons, keys_group visibility, bus-themed accents
    status: completed
  - id: implement-midi-routing
    content: Launchkey keybed, pitch, sustain, drum pads → keyboard_manager → SP-404
    status: completed
  - id: implement-sustain-panic
    content: CC64 deferred note-off; panic + auto flush on bus/mode switch
    status: completed
  - id: effect-profile-mapping
    content: Per-FX keyboard profiles; Hyper Reso detail in hyper_reso_keyboard plan
    status: completed
  - id: launchkey-pad-chords-v1
    content: Drum pads → keys_group chord/scale pads via LAUNCHKEY_DRUM_PAD_NOTE_TO_INDEX
    status: completed
  - id: launchkey-pad-preset-recall
    content: Map Launchkey pads to 8-slot preset recall
    status: cancelled
  - id: validate-regression-test
    content: Manual validation matrix; Launchpad/BCR regression check
    status: pending
  - id: deferred-encoders
    content: Launchkey encoder value feedback + screen SysEx
    status: pending
isProject: false
---

# Launchkey 49 MK4 keyboard integration

**Status:** Implemented (v1, 2026). Runtime code: [`keyboard_manager.lua`](../lua/keyboard_manager.lua) (included from [`root.lua`](../lua/root.lua)). Hyper Reso scale/NOTE specifics: [hyper_reso_keyboard_423aa07a.plan.md](hyper_reso_keyboard_423aa07a.plan.md).

## Goals (locked)

- Single keyboard owner: one bus at a time (`single-active-steal`); chromatic mode is mutually exclusive.
- `keys_group` hidden when detached; per-bus **Keyboard grab** claims ownership.
- Launchkey on TouchOSC **MIDI connection 4** (standalone mode; no SP-404 relay).
- Reuse `octave_grid` for octave UI (chromatic octaves 3–4; Hyper Reso octaves 0–4).
- **V1:** keybed + pitch wheel + sustain + Launchkey 8×2 drum pads → chord/scale grid.
- Vocoder **live** notes only when bus 5 + FX 44 (MIDI ch 11); chromatic uses ch 16 (C2–C4).
- **Chromatic** via `chromatic_keyboard_button` in `perform_group` even with no FX loaded.
- Sustain: CC64 hold/release; **panic** sends explicit note-offs for tracked notes; auto-flush on attach/mode/bus/FX change.

## Architecture

```mermaid
flowchart LR
  launchkeyInput[LaunchkeyMIDIIn] --> rootRouter[RootMIDIRouter]
  rootRouter --> keyboardManager[KeyboardManagerState]
  keyboardManager --> busBinding[AttachedBusBinding]
  busBinding --> effectProfile[EffectKeyboardProfile]
  effectProfile --> sp404Out[SP404MIDISend]
  keyboardManager --> keysUi[KeysGroupUI]
  keyboardManager --> launchkeyPads[LaunchkeyDrumPads]
  keyboardManager --> sustainEngine[SustainDeferredNoteOff]
  keyboardManager --> safetyPanic[AllNotesOffSafety]
```

## Code touchpoints

| File | Role |
| ---- | ---- |
| [`root.lua`](../lua/root.lua) | MIDI ingress; forwards Launchkey to `handleKeyboardMidi` |
| [`keyboard_manager.lua`](../lua/keyboard_manager.lua) | State, routing, profiles, sustain/panic, UI sync |
| [`keyboard_grab_button.lua`](../lua/keyboard_grab_button.lua) | `keyboard_attach_bus` / `keyboard_detach_bus` |
| [`chromatic_keyboard_button.lua`](../lua/chromatic_keyboard_button.lua) | `keyboard_attach_chromatic` / detach |
| [`panic_button.lua`](../lua/panic_button.lua) | `keyboard_panic` |
| [`keys.lua`](../lua/keys.lua), [`keyboard_key.lua`](../lua/keyboard_key.lua) | On-screen piano |
| [`octave_button.lua`](../lua/octave_button.lua) | `keyboard_octave_select` |
| [`chord_pad_button.lua`](../lua/chord_pad_button.lua) | Chord/scale pads 1–16 |
| [`control_mapper.lua`](../lua/control_mapper.lua) | Perform faders → `keyboard_perform_cc` |
| [`toscbuild.json`](../toscbuild.json) | All `keys_group` scripts mapped at build time |

## Effect profiles (implemented)

| FX | ID | Keyboard UI | Launchkey pads |
| --- | --- | --- | --- |
| Resonator | 2 | ROOT + 16 chords | 16 chord pads |
| Hyper Reso | 31 | White-key NOTE degrees + scale grid | Scale maj/min + roots ([detail plan](hyper_reso_keyboard_423aa07a.plan.md)) |
| Vocoder | 44 | Scale + 10 chords; **live** keybed on bus 5 | First 10 pads active |
| Auto Pitch | 43 | ~~KEY only~~ | Out of scope — no keyboard control |
| Harmony | 45 | ~~KEY + 10 harmony chords~~ | Out of scope — no keyboard control |

`chordGridMode` on `keys_group.tag`: `hyper_reso_scale` vs `chord_pads`.

## Notify contract

| Notify | Source | Action |
| ------ | ------ | ------ |
| `keyboard_attach_bus` | `keyboard_grab_button` | Attach bus; flush notes; refresh UI |
| `keyboard_detach_bus` | grab off | Detach if current bus |
| `keyboard_attach_chromatic` / `detach` | chromatic button | Chromatic ch16 mode |
| `keyboard_panic` | panic button | Flush tracked notes + sustain off |
| `keyboard_octave_select` | octave grid | Update octave window |
| `keyboard_ui_note` / `keyboard_ui_chord_pad` | on-screen keys/pads | Route to SP-404 |
| `keyboard_perform_cc` | perform faders | Sync keyboard highlights |
| `keyboard_bus_fx_changed` | bus group | Re-profile keyboard UI |

Root tag fields: `keyboardAttachedBus`, `keyboardChromaticAttached`, `keyboardSustainDown` (via `updateKeyboardRootTag`).

## Launchkey constants

- Connection index: **4** (`LAUNCHKEY_CONNECTION_INDEX`)
- Drum pads: channel 10 (0-based 9); map in `LAUNCHKEY_DRUM_PAD_NOTE_TO_INDEX`
- Keybed: channels 1–2 depending on device mode
- Sustain: CC 64 on keybed channels

## Out of scope (v1)

- Launchkey **encoder** integration and screen SysEx feedback.
- Launchkey pads → **preset recall** (pads drive chord/scale grid only; presets stay on Launchpad/TouchOSC grid).
- Alternate pad modes (delete/grab/morph).

## Testing checklist

- [ ] Attach/detach: `keys_group` visibility + bus color theme
- [ ] Chromatic: notes 36–60 on ch16; octave UI 3–4
- [ ] Bus 5 vocoder: full-range live notes + pitch on ch11
- [ ] Effect profiles switch when FX changes on attached bus
- [ ] Sustain hold/release; no stuck notes after bus switch
- [ ] Panic clears held + deferred notes
- [ ] Launchkey drum pads mirror on-screen chord/scale pads
- [ ] No Launchpad/BCR regressions in `root.lua`

## Acceptance criteria

- Exactly one attached bus or chromatic mode; panel hidden when detached.
- Chromatic works with no FX; sustain and panic reliable.
- Vocoder live only on bus 5 + vocoder FX.
- Effect keyboard adapts to FX (16 vs 10 chord slots).
- Launchkey pads select chords/scales per profile; inactive pads ignored.
- Bus/mode switches never leave hanging notes.
