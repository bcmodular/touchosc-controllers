-- root.lua — TB-3 TouchOSC root node script
-- Injected into the root <node> at build time via toscbuild.py.
-- Responsibilities:
--   • Roland SysEx send helpers (7-bit and 16-bit)
--   • onReceiveMIDI: route BCR2000 CCs to SysEx; receive TB-3 SysEx dumps
--   • Distortion type state machine (increment/decrement, 25 types)
--
-- Included files (concatenated at build time):
--   bcr_map.lua — CC→SysEx lookup tables for both BCR2000 units

-- ---------------------------------------------------------------------------
-- Connection / channel constants
-- ---------------------------------------------------------------------------

-- Connection bitmasks: index = connection number, true = active.
-- BCR2000 #1 and #2 both arrive on connection 2.
local BCR_CONNECTION  = {false, true}
-- TB-3 USB MIDI is on connection 6.
local TB3_CONNECTION  = {false, false, false, false, false, true}

local BCR1_CHANNEL = 6   -- BCR2000 #1: Tone + Dist
local BCR2_CHANNEL = 7   -- BCR2000 #2: EFX1 + EFX2

-- ---------------------------------------------------------------------------
-- SysEx helpers
-- ---------------------------------------------------------------------------

local function tb3Checksum(addrAndData)
  local sum = 0
  for _, b in ipairs(addrAndData) do
    sum = sum + b
  end
  return (0x100 - (sum % 256)) % 128
end

-- Send a 7-bit (single byte) SysEx parameter.
function tb3Send7bit(a1, a2, a3, a4, value)
  local data = {a1, a2, a3, a4, value}
  local cs = tb3Checksum(data)
  sendMIDI({0xF0, 0x41, 0x10, 0x00, 0x00, 0x7B, 0x12,
            a1, a2, a3, a4, value, cs, 0xF7}, TB3_CONNECTION)
end

-- Send a 16-bit SysEx parameter (e.g. VCF cutoff, resonance, env depth, accent).
-- a1–a4 is the MSB address; LSB address is a4+1 (Roland convention).
-- value is the full integer (0–255).
function tb3Send16bit(a1, a2, a3, a4, value)
  local msb = math.floor(value / 16)
  local lsb = value % 16
  local data = {a1, a2, a3, a4, msb, lsb}
  local cs = tb3Checksum(data)
  sendMIDI({0xF0, 0x41, 0x10, 0x00, 0x00, 0x7B, 0x12,
            a1, a2, a3, a4, msb, lsb, cs, 0xF7}, TB3_CONNECTION)
end

-- ---------------------------------------------------------------------------
-- Value scaling helper
-- ---------------------------------------------------------------------------

-- Scale a raw CC value (0–127) to a parameter range (0–maxVal).
local function ccScale(ccVal, maxVal)
  if maxVal == nil or maxVal == 127 then return ccVal end
  return math.floor(ccVal / 127 * maxVal + 0.5)
end

-- ---------------------------------------------------------------------------
-- Distortion type state
-- ---------------------------------------------------------------------------

local DIST_NUM_TYPES = 25
local distType = 0  -- current distortion type (0–24)

local DIST_TYPE_NAMES = {
  "MILD OD", "OD1", "OD2", "OD3", "OD4",
  "WARM DS", "DS1", "DS2", "DS3", "DS4",
  "WARM FUZZ", "FUZZ1", "FUZZ2", "FUZZ3", "FUZZ4",
  "AMP SIM 1", "AMP SIM 2", "AMP SIM 3", "AMP SIM 4", "AMP SIM 5",
  "VINYL CRUSH", "CLEAN", "AMP SIM 6", "DS5", "RECTIFY",
}

local DIST_TYPE_ADDR = {0x10, 0x00, 0x0E, 0x01}

local function sendDistType()
  tb3Send7bit(DIST_TYPE_ADDR[1], DIST_TYPE_ADDR[2],
               DIST_TYPE_ADDR[3], DIST_TYPE_ADDR[4], distType)
  -- Update display label if node exists
  local lbl = findByName("dist_type_label")
  if lbl then
    lbl.values.text = (DIST_TYPE_NAMES[distType + 1] or tostring(distType))
  end
end

