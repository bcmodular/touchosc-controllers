-- efx_section.lua
-- Injected into efx1_section and efx2_section GROUP nodes at build time.
-- Self-identifies as EFX1 (types 0–10) or EFX2 (types 0–9) from self.name.
--
-- Colour tiers (set dynamically via Color.fromHexString so all effects,
-- including Reverb whose type buttons span B2–B8, are coloured correctly):
--   SEL_HEX  — "selector" accent: chooser grid labels + type-option radio buttons
--   BASE_HEX — section base: knobs, SW, utility buttons (BPM SYNC, POLARITY…)
--
-- Toggle Release guard: self.tag = "prog" during all programmatic button value
-- writes so efx_button.lua / efx_chooser_button.lua can distinguish user presses
-- from re-entrant programmatic changes.
--
-- Text colour: label textColor flips black (ON_TXT) when button is active so
-- the text stays readable against the bright lit button background.

-- ---------------------------------------------------------------------------
-- Identity: EFX1 or EFX2
-- ---------------------------------------------------------------------------

local efxNum  = tonumber(self.name:match("efx(%d+)_section")) or 1
local BASE    = (efxNum == 1) and {0x10, 0x00, 0x10, 0x00}
                               or {0x10, 0x00, 0x12, 0x00}
local MAX_TYPE = (efxNum == 1) and 10 or 9

-- ---------------------------------------------------------------------------
-- Connection / channel constants
-- ---------------------------------------------------------------------------

local TB3_CONN = {false, false, false, false, false, true}  -- connection 6
local BCR_CONN = {false, true}                              -- connection 2
local BCR_CH   = 2                                          -- BCR2000 #2

-- ---------------------------------------------------------------------------
-- BCR CC maps
-- ---------------------------------------------------------------------------

local SLOT_CC, BTN_CC
if efxNum == 1 then
  SLOT_CC = {81,82,83,84, 89,90,91,92, 97,98,99,100}
  BTN_CC  = {65,66,67,68, 73,74,75,76}
else
  SLOT_CC = {85,86,87,88, 93,94,95,96, 101,102,103,104}
  BTN_CC  = {69,70,71,72, 77,78,79,80}
end

local TYPE_CC = (efxNum == 1) and 1 or 5

-- ---------------------------------------------------------------------------
-- Colour hex strings for Color.fromHexString (RRGGBBAA, 8 hex chars)
-- Selector tier = effect-type chooser grid + type-option radio buttons.
-- Base tier     = knobs, SW, BPM SYNC, POLARITY, etc.
-- Text colours  = white when button unlit, black when button lit.
-- ---------------------------------------------------------------------------

-- EFX1 selector ≈ (0.70, 0.95, 1.00) — pale icy cyan, near-white
-- EFX1 base     ≈ (0.20, 0.70, 0.75) — teal
-- EFX2 selector ≈ (1.00, 0.65, 0.35) — bright coral-orange
-- EFX2 base     ≈ (0.85, 0.38, 0.12) — coral/rust
local SEL_HEX  = (efxNum == 1) and "B3F2FFFF" or "FFA659FF"
local BASE_HEX = (efxNum == 1) and "33B3BFFF" or "D9611FFF"
local ON_TXT   = "000000FF"   -- black: readable on lit (bright) button
local OFF_TXT  = "FFFFFFFF"   -- white: readable on unlit (dark) button

-- ---------------------------------------------------------------------------
-- SysEx helpers
-- ---------------------------------------------------------------------------

local function tb3Checksum(addrAndData)
  local sum = 0
  for _, b in ipairs(addrAndData) do sum = sum + b end
  return (0x100 - (sum % 256)) % 128
end

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
-- BPM sync beat-division display strings (index 1 = value 0 = "OFF")
-- Source: Unofficial TB-3 FX Parameter Guide v1.07 (Dope Robot)
-- ---------------------------------------------------------------------------

