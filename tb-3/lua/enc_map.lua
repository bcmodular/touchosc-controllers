-- enc_map.lua
-- Included into root.lua at build time (after patch_manager.lua).
-- Provides the send-side lookup tables: encoder name → SysEx address.
--
-- Key format: "section_group,enc_group_name"
-- This two-level key is needed because ring_mod_group shares child names
-- (saw_enc, sqr_enc etc.) with vco_group.
--
-- Entry fields mirror bcr_map.lua:
--   addr : {a1,a2,a3,a4}
--   bits : 7  → tb3Send7bit  (raw 0–maxVal)
--          16 → tb3Send16bit (raw 0–maxVal, nibble-packed)
--   max  : full-scale value (default: bits=7 → 127, bits=16 → 255)
--   sp   : "global_tuning" — plain MIDI CC 104 (not SysEx)

-- ---------------------------------------------------------------------------
-- EncMap namespace table — the single top-level local this include exposes to
-- the shared root chunk (see tb-3/CLAUDE.md "Root chunk — include order
-- contract"). Fields:
--   EncMap.ENC_SEND_MAP  control_fader send-side: "section,enc" → addr/encoding
--   EncMap.SW_SEND_MAP   sw_button / toggle send-side: "section,enc" → addr
--   EncMap.ADDR_TO_ENC   reverse: addr hex → {path, entry} (built below)
--   EncMap.ADDR_TO_SW    reverse: addr hex → {path, entry} (built below)
-- ---------------------------------------------------------------------------
local EncMap = {}

-- ---------------------------------------------------------------------------
-- EncMap.ENC_SEND_MAP and EncMap.SW_SEND_MAP — derived from Params.LIST
-- (param_defs.lua, prepended first in the concatenated root chunk)
-- ---------------------------------------------------------------------------
-- Derivation rules:
--   ENC_SEND_MAP: rows with path, not sw, not btn.
--     encSp rows  → {sp=encSp}
--     normal rows → {addr, bits, [signed], [bipolar], [center], [semitoneRange], [max≠default]}
--   SW_SEND_MAP:  rows with path and (sw or btn) → {addr, bits, [btn=true]}
-- bits=7 default max=127; bits=16 default max=255; max omitted if == default.

EncMap.ENC_SEND_MAP = {}
EncMap.SW_SEND_MAP  = {}

do
  for _, p in ipairs(Params.LIST) do
    if p.path and not p.sw and not p.btn then
      if p.encSp then
        EncMap.ENC_SEND_MAP[p.path] = {sp = p.encSp}
      else
        local e = {addr = p.addr, bits = p.bits}
        if p.signed        then e.signed        = true       end
        if p.bipolar       then e.bipolar        = true       end
        if p.center        then e.center         = p.center   end
        if p.semitoneRange then e.semitoneRange  = true       end
        local dflt = (p.bits == 16) and 255 or 127
        if p.max and p.max ~= dflt then e.max = p.max end
        EncMap.ENC_SEND_MAP[p.path] = e
      end
    end
    if p.path and (p.sw or p.btn) then
      local e = {addr = p.addr, bits = p.bits}
      if p.btn then e.btn = true end
      EncMap.SW_SEND_MAP[p.path] = e
    end
  end
end

-- EFX1/EFX2 slots: added in Phase 4

-- ---------------------------------------------------------------------------
-- Reverse lookups: SysEx addr key → {path, entry}
-- Built at module load time. Used by root.lua to update UI from BCR input
-- and to find BCR CC when syncing BCR2000 after a patch receive.
-- key format: string.format("%02X%02X%02X%02X", a1,a2,a3,a4)
-- ---------------------------------------------------------------------------

EncMap.ADDR_TO_ENC = {}
for path, entry in pairs(EncMap.ENC_SEND_MAP) do
  if entry.addr then
    local k = string.format("%02X%02X%02X%02X",
      entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
    EncMap.ADDR_TO_ENC[k] = { path=path, entry=entry }
  end
end

EncMap.ADDR_TO_SW = {}
for path, entry in pairs(EncMap.SW_SEND_MAP) do
  if entry.addr then
    local k = string.format("%02X%02X%02X%02X",
      entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
    EncMap.ADDR_TO_SW[k] = { path=path, entry=entry }
  end
end
