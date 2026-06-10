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
--
-- BC Manager preset layout (same template for both units, different channel):
--   BCR2000 #1: MIDI CH 1    BCR2000 #2: MIDI CH 2
--
--   CC  1– 8  Encoder Group 1 rotate  (physical top-row encoders)
--   CC  9–16  Encoder Group 2 rotate
--   CC 17–24  Encoder Group 3 rotate  (unused)
--   CC 25–32  Encoder Group 4 rotate  (unused)
--   CC 33–40  Encoder Group 1 push
--   CC 41–48  Encoder Group 2 push
--   CC 49–56  Encoder Group 3 push    (unused)
--   CC 57–64  Encoder Group 4 push    (unused)
--   CC 65–80  Dedicated buttons (2 rows of 8)
--   CC 81–88  Fixed encoder row 1 (bottom-most rows, always active)
--   CC 89–96  Fixed encoder row 2
--   CC 97–104 Fixed encoder row 3

-- ---------------------------------------------------------------------------
-- BCR2000 #1  (MIDI channel 1) — Tone + Distortion
-- ---------------------------------------------------------------------------
--
-- Encoder Group 1 (CC 1–8 rotate, CC 33–40 push): VCO
-- Encoder Group 2 (CC 9–16 rotate, CC 41–48 push): LFO
-- Dedicated buttons: CC 71 DIST ON/OFF, 72 DIST COLOR, 79 TYPE↑, 80 TYPE↓
-- Fixed rows: VCA (81–88), VCF (89–96), Tuning (97–104)

