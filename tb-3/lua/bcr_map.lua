-- bcr_map.lua
-- CC → SysEx address lookup tables for both BCR2000 units.
-- Included into root.lua at build time.
--
-- Table structure per entry:
--   [cc] = { addr = {a1,a2,a3,a4}, bits = 7|16, max = N, signed = bool }
--
--   bits   : 7 = single-byte SysEx; 16 = two-byte MSB/LSB
--   max    : SysEx full-scale value (default 127 if omitted)
--   signed : offset-encoded (raw 64 = 0); display-only hint for UI scripts
--
-- All addresses follow Roland TB-3 SysEx format:
--   F0 41 10 00 00 7B 12 [a1 a2 a3 a4] [data] [checksum] F7

-- ---------------------------------------------------------------------------
-- BCR2000 #1  (MIDI channel 6) — Tone + Distortion
-- ---------------------------------------------------------------------------

local BCR1_MAP = {
  -- Row 0: VCO source levels (rotate)
  [1]  = { addr = {0x10,0x00,0x08,0x00}, bits = 7 },            -- VCO SAW LEVEL
  [2]  = { addr = {0x10,0x00,0x08,0x01}, bits = 7 },            -- VCO SQR LEVEL
  [3]  = { addr = {0x10,0x00,0x08,0x04}, bits = 7 },            -- VCO SIN LEVEL
  [4]  = { addr = {0x10,0x00,0x08,0x05}, bits = 7 },            -- VCO WHITE LEVEL
  [5]  = { addr = {0x10,0x00,0x08,0x06}, bits = 7 },            -- VCO PINK LEVEL
  [6]  = { addr = {0x10,0x00,0x14,0x01}, bits = 7 },            -- PORTAMENTO TIME
  [7]  = { addr = {0x10,0x00,0x00,0x08}, bits = 7, signed = true }, -- VCO LFO DEPTH
  [8]  = { addr = {0x10,0x00,0x08,0x07}, bits = 7 },            -- VCO RING LEVEL

  -- Row 0: push-encoder switches (toggle on rising edge in root.lua)
  [9]  = { addr = {0x10,0x00,0x08,0x08}, bits = 7, max = 1 },  -- VCO SAW SW
  [10] = { addr = {0x10,0x00,0x08,0x09}, bits = 7, max = 1 },  -- VCO SQR SW
  [11] = { addr = {0x10,0x00,0x08,0x0A}, bits = 7, max = 1 },  -- VCO SIN SW
  [12] = { addr = {0x10,0x00,0x08,0x0B}, bits = 7, max = 1 },  -- VCO WHITE SW
  [13] = { addr = {0x10,0x00,0x08,0x0C}, bits = 7, max = 1 },  -- VCO PINK SW
  [14] = { addr = {0x10,0x00,0x14,0x00}, bits = 7, max = 1 },  -- PORTAMENTO SW
  -- CC 15: spare push (VCO LFO DEPTH encoder has no push function)
  [16] = { addr = {0x10,0x00,0x08,0x0D}, bits = 7, max = 1 },  -- VCO RING SW

  -- Row B: dedicated buttons
  [17] = { addr = {0x10,0x00,0x0E,0x00}, bits = 7, max = 1 },  -- DIST ON/OFF
  [18] = { addr = {0x10,0x00,0x0E,0x07}, bits = 7, max = 1 },  -- DIST COLOR
  -- CC 19, 20, 21: spare
  [22] = { addr = {0x10,0x00,0x14,0x02}, bits = 7, max = 1 },  -- PORTA MODE (LEGATO/ALWAYS)
  -- CC 23: DIST TYPE ↑  — handled in root.lua (increment/wrap, no fixed address value)
  -- CC 24: DIST TYPE ↓  — handled in root.lua

  -- Row 1: VCA envelope + distortion character
  [25] = { addr = {0x10,0x00,0x0C,0x00}, bits = 7 },            -- VCA ATTACK
  [26] = { addr = {0x10,0x00,0x0C,0x01}, bits = 7 },            -- VCA DECAY
  [27] = { addr = {0x10,0x00,0x0C,0x02}, bits = 7 },            -- VCA SUSTAIN
  [28] = { addr = {0x10,0x00,0x0C,0x03}, bits = 7 },            -- VCA RELEASE
  [29] = { addr = {0x10,0x00,0x00,0x0A}, bits = 7, signed = true }, -- VCA LFO DEPTH
  [30] = { addr = {0x10,0x00,0x0E,0x02}, bits = 7, max = 120 }, -- DIST DRIVE (0–120)
  [31] = { addr = {0x10,0x00,0x0E,0x03}, bits = 7, max = 100 }, -- DIST BOTTOM (0=−50…100=+50)
  [32] = { addr = {0x10,0x00,0x0E,0x04}, bits = 7, max = 100 }, -- DIST TONE

  -- Row 2: VCF envelope + critical 16-bit params
  [33] = { addr = {0x10,0x00,0x0A,0x06}, bits = 7 },            -- VCF ATTACK
  [34] = { addr = {0x10,0x00,0x0A,0x07}, bits = 7 },            -- VCF DECAY
  [35] = { addr = {0x10,0x00,0x0A,0x08}, bits = 7 },            -- VCF SUSTAIN
  [36] = { addr = {0x10,0x00,0x0A,0x09}, bits = 7 },            -- VCF RELEASE
  [37] = { addr = {0x10,0x00,0x0A,0x00}, bits = 16, max = 255 },-- VCF CUTOFF (MSB at 0x00, LSB at 0x01)
  [38] = { addr = {0x10,0x00,0x0A,0x02}, bits = 16, max = 255 },-- VCF RESONANCE (MSB at 0x02, LSB at 0x03)
  [39] = { addr = {0x10,0x00,0x14,0x0E}, bits = 16, max = 255 },-- ACCENT LEVEL (MSB at 0x0E, LSB at 0x0F)
  [40] = { addr = {0x10,0x00,0x0E,0x05}, bits = 7, max = 100 }, -- DIST EFFECT LEVEL

  -- Row 3: VCF modulation + oscillator duplicates
  [41] = { addr = {0x10,0x00,0x08,0x00}, bits = 7 },            -- VCO SAW LEVEL (duplicate of CC1)
  [42] = { addr = {0x10,0x00,0x08,0x01}, bits = 7 },            -- VCO SQR LEVEL (duplicate of CC2)
  [43] = { addr = {0x10,0x00,0x08,0x07}, bits = 7 },            -- VCO RING LEVEL (duplicate of CC8)
  -- CC 44: spare/TBD (see bcr2000-1-tone-dist.md footnote ³)
  [45] = { addr = {0x10,0x00,0x0A,0x04}, bits = 16, max = 255 },-- VCF ENV DEPTH (MSB at 0x04, LSB at 0x05)
  [46] = { addr = {0x10,0x00,0x0A,0x0A}, bits = 7 },            -- VCF KEY FOLLOW
  [47] = { addr = {0x10,0x00,0x00,0x09}, bits = 7, signed = true }, -- VCF LFO DEPTH
  [48] = { addr = {0x10,0x00,0x0E,0x06}, bits = 7, max = 100 }, -- DIST DRY LEVEL
}

