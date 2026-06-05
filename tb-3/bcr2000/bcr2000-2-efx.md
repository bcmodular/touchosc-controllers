# BCR2000 #2 — EFX1 + EFX2

Controls both effect chains. The controller is split symmetrically: left half = EFX1, right half = EFX2.

- **MIDI Channel:** 7 — matches the existing SP-404 BCR2000 preset. Must differ from BCR2000 #1 (channel 6) — **channel is the differentiator between the two units** since both arrive on the same connection.
- **Connection in TouchOSC:** connection 2 — same port as BCR2000 #1 and the SP-404 layout's BCR2000.
- **All encoders:** absolute CC (0–127)
- **Type-select encoder push:** spare (SW moved to dedicated button B1 per side — see below)
- **Buttons:** CC, value 127 = press

---

## Physical Layout

```
Row 0 (macro push-encoders, 8):
  EFX1 side                         EFX2 side
  [TYPE  ][spare ][spare ][spare ]  [TYPE  ][spare ][spare ][spare ]
   rot=type  (CC 3,4 reserved)        rot=type  (CC 7,8 reserved)
   push=spare                         push=spare

Rows 1–3 (4×3 parameter blocks, 12 slots per side):
  EFX1                              EFX2
  [S01   ][S02   ][S03   ][S04   ]  [S01   ][S02   ][S03   ][S04   ]
  [S05   ][S06   ][S07   ][S08   ]  [S05   ][S06   ][S07   ][S08   ]
  [S09   ][S10   ][S11   ][S12   ]  [S09   ][S10   ][S11   ][S12   ]
                                     S12 = spare except for EQ

Row B (dedicated buttons, 8 total, split 4+4):
  EFX1 side            EFX2 side
  [B1][B2][B3][B4]    [B5][B6][B7][B8]
   SW                   SW
  (physical buttons 1–4)   (physical buttons 5–8)
```

**B1 = EFX1 SW, B5 = EFX2 SW** — these are always on/off for the effect chain regardless of effect type. Remaining buttons are effect-specific (see per-effect tables).

---

## CC Assignment

### Row 0 — Type Select

| Control | CC | Function |
|---------|-----|----------|
| EFX1 type encoder rotate | **CC 1** | EFX1 type (0–10: BYPASS/CS/RM/BC/TR/CH/FL/PH/DD/PS/EQ) |
| EFX1 type encoder push | **CC 2** | spare |
| EFX2 type encoder rotate | **CC 5** | EFX2 type (0–9: BYPASS/CS/RM/BC/TR/CH/FL/PH/DD/RV) |
| EFX2 type encoder push | **CC 6** | spare |
| CC 3, 4, 7, 8 | reserved | spare top-row encoders |

### EFX1 Parameter Slots — CC 11–22

CC numbers are fixed. `efx_section.lua` remaps each slot's SysEx target and label when the effect type changes.

| Slot | CC | Grid pos |
|------|----|---------|
| S01 | **CC 11** | Row 1 Col 1 |
| S02 | **CC 12** | Row 1 Col 2 |
| S03 | **CC 13** | Row 1 Col 3 |
| S04 | **CC 14** | Row 1 Col 4 |
| S05 | **CC 15** | Row 2 Col 1 |
| S06 | **CC 16** | Row 2 Col 2 |
| S07 | **CC 17** | Row 2 Col 3 |
| S08 | **CC 18** | Row 2 Col 4 |
| S09 | **CC 19** | Row 3 Col 1 |
| S10 | **CC 20** | Row 3 Col 2 |
| S11 | **CC 21** | Row 3 Col 3 |
| S12 | **CC 22** | Row 3 Col 4 — active only for EQ |

### EFX1 Buttons — CC 31–38

