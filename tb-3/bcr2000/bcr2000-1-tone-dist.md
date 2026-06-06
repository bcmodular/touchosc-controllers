# BCR2000 #1 — Tone + Dist

Controls the core TB-3 synthesis engine and distortion section.

- **MIDI Channel:** 1 — BCR2000 #2 is on channel 2; channel alone differentiates the two units.
- **Connection in TouchOSC:** connection 2.
- **Preset:** same BC Manager template as BCR2000 #2, set to channel 1.
- **All encoders:** absolute CC (0–127)
- **Push-encoder pushes:** CC with value 127 = down, 0 = up (toggle on rising edge in Lua)
- **Buttons:** CC with value 127 = press

---

## BC Manager Preset Layout (bottom to top)

```
CC 97–104  Fixed encoder row 3: Tuning + VCF modulation + Dist dry
CC 89– 96  Fixed encoder row 2: VCF envelope + critical params
CC 81– 88  Fixed encoder row 1: VCA envelope + Dist character
CC 65– 80  Dedicated buttons (2 rows × 8): only CC71/72/79/80 used
CC 49– 64  Encoder Group 4 push  (unused)
CC 41– 48  Encoder Group 2 push
CC 33– 40  Encoder Group 1 push
CC 17– 32  Encoder Group 3/4 rotate (unused)
CC  9– 16  Encoder Group 2 rotate
CC  1–  8  Encoder Group 1 rotate
```

Encoder Group 1 (CC 1–8 / CC 33–40) and Group 2 (CC 9–16 / CC 41–48) are the
two active virtual encoder groups. Pressing the BCR2000 group button switches
the physical top-row encoders between these two CC ranges. The fixed rows
(CC 81–104) and dedicated buttons always send the same CCs regardless of group.

---

## CC Assignment Table

### Encoder Group 1 — VCO (rotate CC 1–8, push CC 33–40)

| Col | Rotate CC | Push CC | Rotate function | SysEx (rotate) | Push function | SysEx (push) |
|-----|-----------|---------|-----------------|----------------|---------------|--------------|
| 1 | **CC 1** | **CC 33** | VCO SAW LEVEL | `10 00 08 00` | VCO SAW SW | `10 00 08 08` |
| 2 | **CC 2** | **CC 34** | VCO SQR LEVEL | `10 00 08 01` | VCO SQR SW | `10 00 08 09` |
| 3 | **CC 3** | **CC 35** | VCO SIN LEVEL | `10 00 08 04` | VCO SIN SW | `10 00 08 0A` |
| 4 | **CC 4** | **CC 36** | VCO WHITE LEVEL | `10 00 08 05` | VCO WHITE SW | `10 00 08 0B` |
| 5 | **CC 5** | **CC 37** | VCO PINK LEVEL | `10 00 08 06` | VCO PINK SW | `10 00 08 0C` |
| 6 | **CC 6** | **CC 38** | VCO RING LEVEL | `10 00 08 07` | VCO RING SW | `10 00 08 0D` |
| 7 | **CC 7** | **CC 39** | VCO LFO DEPTH | `10 00 00 08` | — spare | — |
| 8 | **CC 8** | **CC 40** | PATCH VOLUME | `10 00 0C 04` | — spare | — |

### Encoder Group 2 — LFO (rotate CC 9–16, push CC 41–48, Dope Robot ordering)

| Col | Rotate CC | Push CC | Rotate function | SysEx (rotate) | Push function | SysEx (push) |
|-----|-----------|---------|-----------------|----------------|---------------|--------------|
| 1 | **CC 9** | **CC 41** | LFO RATE | `10 00 00 00` | BPM SYNC | `10 00 00 0B` |
| 2 | **CC 10** | **CC 42** | LFO CV OFFSET | `10 00 00 06` | RETRIGGER | `10 00 00 0C` |
| 3 | **CC 11** | CC 43 spare | LFO DELAY | `10 00 00 01` | — | — |
| 4 | **CC 12** | CC 44 spare | WAVE TRI | `10 00 00 04` | — | — |
| 5 | **CC 13** | CC 45 spare | WAVE SAW | `10 00 00 02` | — | — |
| 6 | **CC 14** | CC 46 spare | WAVE SQR | `10 00 00 03` | — | — |
| 7 | **CC 15** | CC 47 spare | WAVE SIN | `10 00 00 05` | — | — |
| 8 | **CC 16** | CC 48 spare | WAVE S&H | `10 00 00 07` | — | — |

