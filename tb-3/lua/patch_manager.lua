-- patch_manager.lua
-- Included into root.lua at build time (comes before root.lua in concatenated script).
-- Provides:
--   parseBlock(addr, data)      — update faders/labels from one SysEx block
--   updateAssignDisplay()       — refresh the assign_status_label
--
-- NOTE ON SCOPING: variables declared as local at the top level here are visible
-- to root.lua (concatenated after) because all includes share one Lua chunk.
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
-- PARAM_ID_MAP — maps "section,enc" paths to hardware parameter IDs.
-- Used by root.lua's assign-mode enc_moved handler.
-- IDs come from the (*1) table in TB-3 Sysex Implementation v1.4.1 by Dope Robot.
-- Value = high_nibble * 16 + low_nibble (from the HH LL columns in the spec).
-- ---------------------------------------------------------------------------

local PARAM_ID_MAP = {
  -- ---- LFO ----
  ["lfo_group,lfo_rate_enc"]      = {id=  0, name="LFO RATE"},
  ["lfo_group,lfo_delay_enc"]     = {id=  1, name="LFO DELAY"},
  ["lfo_group,lfo_wave_saw_enc"]  = {id=  2, name="LFO SAW"},
  ["lfo_group,lfo_wave_sqr_enc"]  = {id=  3, name="LFO SQR"},
  ["lfo_group,lfo_wave_tri_enc"]  = {id=  4, name="LFO TRI"},
  ["lfo_group,lfo_wave_sin_enc"]  = {id=  5, name="LFO SIN"},
  ["lfo_group,lfo_cv_offset_enc"] = {id=  6, name="LFO CV OFFSET"},
  ["lfo_group,lfo_wave_sh_enc"]   = {id=  7, name="LFO S&H"},
  ["vco_group,vco_lfo_depth_enc"] = {id=  8, name="VCO LFO DEPTH"},
  ["vcf_group,vcf_lfo_depth_enc"] = {id=  9, name="VCF LFO DEPTH"},
  ["vca_group,vca_lfo_depth_enc"] = {id= 10, name="VCA LFO DEPTH"},
  -- ---- Tuning (CV offset) ----
  ["tuning_group,sqr_tuning_enc"]      = {id= 13, name="SQR TUNING"},
  ["tuning_group,saw_tuning_enc"]      = {id= 14, name="SAW TUNING"},
  ["tuning_group,ring_sin_tuning_enc"] = {id= 15, name="RING+SIN TUNING"},
  -- ---- Cross Modulation ----
  ["cross_mod_group,sqr_saw_enc"]   = {id= 16, name="CM SQR>SAW"},
  ["cross_mod_group,saw_saw_enc"]   = {id= 18, name="CM SAW>SAW"},
  ["cross_mod_group,white_saw_enc"] = {id= 19, name="CM WHITE>SAW"},
  ["cross_mod_group,pink_saw_enc"]  = {id= 20, name="CM PINK>SAW"},
  ["cross_mod_group,sqr_sqr_enc"]   = {id= 21, name="CM SQR>SQR"},
  ["cross_mod_group,saw_sqr_enc"]   = {id= 23, name="CM SAW>SQR"},
  ["cross_mod_group,white_sqr_enc"] = {id= 24, name="CM WHITE>SQR"},
  ["cross_mod_group,pink_sqr_enc"]  = {id= 25, name="CM PINK>SQR"},
  -- ---- Ring Modulation ----
  ["ring_mod_group,saw_enc"]   = {id= 26, name="RM SAW DEPTH"},
  ["ring_mod_group,sqr_enc"]   = {id= 27, name="RM SQR DEPTH"},
  ["ring_mod_group,ring_enc"]  = {id= 30, name="RM RING DEPTH"},
  ["ring_mod_group,white_enc"] = {id= 31, name="RM WHITE DEPTH"},
  ["ring_mod_group,pink_enc"]  = {id= 32, name="RM PINK DEPTH"},
  ["ring_mod_group,depth_enc"] = {id= 37, name="RM DEPTH"},
  -- ---- VCO ----
  ["vco_group,saw_enc"]          = {id= 40, name="VCO SAW LEVEL"},
  ["vco_group,sqr_enc"]          = {id= 41, name="VCO SQR LEVEL"},
  ["vco_group,sin_enc"]          = {id= 44, name="VCO SIN LEVEL"},
  ["vco_group,white_enc"]        = {id= 45, name="VCO WHITE LEVEL"},
  ["vco_group,pink_enc"]         = {id= 46, name="VCO PINK LEVEL"},
  ["vco_group,ring_enc"]         = {id= 47, name="VCO RING LEVEL"},
  ["vco_group,patch_volume_enc"] = {id= 66, name="MASTER VOLUME"},
  -- ---- VCF ----
  ["vcf_group,vcf_cutoff_enc"]     = {id= 54, name="VCF CUTOFF"},
  ["vcf_group,vcf_resonance_enc"]  = {id= 55, name="VCF RESONANCE"},
  ["vcf_group,vcf_env_depth_enc"]  = {id= 56, name="VCF ENV DEPTH"},
  ["vcf_group,vcf_attack_enc"]     = {id= 57, name="VCF ATTACK"},
  ["vcf_group,vcf_decay_enc"]      = {id= 58, name="VCF DECAY"},
  ["vcf_group,vcf_sustain_enc"]    = {id= 59, name="VCF SUSTAIN"},
  ["vcf_group,vcf_release_enc"]    = {id= 60, name="VCF RELEASE"},
  ["vcf_group,vcf_key_follow_enc"] = {id= 61, name="VCF KEY FOLLOW"},
  ["vcf_group,accent_level_enc"]   = {id=264, name="ACCENT"},
  -- ---- VCA ----
  ["vca_group,vca_attack_enc"]  = {id= 62, name="VCA ATTACK"},
  ["vca_group,vca_decay_enc"]   = {id= 63, name="VCA DECAY"},
  ["vca_group,vca_sustain_enc"] = {id= 64, name="VCA SUSTAIN"},
  ["vca_group,vca_release_enc"] = {id= 65, name="VCA RELEASE"},
  -- ---- Distortion ----
  ["dist_group,dist_drive_enc"]     = {id= 69, name="DIST DRIVE"},
  ["dist_group,dist_bottom_enc"]    = {id= 70, name="DIST BOTTOM"},
  ["dist_group,dist_tone_enc"]      = {id= 71, name="DIST TONE"},
  ["dist_group,dist_efx_level_enc"] = {id= 72, name="DIST EFX LEVEL"},
  ["dist_group,dist_dry_level_enc"] = {id= 73, name="DIST DRY LEVEL"},
  -- ---- Portamento / Pitch Bend ----
  ["portamento_group,porta_time_enc"]       = {id=255, name="PORTA TIME"},
  ["other_group,pitch_bend_range_enc"]      = {id=257, name="BENDER RANGE"},
}

