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
--   CH1 (BCR1_CHANNEL) — BCR2000 #1: all groups (VCO, LFO, fixed rows, buttons)
--   CH2 (BCR2_CHANNEL) — BCR2000 #2: EFX1 + EFX2
-- Routing is by CC number alone within each channel — no mode state needed.
-- Both units use the same BC Manager preset template (different channel only).
--
-- Included files (concatenated at build time):
--   bcr_map.lua — CC→SysEx lookup tables + EFX slot/button index helpers

-- ---------------------------------------------------------------------------
-- Connection / channel constants
-- ---------------------------------------------------------------------------

-- Connection bitmasks: index = connection number, true = active.
-- BCR2000 #1 and #2 both arrive on connection 2.
local BCR_CONNECTION   = {false, true}
-- TB-3 USB MIDI is on connection 6.
local TB3_CONNECTION   = {false, false, false, false, false, true}
-- TB-3 MIDI receive channel (default 2 per user setup).
local TB3_MIDI_CHANNEL = 2

local BCR1_CHANNEL     = 1   -- BCR2000 #1 (all encoder groups on one channel)
local BCR2_CHANNEL     = 2   -- BCR2000 #2: EFX1 + EFX2

-- ---------------------------------------------------------------------------
-- SysEx helpers
-- ---------------------------------------------------------------------------

local function tb3Checksum(addrAndData)
  local sum = 0
  for _, b in ipairs(addrAndData) do sum = sum + b end
  return (0x100 - (sum % 256)) % 128
end

-- Send a 7-bit (single byte) SysEx parameter.
function tb3Send7bit(a1, a2, a3, a4, value)
  local data = {a1, a2, a3, a4, value}
  local cs = tb3Checksum(data)
  sendMIDI({0xF0, 0x41, 0x10, 0x00, 0x00, 0x7B, 0x12,
            a1, a2, a3, a4, value, cs, 0xF7}, TB3_CONNECTION)
end

-- Send a 16-bit SysEx parameter (VCF cutoff, resonance, env depth, tuning…).
-- a1–a4 is the MSB address; LSB address is a4+1 (Roland convention).
-- value is the full integer (0–255).
function tb3Send16bit(a1, a2, a3, a4, value)
  local msb = math.floor(value / 16)
  local lsb = value % 16
  local cs = tb3Checksum({a1, a2, a3, a4, msb, lsb})
  sendMIDI({0xF0, 0x41, 0x10, 0x00, 0x00, 0x7B, 0x12,
            a1, a2, a3, a4, msb, lsb, cs, 0xF7}, TB3_CONNECTION)
end

-- ---------------------------------------------------------------------------
-- Value scaling helper
-- ---------------------------------------------------------------------------

local function ccScale(ccVal, maxVal)
  if maxVal == nil or maxVal == 127 then return ccVal end
  return math.floor(ccVal / 127 * maxVal + 0.5)
end

-- ---------------------------------------------------------------------------
-- Generic SysEx send from a bcr_map entry
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
  local lbl = findByName("distortion_section_label")
  if lbl then
    lbl.values.text = "DISTORTION: " .. (DIST_TYPE_NAMES[distType + 1] or tostring(distType))
  end
end

-- ---------------------------------------------------------------------------
-- EXTRAS popup toggle
-- ---------------------------------------------------------------------------

local function togglePopup(groupName)
  local grp = findByName(groupName)
  if grp then grp.visible = not grp.visible end
end

-- ---------------------------------------------------------------------------
-- Push-encoder toggle state
-- BCR sends 127 on press, 0 on release; toggle on rising edge only.
-- Key = channel * 1000 + cc to avoid any cross-unit collision.
-- ---------------------------------------------------------------------------

local pushToggleState = {}

local function handlePushToggle(stateKey, entry, ccVal)
  if ccVal ~= 127 then return end
  local cur = pushToggleState[stateKey] or 0
  local nxt = 1 - cur
  pushToggleState[stateKey] = nxt
  local a = entry.addr
  tb3Send7bit(a[1], a[2], a[3], a[4], nxt)
end

-- ---------------------------------------------------------------------------
-- BCR2000 #1 — all groups (channel 1)
-- CC number alone determines routing; no mode state required.
-- ---------------------------------------------------------------------------

