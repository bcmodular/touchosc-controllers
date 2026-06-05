-- root.lua — TB-3 TouchOSC root node script
-- Injected into the root <node> at build time via toscbuild.py.
-- Responsibilities:
--   • Roland SysEx send helpers (7-bit and 16-bit)
--   • onReceiveMIDI: route BCR2000 CCs to SysEx; receive TB-3 SysEx dumps
--   • Distortion type state machine (increment/decrement, 25 types)
--   • EXTRAS popup toggle: portamento_group, ring_mod_group, cross_mod_group
--   • EFX type button grid (efx_1_chooser / efx_2_chooser) → notify efx_section
--
-- BCR2000 channel routing:
--   CH3 (BCR1_CHANNEL)     — BCR2000 #1 VCO/Dist group (Group 1)
--   CH4 (BCR1_LFO_CHANNEL) — BCR2000 #1 LFO group (Group 2, same unit, same CCs)
--   CH5 (BCR2_CHANNEL)     — BCR2000 #2 EFX1/EFX2
-- No mode state needed: channel alone determines routing.
--
-- Included files (concatenated at build time):
--   bcr_map.lua — CC→SysEx lookup tables for both BCR2000 units

-- ---------------------------------------------------------------------------
-- Connection / channel constants
-- ---------------------------------------------------------------------------

-- Connection bitmasks: index = connection number, true = active.
-- BCR2000 #1 and #2 both arrive on connection 2.
local BCR_CONNECTION      = {false, true}
-- TB-3 USB MIDI is on connection 6.
local TB3_CONNECTION      = {false, false, false, false, false, true}
-- TB-3 MIDI receive channel (default 2 per user setup).
local TB3_MIDI_CHANNEL    = 2

local BCR1_CHANNEL        = 3   -- BCR2000 #1 Group 1: VCO / Dist
local BCR1_LFO_CHANNEL    = 4   -- BCR2000 #1 Group 2: LFO (same unit, different channel)
local BCR2_CHANNEL        = 5   -- BCR2000 #2: EFX1 + EFX2

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
-- Generic continuous-encoder send (shared by BCR1 VCO and LFO handlers)
-- ---------------------------------------------------------------------------

local function sendFromEntry(entry, ccVal)
  local a = entry.addr
  if entry.bits == 16 then
    local val16 = math.floor(ccVal / 127 * (entry.max or 255) + 0.5)
    tb3Send16bit(a[1], a[2], a[3], a[4], val16)
  else
    local scaled = ccScale(ccVal, entry.max or 127)
    tb3Send7bit(a[1], a[2], a[3], a[4], scaled)
  end
end

-- ---------------------------------------------------------------------------
-- Distortion type state
-- ---------------------------------------------------------------------------

local DIST_NUM_TYPES = 25
local distType = 0  -- current distortion type (0–24)

local DIST_TYPE_NAMES = {
  "Mid Boost", "Clean Boost", "Treble Bst",
  "Blues OD",  "Crunch",      "Natural OD",
  "OD-1",      "T-Scream",    "Turbo OD",
  "Warm OD",   "Distortion",  "Mild DS",
  "Mid DS",    "RAT",         "GUV DS",
  "DST+",      "Modern DS",   "Solid DS",
  "Stack",     "Loud",        "Metal Zone",
  "Lead",      "'60s FUZZ",   "Oct FUZZ",
  "MUFF FUZZ",
}

local DIST_TYPE_ADDR = {0x10, 0x00, 0x0E, 0x01}

local function sendDistType()
  tb3Send7bit(DIST_TYPE_ADDR[1], DIST_TYPE_ADDR[2],
               DIST_TYPE_ADDR[3], DIST_TYPE_ADDR[4], distType)
  -- Section label doubles as type display: "DISTORTION: MILD OD"
  local lbl = findByName("distortion_section_label")
  if lbl then
    lbl.values.text = "DISTORTION: " .. (DIST_TYPE_NAMES[distType + 1] or tostring(distType))
  end
end

-- ---------------------------------------------------------------------------
-- EXTRAS popup toggle (independent per panel)
-- ---------------------------------------------------------------------------

local function togglePopup(groupName)
  local grp = findByName(groupName)
  if grp then grp.visible = not grp.visible end
end

-- ---------------------------------------------------------------------------
-- Push-encoder toggle state
-- The BCR sends 127 on press, 0 on release; we toggle on rising edge.
-- ---------------------------------------------------------------------------

local pushToggleState = {}  -- [key] = 0|1  (key = channel*1000 + cc to avoid collisions)

