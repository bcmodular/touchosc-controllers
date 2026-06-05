-- patch_manager.lua
-- Included into root.lua at build time (comes before root.lua in concatenated script).
-- Provides:
--   parseBlock(addr, data)  — update faders/labels from one SysEx block
--
-- NOTE ON SCOPING: distType and DIST_TYPE_NAMES are declared here so they are
-- visible to both parseBlock (below) and root.lua's handlers (concatenated after).
-- Do NOT re-declare them in root.lua.

-- ---------------------------------------------------------------------------
-- Distortion type state — shared with root.lua
-- ---------------------------------------------------------------------------

local distType = 0

local DIST_TYPE_NAMES = {
  "Mid Boost", "Clean Boost", "Treble Bst", "Blues OD",  "Crunch",
  "Natural OD","OD-1",        "T-Scream",   "Turbo OD",  "Warm OD",
  "Distortion","Mild DS",     "Mid DS",     "RAT",        "GUV DS",
  "DST+",      "Modern DS",   "Solid DS",   "Stack",      "Loud",
  "Metal Zone","Lead",        "'60s FUZZ",  "Oct FUZZ",   "MUFF FUZZ",
}

local DIST_NUM_TYPES = 25

-- ---------------------------------------------------------------------------
-- Registry
-- Each entry: { off, enc, [par,] [sw,] [btn,] kind, [max,] [sp] }
--
--   off  : byte offset within the block's data array (0-based)
--   enc  : encoder GROUP name (findByName or parent.children["name"])
--   par  : parent GROUP name — if set, lookup via parent.children[enc]
--            instead of global findByName(enc)  (needed for ring_mod_group
--            whose children share names with vco_group)
--   sw   : true → set the sw_button child rather than control_fader
--   btn  : true → enc is a standalone BUTTON, no child lookup
--   kind : "u7"  0–127 (or 0–max)
--          "u16" two nibble-packed bytes, value = data[off]*16 + data[off+1]
--          "s7"  0–127 offset-encoded, centre=64; display shows raw−64
--          "sw"  0/1 boolean (sw_button or toggle button)
--          "sp"  special handling, see parseSpecial()
--   max  : full-scale for u7/u16 (default: u7→127, u16→255)
--   sp   : string key for parseSpecial() dispatch
-- ---------------------------------------------------------------------------