-- SW_PARAM_ID_MAP — switch/button parameter IDs, keyed by "section,enc" path.
-- Same path format as PARAM_ID_MAP but for sw_button and toggle-button controls.
-- Populated by root.lua's "sw_touched" handler.
local SW_PARAM_ID_MAP = {
  -- ---- VCO source switches ----
  ["vco_group,saw_enc"]   = {id= 48, name="VCO SAW SW"},
  ["vco_group,sqr_enc"]   = {id= 49, name="VCO SQR SW"},
  ["vco_group,sin_enc"]   = {id= 50, name="VCO SIN SW"},
  ["vco_group,white_enc"] = {id= 51, name="VCO WH NOISE SW"},
  ["vco_group,pink_enc"]  = {id= 52, name="VCO PK NOISE SW"},
  ["vco_group,ring_enc"]  = {id= 53, name="VCO RING SW"},
  -- ---- LFO push functions ----
  ["lfo_group,lfo_rate_enc"]      = {id= 11, name="LFO BPM SYNC"},
  ["lfo_group,lfo_cv_offset_enc"] = {id= 12, name="LFO RETRIGGER"},
  -- ---- Portamento switch ----
  ["portamento_group,porta_time_enc"] = {id=254, name="PORTA SW"},
  -- ---- Distortion toggles (standalone BUTTON nodes, not sw_button children) ----
  ["dist_group,dist_on_off"] = {id= 67, name="DIST SW",    btn=true},
  ["dist_group,dist_color"]  = {id= 74, name="DIST COLOR", btn=true},
}

