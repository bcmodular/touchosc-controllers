-- efx_section.lua
-- Injected into efx1_section and efx2_section GROUP nodes at build time.
-- Self-identifies as EFX1 (types 0–10) or EFX2 (types 0–9) from self.name.
--
-- Responsibilities:
--   • Stores current type index and raw EFX block bytes in module-level locals.
--   • type_cc  : BCR type encoder rotated (CC value 0–127) → remap slots/buttons.
--   • type_set : on-screen chooser direct select (0-based type index).
--   • type_step: on-screen PREV/NEXT chooser button (±1).
--   • slot_cc  : BCR slot encoder (slot 1–12, CC value) → scale → SysEx.
--   • slot_moved: on-screen slot fader moved (slot name, x float) → SysEx + BCR ring.
--   • btn_press : BCR or on-screen button (index 1–8) → type-specific action.
--   • patch_data: hex CSV string of EFX block bytes from patch dump → full refresh.
--
-- Note: each script context is isolated from root.lua. TB-3 SysEx helpers and
-- connection constants are duplicated here rather than shared as globals.

-- ---------------------------------------------------------------------------
-- Identity: EFX1 or EFX2
-- ---------------------------------------------------------------------------

local efxNum  = tonumber(self.name:match("efx(%d+)_section")) or 1
local BASE    = (efxNum == 1) and {0x10, 0x00, 0x10, 0x00}
                               or {0x10, 0x00, 0x12, 0x00}
local MAX_TYPE = (efxNum == 1) and 10 or 9

-- ---------------------------------------------------------------------------
-- Connection / channel constants (isolated from root.lua context)
-- ---------------------------------------------------------------------------

local TB3_CONN = {false, false, false, false, false, true}  -- connection 6
local BCR_CONN = {false, true}                              -- connection 2
local BCR_CH   = 2                                          -- BCR2000 #2

-- ---------------------------------------------------------------------------
-- BCR CC maps
-- EFX1: slots use left-side fixed-row CCs; EFX2 use right-side.
-- ---------------------------------------------------------------------------

local SLOT_CC, BTN_CC
if efxNum == 1 then
  SLOT_CC = {81,82,83,84, 89,90,91,92, 97,98,99,100}
  BTN_CC  = {65,66,67,68, 73,74,75,76}
else
  SLOT_CC = {85,86,87,88, 93,94,95,96, 101,102,103,104}
  BTN_CC  = {69,70,71,72, 77,78,79,80}
end

-- BCR type-select encoder CC (for ring feedback)
local TYPE_CC = (efxNum == 1) and 1 or 5

-- ---------------------------------------------------------------------------
-- SysEx helpers
-- ---------------------------------------------------------------------------

local function tb3Checksum(addrAndData)
  local sum = 0
  for _, b in ipairs(addrAndData) do sum = sum + b end
  return (0x100 - (sum % 256)) % 128
end

-- Send a single-byte parameter at address BASE + off.
-- All EFX offsets are < 0x60, so the 4th address byte never wraps.
local function sendParam(off, value)
  local a1, a2, a3, a4 = BASE[1], BASE[2], BASE[3], BASE[4] + off
  local cs = tb3Checksum({a1, a2, a3, a4, value})
  sendMIDI({0xF0, 0x41, 0x10, 0x00, 0x00, 0x7B, 0x12,
            a1, a2, a3, a4, value, cs, 0xF7}, TB3_CONN)
end

local function sendBCRcc(cc, ccVal)
  sendMIDI({0xB0 + (BCR_CH - 1), cc, ccVal}, BCR_CONN)
end

-- ---------------------------------------------------------------------------
-- Module-level state (persists across callbacks in this script context)
-- ---------------------------------------------------------------------------

local curType    = 0      -- current effect type index
local rawData    = {}     -- raw EFX block bytes (0-based offset → rawData[off+1])
local bpmDiv     = {}     -- [off] = last non-zero BPM/step division (for toggle restore)

