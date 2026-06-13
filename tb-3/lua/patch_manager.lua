-- patch_manager.lua
-- Included into root.lua at build time (comes before root.lua in concatenated script).
-- Provides:
--   parseBlock(addr, data)      — update faders/labels from one SysEx block
--   updateAssignDisplay()       — refresh the assign_status_label
--
-- NOTE ON SCOPING: this include exposes a single top-level local table,
-- PatchManager, to root.lua (concatenated after — all includes share one Lua
-- chunk). root.lua references PatchManager.* and must NOT re-declare it.
-- Purely-internal helpers (REGISTRY, applyValue, parseSpecial, the *_OFF_NAMES
-- lookups, etc.) stay file-local and are not part of the namespace.

-- ---------------------------------------------------------------------------
-- PatchManager namespace table. Fields used cross-file by root.lua:
--   distType, DIST_TYPE_NAMES, DIST_NUM_TYPES   distortion type state
--   parseBlock(addr, data)                      update faders/labels from a block
--   updateAssignDisplay()                       refresh the assign status labels
--   PARAM_ID_MAP / SW_PARAM_ID_MAP              "section,enc" → {id, name}
--   PARAM_ID_TO_PATH                            reverse: id → "section,enc"
--   assignedParamIds                            per-slot assigned param IDs
--   efxCurType                                  current EFX type per section
--   EFX_SLOT_OFFSETS_SHARED / _SPECIAL          slot → block byte offset
--   EFX_BASE_PARAM                              EFX param ID base per section
--   U16_OFFSETS                                 nibble-pair offsets for morph
-- ---------------------------------------------------------------------------
local PatchManager = {}

-- ---------------------------------------------------------------------------
-- Distortion type state — shared with root.lua via PatchManager.distType
-- ---------------------------------------------------------------------------

PatchManager.distType = 0

PatchManager.DIST_TYPE_NAMES = {
  "Mid Boost", "Clean Boost", "Treble Bst", "Blues OD",  "Crunch",
  "Natural OD","OD-1",        "T-Scream",   "Turbo OD",  "Warm OD",
  "Distortion","Mild DS",     "Mid DS",     "RAT",        "GUV DS",
  "DST+",      "Modern DS",   "Solid DS",   "Stack",      "Loud",
  "Metal Zone","Lead",        "'60s FUZZ",  "Oct FUZZ",   "MUFF FUZZ",
}

PatchManager.DIST_NUM_TYPES = 25

-- ---------------------------------------------------------------------------
-- PARAM_ID_MAP — maps "section,enc" paths to hardware parameter IDs.
-- Used by root.lua's assign-mode enc_moved handler.
-- IDs come from the (*1) table in TB-3 Sysex Implementation v1.4.1 by Dope Robot.
-- Value = high_nibble * 16 + low_nibble (from the HH LL columns in the spec).
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- PARAM_ID_MAP and SW_PARAM_ID_MAP — derived from Params.LIST
-- (param_defs.lua, loaded first in the concatenated root chunk)
-- ---------------------------------------------------------------------------
-- Derivation rules:
--   PARAM_ID_MAP:    rows with id set, path set, not sw, not btn → {id, name}
--   SW_PARAM_ID_MAP: rows with id set, path set, sw or btn → {id, name, [btn=true]}

PatchManager.PARAM_ID_MAP    = {}
PatchManager.SW_PARAM_ID_MAP = {}

do
  for _, p in ipairs(Params.LIST) do
    if p.id and p.path then
      if p.sw or p.btn then
        local e = {id = p.id, name = p.name}
        if p.btn then e.btn = true end
        PatchManager.SW_PARAM_ID_MAP[p.path] = e
      else
        PatchManager.PARAM_ID_MAP[p.path] = {id = p.id, name = p.name}
      end
    end
  end
end

-- Reverse lookup: ID → display name (built from PARAM_ID_MAP + SW_PARAM_ID_MAP + EFX tables).
-- File-local: only consumed by updateAssignDisplay() below.
local PARAM_ID_NAMES = {}
for _, info in pairs(PatchManager.PARAM_ID_MAP) do
  PARAM_ID_NAMES[info.id] = info.name