local function handlePushToggle(stateKey, entry, ccVal)
  if ccVal ~= 127 then return end  -- act only on press
  local cur = pushToggleState[stateKey] or 0
  local nxt = 1 - cur
  pushToggleState[stateKey] = nxt
  local a = entry.addr
  tb3Send7bit(a[1], a[2], a[3], a[4], nxt)
end

-- ---------------------------------------------------------------------------
-- BCR2000 #1 — VCO Group (channel 6)
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

  -- CCs 1–8: VCO source levels / patch volume
  if cc >= 1 and cc <= 8 then
    local entry = BCR1_VCO_MAP[cc]
    if not entry then return end
    sendFromEntry(entry, ccVal)
    return
  end

  -- CC 44: GLOBAL TUNING — plain MIDI CC 104 to TB-3 (not SysEx).
  -- The TB-3 has no SysEx address for global tuning; it responds to CC 104
  -- via standard MIDI. Device-global setting, not saved in patch dumps.
  if cc == 44 then
    sendMIDI({0xB0 | (TB3_MIDI_CHANNEL - 1), 104, ccVal}, TB3_CONNECTION)
    return
  end

  -- All other BCR1 CCs (mode-independent: SW pushes, Row B buttons, Rows 1-3)
  local entry = BCR1_MAP[cc]
  if not entry then return end

  -- Boolean toggles (SW buttons etc.)
  if entry.max == 1 then
    handlePushToggle(BCR1_CHANNEL * 1000 + cc, entry, ccVal)
    return
  end

  sendFromEntry(entry, ccVal)
end

-- ---------------------------------------------------------------------------
-- BCR2000 #1 — LFO Group (channel 3)
-- ---------------------------------------------------------------------------

local function handleBCR1_LFO(cc, ccVal)
  -- CC1–8: LFO rotate params
  if cc >= 1 and cc <= 8 then
    local entry = BCR1_LFO_MAP[cc]
    if not entry then return end
    sendFromEntry(entry, ccVal)
    return
  end

  -- CC9–10: push buttons (BPM SYNC, RETRIGGER)
  local entry = BCR1_LFO_PUSH_MAP[cc]
  if entry then
    handlePushToggle(BCR1_LFO_CHANNEL * 1000 + cc, entry, ccVal)
  end
end

-- ---------------------------------------------------------------------------
-- BCR2000 #2 — EFX1 + EFX2 (channel 7)
-- EFX slot/button CCs are forwarded to efx_section via notify.
-- ---------------------------------------------------------------------------

local function handleBCR2(cc, ccVal)
  -- EFX1 type rotate
  if cc == 1 then
    local efx1 = findByName("efx1_section")
    if efx1 then efx1:notify("type_cc", ccVal) end
    return
  end
  -- CC 2 (EFX1 type encoder push) — spare

  -- EFX2 type rotate
  if cc == 5 then
    local efx2 = findByName("efx2_section")
    if efx2 then efx2:notify("type_cc", ccVal) end
    return
  end
  -- CC 6 (EFX2 type encoder push) — spare

  -- EFX1/EFX2 SW is on dedicated buttons B1 (CC31) and B1 (CC61).
  -- Those fall into the button-range handlers below, which forward btn_press=1
  -- to efx_section.lua — SW toggling is handled there in Phase 4.

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
      elseif channel == BCR1_LFO_CHANNEL then
        handleBCR1_LFO(cc, ccVal)
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
-- Notify entry point — called by child nodes / UI buttons
-- ---------------------------------------------------------------------------

function onReceiveNotify(key, value)
  -- EXTRAS popup buttons
  if key == "toggle_popup" then
    togglePopup(value)
    return
  end

  -- EFX type direct-select (efx_1_chooser / efx_2_chooser button grids)
  -- value = "N,M" where N = EFX number (1 or 2), M = button index (1-based)
  if key == "efx_type_select" then
    local efxNum, btnIdx = value:match("^(%d+),(%d+)$")
    efxNum  = tonumber(efxNum)
    btnIdx  = tonumber(btnIdx)
    if efxNum and btnIdx then
      local typeIndex   = btnIdx - 1  -- 0-based
      local sectionName = efxNum == 1 and "efx1_section" or "efx2_section"
      local section     = findByName(sectionName)
      if section then section:notify("type_set", typeIndex) end
    end
    return
  end
end

-- ---------------------------------------------------------------------------
-- init
-- ---------------------------------------------------------------------------

function init()
  -- lfo_group is permanently visible — nothing to hide/show here.
end
