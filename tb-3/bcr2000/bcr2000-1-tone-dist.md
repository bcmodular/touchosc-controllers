# BCR2000 #1 — Tone + Dist

Controls the core TB-3 synthesis engine and distortion section.

- **MIDI Channel:** 6 — matches the existing SP-404 BCR2000 preset. Both BCR2000s arrive on the same connection, so **channel is the differentiator between the two units**.
- **Connection in TouchOSC:** connection 2 — same port used by the SP-404 layout's BCR2000. Detection in `onReceiveMIDI` checks both connection 2 and the MIDI channel.
- **All encoders:** absolute CC (0–127)
- **Push-encoder pushes:** CC with value 127 = down, 0 = up (toggle on rising edge in Lua)
- **Buttons:** CC with value 127 = press (latching or momentary as noted)

---

## VCO / LFO Dual-Mode (Row 0 + Row B CC19)

Row 0's 8 encoders are shared between two BCR2000 encoder groups:

- **Group 1 — VCO mode** (default): CC1–8 → VCO source levels + patch volume
- **Group 2 — LFO mode**: CC1–8 → LFO rate, delay, wave levels, sync

**Mode toggle:** BCR1 Row B button CC19 sends value 127 to TouchOSC, which swaps `vco_group` ↔ `lfo_group` visibility and routes CC1–8 to the correct SysEx addresses. The BCR2000 hardware GROUP button switches encoder layers in sync.

---

## Physical Layout

```
Row 0 (macro push-encoders, 8) — VCO MODE:
  [SAW   ][SQR   ][SIN   ][WHITE ][PINK  ][RING  ][LFO   ][PATCH ]
   lev/SW  lev/SW  lev/SW  lev/SW  lev/SW  lev/SW  VCO dep  VOL

Row 0 (macro push-encoders, 8) — LFO MODE (same CCs, different layer):
  [RATE  ][DELAY ][W.SAW ][W.SQR ][W.TRI ][W.SIN ][W.S&H ][SYNC  ]

Row B (dedicated buttons, 8):
  [DIST  ][COLOR ][VCO/  ][      ][      ][      ][DIST  ][DIST  ]
   ON/OFF         LFO     spare   spare   spare   TYPE ↑   TYPE ↓
                  MODE

Row 1 (encoders, 8):
  [VCA A ][VCA D ][VCA S ][VCA R ][VCALFO][DRIVE ][BOTTOM][TONE  ]

Row 2 (encoders, 8):
  [VCF A ][VCF D ][VCF S ][VCF R ][CUTOFF][RESON ][ACCENT][DSTLVL]

Row 3 (encoders, 8):
  [SAWTUN][SQRTUN][RGSNTUN][TUNING][ENVDEP][KEYFOL][VCFLFO][DRYLVL]
```

---

## CC Assignment Table

### Row 0 — VCO Mode (Group 1)

| Col | Rotate CC | Push CC | Function (rotate) | Function (push) | SysEx addr | Type |
|-----|-----------|---------|-------------------|-----------------|------------|------|
| 1 | **CC 1** | **CC 9** | VCO SAW LEVEL | VCO SAW SW | `10 00 08 00` / `10 00 08 08` | 7-bit / bool |
| 2 | **CC 2** | **CC 10** | VCO SQR LEVEL | VCO SQR SW | `10 00 08 01` / `10 00 08 09` | 7-bit / bool |
| 3 | **CC 3** | **CC 11** | VCO SIN LEVEL | VCO SIN SW | `10 00 08 04` / `10 00 08 0A` | 7-bit / bool |
| 4 | **CC 4** | **CC 12** | VCO WHITE LEVEL | VCO WHITE SW | `10 00 08 05` / `10 00 08 0B` | 7-bit / bool |
| 5 | **CC 5** | **CC 13** | VCO PINK LEVEL | VCO PINK SW | `10 00 08 06` / `10 00 08 0C` | 7-bit / bool |
| 6 | **CC 6** | **CC 14** | VCO RING LEVEL | VCO RING SW | `10 00 08 07` / `10 00 08 0D` | 7-bit / bool |
| 7 | **CC 7** | **CC 15** | VCO LFO DEPTH | — (spare push) | `10 00 00 08` / — | 7-bit (signed¹) |
| 8 | **CC 8** | **CC 16** | PATCH VOLUME | — (spare push) | `10 00 0C 04` / — | 7-bit |

