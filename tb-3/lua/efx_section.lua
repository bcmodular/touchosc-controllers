-- efx_section.lua
-- Injected into efx1_section and efx2_section GROUP nodes at build time.
-- Self-identifies as EFX1 (types 0–10) or EFX2 (types 0–9) from self.name.
--
-- Colour tiers (set dynamically via Color.fromHexString so all effects,
-- including Reverb whose type buttons span B2–B8, are coloured correctly):
--   SEL_HEX  — "selector" accent: chooser grid labels + type-option radio buttons
--   BASE_HEX — section base: knobs, SW, utility buttons (POLARITY…)
--
-- Toggle Release guard: self.tag = "prog" during all programmatic button value
-- writes so efx_button.lua / efx_chooser_button.lua can distinguish user presses
-- from re-entrant programmatic changes.
--
-- Text colour: label textColor flips black (ON_TXT) when button is active so
-- the text stays readable against the bright lit button background.
--
-- Slot display: each slot def can include a display(raw) function that converts
-- the raw SysEx value to a human-readable string (dB, Hz, ms, beat divisions…).
-- When absent, the raw integer is shown.

-- ---------------------------------------------------------------------------
-- Identity: EFX1 or EFX2
-- ---------------------------------------------------------------------------

local efxNum  = tonumber(self.name:match("efx(%d+)_section")) or 1
local BASE    = (efxNum == 1) and {0x10, 0x00, 0x10, 0x00}
                               or {0x10, 0x00, 0x12, 0x00}
local MAX_TYPE = (efxNum == 1) and 10 or 9

-- ---------------------------------------------------------------------------
-- Connection / channel constants
-- Keep byte-identical with root.lua TB3_CONNECTION / BCR_CONNECTION.
-- TouchOSC has no shared-library mechanism; this duplication is forced.
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
-- ---------------------------------------------------------------------------

local SEL_HEX  = (efxNum == 1) and "B3F2FFFF" or "FFA659FF"
local BASE_HEX = (efxNum == 1) and "33B3BFFF" or "D9611FFF"
local ON_TXT   = "000000FF"
local OFF_TXT  = "FFFFFFFF"

-- ---------------------------------------------------------------------------
-- SysEx helpers — keep byte-identical with root.lua tb3Checksum / tb3Send7bit.
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
-- Module-level state
-- ---------------------------------------------------------------------------

local curType = 0
local rawData = {}

-- ---------------------------------------------------------------------------
-- Display functions
-- Source: Unofficial TB-3 FX Parameter Guide v1.07 (Dope Robot)
--
-- Each function takes a raw SysEx integer and returns a display string.
-- Referenced by name in TYPE_DEFS slot entries via the "display" field.
-- ---------------------------------------------------------------------------

-- Beat-division strings (index 1 = value 0 = "OFF", … index 21 = value 20)
-- Tremolo/Chorus/Flanger/Phaser BPM SYNC: values 0–20.
-- Delay BPM SYNC:                          values 0–13 (max=13 in slot def).
local BPM_DIVS = {
  "OFF",   "2",    "3/2",  "4/3",  "1",
  "3/4",   "2/3",  "1/2",  "3/8",  "1/3",
  "1/4",   "3/16", "1/6",  "1/8",  "3/32",
  "1/12",  "1/16", "3/64", "1/24", "1/32",
  "3/128"
}
local function dispBpmDiv(raw)
  return BPM_DIVS[raw + 1] or tostring(raw)
end

-- Signed dB (range straddles 0 — use explicit sign)
local function dispDb20(raw)     -- 0-40 → −20 dB…+20 dB
  local db = raw - 20
  return (db >= 0 and "+" or "") .. db .. " dB"
end
local function dispDb15(raw)     -- 0-30 → −15 dB…+15 dB
  local db = raw - 15
  return (db >= 0 and "+" or "") .. db .. " dB"
end
local function dispDb40(raw)     -- 0-80 → −40 dB…+40 dB  (COMP GAIN)
  local db = raw - 40
  return (db >= 0 and "+" or "") .. db .. " dB"
end
local function dispThreshold(raw) -- 0-40 → −40 dB…0 dB  (always ≤ 0)
  return (raw - 40) .. " dB"
end

