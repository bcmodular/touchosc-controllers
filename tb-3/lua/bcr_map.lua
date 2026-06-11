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
-- NRPN (channel 1 only — see BCR.NRPN_MAP below):
--   The four 16-bit params formerly on CC 97/98/99/101 are NRPN encoders
--   (BCR mode "absolute/14"). CC 6/38 (Data Entry MSB/LSB) and CC 98/99
--   (NRPN param LSB/MSB) are RESERVED on channel 1 — never map them as
--   plain CCs. CC 96 (DIST TONE) and CC 100 (GLOBAL TUNING) are
--   spec-dirty (MIDI Data Increment / RPN LSB) but intentional: root.lua's
--   parser only consumes CC 6/38/98/99 as NRPN status bytes.
--
-- All addresses follow Roland TB-3 SysEx format:
--   F0 41 10 00 00 7B 12 [a1 a2 a3 a4] [data] [checksum] F7
--
-- BC Manager preset layout (same template for both units, different channel):
--   BCR2000 #1: MIDI CH 1    BCR2000 #2: MIDI CH 2
--
--   CC  1– 8  Encoder Group 1 rotate  (physical top-row encoders)
--             (BCR1: pos 6 rotate retargeted to CC 17 — CC 6 = NRPN data MSB)
--   CC  9–16  Encoder Group 2 rotate
--   CC 17–24  Encoder Group 3 rotate  (BCR1: CC 17 = VCO RING LEVEL, rest unused)
--   CC 25–32  Encoder Group 4 rotate  (unused)
--   CC 33–40  Encoder Group 1 push
--             (BCR1: pos 6 push retargeted to CC 49 — CC 38 = NRPN data LSB)
--   CC 41–48  Encoder Group 2 push
--   CC 49–56  Encoder Group 3 push    (BCR1: CC 49 = VCO RING SW, rest unused)
--   CC 57–64  Encoder Group 4 push    (unused)
--   CC 65–80  Dedicated buttons (2 rows of 8)
--   CC 81–88  Fixed encoder row 1 (bottom-most rows, always active)
--   CC 89–96  Fixed encoder row 2
--   CC 97–104 Fixed encoder row 3
--             (BCR1: pos 1,2,3,5 are NRPN encoders — see BCR.NRPN_MAP)

-- ---------------------------------------------------------------------------
-- BCR2000 #1  (MIDI channel 1) — Tone + Distortion
-- ---------------------------------------------------------------------------
--
-- Encoder Group 1 (CC 1–8 rotate, CC 33–40 push): VCO
-- Encoder Group 2 (CC 9–16 rotate, CC 41–48 push): LFO
-- Dedicated buttons: CC 71 DIST ON/OFF, 79 DIST COLOR
-- Fixed rows: VCA (81–88), VCF (89–96), Tuning (97–104)

-- ---------------------------------------------------------------------------
-- BCR namespace table — the single top-level local this include exposes to the
-- shared root chunk (see tb-3/CLAUDE.md "Root chunk — include order contract").
-- Fields:
--   BCR.MAP            BCR2000 #1 CC → SysEx address table (was BCR1_MAP)
--   BCR.NRPN_MAP       BCR2000 #1 NRPN → SysEx address table (was BCR1_NRPN_MAP)
--   BCR.ADDR_TO_CC     reverse: addr hex → BCR1 CC (was ADDR_TO_BCR1_CC)
--   BCR.ADDR_TO_NRPN   reverse: addr hex → {nrpn, entry} (was ADDR_TO_BCR1_NRPN)
--   BCR.efx{1,2}SlotIndex / efx{1,2}BtnIndex  BCR2000 #2 CC → slot/button index
-- ---------------------------------------------------------------------------
local BCR = {}