### Row 0 — LFO Mode (Group 2, same CC numbers, different BCR encoder layer)

| Col | Rotate CC | Push CC | Function (rotate) | Function (push) | SysEx addr | Type |
|-----|-----------|---------|-------------------|-----------------|------------|------|
| 1 | **CC 1** | — | LFO RATE | — | `10 00 00 00` | 7-bit |
| 2 | **CC 2** | — | LFO DELAY | — | `10 00 00 01` | 7-bit |
| 3 | **CC 3** | — | LFO WAVE SAW | — | `10 00 00 02` | 7-bit |
| 4 | **CC 4** | — | LFO WAVE SQR | — | `10 00 00 03` | 7-bit |
| 5 | **CC 5** | — | LFO WAVE TRI | — | `10 00 00 04` | 7-bit |
| 6 | **CC 6** | — | LFO WAVE SIN | — | `10 00 00 05` | 7-bit |
| 7 | **CC 7** | — | LFO WAVE S&H | — | `10 00 00 07` | 7-bit |
| 8 | **CC 8** | — | LFO SYNC | — | `10 00 00 0B` | bool (toggle) |

¹ Signed offset-encode: raw 64 = 0, 0 = −64, 127 = +63. Display adjusted in Lua.

### Row B — Buttons

| Btn | CC | Function | SysEx addr | Notes |
|-----|----|----------|------------|-------|
| 1 | **CC 17** | DIST ON/OFF | `10 00 0E 00` | Toggle, bool |
| 2 | **CC 18** | DIST COLOR | `10 00 0E 07` | Toggle, bool |
| 3 | **CC 19** | **VCO/LFO MODE TOGGLE** | — | Rising edge → `root.lua` swaps `vco_group` ↔ `lfo_group` |
| 4 | **CC 20** | — | — | spare |
| 5 | **CC 21** | — | — | spare |
| 6 | **CC 22** | — | — | spare (was PORTAMENTO MODE; portamento is now TouchOSC-only) |
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

### Row 3 — Tuning + VCF modulation

| Col | CC | Function | SysEx addr | Type | Notes |
|-----|----|----------|------------|------|-------|
| 1 | **CC 41** | SAW TUNING | `10 00 02 02/03` | **16-bit** | CV offset SAW pitch |
| 2 | **CC 42** | SQR TUNING | `10 00 02 00/01` | **16-bit** | CV offset SQR pitch |
| 3 | **CC 43** | RING+SIN TUNING | `10 00 02 04/05` | **16-bit** | CV offset RING pitch |
| 4 | **CC 44** | GLOBAL TUNING | TBD | — | Address not yet identified; stub |
| 5 | **CC 45** | VCF ENV DEPTH | `10 00 0A 04/05` | **16-bit** (0–255) | Envelope → filter mod |
| 6 | **CC 46** | VCF KEY FOLLOW | `10 00 0A 0A` | 7-bit | |
| 7 | **CC 47** | VCF LFO DEPTH | `10 00 00 09` | 7-bit (signed¹) | |
| 8 | **CC 48** | DIST DRY LEVEL | `10 00 0E 06` | 7-bit (0–100) | |

---

## Portamento (TouchOSC-only)

Portamento has been moved to a popup panel toggled from the EXTRAS section. It is **not** mapped to any BCR2000 encoder. Parameters:
- PORTAMENTO SW: `10 00 14 00` — toggle button in popup
- PORTAMENTO TIME: `10 00 14 01` — encoder in popup
- PORTAMENTO MODE: `10 00 14 02` — toggle button (LEGATO/ALWAYS) in popup

---

## Summary: Parameters NOT on BCR2000 #1

These are TouchOSC-only (popup panels) or not yet in the layout:

**Popup panels (TouchOSC-only):**
- Portamento TIME/SW/MODE
- Ring Modulation depths: `10 00 06 00/01/04/05/06/0B`
- Cross Modulation depths: `10 00 04 00/02/03/04/05/07/08/09`

**Not yet in layout (future phases):**
- LFO RETRIGGER (`10 00 00 0C`)
- LFO CV OFFSET (`10 00 00 07`) — LFO output offset
- BENDER RANGE (`10 00 14 03`)
- GLOBAL TUNING (CC44 TBD)