-- Bipolar linear (centre = max/2)
local function dispBipolar50(raw) -- 0-100 → −50…+50
  local v = raw - 50
  return (v >= 0 and "+" or "") .. v
end

-- Compressor ratio lookup (0-13)
local CS_RATIOS = {
  "1:1.0","1:1.1","1:1.2","1:1.4","1:1.6","1:1.8",
  "1:2.0","1:2.5","1:3.2","1:4.0","1:5.6","1:8.0","1:16","1:INF"
}
local function dispRatio(raw)
  return CS_RATIOS[raw + 1] or tostring(raw)
end

-- Compressor knee (0-9)
local function dispKnee(raw)
  return raw == 0 and "Hard" or ("Soft " .. raw)
end

-- Compressor attack/release (0-124, linear approximation)
local function dispCsAttack(raw)   -- 0-124 → 0-800 ms
  return math.floor(raw / 124 * 800) .. " ms"
end
local function dispCsRelease(raw)  -- 0-124 → 0-8000 ms
  return math.floor(raw / 124 * 8000) .. " ms"
end

-- HPF table (0-17): Flat → 800 Hz  (shared by Chorus, Phaser, Reverb, EQ)
local HPF_FREQS = {
  "Flat","20 Hz","25 Hz","31 Hz","40 Hz","50 Hz","63 Hz","80 Hz","100 Hz",
  "125 Hz","160 Hz","200 Hz","250 Hz","315 Hz","400 Hz","500 Hz","630 Hz","800 Hz"
}
local function dispHPF(raw)
  return HPF_FREQS[raw + 1] or tostring(raw)
end

-- Flanger HPF (0-10): Flat → 800 Hz in 11 steps (condensed from standard table).
-- Exact frequencies are approximate — verify against hardware.
local FL_HPF_FREQS = {
  "Flat","20 Hz","40 Hz","80 Hz","125 Hz","200 Hz","315 Hz","500 Hz","630 Hz","710 Hz","800 Hz"
}
local function dispFLHPF(raw)
  return FL_HPF_FREQS[raw + 1] or tostring(raw)
end

-- LPF table (0-14): 630 Hz → Flat  (shared by multiple effects)
local LPF_FREQS = {
  "630 Hz","800 Hz","1 kHz","1.25 kHz","1.6 kHz","2 kHz","2.5 kHz",
  "3.15 kHz","4 kHz","5 kHz","6.3 kHz","8 kHz","10 kHz","12.5 kHz","Flat"
}
local function dispLPF(raw)
  return LPF_FREQS[raw + 1] or tostring(raw)
end

-- EQ parametric frequency (0-27): 20 Hz → 10 kHz  (log-spaced Roland standard)
local EQ_FREQS = {
  "20 Hz","25 Hz","31 Hz","40 Hz","50 Hz","63 Hz","80 Hz","100 Hz","125 Hz",
  "160 Hz","200 Hz","250 Hz","315 Hz","400 Hz","500 Hz","630 Hz","800 Hz",
  "1 kHz","1.25 kHz","1.6 kHz","2 kHz","2.5 kHz","3.15 kHz","4 kHz",
  "5 kHz","6.3 kHz","8 kHz","10 kHz"
}
local function dispEQFreq(raw)
  return EQ_FREQS[raw + 1] or tostring(raw)
end

-- EQ Q (0-5): 0.5 → 16
local EQ_Q = {"0.5","1.0","2.0","4.0","8.0","16"}
local function dispEQQ(raw)
  return "Q " .. (EQ_Q[raw + 1] or tostring(raw))
end

-- Tremolo waveform type (0-5)
local TR_TYPES = {"TRI","UP SAW","DN SAW","SIN","SQR","RND"}
local function dispTrType(raw)
  return TR_TYPES[raw + 1] or tostring(raw)
end

-- Tremolo phase (0-100 → 0°–360°)
local function dispPhase(raw)
  return math.floor(raw * 3.6 + 0.5) .. "\194\176"  -- \194\176 = UTF-8 degree sign
end

-- Rate/period (0-100 → ~8000 ms … 20 ms, linear approximation)
-- Real mapping is logarithmic; this first-pass display is directionally correct.
local function dispRate(raw)
  return math.floor((1 - raw / 100) * 7980 + 20) .. " ms"
