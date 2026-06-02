---
name: Launchpad Brightness Profiles
overview: Add Launchpad-only brightness profiles so idle/off/press levels can be switched for bright rooms without changing TouchOSC visuals.
todos:
  - id: add-launchpad-profiles
    content: Create 4 Launchpad brightness profiles and getter helpers in launchpad_led.lua
    status: completed
  - id: add-user-button-cycle
    content: Wire Launchpad User button (CC 98) to cycle brightness profiles
    status: completed
  - id: persist-selected-profile
    content: Persist selected profile in root tag and restore on init
    status: completed
  - id: wire-preset-scene-leds
    content: Replace preset/scene Launchpad brightness literals with profile-driven values
    status: completed
  - id: set-default-and-test
    content: Verify profile cycling and Launchpad LED states across all modes
    status: completed
isProject: false
---

# Launchpad-Only Brightness Profiles

## Goal
Introduce configurable Launchpad LED brightness profiles (4 levels) with cycling on Launchpad User button (`CC 98`), while leaving TouchOSC UI brightness logic untouched.

## Scope
- Include only Launchpad LED brightness controls used by:
  - preset grid LEDs
  - scene grid LEDs
  - bus/control button LEDs
- Exclude TouchOSC color scaling (`0.75` factors in preset/scene UI renderers).

## Implementation Plan
- Add a centralized Launchpad brightness config in [`/Users/willellis/Documents/Development/Github/touchosc-controllers/sp404-mk2/lua/launchpad_led.lua`](/Users/willellis/Documents/Development/Github/touchosc-controllers/sp404-mk2/lua/launchpad_led.lua):
  - Define 4-profile table, e.g. `very_dim`, `night`, `normal`, `day`.
  - Add selected profile state and helper getters for:
    - idle brightness
    - on brightness
    - press brightness
    - bus-off brightness
    - empty-press brightness (preset/scene)
- Add Launchpad button-cycle control in [`/Users/willellis/Documents/Development/Github/touchosc-controllers/sp404-mk2/lua/root.lua`](/Users/willellis/Documents/Development/Github/touchosc-controllers/sp404-mk2/lua/root.lua):
  - On `CC 98` press, advance to next profile.
  - Trigger immediate LED refresh so brightness change is visible instantly.
- Persist selected profile in root tag:
  - Save profile key/index under `root.tag` when cycled.
  - Restore on init (fallback to default if unset/invalid).
- Replace hardcoded Launchpad brightness literals/usages with profile-driven values in:
  - [`/Users/willellis/Documents/Development/Github/touchosc-controllers/sp404-mk2/lua/launchpad_led.lua`](/Users/willellis/Documents/Development/Github/touchosc-controllers/sp404-mk2/lua/launchpad_led.lua)
  - [`/Users/willellis/Documents/Development/Github/touchosc-controllers/sp404-mk2/lua/preset_grid_manager.lua`](/Users/willellis/Documents/Development/Github/touchosc-controllers/sp404-mk2/lua/preset_grid_manager.lua)
  - [`/Users/willellis/Documents/Development/Github/touchosc-controllers/sp404-mk2/lua/scene_manager.lua`](/Users/willellis/Documents/Development/Github/touchosc-controllers/sp404-mk2/lua/scene_manager.lua)
- Keep current behavior as baseline by mapping current constants into the `night` profile.

## Defaults
- 4 levels: `very_dim`, `night`, `normal`, `day`.
- `night` starts with current values (`idle=0.18`, `on=1.0`, `press=0.88`, `busOff=0.02`, empty-press `0.35`).
- `normal` and `day` progressively increase idle/off visibility; `very_dim` decreases for dark environments.

## Validation
- Verify Launchpad visual states for both profiles:
  - profile cycling using User button (`CC 98`)
  - persistence across layout reload
  - stored preset/scene idle vs pressed
  - empty slot press flash
  - delete mode red behavior
  - bus off-state dimness
- Confirm no regressions in TouchOSC pad/back-layer rendering (unchanged code paths).