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

-- Send a Roland RQ1 (data request) for one parameter block.
-- a1–a4 = block start address; s1–s4 = byte count (4-byte big-endian).
local function tb3Request(a1, a2, a3, a4, s1, s2, s3, s4)
  local body = {a1, a2, a3, a4, s1, s2, s3, s4}
  local cs = tb3Checksum(body)
  sendMIDI({0xF0, 0x41, 0x10, 0x00, 0x00, 0x7B, 0x11,
            a1, a2, a3, a4, s1, s2, s3, s4, cs, 0xF7}, TB3_CONNECTION)
end

-- Request all 11 synthesis blocks (sound only — no pattern data).
-- Sizes and checksums taken directly from Dope Robot Ctrlr panel source.
local function requestPatchDump()
  awaitingBlocks = 11  -- countdown; BCR1 sync fires when this reaches 0
  syncTimer = 180      -- fallback: sync ~3s after request (catches split SysEx)
  tb3Request(0x10,0x00,0x00,0x00, 0x00,0x00,0x00,0x0D)  -- LFO
  tb3Request(0x10,0x00,0x02,0x00, 0x00,0x00,0x00,0x06)  -- CV Offset / Tuning
  tb3Request(0x10,0x00,0x04,0x00, 0x00,0x00,0x00,0x0A)  -- Cross Modulation
  tb3Request(0x10,0x00,0x06,0x00, 0x00,0x00,0x00,0x0E)  -- Ring Modulation
  tb3Request(0x10,0x00,0x08,0x00, 0x00,0x00,0x00,0x0E)  -- VCO
  tb3Request(0x10,0x00,0x0A,0x00, 0x00,0x00,0x00,0x0B)  -- VCF
  tb3Request(0x10,0x00,0x0C,0x00, 0x00,0x00,0x00,0x05)  -- VCA
  tb3Request(0x10,0x00,0x0E,0x00, 0x00,0x00,0x00,0x09)  -- Distortion
  tb3Request(0x10,0x00,0x10,0x00, 0x00,0x00,0x00,0x5F)  -- EFX1
  tb3Request(0x10,0x00,0x12,0x00, 0x00,0x00,0x00,0x54)  -- EFX2
  tb3Request(0x10,0x00,0x14,0x00, 0x00,0x00,0x00,0x12)  -- Param Assign
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
-- SysEx send from an enc_map / sw_map entry given a 0–1 float fader value.
-- Used by the enc_moved / sw_toggled notify handlers below.
-- ---------------------------------------------------------------------------

local function sendFromEntryFloat(entry, x)
  if entry.sp == "global_tuning" then
    local ccVal = math.floor(x * 127 + 0.5)
    sendMIDI({0xB0 + (TB3_MIDI_CHANNEL - 1), 104, ccVal}, TB3_CONNECTION)
    return
  end
  local a = entry.addr
  if entry.bits == 16 then
    local raw = math.floor(x * (entry.max or 255) + 0.5)
    tb3Send16bit(a[1], a[2], a[3], a[4], raw)
  else
    local raw = math.floor(x * (entry.max or 127) + 0.5)
    tb3Send7bit(a[1], a[2], a[3], a[4], raw)
  end
end

-- ---------------------------------------------------------------------------
-- UI update helpers — called after BCR input so faders reflect hardware state
-- ---------------------------------------------------------------------------

-- Update a control_fader (and its value_label) by SysEx address.
-- ccVal is the raw BCR CC value (0–127); srcEntry gives the parameter's max.
local function updateUIForAddr(addr, ccVal, srcEntry)
  local key = string.format("%02X%02X%02X%02X",
    addr[1], addr[2], addr[3], addr[4])
  local hit = ADDR_TO_ENC[key]
  if not hit then return end
  local encGrp = root:findByName(hit.path:match(",(.+)$"), true)
  if not encGrp then return end
  local x = ccVal / 127
  local fader = encGrp.children["control_fader"]
  if fader then fader.values.x = x end
  local lbl = encGrp.children["value_label"]
  if lbl then
    local max = (srcEntry and srcEntry.max) or
                hit.entry.max or
                (hit.entry.bits == 16 and 255 or 127)
    lbl.values.text = tostring(math.floor(x * max + 0.5))
  end