end

-- Direct millisecond mappings (value = ms)
local function dispMs(raw)   return raw .. " ms"  end
local function dispPct(raw)  return raw .. "%"     end

-- Reverb time (0-99 → 0.0 s … 9.9 s in 0.1 s steps)
local function dispRevTime(raw)
  return string.format("%.1f s", raw / 10)
end

-- Pitch shift in semitones (0-48, centre 24 = 0 st)
local function dispPitchSt(raw)
  local st = raw - 24
  return (st >= 0 and "+" or "") .. st .. " st"
end

-- ---------------------------------------------------------------------------
-- EFX type definitions — rebuilt from the shared efx_defs Shared Script.
--
-- efx_defs.lua (require("efx_defs")) is the single source of truth for slot
-- byte offsets, names, maxes, defaults, disabledBy, and button rows. It is also
-- consumed by patch_manager.lua in the root chunk to derive EFX_SLOT_OFFSETS_*,
-- so the offsets now live in exactly one place (before Task 2.2b they were
-- hand-mirrored across the two unreachable chunks and drifted silently).
--
-- efx_defs is PURE DATA: each slot's `display` is a STRING KEY, resolved here to
-- a local display function via DISPLAY_FNS. The display fns and their lookup
-- tables stay local to this chunk and never cross the shared-script boundary
-- (the sp404 controls_info.lua pattern), keeping the shared file portable and
-- the root chunk free of EFX display code.
--
-- TYPE_DEFS keeps the exact runtime shape the rest of this file expects:
--   slot : { off, name, max [, display(fn)] [, default] [, disabledBy] }
--     display(raw) → string — optional; omit for plain 0-N integer display.
--   btn  : { off, name, action [, val] }
--     action "set"    → radio preset; write val; light this, unlight siblings
--     action "toggle" → binary flip at offset
--   Type-option ("set") buttons sit at the bottom row (btns[4]-[7] = B5-B8).
--   Reverb fills all 7 B-button slots B2-B8 (btns[1]-[7]).
--   Slot/button positional nil holes are preserved (consumers iterate 1..12 /
--   2..8, never ipairs).
-- ---------------------------------------------------------------------------

-- String-key -> local display function. Keys match efx_defs.lua slot `display`.
local DISPLAY_FNS = {
  dispBpmDiv    = dispBpmDiv,
  dispDb20      = dispDb20,
  dispDb15      = dispDb15,
  dispDb40      = dispDb40,
  dispThreshold = dispThreshold,
  dispBipolar50 = dispBipolar50,
  dispRatio     = dispRatio,
  dispKnee      = dispKnee,
  dispCsAttack  = dispCsAttack,
  dispCsRelease = dispCsRelease,
  dispHPF       = dispHPF,
  dispFLHPF     = dispFLHPF,
  dispLPF       = dispLPF,
  dispEQFreq    = dispEQFreq,
  dispEQQ       = dispEQQ,
  dispTrType    = dispTrType,
  dispPhase     = dispPhase,
  dispRate      = dispRate,
  dispMs        = dispMs,
  dispPct       = dispPct,
  dispRevTime   = dispRevTime,
  dispPitchSt   = dispPitchSt,
}

-- Build a runtime type def from a shared (pure-data) def: copy scalar fields,
-- resolve the display string key to a function, preserve slot nil holes.
-- btns/disabledBy are shared by reference (read-only at runtime, never mutated).
local function buildTypeDef(src)
  local t = { name = src.name, swOff = src.swOff, btns = src.btns }
  if src.slots then
    t.slots = {}
    for i = 1, 12 do
      local s = src.slots[i]
      if s then
        t.slots[i] = {
          off        = s.off,
          name       = s.name,
          max        = s.max,
          default    = s.default,
          disabledBy = s.disabledBy,
          display    = s.display and DISPLAY_FNS[s.display] or nil,
        }
      end
    end
  end
  return t
end