| Btn | CC | Always-on function |
|-----|----|--------------------|
| B1 | **CC 31** | **EFX1 SW toggle** (all effect types) |
| B2 | **CC 32** | Effect-specific (see per-effect tables) |
| B3 | **CC 33** | Effect-specific |
| B4 | **CC 34** | Effect-specific |
| B5 | **CC 35** | Effect-specific |
| B6 | **CC 36** | Effect-specific |
| B7 | **CC 37** | Effect-specific |
| B8 | **CC 38** | Effect-specific |

### EFX2 Parameter Slots — CC 41–52

| Slot | CC | Grid pos |
|------|----|---------|
| S01 | **CC 41** | Row 1 Col 1 |
| S02 | **CC 42** | Row 1 Col 2 |
| S03 | **CC 43** | Row 1 Col 3 |
| S04 | **CC 44** | Row 1 Col 4 |
| S05 | **CC 45** | Row 2 Col 1 |
| S06 | **CC 46** | Row 2 Col 2 |
| S07 | **CC 47** | Row 2 Col 3 |
| S08 | **CC 48** | Row 2 Col 4 |
| S09 | **CC 49** | Row 3 Col 1 |
| S10 | **CC 50** | Row 3 Col 2 |
| S11 | **CC 51** | Row 3 Col 3 |
| S12 | **CC 52** | Row 3 Col 4 — active only for EQ |

### EFX2 Buttons — CC 61–68

| Btn | CC | Always-on function |
|-----|----|--------------------|
| B1 | **CC 61** | **EFX2 SW toggle** (all effect types) — physical button 5 |
| B2 | **CC 62** | Effect-specific |
| B3 | **CC 63** | Effect-specific |
| B4 | **CC 64** | Effect-specific |
| B5 | **CC 65** | Effect-specific |
| B6 | **CC 66** | Effect-specific |
| B7 | **CC 67** | Effect-specific |
| B8 | **CC 68** | Effect-specific |

---

## Per-Effect Slot + Button Maps

**Base addresses:** EFX1 = `10 00 10 00`, EFX2 = `10 00 12 00`.
All offsets below are the same for both (change only the base).

`*` BPM SYNC active: S01 (RATE slot) repurposes as beat-division selector.

**Button convention:** B1 = SW for all effect types (handled universally by `efx_section.lua`). Per-effect button tables below show B2–B8 only.

---

### BYPASS (type 0)
All slots and buttons hidden/disabled. B1 (SW) active to allow re-enabling.

---

### CS — Compressor (type 1)

SW addr: EFX1 `10 00 10 01` | EFX2 `10 00 12 01`

**Slots:**
```
Row 1:  S01=THRESHOLD  S02=RATIO      S03=ATTACK     S04=RELEASE
Row 2:  S05=KNEE       S06=GAIN       S07=BALANCE    (S08 spare)
Row 3:  (all spare)
```

| Slot | Parameter | Hex offset | SysEx range | Notes |
|------|-----------|-----------|-------------|-------|
| S01 | CS THRESHOLD | `+04` | 0–40 | Scale CC 0–127 → 0–40 |
| S02 | CS RATIO | `+05` | 0–13 | Scale CC → 0–13 (1:1.0–1:INF) |
| S03 | CS ATTACK | `+02` | 0–124 | Scale CC 0–127 → 0–124 |
| S04 | CS RELEASE | `+03` | 0–124 | Scale CC 0–127 → 0–124 |
| S05 | CS KNEE | `+06` | 0–9 | Hard, Soft1–9 |
| S06 | CS GAIN | `+07` | 0–80 | Scale CC → 0–80 (−40 to +40 dB) |
| S07 | CS BALANCE | `+08` | 0–100 | −50 to +50 |

**Buttons (B2–B8):**
| Btn | Function | SysEx | Action |
|-----|----------|-------|--------|
| B2 | RATIO: 1:2 | `+05` | Set = 6 |
| B3 | RATIO: 1:4 | `+05` | Set = 8 |
| B4 | RATIO: 1:∞ | `+05` | Set = 13 |
| B5–B8 | spare | | |

