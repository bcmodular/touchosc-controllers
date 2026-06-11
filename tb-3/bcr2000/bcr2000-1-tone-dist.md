# BCR2000 #1 — Tone + Dist

Controls the core TB-3 synthesis engine and distortion section.

Regenerated from `lua/bcr_map.lua` (`BCR1_MAP` / `BCR1_NRPN_MAP`) — that file is
the source of truth; keep this doc in sync with it.

- **MIDI Channel:** 1 — BCR2000 #2 is on channel 2; channel alone differentiates the two units.
- **Connection in TouchOSC:** connection 2.
- **Encoders:** absolute CC (0–127), except the four NRPN encoders (absolute/14, raw-value range) and morph (NRPN, 0–1000).
- **Push-encoder pushes / buttons:** CC in BCR "Toggle On" mode — 127 = latched on, 0 = off.

## Reserved / spec-overlap CCs (channel 1)

| CC | Status |
|----|--------|
| **6 / 38** | RESERVED — NRPN Data Entry MSB/LSB. Never assign as plain CC. (VCO RING LEVEL/SW moved to CC 17/49 because of this.) |
| **98 / 99** | RESERVED — NRPN Param LSB/MSB. Never assign as plain CC. |
| 96 | DIST TONE — overlaps MIDI-spec Data Increment; intentional (root's parser only consumes 6/38/98/99) |
| 100 | GLOBAL TUNING — overlaps MIDI-spec RPN LSB; intentional |
| 97, 101 | Unassigned (spec Data Decrement / RPN MSB) — keep free |

---

## BC Manager Preset Layout (bottom to top)

```
CC 97–104  Fixed encoder row 3: Tuning (NRPN) + VCF modulation + Dist levels
CC 89– 96  Fixed encoder row 2: Patch vol + VCF envelope + Dist character
CC 81– 88  Fixed encoder row 1: VCA envelope + Dist drive/type
CC 65– 80  Dedicated buttons (2 rows × 8): only CC 71/79 used
CC 49      Encoder Group 3 push slot 1: VCO RING SW (rest of 49–64 unused)
CC 41– 48  Encoder Group 2 push
CC 33– 40  Encoder Group 1 push
CC 17      Encoder Group 3 rotate slot 1: VCO RING LEVEL (rest of 17–32 unused)
CC  9– 16  Encoder Group 2 rotate
CC  1–  8  Encoder Group 1 rotate (pos 6 → CC 17; pos 8 → NRPN 8)
```

Encoder Group 1 and Group 2 are the two active virtual encoder groups; the
group button switches the physical top-row encoders between them. The fixed
rows and dedicated buttons always send the same messages regardless of group.

---

## Assignment Tables

### Encoder Group 1 — VCO + Morph (rotate CC 1–8, push CC 33–40)

| Col | Rotate | Push | Rotate function | SysEx (rotate) | Push function | SysEx (push) |
|-----|--------|------|-----------------|----------------|---------------|--------------|
| 1 | **CC 1** | **CC 33** | VCO SAW LEVEL | `10 00 08 00` | VCO SAW SW | `10 00 08 08` |
| 2 | **CC 2** | **CC 34** | VCO SQR LEVEL | `10 00 08 01` | VCO SQR SW | `10 00 08 09` |
| 3 | **CC 3** | **CC 35** | VCO SIN LEVEL | `10 00 08 04` | VCO SIN SW | `10 00 08 0A` |
| 4 | **CC 4** | **CC 36** | VCO WHITE LEVEL | `10 00 08 05` | VCO WHITE SW | `10 00 08 0B` |
| 5 | **CC 5** | **CC 37** | VCO PINK LEVEL | `10 00 08 06` | VCO PINK SW | `10 00 08 0C` |
| 6 | **CC 17**³ | **CC 49**³ | VCO RING LEVEL | `10 00 08 07` | VCO RING SW | `10 00 08 0D` |
| 7 | **CC 7** | CC 39 spare | VCO LFO DEPTH | `10 00 00 08` (signed¹) | — | — |
| 8 | **NRPN 8**⁴ | **CC 40** | MORPH AMOUNT (0–1000) | — layout-internal | MORPH ON/OFF | — layout-internal |

### Encoder Group 2 — LFO (rotate CC 9–16, push CC 41–48, Dope Robot ordering)

| Col | Rotate | Push | Rotate function | SysEx (rotate) | Push function | SysEx (push) |
|-----|--------|------|-----------------|----------------|---------------|--------------|
| 1 | **CC 9** | **CC 41** | LFO RATE | `10 00 00 00` | BPM SYNC | `10 00 00 0B` |
| 2 | **CC 10** | **CC 42** | LFO CV OFFSET | `10 00 00 06` | RETRIGGER | `10 00 00 0C` |
| 3 | **CC 11** | CC 43 spare | LFO DELAY | `10 00 00 01` | — | — |
| 4 | **CC 12** | CC 44 spare | WAVE TRI | `10 00 00 04` | — | — |
| 5 | **CC 13** | CC 45 spare | WAVE SAW | `10 00 00 02` | — | — |
| 6 | **CC 14** | CC 46 spare | WAVE SQR | `10 00 00 03` | — | — |
| 7 | **CC 15** | CC 47 spare | WAVE SIN | `10 00 00 05` | — | — |
| 8 | **CC 16** | CC 48 spare | WAVE S&H | `10 00 00 07` | — | — |

### Dedicated Buttons (CC 65–80)

| CC | Function | SysEx | Notes |
|----|----------|-------|-------|
| **CC 71** | DIST ON/OFF | `10 00 0E 00` | Toggle |
| **CC 79** | DIST COLOR | `10 00 0E 07` | Toggle |
| CC 65–70, 72–78, 80 | spare | | |

### Fixed Encoder Row 1 — VCA + Distortion drive/type (CC 81–88)

| CC | Function | SysEx addr | Type |
|----|----------|------------|------|
| **CC 81** | VCA ATTACK | `10 00 0C 00` | 7-bit |
| **CC 82** | VCA DECAY | `10 00 0C 01` | 7-bit |
| **CC 83** | VCA SUSTAIN | `10 00 0C 02` | 7-bit |
| **CC 84** | VCA RELEASE | `10 00 0C 03` | 7-bit |
| **CC 85** | VCA LFO DEPTH | `10 00 00 0A` | 7-bit (signed¹) |
| CC 86 | spare | | |
| **CC 87** | DIST DRIVE | `10 00 0E 02` | 7-bit (0–120) |
| **CC 88** | DIST TYPE | `10 00 0E 01` | 7-bit (0–24; special-cased in root.lua) |

### Fixed Encoder Row 2 — Patch vol + VCF envelope + Dist character (CC 89–96)

| CC | Function | SysEx addr | Type |
|----|----------|------------|------|
| **CC 89** | PATCH VOLUME | `10 00 0C 04` | 7-bit |
| **CC 90** | VCF ATTACK | `10 00 0A 06` | 7-bit |
| **CC 91** | VCF DECAY | `10 00 0A 07` | 7-bit |
| **CC 92** | VCF SUSTAIN | `10 00 0A 08` | 7-bit |
| **CC 93** | VCF RELEASE | `10 00 0A 09` | 7-bit |
| **CC 94** | VCF LFO MOD | `10 00 00 09` | 7-bit (signed¹) |
| **CC 95** | DIST BOTTOM | `10 00 0E 03` | 7-bit (0=−50, 100=+50) |
| **CC 96** | DIST TONE | `10 00 0E 04` | 7-bit (0=−50, 100=+50) |

### Fixed Encoder Row 3 — Tuning + VCF modulation + Dist levels (positions 1–8)

Positions 1, 2, 3 and 5 are **NRPN encoders** (absolute/14, channel 1, Min/Max
= raw range below). The remaining positions stay plain CC.

| Pos | Message | Function | SysEx addr | Range / type |
|-----|---------|----------|------------|--------------|
| 1 | **NRPN 1** | SAW TUNING | `10 00 02 00/01` | 0–151 (bipolar²) |
| 2 | **NRPN 2** | SQR TUNING | `10 00 02 02/03` | 0–151 (bipolar²) |
| 3 | **NRPN 3** | RING+SIN TUNING | `10 00 02 04/05` | 0–151 (bipolar²) |
| 4 | **CC 100** | GLOBAL TUNING | — | No SysEx; plain CC 104 to TB-3 |
| 5 | **NRPN 4** | VCF ENV DEPTH | `10 00 0A 04/05` | 0–255 (16-bit) |
| 6 | **CC 102** | VCF KEY FOLLOW | `10 00 0A 0A` | 7-bit |
| 7 | **CC 103** | DIST EFFECT LEVEL | `10 00 0E 05` | 7-bit (0–100) |
| 8 | **CC 104** | DIST DRY LEVEL | `10 00 0E 06` | 7-bit (0–100) |

NOTE: spec labels the tuning addresses SQR=`00`, SAW=`02`, but hardware SysEx
capture confirms the reverse (SAW=`00`, SQR=`02`) — tables above follow hardware.

### NRPN-only parameters (no BCR encoder)

Defined in `BCR1_NRPN_MAP` for use from an external NRPN controller (channel 1);
they receive feedback packets like the rest. On-screen they live in
`panel_controls_group`.

| NRPN | Function | SysEx addr | Range |
|------|----------|------------|-------|
| 5 | VCF CUTOFF | `10 00 0A 00/01` | 0–255 |
| 6 | VCF RESONANCE | `10 00 0A 02/03` | 0–255 |
| 7 | ACCENT LEVEL | `10 00 14 0E/0F` | 0–255 |

---

## Portamento (TouchOSC-only)

Not mapped to any BCR2000 encoder. Controlled via the `portamento_group` section:
- PORTAMENTO SW: `10 00 14 00` — sw_button in porta_time_enc group
- PORTAMENTO TIME: `10 00 14 01` — encoder
- PORTAMENTO MODE: `10 00 14 02` — two radio buttons: **LEGATO** (0) / **ALWAYS** (1)
- BENDER RANGE: `10 00 14 03` — pitch_bend_range_enc (0–17 semitones)

---

¹ Signed offset-encode: raw 64 = 0, 0 = −64, 127 = +63.

² Bipolar tuning: raw 0–151, centre 127 = 0. Display shows −127…+24 (no audible
effect above raw 151; matches the on-screen encoder cap).

³ Physical encoder group 1, position 6 — rotate/push retargeted from CC 6/38,
which are reserved as NRPN Data Entry bytes.

⁴ Morph amount has no SysEx address: 0–1000 maps to `morphAmount` 0.0–1.0 in
root.lua. Only active when morph mode is on and a target preset is selected.