-- ---------------------------------------------------------------------------
-- EFX type definitions — shared types (0–8 same for EFX1 and EFX2)
-- ---------------------------------------------------------------------------
-- slot entry: { off, name, max }
--   off  : byte offset from EFX block start (0-based hex)
--   name : slot display label
--   max  : full-scale SysEx value
-- btn entry (B2–B8): { off, name, action, val, max }
--   action: "set"       → write val to offset (fixed-value setter); auto-reset BCR latch
--           "toggle"    → toggle 0 ↔ 1 at offset
--           "bpm_sync"  → toggle 0 ↔ last-non-zero at offset (BPM div or step rate)
--   val   : value for "set" actions
--   max   : max for "bpm_sync" (informational)

local TYPE_DEFS = {

  -- 0: BYPASS — no slots, no buttons (just show label)
  [0] = { name="BYPASS" },

  -- 1: CS — Compressor/Sustainer
  -- SW at 0x01, params at 0x02–0x08
  [1] = { name="COMP",
    swOff = 0x01,
    slots = {
      {off=0x04, name="THRESHOLD", max=40},
      {off=0x05, name="RATIO",     max=13},
      {off=0x02, name="ATTACK",    max=124},
      {off=0x03, name="RELEASE",   max=124},
      {off=0x06, name="KNEE",      max=9},
      {off=0x07, name="GAIN",      max=80},
      {off=0x08, name="BALANCE",   max=100},
      -- S08–S12 spare
    },
    btns = {
      -- B2: RATIO preset 1:2
      {off=0x05, name="1:2",   action="set", val=6},
      -- B3: RATIO preset 1:4
      {off=0x05, name="1:4",   action="set", val=8},
      -- B4: RATIO preset 1:INF
      {off=0x05, name="1:INF", action="set", val=13},
      -- B5–B7 spare
    },
  },

  -- 2: RM — Ring Modulator
  -- SW at 0x09, params at 0x0A–0x10
  [2] = { name="RING MOD",
    swOff = 0x09,
    slots = {
      {off=0x0A, name="FREQ",    max=127},
      {off=0x0B, name="SENS",    max=127},
      {off=0x0F, name="BALANCE", max=100},
      {off=0x10, name="LEVEL",   max=127},
      {off=0x0D, name="EQ LOW",  max=30},
      {off=0x0E, name="EQ HIGH", max=30},
      -- S07–S12 spare
    },
    btns = {
      -- B2: POLARITY toggle (0=UP, 1=DOWN)
      {off=0x0C, name="POLARITY", action="toggle", max=1},
      -- B3–B7 spare
    },
  },

  -- 3: BC — Bit Crusher
  -- SW at 0x11, params at 0x12–0x17
  [3] = { name="BIT CRUSH",
    swOff = 0x11,
    slots = {
      {off=0x12, name="FILTER",   max=127},
      {off=0x13, name="SAMP RATE",max=127},
      {off=0x17, name="LEVEL",    max=127},
      -- S04 spare
      nil,
      {off=0x15, name="EQ LOW",   max=30},
      {off=0x16, name="EQ HIGH",  max=30},
      -- S07–S12 spare
    },
    btns = {},
  },

  -- 4: TR — Tremolo
  -- SW at 0x18, params at 0x19–0x20
  [4] = { name="TREMOLO",
    swOff = 0x18,
    slots = {
      {off=0x1B, name="RATE",  max=100},
      {off=0x1E, name="DEPTH", max=100},
      {off=0x19, name="TYPE",  max=5},
      {off=0x20, name="LEVEL", max=100},
      {off=0x1A, name="PHASE", max=100},
      {off=0x1D, name="SHAPE", max=100},
      -- S07–S12 spare
    },
    btns = {
      -- B2: BPM SYNC toggle (0=off, non-zero=division)
      {off=0x1C, name="BPM SYNC", action="bpm_sync", max=20},
      -- B3: PAN/TRE select toggle (0=TREMOLO, 1=PAN)
      {off=0x1F, name="PAN/TRE",  action="toggle",   max=1},
      -- B4–B7 spare
    },
  },

  -- 5: CH — Chorus
  -- SW at 0x21, params at 0x22–0x29
  [5] = { name="CHORUS",
    swOff = 0x21,
    slots = {
      {off=0x23, name="RATE",    max=100},
      {off=0x25, name="DEPTH",   max=100},
      {off=0x26, name="PRE DLY", max=80},
      {off=0x29, name="LEVEL",   max=100},
      {off=0x27, name="HPF",     max=17},
      {off=0x28, name="LPF",     max=14},
      -- S07–S12 spare
    },
    btns = {
      -- B2: BPM SYNC toggle
      {off=0x24, name="BPM SYNC", action="bpm_sync", max=20},
      -- B3: MODE MONO
      {off=0x22, name="MONO",     action="set", val=0},
      -- B4: MODE STEREO1
      {off=0x22, name="STEREO1",  action="set", val=1},
      -- B5: MODE STEREO2
      {off=0x22, name="STEREO2",  action="set", val=2},
      -- B6–B7 spare
    },
  },

  -- 6: FL — Flanger
  -- SW at 0x2A, params at 0x2B–0x33
  [6] = { name="FLANGER",
    swOff = 0x2A,
    slots = {
      {off=0x2B, name="RATE",      max=100},
      {off=0x2D, name="DEPTH",     max=100},
      {off=0x2E, name="MANUAL",    max=100},
      {off=0x2F, name="RESONANCE", max=100},
      {off=0x30, name="SEPARATN",  max=100},
      {off=0x31, name="HPF",       max=10},
      {off=0x32, name="EFX LVL",   max=100},
      {off=0x33, name="DIRECT LVL",max=100},
      -- S09–S12 spare
    },
    btns = {
      -- B2: BPM SYNC toggle
      {off=0x2C, name="BPM SYNC", action="bpm_sync", max=20},
      -- B3–B7 spare
    },
  },

  -- 7: PH — Phaser
  -- SW at 0x34, params at 0x35–0x3D
  [7] = { name="PHASER",
    swOff = 0x34,
    slots = {
      {off=0x36, name="RATE",      max=100},
      {off=0x38, name="DEPTH",     max=100},
      {off=0x39, name="MANUAL",    max=100},
      {off=0x3A, name="RESONANCE", max=127},
      {off=0x3C, name="EFX LVL",   max=100},
      {off=0x3D, name="DIRECT LVL",max=100},
      -- S07–S12 spare
    },
    btns = {
      -- B2: BPM SYNC toggle
      {off=0x37, name="BPM SYNC",  action="bpm_sync", max=20},
      -- B3: STEP RATE toggle (same bpm_sync pattern)
      {off=0x3B, name="STEP RATE", action="bpm_sync", max=20},
      -- B4: TYPE 4STAGE
      {off=0x35, name="4STAGE",    action="set", val=0},
      -- B5: TYPE 8STAGE
      {off=0x35, name="8STAGE",    action="set", val=1},
      -- B6: TYPE 12STAGE
      {off=0x35, name="12STAGE",   action="set", val=2},
      -- B7: TYPE BI-PHASE
      {off=0x35, name="BI-PH",     action="set", val=3},
    },
  },

  -- 8: DD — Digital Delay
  -- SW at 0x3E, params at 0x3F–0x46
  [8] = { name="DELAY",
    swOff = 0x3E,
    slots = {
      {off=0x40, name="TIME",      max=100},
      {off=0x41, name="TAP TIME",  max=100},
      {off=0x43, name="FEEDBACK",  max=100},
      {off=0x44, name="LPF",       max=14},
      {off=0x45, name="EFX LVL",   max=100},
      {off=0x46, name="DIRECT LVL",max=100},
      -- S07–S12 spare
    },
    btns = {
      -- B2: BPM SYNC toggle
      {off=0x42, name="BPM SYNC", action="bpm_sync", max=20},
      -- B3: TYPE SINGLE
      {off=0x3F, name="SINGLE",   action="set", val=0},
      -- B4: TYPE PAN
      {off=0x3F, name="PAN",      action="set", val=1},
      -- B5: TYPE STEREO
      {off=0x3F, name="STEREO",   action="set", val=2},
      -- B6–B7 spare
    },
  },
}