### Dedicated Buttons (CC 65–80) — right-aligned in BC Manager layout

| CC | Function | SysEx | Notes |
|----|----------|-------|-------|
| **CC 71** | DIST ON/OFF | `10 00 0E 00` | Toggle |
| **CC 72** | DIST COLOR | `10 00 0E 07` | Toggle |
| **CC 79** | DIST TYPE ↑ | `10 00 0E 01` | Momentary — Lua increments (0–24) |
| **CC 80** | DIST TYPE ↓ | `10 00 0E 01` | Momentary — Lua decrements |
| CC 65–70, 73–78 | spare | | |

### Fixed Encoder Row 1 — VCA + Distortion character (CC 81–88)

| CC | Function | SysEx addr | Type |
|----|----------|------------|------|
| **CC 81** | VCA ATTACK | `10 00 0C 00` | 7-bit |
| **CC 82** | VCA DECAY | `10 00 0C 01` | 7-bit |
| **CC 83** | VCA SUSTAIN | `10 00 0C 02` | 7-bit |
| **CC 84** | VCA RELEASE | `10 00 0C 03` | 7-bit |
| **CC 85** | VCA LFO DEPTH | `10 00 00 0A` | 7-bit (signed¹) |
| **CC 86** | DIST DRIVE | `10 00 0E 02` | 7-bit (0–120) |
| **CC 87** | DIST BOTTOM | `10 00 0E 03` | 7-bit (0=−50, 100=+50) |
| **CC 88** | DIST TONE | `10 00 0E 04` | 7-bit (0=−50, 100=+50) |

### Fixed Encoder Row 2 — VCF (screen order: CUTOFF first) (CC 89–96)

| CC | Function | SysEx addr | Type |
|----|----------|------------|------|
| **CC 89** | VCF CUTOFF | `10 00 0A 00/01` | **16-bit** (0–255) |
| **CC 90** | VCF RESONANCE | `10 00 0A 02/03` | **16-bit** (0–255) |
| **CC 91** | VCF ATTACK | `10 00 0A 06` | 7-bit |
| **CC 92** | VCF DECAY | `10 00 0A 07` | 7-bit |
| **CC 93** | VCF SUSTAIN | `10 00 0A 08` | 7-bit |
| **CC 94** | VCF RELEASE | `10 00 0A 09` | 7-bit |
| **CC 95** | ACCENT LEVEL | `10 00 14 0E/0F` | **16-bit** (0–255) |
| **CC 96** | DIST EFFECT LEVEL | `10 00 0E 05` | 7-bit (0–100) |

### Fixed Encoder Row 3 — Tuning + VCF modulation (CC 97–104)

| CC | Function | SysEx addr | Type | Notes |
|----|----------|------------|------|-------|
| **CC 97** | SAW TUNING | `10 00 02 02/03` | **16-bit** (bipolar²) | CV offset SAW pitch |
| **CC 98** | SQR TUNING | `10 00 02 00/01` | **16-bit** (bipolar²) | CV offset SQR pitch |
| **CC 99** | RING+SIN TUNING | `10 00 02 04/05` | **16-bit** (bipolar²) | CV offset RING pitch |
| **CC 100** | GLOBAL TUNING | — | MIDI CC 104 | No SysEx; plain CC 104 to TB-3 CH2 |
| **CC 101** | VCF ENV DEPTH | `10 00 0A 04/05` | **16-bit** (0–255) | |
| **CC 102** | VCF KEY FOLLOW | `10 00 0A 0A` | 7-bit | |
| **CC 103** | VCF LFO DEPTH | `10 00 00 09` | 7-bit (signed¹) | |
| **CC 104** | DIST DRY LEVEL | `10 00 0E 06` | 7-bit (0–100) | |

---

## Portamento (TouchOSC-only)

Not mapped to any BCR2000 encoder. Controlled via the `portamento_group` section:
- PORTAMENTO SW: `10 00 14 00` — sw_button in porta_time_enc group
- PORTAMENTO TIME: `10 00 14 01` — encoder
- PORTAMENTO MODE: `10 00 14 02` — two radio buttons: **LEGATO** (0) / **ALWAYS** (1)
- BENDER RANGE: `10 00 14 03` — pitch_bend_range_enc (0–17 semitones)

---

¹ Signed offset-encode: raw 64 = 0, 0 = −64, 127 = +63.

² Bipolar 16-bit: raw 0–255, centre 128 = 0. Display shows −128…+127.
