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
-- VCO/LFO dual-mode: top 8 encoders are shared between two BCR encoder groups.
--   Group 1 (BCR channel 6): CC1–8 rotate → VCO source levels + patch volume
--   Group 2 (BCR channel 3): CC1–8 rotate → LFO params (Dope Robot order)
--                            CC9–10 push  → BPM SYNC / RETRIGGER
-- root.lua routes by MIDI channel alone — no mode state variable needed.

-- VCO mode map (Group 1, BCR2000 channel 6) — CC1–8 rotate
local BCR1_VCO_MAP = {
  [1]  = { addr = {0x10,0x00,0x08,0x00}, bits = 7 },            -- VCO SAW LEVEL
  [2]  = { addr = {0x10,0x00,0x08,0x01}, bits = 7 },            -- VCO SQR LEVEL
  [3]  = { addr = {0x10,0x00,0x08,0x04}, bits = 7 },            -- VCO SIN LEVEL
  [4]  = { addr = {0x10,0x00,0x08,0x05}, bits = 7 },            -- VCO WHITE LEVEL
  [5]  = { addr = {0x10,0x00,0x08,0x06}, bits = 7 },            -- VCO PINK LEVEL
  [6]  = { addr = {0x10,0x00,0x08,0x07}, bits = 7 },            -- VCO RING LEVEL
  [7]  = { addr = {0x10,0x00,0x00,0x08}, bits = 7, signed = true }, -- VCO LFO DEPTH
  [8]  = { addr = {0x10,0x00,0x0C,0x04}, bits = 7 },            -- PATCH VOLUME (master vol)
}

-- LFO mode map (Group 2, BCR2000 channel 3) — CC1–8 rotate.
-- Dope Robot ordering: RATE, CV OFFSET, DELAY, TRI, SAW, SQR, SIN, S&H.
local BCR1_LFO_MAP = {
  [1]  = { addr = {0x10,0x00,0x00,0x00}, bits = 7 },            -- LFO RATE
  [2]  = { addr = {0x10,0x00,0x00,0x06}, bits = 7 },            -- LFO CV OFFSET
  [3]  = { addr = {0x10,0x00,0x00,0x01}, bits = 7 },            -- LFO DELAY
  [4]  = { addr = {0x10,0x00,0x00,0x04}, bits = 7 },            -- LFO WAVE TRI
  [5]  = { addr = {0x10,0x00,0x00,0x02}, bits = 7 },            -- LFO WAVE SAW
  [6]  = { addr = {0x10,0x00,0x00,0x03}, bits = 7 },            -- LFO WAVE SQR
  [7]  = { addr = {0x10,0x00,0x00,0x05}, bits = 7 },            -- LFO WAVE SIN
  [8]  = { addr = {0x10,0x00,0x00,0x07}, bits = 7 },            -- LFO WAVE S&H
}

-- LFO push map (Group 2, BCR2000 channel 3) — CC9/CC10 push.
-- BPM SYNC is the push of RATE (Col 1); RETRIGGER is push of CV OFFSET (Col 2).
local BCR1_LFO_PUSH_MAP = {
  [9]  = { addr = {0x10,0x00,0x00,0x0B}, bits = 7, max = 1 },   -- LFO BPM SYNC (bool)
  [10] = { addr = {0x10,0x00,0x00,0x0C}, bits = 7, max = 1 },   -- LFO RETRIGGER (bool)
}

-- Full BCR1 map (mode-independent CCs)
local BCR1_MAP = {
  -- Row 0: push-encoder switches (toggle on rising edge in root.lua)
  [9]  = { addr = {0x10,0x00,0x08,0x08}, bits = 7, max = 1 },  -- VCO SAW SW
  [10] = { addr = {0x10,0x00,0x08,0x09}, bits = 7, max = 1 },  -- VCO SQR SW
  [11] = { addr = {0x10,0x00,0x08,0x0A}, bits = 7, max = 1 },  -- VCO SIN SW
  [12] = { addr = {0x10,0x00,0x08,0x0B}, bits = 7, max = 1 },  -- VCO WHITE SW
  [13] = { addr = {0x10,0x00,0x08,0x0C}, bits = 7, max = 1 },  -- VCO PINK SW
  [14] = { addr = {0x10,0x00,0x08,0x0D}, bits = 7, max = 1 },  -- VCO RING SW
  -- CC 15: spare push (VCO LFO DEPTH encoder has no push function)
  -- CC 16: spare (was RING SW; RING SW moved to CC14)

  -- Row B: dedicated buttons
  [17] = { addr = {0x10,0x00,0x0E,0x00}, bits = 7, max = 1 },  -- DIST ON/OFF
  [18] = { addr = {0x10,0x00,0x0E,0x07}, bits = 7, max = 1 },  -- DIST COLOR
  -- CC 19: VCO/LFO mode toggle — handled in root.lua (switches bcrVcoLfoMode)
  -- CC 20, 21: spare
  -- CC 22: spare (was PORTA MODE; portamento is now TouchOSC-only)
  -- CC 23: DIST TYPE ↑  — handled in root.lua
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
  [37] = { addr = {0x10,0x00,0x0A,0x00}, bits = 16, max = 255 },-- VCF CUTOFF (MSB 0x00, LSB 0x01)
  [38] = { addr = {0x10,0x00,0x0A,0x02}, bits = 16, max = 255 },-- VCF RESONANCE (MSB 0x02, LSB 0x03)
  [39] = { addr = {0x10,0x00,0x14,0x0E}, bits = 16, max = 255 },-- ACCENT LEVEL (MSB 0x0E, LSB 0x0F)
  [40] = { addr = {0x10,0x00,0x0E,0x05}, bits = 7, max = 100 }, -- DIST EFFECT LEVEL

  -- Row 3: tuning (CV offset, 16-bit) + VCF modulation + dist dry
  [41] = { addr = {0x10,0x00,0x02,0x02}, bits = 16, max = 255 },-- SAW TUNING (CV offset SAW pitch)
  [42] = { addr = {0x10,0x00,0x02,0x00}, bits = 16, max = 255 },-- SQR TUNING (CV offset SQR pitch)
  [43] = { addr = {0x10,0x00,0x02,0x04}, bits = 16, max = 255 },-- RING+SIN TUNING (CV offset RING pitch)
  -- CC 44: GLOBAL TUNING — plain MIDI CC 104 to TB-3, handled in root.lua (not a SysEx address)
  [45] = { addr = {0x10,0x00,0x0A,0x04}, bits = 16, max = 255 },-- VCF ENV DEPTH (MSB 0x04, LSB 0x05)
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
  -- CC 3, 4, 7, 8: spare top-row encoders (reserved for future use)

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