-- ---------------------------------------------------------------------------
-- EFX1-specific types (PS type 9, EQ type 10)
-- ---------------------------------------------------------------------------

if efxNum == 1 then

  -- 9: PS — Pitch Shifter (EFX1 only)
  TYPE_DEFS[9] = { name="PITCH SHIFT",
    swOff = 0x47,
    slots = {
      {off=0x49, name="PITCH 1",   max=48},
      {off=0x4A, name="PRE DLY 1", max=100},
      {off=0x4C, name="EFX LVL 1", max=100},
      {off=0x4B, name="FEEDBACK",  max=100},
      {off=0x4D, name="PITCH 2",   max=48},
      {off=0x4E, name="PRE DLY 2", max=100},
      {off=0x50, name="EFX LVL 2", max=100},
      {off=0x51, name="DIRECT LVL",max=100},
      -- S09–S12 spare
    },
    btns = {
      -- B2: VOICE 1MONO
      {off=0x48, name="1MONO",   action="set", val=0},
      -- B3: VOICE 2MONO
      {off=0x48, name="2MONO",   action="set", val=1},
      -- B4: VOICE 2STEREO
      {off=0x48, name="2STEREO", action="set", val=2},
      -- B5–B7 spare
    },
  }

  -- 10: EQ — Parametric EQ (EFX1 only), uses all 12 slots
  TYPE_DEFS[10] = { name="EQ",
    swOff = 0x53,
    slots = {
      {off=0x54, name="LOW CUT",  max=17},
      {off=0x55, name="LOW GAIN", max=40},
      {off=0x5C, name="HI CUT",   max=14},
      {off=0x5D, name="HI GAIN",  max=40},
      {off=0x56, name="LM FREQ",  max=27},
      {off=0x57, name="LM Q",     max=5},
      {off=0x58, name="LM GAIN",  max=40},
      -- S08 spare
      nil,
      {off=0x59, name="HM FREQ",  max=27},
      {off=0x5A, name="HM Q",     max=5},
      {off=0x5B, name="HM GAIN",  max=40},
      {off=0x5E, name="LEVEL",    max=40},
    },
    btns = {},
  }