---

### RM — Ring Modulator (type 2)

SW addr: `10 00 10 09` / `10 00 12 09`

**Slots:**
```
Row 1:  S01=FREQUENCY  S02=SENS       S03=BALANCE    S04=LEVEL
Row 2:  S05=EQ LOW     S06=EQ HIGH    (S07,S08 spare)
Row 3:  (all spare)
```

| Slot | Parameter | Offset | Range |
|------|-----------|--------|-------|
| S01 | RM FREQUENCY | `+0A` | 0–127 |
| S02 | RM SENS | `+0B` | 0–127 |
| S03 | RM BALANCE | `+0F` | 0–100 (−50 to +50) |
| S04 | RM LEVEL | `+10` | 0–127 |
| S05 | RM EQ LOW | `+0D` | 0–30 (−15 to +15 dB) |
| S06 | RM EQ HIGH | `+0E` | 0–30 |

**Buttons (B2–B8):**
| Btn | Function | SysEx | Action |
|-----|----------|-------|--------|
| B2 | POLARITY toggle | `+0C` | Toggle 0 (UP) ↔ 1 (DOWN) |
| B3–B8 | spare | | |

---

### BC — Bitcrusher (type 3)

SW addr: `10 00 10 11` / `10 00 12 11`

**Slots:**
```
Row 1:  S01=FILTER     S02=SAMP RATE  S03=LEVEL      (S04 spare)
Row 2:  S05=EQ LOW     S06=EQ HIGH    (S07,S08 spare)
Row 3:  (all spare)
```

| Slot | Parameter | Offset | Range |
|------|-----------|--------|-------|
| S01 | BC FILTER | `+12` | 0–127 |
| S02 | BC SAMPLE RATE | `+13` | 0–127 |
| S03 | BC LEVEL | `+17` | 0–127 |
| S05 | BC EQ LOW | `+15` | 0–30 |
| S06 | BC EQ HIGH | `+16` | 0–30 |

**Buttons (B2–B8):** spare.

---

### TR — Tremolo (type 4)

SW addr: `10 00 10 18` / `10 00 12 18`

**Slots:**
```
Row 1:  S01=RATE/DIV*  S02=DEPTH      S03=TYPE       S04=LEVEL
Row 2:  S05=PHASE      S06=SHAPE      (S07,S08 spare)
Row 3:  (all spare)
```

| Slot | Parameter | Offset | Range | Notes |
|------|-----------|--------|-------|-------|
| S01 | TR RATE (or BPM DIV when sync on) | `+1B` (rate) / `+1C` (sync div) | 0–100 / 0–20 | Context-switched by BPM SYNC button |
| S02 | TR DEPTH | `+1E` | 0–100 | |
| S03 | TR TYPE | `+19` | 0–5 | TRI / SAW1 / SAW2 / SIN / SQR / RAND |
| S04 | TR LEVEL | `+20` | 0–100 | |
| S05 | TR PHASE | `+1A` | 0–100 (0–360°) | |
| S06 | TR SHAPE | `+1D` | 0–100 | |

**Buttons (B2–B8):**
| Btn | Function | SysEx | Action |
|-----|----------|-------|--------|
| B2 | BPM SYNC toggle | `+1C` | Toggle 0 (OFF) ↔ last division; switches S01 target |
| B3 | PAN/TRE toggle | `+1F` | Toggle 0 (TREMOLO) ↔ 1 (PAN) |
| B4–B8 | spare | | |

---

### CH — Chorus (type 5)

SW addr: `10 00 10 21` / `10 00 12 21`

**Slots:**
```
Row 1:  S01=RATE/DIV*  S02=DEPTH      S03=PRE DELAY  S04=LEVEL
Row 2:  S05=HPF        S06=LPF        (S07,S08 spare)
Row 3:  (all spare)
```

