---
name: TouchOSC BCR morph UI
overview: TouchOSC morph UI + BCR top-row on ch 6 (BCR1, buses 1–4) and ch 7 (BCR2, bus 5 only).
todos:
  - id: morph-core-ui-state
    content: "preset_grid_manager: uiMorph in bus tag, target-select mode, set_morph_* notifies, commit-on-disable"
    status: pending
  - id: morph-touchosc-layout
    content: morph_group on bus1 + sync_bus1_ui_to_buses + lua scripts + toscbuild
    status: pending
  - id: morph-bus-wiring
    content: bus_group_instance + preset_grid relay + applyBusGroupTheme
    status: pending
  - id: morph-bcr-root
    content: root.lua MORPH_BCR_BY_BUS — ch6 buses 1-4, ch7 bus 5; FX selector wins ch6 only
    status: pending
  - id: morph-launchpad-coexist
    content: Quantise down cancels UI morph; README gesture priority
    status: pending
  - id: morph-docs-build
    content: lua/README BCR table; toscbuild; hardware test
    status: pending
isProject: false
---

# TouchOSC + BCR morph controls

Full plan: Cursor `touchosc_bcr_morph_ui_6601d4d4`.

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