local BPM_DIVS = {
  "OFF",   "2",    "3/2",  "4/3",  "1",
  "3/4",   "2/3",  "1/2",  "3/8",  "1/3",
  "1/4",   "3/16", "1/6",  "1/8",  "3/32",
  "1/12",  "1/16", "3/64", "1/24", "1/32",
  "3/128"
}

-- ---------------------------------------------------------------------------
-- Module-level state
-- ---------------------------------------------------------------------------

local curType    = 0
local rawData    = {}
local bpmDiv     = {}

-- ---------------------------------------------------------------------------
-- EFX type definitions
-- ---------------------------------------------------------------------------
-- slot  : { off, name, max }
-- btn   : { off, name, action, val, max }
--   action "set"      → radio preset; write val; light this, unlight siblings
--   action "toggle"   → binary flip at offset
--   action "bpm_sync" → toggle 0 ↔ last-non-zero
--
-- Type-option ("set") buttons sit at the bottom row (btns[4]–[7] = B5–B8)
-- where possible.  Reverb fills all 7 slots B2–B8 (btns[1]–[7]).
-- Dynamic Lua coloring in applyType correctly handles all cases.

local TYPE_DEFS = {

  [0] = { name="BYPASS" },

  -- 1: COMP — Compressor/Sustainer
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
    },
    btns = {
      nil, nil, nil,
      {off=0x05, name="1:2",   action="set", val=6},
      {off=0x05, name="1:4",   action="set", val=8},
      {off=0x05, name="1:INF", action="set", val=13},
    },
  },

  -- 2: RING MOD
  [2] = { name="RING MOD",
    swOff = 0x09,
    slots = {
      {off=0x0A, name="FREQ",    max=127},
      {off=0x0B, name="SENS",    max=127},
      {off=0x0F, name="BALANCE", max=100},
      {off=0x10, name="LEVEL",   max=127},
      {off=0x0D, name="EQ LOW",  max=30},
      {off=0x0E, name="EQ HIGH", max=30},
    },
    btns = {
      {off=0x0C, name="POLARITY", action="toggle", max=1},
    },
  },

  -- 3: BIT CRUSH
  [3] = { name="BIT CRUSH",
    swOff = 0x11,
    slots = {
      {off=0x12, name="FILTER",    max=127},
      {off=0x13, name="SAMP RATE", max=127},
      {off=0x17, name="LEVEL",     max=127},
      nil,
      {off=0x15, name="EQ LOW",   max=30},
      {off=0x16, name="EQ HIGH",  max=30},
    },
    btns = {},
  },

  -- 4: TREMOLO
  [4] = { name="TREMOLO",
    swOff = 0x18,
    slots = {
      {off=0x1B, name="RATE",  max=100, bpmSync={off=0x1C}},
      {off=0x1E, name="DEPTH", max=100},
      {off=0x19, name="TYPE",  max=5},
      {off=0x20, name="LEVEL", max=100},
      {off=0x1A, name="PHASE", max=100},
      {off=0x1D, name="SHAPE", max=100},
    },
    btns = {
      {off=0x1C, name="BPM SYNC", action="bpm_sync", max=20},
      nil, nil,
      {off=0x1F, name="TREMOLO",  action="set", val=0},
      {off=0x1F, name="PAN",      action="set", val=1},
    },
  },

  -- 5: CHORUS
  [5] = { name="CHORUS",
    swOff = 0x21,
    slots = {
      {off=0x23, name="RATE",    max=100, bpmSync={off=0x24}},
      {off=0x25, name="DEPTH",   max=100},
      {off=0x26, name="PRE DLY", max=80},
      {off=0x29, name="LEVEL",   max=100},
      {off=0x27, name="HPF",     max=17},
      {off=0x28, name="LPF",     max=14},
    },
    btns = {
      {off=0x24, name="BPM SYNC", action="bpm_sync", max=20},
      nil, nil,
      {off=0x22, name="MONO",    action="set", val=0},
      {off=0x22, name="STEREO1", action="set", val=1},
      {off=0x22, name="STEREO2", action="set", val=2},
    },
  },

  -- 6: FLANGER
  [6] = { name="FLANGER",
    swOff = 0x2A,
    slots = {
      {off=0x2B, name="RATE",       max=100, bpmSync={off=0x2C}},
      {off=0x2D, name="DEPTH",      max=100},
      {off=0x2E, name="MANUAL",     max=100},
      {off=0x2F, name="RESONANCE",  max=100},
      {off=0x30, name="SEPARATN",   max=100},
      {off=0x31, name="HPF",        max=10},
      {off=0x32, name="EFX LVL",    max=100},
      {off=0x33, name="DIRECT LVL", max=100},
    },
    btns = {
      {off=0x2C, name="BPM SYNC", action="bpm_sync", max=20},
    },
  },

  -- 7: PHASER
  [7] = { name="PHASER",
    swOff = 0x34,
    slots = {
      {off=0x36, name="RATE",       max=100, bpmSync={off=0x37}},
      {off=0x38, name="DEPTH",      max=100},
      {off=0x39, name="MANUAL",     max=100},
      {off=0x3A, name="RESONANCE",  max=127},
      {off=0x3C, name="EFX LVL",    max=100},
      {off=0x3D, name="DIRECT LVL", max=100},
    },
    btns = {
      {off=0x37, name="BPM SYNC",  action="bpm_sync", max=20},
      {off=0x3B, name="STEP RATE", action="bpm_sync", max=20},
      nil,
      {off=0x35, name="4STAGE",  action="set", val=0},
      {off=0x35, name="8STAGE",  action="set", val=1},
      {off=0x35, name="12STAGE", action="set", val=2},
      {off=0x35, name="BI-PH",   action="set", val=3},
    },
  },

  -- 8: DELAY
  [8] = { name="DELAY",
    swOff = 0x3E,
    slots = {
      {off=0x40, name="TIME",       max=100, bpmSync={off=0x42}},
      {off=0x41, name="TAP TIME",   max=100},
      {off=0x43, name="FEEDBACK",   max=100},
      {off=0x44, name="LPF",        max=14},
      {off=0x45, name="EFX LVL",    max=100},
      {off=0x46, name="DIRECT LVL", max=100},
    },
    btns = {
      {off=0x42, name="BPM SYNC", action="bpm_sync", max=20},
      nil, nil,
      {off=0x3F, name="SINGLE", action="set", val=0},
      {off=0x3F, name="PAN",    action="set", val=1},
      {off=0x3F, name="STEREO", action="set", val=2},
    },
  },
}