| Slot | Parameter | Offset | Range |
|------|-----------|--------|-------|
| S01 | CH RATE (or BPM DIV) | `+23` / `+24` | 0–100 / 0–20 |
| S02 | CH DEPTH | `+25` | 0–100 |
| S03 | CH PRE DELAY | `+26` | 0–80 ms |
| S04 | CH LEVEL | `+29` | 0–100 |
| S05 | CH HPF | `+27` | 0–17 (Flat–800 Hz) |
| S06 | CH LPF | `+28` | 0–14 (630 Hz–Flat) |

**Buttons (B2–B8):**
| Btn | Function | SysEx | Action |
|-----|----------|-------|--------|
| B2 | BPM SYNC toggle | `+24` | 0 (OFF) ↔ last division |
| B3 | MODE: MONO | `+22` | Set = 0 |
| B4 | MODE: STEREO1 | `+22` | Set = 1 |
| B5 | MODE: STEREO2 | `+22` | Set = 2 |
| B6–B8 | spare | | |

---

### FL — Flanger (type 6)

SW addr: `10 00 10 2A` / `10 00 12 2A`

**Slots:**
```
Row 1:  S01=RATE/DIV*  S02=DEPTH      S03=MANUAL     S04=RESONANCE
Row 2:  S05=SEPARATN   S06=HPF        S07=EFX LVL    S08=DIRECT LVL
Row 3:  (all spare)
```

| Slot | Parameter | Offset | Range |
|------|-----------|--------|-------|
| S01 | FL RATE (or BPM DIV) | `+2B` / `+2C` | 0–100 / 0–20 |
| S02 | FL DEPTH | `+2D` | 0–100 |
| S03 | FL MANUAL | `+2E` | 0–100 (−50 to +50) |
| S04 | FL RESONANCE | `+2F` | 0–100 |
| S05 | FL SEPARATION | `+30` | 0–100 |
| S06 | FL HPF | `+31` | 0–10 (Flat–800 Hz) |
| S07 | FL EFFECT LEVEL | `+32` | 0–100 |
| S08 | FL DIRECT LEVEL | `+33` | 0–100 |

**Buttons (B2–B8):**
| Btn | Function | SysEx | Action |
|-----|----------|-------|--------|
| B2 | BPM SYNC toggle | `+2C` | 0 (OFF) ↔ last division |
| B3–B8 | spare | | |

---

### PH — Phaser (type 7)

SW addr: `10 00 10 34` / `10 00 12 34`

**Slots:**
```
Row 1:  S01=RATE/DIV*  S02=DEPTH      S03=MANUAL     S04=RESONANCE
Row 2:  S05=EFX LVL    S06=DIRECT LVL (S07,S08 spare)
Row 3:  (all spare)
```

| Slot | Parameter | Offset | Range |
|------|-----------|--------|-------|
| S01 | PH RATE (or BPM DIV) | `+36` / `+37` | 0–100 / 0–20 |
| S02 | PH DEPTH | `+38` | 0–100 |
| S03 | PH MANUAL | `+39` | 0–100 (−50 to +50) |
| S04 | PH RESONANCE | `+3A` | 0–127 |
| S05 | PH EFFECT LEVEL | `+3C` | 0–100 |
| S06 | PH DIRECT LEVEL | `+3D` | 0–100 |

**Buttons (B2–B8):**
| Btn | Function | SysEx | Action |
|-----|----------|-------|--------|
| B2 | BPM SYNC toggle | `+37` | 0 (OFF) ↔ last division |
| B3 | STEP RATE toggle | `+3B` | 0 (OFF) ↔ last non-zero division |
| B4 | PH TYPE: 4STAGE | `+35` | Set = 0 |
| B5 | PH TYPE: 8STAGE | `+35` | Set = 1 |
| B6 | PH TYPE: 12STAGE | `+35` | Set = 2 |
| B7 | PH TYPE: BI-PHASE | `+35` | Set = 3 |
| B8 | spare | | |

