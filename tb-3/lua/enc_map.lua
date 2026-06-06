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
-- ENC_SEND_MAP — control_fader nodes
-- ---------------------------------------------------------------------------

local ENC_SEND_MAP = {

  -- ---- LFO  10 00 00 00 ----
  ["lfo_group,lfo_rate_enc"]      = { addr={0x10,0x00,0x00,0x00}, bits=7 },
  ["lfo_group,lfo_delay_enc"]     = { addr={0x10,0x00,0x00,0x01}, bits=7 },
  ["lfo_group,lfo_wave_saw_enc"]  = { addr={0x10,0x00,0x00,0x02}, bits=7 },
  ["lfo_group,lfo_wave_sqr_enc"]  = { addr={0x10,0x00,0x00,0x03}, bits=7 },
  ["lfo_group,lfo_wave_tri_enc"]  = { addr={0x10,0x00,0x00,0x04}, bits=7 },
  ["lfo_group,lfo_wave_sin_enc"]  = { addr={0x10,0x00,0x00,0x05}, bits=7 },
  ["lfo_group,lfo_cv_offset_enc"] = { addr={0x10,0x00,0x00,0x06}, bits=7 },
  ["lfo_group,lfo_wave_sh_enc"]   = { addr={0x10,0x00,0x00,0x07}, bits=7 },
  -- LFO depth params: signed, offset-encoded (raw 64 = 0; display raw−64).
  ["vco_group,vco_lfo_depth_enc"] = { addr={0x10,0x00,0x00,0x08}, bits=7, signed=true },
  ["vcf_group,vcf_lfo_depth_enc"] = { addr={0x10,0x00,0x00,0x09}, bits=7, signed=true },
  ["vca_group,vca_lfo_depth_enc"] = { addr={0x10,0x00,0x00,0x0A}, bits=7, signed=true },

  -- ---- CV OFFSET / TUNING  10 00 02 00 ----
  ["tuning_group,sqr_tuning_enc"]      = { addr={0x10,0x00,0x02,0x00}, bits=16 },
  ["tuning_group,saw_tuning_enc"]      = { addr={0x10,0x00,0x02,0x02}, bits=16 },
  ["tuning_group,ring_sin_tuning_enc"] = { addr={0x10,0x00,0x02,0x04}, bits=16 },
  ["tuning_group,tuning_enc"]          = { sp="global_tuning" },

  -- ---- CROSS MODULATION  10 00 04 00 ----
  -- All cross-mod params are signed, offset-encoded (raw 64 = 0; display raw−64).
  ["cross_mod_group,sqr_saw_enc"]   = { addr={0x10,0x00,0x04,0x00}, bits=7, signed=true },
  ["cross_mod_group,saw_saw_enc"]   = { addr={0x10,0x00,0x04,0x02}, bits=7, signed=true },
  ["cross_mod_group,white_saw_enc"] = { addr={0x10,0x00,0x04,0x03}, bits=7, signed=true },
  ["cross_mod_group,pink_saw_enc"]  = { addr={0x10,0x00,0x04,0x04}, bits=7, signed=true },
  ["cross_mod_group,sqr_sqr_enc"]   = { addr={0x10,0x00,0x04,0x05}, bits=7, signed=true },
  ["cross_mod_group,saw_sqr_enc"]   = { addr={0x10,0x00,0x04,0x07}, bits=7, signed=true },
  ["cross_mod_group,white_sqr_enc"] = { addr={0x10,0x00,0x04,0x08}, bits=7, signed=true },
  ["cross_mod_group,pink_sqr_enc"]  = { addr={0x10,0x00,0x04,0x09}, bits=7, signed=true },

  -- ---- RING MODULATION  10 00 06 00 ----
  -- Note: enc names collide with vco_group; section prefix disambiguates.
  ["ring_mod_group,saw_enc"]   = { addr={0x10,0x00,0x06,0x00}, bits=7 },
  ["ring_mod_group,sqr_enc"]   = { addr={0x10,0x00,0x06,0x01}, bits=7 },
  ["ring_mod_group,ring_enc"]  = { addr={0x10,0x00,0x06,0x04}, bits=7 },
  ["ring_mod_group,white_enc"] = { addr={0x10,0x00,0x06,0x05}, bits=7 },
  ["ring_mod_group,pink_enc"]  = { addr={0x10,0x00,0x06,0x06}, bits=7 },
  ["ring_mod_group,depth_enc"] = { addr={0x10,0x00,0x06,0x0B}, bits=7 },

  -- ---- VCO  10 00 08 00 ----
  ["vco_group,saw_enc"]            = { addr={0x10,0x00,0x08,0x00}, bits=7 },
  ["vco_group,sqr_enc"]            = { addr={0x10,0x00,0x08,0x01}, bits=7 },
  ["vco_group,sin_enc"]            = { addr={0x10,0x00,0x08,0x04}, bits=7 },
  ["vco_group,white_enc"]          = { addr={0x10,0x00,0x08,0x05}, bits=7 },
  ["vco_group,pink_enc"]           = { addr={0x10,0x00,0x08,0x06}, bits=7 },
  ["vco_group,ring_enc"]           = { addr={0x10,0x00,0x08,0x07}, bits=7 },
  ["vco_group,patch_volume_enc"]   = { addr={0x10,0x00,0x0C,0x04}, bits=7 },

  -- ---- VCF  10 00 0A 00 ----
  ["vcf_group,vcf_cutoff_enc"]    = { addr={0x10,0x00,0x0A,0x00}, bits=16 },
  ["vcf_group,vcf_resonance_enc"] = { addr={0x10,0x00,0x0A,0x02}, bits=16 },
  ["vcf_group,vcf_env_depth_enc"] = { addr={0x10,0x00,0x0A,0x04}, bits=16 },
  ["vcf_group,vcf_attack_enc"]    = { addr={0x10,0x00,0x0A,0x06}, bits=7 },
  ["vcf_group,vcf_decay_enc"]     = { addr={0x10,0x00,0x0A,0x07}, bits=7 },
  ["vcf_group,vcf_sustain_enc"]   = { addr={0x10,0x00,0x0A,0x08}, bits=7 },
  ["vcf_group,vcf_release_enc"]   = { addr={0x10,0x00,0x0A,0x09}, bits=7 },
  ["vcf_group,vcf_key_follow_enc"]= { addr={0x10,0x00,0x0A,0x0A}, bits=7 },
  ["vcf_group,accent_level_enc"]  = { addr={0x10,0x00,0x14,0x0E}, bits=16 },

  -- ---- VCA  10 00 0C 00 ----
  ["vca_group,vca_attack_enc"]  = { addr={0x10,0x00,0x0C,0x00}, bits=7 },
  ["vca_group,vca_decay_enc"]   = { addr={0x10,0x00,0x0C,0x01}, bits=7 },
  ["vca_group,vca_sustain_enc"] = { addr={0x10,0x00,0x0C,0x02}, bits=7 },
  ["vca_group,vca_release_enc"] = { addr={0x10,0x00,0x0C,0x03}, bits=7 },

  -- ---- DISTORTION  10 00 0E 00 ----
  ["dist_group,dist_drive_enc"]     = { addr={0x10,0x00,0x0E,0x02}, bits=7, max=120 },
  ["dist_group,dist_bottom_enc"]    = { addr={0x10,0x00,0x0E,0x03}, bits=7, max=100, bipolar=true },
  ["dist_group,dist_tone_enc"]      = { addr={0x10,0x00,0x0E,0x04}, bits=7, max=100, bipolar=true },
  ["dist_group,dist_efx_level_enc"] = { addr={0x10,0x00,0x0E,0x05}, bits=7, max=100 },
  ["dist_group,dist_dry_level_enc"] = { addr={0x10,0x00,0x0E,0x06}, bits=7, max=100 },

  -- ---- PORTAMENTO / PARAM ASSIGN  10 00 14 00 ----
  ["portamento_group,porta_time_enc"]      = { addr={0x10,0x00,0x14,0x01}, bits=7 },
  ["pitch_bend_group,pitch_bend_range_enc"]= { addr={0x10,0x00,0x14,0x03}, bits=7, max=17 },

  -- EFX1/EFX2 slots: added in Phase 4
}