-- Reverse lookup: ID → display name (built from PARAM_ID_MAP + SW_PARAM_ID_MAP + EFX tables).
local PARAM_ID_NAMES = {}
for _, info in pairs(PARAM_ID_MAP) do
  PARAM_ID_NAMES[info.id] = info.name
end
for _, info in pairs(SW_PARAM_ID_MAP) do
  PARAM_ID_NAMES[info.id] = info.name
end

-- EFX parameter names keyed by block-relative byte offset.
-- Types CS/RM/BC/TR/CH/FL/PH/DD are identical for EFX1 and EFX2.
local EFX_PARAM_OFF_NAMES = {
  [0x00]="TYPE",
  -- COMP (Compressor / Sustainer)
  [0x01]="CS SW",      [0x02]="CS ATTACK",  [0x03]="CS RELEASE",
  [0x04]="CS THRESH",  [0x05]="CS RATIO",   [0x06]="CS KNEE",
  [0x07]="CS GAIN",    [0x08]="CS BALANCE",
  -- RING MOD
  [0x09]="RM SW",      [0x0A]="RM FREQ",    [0x0B]="RM SENS",
  [0x0C]="RM POLAR",   [0x0D]="RM EQ LOW",  [0x0E]="RM EQ HIGH",
  [0x0F]="RM BALANCE", [0x10]="RM LEVEL",
  -- BIT CRUSH
  [0x11]="BC SW",      [0x12]="BC FILTER",  [0x13]="BC SAMP RATE",
  [0x15]="BC EQ LOW",  [0x16]="BC EQ HIGH", [0x17]="BC LEVEL",
  -- TREMOLO
  [0x18]="TR SW",      [0x19]="TR TYPE",    [0x1A]="TR PHASE",
  [0x1B]="TR RATE",    [0x1C]="TR BPM SYNC",[0x1D]="TR SHAPE",
  [0x1E]="TR DEPTH",   [0x1F]="TR PAN SEL", [0x20]="TR LEVEL",
  -- CHORUS
  [0x21]="CH SW",      [0x22]="CH MODE",    [0x23]="CH RATE",
  [0x24]="CH BPM SYNC",[0x25]="CH DEPTH",   [0x26]="CH PRE DLY",
  [0x27]="CH HPF",     [0x28]="CH LPF",     [0x29]="CH LEVEL",
  -- FLANGER
  [0x2A]="FL SW",      [0x2B]="FL RATE",    [0x2C]="FL BPM SYNC",
  [0x2D]="FL DEPTH",   [0x2E]="FL MANUAL",  [0x2F]="FL RESONANCE",
  [0x30]="FL SEP",     [0x31]="FL HPF",     [0x32]="FL EFX LVL",
  [0x33]="FL DRY LVL",
  -- PHASER
  [0x34]="PH SW",      [0x35]="PH TYPE",    [0x36]="PH RATE",
  [0x37]="PH BPM SYNC",[0x38]="PH DEPTH",   [0x39]="PH MANUAL",
  [0x3A]="PH RESONANCE",[0x3B]="PH STEP RATE",[0x3C]="PH EFX LVL",
  [0x3D]="PH DRY LVL",
  -- DELAY
  [0x3E]="DD SW",      [0x3F]="DD TYPE",    [0x40]="DD TIME",
  [0x41]="DD TAP TIME",[0x42]="DD BPM SYNC",[0x43]="DD FEEDBACK",
  [0x44]="DD LPF",     [0x45]="DD EFX LVL", [0x46]="DD DRY LVL",
}
-- EFX1-specific offsets (PITCH SHIFT type 9, EQ type 10)
local EFX1_PARAM_OFF_NAMES = {
  [0x47]="PS SW",      [0x48]="PS VOICE",     [0x49]="PS PITCH 1",
  [0x4A]="PS PRE DLY 1",[0x4B]="PS FEEDBACK", [0x4C]="PS EFX LVL 1",
  [0x4D]="PS PITCH 2", [0x4E]="PS PRE DLY 2", [0x50]="PS EFX LVL 2",
  [0x51]="PS DRY LVL",
  [0x53]="EQ SW",      [0x54]="EQ LOW CUT",   [0x55]="EQ LOW GAIN",
  [0x56]="EQ LM FREQ", [0x57]="EQ LM Q",      [0x58]="EQ LM GAIN",
  [0x59]="EQ HM FREQ", [0x5A]="EQ HM Q",      [0x5B]="EQ HM GAIN",
  [0x5C]="EQ HI CUT",  [0x5D]="EQ HI GAIN",   [0x5E]="EQ LEVEL",
}
-- EFX2-specific offsets (REVERB type 9)
local EFX2_PARAM_OFF_NAMES = {
  [0x47]="RV SW",      [0x48]="RV TYPE",      [0x49]="RV TIME",
  [0x4A]="RV PRE DLY", [0x4B]="RV HPF",       [0x4C]="RV LPF",
  [0x4D]="RV DENSITY", [0x4E]="RV EFX LVL",   [0x4F]="RV DRY LVL",
  [0x50]="RV SPRING SNS",
}