---

### DD — Delay (type 8)

SW addr: `10 00 10 3E` / `10 00 12 3E`

**Slots:**
```
Row 1:  S01=TIME/DIV*  S02=TAP TIME   S03=FEEDBACK   S04=LPF
Row 2:  S05=EFX LVL    S06=DIRECT LVL (S07,S08 spare)
Row 3:  (all spare)
```

| Slot | Parameter | Offset | Range |
|------|-----------|--------|-------|
| S01 | DD TIME (or BPM DIV) | `+40` / `+42` | 0–100 ms / 0–20 |
| S02 | DD TAP TIME | `+41` | 0–100 ms |
| S03 | DD FEEDBACK | `+43` | 0–100 |
| S04 | DD LPF | `+44` | 0–14 (630 Hz–Flat) |
| S05 | DD EFFECT LEVEL | `+45` | 0–100 |
| S06 | DD DIRECT LEVEL | `+46` | 0–100 |

**Buttons (B2–B8):**
| Btn | Function | SysEx | Action |
|-----|----------|-------|--------|
| B2 | BPM SYNC toggle | `+42` | 0 (OFF) ↔ last division |
| B3 | TYPE: SINGLE | `+3F` | Set = 0 |
| B4 | TYPE: PAN | `+3F` | Set = 1 |
| B5 | TYPE: STEREO | `+3F` | Set = 2 |
| B6–B8 | spare | | |

---

### PS — Pitch Shifter (type 9, EFX1 only)

SW addr: `10 00 10 47`

**Slots:**
```
Row 1:  S01=PITCH 1    S02=PRE DLY 1  S03=EFX LVL 1  S04=FEEDBACK
Row 2:  S05=PITCH 2    S06=PRE DLY 2  S07=EFX LVL 2  S08=DIRECT LVL
Row 3:  (all spare)
```

| Slot | Parameter | Offset | Range | Notes |
|------|-----------|--------|-------|-------|
| S01 | PS 1 PITCH | `+49` | 0–48 | Scale CC → 0–48 (±2400 cents) |
| S02 | PS 1 PRE DELAY | `+4A` | 0–100 ms | |
| S03 | PS 1 EFX LEVEL | `+4C` | 0–100 | |
| S04 | PS FEEDBACK | `+4B` | 0–100 | |
| S05 | PS 2 PITCH | `+4D` | 0–48 | |
| S06 | PS 2 PRE DELAY | `+4E` | 0–100 ms | |
| S07 | PS 2 EFX LEVEL | `+50` | 0–100 | Note: `+4F` = unidentified, skip |
| S08 | PS DIRECT LEVEL | `+51` | 0–100 | |

**Buttons (B2–B8):**
| Btn | Function | SysEx | Action |
|-----|----------|-------|--------|
| B2 | VOICE: 1MONO | `+48` | Set = 0 |
| B3 | VOICE: 2MONO | `+48` | Set = 1 |
| B4 | VOICE: 2STEREO | `+48` | Set = 2 |
| B5–B8 | spare | | |

---

### EQ — Equalizer (type 10 for EFX1, type 9 for EFX2)

SW addr: EFX1 `10 00 10 53` | EFX2 `10 00 12 53`

All 12 slots used (including S12).

**Slots:**
```
Row 1:  S01=LOW CUT    S02=LOW GAIN   S03=HIGH CUT   S04=HIGH GAIN
Row 2:  S05=LM FREQ    S06=LM Q       S07=LM GAIN    (S08 spare)
Row 3:  S09=HM FREQ    S10=HM Q       S11=HM GAIN    S12=LEVEL
```