-- ---------------------------------------------------------------------------
-- Push-encoder toggle state (BCR2000 #1 Row 0 push CCs 9–16)
-- The BCR sends 127 on press, 0 on release; we toggle on rising edge.
-- ---------------------------------------------------------------------------

local pushToggleState = {}  -- [cc] = 0|1

local function handlePushToggle(cc, entry, ccVal)
  if ccVal ~= 127 then return end  -- act only on press
  local cur = pushToggleState[cc] or 0
  local nxt = 1 - cur
  pushToggleState[cc] = nxt
  local a = entry.addr
  tb3Send7bit(a[1], a[2], a[3], a[4], nxt)
end

-- ---------------------------------------------------------------------------
-- BCR2000 #1 CC handler
-- ---------------------------------------------------------------------------

local function handleBCR1(cc, ccVal)
  -- DIST TYPE ↑
  if cc == 23 then
    if ccVal == 127 then
      distType = (distType + 1) % DIST_NUM_TYPES
      sendDistType()
    end
    return
  end

  -- DIST TYPE ↓
  if cc == 24 then
    if ccVal == 127 then
      distType = (distType - 1 + DIST_NUM_TYPES) % DIST_NUM_TYPES
      sendDistType()
    end
    return
  end

  local entry = BCR1_MAP[cc]
  if not entry then return end

  -- Push-encoder SW toggles (CCs 9–16, boolean params)
  if entry.max == 1 then
    handlePushToggle(cc, entry, ccVal)
    return
  end

  -- Continuous encoder — scale and send
  local a = entry.addr
  local maxVal = entry.max or 127
  local scaled = ccScale(ccVal, maxVal)

  if entry.bits == 16 then
    -- Full 0–255 range encoded from 0–127 CC
    local val16 = math.floor(ccVal / 127 * (entry.max or 255) + 0.5)
    tb3Send16bit(a[1], a[2], a[3], a[4], val16)
  else
    tb3Send7bit(a[1], a[2], a[3], a[4], scaled)
  end
end

-- ---------------------------------------------------------------------------
-- BCR2000 #2 CC handler
-- EFX slot/button CCs are forwarded to efx_section via notify.
-- ---------------------------------------------------------------------------

local function handleBCR2(cc, ccVal)
  -- EFX1 type rotate
  if cc == 1 then
    local efx1 = findByName("efx1_section")
    if efx1 then efx1:notify("type_cc", ccVal) end
    return
  end

  -- EFX1 SW toggle
  if cc == 2 then
    if ccVal == 127 then
      local efx1 = findByName("efx1_section")
      if efx1 then efx1:notify("sw_toggle", 0) end
    end
    return
  end

  -- EFX2 type rotate
  if cc == 5 then
    local efx2 = findByName("efx2_section")
    if efx2 then efx2:notify("type_cc", ccVal) end
    return
  end

  -- EFX2 SW toggle
  if cc == 6 then
    if ccVal == 127 then
      local efx2 = findByName("efx2_section")
      if efx2 then efx2:notify("sw_toggle", 0) end
    end
    return
  end

  -- EFX1 param slots
  if cc >= EFX1_SLOT_CC_MIN and cc <= EFX1_SLOT_CC_MAX then
    local slot = cc - EFX1_SLOT_CC_MIN + 1  -- 1–12
    local efx1 = findByName("efx1_section")
    if efx1 then efx1:notify("slot_cc", slot .. "," .. ccVal) end
    return
  end

  -- EFX1 buttons
  if cc >= EFX1_BTN_CC_MIN and cc <= EFX1_BTN_CC_MAX then
    if ccVal == 127 then
      local btn = cc - EFX1_BTN_CC_MIN + 1  -- 1–8
      local efx1 = findByName("efx1_section")
      if efx1 then efx1:notify("btn_press", btn) end
    end
    return
  end

  -- EFX2 param slots
  if cc >= EFX2_SLOT_CC_MIN and cc <= EFX2_SLOT_CC_MAX then
    local slot = cc - EFX2_SLOT_CC_MIN + 1  -- 1–12
    local efx2 = findByName("efx2_section")
    if efx2 then efx2:notify("slot_cc", slot .. "," .. ccVal) end
    return
  end

  -- EFX2 buttons
  if cc >= EFX2_BTN_CC_MIN and cc <= EFX2_BTN_CC_MAX then
    if ccVal == 127 then
      local btn = cc - EFX2_BTN_CC_MIN + 1  -- 1–8
      local efx2 = findByName("efx2_section")
      if efx2 then efx2:notify("btn_press", btn) end
    end
    return
  end
end

-- ---------------------------------------------------------------------------
-- TB-3 SysEx receive (patch dump)
-- ---------------------------------------------------------------------------

local function handleTB3SysEx(message)
  -- Roland Data Set 1 reply: F0 41 10 00 00 7B 12 [addr x4] [data...] [cs] F7
  -- Minimum length: 14 bytes (header 7 + addr 4 + 1 data byte + cs + F7)
  if #message < 14 then return end
  if message[1] ~= 0xF0 then return end
  if message[2] ~= 0x41 then return end  -- Roland
  if message[7] ~= 0x12 then return end  -- Data Set 1

  -- Forward to patch_manager for full parse
  local pm = findByName("patch_manager")
  if pm then
    -- Pass raw message as comma-separated hex string
    local parts = {}
    for _, b in ipairs(message) do
      parts[#parts + 1] = string.format("%02X", b)
    end
    pm:notify("sysex_receive", table.concat(parts, ","))
  end
end

-- ---------------------------------------------------------------------------
-- MIDI receive entry point
-- ---------------------------------------------------------------------------

function onReceiveMIDI(message, connections)
  -- BCR2000 (both units arrive on connection 2)
  if connections[2] then
    local status  = message[1]
    local msgType = status & 0xF0
    local channel = (status & 0x0F) + 1  -- 1-indexed

    if msgType == 0xB0 then  -- Control Change
      local cc    = message[2]
      local ccVal = message[3]

      if channel == BCR1_CHANNEL then
        handleBCR1(cc, ccVal)
      elseif channel == BCR2_CHANNEL then
        handleBCR2(cc, ccVal)
      end
    end
    return
  end

  -- TB-3 (connection 6)
  if connections[6] then
    if message[1] == 0xF0 then
      handleTB3SysEx(message)
    end
    return
  end
end

-- ---------------------------------------------------------------------------
-- init
-- ---------------------------------------------------------------------------

function init()
  -- Nothing to initialise yet; layout controls are set up by per-node scripts.
end