-- EFX1 base param ID = 76 (0x04 0C); EFX2 base = 171 (0x0A 0B).
-- Param ID = base + block-relative offset.
local EFX_BASE_PARAM = {[1]=76, [2]=171}

-- Populate PARAM_ID_NAMES for all EFX params.
for off, name in pairs(EFX_PARAM_OFF_NAMES) do
  PARAM_ID_NAMES[76  + off] = "E1:" .. name
  PARAM_ID_NAMES[171 + off] = "E2:" .. name
end
for off, name in pairs(EFX1_PARAM_OFF_NAMES) do
  PARAM_ID_NAMES[76  + off] = "E1:" .. name
end
for off, name in pairs(EFX2_PARAM_OFF_NAMES) do
  PARAM_ID_NAMES[171 + off] = "E2:" .. name
end

-- ---------------------------------------------------------------------------
-- Reverse lookup: param ID → "section,enc" path (regular encoders only).
-- Used by root.lua to find the on-screen fader when an assign CC arrives.
local PARAM_ID_TO_PATH = {}
for path, info in pairs(PARAM_ID_MAP) do
  PARAM_ID_TO_PATH[info.id] = path
end

-- EFX current type tracking — updated by efx_section via "efx_type_changed".
-- Must be a local table so root.lua can mutate it by reference.
-- ---------------------------------------------------------------------------

local efxCurType = {[1]=0, [2]=0}

-- ---------------------------------------------------------------------------
-- EFX slot → block-relative byte offset, by [typeIdx][slotIdx].
-- Mirrors TYPE_DEFS slot order in efx_section.lua (not hardware order).
-- nil entries mean the slot is hidden/unused for that type.
-- Types 0–8 are shared between EFX1 and EFX2.
-- ---------------------------------------------------------------------------