| Slot | Parameter | Offset | Range |
|------|-----------|--------|-------|
| S01 | EQ LOW CUT | `+54` | 0–17 (Flat–800 Hz) |
| S02 | EQ LOW GAIN | `+55` | 0–40 (−20 to +20 dB) |
| S03 | EQ HIGH CUT | `+5C` | 0–14 (630 Hz–Flat) |
| S04 | EQ HIGH GAIN | `+5D` | 0–40 |
| S05 | EQ LOW MID FREQ | `+56` | 0–27 (20 Hz–10 kHz) |
| S06 | EQ LOW MID Q | `+57` | 0–5 (0.5/1/2/4/8/16) |
| S07 | EQ LOW MID GAIN | `+58` | 0–40 |
| S09 | EQ HIGH MID FREQ | `+59` | 0–27 |
| S10 | EQ HIGH MID Q | `+5A` | 0–5 |
| S11 | EQ HIGH MID GAIN | `+5B` | 0–40 |
| S12 | EQ LEVEL | `+5E` | 0–40 (−20 to +20 dB) |

**Buttons (B2–B8):** spare.

---

### RV — Reverb (type 9, EFX2 only)

SW addr: `10 00 12 47`

**Slots:**
```
Row 1:  S01=TIME       S02=PRE DELAY  S03=DENSITY    S04=SPRING SNS
Row 2:  S05=HPF        S06=LPF        S07=EFX LVL    S08=DIRECT LVL
Row 3:  (all spare)
```

| Slot | Parameter | EFX2 offset | Range |
|------|-----------|-------------|-------|
| S01 | RV TIME | `+49` | 0–99 (0–9.9 s) |
| S02 | RV PRE DELAY | `+4A` | 0–100 ms |
| S03 | RV DENSITY | `+4D` | 0–10 |
| S04 | RV SPRING SENS | `+50` | 0–100 |
| S05 | RV HPF | `+4B` | 0–17 (Flat–800 Hz) |
| S06 | RV LPF | `+4C` | 0–14 (630 Hz–Flat) |
| S07 | RV EFFECT LEVEL | `+4E` | 0–100 |
| S08 | RV DIRECT LEVEL | `+4F` | 0–100 |

**Buttons (B2–B8) — one per reverb type:**
| Btn | CC (EFX2) | Type | Sets `10 00 12 48` = |
|-----|-----------|------|----------------------|
| B2 | CC 62 | AMBIENT | 0 |
| B3 | CC 63 | ROOM | 1 |
| B4 | CC 64 | HALL 1 | 2 |
| B5 | CC 65 | HALL 2 | 3 |
| B6 | CC 66 | PLATE | 4 |
| B7 | CC 67 | SPRING | 5 |
| B8 | CC 68 | MODULATION | 6 |

---

## Implementation Notes

**SW handling:** B1 (CC31 for EFX1) and B1 (CC61 for EFX2) are the universal on/off buttons for each chain. `efx_section.lua` handles `btn_press = 1` as a SW toggle. The encoder push (CC2 / CC6) is spare. The SW SysEx address varies by effect type and is looked up by `efx_section.lua` at runtime.

**Value scaling in `bcr_map.lua`:** BCR2000 CCs arrive as 0–127. Parameters with narrower ranges (e.g. CS RATIO 0–13, EQ Q 0–5, TR TYPE 0–5) must be scaled: `sysex_val = math.floor(cc_val / 127 * max_val + 0.5)`.

**BPM SYNC dual-mode:** When BPM SYNC is toggled on, `efx_section.lua` switches slot S01's SysEx address from the RATE offset to the BPM SYNC offset (and updates the display label). The CC number for S01 never changes.

**Button momentary vs toggle:** Type-select buttons (CS RATIO shortcuts, CH MODE, DD TYPE, PS VOICE, RV TYPE, PH TYPE) write a fixed value to a fixed address. BPM SYNC and PAN/TRE buttons toggle between stored values. STEP RATE likewise.

**EFX2 type numbering:** EFX2 type 9 = RV (Reverb); EFX1 type 9 = PS (Pitch Shifter). EFX2 has no PS; EFX1 has no RV.
