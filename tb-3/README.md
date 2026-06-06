# TB-3 TouchOSC Controller

A full-featured TouchOSC layout for the Roland TB-3 synthesizer, providing complete parameter control via SysEx with optional BCR2000 hardware encoder support.

![TB-3 controller showing patch C03](screenshots/C03.png)

---

## Requirements

- **TouchOSC** (desktop or iPad) — `TB3.tosc`
- **Roland TB-3** connected via USB MIDI
- **BCR2000 ×2** *(optional)* — hardware encoder control for tone and effects

---

## MIDI Setup

### TouchOSC Connections

Configure **Connection 2** in TouchOSC to your TB-3 USB MIDI port (bidirectional). The controller sends SysEx on this connection and receives patch dumps back.

If using BCR2000 units, both connect on the **same port** as the TB-3 (or a separate MIDI interface on connection 2) — they are differentiated by MIDI channel:

| Device | MIDI Channel | Purpose |
|--------|-------------|---------|
| BCR2000 #1 | Ch 1 | Tone + Distortion |
| BCR2000 #2 | Ch 2 | EFX1 + EFX2 |
| TB-3 | Ch 2 (receive) | SysEx / MIDI CC |

### BCR2000 Presets

Load the BC Manager presets from the `bcr2000/` folder. Both units use the same template — set BCR2000 #1 to channel 1 and BCR2000 #2 to channel 2. See [`bcr2000/bcr2000-1-tone-dist.md`](bcr2000/bcr2000-1-tone-dist.md) and [`bcr2000/bcr2000-2-efx.md`](bcr2000/bcr2000-2-efx.md) for the full CC maps.

---

## Syncing from the TB-3

Press **SYNC FROM TB-3** at the top-left to request a full patch dump. All parameters on screen (and BCR2000 encoder rings if connected) will update to match the current patch on the TB-3.

> Do this whenever you change a patch on the TB-3 itself, or at the start of a session.

---

## Layout Overview

The layout is divided into functional colour-coded sections:

| Colour | Section |
|--------|---------|
| Blue | Oscillators (VCO source levels + switches) |
| Teal | LFO |
| Green | VCA (Voltage Controlled Amplifier) |
| Amber | VCF (Voltage Controlled Filter) |
| Red | Distortion |
| Purple | Tuning |
| Magenta | Cross Modulation |
| Violet | Ring Modulation |
| Blue-indigo | Portamento + Pitch Bend |
| Teal / Coral | EFX1 / EFX2 (effects chains) |

---

## Oscillators

Eight encoders control source levels (SAW, SQUARE, SINE, WHITE NOISE, PINK NOISE, RING MOD, LFO MOD, PATCH VOLUME). Toggle buttons below each encoder switch the oscillator on/off.

---

## LFO

Controls LFO RATE, CV OFFSET, DELAY, and waveform mix levels (TRI, SAW, SQR, SIN, S&H). The LFO RATE encoder has a push-toggle for BPM SYNC; CV OFFSET has a RETRIGGER toggle.

---

## Cross Modulation & Ring Modulation

Eight encoders for cross-modulation routing between oscillators (SQR→SAW, SAW→SAW, WHITE→SAW, PINK→SAW, SQR→SQR, SAW→SQR, WHITE→SQR, PINK→SQR) plus Ring Modulation levels (SAW, SQR, RING, WHITE, PINK, DEPTH).

---

## Portamento & Pitch Bend

**Portamento:** TIME encoder with SW toggle. MODE button toggles LEGATO / ALWAYS.

**Pitch Bend:** RANGE encoder (0–17 semitones). TIME encoder sets the bend ramp time.

**LEGATO** button toggles LEGATO mode on/off.

---

## Distortion

The distortion section shows the current distortion **type name** in the header (e.g. *MILD OD*, *LEAD*). Controls:

- **ON/OFF** — bypass toggle
- **COLOR** — tone character toggle  
- **TYPE ↑ / TYPE ↓** — step through distortion types (24 types)
- **Encoders:** DRIVE, BOTTOM, TONE, EFFECT LEVEL, DRY LEVEL

---

## VCA, VCF, Tuning

- **VCA:** ATTACK, DECAY, SUSTAIN, RELEASE, LFO DEPTH
- **VCF:** ATTACK, DECAY, SUSTAIN, RELEASE, CUTOFF, RESONANCE, ACCENT, DIST LEVEL. CUTOFF and RESONANCE are 16-bit parameters (0–255 range).
- **Tuning:** SAW, SQUARE, RING+SINE individual tuning offsets, global TUNING, ENV DEPTH, KEY FOLLOW, LFO MOD, DRY LEVEL

---

## EFX Sections (EFX1 + EFX2)

There are two independent effects chains. **EFX1** (teal) and **EFX2** (coral) have the same control layout.

### Selecting an Effect Type

The two rows of buttons at the top of each EFX section are the **type selector**. Tap any effect to activate it:

| EFX1 | EFX2 |
|------|------|
| COMP, RING MOD, BIT CRUSH, TREMOLO, CHORUS | COMP, RING MOD, BIT CRUSH, TREMOLO, CHORUS |
| FLANGER, PHASER, DELAY, PITCH SHIFT, EQ | FLANGER, PHASER, DELAY, REVERB |

- **Tapping the active type again** returns to BYPASS (all controls hidden).
- The active type button is highlighted; others remain dimmed.

### Parameter Encoders

Once an effect type is selected, the relevant parameter encoders appear below the type selector. Unused slots for the current effect are hidden automatically.

### Action Buttons

Below the parameter encoders are up to 8 buttons (B1–B8):

| Button | Purpose |
|--------|---------|
| **B1 (ON/OFF)** | Effect bypass toggle — always present when an effect is active |
| **B2–B4** | Utility controls: BPM SYNC, STEP RATE (Phaser), POLARITY (Ring Mod) |
| **B5–B8** | Type-option presets: shown in a lighter shade — e.g. SINGLE/PAN/STEREO for Delay, 4STAGE/8STAGE/12STAGE/BI-PH for Phaser |

For **BPM SYNC** effects (Chorus, Flanger, Phaser, Delay, Tremolo): when BPM SYNC is on, the rate slot switches to a beat-division value.

Reverb (EFX2 only) uses all 7 action buttons (B2–B8) as reverb-type presets: AMBIENT, ROOM, HALL 1, HALL 2, PLATE, SPRING, MOD.

---

## BCR2000 Encoder Control

When BCR2000 units are connected, all encoder rings update automatically when a patch is received or when parameters change on screen.

**BCR2000 #1** covers the synthesis engine:
- Encoder groups 1 & 2: VCO source levels and LFO parameters
- Fixed rows: VCA envelope, distortion character, VCF envelope, tuning

**BCR2000 #2** covers the effects chains:
- Left 4 columns: EFX1 parameter slots S01–S12
- Right 4 columns: EFX2 parameter slots S01–S12
- Dedicated buttons: EFX1 and EFX2 SW, BPM SYNC, and type-option presets
- Top encoder (left): EFX1 type select
- Top encoder (right): EFX2 type select

See the `bcr2000/` folder for the full CC assignment tables.

---

## Files

| File | Description |
|------|-------------|
| `TB3.tosc` | TouchOSC layout — open this in TouchOSC |
| `lua/` | Lua source scripts (build-time injected) |
| `bcr2000/` | BCR2000 BC Manager preset documentation |
| `resources/` | TB-3 SysEx reference and Dope Robot panel files |
| `tools/` | Layout maintenance scripts |
