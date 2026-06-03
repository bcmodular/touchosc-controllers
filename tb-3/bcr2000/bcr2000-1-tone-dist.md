# BCR2000 #1 — Tone + Dist

Controls the core TB-3 synthesis engine and distortion section.

- **MIDI Channel:** 3
- **Connection in TouchOSC:** connection 2 (i.e. `connections[2] == true` in `onReceiveMIDI`)
- **All encoders:** absolute CC (0–127)
- **Push-encoder pushes:** CC with value 127 = down, 0 = up (toggle on rising edge in Lua)
- **Buttons:** CC with value 127 = press (latching or momentary as noted)

---

## Physical Layout

```
Row 0 (macro push-encoders, 8):
  [SAW   ][SQR   ][SIN   ][WHITE ][PINK  ][PORTA ][LFO   ][RING  ]
   lev/SW  lev/SW  lev/SW  lev/SW  lev/SW  time/SW  VCO dep  lev/SW

Row B (dedicated buttons, 8):
  [DIST  ][COLOR ][      ][      ][      ][PORTA ][DIST  ][DIST  ]
   ON/OFF         spare   spare   spare   MODE    TYPE ↑   TYPE ↓

Row 1 (encoders, 8):
  [VCA A ][VCA D ][VCA S ][VCA R ][VCALFO][DRIVE ][BOTTOM][TONE  ]

Row 2 (encoders, 8):
  [VCF A ][VCF D ][VCF S ][VCF R ][CUTOFF][RESON ][ACCENT][DSTLVL]

Row 3 (encoders, 8):
  [SAWLVL][SQRLVL][RINGLVL][      ][ENVDEP][KEYFOL][VCFLFO][DRYLVL]
                            spare?
```

---

## CC Assignment Table

### Row 0 — VCO Sources + Portamento (macro push-encoders)

| Col | Rotate CC | Push CC | Function (rotate) | Function (push) | SysEx addr | Type |
|-----|-----------|---------|-------------------|-----------------|------------|------|
| 1 | **CC 1** | **CC 9** | VCO SAW LEVEL | VCO SAW SW | `10 00 08 00` / `10 00 08 08` | 7-bit / bool |
| 2 | **CC 2** | **CC 10** | VCO SQR LEVEL | VCO SQR SW | `10 00 08 01` / `10 00 08 09` | 7-bit / bool |
| 3 | **CC 3** | **CC 11** | VCO SIN LEVEL | VCO SIN SW | `10 00 08 04` / `10 00 08 0A` | 7-bit / bool |
| 4 | **CC 4** | **CC 12** | VCO WHITE LEVEL | VCO WHITE SW | `10 00 08 05` / `10 00 08 0B` | 7-bit / bool |
| 5 | **CC 5** | **CC 13** | VCO PINK LEVEL | VCO PINK SW | `10 00 08 06` / `10 00 08 0C` | 7-bit / bool |
| 6 | **CC 6** | **CC 14** | PORTAMENTO TIME | PORTAMENTO SW | `10 00 14 01` / `10 00 14 00` | 7-bit / bool |
| 7 | **CC 7** | **CC 15** | VCO LFO DEPTH | — (spare push) | `10 00 00 08` / — | 7-bit (signed¹) |
| 8 | **CC 8** | **CC 16** | VCO RING LEVEL | VCO RING SW | `10 00 08 07` / `10 00 08 0D` | 7-bit / bool |

¹ Signed offset-encode: raw 64 = 0, 0 = −64, 127 = +63. Display adjusted in Lua.

### Row B — Buttons

| Btn | CC | Function | SysEx addr | Notes |
|-----|----|----------|------------|-------|
| 1 | **CC 17** | DIST ON/OFF | `10 00 0E 00` | Toggle, bool |
| 2 | **CC 18** | DIST COLOR | `10 00 0E 07` | Toggle, bool |
| 3 | **CC 19** | — | — | spare |
| 4 | **CC 20** | — | — | spare |
| 5 | **CC 21** | — | — | spare |
| 6 | **CC 22** | PORTAMENTO MODE | `10 00 14 02` | Toggle: LEGATO(0) / ALWAYS(1) |
| 7 | **CC 23** | DIST TYPE ↑ | `10 00 0E 01` | Momentary — Lua increments type (0–24), wraps |
| 8 | **CC 24** | DIST TYPE ↓ | `10 00 0E 01` | Momentary — Lua decrements type, wraps |

### Row 1 — VCA + Distortion character