local EFX_SLOT_OFFSETS_SHARED = {
  [0] = {},   -- BYPASS
  [1] = {0x04, 0x05, 0x02, 0x03, 0x06, 0x07, 0x08},                            -- COMP
  [2] = {0x0A, 0x0B, 0x0F, 0x10, 0x0D, 0x0E},                                  -- RING MOD
  [3] = {0x12, 0x13, 0x17, nil,  0x15, 0x16},                                   -- BIT CRUSH
  [4] = {0x1C, 0x1B, nil,  nil,  0x1E, 0x19, 0x20, 0x1A, 0x1D},               -- TREMOLO
  [5] = {0x24, 0x23, nil,  nil,  0x25, 0x26, 0x29, 0x27, 0x28},               -- CHORUS
  [6] = {0x2C, 0x2B, nil,  nil,  0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33},  -- FLANGER
  [7] = {0x37, 0x36, 0x3B, nil,  0x38, 0x39, 0x3A, 0x3C, 0x3D},              -- PHASER
  [8] = {0x42, 0x40, nil,  nil,  0x41, 0x43, 0x44, 0x45, 0x46},              -- DELAY
}
-- Type 9 and 10 differ between EFX1 and EFX2.
local EFX_SLOT_OFFSETS_SPECIAL = {
  [1] = {
    [9]  = {0x49, 0x4A, 0x4C, 0x4B, 0x4D, 0x4E, 0x50, 0x51},                 -- PITCH SHIFT
    [10] = {0x54, 0x55, 0x5C, 0x5D, 0x56, 0x57, 0x58, nil, 0x59, 0x5A, 0x5B, 0x5E}, -- EQ
  },
  [2] = {
    [9]  = {0x49, 0x4A, 0x4D, 0x50, 0x4B, 0x4C, 0x4E, 0x4F},                 -- REVERB
  },
}

-- ---------------------------------------------------------------------------
-- Parameter Assign slot state — tracks the PARAM_ID currently assigned to
-- each hardware control slot. Populated by parseSpecial on dump receive and
-- updated by root.lua when the user makes a manual assignment.
-- ---------------------------------------------------------------------------

local assignedParamIds = {
  xy_mod      = nil,
  effect_knob = nil,
  pad_x       = nil,
  pad_y       = nil,
}

-- Per-slot label node names: "assign_<key>_status"
-- Each label sits beneath its corresponding slot button in the assign_group.
local ASSIGN_STATUS_LABELS = {
  xy_mod      = "assign_xy_mod_status",
  effect_knob = "assign_effect_knob_status",
  pad_x       = "assign_pad_x_status",
  pad_y       = "assign_pad_y_status",
}

-- Refresh the four individual assign status labels with the current
-- slot→param-name mapping.  Called from parseSpecial (after dump) and
-- from root.lua's refreshAssignLabel (after a manual assign or mode change).
function updateAssignDisplay()
  for key, lblName in pairs(ASSIGN_STATUS_LABELS) do
    local lbl = root:findByName(lblName, true)
    if lbl then
      local pid  = assignedParamIds[key]
      lbl.values.text = pid and (PARAM_ID_NAMES[pid] or ("ID " .. pid)) or "\226\128\148"
    end
  end
