---
name: TouchOSC BCR morph UI
overview: TouchOSC morph UI + BCR top-row on ch 6 (BCR1, buses 1–4) and ch 7 (BCR2, bus 5 only). **Implemented** — hardware validation may remain open.
todos:
  - id: morph-core-ui-state
    content: "preset_grid_manager: morphEnabled/morphTargetPreset in bus tag, set_morph_* notifies, commit-on-disable"
    status: completed
  - id: morph-touchosc-layout
    content: morph_group on buses + morph_amount_fader + morph_choose_button + toscbuild
    status: completed
  - id: morph-bus-wiring
    content: bus_group_instance + preset_grid relay + on_off_button_group morph state
    status: completed
  - id: morph-bcr-root
    content: root.lua MORPH_BCR amount CC on ch 6/7 per bus
    status: completed
  - id: morph-launchpad-coexist
    content: Quantise down cancels UI morph; README gesture priority
    status: completed
  - id: morph-docs-build
    content: lua/README BCR table; toscbuild; hardware test
    status: pending
isProject: false
---

# TouchOSC + BCR morph controls

**Status:** Implemented in [`preset_grid_manager.lua`](../lua/preset_grid_manager.lua), [`morph_amount_fader.lua`](../lua/morph_amount_fader.lua), [`root.lua`](../lua/root.lua).

## BCR mapping (locked)

Turn CC **1–8**; push CC **9–16** (encoder *N* push = **8+N**).

| Bus | Ch | Morph turn | Target turn | Morph push | Target push |
|-----|-----|------------|-------------|------------|-------------|
| 1 | 6 | 1 | 2 | **9** | **10** |
| 2 | 6 | 3 | 4 | **11** | **12** |
| 3 | 6 | 5 | 6 | **13** | **14** |
| 4 | 6 | 7 | 8 | **15** | **16** |
| 5 | 7 | 1 | 2 | **9** | **10** |

Left encoder = morph (on/off + amount); right = target (select mode + step). Pushes advance **+2 per bus** (9/10 → 11/12 → …).