local BCR1_MAP = {
  -- ---- Encoder Group 1 rotate: VCO source levels + LFO depth + patch vol ----
  [1]  = { addr = {0x10,0x00,0x08,0x00}, bits = 7 },              -- VCO SAW LEVEL
  [2]  = { addr = {0x10,0x00,0x08,0x01}, bits = 7 },              -- VCO SQR LEVEL
  [3]  = { addr = {0x10,0x00,0x08,0x04}, bits = 7 },              -- VCO SIN LEVEL
  [4]  = { addr = {0x10,0x00,0x08,0x05}, bits = 7 },              -- VCO WHITE LEVEL
  [5]  = { addr = {0x10,0x00,0x08,0x06}, bits = 7 },              -- VCO PINK LEVEL
  [6]  = { addr = {0x10,0x00,0x08,0x07}, bits = 7 },              -- VCO RING LEVEL
  [7]  = { addr = {0x10,0x00,0x00,0x08}, bits = 7, signed = true },-- VCO LFO DEPTH
  [8]  = { addr = {0x10,0x00,0x0C,0x04}, bits = 7 },              -- PATCH VOLUME

  -- ---- Encoder Group 2 rotate: LFO (Dope Robot ordering) ----
  [9]  = { addr = {0x10,0x00,0x00,0x00}, bits = 7 },              -- LFO RATE
  [10] = { addr = {0x10,0x00,0x00,0x06}, bits = 7 },              -- LFO CV OFFSET
  [11] = { addr = {0x10,0x00,0x00,0x01}, bits = 7 },              -- LFO DELAY
  [12] = { addr = {0x10,0x00,0x00,0x04}, bits = 7 },              -- LFO WAVE TRI
  [13] = { addr = {0x10,0x00,0x00,0x02}, bits = 7 },              -- LFO WAVE SAW
  [14] = { addr = {0x10,0x00,0x00,0x03}, bits = 7 },              -- LFO WAVE SQR
  [15] = { addr = {0x10,0x00,0x00,0x05}, bits = 7 },              -- LFO WAVE SIN
  [16] = { addr = {0x10,0x00,0x00,0x07}, bits = 7 },              -- LFO WAVE S&H

  -- ---- Encoder Group 1 push: VCO source on/off switches ----
  [33] = { addr = {0x10,0x00,0x08,0x08}, bits = 7, max = 1 },     -- VCO SAW SW
  [34] = { addr = {0x10,0x00,0x08,0x09}, bits = 7, max = 1 },     -- VCO SQR SW
  [35] = { addr = {0x10,0x00,0x08,0x0A}, bits = 7, max = 1 },     -- VCO SIN SW
  [36] = { addr = {0x10,0x00,0x08,0x0B}, bits = 7, max = 1 },     -- VCO WHITE SW
  [37] = { addr = {0x10,0x00,0x08,0x0C}, bits = 7, max = 1 },     -- VCO PINK SW
  [38] = { addr = {0x10,0x00,0x08,0x0D}, bits = 7, max = 1 },     -- VCO RING SW
  -- CC 39: spare (VCO LFO DEPTH has no switch)
  -- CC 40: spare (PATCH VOLUME has no switch)

  -- ---- Encoder Group 2 push: LFO ----
  [41] = { addr = {0x10,0x00,0x00,0x0B}, bits = 7, max = 1 },     -- LFO BPM SYNC (push of RATE)
  [42] = { addr = {0x10,0x00,0x00,0x0C}, bits = 7, max = 1 },     -- LFO RETRIGGER (push of CV OFFSET)
  -- CC 43–48: spare

  -- ---- Dedicated buttons (right-aligned in layout) ----
  [71] = { addr = {0x10,0x00,0x0E,0x00}, bits = 7, max = 1 },     -- DIST ON/OFF
  [79] = { addr = {0x10,0x00,0x0E,0x07}, bits = 7, max = 1 },     -- DIST COLOR

  -- ---- Fixed encoder row 1: VCA ----
  [81] = { addr = {0x10,0x00,0x0C,0x00}, bits = 7 },              -- VCA ATTACK
  [82] = { addr = {0x10,0x00,0x0C,0x01}, bits = 7 },              -- VCA DECAY
  [83] = { addr = {0x10,0x00,0x0C,0x02}, bits = 7 },              -- VCA SUSTAIN
  [84] = { addr = {0x10,0x00,0x0C,0x03}, bits = 7 },              -- VCA RELEASE
  [85] = { addr = {0x10,0x00,0x00,0x0A}, bits = 7, signed = true },-- VCA LFO DEPTH
  [86] = { addr = {0x10,0x00,0x0E,0x02}, bits = 7, max = 120 },   -- DIST DRIVE (0–120)
  -- CC 87: spare
  -- CC 88: spare

  -- ---- Fixed encoder row 2: VCF ADSR + LFO MOD + Distortion character ----
  -- CUTOFF, RESONANCE and ACCENT moved to panel_controls_group (not BCR-controllable).
  [89] = { addr = {0x10,0x00,0x0A,0x06}, bits = 7 },              -- VCF ATTACK
  [90] = { addr = {0x10,0x00,0x0A,0x07}, bits = 7 },              -- VCF DECAY
  [91] = { addr = {0x10,0x00,0x0A,0x08}, bits = 7 },              -- VCF SUSTAIN
  [92] = { addr = {0x10,0x00,0x0A,0x09}, bits = 7 },              -- VCF RELEASE
  [93] = { addr = {0x10,0x00,0x00,0x09}, bits = 7, signed = true },-- VCF LFO MOD
  -- CC 94: spare
  [95] = { addr = {0x10,0x00,0x0E,0x03}, bits = 7, max = 100, bipolar = true }, -- DIST BOTTOM
  [96] = { addr = {0x10,0x00,0x0E,0x04}, bits = 7, max = 100, bipolar = true }, -- DIST TONE

  -- ---- Fixed encoder row 3: Tuning + VCF ENV/KEY + Dist levels ----
  -- CC 97/98 order confirmed from hardware SysEx capture (SAW=0x00, SQR=0x02).
  [97]  = { addr = {0x10,0x00,0x02,0x00}, bits = 16, max = 255 }, -- SAW TUNING
  [98]  = { addr = {0x10,0x00,0x02,0x02}, bits = 16, max = 255 }, -- SQR TUNING
  [99]  = { addr = {0x10,0x00,0x02,0x04}, bits = 16, max = 255 }, -- RING+SIN TUNING
  -- CC 100: GLOBAL TUNING — sends plain MIDI CC 104 to TB-3 (handled in root.lua)
  [101] = { addr = {0x10,0x00,0x0A,0x04}, bits = 16, max = 255 }, -- VCF ENV DEPTH
  [102] = { addr = {0x10,0x00,0x0A,0x0A}, bits = 7 },             -- VCF KEY FOLLOW
  [103] = { addr = {0x10,0x00,0x0E,0x05}, bits = 7, max = 100 },  -- DIST EFX LEVEL
  [104] = { addr = {0x10,0x00,0x0E,0x06}, bits = 7, max = 100 },  -- DIST DRY LEVEL
}