end

-- Update a sw_button (or standalone toggle button) by SysEx address.
-- v is 0 or 1.
local function updateSwUIForAddr(addr, v)
  local key = string.format("%02X%02X%02X%02X",
    addr[1], addr[2], addr[3], addr[4])
  local hit = ADDR_TO_SW[key]
  if not hit then return end
  local node = root:findByName(hit.path:match(",(.+)$"), true)
  if not node then return end
  if hit.entry.btn then
    -- Standalone BUTTON node: set value directly (no children to look up).
    node.values.x = v
  else
    -- enc_group: the sw_button is a child of the group.
    local swBtn = node.children["sw_button"]
    if swBtn then swBtn.values.x = v end
  end
end

-- ---------------------------------------------------------------------------
-- BCR2000 #1 sync — called after a full patch receive to push current
-- fader positions to the BCR2000 so its LED rings reflect the patch.
-- ---------------------------------------------------------------------------

local awaitingBlocks = 0   -- counts DT1 blocks expected after requestPatchDump
local pushToggleState = {} -- BCR push-encoder toggle state; key = channel*1000+cc
local syncTimer = 0        -- frame countdown; fires syncBCR1() as a fallback

local function syncBCR1()
  for cc, entry in pairs(BCR1_MAP) do
    if entry.addr then
      local key = string.format("%02X%02X%02X%02X",
        entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
      if entry.max == 1 then
        -- Toggle switch: read sw_button / standalone button state
        local hit = ADDR_TO_SW[key]
        if hit then
          local node = root:findByName(hit.path:match(",(.+)$"), true)
          if node then
            local btn
            if hit.entry.btn then
              btn = node  -- standalone BUTTON
            else
              btn = node.children["sw_button"]  -- child of enc_group
            end
            if btn then
              local v = btn.values.x >= 0.5 and 1 or 0
              -- Keep pushToggleState consistent so ↑/↓ toggles stay in step
              pushToggleState[BCR1_CHANNEL * 1000 + cc] = v
              sendMIDI({0xB0, cc, v * 127}, BCR_CONNECTION)
            end
          end
        end
      else
        -- Regular encoder: read fader position
        local hit = ADDR_TO_ENC[key]
        if hit then
          local encGrp = root:findByName(hit.path:match(",(.+)$"), true)
          if encGrp then
            local fader = encGrp.children["control_fader"]
            if fader then
              sendMIDI({0xB0, cc, math.floor(fader.values.x * 127 + 0.5)}, BCR_CONNECTION)
            end
          end
        end
      end
    end
  end
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
-- NOTE: distType, DIST_TYPE_NAMES and DIST_NUM_TYPES are declared in
-- patch_manager.lua (included before this file) so that parseBlock can
-- share the same variables.  Do NOT re-declare them here.
-- ---------------------------------------------------------------------------

local DIST_TYPE_ADDR = {0x10, 0x00, 0x0E, 0x01}

local function sendDistType()
  tb3Send7bit(DIST_TYPE_ADDR[1], DIST_TYPE_ADDR[2],
              DIST_TYPE_ADDR[3], DIST_TYPE_ADDR[4], distType)
  local lbl = root:findByName("distortion_section_label", true)
  if lbl then
    lbl.values.text = "DISTORTION: " .. (DIST_TYPE_NAMES[distType + 1] or tostring(distType))
  end
end

-- ---------------------------------------------------------------------------
-- EXTRAS popup toggle
-- ---------------------------------------------------------------------------

local function togglePopup(groupName)
  local grp = root:findByName(groupName, true)
  if grp then grp.visible = not grp.visible end
end

-- ---------------------------------------------------------------------------
-- Push-encoder toggle state
-- BCR2000 buttons are in "Toggle On" mode: sends 127 when latched on, 0 off.
-- Use CC value directly — BCR owns the latch state, we just mirror it.
-- Key = channel * 1000 + cc to avoid any cross-unit collision.
-- (pushToggleState declared above syncBCR1 so both can reference it.)
-- ---------------------------------------------------------------------------

local function handlePushToggle(stateKey, entry, ccVal)
  local v = ccVal >= 64 and 1 or 0
  pushToggleState[stateKey] = v
  local a = entry.addr
  tb3Send7bit(a[1], a[2], a[3], a[4], v)
  updateSwUIForAddr(a, v)  -- keep layout switch in step with BCR
end

-- ---------------------------------------------------------------------------
-- BCR2000 #1 — all groups (channel 1)
-- CC number alone determines routing; no mode state required.
-- ---------------------------------------------------------------------------

local function handleBCR1(cc, ccVal)
  -- DIST TYPE ↑ / ↓ — "Toggle On" auto-reset pattern:
  -- On 127 (latch on): act, then immediately send 0 back to reset the BCR latch
  -- so the next press generates another 127 rather than a 0 (which we'd ignore).
  -- On 0 (latch off, from normal Toggle On second-press): ignore.
  if cc == 72 then
    if ccVal == 127 then
      distType = (distType + 1) % DIST_NUM_TYPES
      sendDistType()
      sendMIDI({0xB0, 72, 0}, BCR_CONNECTION)  -- reset BCR latch
    end
    return
  end

  if cc == 80 then
    if ccVal == 127 then
      distType = (distType - 1 + DIST_NUM_TYPES) % DIST_NUM_TYPES
      sendDistType()
      sendMIDI({0xB0, 80, 0}, BCR_CONNECTION)  -- reset BCR latch
    end
    return
  end

  -- GLOBAL TUNING (CC 100) — plain MIDI CC 104 to TB-3, not SysEx.
  -- The TB-3 has no SysEx address for global tuning; responds to CC 104
  -- via standard MIDI. Device-global, not saved in patch dumps.
  -- Note: addition is equivalent to bitwise OR here because 0xB0 lower nibble = 0.
  if cc == 100 then
    sendMIDI({0xB0 + (TB3_MIDI_CHANNEL - 1), 104, ccVal}, TB3_CONNECTION)
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
  updateUIForAddr(entry.addr, ccVal, entry)  -- keep layout fader in step with BCR
end

-- ---------------------------------------------------------------------------
-- BCR2000 #2 — EFX1 + EFX2 (channel 2)
-- EFX slot/button CCs forwarded to efx_section.lua via notify.
-- Slot and button index helpers are defined in bcr_map.lua (included above).
-- ---------------------------------------------------------------------------

local function handleBCR2(cc, ccVal)
  -- EFX1 type rotate
  if cc == 1 then
    local efx1 = root:findByName("efx1_section", true)
    if efx1 then efx1:notify("type_cc", ccVal) end
    return
  end
  -- CC 33: EFX1 type encoder push — spare (future: engage type-select mode)

  -- EFX2 type rotate
  if cc == 5 then
    local efx2 = root:findByName("efx2_section", true)
    if efx2 then efx2:notify("type_cc", ccVal) end
    return
  end
  -- CC 37: EFX2 type encoder push — spare

  -- EFX1 dedicated buttons (CC 65–68 = B1–B4, CC 73–76 = B5–B8)
  -- B1 (CC 65) = EFX1 SW — handled by efx_section receiving btn_press=1
  local b1 = efx1BtnIndex(cc)
  if b1 then
    if ccVal == 127 then
      local efx1 = root:findByName("efx1_section", true)
      if efx1 then efx1:notify("btn_press", b1) end
    end
    return
  end

  -- EFX2 dedicated buttons (CC 69–72 = B1–B4, CC 77–80 = B5–B8)
  -- B1 (CC 69) = EFX2 SW
  local b2 = efx2BtnIndex(cc)
  if b2 then
    if ccVal == 127 then
      local efx2 = root:findByName("efx2_section", true)
      if efx2 then efx2:notify("btn_press", b2) end
    end
    return
  end

  -- EFX1 param slots (CC 81–84 → S01–S04, 89–92 → S05–S08, 97–100 → S09–S12)
  local s1 = efx1SlotIndex(cc)
  if s1 then
    local efx1 = root:findByName("efx1_section", true)
    if efx1 then efx1:notify("slot_cc", s1 .. "," .. ccVal) end
    return
  end

  -- EFX2 param slots (CC 85–88 → S01–S04, 93–96 → S05–S08, 101–104 → S09–S12)
  local s2 = efx2SlotIndex(cc)
  if s2 then
    local efx2 = root:findByName("efx2_section", true)
    if efx2 then efx2:notify("slot_cc", s2 .. "," .. ccVal) end
    return
  end
end

-- ---------------------------------------------------------------------------
-- TB-3 CC receive — hardware knob feedback updates the layout display.
-- CCs 74 (Cutoff) and 71 (Resonance) are standard MIDI; their faders are
-- updated directly. CCs 16/17 (Accent, Effect) pass through the parameter
-- assign system and will be mapped properly in Phase 5.
-- We update the display only — no SysEx is re-sent (TB-3 already changed).
-- ---------------------------------------------------------------------------

local TB3_CC_DISPLAY_MAP = {
  [71] = "vcf_group,vcf_resonance_enc",
  [74] = "vcf_group,vcf_cutoff_enc",
  -- [16] = accent — parameter-assign dependent, Phase 5
  -- [17] = effect — parameter-assign dependent, Phase 5
}

local function handleTB3CC(cc, ccVal)
  local encPath = TB3_CC_DISPLAY_MAP[cc]
  if not encPath then return end
  local encName = encPath:match(",(.+)$")
  local encGrp  = root:findByName(encName, true)
  if not encGrp then return end
  local x = ccVal / 127
  local fader = encGrp.children["control_fader"]
  if fader then fader.values.x = x end
  local lbl = encGrp.children["value_label"]
  if lbl then
    -- Scale to the SysEx range for display (u16 params span 0–255).
    lbl.values.text = tostring(math.floor(x * 255 + 0.5))
  end
end

-- ---------------------------------------------------------------------------
-- TB-3 SysEx receive (patch dump) — calls parseBlock from patch_manager.lua
-- ---------------------------------------------------------------------------

local function handleTB3SysEx(message)
  if #message < 14 then return end
  if message[1] ~= 0xF0 then return end
  if message[2] ~= 0x41 then return end
  if message[7] ~= 0x12 then return end

  local addr = {message[8], message[9], message[10], message[11]}
  local data = {}
  for i = 12, #message - 2 do  -- strip checksum and F7
    data[#data + 1] = message[i]
  end

  -- Decrement BEFORE parseBlock so a Lua error inside parseBlock cannot
  -- prevent the countdown from completing and syncBCR1() from firing.
  local triggerSync = false
  if awaitingBlocks > 0 then
    awaitingBlocks = awaitingBlocks - 1
    if awaitingBlocks == 0 then triggerSync = true end
  end

  parseBlock(addr, data)

  -- Forward EFX blocks to their section nodes as hex CSV strings.
  -- efx_section.lua stores the raw bytes and remaps slots when it receives them.
  if addr[1] == 0x10 and addr[2] == 0x00 then
    local efxSection
    if addr[3] == 0x10 then
      efxSection = root:findByName("efx1_section", true)
    elseif addr[3] == 0x12 then
      efxSection = root:findByName("efx2_section", true)
    end
    if efxSection then
      local hex = {}
      for _, b in ipairs(data) do hex[#hex + 1] = string.format("%02X", b) end
      efxSection:notify("patch_data", table.concat(hex, ","))
    end
  end

  if triggerSync then
    syncTimer = 0  -- cancel fallback timer; awaitingBlocks beat it
    syncBCR1()
  end
end

-- ---------------------------------------------------------------------------
-- MIDI receive entry point
-- ---------------------------------------------------------------------------

function onReceiveMIDI(message, connections)
  -- BCR2000 units (both on connection 2)
  if connections[2] then
    local status  = message[1]
    local msgType = status - (status % 16)   -- equiv: status & 0xF0
    local channel = (status % 16) + 1        -- equiv: (status & 0x0F) + 1, 1-indexed

    -- Lua 5.1 has no bitwise operators; use modulo/subtraction instead.
    -- msgType = status & 0xF0  →  status - (status % 16)
    -- channel = (status & 0x0F) + 1  →  (status % 16) + 1
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
    local status  = message[1]
    local msgType = status - (status % 16)
    if msgType == 0xF0 or status == 0xF0 then
      handleTB3SysEx(message)
    elseif msgType == 0xB0 then
      local ch = (status % 16) + 1
      if ch == TB3_MIDI_CHANNEL then
        handleTB3CC(message[2], message[3])
      end
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

  -- Sent by receive_button.lua (or any other trigger).
  if key == "request_patch_dump" then
    requestPatchDump()
    return
  end

  -- Sent by control_fader.lua when a fader is moved.
  -- value = "section,enc,x"  (x is a 0–1 float string)
  if key == "enc_moved" then
    local sec, enc, xs = value:match("^([^,]+),([^,]+),(.+)$")
    if sec and enc and xs then
      local x = tonumber(xs) or 0
      local entry = ENC_SEND_MAP[sec .. "," .. enc]
      if entry then
        sendFromEntryFloat(entry, x)

        -- Correct the value_label: control_fader.lua shows a fallback 0-127
        -- value; override it here with the parameter's actual range/encoding.
        -- Use section-scoped child lookup to handle name collisions (e.g.
        -- ring_mod_group and vco_group both have a child named "saw_enc").
        local lbl_text
        if entry.signed then
          -- Signed offset-encoded: raw 64 = 0; display range −64…+63.
          local raw = math.floor(x * 127 + 0.5)
          local s   = raw - 64
          lbl_text  = (s >= 0 and "+" or "") .. tostring(s)
        elseif entry.bipolar then
          -- Bipolar linear: centre = max/2; display as ±value.
          local m    = entry.max or 100
          local raw  = math.floor(x * m + 0.5)
          local s    = raw - math.floor(m / 2)
          lbl_text   = (s >= 0 and "+" or "") .. tostring(s)
        elseif entry.bits == 16 then
          -- 16-bit nibble-packed: full range is 0–(max or 255).
          local raw16 = math.floor(x * (entry.max or 255) + 0.5)
          if entry.bipolar then
            local half = math.floor((entry.max or 255) / 2)
            local s    = raw16 - half
            lbl_text   = (s >= 0 and "+" or "") .. tostring(s)
          else
            lbl_text = tostring(raw16)
          end
        elseif entry.max and entry.max ~= 127 then
          -- Custom 7-bit max (e.g. DRIVE=120, BENDER=17).
          lbl_text = tostring(math.floor(x * entry.max + 0.5))
        end
        if lbl_text then
          local secGrp = root:findByName(sec, true)
          local encGrp = secGrp and secGrp.children[enc]
          if encGrp then
            local lbl = encGrp.children["value_label"]
            if lbl then lbl.values.text = lbl_text end
          end
        end

        -- Mirror to BCR2000 #1 so its LED ring tracks the on-screen fader.
        if entry.addr then
          local addrKey = string.format("%02X%02X%02X%02X",
            entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
          local bcr1cc = ADDR_TO_BCR1_CC[addrKey]
          if bcr1cc then
            sendMIDI({0xB0, bcr1cc, math.floor(x * 127 + 0.5)}, BCR_CONNECTION)
          end
        end
      else
        -- Not in ENC_SEND_MAP — route EFX slot faders to their section.
        -- sec = "efx1_section" or "efx2_section"; enc = "efx1_s03" etc.
        local efxSection = root:findByName(sec, true)
        if efxSection then efxSection:notify("slot_moved", enc .. "," .. xs) end
      end
    end
    return
  end

  -- Sent by sw_button.lua and porta_mode_button.lua when a toggle is pressed.
  -- value = "section,enc,v"  (v is 0 or 1)
  if key == "sw_toggled" then
    local sec, enc, vs = value:match("^([^,]+),([^,]+),(%d+)$")
    if sec and enc and vs then
      local entry = SW_SEND_MAP[sec .. "," .. enc]
      if entry then
        local a = entry.addr
        local v = tonumber(vs) or 0
        tb3Send7bit(a[1], a[2], a[3], a[4], v)
        -- Mirror to BCR2000 #1 if this switch has a BCR mapping.
        local addrKey = string.format("%02X%02X%02X%02X", a[1],a[2],a[3],a[4])
        local bcr1cc = ADDR_TO_BCR1_CC[addrKey]
        if bcr1cc then
          sendMIDI({0xB0, bcr1cc, v * 127}, BCR_CONNECTION)
        end
      end
    end
    return
  end

  -- Sent by porta_radio_btn.lua when a portamento mode radio button is pressed.
  -- value = "0" (LEGATO) or "1" (ALWAYS)
  if key == "porta_mode_set" then
    local v = tonumber(value) or 0
    tb3Send7bit(0x10, 0x00, 0x14, 0x02, v)
    -- Notify both radio buttons so they update their visual state in sync.
    local legato = root:findByName("porta_legato_btn", true)
    local always  = root:findByName("porta_always_btn", true)
    if legato then legato:notify("porta_mode_updated", value) end
    if always  then always:notify("porta_mode_updated", value) end
    return
  end

  -- Sent by dist_type_button.lua (momentary ↑/↓ buttons in the layout).
  if key == "dist_type_up" then
    distType = (distType + 1) % DIST_NUM_TYPES
    sendDistType()
    return
  end
  if key == "dist_type_dn" then
    distType = (distType - 1 + DIST_NUM_TYPES) % DIST_NUM_TYPES
    sendDistType()
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
      local section     = root:findByName(sectionName, true)
      if section then section:notify("type_set", typeIndex) end
    end
    return
  end

  -- EFX type step (PREV/NEXT) from on-screen chooser buttons.
  -- value = "N,D": N = EFX number (1 or 2), D = direction (+1 or -1)
  if key == "efx_type_step" then
    local efxNum, dir = value:match("^(%d+),([-]?%d+)$")
    efxNum = tonumber(efxNum)
    dir    = tonumber(dir) or 0
    if efxNum then
      local sectionName = efxNum == 1 and "efx1_section" or "efx2_section"
      local section     = root:findByName(sectionName, true)
      if section then section:notify("type_step", dir) end
    end
    return
  end
end

-- ---------------------------------------------------------------------------
-- OSC receive — test harness for patch restore without live TB-3.
-- Python sender: split .syx into F0…F7 blocks, send each as hex CSV string
-- to address /tb3/patch on whatever port TouchOSC is listening on.
-- e.g.  /tb3/patch  "F0,41,10,00,00,7B,12,10,00,0C,00,00,2A,00,00,52,68,F7"
-- ---------------------------------------------------------------------------

function onReceiveOSC(message, connections)
  -- Allow external tools (Python, other apps) to trigger a dump request.
  if message.address == "/tb3/request_dump" then
    requestPatchDump()
    return
  end

  if message.address ~= "/tb3/patch" then return end
  local arg = message.arguments[1]
  if not arg then return end
  local hexStr = arg.value
  if type(hexStr) ~= "string" then return end

  -- Parse comma-separated hex bytes back into a byte array.
  local bytes = {}
  for hex in hexStr:gmatch("[^,]+") do
    bytes[#bytes + 1] = tonumber(hex, 16)
  end

  -- Validate Roland TB-3 SysEx framing.
  if #bytes < 14 then return end
  if bytes[1] ~= 0xF0 then return end
  if bytes[2] ~= 0x41 then return end
  if bytes[7] ~= 0x12 then return end

  local addr = {bytes[8], bytes[9], bytes[10], bytes[11]}
  local data = {}
  for i = 12, #bytes - 2 do data[#data + 1] = bytes[i] end
  parseBlock(addr, data)
end

-- ---------------------------------------------------------------------------
-- update — frame callback used as a reliable post-receive BCR sync fallback.
-- syncTimer is set by requestPatchDump(); the awaitingBlocks countdown clears
-- it early if all 11 DT1 blocks arrive intact. Otherwise it fires after ~3s,
-- catching cases where large EFX blocks are split by the MIDI interface.
-- ---------------------------------------------------------------------------

function update()
  if syncTimer > 0 then
    syncTimer = syncTimer - 1
    if syncTimer == 0 then syncBCR1() end
  end
end

-- ---------------------------------------------------------------------------
-- init
-- ---------------------------------------------------------------------------

function init()
  -- Push current fader positions to BCR2000 #1 on layout load so its LED
  -- rings reflect whatever values the layout last had.
  syncBCR1()
end