end
for _, info in pairs(PatchManager.SW_PARAM_ID_MAP) do
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
PatchManager.EFX_BASE_PARAM = {[1]=76, [2]=171}

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
PatchManager.PARAM_ID_TO_PATH = {}
for path, info in pairs(PatchManager.PARAM_ID_MAP) do
  PatchManager.PARAM_ID_TO_PATH[info.id] = path
end

-- EFX current type tracking — updated by efx_section via "efx_type_changed".
-- A table field so root.lua can mutate it by reference.
-- ---------------------------------------------------------------------------

PatchManager.efxCurType = {[1]=0, [2]=0}

-- ---------------------------------------------------------------------------
-- EFX slot → block-relative byte offset, by [typeIdx][slotIdx].
-- DERIVED from the shared efx_defs Shared Script (require("efx_defs")) — the
-- single source of truth for EFX slot layout (also consumed by efx_section.lua
-- to rebuild TYPE_DEFS). We extract only the byte offsets here so the root chunk
-- carries no EFX names/maxes/display fns. nil entries (hidden/unused slots) are
-- preserved by indexing 1..12, never ipairs. Types 0–8 are shared between EFX1
-- and EFX2; types 9/10 are per-section.
--
-- Before Task 2.2b these tables were hand-mirrored against TYPE_DEFS in the
-- (unreachable) efx_section.lua chunk; the two drifted silently. Now both
-- derive from efx_defs.lua, so the offsets exist in exactly one place.
-- ---------------------------------------------------------------------------

PatchManager.EFX_SLOT_OFFSETS_SHARED  = {}
PatchManager.EFX_SLOT_OFFSETS_SPECIAL = {}

do
  local EfxDefs = require("efx_defs")

  -- Extract { [slotIdx] = off } from a type def's slot rows, preserving holes.
  local function offsetsOf(def)
    local offs = {}
    if def.slots then
      for i = 1, 12 do
        local s = def.slots[i]
        if s then offs[i] = s.off end
      end
    end
    return offs
  end

  for typeIdx, def in pairs(EfxDefs.SHARED) do
    PatchManager.EFX_SLOT_OFFSETS_SHARED[typeIdx] = offsetsOf(def)
  end

  for efxN, types in pairs(EfxDefs.SPECIAL) do
    PatchManager.EFX_SLOT_OFFSETS_SPECIAL[efxN] = {}
    for typeIdx, def in pairs(types) do
      PatchManager.EFX_SLOT_OFFSETS_SPECIAL[efxN][typeIdx] = offsetsOf(def)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Parameter Assign slot state — tracks the PARAM_ID currently assigned to
-- each hardware control slot. Populated by parseSpecial on dump receive and
-- updated by root.lua when the user makes a manual assignment.
-- ---------------------------------------------------------------------------

PatchManager.assignedParamIds = {
  xy_mod      = nil,
  effect_knob = nil,
  pad_x       = nil,
  pad_y       = nil,
}

-- Per-slot label node names: "assign_<key>_status"
-- Each label sits beneath its corresponding slot button in the assign_group.
-- File-local: only consumed by updateAssignDisplay() below.
local ASSIGN_STATUS_LABELS = {
  xy_mod      = "assign_xy_mod_status",
  effect_knob = "assign_effect_knob_status",
  pad_x       = "assign_pad_x_status",
  pad_y       = "assign_pad_y_status",
}

-- Refresh the four individual assign status labels with the current
-- slot→param-name mapping.  Called from parseSpecial (after dump) and
-- from root.lua's refreshAssignLabel (after a manual assign or mode change).
function PatchManager.updateAssignDisplay()
  for key, lblName in pairs(ASSIGN_STATUS_LABELS) do
    local lbl = root:findByName(lblName, true)
    if lbl then
      local pid  = PatchManager.assignedParamIds[key]
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

-- ---------------------------------------------------------------------------
-- REGISTRY — derived from Params.LIST
-- ---------------------------------------------------------------------------
-- Block key = string.format("%02X%02X%02X00", addr[1], addr[2], addr[3])
-- Each row with addr contributes one field entry, in Params.LIST order
-- (which matches HEAD entry order within each block).
--
-- Derivation rules for kind:
--   regSp set  → kind="sp", sp=regSp, [u16=regU16]; no enc
--   btn        → kind="sw", btn=true, enc=<name-after-comma>
--   sw         → kind="sw", sw=true,  enc=<name-after-comma>
--   bits==16   → kind="u16", max=(p.max or 255); carry bipolar/center
--   signed     → kind="s7", enc=<name-after-comma>
--   default    → kind="u7",  enc=<name-after-comma>; max if ≠127; carry bipolar/center/semitoneRange
-- par carried through when set (ring_mod_group name-collision guard).