-- ---------------------------------------------------------------------------
-- BCR2000 #2  (MIDI channel 2) — EFX1 + EFX2
-- ---------------------------------------------------------------------------
-- EFX slot parameters are context-sensitive (SysEx target changes with effect
-- type). root.lua delegates to efx_section.lua via notify.
--
-- EFX1 slots: CC 81–84, 89–92, 97–100  (left 4 cols of each fixed row)
-- EFX2 slots: CC 85–88, 93–96, 101–104 (right 4 cols of each fixed row)
-- EFX1 buttons: CC 65–68 (B1–B4), CC 73–76 (B5–B8)
-- EFX2 buttons: CC 69–72 (B1–B4), CC 77–80 (B5–B8)
-- EFX1 type select: CC 1 (rotate), CC 33 (push — spare/future)
-- EFX2 type select: CC 5 (rotate), CC 37 (push — spare/future)

-- Helper functions (used by root.lua handleBCR2 — defined here for locality)

local function efx1SlotIndex(cc)
  -- Returns 1–12 for EFX1 param slots, nil otherwise
  if cc >= 81 and cc <= 84  then return cc - 80 end  -- S01–S04
  if cc >= 89 and cc <= 92  then return cc - 84 end  -- S05–S08
  if cc >= 97 and cc <= 100 then return cc - 88 end  -- S09–S12
end

local function efx2SlotIndex(cc)
  -- Returns 1–12 for EFX2 param slots, nil otherwise
  if cc >= 85  and cc <= 88  then return cc - 84  end -- S01–S04
  if cc >= 93  and cc <= 96  then return cc - 88  end -- S05–S08
  if cc >= 101 and cc <= 104 then return cc - 92  end -- S09–S12
end

local function efx1BtnIndex(cc)
  -- Returns 1–8 for EFX1 dedicated buttons, nil otherwise
  if cc >= 65 and cc <= 68 then return cc - 64 end   -- B1–B4
  if cc >= 73 and cc <= 76 then return cc - 68 end   -- B5–B8
end

local function efx2BtnIndex(cc)
  -- Returns 1–8 for EFX2 dedicated buttons, nil otherwise
  if cc >= 69 and cc <= 72 then return cc - 68 end   -- B1–B4
  if cc >= 77 and cc <= 80 then return cc - 72 end   -- B5–B8
end

local BCR2_MAP = {
  -- All EFX routing is handled via the helper functions above.
  -- No fixed-address entries: all EFX params are context-sensitive.
}

-- ---------------------------------------------------------------------------
-- ADDR_TO_BCR1_CC — reverse lookup for BCR1 sync after patch receive.
-- key = "%02X%02X%02X%02X" of the SysEx address, value = BCR1 CC number.
-- ---------------------------------------------------------------------------

local ADDR_TO_BCR1_CC = {}
for cc, entry in pairs(BCR1_MAP) do
  if entry.addr then
    local k = string.format("%02X%02X%02X%02X",
      entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
    ADDR_TO_BCR1_CC[k] = cc
  end
end