BCR.MAP = {
  -- ---- Encoder Group 1 rotate: VCO source levels + LFO depth + patch vol ----
  [1]  = { addr = {0x10,0x00,0x08,0x00}, bits = 7 },              -- VCO SAW LEVEL
  [2]  = { addr = {0x10,0x00,0x08,0x01}, bits = 7 },              -- VCO SQR LEVEL
  [3]  = { addr = {0x10,0x00,0x08,0x04}, bits = 7 },              -- VCO SIN LEVEL
  [4]  = { addr = {0x10,0x00,0x08,0x05}, bits = 7 },              -- VCO WHITE LEVEL
  [5]  = { addr = {0x10,0x00,0x08,0x06}, bits = 7 },              -- VCO PINK LEVEL
  -- CC 6 (VCO RING LEVEL) moved to CC 17 — CC 6 is NRPN Data Entry MSB.
  [7]  = { addr = {0x10,0x00,0x00,0x08}, bits = 7, signed = true },-- VCO LFO DEPTH
  -- CC 8 (MORPH AMOUNT) retired — pos 8 rotate is now NRPN 8 (see BCR.NRPN_MAP).
  -- Its push remains plain CC 40 (MORPH ON/OFF) below.

  -- VCO RING LEVEL — physical encoder group 1 pos 6 rotate, retargeted from
  -- CC 6 to CC 17 (group 3 rotate slot, unused) to free the NRPN data byte.
  [17] = { addr = {0x10,0x00,0x08,0x07}, bits = 7 },              -- VCO RING LEVEL

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
  -- CC 38 (VCO RING SW) moved to CC 49 — CC 38 is NRPN Data Entry LSB.
  -- CC 39: spare (VCO LFO DEPTH has no switch)
  [40] = { morph_btn = true },                                     -- MORPH ON/OFF (no SysEx addr; special-cased in handleBCR1/syncBCR1)

  -- VCO RING SW — physical encoder group 1 pos 6 push, retargeted from
  -- CC 38 to CC 49 (group 3 push slot; keeps push = rotate + 32 pairing).
  [49] = { addr = {0x10,0x00,0x08,0x0D}, bits = 7, max = 1 },     -- VCO RING SW

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
  -- CC 86: spare
  [87] = { addr = {0x10,0x00,0x0E,0x02}, bits = 7, max = 120 },   -- DIST DRIVE (0–120)
  [88] = { addr = {0x10,0x00,0x0E,0x01}, bits = 7, max = 24  },   -- DIST TYPE (0–24; special-cased in handleBCR1)

  -- ---- Fixed encoder row 2: PATCH VOL + VCF ADSR + LFO MOD + Distortion character ----
  -- CUTOFF, RESONANCE and ACCENT moved to panel_controls_group (not BCR-controllable).
  [89] = { addr = {0x10,0x00,0x0C,0x04}, bits = 7 },              -- PATCH VOLUME
  [90] = { addr = {0x10,0x00,0x0A,0x06}, bits = 7 },              -- VCF ATTACK
  [91] = { addr = {0x10,0x00,0x0A,0x07}, bits = 7 },              -- VCF DECAY
  [92] = { addr = {0x10,0x00,0x0A,0x08}, bits = 7 },              -- VCF SUSTAIN
  [93] = { addr = {0x10,0x00,0x0A,0x09}, bits = 7 },              -- VCF RELEASE
  [94] = { addr = {0x10,0x00,0x00,0x09}, bits = 7, signed = true },-- VCF LFO MOD
  [95] = { addr = {0x10,0x00,0x0E,0x03}, bits = 7, max = 100, bipolar = true }, -- DIST BOTTOM
  [96] = { addr = {0x10,0x00,0x0E,0x04}, bits = 7, max = 100, bipolar = true }, -- DIST TONE

  -- ---- Fixed encoder row 3: Tuning + VCF ENV/KEY + Dist levels ----
  -- Positions 1,2,3,5 (SAW/SQR/RING+SIN TUNING, VCF ENV DEPTH) are NRPN
  -- encoders — see BCR.NRPN_MAP below. Their old plain CCs (97/98/99/101)
  -- are retired: 98/99 are NRPN param-select bytes; 97 (Data Decrement) and
  -- 101 (RPN MSB) are left unassigned to keep the channel spec-clean.
  -- CC 100: GLOBAL TUNING — sends plain MIDI CC 104 to TB-3 (handled in root.lua)
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

function BCR.efx1SlotIndex(cc)
  -- Returns 1–12 for EFX1 param slots, nil otherwise
  if cc >= 81 and cc <= 84  then return cc - 80 end  -- S01–S04
  if cc >= 89 and cc <= 92  then return cc - 84 end  -- S05–S08
  if cc >= 97 and cc <= 100 then return cc - 88 end  -- S09–S12
end

function BCR.efx2SlotIndex(cc)
  -- Returns 1–12 for EFX2 param slots, nil otherwise
  if cc >= 85  and cc <= 88  then return cc - 84  end -- S01–S04
  if cc >= 93  and cc <= 96  then return cc - 88  end -- S05–S08
  if cc >= 101 and cc <= 104 then return cc - 92  end -- S09–S12
end

function BCR.efx1BtnIndex(cc)
  -- Returns 1–8 for EFX1 dedicated buttons, nil otherwise
  if cc >= 65 and cc <= 68 then return cc - 64 end   -- B1–B4
  if cc >= 73 and cc <= 76 then return cc - 68 end   -- B5–B8
end

function BCR.efx2BtnIndex(cc)
  -- Returns 1–8 for EFX2 dedicated buttons, nil otherwise
  if cc >= 69 and cc <= 72 then return cc - 68 end   -- B1–B4
  if cc >= 77 and cc <= 80 then return cc - 72 end   -- B5–B8
end

-- ---------------------------------------------------------------------------
-- BCR.ADDR_TO_CC — reverse lookup for BCR1 sync after patch receive.
-- key = "%02X%02X%02X%02X" of the SysEx address, value = BCR1 CC number.
-- ---------------------------------------------------------------------------

BCR.ADDR_TO_CC = {}
for cc, entry in pairs(BCR.MAP) do
  if entry.addr then
    local k = string.format("%02X%02X%02X%02X",
      entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
    BCR.ADDR_TO_CC[k] = cc
  end
end

-- ---------------------------------------------------------------------------
-- BCR.NRPN_MAP — 16-bit (nibble-packed) parameters controlled via NRPN on
-- channel 1. The BCR encoders are programmed in BC Manager as type NRPN,
-- mode absolute/14, Min 0 / Max = entry max, so the 14-bit data entry value
-- (CC 6 MSB ×128 + CC 38 LSB) IS the raw SysEx value — no scaling.
--
-- Key = NRPN number (param MSB = 0, LSB = key). Entries 1–4 live on
-- BCR2000 #1 fixed row 3 (positions 1, 2, 3, 5). Entries 5–7 have no BCR
-- encoder; they exist so an external NRPN controller can drive them and
-- they receive feedback packets like the rest.
--
-- bipolar/center are display hints consumed by the enc_moved label path
-- (must match the corresponding ENC_SEND_MAP entries in enc_map.lua).
-- ---------------------------------------------------------------------------

BCR.NRPN_MAP = {
  -- Tuning: usable hardware range is raw 0–151 (centre 127 = 0, +24 max);
  -- no audible effect above 151 — same cap as enc_map.lua.
  [1] = { addr = {0x10,0x00,0x02,0x00}, max = 151 }, -- SAW TUNING       (row 3 pos 1)
  [2] = { addr = {0x10,0x00,0x02,0x02}, max = 151 }, -- SQR TUNING       (row 3 pos 2)
  [3] = { addr = {0x10,0x00,0x02,0x04}, max = 151 }, -- RING+SIN TUNING  (row 3 pos 3)
  [4] = { addr = {0x10,0x00,0x0A,0x04}, max = 255 }, -- VCF ENV DEPTH    (row 3 pos 5)
  [5] = { addr = {0x10,0x00,0x0A,0x00}, max = 255 }, -- VCF CUTOFF       (no BCR encoder)
  [6] = { addr = {0x10,0x00,0x0A,0x02}, max = 255 }, -- VCF RESONANCE    (no BCR encoder)
  [7] = { addr = {0x10,0x00,0x14,0x0E}, max = 255 }, -- ACCENT LEVEL     (no BCR encoder)
  -- MORPH AMOUNT — layout-internal float, no SysEx address; special-cased in
  -- the handleBCR1 NRPN dispatch and syncBCR1. 0–500 → morphAmount 0.0–1.0
  -- (matches the BCR encoder's Min/Max; acceleration levels 96 and 384).
  [8] = { morph = true, max = 500 },                 -- MORPH AMOUNT     (group 1 pos 8 rotate)
}

-- Reverse lookup for NRPN feedback (syncBCR1 / enc_moved mirror).
-- key = addr hex string, value = { nrpn = N, entry = BCR.NRPN_MAP[N] }.
-- Address-less entries (morph) are skipped — they have no SysEx identity.
BCR.ADDR_TO_NRPN = {}
for nrpn, entry in pairs(BCR.NRPN_MAP) do
  if entry.addr then
    local k = string.format("%02X%02X%02X%02X",
      entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
    BCR.ADDR_TO_NRPN[k] = { nrpn = nrpn, entry = entry }
  end
end