end

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
  -- Bipolar: raw 0–255, centre 128 = 0, display raw−128 (−128…+127).
  -- NOTE: spec labels off=0 as SQR and off=2 as SAW, but hardware is reversed.
  ["10000200"] = {
    {off=0, enc="saw_tuning_enc",      kind="u16", max=151, center=127, bipolar=true},  -- spec says SQR here; hardware is SAW
    {off=2, enc="sqr_tuning_enc",      kind="u16", max=151, center=127, bipolar=true},  -- spec says SAW here; hardware is SQR
    {off=4, enc="ring_sin_tuning_enc", kind="u16", max=151, center=127, bipolar=true},
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
    {off=3, enc="dist_bottom_enc",    kind="u7",  max=100, bipolar=true},
    {off=4, enc="dist_tone_enc",      kind="u7",  max=100, bipolar=true},
    {off=5, enc="dist_efx_level_enc", kind="u7",  max=100},
    {off=6, enc="dist_dry_level_enc", kind="u7",  max=100},
    {off=7, enc="dist_color",         kind="sw",  btn=true},
  },

  -- ---- PARAM ASSIGN / PORTAMENTO  10 00 14 00 ----
  ["10001400"] = {
    {off= 0, enc="porta_time_enc",      kind="sw",  sw=true},  -- PORTA SW
    {off= 1, enc="porta_time_enc",      kind="u7"},             -- PORTA TIME
    {off= 2, kind="sp",                 sp="porta_mode"},       -- PORTA MODE (radio buttons)
    -- Confirmed via hardware probe: raw 0-23, where raw N = ±(N+1) semitones
    -- (0 = ±1 ... 23 = ±24). semitoneRange flag tells applyValue to display
    -- "±N st" instead of the raw byte.
    {off= 3, enc="pitch_bend_range_enc",kind="u7",  max=23, semitoneRange=true},  -- BENDER RANGE
    -- offsets 4–11: PARAM ID assignments (16-bit nibble-packed, u16=true)
    {off= 4, kind="sp", sp="assign_xy_mod",      u16=true},    -- XY PAD MOD param ID
    {off= 6, kind="sp", sp="assign_effect_knob", u16=true},    -- EFFECT KNOB param ID
    {off= 8, kind="sp", sp="assign_pad_x",       u16=true},    -- XY PAD X param ID
    {off=10, kind="sp", sp="assign_pad_y",        u16=true},    -- XY PAD Y param ID
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
    if field.semitoneRange then
      -- Range-size display: raw N → ±(N+1) semitones (BENDER RANGE: 0=±1 ... 23=±24).
      labelText = "\194\177" .. (raw + 1) .. " st"  -- \194\177 = UTF-8 plus-minus sign
    elseif field.bipolar then
      -- Bipolar linear: centre = floor(max/2), display as ±value.
      local half = field.center or math.floor(m / 2)
      local s    = raw - half
      labelText  = (s >= 0 and "+" or "") .. s
    else
      labelText = tostring(raw)
    end

  elseif kind == "u16" then
    local m = maxV or 255
    faderVal  = raw / m
    if field.bipolar then
      -- Use explicit center if set (asymmetric range), else floor(max/2).
      -- e.g. tuning: max=151, center=127 → display −127…+24.
      local half = field.center or math.floor(m / 2)
      local s    = raw - half
      labelText  = (s >= 0 and "+" or "") .. s
    else
      labelText = tostring(raw)
    end

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

-- Special-case handler (DIST TYPE, PORTA MODE etc.)
local function parseSpecial(sp, raw)
  if sp == "dist_type" then
    distType = raw
    local name = DIST_TYPE_NAMES[raw + 1] or tostring(raw)
    local lbl = root:findByName("distortion_section_label", true)
    if lbl then lbl.values.text = "DISTORTION: " .. name end
    -- Note: does NOT send SysEx (we are receiving, not sending).
    return
  end

  if sp == "porta_mode" then
    -- Notify both portamento mode radio buttons so they update silently.
    local legato = root:findByName("porta_legato_btn", true)
    local always  = root:findByName("porta_always_btn", true)
    if legato then legato:notify("porta_mode_updated", tostring(raw)) end
    if always  then always:notify("porta_mode_updated", tostring(raw)) end
    return
  end

  if sp == "assign_xy_mod" then
    assignedParamIds.xy_mod = raw
    updateAssignDisplay()
    return
  end
  if sp == "assign_effect_knob" then
    assignedParamIds.effect_knob = raw
    updateAssignDisplay()
    return
  end
  if sp == "assign_pad_x" then
    assignedParamIds.pad_x = raw
    updateAssignDisplay()
    return
  end
  if sp == "assign_pad_y" then
    assignedParamIds.pad_y = raw
    updateAssignDisplay()
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

    -- Special-case (may be single-byte or 16-bit nibble-packed)
    if field.kind == "sp" then
      if field.u16 then
        -- 16-bit nibble-packed special (e.g. parameter assign ID)
        if off + 1 < #data then
          local raw = data[off + 1] * 16 + data[off + 2]
          parseSpecial(field.sp, raw)
        end
      else
        if off < #data then
          parseSpecial(field.sp, data[off + 1])
        end
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