-- ---------------------------------------------------------------------------
-- EFX2-specific types (RV type 9 — no PS or EQ)
-- ---------------------------------------------------------------------------

else  -- efxNum == 2

  -- 9: RV — Reverb (EFX2 only)
  TYPE_DEFS[9] = { name="REVERB",
    swOff = 0x47,
    slots = {
      {off=0x49, name="TIME",      max=99},
      {off=0x4A, name="PRE DLY",   max=100},
      {off=0x4D, name="DENSITY",   max=10},
      {off=0x50, name="SPRING SNS",max=100},
      {off=0x4B, name="HPF",       max=17},
      {off=0x4C, name="LPF",       max=14},
      {off=0x4E, name="EFX LVL",   max=100},
      {off=0x4F, name="DIRECT LVL",max=100},
      -- S09–S12 spare
    },
    btns = {
      -- B2–B8: reverb type presets (write to RV TYPE offset 0x48)
      {off=0x48, name="AMBIENT", action="set", val=0},
      {off=0x48, name="ROOM",    action="set", val=1},
      {off=0x48, name="HALL 1",  action="set", val=2},
      {off=0x48, name="HALL 2",  action="set", val=3},
      {off=0x48, name="PLATE",   action="set", val=4},
      {off=0x48, name="SPRING",  action="set", val=5},
      {off=0x48, name="MOD",     action="set", val=6},
    },
  }