local REGISTRY = {

  -- ---- LFO  10 00 00 00 ----
  ["10000000"] = {
    {off= 0, enc="lfo_rate_enc",      kind="u7"},
    {off= 1, enc="lfo_delay_enc",     kind="u7"},
    {off= 2, enc="lfo_wave_saw_enc",  kind="u7"},
    {off= 3, enc="lfo_wave_sqr_enc",  kind="u7"},
    {off= 4, enc="lfo_wave_tri_enc",  kind="u7"},
    {off= 5, enc="lfo_wave_sin_enc",  kind="u7"},
    {off= 6, enc="lfo_cv_offset_enc", kind="u7"},
    {off= 7, enc="lfo_wave_sh_enc",   kind="u7"},
    {off= 8, enc="vco_lfo_depth_enc", kind="s7"},
    {off= 9, enc="vcf_lfo_depth_enc", kind="s7"},
    {off=10, enc="vca_lfo_depth_enc", kind="s7"},
    {off=11, enc="lfo_rate_enc",      kind="sw", sw=true},   -- BPM SYNC
    {off=12, enc="lfo_cv_offset_enc", kind="sw", sw=true},   -- RETRIGGER
  },

  -- ---- CV OFFSET / TUNING  10 00 02 00 ----
  ["10000200"] = {
    {off=0, enc="sqr_tuning_enc",      kind="u16", max=255},
    {off=2, enc="saw_tuning_enc",      kind="u16", max=255},
    {off=4, enc="ring_sin_tuning_enc", kind="u16", max=255},
  },

  -- ---- CROSS MODULATION  10 00 04 00 ----
  ["10000400"] = {
    {off=0, enc="sqr_saw_enc",   kind="s7"},
    {off=2, enc="saw_saw_enc",   kind="s7"},
    {off=3, enc="white_saw_enc", kind="s7"},
    {off=4, enc="pink_saw_enc",  kind="s7"},
    {off=5, enc="sqr_sqr_enc",   kind="s7"},
    {off=7, enc="saw_sqr_enc",   kind="s7"},
    {off=8, enc="white_sqr_enc", kind="s7"},
    {off=9, enc="pink_sqr_enc",  kind="s7"},
  },

  -- ---- RING MODULATION  10 00 06 00 ----
  -- Uses par="ring_mod_group" because enc names collide with vco_group.
  ["10000600"] = {
    {off= 0, par="ring_mod_group", enc="saw_enc",   kind="u7"},
    {off= 1, par="ring_mod_group", enc="sqr_enc",   kind="u7"},
    {off= 4, par="ring_mod_group", enc="ring_enc",  kind="u7"},
    {off= 5, par="ring_mod_group", enc="white_enc", kind="u7"},
    {off= 6, par="ring_mod_group", enc="pink_enc",  kind="u7"},
    {off=11, par="ring_mod_group", enc="depth_enc", kind="u7"},
  },

  -- ---- VCO  10 00 08 00 ----
  ["10000800"] = {
    -- levels
    {off=0, enc="saw_enc",   kind="u7"},
    {off=1, enc="sqr_enc",   kind="u7"},
    {off=4, enc="sin_enc",   kind="u7"},
    {off=5, enc="white_enc", kind="u7"},
    {off=6, enc="pink_enc",  kind="u7"},
    {off=7, enc="ring_enc",  kind="u7"},
    -- source switches (sw_button inside the same group)
    {off= 8, enc="saw_enc",   kind="sw", sw=true},
    {off= 9, enc="sqr_enc",   kind="sw", sw=true},
    {off=10, enc="sin_enc",   kind="sw", sw=true},
    {off=11, enc="white_enc", kind="sw", sw=true},
    {off=12, enc="pink_enc",  kind="sw", sw=true},
    {off=13, enc="ring_enc",  kind="sw", sw=true},
  },

  -- ---- VCF  10 00 0A 00 ----
  ["10000A00"] = {
    {off= 0, enc="vcf_cutoff_enc",    kind="u16", max=255},
    {off= 2, enc="vcf_resonance_enc", kind="u16", max=255},
    {off= 4, enc="vcf_env_depth_enc", kind="u16", max=255},
    {off= 6, enc="vcf_attack_enc",    kind="u7"},
    {off= 7, enc="vcf_decay_enc",     kind="u7"},
    {off= 8, enc="vcf_sustain_enc",   kind="u7"},
    {off= 9, enc="vcf_release_enc",   kind="u7"},
    {off=10, enc="vcf_key_follow_enc",kind="u7"},
  },

  -- ---- VCA  10 00 0C 00 ----
  ["10000C00"] = {
    {off=0, enc="vca_attack_enc",   kind="u7"},
    {off=1, enc="vca_decay_enc",    kind="u7"},
    {off=2, enc="vca_sustain_enc",  kind="u7"},
    {off=3, enc="vca_release_enc",  kind="u7"},
    {off=4, enc="patch_volume_enc", kind="u7"},
  },

  -- ---- DISTORTION  10 00 0E 00 ----
  ["10000E00"] = {
    {off=0, enc="dist_on_off",        kind="sw",  btn=true},
    {off=1, kind="sp",                sp="dist_type"},
    {off=2, enc="dist_drive_enc",     kind="u7",  max=120},
    {off=3, enc="dist_bottom_enc",    kind="u7",  max=100},
    {off=4, enc="dist_tone_enc",      kind="u7",  max=100},
    {off=5, enc="dist_efx_level_enc", kind="u7",  max=100},
    {off=6, enc="dist_dry_level_enc", kind="u7",  max=100},
    {off=7, enc="dist_color",         kind="sw",  btn=true},
  },

  -- ---- PARAM ASSIGN / PORTAMENTO  10 00 14 00 ----
  ["10001400"] = {
    {off= 0, enc="porta_time_enc",      kind="sw",  sw=true},  -- PORTA SW
    {off= 1, enc="porta_time_enc",      kind="u7"},             -- PORTA TIME
    {off= 2, enc="porta_mode_button",   kind="sw",  btn=true},  -- PORTA MODE
    {off= 3, enc="pitch_bend_range_enc",kind="u7",  max=23},    -- BENDER RANGE (raw)
    -- offsets 4–13: PARAM ID entries (no UI elements yet — Phase 5)
    {off=14, enc="accent_level_enc",    kind="u16", max=255},   -- ACCENT
  },
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Find a node: if par is set, go via parent.children[enc]; else global search.
local function findEncoderGroup(field)
  if field.par then
    local parent = root:findByName(field.par, true)
    return parent and parent.children[field.enc]
  end
  return root:findByName(field.enc, true)
end

-- Set a fader/button value and update its value_label if present.
local function applyValue(field, raw)
  local kind = field.kind
  local maxV = field.max

  -- ---- standalone button (btn=true) ----
  if field.btn then
    local btn = root:findByName(field.enc, true)
    if btn then btn.values.x = raw end
    return
  end

  -- ---- encoder group ----
  local group = findEncoderGroup(field)
  if not group then return end

  if kind == "sw" then
    -- sw_button inside the group
    local swBtn = field.sw and group.children["sw_button"]
    if swBtn then swBtn.values.x = raw end
    return
  end

  local fader = group.children["control_fader"]
  if not fader then return end

  local faderVal, labelText

  if kind == "u7" then
    local m = maxV or 127
    faderVal  = raw / m
    labelText = tostring(raw)

  elseif kind == "u16" then
    local m = maxV or 255
    faderVal  = raw / m
    labelText = tostring(raw)

  elseif kind == "s7" then
    -- centre 64 → display as signed
    faderVal  = raw / 127
    local signed = raw - 64
    labelText = (signed >= 0 and "+" or "") .. signed

  end

  if faderVal then
    fader.values.x = math.max(0, math.min(1, faderVal))
  end

  local lbl = group.children["value_label"]
  if lbl and labelText then
    lbl.values.text = labelText
  end
end

-- Special-case handler (DIST TYPE etc.)
local function parseSpecial(sp, raw)
  if sp == "dist_type" then
    distType = raw
    local name = DIST_TYPE_NAMES[raw + 1] or tostring(raw)
    local lbl = root:findByName("distortion_section_label", true)
    if lbl then lbl.values.text = "DISTORTION: " .. name end
    -- Note: does NOT send SysEx (we are receiving, not sending).
    return
  end
end

-- ---------------------------------------------------------------------------
-- parseBlock — called from root.lua's handleTB3SysEx and onReceiveOSC
-- addr : {a1, a2, a3, a4}  (4 bytes, 1-indexed Lua table)
-- data : {d1, d2, ...}     (payload bytes, excluding checksum and F7)
-- ---------------------------------------------------------------------------

function parseBlock(addr, data)
  local key = string.format("%02X%02X%02X%02X",
    addr[1], addr[2], addr[3], addr[4])
  local blockDef = REGISTRY[key]
  if not blockDef then return end  -- unknown or pattern block, silently skip

  for _, field in ipairs(blockDef) do
    local off = field.off

    -- Special-case (no raw value extraction needed for dispatch)
    if field.kind == "sp" then
      if off < #data then
        parseSpecial(field.sp, data[off + 1])
      end
    -- 16-bit nibble-packed: two consecutive bytes
    elseif field.kind == "u16" then
      if off + 1 < #data then
        local raw = data[off + 1] * 16 + data[off + 2]
        applyValue(field, raw)
      end
    -- All single-byte kinds
    else
      if off < #data then
        applyValue(field, data[off + 1])
      end
    end
  end
end