-- ---------------------------------------------------------------------------
-- EFX1-specific types (PS type 9, EQ type 10)
-- ---------------------------------------------------------------------------

if efxNum == 1 then

  TYPE_DEFS[9] = { name="PITCH SHIFT",
    swOff = 0x47,
    slots = {
      {off=0x49, name="PITCH 1",    max=48},
      {off=0x4A, name="PRE DLY 1",  max=100},
      {off=0x4C, name="EFX LVL 1",  max=100},
      {off=0x4B, name="FEEDBACK",   max=100},
      {off=0x4D, name="PITCH 2",    max=48},
      {off=0x4E, name="PRE DLY 2",  max=100},
      {off=0x50, name="EFX LVL 2",  max=100},
      {off=0x51, name="DIRECT LVL", max=100},
    },
    btns = {
      nil, nil, nil,
      {off=0x48, name="1MONO",   action="set", val=0},
      {off=0x48, name="2MONO",   action="set", val=1},
      {off=0x48, name="2STEREO", action="set", val=2},
    },
  }

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
      nil,
      {off=0x59, name="HM FREQ",  max=27},
      {off=0x5A, name="HM Q",     max=5},
      {off=0x5B, name="HM GAIN",  max=40},
      {off=0x5E, name="LEVEL",    max=40},
    },
    btns = {},
  }