local TYPE_DEFS = {}
do
  local EfxDefs = require("efx_defs")
  for idx, src in pairs(EfxDefs.SHARED) do
    TYPE_DEFS[idx] = buildTypeDef(src)
  end
  local special = EfxDefs.SPECIAL[efxNum]   -- types 9/10, per EFX section
  if special then
    for idx, src in pairs(special) do
      TYPE_DEFS[idx] = buildTypeDef(src)
    end
  end
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
-- refreshDisabledLabels
-- Dims the name_label of any slot whose disabledBy condition is currently met.
-- Called from applyType (inline) and after every slot send so the rate label
-- updates immediately when the user changes BPM SYNC via an encoder.
-- ---------------------------------------------------------------------------

local DIM_COLOR = "777777FF"   -- greyed name text → parameter currently bypassed
local LIT_COLOR = "FFFFFFFF"   -- normal name text

local function refreshDisabledLabels(def)
  if not def or not def.slots then return end
  for i = 1, 12 do
    local slotDef = def.slots[i]
    local slotGrp = self.children[slotGroupName(i)]
    if slotGrp then
      local nameLbl = slotGrp.children["name_label"]
      local valLbl  = slotGrp.children["value_label"]
      if slotDef and slotDef.disabledBy then
        local disabled = false
        for _, dOff in ipairs(slotDef.disabledBy) do
          if (rawData[dOff + 1] or 0) > 0 then
            disabled = true; break
          end
        end
        local clr = disabled and DIM_COLOR or LIT_COLOR
        if nameLbl then nameLbl.textColor = Color.fromHexString(clr) end
        if valLbl  then valLbl.textColor  = Color.fromHexString(clr) end
        slotGrp.tag = disabled and "disabled" or ""
      else
        -- No disabledBy condition — always interactive.
        -- Reset any stale dim colours left over from a previous effect type
        -- that had a disabledBy slot at this same index (e.g. switching from
        -- Chorus RATE at S01 to EQ LOW CUT at S01).
        if nameLbl then nameLbl.textColor = Color.fromHexString(LIT_COLOR) end
        if valLbl  then valLbl.textColor  = Color.fromHexString(LIT_COLOR) end
        slotGrp.tag = ""
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- applyType — remaps slots, buttons, colours, labels, BCR rings.
--
-- Slot display: if slotDef.display is set, calls display(raw) for the label.
-- Button colour: "set" → SEL_HEX, everything else → BASE_HEX.
-- ---------------------------------------------------------------------------