-- ---------------------------------------------------------------------------
-- BCR2000 #2  (MIDI channel 7) — EFX1 + EFX2
-- ---------------------------------------------------------------------------
-- EFX slot parameters (CC 11–22 for EFX1, CC 41–52 for EFX2) are context-
-- sensitive: their SysEx targets change when the effect type changes.
-- root.lua delegates these to efx_section.lua via notify.
-- This table covers only the fixed-address entries on BCR2000 #2.

local BCR2_MAP = {
  -- CC 1: EFX1 type rotate — handled in root.lua (notify efx_section)
  -- CC 2: EFX1 SW toggle   — handled in root.lua (notify efx_section)
  -- CC 5: EFX2 type rotate — handled in root.lua
  -- CC 6: EFX2 SW toggle   — handled in root.lua
  -- CC 3, 4, 7, 8: spare top-row encoders

  -- EFX1 param slots CC 11–22: delegated to efx_section.lua
  -- EFX1 buttons    CC 31–38: delegated to efx_section.lua
  -- EFX2 param slots CC 41–52: delegated to efx_section.lua
  -- EFX2 buttons    CC 61–68: delegated to efx_section.lua
}

-- EFX slot CC ranges (used by root.lua to detect EFX messages)
local EFX1_SLOT_CC_MIN  = 11
local EFX1_SLOT_CC_MAX  = 22
local EFX1_BTN_CC_MIN   = 31
local EFX1_BTN_CC_MAX   = 38
local EFX2_SLOT_CC_MIN  = 41
local EFX2_SLOT_CC_MAX  = 52
local EFX2_BTN_CC_MIN   = 61
local EFX2_BTN_CC_MAX   = 68
