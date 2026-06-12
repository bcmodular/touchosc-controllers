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

-- ---------------------------------------------------------------------------
-- BCR.MAP — derived from Params.LIST (param_defs.lua, loaded first)
-- ---------------------------------------------------------------------------
-- Derivation rules:
--   Rows with bcr set → BCR.MAP[bcr] = {addr, bits, [signed], [bipolar], [max≠default]}
--   sw/btn rows → max=1 always (no signed/bipolar); non-sw/btn omit max if == default.
-- Address-less morph literals are added explicitly after the loop.
-- CC 6 and CC 38 are NRPN status bytes on ch1 — never mapped here.

BCR.MAP = {}

do
  for _, p in ipairs(Params.LIST) do
    if p.bcr then
      local e = {addr = p.addr, bits = p.bits}
      if p.sw or p.btn then
        e.max = 1
      else
        if p.signed  then e.signed  = true end
        if p.bipolar then e.bipolar = true end
        local dflt = (p.bits == 16) and 255 or 127
        if p.max and p.max ~= dflt then e.max = p.max end
      end
      BCR.MAP[p.bcr] = e
    end
  end
  -- Address-less morph entries have no SysEx identity — not in Params.LIST
  BCR.MAP[40] = {morph_btn = true}  -- MORPH ON/OFF push (special-cased in handleBCR1/syncBCR1)
end

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

-- ---------------------------------------------------------------------------
-- BCR.NRPN_MAP — derived from Params.LIST
-- ---------------------------------------------------------------------------
-- Rows with nrpn set → BCR.NRPN_MAP[nrpn] = {addr, [max]}
-- bipolar/center NOT emitted (display-only, driven by ENC_SEND_MAP).
-- NRPN 8 (morph) has no SysEx address — added explicitly after the loop.

BCR.NRPN_MAP = {}

do
  for _, p in ipairs(Params.LIST) do
    if p.nrpn then
      local e = {addr = p.addr}
      if p.max then e.max = p.max end
      BCR.NRPN_MAP[p.nrpn] = e
    end
  end
  -- MORPH AMOUNT: layout-internal float, no SysEx address; special-cased in
  -- the handleBCR1 NRPN dispatch and syncBCR1. 0–500 → morphAmount 0.0–1.0
  BCR.NRPN_MAP[8] = {morph = true, max = 500}
end

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