-- ---------------------------------------------------------------------------
-- EFX2-specific types (RV type 9)
-- ---------------------------------------------------------------------------

else

  -- Reverb: all 7 type-option buttons (B2–B8) — dynamic coloring handles this
  TYPE_DEFS[9] = { name="REVERB",
    swOff = 0x47,
    slots = {
      {off=0x49, name="TIME",       max=99},
      {off=0x4A, name="PRE DLY",    max=100},
      {off=0x4D, name="DENSITY",    max=10},
      {off=0x50, name="SPRING SNS", max=100},
      {off=0x4B, name="HPF",        max=17},
      {off=0x4C, name="LPF",        max=14},
      {off=0x4E, name="EFX LVL",    max=100},
      {off=0x4F, name="DIRECT LVL", max=100},
    },
    btns = {
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

local function chooserGroup()
  return self.children["efx_" .. efxNum .. "_chooser"]
end

local function chooserLabelsGroup()
  return self.children["efx_" .. efxNum .. "_chooser_labels"]
end

local function btnLabelsGroup()
  return self.children["efx" .. efxNum .. "_b_labels"]
end

-- ---------------------------------------------------------------------------
-- applyType — remaps slots, buttons, colours, labels, BCR rings.
--
-- Button colour rules (applied dynamically so Reverb is handled correctly):
--   "set" action  → SEL_HEX  (type-option radio — selector tier)
--   everything else → BASE_HEX (utility — base tier)
-- Text colour flips black when active so text stays readable on lit buttons.
-- ---------------------------------------------------------------------------

local function applyType(typeIdx)
  curType = typeIdx
  local def = TYPE_DEFS[typeIdx]

  updateLabel("EFX" .. efxNum .. ": " .. (def and def.name or "???"))

  local typeCCval = (MAX_TYPE > 0) and math.floor(typeIdx / MAX_TYPE * 127 + 0.5) or 0
  sendBCRcc(TYPE_CC, typeCCval)

  -- ── Chooser radio + chooser label text colours ──────────────────────────
  local cgrp  = chooserGroup()
  local clGrp = chooserLabelsGroup()
  self.tag = "prog"
  if cgrp then
    for i = 1, MAX_TYPE do
      local cb = cgrp.children[tostring(i)]
      local cl = clGrp and clGrp.children[tostring(i)]
      local isActive = (i == curType)
      if cb then cb.values.x = isActive and 1 or 0 end
      if cl then cl.textColor = Color.fromHexString(isActive and ON_TXT or OFF_TXT) end
    end
  end
  self.tag = ""

  -- ── Slot faders (S01–S12) — hide unused ─────────────────────────────────
  -- BPM dual-mode: if a slot has a bpmSync field and BPM SYNC is currently
  -- active (rawData[bpmSync.off+1] > 0), show the division value and name
  -- instead of the primary rate parameter.
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
        if #rawData > 0 then
          local bpmActive = slotDef.bpmSync and (rawData[slotDef.bpmSync.off + 1] or 0) > 0
          local x, txt
          if bpmActive then
            local div = rawData[slotDef.bpmSync.off + 1] or 1
            x   = div / 20
            txt = BPM_DIVS[div + 1] or tostring(div)
          else
            local raw = rawData[slotDef.off + 1] or 0
            x   = math.max(0, math.min(1, raw / slotDef.max))
            txt = tostring(raw)
          end
          if fader  then fader.values.x    = math.max(0, math.min(1, x)) end
          if valLbl then valLbl.values.text = txt end
          sendBCRcc(SLOT_CC[i], math.floor(x * 127 + 0.5))
        else
          if fader  then fader.values.x    = 0 end
          if valLbl then valLbl.values.text = "--" end
          sendBCRcc(SLOT_CC[i], 0)
        end
      else
        sendBCRcc(SLOT_CC[i], 0)
      end
    end
  end

  -- ── B buttons + labels — colour, visibility, state, text colour ──────────
  local lblGrp = btnLabelsGroup()

  self.tag = "prog"

  -- B1: EFX SW (always utility colour)
  local hasSW = (def ~= nil and def.swOff ~= nil)
  local b1    = self.children[btnNodeName(1)]
  local lbl1  = lblGrp and lblGrp.children["1"]
  if b1 then
    b1.visible = hasSW
    b1.color   = Color.fromHexString(BASE_HEX)
    if hasSW then
      local swVal = (#rawData > 0) and (rawData[def.swOff + 1] or 0) or 0
      b1.values.x = swVal
      if lbl1 then lbl1.textColor = Color.fromHexString(swVal >= 0.5 and ON_TXT or OFF_TXT) end
      sendBCRcc(BTN_CC[1], swVal * 127)
    else
      b1.values.x = 0
      sendBCRcc(BTN_CC[1], 0)
    end
  end
  if lbl1 then
    lbl1.visible     = hasSW
    lbl1.values.text = "ON/OFF"
  end

  -- B2–B8: per-effect action buttons
  -- Colour: "set" → SEL_HEX (type-option), anything else → BASE_HEX (utility)
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
      elseif btnDef.action == "set" then
        local cur = (#rawData > 0) and rawData[btnDef.off + 1] or nil
        uiVal  = (cur ~= nil and cur == btnDef.val) and 1 or 0
        bcrVal = uiVal * 127
      end
    end

    -- Selector tier if "set", base tier for everything else
    local clrHex = (btnDef and btnDef.action == "set") and SEL_HEX or BASE_HEX

    if btn then
      btn.visible  = (btnDef ~= nil)
      btn.values.x = uiVal
      btn.color    = Color.fromHexString(clrHex)
    end
    if lbl then
      lbl.visible     = (btnDef ~= nil)
      lbl.values.text = btnDef and btnDef.name or ""
      lbl.textColor   = Color.fromHexString(uiVal >= 0.5 and ON_TXT or OFF_TXT)
    end
    sendBCRcc(BTN_CC[i], bcrVal)
  end

  self.tag = ""
end

-- ---------------------------------------------------------------------------
-- Slot SysEx send helpers
-- BPM dual-mode: when a slot has a bpmSync field and BPM SYNC is currently
-- active, the encoder controls the beat-division value (1–20) instead of the
-- primary rate parameter.  Both sendSlotFromFloat and sendSlotFromCC share the
-- same BPM branch so BCR and on-screen encoders behave identically.
-- ---------------------------------------------------------------------------

local function applyBpmSlot(slotDef, slotIdx, divVal)
  -- divVal: desired division integer (1–20).  Clamp and record.
  divVal = math.max(1, math.min(20, divVal))
  sendParam(slotDef.bpmSync.off, divVal)
  rawData[slotDef.bpmSync.off + 1] = divVal
  bpmDiv[slotDef.bpmSync.off]      = divVal
  local slotGrp = self.children[slotGroupName(slotIdx)]
  if slotGrp then
    local fader  = slotGrp.children["control_fader"]
    local valLbl = slotGrp.children["value_label"]
    if fader  then fader.values.x     = divVal / 20 end
    if valLbl then valLbl.values.text = BPM_DIVS[divVal + 1] or tostring(divVal) end
  end
end

local function sendSlotFromFloat(slotIdx, x)
  local def     = TYPE_DEFS[curType]
  local slotDef = def and def.slots and def.slots[slotIdx]
  if not slotDef then return end

  -- BPM dual-mode: redirect to division parameter when sync is active.
  if slotDef.bpmSync and (rawData[slotDef.bpmSync.off + 1] or 0) > 0 then
    local divVal = math.floor(x * 20 + 0.5)
    applyBpmSlot(slotDef, slotIdx, divVal)
    return
  end

  local raw = math.floor(x * slotDef.max + 0.5)
  sendParam(slotDef.off, raw)
  rawData[slotDef.off + 1] = raw
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

  -- BPM dual-mode: redirect to division parameter when sync is active.
  if slotDef.bpmSync and (rawData[slotDef.bpmSync.off + 1] or 0) > 0 then
    local divVal = math.floor(ccVal / 127 * 20 + 0.5)
    applyBpmSlot(slotDef, slotIdx, divVal)
    return
  end

  local raw = math.floor(ccVal / 127 * slotDef.max + 0.5)
  sendParam(slotDef.off, raw)
  rawData[slotDef.off + 1] = raw
  local slotGrp = self.children[slotGroupName(slotIdx)]
  if slotGrp then
    local fader  = slotGrp.children["control_fader"]
    local valLbl = slotGrp.children["value_label"]
    if fader  then fader.values.x     = raw / slotDef.max end
    if valLbl then valLbl.values.text = tostring(raw) end
  end
end

-- ---------------------------------------------------------------------------
-- onReceiveNotify
-- ---------------------------------------------------------------------------

function onReceiveNotify(key, value)

  if key == "type_cc" then
    local ccVal   = tonumber(value) or 0
    local typeIdx = math.floor(ccVal / 127 * MAX_TYPE + 0.5)
    sendParam(0x00, typeIdx)
    rawData[1] = typeIdx
    applyType(typeIdx)
    return
  end

  if key == "type_set" then
    local typeIdx = math.min(math.max(tonumber(value) or 0, 0), MAX_TYPE)
    if typeIdx ~= 0 and typeIdx == curType then typeIdx = 0 end
    sendParam(0x00, typeIdx)
    rawData[1] = typeIdx
    applyType(typeIdx)
    return
  end

  if key == "type_step" then
    local dir     = tonumber(value) or 0
    local typeIdx = ((curType + dir) % (MAX_TYPE + 1) + (MAX_TYPE + 1)) % (MAX_TYPE + 1)
    sendParam(0x00, typeIdx)
    rawData[1] = typeIdx
    applyType(typeIdx)
    return
  end

  if key == "patch_data" then
    rawData = {}
    for hex in value:gmatch("[^,]+") do
      rawData[#rawData + 1] = tonumber(hex, 16) or 0
    end
    local typeIdx = rawData[1] or 0
    applyType(typeIdx)
    return
  end

  if key == "slot_cc" then
    local si, cv = value:match("^(%d+),(%d+)$")
    local slotIdx = tonumber(si)
    local ccVal   = tonumber(cv) or 0
    if not slotIdx then return end
    sendSlotFromCC(slotIdx, ccVal)
    return
  end

  if key == "slot_moved" then
    local encName, xs = value:match("^([^,]+),(.+)$")
    if not encName then return end
    local slotIdx = tonumber(encName:match("efx%d+_s(%d+)"))
    if not slotIdx then return end
    local x = tonumber(xs) or 0
    sendSlotFromFloat(slotIdx, x)
    sendBCRcc(SLOT_CC[slotIdx], math.floor(x * 127 + 0.5))
    return
  end

  if key == "btn_press" then
    local btnIdx = tonumber(value) or 0
    if btnIdx < 1 or btnIdx > 8 then return end
    local def    = TYPE_DEFS[curType]
    local lblGrp = btnLabelsGroup()

    -- B1: EFX SW toggle
    if btnIdx == 1 then
      if not def or not def.swOff then return end
      local cur = rawData[def.swOff + 1] or 0
      local nxt = 1 - cur
      sendParam(def.swOff, nxt)
      rawData[def.swOff + 1] = nxt
      self.tag = "prog"
      local b1  = self.children[btnNodeName(1)]
      local lbl = lblGrp and lblGrp.children["1"]
      if b1  then b1.values.x   = nxt end
      if lbl then lbl.textColor = Color.fromHexString(nxt >= 0.5 and ON_TXT or OFF_TXT) end
      self.tag = ""
      sendBCRcc(BTN_CC[1], nxt * 127)
      return
    end

    local btnDef = def and def.btns and def.btns[btnIdx - 1]
    if not btnDef then return end

    if btnDef.action == "set" then
      sendParam(btnDef.off, btnDef.val)
      rawData[btnDef.off + 1] = btnDef.val
      self.tag = "prog"
      for bi = 2, 8 do
        local bd  = def.btns and def.btns[bi - 1]
        local bb  = self.children[btnNodeName(bi)]
        local bl  = lblGrp and lblGrp.children[tostring(bi)]
        if bd and bd.action == "set" and bd.off == btnDef.off then
          local isActive = (bi == btnIdx)
          if bb  then bb.values.x   = isActive and 1 or 0 end
          if bl  then bl.textColor  = Color.fromHexString(isActive and ON_TXT or OFF_TXT) end
          sendBCRcc(BTN_CC[bi], isActive and 127 or 0)
        end
      end
      self.tag = ""

    elseif btnDef.action == "toggle" then
      local cur = rawData[btnDef.off + 1] or 0
      local nxt = 1 - cur
      sendParam(btnDef.off, nxt)
      rawData[btnDef.off + 1] = nxt
      self.tag = "prog"
      local btn = self.children[btnNodeName(btnIdx)]
      local lbl = lblGrp and lblGrp.children[tostring(btnIdx)]
      if btn then btn.values.x   = nxt end
      if lbl then lbl.textColor  = Color.fromHexString(nxt >= 0.5 and ON_TXT or OFF_TXT) end
      self.tag = ""
      sendBCRcc(BTN_CC[btnIdx], nxt * 127)

    elseif btnDef.action == "bpm_sync" then
      local cur = rawData[btnDef.off + 1] or 0
      local nxt
      if cur > 0 then
        bpmDiv[btnDef.off] = cur
        nxt = 0
      else
        nxt = bpmDiv[btnDef.off] or 8
      end
      sendParam(btnDef.off, nxt)
      rawData[btnDef.off + 1] = nxt
      local uiV = (nxt > 0) and 1 or 0
      self.tag = "prog"
      local btn = self.children[btnNodeName(btnIdx)]
      local lbl = lblGrp and lblGrp.children[tostring(btnIdx)]
      if btn then btn.values.x   = uiV end
      if lbl then lbl.textColor  = Color.fromHexString(uiV >= 0.5 and ON_TXT or OFF_TXT) end
      self.tag = ""
      sendBCRcc(BTN_CC[btnIdx], uiV * 127)

      -- Refresh S01 when BPM SYNC is linked to it (TREMOLO/CHORUS/FLANGER/PHASER/DELAY).
      -- When SYNC turns on:  S01 shows the beat division name.
      -- When SYNC turns off: S01 reverts to the primary rate value.
      local s1def = def and def.slots and def.slots[1]
      if s1def and s1def.bpmSync and s1def.bpmSync.off == btnDef.off then
        local s1grp  = self.children[slotGroupName(1)]
        if s1grp then
          local s1fader  = s1grp.children["control_fader"]
          local s1valLbl = s1grp.children["value_label"]
          local newX, newTxt
          if nxt > 0 then
            newX   = nxt / 20
            newTxt = BPM_DIVS[nxt + 1] or tostring(nxt)
          else
            local raw = rawData[s1def.off + 1] or 0
            newX   = raw / s1def.max
            newTxt = tostring(raw)
          end
          newX = math.max(0, math.min(1, newX))
          self.tag = "prog"
          if s1fader  then s1fader.values.x     = newX end
          if s1valLbl then s1valLbl.values.text  = newTxt end
          self.tag = ""
          sendBCRcc(SLOT_CC[1], math.floor(newX * 127 + 0.5))
        end
      end
    end

    return
  end
end

-- ---------------------------------------------------------------------------
-- init
-- ---------------------------------------------------------------------------

function init()
  applyType(0)
end