-- ---------------------------------------------------------------------------
-- SW_SEND_MAP — sw_button and standalone toggle button nodes
-- ---------------------------------------------------------------------------
-- Key: "section_group,enc_group_name" for sw_buttons inside encoder groups.
--      "section_group,button_name"    for standalone toggle buttons.

local SW_SEND_MAP = {

  -- ---- VCO source switches ----
  ["vco_group,saw_enc"]   = { addr={0x10,0x00,0x08,0x08}, bits=7 },
  ["vco_group,sqr_enc"]   = { addr={0x10,0x00,0x08,0x09}, bits=7 },
  ["vco_group,sin_enc"]   = { addr={0x10,0x00,0x08,0x0A}, bits=7 },
  ["vco_group,white_enc"] = { addr={0x10,0x00,0x08,0x0B}, bits=7 },
  ["vco_group,pink_enc"]  = { addr={0x10,0x00,0x08,0x0C}, bits=7 },
  ["vco_group,ring_enc"]  = { addr={0x10,0x00,0x08,0x0D}, bits=7 },

  -- ---- LFO push functions ----
  ["lfo_group,lfo_rate_enc"]      = { addr={0x10,0x00,0x00,0x0B}, bits=7 },  -- BPM SYNC
  ["lfo_group,lfo_cv_offset_enc"] = { addr={0x10,0x00,0x00,0x0C}, bits=7 },  -- RETRIGGER

  -- ---- Portamento switch (sw_button inside porta_time_enc) ----
  ["portamento_group,porta_time_enc"] = { addr={0x10,0x00,0x14,0x00}, bits=7 },

  -- ---- Portamento mode (standalone toggle: 0=LEGATO, 1=ALWAYS) ----
  ["portamento_group,porta_mode_button"] = { addr={0x10,0x00,0x14,0x02}, bits=7, btn=true },

  -- ---- Distortion toggles — Phase 3 (included here for completeness) ----
  -- btn=true: these are standalone BUTTON nodes, not enc_groups with sw_button children.
  ["dist_group,dist_on_off"] = { addr={0x10,0x00,0x0E,0x00}, bits=7, btn=true },
  ["dist_group,dist_color"]  = { addr={0x10,0x00,0x0E,0x07}, bits=7, btn=true },
}

-- ---------------------------------------------------------------------------
-- Reverse lookups: SysEx addr key → {path, entry}
-- Built at module load time. Used by root.lua to update UI from BCR input
-- and to find BCR CC when syncing BCR2000 after a patch receive.
-- key format: string.format("%02X%02X%02X%02X", a1,a2,a3,a4)
-- ---------------------------------------------------------------------------

local ADDR_TO_ENC = {}
for path, entry in pairs(ENC_SEND_MAP) do
  if entry.addr then
    local k = string.format("%02X%02X%02X%02X",
      entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
    ADDR_TO_ENC[k] = { path=path, entry=entry }
  end
end

local ADDR_TO_SW = {}
for path, entry in pairs(SW_SEND_MAP) do
  if entry.addr then
    local k = string.format("%02X%02X%02X%02X",
      entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
    ADDR_TO_SW[k] = { path=path, entry=entry }
  end
end