| Col | CC | Function | SysEx addr | Type |
|-----|----|----------|------------|------|
| 1 | **CC 25** | VCA ATTACK | `10 00 0C 00` | 7-bit |
| 2 | **CC 26** | VCA DECAY | `10 00 0C 01` | 7-bit |
| 3 | **CC 27** | VCA SUSTAIN | `10 00 0C 02` | 7-bit |
| 4 | **CC 28** | VCA RELEASE | `10 00 0C 03` | 7-bit |
| 5 | **CC 29** | VCA LFO DEPTH | `10 00 00 0A` | 7-bit (signed¹) |
| 6 | **CC 30** | DIST DRIVE | `10 00 0E 02` | 7-bit (0–120) |
| 7 | **CC 31** | DIST BOTTOM | `10 00 0E 03` | 7-bit (0=−50, 50=0, 100=+50) |
| 8 | **CC 32** | DIST TONE | `10 00 0E 04` | 7-bit (0=−50, 50=0, 100=+50) |

### Row 2 — VCF + mix levels

| Col | CC | Function | SysEx addr | Type |
|-----|----|----------|------------|------|
| 1 | **CC 33** | VCF ATTACK | `10 00 0A 06` | 7-bit |
| 2 | **CC 34** | VCF DECAY | `10 00 0A 07` | 7-bit |
| 3 | **CC 35** | VCF SUSTAIN | `10 00 0A 08` | 7-bit |
| 4 | **CC 36** | VCF RELEASE | `10 00 0A 09` | 7-bit |
| 5 | **CC 37** | VCF CUTOFF | `10 00 0A 00/01` | **16-bit** (0–255) |
| 6 | **CC 38** | VCF RESONANCE | `10 00 0A 02/03` | **16-bit** (0–255) |
| 7 | **CC 39** | ACCENT LEVEL | `10 00 14 0E/0F` | **16-bit** (0–255) |
| 8 | **CC 40** | DIST EFFECT LEVEL | `10 00 0E 05` | 7-bit (0–100) |

### Row 3 — VCF modulation + oscillator levels

| Col | CC | Function | SysEx addr | Type | Notes |
|-----|----|----------|------------|------|-------|
| 1 | **CC 41** | VCO SAW LEVEL² | `10 00 08 00` | 7-bit | See note² |
| 2 | **CC 42** | VCO SQR LEVEL² | `10 00 08 01` | 7-bit | See note² |
| 3 | **CC 43** | VCO RING LEVEL² | `10 00 08 07` | 7-bit | See note² |
| 4 | **CC 44** | — | — | — | spare — TBD³ |
| 5 | **CC 45** | VCF ENV DEPTH | `10 00 0A 04/05` | **16-bit** (0–255) | Envelope → filter mod |
| 6 | **CC 46** | VCF KEY FOLLOW | `10 00 0A 0A` | 7-bit | |
| 7 | **CC 47** | VCF LFO DEPTH | `10 00 00 09` | 7-bit (signed¹) | |
| 8 | **CC 48** | DIST DRY LEVEL | `10 00 0E 06` | 7-bit (0–100) | |

² Row 0 and Row 3 both map to the same SysEx address for SAW/SQR/RING levels. The TouchOSC layout control linked to each CC is the same fader node — moving either the Row 0 encoder or the Row 3 encoder will update the display and send SysEx. This gives you the choice of reach (macro top-row or closer bottom-row). If you'd prefer Row 3 cols 1–3 to control something else entirely (e.g. LFO waveform levels), update these entries.

³ Diagram shows "TUNING?" for this position — no obvious single TB-3 parameter fits. Candidates: VCO SIN LEVEL (`10 00 08 04`) as a spare oscillator level, or MASTER VOLUME (`10 00 0C 04`). Left as spare pending hardware testing.

---

## Summary: TB-3 Parameters NOT on BCR2000 #1

These require TouchOSC direct control only (or move to BCR2000 #1 spare slots):

- VCO SIN LEVEL (if not in row 3 col 4 TBD slot)
- VCO WHITE NOISE LEVEL / PINK NOISE LEVEL (they ARE on row 0 rotate — encoder 3/4)
- MASTER VOLUME (`10 00 0C 04`)
- LFO RATE (`10 00 00 00`), LFO DELAY (`10 00 00 01`)
- LFO waveform levels (SAW/SQR/TRI/SIN wave levels `10 00 00 02–05`)
- Cross Modulation, Ring Modulation, CV Offset params — Phase 2
- BENDER RANGE (`10 00 14 03`)