local function handleBCR1(cc, ccVal)
  -- DIST TYPE ↑ (dedicated button, right-aligned in BC Manager layout)
  if cc == 79 then
    if ccVal == 127 then
      distType = (distType + 1) % DIST_NUM_TYPES
      sendDistType()
    end
    return
  end

  -- DIST TYPE ↓
  if cc == 80 then
    if ccVal == 127 then
      distType = (distType - 1 + DIST_NUM_TYPES) % DIST_NUM_TYPES
      sendDistType()
    end
    return
  end

  -- GLOBAL TUNING (CC 100) — plain MIDI CC 104 to TB-3, not SysEx.
  -- The TB-3 has no SysEx address for global tuning; responds to CC 104
  -- via standard MIDI. Device-global, not saved in patch dumps.
  if cc == 100 then
    sendMIDI({0xB0 | (TB3_MIDI_CHANNEL - 1), 104, ccVal}, TB3_CONNECTION)
    return
  end

  -- All other BCR1 CCs: flat lookup in BCR1_MAP
  local entry = BCR1_MAP[cc]
  if not entry then return end

  if entry.max == 1 then
    -- Boolean toggle (VCO SW, LFO BPM SYNC, LFO RETRIGGER, DIST ON/OFF, DIST COLOR)
    handlePushToggle(BCR1_CHANNEL * 1000 + cc, entry, ccVal)
    return
  end

  sendFromEntry(entry, ccVal)
end

-- ---------------------------------------------------------------------------
-- BCR2000 #2 — EFX1 + EFX2 (channel 2)
-- EFX slot/button CCs forwarded to efx_section.lua via notify.
-- Slot and button index helpers are defined in bcr_map.lua (included above).
-- ---------------------------------------------------------------------------

local function handleBCR2(cc, ccVal)
  -- EFX1 type rotate
  if cc == 1 then
    local efx1 = findByName("efx1_section")
    if efx1 then efx1:notify("type_cc", ccVal) end
    return
  end
  -- CC 33: EFX1 type encoder push — spare (future: engage type-select mode)

  -- EFX2 type rotate
  if cc == 5 then
    local efx2 = findByName("efx2_section")
    if efx2 then efx2:notify("type_cc", ccVal) end
    return
  end
  -- CC 37: EFX2 type encoder push — spare

  -- EFX1 dedicated buttons (CC 65–68 = B1–B4, CC 73–76 = B5–B8)
  -- B1 (CC 65) = EFX1 SW — handled by efx_section receiving btn_press=1
  local b1 = efx1BtnIndex(cc)
  if b1 then
    if ccVal == 127 then
      local efx1 = findByName("efx1_section")
      if efx1 then efx1:notify("btn_press", b1) end
    end
    return
  end

  -- EFX2 dedicated buttons (CC 69–72 = B1–B4, CC 77–80 = B5–B8)
  -- B1 (CC 69) = EFX2 SW
  local b2 = efx2BtnIndex(cc)
  if b2 then
    if ccVal == 127 then
      local efx2 = findByName("efx2_section")
      if efx2 then efx2:notify("btn_press", b2) end
    end
    return
  end

  -- EFX1 param slots (CC 81–84 → S01–S04, 89–92 → S05–S08, 97–100 → S09–S12)
  local s1 = efx1SlotIndex(cc)
  if s1 then
    local efx1 = findByName("efx1_section")
    if efx1 then efx1:notify("slot_cc", s1 .. "," .. ccVal) end
    return
  end

  -- EFX2 param slots (CC 85–88 → S01–S04, 93–96 → S05–S08, 101–104 → S09–S12)
  local s2 = efx2SlotIndex(cc)
  if s2 then
    local efx2 = findByName("efx2_section")
    if efx2 then efx2:notify("slot_cc", s2 .. "," .. ccVal) end
    return
  end
end

-- ---------------------------------------------------------------------------
-- TB-3 SysEx receive (patch dump)
-- ---------------------------------------------------------------------------

local function handleTB3SysEx(message)
  if #message < 14 then return end
  if message[1] ~= 0xF0 then return end
  if message[2] ~= 0x41 then return end
  if message[7] ~= 0x12 then return end
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
  -- BCR2000 units (both on connection 2)
  if connections[2] then
    local status  = message[1]
    local msgType = status & 0xF0
    local channel = (status & 0x0F) + 1  -- 1-indexed

    if msgType == 0xB0 then
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
-- Notify entry point — called by child nodes / UI buttons
-- ---------------------------------------------------------------------------

function onReceiveNotify(key, value)
  if key == "toggle_popup" then
    togglePopup(value)
    return
  end

  -- EFX type direct-select from efx_1_chooser / efx_2_chooser button grids
  -- value = "N,M": N = EFX number (1 or 2), M = button index (1-based)
  if key == "efx_type_select" then
    local efxNum, btnIdx = value:match("^(%d+),(%d+)$")
    efxNum  = tonumber(efxNum)
    btnIdx  = tonumber(btnIdx)
    if efxNum and btnIdx then
      local typeIndex   = btnIdx - 1
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