local REGISTRY = {}
do
  for _, p in ipairs(Params.LIST) do
    if p.addr then
      local blk = string.format("%02X%02X%02X00", p.addr[1], p.addr[2], p.addr[3])
      if not REGISTRY[blk] then REGISTRY[blk] = {} end
      local f
      if p.regSp then
        f = {off = p.addr[4], kind = "sp", sp = p.regSp}
        if p.regU16 then f.u16 = true end
      elseif p.btn then
        f = {off = p.addr[4], enc = p.path:match(",(.+)"), kind = "sw", btn = true}
      elseif p.sw then
        f = {off = p.addr[4], enc = p.path:match(",(.+)"), kind = "sw", sw = true}
      elseif p.bits == 16 then
        f = {off = p.addr[4], enc = p.path:match(",(.+)"), kind = "u16", max = p.max or 255}
        if p.bipolar then f.bipolar = true end
        if p.center  then f.center  = p.center end
      elseif p.signed then
        f = {off = p.addr[4], enc = p.path:match(",(.+)"), kind = "s7"}
      else
        f = {off = p.addr[4], enc = p.path:match(",(.+)"), kind = "u7"}
        if p.max and p.max ~= 127 then f.max = p.max end
        if p.bipolar       then f.bipolar       = true    end
        if p.center        then f.center        = p.center end
        if p.semitoneRange then f.semitoneRange = true    end
      end
      if p.par then f.par = p.par end
      table.insert(REGISTRY[blk], f)
    end
  end
end

-- ---------------------------------------------------------------------------
-- U16_OFFSETS — set of 0-based data byte offsets that are the MSB of a u16
-- nibble pair, keyed by block address string.  Used by applyMorph in root.lua
-- so nibble-packed params are interpolated as a unit (not byte-by-byte).
PatchManager.U16_OFFSETS = {}
do
  for addrKey, blockDef in pairs(REGISTRY) do
    local offs = {}
    for _, field in ipairs(blockDef) do
      if field.kind == "u16" or (field.kind == "sp" and field.u16) then
        offs[field.off] = true
      end
    end
    if next(offs) then PatchManager.U16_OFFSETS[addrKey] = offs end
  end
end

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
    PatchManager.distType = raw
    local name = PatchManager.DIST_TYPE_NAMES[raw + 1] or tostring(raw)
    local encGrp = root:findByName("dist_type_enc", true)
    if encGrp then
      local fader = encGrp.children["control_fader"]
      if fader then
        -- Setting fader.values.x fires enc_moved, but its typeIdx ~= distType guard prevents a redundant SysEx send.
        local n = PatchManager.DIST_NUM_TYPES
        fader.values.x = n > 1 and (PatchManager.distType / (n - 1)) or 0
      end
      local lbl = encGrp.children["value_label"]
      if lbl then lbl.values.text = name end
    end
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
    PatchManager.assignedParamIds.xy_mod = raw
    PatchManager.updateAssignDisplay()
    return
  end
  if sp == "assign_effect_knob" then
    PatchManager.assignedParamIds.effect_knob = raw
    PatchManager.updateAssignDisplay()
    return
  end
  if sp == "assign_pad_x" then
    PatchManager.assignedParamIds.pad_x = raw
    PatchManager.updateAssignDisplay()
    return
  end
  if sp == "assign_pad_y" then
    PatchManager.assignedParamIds.pad_y = raw
    PatchManager.updateAssignDisplay()
    return
  end
end

-- ---------------------------------------------------------------------------
-- parseBlock — called from root.lua's handleTB3SysEx and onReceiveOSC
-- addr : {a1, a2, a3, a4}  (4 bytes, 1-indexed Lua table)
-- data : {d1, d2, ...}     (payload bytes, excluding checksum and F7)
-- ---------------------------------------------------------------------------

function PatchManager.parseBlock(addr, data)
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