local function applyType(typeIdx, syncBCR)
  curType = typeIdx
  local def = TYPE_DEFS[typeIdx]

  -- Notify root so it can track the current type for parameter assignment.
  root:notify("efx_type_changed", efxNum .. "," .. typeIdx)

  updateLabel("EFX" .. efxNum .. ": " .. (def and def.name or "???"))

  if syncBCR ~= false then
    local typeCCval = (MAX_TYPE > 0) and math.floor(typeIdx / MAX_TYPE * 127 + 0.5) or 0
    sendBCRcc(TYPE_CC, typeCCval)
  end

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

  -- ── Slot faders (S01–S12) ────────────────────────────────────────────────
  for i = 1, 12 do
    local slotGrp = self.children[slotGroupName(i)]
    if slotGrp then
      local slotDef = def and def.slots and def.slots[i]
      slotGrp.visible = (slotDef ~= nil)
      if slotDef then
        local fader   = slotGrp.children["control_fader"]
        local nameLbl = slotGrp.children["name_label"]
        local valLbl  = slotGrp.children["value_label"]
        local slotDefault = slotDef.default or 0
        if nameLbl then nameLbl.values.text = slotDef.name end
        if fader then fader:setValueField("x", ValueField.DEFAULT, slotDefault) end
        if #rawData > 0 then
          local raw = rawData[slotDef.off + 1] or 0
          local x   = math.max(0, math.min(1, raw / slotDef.max))
          local txt = slotDef.display and slotDef.display(raw) or tostring(raw)
          if fader  then fader.values.x    = x end
          if valLbl then valLbl.values.text = txt end
          sendBCRcc(SLOT_CC[i], math.floor(x * 127 + 0.5))
        else
          if fader  then fader.values.x    = slotDefault end
          if valLbl then valLbl.values.text = "--" end
          sendBCRcc(SLOT_CC[i], 0)
        end
      else
        sendBCRcc(SLOT_CC[i], 0)
      end
    end
  end

  -- Dim name labels for any slot that is currently bypassed by BPM SYNC etc.
  refreshDisabledLabels(def)

  -- ── B buttons + labels ───────────────────────────────────────────────────
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

  -- B2–B8: per-effect action buttons ("set" or "toggle")
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
      elseif btnDef.action == "set" then
        local cur = (#rawData > 0) and rawData[btnDef.off + 1] or nil
        uiVal  = (cur ~= nil and cur == btnDef.val) and 1 or 0
        bcrVal = uiVal * 127
      end
    end

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
  self.tag = json.fromTable(rawData)
end

-- ---------------------------------------------------------------------------
-- Slot SysEx send helpers
-- Uses slotDef.display for label when available; falls back to tostring(raw).
-- ---------------------------------------------------------------------------

local function sendSlotFromFloat(slotIdx, x)
  local def     = TYPE_DEFS[curType]
  local slotDef = def and def.slots and def.slots[slotIdx]
  if not slotDef then return end
  local raw = math.floor(x * slotDef.max + 0.5)
  sendParam(slotDef.off, raw)
  rawData[slotDef.off + 1] = raw
  self.tag = json.fromTable(rawData)
  local slotGrp = self.children[slotGroupName(slotIdx)]
  if slotGrp then
    local valLbl = slotGrp.children["value_label"]
    local txt    = slotDef.display and slotDef.display(raw) or tostring(raw)
    if valLbl then valLbl.values.text = txt end
  end
  -- Re-check disabled labels in case this change affected a RATE slot.
  refreshDisabledLabels(def)
end

local function sendSlotFromCC(slotIdx, ccVal)
  local def     = TYPE_DEFS[curType]
  local slotDef = def and def.slots and def.slots[slotIdx]
  if not slotDef then return end
  local raw = math.floor(ccVal / 127 * slotDef.max + 0.5)
  sendParam(slotDef.off, raw)
  rawData[slotDef.off + 1] = raw
  self.tag = json.fromTable(rawData)
  local slotGrp = self.children[slotGroupName(slotIdx)]
  if slotGrp then
    local fader  = slotGrp.children["control_fader"]
    local valLbl = slotGrp.children["value_label"]
    local txt    = slotDef.display and slotDef.display(raw) or tostring(raw)
    if fader  then fader.values.x     = raw / slotDef.max end
    if valLbl then valLbl.values.text = txt end
  end
  -- Re-check disabled labels in case this change affected a RATE slot.
  refreshDisabledLabels(def)
end

-- ---------------------------------------------------------------------------
-- onReceiveNotify
-- ---------------------------------------------------------------------------

function onReceiveNotify(key, value)

  if key == "sync_bcr" then
    applyType(curType)
    return
  end

  if key == "type_cc" then
    local ccVal   = tonumber(value) or 0
    local typeIdx = math.min(math.floor(ccVal / 127 * MAX_TYPE + 0.5), MAX_TYPE)
    sendParam(0x00, typeIdx)
    rawData[1] = typeIdx
    applyType(typeIdx, false)
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
    -- applyType ends with self.tag = json.fromTable(rawData)
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
    local valStr  = tostring(value)
    local btnIdx  = tonumber(valStr:match("^(%d+)")) or 0
    local fromBCR = valStr:find(",bcr", 1, true) ~= nil
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
      self.tag = json.fromTable(rawData)
      if not fromBCR then sendBCRcc(BTN_CC[1], nxt * 127) end
      -- Notify root for parameter assignment: EFX SW param (swOff encodes param ID).
      root:notify("efx_sw_touched", efxNum .. "," .. def.swOff)
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
          -- When the press came from the BCR: skip echoing the active button back
          -- (it's already lit), but DO send CC=0 for siblings so the BCR follows
          -- the radio-button logic and turns off the previously active button.
          if not fromBCR then
            sendBCRcc(BTN_CC[bi], isActive and 127 or 0)
          elseif not isActive then
            sendBCRcc(BTN_CC[bi], 0)
          end
        end
      end
      self.tag = ""
      self.tag = json.fromTable(rawData)

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
      self.tag = json.fromTable(rawData)
      if not fromBCR then sendBCRcc(BTN_CC[btnIdx], nxt * 127) end
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