end

-- ---------------------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------------------

local function slotGroupName(i)
  return string.format("efx%d_s%02d", efxNum, i)
end

local function btnNodeName(i)
  return string.format("efx%d_b%d", efxNum, i)
end

local function updateLabel(text)
  local lbl = self.children["efx" .. efxNum .. "_label"]
  if lbl then lbl.values.text = text end
end

-- Helper: get the chooser button group for this section
local function chooserGroup()
  return self.children["efx_" .. efxNum .. "_chooser"]
end

-- Helper: get the B-button labels group for this section
local function btnLabelsGroup()
  return self.children["efx" .. efxNum .. "_b_labels"]
end

-- ---------------------------------------------------------------------------
-- applyType — remaps all slots, buttons, BCR rings, and labels for typeIdx.
-- Reads parameter values from rawData if available, otherwise shows zeroed state.
-- ---------------------------------------------------------------------------

local function applyType(typeIdx)
  curType = typeIdx
  local def = TYPE_DEFS[typeIdx]

  -- Section label
  updateLabel("EFX" .. efxNum .. ": " .. (def and def.name or "???"))

  -- Sync BCR type encoder ring
  local typeCCval = (MAX_TYPE > 0) and math.floor(typeIdx / MAX_TYPE * 127 + 0.5) or 0
  sendBCRcc(TYPE_CC, typeCCval)

  -- Radio-button state on chooser (one lit, rest off; none for BYPASS)
  local cgrp = chooserGroup()
  if cgrp then
    for i = 1, MAX_TYPE do
      local cb = cgrp.children[tostring(i)]
      if cb then cb.values.x = (i == curType) and 1 or 0 end
    end
  end

  -- Slot faders (S01–S12) — hide unused slots
  for i = 1, 12 do
    local slotGrp = self.children[slotGroupName(i)]
    if slotGrp then
      local slotDef = def and def.slots and def.slots[i]
      slotGrp.visible = (slotDef ~= nil)

      if slotDef then
        local fader   = slotGrp.children["control_fader"]
        local nameLbl = slotGrp.children["name_label"]
        local valLbl  = slotGrp.children["value_label"]

        if nameLbl then nameLbl.values.text = slotDef.name end

        if slotDef and #rawData > 0 then
          local raw = rawData[slotDef.off + 1] or 0
          local x   = math.max(0, math.min(1, raw / slotDef.max))
          if fader  then fader.values.x     = x end
          if valLbl then valLbl.values.text = tostring(raw) end
          sendBCRcc(SLOT_CC[i], math.floor(x * 127 + 0.5))
        else
          if fader  then fader.values.x     = 0 end
          if valLbl then valLbl.values.text = "--" end
          sendBCRcc(SLOT_CC[i], 0)
        end
      else
        sendBCRcc(SLOT_CC[i], 0)
      end
    end
  end

  -- B buttons + their labels — hide unused; B1 = SW, B2-B8 = per-type
  local lblGrp = btnLabelsGroup()

  -- B1: EFX SW — visible only when a real effect is active
  local hasSW  = (def ~= nil and def.swOff ~= nil)
  local b1     = self.children[btnNodeName(1)]
  local lbl1   = lblGrp and lblGrp.children["1"]
  if b1 then
    b1.visible = hasSW
    if hasSW then
      local swVal = (#rawData > 0) and (rawData[def.swOff + 1] or 0) or 0
      b1.values.x = swVal
      sendBCRcc(BTN_CC[1], swVal * 127)
    else
      sendBCRcc(BTN_CC[1], 0)
    end
  end
  if lbl1 then
    lbl1.visible    = hasSW
    lbl1.values.text = "ON/OFF"
  end

  -- B2–B8: per-effect action buttons
  for i = 2, 8 do
    local btn    = self.children[btnNodeName(i)]
    local lbl    = lblGrp and lblGrp.children[tostring(i)]
    local btnDef = def and def.btns and def.btns[i - 1]
    local bcrVal = 0
    local uiVal  = 0

    if btnDef then
      if btnDef.action == "toggle" then
        local cur = (#rawData > 0) and (rawData[btnDef.off + 1] or 0) or 0
        uiVal  = (cur > 0) and 1 or 0
        bcrVal = uiVal * 127
      elseif btnDef.action == "bpm_sync" then
        local cur = (#rawData > 0) and (rawData[btnDef.off + 1] or 0) or 0
        uiVal  = (cur > 0) and 1 or 0
        bcrVal = uiVal * 127
        if cur > 0 then bpmDiv[btnDef.off] = cur end
      end
      -- "set" buttons: momentary, always shown off
    end

    if btn then
      btn.visible  = (btnDef ~= nil)
      btn.values.x = uiVal
    end
    if lbl then
      lbl.visible     = (btnDef ~= nil)
      lbl.values.text = btnDef and btnDef.name or ""
    end
    sendBCRcc(BTN_CC[i], bcrVal)
  end
end

-- ---------------------------------------------------------------------------
-- Slot SysEx send helpers
-- ---------------------------------------------------------------------------

local function sendSlotFromFloat(slotIdx, x)
  local def     = TYPE_DEFS[curType]
  local slotDef = def and def.slots and def.slots[slotIdx]
  if not slotDef then return end
  local raw = math.floor(x * slotDef.max + 0.5)
  sendParam(slotDef.off, raw)
  rawData[slotDef.off + 1] = raw
  -- Update value label
  local slotGrp = self.children[slotGroupName(slotIdx)]
  if slotGrp then
    local valLbl = slotGrp.children["value_label"]
    if valLbl then valLbl.values.text = tostring(raw) end
  end
end

local function sendSlotFromCC(slotIdx, ccVal)
  local def     = TYPE_DEFS[curType]
  local slotDef = def and def.slots and def.slots[slotIdx]
  if not slotDef then return end
  local raw = math.floor(ccVal / 127 * slotDef.max + 0.5)
  sendParam(slotDef.off, raw)
  rawData[slotDef.off + 1] = raw
  -- Update slot fader + label
  local slotGrp = self.children[slotGroupName(slotIdx)]
  if slotGrp then
    local fader  = slotGrp.children["control_fader"]
    local valLbl = slotGrp.children["value_label"]
    if fader  then fader.values.x       = raw / slotDef.max end
    if valLbl then valLbl.values.text   = tostring(raw) end
  end
end

-- ---------------------------------------------------------------------------
-- onReceiveNotify — all cross-node communication
-- ---------------------------------------------------------------------------

function onReceiveNotify(key, value)

  -- BCR type encoder rotated (0–127 CC → 0–MAX_TYPE type index)
  if key == "type_cc" then
    local ccVal   = tonumber(value) or 0
    local typeIdx = math.floor(ccVal / 127 * MAX_TYPE + 0.5)
    applyType(typeIdx)
    return
  end

  -- Direct type select from on-screen chooser (button name = 1-based type index).
  -- Re-pressing the active type toggles to BYPASS (0).
  if key == "type_set" then
    local typeIdx = math.min(math.max(tonumber(value) or 0, 0), MAX_TYPE)
    if typeIdx ~= 0 and typeIdx == curType then typeIdx = 0 end  -- toggle off → BYPASS
    applyType(typeIdx)
    return
  end

  -- PREV (−1) or NEXT (+1) from on-screen chooser buttons
  if key == "type_step" then
    local dir     = tonumber(value) or 0
    local typeIdx = ((curType + dir) % (MAX_TYPE + 1) + (MAX_TYPE + 1)) % (MAX_TYPE + 1)
    applyType(typeIdx)
    return
  end

  -- Full EFX block received from TB-3 patch dump.
  -- value = hex CSV string: "00,7F,3C,..." (one token per byte)
  if key == "patch_data" then
    rawData = {}
    for hex in value:gmatch("[^,]+") do
      rawData[#rawData + 1] = tonumber(hex, 16) or 0
    end
    local typeIdx = rawData[1] or 0
    applyType(typeIdx)
    return
  end

  -- BCR slot encoder turned: "slotIdx,ccVal" (slot 1–12, CC 0–127)
  if key == "slot_cc" then
    local si, cv = value:match("^(%d+),(%d+)$")
    local slotIdx = tonumber(si)
    local ccVal   = tonumber(cv) or 0
    if not slotIdx then return end
    sendSlotFromCC(slotIdx, ccVal)
    return
  end

  -- On-screen slot fader moved by user: "efxN_sXX,x" forwarded by root.lua
  if key == "slot_moved" then
    local encName, xs = value:match("^([^,]+),(.+)$")
    if not encName then return end
    local slotIdx = tonumber(encName:match("efx%d+_s(%d+)"))
    if not slotIdx then return end
    local x = tonumber(xs) or 0
    sendSlotFromFloat(slotIdx, x)
    -- Mirror to BCR ring
    sendBCRcc(SLOT_CC[slotIdx], math.floor(x * 127 + 0.5))
    return
  end

  -- BCR or on-screen button press: button index 1–8
  if key == "btn_press" then
    local btnIdx = tonumber(value) or 0
    if btnIdx < 1 or btnIdx > 8 then return end
    local def = TYPE_DEFS[curType]

    -- B1: EFX SW toggle (universal)
    if btnIdx == 1 then
      if not def or not def.swOff then return end
      local cur = rawData[def.swOff + 1] or 0
      local nxt = 1 - cur
      sendParam(def.swOff, nxt)
      rawData[def.swOff + 1] = nxt
      local b1 = self.children[btnNodeName(1)]
      if b1 then b1.values.x = nxt end
      sendBCRcc(BTN_CC[1], nxt * 127)
      return
    end

    -- B2–B8: per-effect action
    local btnDef = def and def.btns and def.btns[btnIdx - 1]
    if not btnDef then return end

    if btnDef.action == "set" then
      -- Fixed-value setter (e.g. CS RATIO preset, CH MODE, PH TYPE, RV TYPE, PS VOICE)
      sendParam(btnDef.off, btnDef.val)
      rawData[btnDef.off + 1] = btnDef.val
      -- Auto-reset BCR latch so every press triggers
      sendBCRcc(BTN_CC[btnIdx], 0)

    elseif btnDef.action == "toggle" then
      -- Simple binary toggle (e.g. RM POLARITY, TR PAN/TRE)
      local cur = rawData[btnDef.off + 1] or 0
      local nxt = 1 - cur
      sendParam(btnDef.off, nxt)
      rawData[btnDef.off + 1] = nxt
      local btn = self.children[btnNodeName(btnIdx)]
      if btn then btn.values.x = nxt end
      sendBCRcc(BTN_CC[btnIdx], nxt * 127)

    elseif btnDef.action == "bpm_sync" then
      -- Toggle between 0 (off) and last-non-zero division
      local cur = rawData[btnDef.off + 1] or 0
      local nxt
      if cur > 0 then
        bpmDiv[btnDef.off] = cur  -- cache before zeroing
        nxt = 0
      else
        nxt = bpmDiv[btnDef.off] or 8  -- 8 = 1/4 note as default
      end
      sendParam(btnDef.off, nxt)
      rawData[btnDef.off + 1] = nxt
      local btn = self.children[btnNodeName(btnIdx)]
      local uiV = (nxt > 0) and 1 or 0
      if btn then btn.values.x = uiV end
      sendBCRcc(BTN_CC[btnIdx], uiV * 127)
    end

    return
  end
end

-- ---------------------------------------------------------------------------
-- init
-- ---------------------------------------------------------------------------

function init()
  -- rawData is empty on load; applyType(0) shows BYPASS state with zeroed slots.
  -- Once the user presses RECEIVE, patch_data will populate rawData and re-apply.
  applyType(0)
end
