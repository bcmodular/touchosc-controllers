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
-- Included files (concatenated into ONE shared chunk at build time, in order):
--   bcr_map.lua       → BCR          (CC/NRPN→SysEx tables, EFX slot/btn helpers)
--   patch_manager.lua → PatchManager (parseBlock, param-ID maps, EFX offsets, …)
--   enc_map.lua       → EncMap       (ENC_SEND_MAP/SW_SEND_MAP + reverse lookups)
-- Each include exposes exactly one top-level local namespace table; root.lua
-- references only BCR.*, PatchManager.*, EncMap.*.  Include order is load-bearing
-- (see tb-3/CLAUDE.md "Root chunk — include order contract").

-- ---------------------------------------------------------------------------
-- Connection / channel constants
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Parameter Assign state
-- ---------------------------------------------------------------------------

-- Active slot being assigned (nil = not in assign mode).
-- Set to "xy_mod" | "effect_knob" | "pad_x" | "pad_y" while waiting for
-- the user to move an encoder to select the parameter.
local assignActiveSlot = nil

-- Hardware slot → SysEx address + display label.
local ASSIGN_SLOTS = {
  xy_mod      = {addr={0x10,0x00,0x14,0x04}, label="XY PAD MOD"},
  effect_knob = {addr={0x10,0x00,0x14,0x06}, label="EFX KNOB"},
  pad_x       = {addr={0x10,0x00,0x14,0x08}, label="PAD X"},
  pad_y       = {addr={0x10,0x00,0x14,0x0A}, label="PAD Y"},
}

-- Keys in a stable order for iteration (broadcastAssignMode, export).
local ASSIGN_SLOT_KEYS = {"xy_mod", "effect_knob", "pad_x", "pad_y"}

-- Notify all four assign slot buttons so they update their lit state.
-- activeSlot = slot key string, or nil/"" to turn all off.
local function broadcastAssignMode(activeSlot)
  for _, k in ipairs(ASSIGN_SLOT_KEYS) do
    local btn = root:findByName("assign_" .. k .. "_btn", true)
    if btn then btn:notify("assign_mode_changed", activeSlot or "") end
  end
end

-- Refresh all four per-slot assign status labels.
-- When a slot is active (assign mode), its label shows a touch prompt.
-- All other labels (and all labels when not in assign mode) show the
-- currently assigned parameter name or "—".
local function refreshAssignLabel()
  -- Update all labels to their current param-name values first.
  PatchManager.updateAssignDisplay()
  -- Override the active slot's label with the assign-mode prompt.
  if assignActiveSlot then
    local lbl = root:findByName("assign_" .. assignActiveSlot .. "_status", true)
    if lbl then lbl.values.text = "tap encoder" end
  end
end

-- ---------------------------------------------------------------------------
-- Raw SysEx block cache — stores the last received DT1 block per address key.
-- Used by snapshotCurrentPatch() to export patches.
-- Key: "%02X%02X%02X%02X" of the 4-byte address.
-- Kept continuously fresh: every send call site patches the corresponding
-- byte(s) so the cache reflects current UI state, not just the last sync.
-- EFX blocks (10001000 / 10001200) are NOT stored here; they live in
-- efx1_section.tag / efx2_section.tag as JSON byte arrays (see efx_section.lua).
-- ---------------------------------------------------------------------------

local rawSysexBlocks = {}

-- ---------------------------------------------------------------------------
-- Patch grid state
-- ---------------------------------------------------------------------------

local patchGridMode     = nil   -- nil | "delete" | "grab" | "morph"
local grabSnapshot      = nil   -- JSON string saved on grab press
local morphTargetSlot   = nil
local pendingStoreSlot  = nil   -- slot key awaiting auto-store after a triggered dump
local morphBaseSnapshot = nil -- JSON string of patch at morph-target selection time
local currentBankName   = ""  -- name of the most recently restored bank
local currentPresetName = ""  -- name of the most recently recalled preset slot
local bankRestoreStaging = nil -- accumulates slots during a chunked /patchgrid/restore_* push
local bankRestoreName    = ""  -- bank name carried by /patchgrid/restore_begin
local morphLastBlocks   = nil -- block hex strings last sent by applyMorph (for diff)
local morphAmount     = 0.0  -- 0.0–1.0 float from fader
local morphing        = false -- true while applyMorph is running; suppresses BCR sends
local applyMorph              -- forward declaration; defined below after getPatchGridSlots
local broadcastPatchMode      -- forward declaration; defined below after applyMorph
local updateMorphEncState     -- forward declaration; defined below after broadcastPatchMode
local tryCompletePendingStore -- forward declaration; defined below after setPatchGridSlots

local EXPORT_BLOCK_ORDER = {
  "10000000", "10000200", "10000400", "10000600",
  "10000800", "10000A00", "10000C00", "10000E00",
  "10001000", "10001200", "10001400",
}

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

local LAUNCHKEY_CONNECTION = {false,false,false,true}
local LAUNCHKEY_CHANNEL    = 1  -- Launchkey MK4 sends on MIDI ch 1

-- CC assignments for Launchkey MK4 encoders (7 encoders, 0-127 resolution).
-- 16-bit SysEx params (cutoff/resonance/accent) are scaled 0-127 → 0-255.
local LAUNCHKEY_CC_MAP = {
  [74]  = { addr={0x10,0x00,0x0A,0x00}, max=255 },  -- VCF CUTOFF    (enc 1)
  [71]  = { addr={0x10,0x00,0x0A,0x02}, max=255 },  -- VCF RESONANCE (enc 2)
  [16]  = { addr={0x10,0x00,0x14,0x0E}, max=255 },  -- ACCENT LEVEL  (enc 3)
  [17]  = { assignCC=17 },                           -- EFFECT KNOB   (enc 4)
  [12]  = { assignCC=12 },                           -- XY PAD X      (enc 5)
  [13]  = { assignCC=13 },                           -- XY PAD Y      (enc 6)
  [104] = { globalTuning=true },                     -- GLOBAL TUNING (enc 7)
  [105] = { morph=true },                            -- MORPH AMOUNT
  [1]   = { assignCC=1 },                            -- MOD WHEEL → xy_mod assign slot
}

-- Reverse lookup: SysEx addr hex → Launchkey CC (for enc_moved feedback).
local LAUNCHKEY_ADDR_TO_CC = {}
for cc, entry in pairs(LAUNCHKEY_CC_MAP) do
  if entry.addr then
    local k = string.format("%02X%02X%02X%02X",
      entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
    LAUNCHKEY_ADDR_TO_CC[k] = cc
  end
end

-- Assign slot key → Launchkey CC (for per-change mirror of assigned params).
local LAUNCHKEY_ASSIGN_CC = {
  effect_knob = 17,
  pad_x       = 12,
  pad_y       = 13,
}

-- Reverse: Launchkey CC → assign slot key (for syncLaunchkey assign-slot push).
local LAUNCHKEY_ASSIGN_CC_REVERSE = {}
for slotKey, cc in pairs(LAUNCHKEY_ASSIGN_CC) do
  LAUNCHKEY_ASSIGN_CC_REVERSE[cc] = slotKey
end

-- ---------------------------------------------------------------------------
-- Global tuning display table (CC 104, verified against hardware)
-- CC 64 = 0.0, range −7.0 (CC 0) to +7.0 (CC 127), steps mostly 0.1 st.
-- ---------------------------------------------------------------------------
local GLOBAL_TUNING_DISPLAY = {
  [0]="-7.0st", [1]="-6.9st", [2]="-6.8st", [3]="-6.7st", [4]="-6.6st", [5]="-6.4st", [6]="-6.3st", [7]="-6.2st",
  [8]="-6.1st", [9]="-6.0st", [10]="-5.9st", [11]="-5.8st", [12]="-5.7st", [13]="-5.6st", [14]="-5.5st", [15]="-5.3st",
  [16]="-5.2st", [17]="-5.1st", [18]="-5.0st", [19]="-4.9st", [20]="-4.8st", [21]="-4.7st", [22]="-4.6st", [23]="-4.5st",
  [24]="-4.4st", [25]="-4.2st", [26]="-4.1st", [27]="-4.0st", [28]="-3.9st", [29]="-3.8st", [30]="-3.7st", [31]="-3.6st",
  [32]="-3.5st", [33]="-3.4st", [34]="-3.3st", [35]="-3.1st", [36]="-3.0st", [37]="-2.9st", [38]="-2.8st", [39]="-2.7st",
  [40]="-2.6st", [41]="-2.5st", [42]="-2.4st", [43]="-2.3st", [44]="-2.1st", [45]="-2.0st", [46]="-1.9st", [47]="-1.8st",
  [48]="-1.7st", [49]="-1.6st", [50]="-1.5st", [51]="-1.4st", [52]="-1.3st", [53]="-1.2st", [54]="-1.0st", [55]="-0.9st",
  [56]="-0.8st", [57]="-0.7st", [58]="-0.6st", [59]="-0.5st", [60]="-0.4st", [61]="-0.3st", [62]="-0.2st", [63]="-0.1st",
  [64]="+0.0st", [65]="+0.2st", [66]="+0.3st", [67]="+0.4st", [68]="+0.5st", [69]="+0.6st", [70]="+0.7st", [71]="+0.8st",
  [72]="+0.9st", [73]="+1.0st", [74]="+1.2st", [75]="+1.3st", [76]="+1.4st", [77]="+1.5st", [78]="+1.6st", [79]="+1.7st",
  [80]="+1.8st", [81]="+1.9st", [82]="+2.0st", [83]="+2.1st", [84]="+2.3st", [85]="+2.4st", [86]="+2.5st", [87]="+2.6st",
  [88]="+2.7st", [89]="+2.8st", [90]="+2.9st", [91]="+3.0st", [92]="+3.1st", [93]="+3.3st", [94]="+3.4st", [95]="+3.5st",
  [96]="+3.6st", [97]="+3.7st", [98]="+3.8st", [99]="+3.9st", [100]="+4.0st", [101]="+4.1st", [102]="+4.2st", [103]="+4.4st",
  [104]="+4.5st", [105]="+4.6st", [106]="+4.7st", [107]="+4.8st", [108]="+4.9st", [109]="+5.0st", [110]="+5.1st", [111]="+5.2st",
  [112]="+5.3st", [113]="+5.5st", [114]="+5.6st", [115]="+5.7st", [116]="+5.8st", [117]="+5.9st", [118]="+6.0st", [119]="+6.1st",
  [120]="+6.2st", [121]="+6.3st", [122]="+6.4st", [123]="+6.6st", [124]="+6.7st", [125]="+6.8st", [126]="+6.9st", [127]="+7.0st",
}

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

-- ---------------------------------------------------------------------------
-- BCR2000 #1 sync state — declared before requestPatchDump to prevent
-- forward-reference scoping bug (function body captures globals, not locals,
-- when the locals are declared after the function definition).
-- ---------------------------------------------------------------------------

local awaitingBlocks  = 0   -- counts DT1 blocks expected after requestPatchDump
local pushToggleState = {}  -- BCR push-encoder toggle state; key = channel*1000+cc
local syncTimer       = 0   -- frame countdown; fires syncBCR1() as a fallback

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
local function tb3Send7bit(a1, a2, a3, a4, value)
  local data = {a1, a2, a3, a4, value}
  local cs = tb3Checksum(data)
  sendMIDI({0xF0, 0x41, 0x10, 0x00, 0x00, 0x7B, 0x12,
            a1, a2, a3, a4, value, cs, 0xF7}, TB3_CONNECTION)
end

-- Send a 16-bit SysEx parameter (VCF cutoff, resonance, env depth, tuning…).
-- a1–a4 is the MSB address; LSB address is a4+1 (Roland convention).
-- value is the full integer (0–255).
local function tb3Send16bit(a1, a2, a3, a4, value)
  local msb = math.floor(value / 16)
  local lsb = value % 16
  local cs = tb3Checksum({a1, a2, a3, a4, msb, lsb})
  sendMIDI({0xF0, 0x41, 0x10, 0x00, 0x00, 0x7B, 0x12,
            a1, a2, a3, a4, msb, lsb, cs, 0xF7}, TB3_CONNECTION)
end

-- Send a 14-bit NRPN packet to the BCR connection (channel 1) so the LED
-- ring of an NRPN-assigned encoder tracks state. Param MSB is always 0
-- (see BCR.NRPN_MAP in bcr_map.lua). The BCR ignores NRPN numbers with no
-- assigned encoder, so mirroring entries 5–7 (no physical encoder) is
-- harmless — and gives a future external NRPN controller feedback for free.
-- NEVER send plain CC 6/38/98/99 on this channel: the BCR's own NRPN
-- receive parser would misread them as status bytes.
local function sendNRPNToBCR(nrpn, value)
  local st = 0xB0 + (BCR1_CHANNEL - 1)
  sendMIDI({st, 99, 0},                          BCR_CONNECTION)  -- param MSB
  sendMIDI({st, 98, nrpn},                       BCR_CONNECTION)  -- param LSB
  sendMIDI({st, 6,  math.floor(value / 128)},    BCR_CONNECTION)  -- data MSB
  sendMIDI({st, 38, value % 128},                BCR_CONNECTION)  -- data LSB
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
  local blockKey = string.format("%02X%02X%02X00", a[1], a[2], a[3])
  if entry.bits == 16 then
    local raw = math.floor(x * (entry.max or 255) + 0.5)
    tb3Send16bit(a[1], a[2], a[3], a[4], raw)
    local blk = rawSysexBlocks[blockKey]
    if blk then
      blk.data[a[4] + 1] = math.floor(raw / 16)
      blk.data[a[4] + 2] = raw % 16
    end
  else
    local raw = math.floor(x * (entry.max or 127) + 0.5)
    tb3Send7bit(a[1], a[2], a[3], a[4], raw)
    local blk = rawSysexBlocks[blockKey]
    if blk then blk.data[a[4] + 1] = raw end
  end
end

-- ---------------------------------------------------------------------------
-- Scoped node lookup — avoids ring_mod/vco name collisions (saw_enc)
-- ---------------------------------------------------------------------------

-- Look up an encoder group using the "section,enc" path format from EncMap.
-- Prefers a section-scoped lookup (section → children[enc]) to avoid name
-- collisions (e.g. saw_enc exists in both ring_mod_group and vco_group).
-- Falls back to a global findByName if the scoped lookup returns nil so that
-- results degrade gracefully rather than silently dropping updates.
local function findEncByPath(path)
  local sec, enc = path:match("^([^,]+),([^,]+)$")
  if not sec then return root:findByName(path, true) end
  local secGrp = root:findByName(sec, true)
  local node   = secGrp and secGrp.children[enc]
  if not node  then node = root:findByName(enc, true) end
  return node
end

-- ---------------------------------------------------------------------------
-- UI update helpers — called after BCR input so faders reflect hardware state
-- ---------------------------------------------------------------------------

-- Update a control_fader (and its value_label) by SysEx address.
-- ccVal is the raw BCR CC value (0–127); srcEntry gives the parameter's max.
local function updateUIForAddr(addr, ccVal, srcEntry)
  local key = string.format("%02X%02X%02X%02X",
    addr[1], addr[2], addr[3], addr[4])
  local hit = EncMap.ADDR_TO_ENC[key]
  if not hit then return end
  local encGrp = findEncByPath(hit.path)
  if not encGrp then return end
  local x = ccVal / 127
  local fader = encGrp.children["control_fader"]
  -- Setting fader.values.x fires control_fader → enc_moved, which re-derives
  -- the correct label from EncMap.ENC_SEND_MAP (handles bipolar, signed, semitoneRange,
  -- custom max, etc.).  Do NOT set the label here — that would overwrite the
  -- enc_moved result with a flat 0–max value that ignores display encoding.
  if fader then fader.values.x = x end
end

-- Update a sw_button (or standalone toggle button) by SysEx address.
-- v is 0 or 1.
local function updateSwUIForAddr(addr, v)
  local key = string.format("%02X%02X%02X%02X",
    addr[1], addr[2], addr[3], addr[4])
  local hit = EncMap.ADDR_TO_SW[key]
  if not hit then return end
  local node = findEncByPath(hit.path)
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

-- Set around every PatchManager.parseBlock() call (patch dump / OSC patch / restore).
-- applyValue() sets fader/switch values directly, which synchronously
-- triggers control_fader/sw_button → enc_moved/sw_toggled → SysEx back to
-- the TB-3. That round trip is pointless when we're just mirroring received
-- data into the UI — and actively harmful for any parameter whose
-- EncMap.ENC_SEND_MAP scaling differs from its REGISTRY scaling (e.g. BENDER RANGE:
-- max 17 vs 23), which silently rewrites the hardware value on every sync.
-- The enc_moved/sw_toggled handlers check this flag and skip the SysEx send
-- (but still update labels / mirror to the BCR LED rings).
--
-- Cleared synchronously right after PatchManager.parseBlock() returns (the normal path —
-- PatchManager.parseBlock and everything it triggers run synchronously, so this is exact
-- and never swallows real user input). receivingPatchTimer is a frame-based
-- backstop that force-clears the flag a few frames later in case PatchManager.parseBlock
-- errors partway through — TouchOSC's sandboxed Lua has no pcall, so we
-- can't wrap-and-restore directly.
local receivingPatch = false
local receivingPatchTimer = 0

local function syncBCR1()
  for cc, entry in pairs(BCR.MAP) do
    if entry.addr then
      local key = string.format("%02X%02X%02X%02X",
        entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
      if entry.max == 1 then
        -- Toggle switch: read sw_button / standalone button state
        local hit = EncMap.ADDR_TO_SW[key]
        if hit then
          local node = findEncByPath(hit.path)
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
        local hit = EncMap.ADDR_TO_ENC[key]
        if hit then
          local encGrp = findEncByPath(hit.path)
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
  -- NRPN-controlled 16-bit params (tunings, VCF env depth, cutoff, etc.).
  -- Value = raw SysEx value (fader 0–1 × entry max), not a 0–127 CC value.
  -- Address-less entries (morph, NRPN 8) are synced manually below.
  for nrpn, entry in pairs(BCR.NRPN_MAP) do
    if entry.addr then
      local key = string.format("%02X%02X%02X%02X",
        entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
      local hit = EncMap.ADDR_TO_ENC[key]
      if hit then
        local encGrp = findEncByPath(hit.path)
        local fader  = encGrp and encGrp.children["control_fader"]
        if fader then
          sendNRPNToBCR(nrpn, math.floor(fader.values.x * entry.max + 0.5))
        end
      end
    end
  end
  -- Morph amount (NRPN 8) and morph on/off (CC 40) — no addr entries, handled manually
  sendNRPNToBCR(8, math.floor(morphAmount * BCR.NRPN_MAP[8].max + 0.5))
  sendMIDI({0xB0, 40, patchGridMode == "morph" and 127 or 0}, BCR_CONNECTION)
end

-- Return the current fader x (0–1) for any paramId, including EFX slot params.
-- Used by syncLaunchkey to push assign-slot CC values after a full sync.
local function getFaderXForParamId(paramId)
  local path = PatchManager.PARAM_ID_TO_PATH[paramId]
  if path then
    local encGrp = findEncByPath(path)
    local fader  = encGrp and encGrp.children["control_fader"]
    return fader and fader.values.x
  end
  local efxNum, off
  if paramId >= 77 and paramId <= 170 then
    efxNum = 1; off = paramId - 76
  elseif paramId >= 172 and paramId <= 253 then
    efxNum = 2; off = paramId - 171
  end
  if efxNum and off then
    local typeIdx = PatchManager.efxCurType[efxNum] or 0
    local offs = PatchManager.EFX_SLOT_OFFSETS_SHARED[typeIdx]
    if not offs then
      local sp = PatchManager.EFX_SLOT_OFFSETS_SPECIAL[efxNum]
      offs = sp and sp[typeIdx]
    end
    if offs then
      for slotIdx = 1, 12 do
        if offs[slotIdx] == off then
          local slotGrp = root:findByName(
            string.format("efx%d_s%02d", efxNum, slotIdx), true)
          local fader = slotGrp and slotGrp.children["control_fader"]
          return fader and fader.values.x
        end
      end
    end
  end
  return nil
end

-- Return the current paramId for an EFX slot identified by sec/enc from enc_moved.
-- sec = "efx1_section" | "efx2_section"; enc = "efx1_s03" etc.
-- Returns nil if sec is not an EFX section or slot has no offset in current type.
local function getEfxSlotParamId(sec, enc)
  local efxNum
  if sec == "efx1_section" then efxNum = 1
  elseif sec == "efx2_section" then efxNum = 2
  else return nil end
  local slotIdx = tonumber(enc:match("%d+$"))
  if not slotIdx then return nil end
  local typeIdx = PatchManager.efxCurType[efxNum] or 0
  local offs = PatchManager.EFX_SLOT_OFFSETS_SHARED[typeIdx]
  if not offs then
    local sp = PatchManager.EFX_SLOT_OFFSETS_SPECIAL[efxNum]
    offs = sp and sp[typeIdx]
  end
  if not offs then return nil end
  local off = offs[slotIdx]
  if not off then return nil end
  return efxNum == 1 and (76 + off) or (171 + off)
end

-- Push current fader positions to the Launchkey MK4's encoder LED rings via CC.
-- Assign-slot entries (17/12/13) are omitted — values depend on active assignment.
local function syncLaunchkey()
  for cc, entry in pairs(LAUNCHKEY_CC_MAP) do
    local ccVal
    if entry.addr then
      local hit = EncMap.ADDR_TO_ENC[string.format("%02X%02X%02X%02X",
        entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])]
      if hit then
        local encGrp = findEncByPath(hit.path)
        local fader  = encGrp and encGrp.children["control_fader"]
        if fader then ccVal = math.floor(fader.values.x * 127 + 0.5) end
      end
    elseif entry.globalTuning then
      local encGrp = findEncByPath("tuning_group,tuning_enc")
      local fader  = encGrp and encGrp.children["control_fader"]
      if fader then ccVal = math.floor(fader.values.x * 127 + 0.5) end
    elseif entry.morph then
      ccVal = math.floor(morphAmount * 127 + 0.5)
    elseif entry.assignCC then
      -- Assign-slot: push the current value of the assigned parameter, if any.
      -- getFaderXForParamId handles both regular encoder params and EFX slot params.
      local slotKey = LAUNCHKEY_ASSIGN_CC_REVERSE[cc]
      if slotKey then
        local paramId = PatchManager.assignedParamIds[slotKey]
        if paramId then
          local fx = getFaderXForParamId(paramId)
          if fx then ccVal = math.floor(fx * 127 + 0.5) end
        end
      end
    end
    if ccVal then sendMIDI({0xB0, cc, ccVal}, LAUNCHKEY_CONNECTION) end
  end
end

-- ---------------------------------------------------------------------------
-- Generic SysEx send from a bcr_map entry
-- ---------------------------------------------------------------------------

local function sendFromEntry(entry, ccVal)
  local a = entry.addr
  local blockKey = string.format("%02X%02X%02X00", a[1], a[2], a[3])
  if entry.bits == 16 then
    local val16 = math.floor(ccVal / 127 * (entry.max or 255) + 0.5)
    tb3Send16bit(a[1], a[2], a[3], a[4], val16)
    local blk = rawSysexBlocks[blockKey]
    if blk then
      blk.data[a[4] + 1] = math.floor(val16 / 16)
      blk.data[a[4] + 2] = val16 % 16
    end
  else
    local scaled = ccScale(ccVal, entry.max or 127)
    tb3Send7bit(a[1], a[2], a[3], a[4], scaled)
    local blk = rawSysexBlocks[blockKey]
    if blk then blk.data[a[4] + 1] = scaled end
  end
end

-- ---------------------------------------------------------------------------
-- Distortion type state
-- NOTE: distType, DIST_TYPE_NAMES and DIST_NUM_TYPES live on the PatchManager
-- namespace table (patch_manager.lua, included before this file) so parseBlock
-- and root share one source of truth.  Read/write via PatchManager.* — do NOT
-- shadow them with a new local here.
-- ---------------------------------------------------------------------------

local DIST_TYPE_ADDR = {0x10, 0x00, 0x0E, 0x01}

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

-- NRPN receive state (BCR1, channel 1). pmsb/plsb = param select (CC 99/98);
-- dmsb = data entry MSB (CC 6). Dispatch happens on CC 38 (data LSB) —
-- the BCR's absolute/14 mode always sends the full 4-message packet, so
-- there is no partial-update edge case.
local nrpnState = { pmsb = 0, plsb = 0, dmsb = 0 }

local function handleBCR1(cc, ccVal)
  -- NRPN status bytes — must be consumed before every other branch so they
  -- can never fall through to the BCR.MAP lookup or special cases.
  -- CC 6/38/98/99 are reserved on channel 1 (see bcr_map.lua header).
  if cc == 99 then nrpnState.pmsb = ccVal; return end
  if cc == 98 then nrpnState.plsb = ccVal; return end
  if cc == 6  then nrpnState.dmsb = ccVal; return end
  if cc == 38 then
    -- Data Entry LSB completes the 14-bit value → dispatch.
    local nrpn  = nrpnState.pmsb * 128 + nrpnState.plsb
    local entry = BCR.NRPN_MAP[nrpn]
    if not entry then return end
    local v = nrpnState.dmsb * 128 + ccVal
    if v > entry.max then v = entry.max end
    if entry.morph then
      -- MORPH AMOUNT — layout-internal, no SysEx address. Setting the fader
      -- fires enc_moved → morph_enc special case, which updates the percent
      -- label; its second applyMorph() is a no-op (morphLastBlocks diff guard).
      if patchGridMode ~= "morph" or not morphTargetSlot then return end
      morphAmount = v / entry.max
      applyMorph()
      local morphEnc = root:findByName("morph_enc", true)
      if morphEnc then
        local fader = morphEnc.children["control_fader"]
        if fader then fader.values.x = morphAmount end
      end
      return
    end
    local a = entry.addr
    tb3Send16bit(a[1], a[2], a[3], a[4], v)
    -- Keep the snapshot cache fresh (MSB/LSB nibbles, Roland convention).
    local blk = rawSysexBlocks[string.format("%02X%02X%02X00", a[1], a[2], a[3])]
    if blk then
      blk.data[a[4] + 1] = math.floor(v / 16)
      blk.data[a[4] + 2] = v % 16
    end
    -- Update the on-screen fader. Don't use updateUIForAddr (assumes 0–127
    -- input); scale by the entry's raw max instead. Setting fader.values.x
    -- fires control_fader → enc_moved, which re-derives the bipolar/center
    -- label and echoes the NRPN packet back to the BCR (harmless, no loop).
    local key = string.format("%02X%02X%02X%02X", a[1], a[2], a[3], a[4])
    local hit = EncMap.ADDR_TO_ENC[key]
    if hit then
      local encGrp = findEncByPath(hit.path)
      local fader  = encGrp and encGrp.children["control_fader"]
      if fader then fader.values.x = v / entry.max end
    end
    return
  end

  -- MORPH AMOUNT: was plain CC 8; now NRPN 8 (handled by the dispatch above).

  -- MORPH ON/OFF (CC 40) — encoder group 1 push, position 8
  -- BCR "Toggle On" mode: 127 = latched on, 0 = released.
  if cc == 40 then
    if ccVal >= 64 then
      patchGridMode = "morph"
      morphTargetSlot = nil
      morphBaseSnapshot = nil
      morphLastBlocks = nil
    else
      if patchGridMode == "morph" then
        patchGridMode = nil
        morphTargetSlot = nil
        morphBaseSnapshot = nil
        morphLastBlocks = nil
      end
    end
    broadcastPatchMode()
    return
  end

  -- DIST TYPE (CC 88) — update PatchManager.distType state BEFORE setting fader so that the
  -- enc_moved special case guard (typeIdx ~= PatchManager.distType) sees them equal and skips
  -- the redundant SysEx send.
  if cc == 88 then
    local typeIdx = math.min(math.floor(ccVal * (PatchManager.DIST_NUM_TYPES - 1) / 127 + 0.5), PatchManager.DIST_NUM_TYPES - 1)
    PatchManager.distType = typeIdx
    local a = DIST_TYPE_ADDR
    tb3Send7bit(a[1], a[2], a[3], a[4], PatchManager.distType)
    local blk = rawSysexBlocks[string.format("%02X%02X%02X00", a[1], a[2], a[3])]
    if blk then blk.data[a[4]+1] = PatchManager.distType end
    local encGrp = root:findByName("dist_type_enc", true)
    if encGrp then
      local fader = encGrp.children["control_fader"]
      -- enc_moved fires but guard prevents double-send; it updates value_label.
      if fader then fader.values.x = PatchManager.DIST_NUM_TYPES > 1 and (PatchManager.distType / (PatchManager.DIST_NUM_TYPES - 1)) or 0 end
    end
    return
  end

  -- GLOBAL TUNING (CC 100) — plain MIDI CC 104 to TB-3, not SysEx.
  -- The TB-3 has no SysEx address for global tuning; responds to CC 104
  -- via standard MIDI. Device-global, not saved in patch dumps.
  -- Note: addition is equivalent to bitwise OR here because 0xB0 lower nibble = 0.
  if cc == 100 then
    sendMIDI({0xB0 + (TB3_MIDI_CHANNEL - 1), 104, ccVal}, TB3_CONNECTION)
    -- Update on-screen global tuning encoder.
    local x = ccVal / 127
    local tuningGrp = root:findByName("tuning_group", true)
    local encGrp    = tuningGrp and tuningGrp.children["tuning_enc"]
    if encGrp then
      local fader = encGrp.children["control_fader"]
      if fader then fader.values.x = x end
      local lbl = encGrp.children["value_label"]
      if lbl then
        lbl.values.text = GLOBAL_TUNING_DISPLAY[ccVal] or "---"
      end
    end
    return
  end

  -- All other BCR1 CCs: flat lookup in BCR.MAP
  local entry = BCR.MAP[cc]
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
  -- BCR Toggle On mode: CC=127 = latch-on press, CC=0 = latch-off press.
  -- Both are distinct physical presses. `,bcr` flag suppresses re-echo feedback.
  local b1 = BCR.efx1BtnIndex(cc)
  if b1 then
    local efx1 = root:findByName("efx1_section", true)
    if efx1 then efx1:notify("btn_press", b1 .. ",bcr") end
    return
  end

  -- EFX2 dedicated buttons (CC 69–72 = B1–B4, CC 77–80 = B5–B8)
  -- B1 (CC 69) = EFX2 SW
  local b2 = BCR.efx2BtnIndex(cc)
  if b2 then
    local efx2 = root:findByName("efx2_section", true)
    if efx2 then efx2:notify("btn_press", b2 .. ",bcr") end
    return
  end

  -- EFX1 param slots (CC 81–84 → S01–S04, 89–92 → S05–S08, 97–100 → S09–S12)
  local s1 = BCR.efx1SlotIndex(cc)
  if s1 then
    local efx1 = root:findByName("efx1_section", true)
    if efx1 then efx1:notify("slot_cc", s1 .. "," .. ccVal) end
    return
  end

  -- EFX2 param slots (CC 85–88 → S01–S04, 93–96 → S05–S08, 101–104 → S09–S12)
  local s2 = BCR.efx2SlotIndex(cc)
  if s2 then
    local efx2 = root:findByName("efx2_section", true)
    if efx2 then efx2:notify("slot_cc", s2 .. "," .. ccVal) end
    return
  end
end

-- ---------------------------------------------------------------------------
-- TB-3 CC receive — hardware knob feedback updates the layout display.
-- CCs 16 (Accent), 74 (Cutoff) and 71 (Resonance) are hardwired standard MIDI —
-- the physical knobs send these alongside their SysEx patch writes.
-- CCs 1/12/13/17 are the four parameter-assign hardware controls; we update
-- whichever on-screen encoder is currently assigned to each slot.
--
-- NOTE: setting fader.values.x triggers control_fader → enc_moved → SysEx
-- back to the TB-3.  This is unnecessary but harmless (no loop forms).
-- ---------------------------------------------------------------------------

-- Fixed CC → encoder path (always mapped regardless of assign state).
-- Updated in F1: accent/cutoff/resonance moved to panel_controls_group.
local TB3_CC_DISPLAY_MAP = {
  [16] = "panel_controls_group,accent_level_enc",
  [71] = "panel_controls_group,vcf_resonance_enc",
  [74] = "panel_controls_group,vcf_cutoff_enc",
}

-- TB-3 assign-control CCs → assign slot keys.
local ASSIGN_CC_SLOTS = {
  [1]  = "xy_mod",       -- XY PAD MODULATION (PAD Z)
  [12] = "pad_x",        -- XY PAD X
  [13] = "pad_y",        -- XY PAD Y
  [17] = "effect_knob",  -- EFX KNOB
}

-- Update the on-screen fader for paramId when an assign CC arrives.
-- ccVal is 0–127 (TB-3 normalises to full param range before sending CC).
-- For EFX slots only updates when the correct type is currently selected.
local function updateUIForParamId(paramId, ccVal)
  local x = ccVal / 127

  -- 1. Regular encoder (from PatchManager.PARAM_ID_MAP)
  local path = PatchManager.PARAM_ID_TO_PATH[paramId]
  if path then
    local encGrp = findEncByPath(path)
    if encGrp then
      local fader = encGrp.children["control_fader"]
      if fader then fader.values.x = x end
    end
    return
  end

  -- 2. EFX slot param: resolve via current type and EFX_SLOT_OFFSETS tables.
  local efxNum, off
  if paramId >= 77 and paramId <= 170 then
    efxNum = 1; off = paramId - 76
  elseif paramId >= 172 and paramId <= 253 then
    efxNum = 2; off = paramId - 171
  end
  if efxNum and off then
    local typeIdx = PatchManager.efxCurType[efxNum] or 0
    local offs = PatchManager.EFX_SLOT_OFFSETS_SHARED[typeIdx]
    if not offs then
      local sp = PatchManager.EFX_SLOT_OFFSETS_SPECIAL[efxNum]
      offs = sp and sp[typeIdx]
    end
    if offs then
      -- Use a numeric loop (not ipairs) so nil gaps in the offset table
      -- (hidden slots like EQ s08, Tremolo s03/s04) don't stop iteration early.
      for slotIdx = 1, 12 do
        local slotOff = offs[slotIdx]
        if slotOff == off then
          local slotGrp = root:findByName(
            string.format("efx%d_s%02d", efxNum, slotIdx), true)
          if slotGrp then
            local fader = slotGrp.children["control_fader"]
            if fader then fader.values.x = x end
          end
          break
        end
      end
    end
  end
end


local function handleTB3CC(cc, ccVal)
  -- Fixed encoder display (cutoff, resonance)
  local encPath = TB3_CC_DISPLAY_MAP[cc]
  if encPath then
    local encGrp = findEncByPath(encPath)
    if not encGrp then return end
    local x = ccVal / 127
    local fader = encGrp.children["control_fader"]
    if fader then fader.values.x = x end
    local lbl = encGrp.children["value_label"]
    if lbl then
      lbl.values.text = tostring(math.floor(x * 255 + 0.5))
    end
    return
  end

  -- Parameter assign controls: update whichever fader is currently assigned.
  local slotKey = ASSIGN_CC_SLOTS[cc]
  if slotKey then
    local paramId = PatchManager.assignedParamIds[slotKey]
    if paramId then updateUIForParamId(paramId, ccVal) end
  end
end

-- ---------------------------------------------------------------------------
-- TB-3 SysEx receive (patch dump) — calls PatchManager.parseBlock from patch_manager.lua
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

  -- Cache raw block for snapshotCurrentPatch() export.
  local addrKey = string.format("%02X%02X%02X%02X",
    addr[1], addr[2], addr[3], addr[4])
  rawSysexBlocks[addrKey] = {addr=addr, data=data}

  -- Decrement BEFORE PatchManager.parseBlock so a Lua error inside PatchManager.parseBlock cannot
  -- prevent the countdown from completing and syncBCR1() from firing.
  local triggerSync = false
  if awaitingBlocks > 0 then
    awaitingBlocks = awaitingBlocks - 1
    if awaitingBlocks == 0 then triggerSync = true end
  end

  -- Guard against PatchManager.parseBlock() and efx_section patch_data processing echoing
  -- values back to the TB-3 (see receivingPatch declaration above).
  -- The flag is kept active through the EFX section notify so that slot fader
  -- updates triggered by applyType() don't fire slot_moved → sendSlotFromFloat
  -- → sendParam, which would echo every slot value straight back to the TB-3.
  -- receivingPatchTimer force-clears the flag in update() as a backstop.
  receivingPatch = true
  receivingPatchTimer = 5
  PatchManager.parseBlock(addr, data)

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

  -- Clear only after both PatchManager.parseBlock and EFX section processing are done.
  receivingPatch = false
  receivingPatchTimer = 0

  if triggerSync then
    syncTimer = 0  -- cancel fallback timer; awaitingBlocks beat it
    syncBCR1()
    syncLaunchkey()
  end

  -- Attempt pending store after every block: succeeds as soon as all required
  -- blocks are present, regardless of awaitingBlocks counter state.
  tryCompletePendingStore()
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

  -- Launchkey MK4 (connection 4): notes/pitch bend pass through; encoders via CC
  if connections[4] then
    local status  = message[1]
    local msgType = status - (status % 16)
    local ch      = (status % 16) + 1
    if ch ~= LAUNCHKEY_CHANNEL then return end

    if msgType == 0x90 or msgType == 0x80 then
      sendMIDI({msgType + (TB3_MIDI_CHANNEL - 1), message[2], message[3]}, TB3_CONNECTION)
    elseif msgType == 0xE0 then
      sendMIDI({0xE0 + (TB3_MIDI_CHANNEL - 1), message[2], message[3]}, TB3_CONNECTION)
    elseif msgType == 0xB0 then
      local cc    = message[2]
      local ccVal = message[3]
      local entry = LAUNCHKEY_CC_MAP[cc]
      if entry then
        local x = ccVal / 127
        if entry.addr then
          -- 16-bit SysEx param: scale 0-127 → 0-255, send SysEx, update on-screen
          local a     = entry.addr
          local val16 = math.floor(x * entry.max + 0.5)
          tb3Send16bit(a[1], a[2], a[3], a[4], val16)
          local blk = rawSysexBlocks[string.format("%02X%02X%02X00", a[1], a[2], a[3])]
          if blk then blk.data[a[4]+1]=math.floor(val16/16); blk.data[a[4]+2]=val16%16 end
          local hit = EncMap.ADDR_TO_ENC[string.format("%02X%02X%02X%02X",a[1],a[2],a[3],a[4])]
          if hit then
            local encGrp = findEncByPath(hit.path)
            if encGrp then
              local fader = encGrp.children["control_fader"]
              if fader then fader.values.x = x end
              local lbl = encGrp.children["value_label"]
              if lbl then lbl.values.text = tostring(val16) end
            end
          end
        elseif entry.assignCC then
          -- Assign-slot param: forward CC to TB-3, update on-screen
          sendMIDI({0xB0 + (TB3_MIDI_CHANNEL - 1), cc, ccVal}, TB3_CONNECTION)
          handleTB3CC(cc, ccVal)
        elseif entry.globalTuning then
          -- Global tuning: forward CC 104 to TB-3, update display, mirror to BCR1
          sendMIDI({0xB0 + (TB3_MIDI_CHANNEL - 1), 104, ccVal}, TB3_CONNECTION)
          local encGrp = findEncByPath("tuning_group,tuning_enc")
          if encGrp then
            local fader = encGrp.children["control_fader"]
            if fader then fader.values.x = x end
            local lbl = encGrp.children["value_label"]
            if lbl then lbl.values.text = GLOBAL_TUNING_DISPLAY[ccVal] or "---" end
          end
          sendMIDI({0xB0, 100, ccVal}, BCR_CONNECTION)
        elseif entry.morph then
          -- Morph amount: gated on morph mode + target selected
          if patchGridMode ~= "morph" or morphTargetSlot == nil then return end
          morphAmount = x
          applyMorph()
          local morphEnc = root:findByName("morph_enc", true)
          local fader    = morphEnc and morphEnc.children["control_fader"]
          if fader then fader.values.x = morphAmount end
        end
      else
        -- Unmapped CC (mod wheel, sustain, etc.): pass through to TB-3
        sendMIDI({0xB0 + (TB3_MIDI_CHANNEL - 1), cc, ccVal}, TB3_CONNECTION)
      end
    end
    return
  end
end

-- ---------------------------------------------------------------------------
-- Patch snapshot helpers
-- ---------------------------------------------------------------------------

local EFX1_KEY = "10001000"
local EFX2_KEY = "10001200"
local EFX1_ADDR = {0x10, 0x00, 0x10, 0x00}
local EFX2_ADDR = {0x10, 0x00, 0x12, 0x00}

-- Build a DT1 hex string from a block's addr+data arrays.
local function blockToHexString(blkAddr, blkData)
  local addrAndData = {}
  for _, b in ipairs(blkAddr) do addrAndData[#addrAndData+1] = b end
  for _, b in ipairs(blkData) do addrAndData[#addrAndData+1] = b end
  local cs = tb3Checksum(addrAndData)
  local msg = {0xF0, 0x41, 0x10, 0x00, 0x00, 0x7B, 0x12}
  for _, b in ipairs(addrAndData) do msg[#msg+1] = b end
  msg[#msg+1] = cs
  msg[#msg+1] = 0xF7
  local hex = {}
  for _, b in ipairs(msg) do hex[#hex+1] = string.format("%02X", b) end
  return table.concat(hex)
end

-- Assemble the current patch state as a JSON string (same shape as /tb3/backup).
-- EFX blocks are read from efx1_section.tag / efx2_section.tag (byte arrays
-- written there by efx_section.lua on every parameter change).
-- Returns nil if any required block is missing (never-synced session).
local function snapshotCurrentPatch()
  local efx1Node = root:findByName("efx1_section", true)
  local efx2Node = root:findByName("efx2_section", true)
  local efx1Data = efx1Node and json.toTable(efx1Node.tag)
  local efx2Data = efx2Node and json.toTable(efx2Node.tag)

  for _, k in ipairs(EXPORT_BLOCK_ORDER) do
    if k == EFX1_KEY then
      if not efx1Data or #efx1Data == 0 then
        if not rawSysexBlocks[k] then return nil end
      end
    elseif k == EFX2_KEY then
      if not efx2Data or #efx2Data == 0 then
        if not rawSysexBlocks[k] then return nil end
      end
    else
      if not rawSysexBlocks[k] then return nil end
    end
  end

  local parts = {}
  for _, k in ipairs(EXPORT_BLOCK_ORDER) do
    local hexStr
    if k == EFX1_KEY and efx1Data and #efx1Data > 0 then
      hexStr = blockToHexString(EFX1_ADDR, efx1Data)
    elseif k == EFX2_KEY and efx2Data and #efx2Data > 0 then
      hexStr = blockToHexString(EFX2_ADDR, efx2Data)
    else
      local blk = rawSysexBlocks[k]
      if not blk then return nil end
      hexStr = blockToHexString(blk.addr, blk.data)
    end
    parts[#parts+1] = '"' .. hexStr .. '"'
  end
  -- Use currentPresetName directly — preset_name_label now holds the combined
  -- "Bank: X  Preset: Y" string and must not be used as the preset name.
  local nameStr = currentPresetName:gsub('"', '\\"')
  return '{"name":"' .. nameStr .. '","blocks":[' .. table.concat(parts, ",") .. ']}'
end

-- Send the current TouchOSC patch state directly to the TB-3 without touching the UI.
-- Uses the same block data as snapshotCurrentPatch but sends raw SysEx, not JSON.
local function sendCurrentPatchToDevice()
  local snapshot = snapshotCurrentPatch()
  if not snapshot then
    print("sendCurrentPatchToDevice: snapshot nil — sync from TB-3 first")
    return
  end
  local t = json.toTable(snapshot)
  if not t or not t.blocks then return end
  for _, hexStr in ipairs(t.blocks) do
    local bytes = {}
    for i = 1, #hexStr - 1, 2 do
      bytes[#bytes+1] = tonumber(hexStr:sub(i, i+1), 16) or 0
    end
    if #bytes >= 14 and bytes[1] == 0xF0 and bytes[2] == 0x41 and bytes[7] == 0x12 then
      sendMIDI(bytes, TB3_CONNECTION)
    end
  end
end

-- Apply a snapshot (JSON string with "blocks" array) to the TB-3 and UI.
-- Each block is a contiguous DT1 hex string (no separators).
-- Sends the SysEx to hardware AND updates the truth cache + UI via handleTB3SysEx.
local function applySnapshot(snapshotJson)
  local t = json.toTable(snapshotJson)
  if not t or not t.blocks then return end
  for _, hexStr in ipairs(t.blocks) do
    local bytes = {}
    for i = 1, #hexStr - 1, 2 do
      bytes[#bytes+1] = tonumber(hexStr:sub(i, i+1), 16) or 0
    end
    if #bytes >= 14 and bytes[1] == 0xF0 and bytes[2] == 0x41 and bytes[7] == 0x12 then
      sendMIDI(bytes, TB3_CONNECTION)
      handleTB3SysEx(bytes)
    end
  end
end

-- Apply only the blocks that differ between targetJson and baseJson.
-- targetJson = where we want to end up; baseJson = current state.
-- Block comparison is on the full hex string (includes checksum, so any
-- data change makes the strings differ).  Positional: both use EXPORT_BLOCK_ORDER.
local function applySnapshotDiff(targetJson, baseJson)
  local target = json.toTable(targetJson)
  if not target or not target.blocks then return end
  local base = (baseJson and json.toTable(baseJson)) or {}
  local baseBlocks = base.blocks or {}
  local sent = 0
  for i, hexStr in ipairs(target.blocks) do
    if hexStr ~= baseBlocks[i] then
      local bytes = {}
      for j = 1, #hexStr - 1, 2 do
        bytes[#bytes+1] = tonumber(hexStr:sub(j, j+1), 16) or 0
      end
      if #bytes >= 14 and bytes[1] == 0xF0 and bytes[2] == 0x41 and bytes[7] == 0x12 then
        sendMIDI(bytes, TB3_CONNECTION)
        handleTB3SysEx(bytes)
        sent = sent + 1
      end
    end
  end
  print("patch_grid: diff applied " .. sent .. "/" .. #target.blocks .. " blocks")
  syncBCR1()
  syncLaunchkey()
end

-- Read all 16 slot snapshots from preset_grid's tag.
local function getPatchGridSlots()
  local pgNode = root:findByName("preset_grid", true)
  if not pgNode then return {} end
  return json.toTable(pgNode.tag) or {}
end

-- Write all 16 slot snapshots back to preset_grid's tag and refresh the UI.
local function setPatchGridSlots(slots)
  local pgNode = root:findByName("preset_grid", true)
  if not pgNode then return end
  pgNode.tag = json.fromTable(slots)
  pgNode:notify("refresh_preset_ui", "")
end

-- Complete an auto-store that was deferred because blocks weren't cached yet.
-- Called after a full dump (awaitingBlocks countdown and syncTimer fallback).
tryCompletePendingStore = function()
  if not pendingStoreSlot then return end
  local snapshot = snapshotCurrentPatch()
  if not snapshot then return end  -- blocks still arriving; retry on next block
  local key = pendingStoreSlot
  pendingStoreSlot = nil
  local slots = getPatchGridSlots()
  slots[key] = json.toTable(snapshot)
  setPatchGridSlots(slots)
  print("patch_grid: pending store completed for slot " .. key)
end

-- Interpolate every data byte between morphBaseSnapshot and the morph target
-- slot at the current morphAmount (0.0–1.0).  Only sends blocks that changed
-- since the last applyMorph call (morphLastBlocks).
applyMorph = function()
  if not morphTargetSlot or not morphBaseSnapshot then return end
  local slots = getPatchGridSlots()
  local targetData = slots[tostring(morphTargetSlot)]
  if not targetData then return end

  local base   = json.toTable(morphBaseSnapshot)
  local target = json.toTable(json.fromTable(targetData))
  if not base or not target or not base.blocks or not target.blocks then return end

  local t = morphAmount   -- 0.0–1.0

  local blended = {}
  for i = 1, #base.blocks do
    local bHex = base.blocks[i]
    local tHex = target.blocks[i] or bHex
    if bHex == tHex then
      blended[i] = bHex
    else
      local bB, tB = {}, {}
      for j = 1, #bHex - 1, 2 do bB[#bB+1] = tonumber(bHex:sub(j,j+1),16) or 0 end
      for j = 1, #tHex - 1, 2 do tB[#tB+1] = tonumber(tHex:sub(j,j+1),16) or 0 end
      local addr = {bB[8], bB[9], bB[10], bB[11]}
      local addrKey = string.format("%02X%02X%02X%02X",
        bB[8], bB[9], bB[10], bB[11])
      local u16Offs = PatchManager.U16_OFFSETS[addrKey]
      local newData = {}
      local skipNext = false
      for j = 12, #bB - 2 do
        if skipNext then
          skipNext = false
        else
          local dataOff = j - 12  -- 0-based offset into block data
          if u16Offs and u16Offs[dataOff] then
            -- nibble-packed 16-bit pair: interpolate as a unit to avoid jumps
            local rawB = (bB[j] or 0) * 16 + (bB[j+1] or 0)
            local rawT = (tB[j] or 0) * 16 + (tB[j+1] or 0)
            local rawOut = math.floor(rawB + (rawT - rawB) * t + 0.5)
            newData[#newData+1] = math.floor(rawOut / 16)
            newData[#newData+1] = rawOut % 16
            skipNext = true
          else
            local b  = bB[j] or 0
            local tb = tB[j] or b
            newData[#newData+1] = math.floor(b + (tb - b) * t + 0.5)
          end
        end
      end
      blended[i] = blockToHexString(addr, newData)
    end
  end

  local prev = morphLastBlocks or {}
  local anyChanged = false
  morphing = true
  for i, hexStr in ipairs(blended) do
    if hexStr ~= prev[i] then
      anyChanged = true
      local bytes = {}
      for j = 1, #hexStr - 1, 2 do bytes[#bytes+1] = tonumber(hexStr:sub(j,j+1),16) or 0 end
      if #bytes >= 14 and bytes[1] == 0xF0 and bytes[2] == 0x41 and bytes[7] == 0x12 then
        sendMIDI(bytes, TB3_CONNECTION)
        handleTB3SysEx(bytes)
      end
    end
  end
  morphing = false
  morphLastBlocks = blended
  -- Debounced BCR sync: arm (or re-arm) the countdown instead of syncing
  -- synchronously. A per-detent syncBCR1() floods the BCR (~60 messages) and
  -- echoes NRPN 8 back at the morph encoder while it is still moving — the
  -- stale echoes snap the encoder position backwards (jerky response). The
  -- timer fires one full sync ~0.3s after the last morph step, when the
  -- echoed morph amount matches the encoder's resting position.
  if anyChanged then syncTimer = 40 end
end

-- Broadcast the current mode to all mode buttons.
broadcastPatchMode = function()
  local modeStr = patchGridMode or ""
  local btns = {"morph_button", "delete_button", "grab_mode_button"}
  for _, name in ipairs(btns) do
    local btn = root:findByName(name, true)
    if btn then btn:notify("patch_mode_changed", modeStr) end
  end
  local pgNode = root:findByName("preset_grid", true)
  if pgNode then pgNode:notify("patch_mode_changed", modeStr) end
  -- morph_group visibility is always-on; no longer toggled here.
  -- When entering morph mode: show "-" in morph_preset_label and "Pick Preset"
  -- in the morph_enc value_label. On exit: clear both.
  local morphLbl = root:findByName("morph_preset_label", true)
  if morphLbl then
    morphLbl.values.text = patchGridMode == "morph" and "-" or ""
  end
  local morphEnc = root:findByName("morph_enc", true)
  local encValLbl = morphEnc and morphEnc.children["value_label"]
  if encValLbl then
    encValLbl.values.text = patchGridMode == "morph" and "Pick Preset" or ""
  end
  updateMorphEncState()
end

-- Enable morph_enc only when morph mode is on and a target preset is selected.
local MORPH_ENC_DIM = "777777FF"
local MORPH_ENC_LIT = "FFFFFFFF"

updateMorphEncState = function()
  local morphEnc = root:findByName("morph_enc", true)
  if not morphEnc then return end
  local enabled = (patchGridMode == "morph" and morphTargetSlot ~= nil)
  local waitingForPick = (patchGridMode == "morph" and not morphTargetSlot)
  morphEnc.tag = enabled and "" or "disabled"
  local valLbl = morphEnc.children["value_label"]
  local nameLbl = morphEnc.children["name_label"]
  -- "Pick Preset" prompt stays white; only the encoder ring/name dim when disabled.
  if valLbl then
    valLbl.textColor = Color.fromHexString(
      (enabled or waitingForPick) and MORPH_ENC_LIT or MORPH_ENC_DIM)
  end
  if nameLbl then
    nameLbl.textColor = Color.fromHexString(enabled and MORPH_ENC_LIT or MORPH_ENC_DIM)
  end
end

-- Update the single combined preset_name_label with bank + preset info.
-- Call whenever currentBankName or currentPresetName changes.
local function updatePatchInfoLabel()
  local lbl = root:findByName("preset_name_label", true)
  if not lbl then return end
  local parts = {}
  if currentBankName   ~= "" then parts[#parts+1] = "Bank: "   .. currentBankName   end
  if currentPresetName ~= "" then parts[#parts+1] = "Preset: " .. currentPresetName end
  lbl.values.text = table.concat(parts, "  ")
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

  -- Sent by send_button.lua — push current TouchOSC state to TB-3.
  if key == "send_patch_to_device" then
    sendCurrentPatchToDevice()
    return
  end

  -- Sent by sync_to_controllers_button.lua — push current state to BCRs + Launchkey.
  if key == "sync_to_controllers" then
    syncBCR1()
    syncLaunchkey()
    local efx1 = root:findByName("efx1_section", true)
    local efx2 = root:findByName("efx2_section", true)
    if efx1 then efx1:notify("sync_bcr", "") end
    if efx2 then efx2:notify("sync_bcr", "") end
    return
  end

  -- Sent by control_fader.lua when a fader is moved.
  -- value = "section,enc,x"  (x is a 0–1 float string)
  if key == "enc_moved" then
    local sec, enc, xs = value:match("^([^,]+),([^,]+),(.+)$")
    if sec and enc and xs then
      local x = tonumber(xs) or 0

      -- dist_type_enc special case: guard against redundant SysEx send when
      -- PatchManager.parseBlock sets the fader (PatchManager.distType is already up to date then).
      if sec == "dist_group" and enc == "dist_type_enc" then
        local typeIdx = math.min(math.floor(x * (PatchManager.DIST_NUM_TYPES - 1) + 0.5), PatchManager.DIST_NUM_TYPES - 1)
        if typeIdx ~= PatchManager.distType then
          PatchManager.distType = typeIdx
          local a = DIST_TYPE_ADDR
          tb3Send7bit(a[1], a[2], a[3], a[4], PatchManager.distType)
          local blk = rawSysexBlocks[string.format("%02X%02X%02X00", a[1], a[2], a[3])]
          if blk then blk.data[a[4] + 1] = PatchManager.distType end
        end
        local encGrp = root:findByName("dist_type_enc", true)
        if encGrp then
          local lbl = encGrp.children["value_label"]
          if lbl then lbl.values.text = PatchManager.DIST_TYPE_NAMES[PatchManager.distType + 1] or tostring(PatchManager.distType) end
        end
        return
      end

      -- morph_enc special case: replaces old morph_amount_changed path.
      if sec == "morph_group" and enc == "morph_enc" then
        if patchGridMode ~= "morph" or not morphTargetSlot then return end
        morphAmount = x
        applyMorph()
        -- Do NOT echo CC 105 to Launchkey here — per-step echoes snap the encoder
        -- ring backwards while still sweeping (same fix as BCR NRPN 8 debounce).
        -- syncLaunchkey() sends the final value after the syncTimer debounce.
        -- Show the actual morph amount as a percentage — control_fader's
        -- fallback label is a meaningless 0–127 value here.
        local secGrp = root:findByName(sec, true)
        local encGrp = secGrp and secGrp.children[enc]
        if encGrp then
          local lbl = encGrp.children["value_label"]
          if lbl then lbl.values.text = string.format("%.1f%%", x * 100) end
        end
        return
      end

      local entry = EncMap.ENC_SEND_MAP[sec .. "," .. enc]
      if entry then
        -- Skip the SysEx echo while applying a received patch — see
        -- receivingPatch declaration. Label/BCR mirroring below still runs
        -- so the UI and BCR LED rings reflect the received value.
        if not receivingPatch then
          sendFromEntryFloat(entry, x)
        end

        -- Correct the value_label: control_fader.lua shows a fallback 0-127
        -- value; override it here with the parameter's actual range/encoding.
        -- Use section-scoped child lookup to handle name collisions (e.g.
        -- ring_mod_group and vco_group both have a child named "saw_enc").
        local lbl_text
        if entry.bits == 16 then
          -- 16-bit nibble-packed: full range is 0–max (default 255).
          local m     = entry.max or 255
          local raw16 = math.floor(x * m + 0.5)
          if entry.bipolar then
            -- Use explicit center if set (asymmetric range), else floor(m/2).
            -- e.g. tuning: max=151, center=127 → display −127…+24.
            local half = entry.center or math.floor(m / 2)
            local s    = raw16 - half
            lbl_text   = (s >= 0 and "+" or "") .. tostring(s)
          else
            lbl_text = tostring(raw16)
          end
        elseif entry.signed then
          -- Signed offset-encoded (7-bit): raw 64 = 0; display −64…+63.
          local raw = math.floor(x * 127 + 0.5)
          local s   = raw - 64
          lbl_text  = (s >= 0 and "+" or "") .. tostring(s)
        elseif entry.bipolar then
          -- Bipolar 7-bit (e.g. DIST BOTTOM/TONE, max=100): centre = floor(max/2).
          local m    = entry.max or 100
          local raw  = math.floor(x * m + 0.5)
          local s    = raw - math.floor(m / 2)
          lbl_text   = (s >= 0 and "+" or "") .. tostring(s)
        elseif entry.semitoneRange then
          -- Range-size display: raw N → ±(N+1) semitones (BENDER RANGE: 0=±1 ... 23=±24).
          local raw = math.floor(x * (entry.max or 127) + 0.5)
          lbl_text  = "\194\177" .. tostring(raw + 1) .. " st"  -- \194\177 = UTF-8 plus-minus sign
        elseif entry.max and entry.max ~= 127 then
          -- Custom 7-bit max (e.g. DRIVE=120). BENDER RANGE has its own
          -- semitoneRange branch above despite also having a custom max.
          lbl_text = tostring(math.floor(x * entry.max + 0.5))
        elseif entry.sp == "global_tuning" then
          -- Global tuning: CC 104. Lookup table verified against hardware.
          local cc = math.floor(x * 127 + 0.5)
          lbl_text = GLOBAL_TUNING_DISPLAY[cc] or "---"
        end
        if lbl_text then
          local secGrp = root:findByName(sec, true)
          local encGrp = secGrp and secGrp.children[enc]
          if encGrp then
            local lbl = encGrp.children["value_label"]
            if lbl then lbl.values.text = lbl_text end
          end
        end

        -- Mirror to BCR2000 #1 and Launchkey MK4.
        -- Skip during morph — applyMorph calls syncBCR1() + syncLaunchkey() once after the batch.
        if not morphing then
          if entry.sp == "global_tuning" then
            -- Global tuning has no SysEx addr; BCR uses CC 100 on channel 1.
            sendMIDI({0xB0, 100, math.floor(x * 127 + 0.5)}, BCR_CONNECTION)
          elseif entry.addr then
            local addrKey = string.format("%02X%02X%02X%02X",
              entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
            local bcr1cc = BCR.ADDR_TO_CC[addrKey]
            if bcr1cc then
              sendMIDI({0xB0, bcr1cc, math.floor(x * 127 + 0.5)}, BCR_CONNECTION)
            else
              -- 16-bit NRPN-controlled param: mirror as a full NRPN packet
              -- carrying the raw value (x × max), not a 0–127 CC value.
              local nh = BCR.ADDR_TO_NRPN[addrKey]
              if nh then
                sendNRPNToBCR(nh.nrpn, math.floor(x * nh.entry.max + 0.5))
              end
            end
          end

          -- Mirror to Launchkey MK4 (CC).
          local lkCCVal = math.floor(x * 127 + 0.5)
          if entry.sp == "global_tuning" then
            sendMIDI({0xB0, 104, lkCCVal}, LAUNCHKEY_CONNECTION)
          elseif entry.addr then
            local addrKey = string.format("%02X%02X%02X%02X",
              entry.addr[1], entry.addr[2], entry.addr[3], entry.addr[4])
            local lkCC = LAUNCHKEY_ADDR_TO_CC[addrKey]
            if lkCC then sendMIDI({0xB0, lkCC, lkCCVal}, LAUNCHKEY_CONNECTION) end
          end
          -- If this param is assigned to a Launchkey assign slot, mirror there too.
          local currentPath = sec .. "," .. enc
          for slotKey, lkCC in pairs(LAUNCHKEY_ASSIGN_CC) do
            local paramId = PatchManager.assignedParamIds[slotKey]
            if paramId and PatchManager.PARAM_ID_TO_PATH[paramId] == currentPath then
              sendMIDI({0xB0, lkCC, lkCCVal}, LAUNCHKEY_CONNECTION)
            end
          end
        end
      else
        -- Not in EncMap.ENC_SEND_MAP — route EFX slot faders to their section.
        -- sec = "efx1_section" or "efx2_section"; enc = "efx1_s03" etc.
        -- Skip during patch receive: applyType() sets slot faders from rawData,
        -- and we must not echo them back via sendSlotFromFloat → sendParam.
        if not receivingPatch then
          local efxSection = root:findByName(sec, true)
          if efxSection then efxSection:notify("slot_moved", enc .. "," .. xs) end
        end
        -- Mirror to Launchkey assign slots if this EFX slot is currently assigned.
        if not morphing then
          local efxParamId = getEfxSlotParamId(sec, enc)
          if efxParamId then
            local lkCCVal = math.floor(x * 127 + 0.5)
            for slotKey, lkCC in pairs(LAUNCHKEY_ASSIGN_CC) do
              if PatchManager.assignedParamIds[slotKey] == efxParamId then
                sendMIDI({0xB0, lkCC, lkCCVal}, LAUNCHKEY_CONNECTION)
              end
            end
          end
        end
      end
    end
    return
  end

  -- Sent by sw_button.lua and porta_mode_button.lua when a toggle is pressed.
  -- value = "section,enc,v"  (v is 0 or 1)
  if key == "sw_toggled" then
    local sec, enc, vs = value:match("^([^,]+),([^,]+),(%d+)$")
    if sec and enc and vs then
      local entry = EncMap.SW_SEND_MAP[sec .. "," .. enc]
      if entry then
        local a = entry.addr
        local v = tonumber(vs) or 0
        -- Skip the SysEx echo while applying a received patch — see
        -- receivingPatch declaration. BCR mirroring below still runs.
        if not receivingPatch then
          tb3Send7bit(a[1], a[2], a[3], a[4], v)
          local blk = rawSysexBlocks[string.format("%02X%02X%02X00", a[1],a[2],a[3])]
          if blk then blk.data[a[4] + 1] = v end
        end
        -- Mirror to BCR2000 #1 if this switch has a BCR mapping.
        local addrKey = string.format("%02X%02X%02X%02X", a[1],a[2],a[3],a[4])
        local bcr1cc = BCR.ADDR_TO_CC[addrKey]
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
    local blk = rawSysexBlocks["10001400"]
    if blk then blk.data[0x02 + 1] = v end
    -- Notify both radio buttons so they update their visual state in sync.
    local legato = root:findByName("porta_legato_btn", true)
    local always  = root:findByName("porta_always_btn", true)
    if legato then legato:notify("porta_mode_updated", value) end
    if always  then always:notify("porta_mode_updated", value) end
    return
  end

  -- Sent by assign_slot_btn.lua when the user presses (or re-presses) an
  -- assign slot button.  value = slot key ("xy_mod"/"effect_knob"/…) or ""
  -- to cancel.  Pressing the active slot again also cancels.
  if key == "assign_slot_select" then
    local slot = value
    -- Pressing the active slot button again (or sending "" explicitly) cancels.
    if slot == "" or slot == assignActiveSlot then
      assignActiveSlot = nil
      broadcastAssignMode(nil)
    else
      assignActiveSlot = slot
      broadcastAssignMode(slot)
    end
    refreshAssignLabel()
    return
  end

  -- Sent by pointer.lua on PointerState.BEGIN (finger-down on any encoder).
  -- When assign mode is active, assigns that encoder's parameter to the pending slot.
  -- Also handles EFX section slots (type-dependent resolution via EFX_SLOT_OFFSETS).
  if key == "enc_touched" then
    if not assignActiveSlot then return end
    local sec, enc = value:match("^([^,]+),([^,]+)$")
    if sec and enc then
      -- 1. Check regular encoder map.
      local paramInfo = PatchManager.PARAM_ID_MAP[sec .. "," .. enc]
      if paramInfo then
        local slotEntry = ASSIGN_SLOTS[assignActiveSlot]
        if slotEntry then
          local a = slotEntry.addr
          tb3Send16bit(a[1], a[2], a[3], a[4], paramInfo.id)
          PatchManager.assignedParamIds[assignActiveSlot] = paramInfo.id
        end
        assignActiveSlot = nil
        broadcastAssignMode(nil)
        refreshAssignLabel()
      else
        -- 2. Check EFX section slots (sec = "efx1_section" / "efx2_section").
        local efxNum = tonumber(sec:match("^efx(%d+)_section$"))
        if efxNum then
          local slotIdx = tonumber(enc:match("_s(%d+)$"))
          if slotIdx then
            local typeIdx = PatchManager.efxCurType[efxNum] or 0
            -- Try shared types first, then EFX-specific.
            local offs = PatchManager.EFX_SLOT_OFFSETS_SHARED[typeIdx]
            if not offs then
              local sp = PatchManager.EFX_SLOT_OFFSETS_SPECIAL[efxNum]
              offs = sp and sp[typeIdx]
            end
            local off = offs and offs[slotIdx]
            if off then
              local paramId = PatchManager.EFX_BASE_PARAM[efxNum] + off
              local slotEntry = ASSIGN_SLOTS[assignActiveSlot]
              if slotEntry then
                local a = slotEntry.addr
                tb3Send16bit(a[1], a[2], a[3], a[4], paramId)
                PatchManager.assignedParamIds[assignActiveSlot] = paramId
              end
              assignActiveSlot = nil
              broadcastAssignMode(nil)
              refreshAssignLabel()
            end
          end
        end
      end
    end
    return
  end

  -- Sent by sw_button.lua and dist_toggle_button.lua on any value change.
  -- When assign mode is active, assigns the switch parameter to the pending slot
  -- and sends "assign_revert" back to the button so it doesn't actually toggle.
  if key == "sw_touched" then
    if not assignActiveSlot then return end
    local sec, enc = value:match("^([^,]+),([^,]+)$")
    if sec and enc then
      local swInfo = PatchManager.SW_PARAM_ID_MAP[sec .. "," .. enc]
      if swInfo then
        local slotEntry = ASSIGN_SLOTS[assignActiveSlot]
        if slotEntry then
          local a = slotEntry.addr
          tb3Send16bit(a[1], a[2], a[3], a[4], swInfo.id)
          PatchManager.assignedParamIds[assignActiveSlot] = swInfo.id
        end
        -- Revert the button's visual state so the tap doesn't actually toggle it.
        if swInfo.btn then
          -- Standalone BUTTON node (dist_on_off, dist_color)
          local btn = root:findByName(enc, true)
          if btn then btn:notify("assign_revert", "") end
        else
          -- sw_button child inside an encoder group
          local grp = root:findByName(enc, true)
          if grp then
            local swBtn = grp.children["sw_button"]
            if swBtn then swBtn:notify("assign_revert", "") end
          end
        end
        assignActiveSlot = nil
        broadcastAssignMode(nil)
        refreshAssignLabel()
      end
    end
    return
  end

  -- Sent by efx_section.lua B1 handler when the EFX SW button is pressed.
  -- value = "efxNum,swOff"; paramId = PatchManager.EFX_BASE_PARAM[efxNum] + swOff.
  if key == "efx_sw_touched" then
    if not assignActiveSlot then return end
    local efxNum, offStr = value:match("^(%d+),(%d+)$")
    efxNum = tonumber(efxNum)
    local off = tonumber(offStr)
    if efxNum and off then
      local paramId = PatchManager.EFX_BASE_PARAM[efxNum] + off
      local slotEntry = ASSIGN_SLOTS[assignActiveSlot]
      if slotEntry then
        local a = slotEntry.addr
        tb3Send16bit(a[1], a[2], a[3], a[4], paramId)
        PatchManager.assignedParamIds[assignActiveSlot] = paramId
      end
      assignActiveSlot = nil
      broadcastAssignMode(nil)
      refreshAssignLabel()
    end
    return
  end

  -- Sent by efx_section.lua's applyType() whenever the EFX type changes.
  -- Keeps PatchManager.efxCurType in sync so enc_touched can resolve EFX slot param IDs.
  if key == "efx_type_changed" then
    local n, t = value:match("^(%d+),(%d+)$")
    if n then PatchManager.efxCurType[tonumber(n)] = tonumber(t) or 0 end
    return
  end

  -- EFX type direct-select from efx_1_chooser / efx_2_chooser button grids
  -- value = "N,M": N = EFX number (1 or 2), M = type index (button name == type index;
  -- 0 = BYPASS, 1 = COMP, 2 = RING MOD, ...)
  if key == "efx_type_select" then
    local efxNum, typeIdx = value:match("^(%d+),(%d+)$")
    efxNum  = tonumber(efxNum)
    typeIdx = tonumber(typeIdx)
    if efxNum and typeIdx then
      local sectionName = efxNum == 1 and "efx1_section" or "efx2_section"
      local section     = root:findByName(sectionName, true)
      if section then section:notify("type_set", typeIdx) end
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

  -- Sent by mode buttons (delete_button, grab_mode_button, morph_button).
  -- Toggles the mode on/off (pressing the active mode again clears it).
  if key == "patch_mode_set" then
    local wasInMorph = (patchGridMode == "morph")
    if value == patchGridMode then
      patchGridMode = nil
    else
      patchGridMode = value
    end
    if patchGridMode ~= "morph" or not wasInMorph then
      morphTargetSlot = nil
      morphBaseSnapshot = nil
      morphLastBlocks = nil
    end
    pendingStoreSlot = nil
    broadcastPatchMode()
    -- When leaving morph mode, sync BCR1 to the final blended state.
    if wasInMorph then syncBCR1(); syncLaunchkey() end
    return
  end

  -- Sent by slot buttons "1"–"16" under preset_grid.
  -- Default (nil mode): empty slot → store; filled slot → recall.
  -- Delete mode: clear the slot.
  -- Grab / Morph: stubbed — wired but no action yet.
  if key == "patch_slot_pressed" then
    print("patch_grid: slot pressed " .. tostring(value) .. " mode=" .. tostring(patchGridMode))
    local slotNum = tonumber(value)
    if not slotNum then return end
    -- Any new slot press cancels a pending auto-store from a previous tap.
    pendingStoreSlot = nil
    local slots = getPatchGridSlots()
    local slotKey = tostring(slotNum)

    if patchGridMode == "delete" then
      slots[slotKey] = nil
      setPatchGridSlots(slots)
      currentPresetName = ""
      updatePatchInfoLabel()

    elseif patchGridMode == "grab" then
      -- Snapshot current state, diff-apply the slot; release restores.
      if slots[slotKey] then
        grabSnapshot = snapshotCurrentPatch()
        local slotJson = json.fromTable(slots[slotKey])
        applySnapshotDiff(slotJson, grabSnapshot)
      end

    elseif patchGridMode == "morph" then
      -- Record base snapshot and reset fader so morph starts from current patch.
      morphTargetSlot   = slotNum
      morphBaseSnapshot = snapshotCurrentPatch()
      if morphBaseSnapshot then
        morphLastBlocks = (json.toTable(morphBaseSnapshot) or {}).blocks
      end
      morphAmount = 0.0
      local morphEnc = root:findByName("morph_enc", true)
      local fader    = morphEnc and morphEnc.children["control_fader"]
      if fader then fader.values.x = 0.0 end
      local morphLbl = root:findByName("morph_preset_label", true)
      if morphLbl then morphLbl.values.text = tostring(slotNum) end
      local encValLbl = morphEnc and morphEnc.children["value_label"]
      if encValLbl then encValLbl.values.text = "0" end
      updateMorphEncState()

    else
      -- Default: empty → store; filled → recall
      if slots[slotKey] == nil then
        print("patch_grid: storing slot " .. slotKey)
        local snapshot = snapshotCurrentPatch()
        if snapshot then
          print("patch_grid: snapshot ok, saving")
          slots[slotKey] = json.toTable(snapshot)
          setPatchGridSlots(slots)
        else
          print("patch_grid: snapshot nil - blocks missing, triggering sync")
          pendingStoreSlot = slotKey
          requestPatchDump()
        end
      else
        print("patch_grid: recalling slot " .. slotKey)
        applySnapshotDiff(json.fromTable(slots[slotKey]), snapshotCurrentPatch())
        currentPresetName = (type(slots[slotKey]) == "table" and slots[slotKey].name) or ""
        updatePatchInfoLabel()
      end
    end
    return
  end

  -- Sent by slot buttons on release (x → 0).
  -- In grab mode: restore the snapshot saved on press.
  if key == "patch_slot_released" then
    if patchGridMode == "grab" and grabSnapshot then
      -- Diff against current state (= the grabbed preset) to restore original.
      applySnapshotDiff(grabSnapshot, snapshotCurrentPatch())
      grabSnapshot = nil
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
  -- message is an array: message[1] = OSC address path, message[2] = arguments.
  local address   = message[1]
  local arguments = message[2]

  -- Allow external tools (Python, other apps) to trigger a dump request.
  if address == "/tb3/request_dump" then
    requestPatchDump()
    return
  end

  -- Python app requests a snapshot of the current patch (replaces the old
  -- "SAVE TO LIBRARY" TouchOSC button).  Responds with /tb3/backup.
  if address == "/tb3/request_patch_export" then
    local snapshot = snapshotCurrentPatch()
    if snapshot then sendOSC("/tb3/backup", snapshot) end
    return
  end

  -- ---- Chunked bank PULL (root → Python) -------------------------------------
  -- A full 16-slot bank serialises to ~15 KB, but macOS caps a UDP datagram at
  -- net.inet.udp.maxdgram (~9 KB). So instead of one big /backup message we send
  -- a small manifest of filled slots, then one message per slot on request.

  -- Step 1: Python requests the manifest → list of filled slot keys + bank name.
  if address == "/tb3/patchgrid/request_manifest" then
    local slots = getPatchGridSlots()
    local keys = {}
    for k, v in pairs(slots) do
      if type(v) == "table" then keys[#keys + 1] = k end
    end
    sendOSC("/tb3/patchgrid/manifest",
            json.fromTable({version = 2, name = currentBankName, slots = keys}))
    return
  end

  -- Step 2: Python requests one slot (arg = slot key string) → its full data.
  if address == "/tb3/patchgrid/request_slot" then
    local arg = arguments and arguments[1]
    if arg == nil then return end
    local key = (type(arg) == "table") and arg.value or arg
    key = tostring(key)
    local data = getPatchGridSlots()[key]
    if type(data) ~= "table" then return end  -- emptied since manifest; skip
    sendOSC("/tb3/patchgrid/slot", json.fromTable({slot = key, data = data}))
    return
  end

  -- ---- Chunked bank PUSH (Python → root) -------------------------------------
  -- restore_begin resets a staging buffer, each restore_slot adds one slot, and
  -- restore_end commits the whole staged bank to the grid. Same size rationale.
  if address == "/tb3/patchgrid/restore_begin" then
    bankRestoreStaging = {}
    local arg = arguments and arguments[1]
    local s = (type(arg) == "table") and arg.value or arg
    local hdr = (type(s) == "string") and json.toTable(s)
    bankRestoreName = (hdr and hdr.name) or ""
    return
  end

  if address == "/tb3/patchgrid/restore_slot" then
    if not bankRestoreStaging then return end  -- stray slot with no begin; ignore
    local arg = arguments and arguments[1]
    local s = (type(arg) == "table") and arg.value or arg
    if type(s) ~= "string" then return end
    local item = json.toTable(s)
    if item and item.slot and item.data then
      bankRestoreStaging[tostring(item.slot)] = item.data
    end
    return
  end

  if address == "/tb3/patchgrid/restore_end" then
    if not bankRestoreStaging then return end
    setPatchGridSlots(bankRestoreStaging)
    currentBankName    = bankRestoreName
    currentPresetName  = ""
    updatePatchInfoLabel()
    bankRestoreStaging = nil
    bankRestoreName    = ""
    return
  end

  -- /tb3/restore — update UI AND forward SysEx to the TB-3.
  if address ~= "/tb3/restore" then return end

  local arg = arguments and arguments[1]
  if arg == nil then return end
  local hexStr = (type(arg) == "table") and arg.value or arg
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

  sendMIDI(bytes, TB3_CONNECTION)

  local addr = {bytes[8], bytes[9], bytes[10], bytes[11]}
  local data = {}
  for i = 12, #bytes - 2 do data[#data + 1] = bytes[i] end

  -- Same PatchManager.parseBlock() echo guard as handleTB3SysEx (see receivingPatch
  -- declaration). The raw SysEx forward above already restores the patch;
  -- we don't also want applyValue()'s UI updates re-deriving and re-sending
  -- (potentially mismatched) values for each field on top of that.
  receivingPatch = true
  receivingPatchTimer = 5
  PatchManager.parseBlock(addr, data)
  receivingPatch = false
  receivingPatchTimer = 0

  -- Forward EFX blocks to their section nodes.
  if addr[1] == 0x10 and addr[2] == 0x00 then
    local efxSection
    if addr[3] == 0x10 then
      efxSection = root:findByName("efx1_section", true)
    elseif addr[3] == 0x12 then
      efxSection = root:findByName("efx2_section", true)
    end
    if efxSection then
      local hex = {}
      for _, b in ipairs(data) do hex[#hex+1] = string.format("%02X", b) end
      efxSection:notify("patch_data", table.concat(hex, ","))
    end
  end
end

-- ---------------------------------------------------------------------------
-- update — frame callback. Two independent countdowns:
--   syncTimer            — deferred BCR sync. Armed long (~3s) by
--                          requestPatchDump as a post-receive fallback (the
--                          awaitingBlocks countdown usually beats it), and
--                          short (~0.3s) by applyMorph as a debounce so morph
--                          sweeps don't echo NRPN 8 at a moving encoder
--   receivingPatchTimer  — receivingPatch backstop (see declaration)
-- ---------------------------------------------------------------------------

function update()
  if syncTimer > 0 then
    syncTimer = syncTimer - 1
    if syncTimer == 0 then syncBCR1(); syncLaunchkey(); tryCompletePendingStore() end
  end

  -- Backstop for receivingPatch (see declaration) — normally cleared
  -- synchronously right after PatchManager.parseBlock() returns; this only fires if
  -- PatchManager.parseBlock errored before reaching that explicit clear.
  if receivingPatchTimer > 0 then
    receivingPatchTimer = receivingPatchTimer - 1
    if receivingPatchTimer == 0 then receivingPatch = false end
  end
end

-- ---------------------------------------------------------------------------
-- init
-- ---------------------------------------------------------------------------

function init()
  -- Initialise global tuning encoder to CC 64 (0.0 st) on startup.
  local tuningGrp = root:findByName("tuning_group", true)
  local encGrp    = tuningGrp and tuningGrp.children["tuning_enc"]
  if encGrp then
    local fader = encGrp.children["control_fader"]
    if fader then fader.values.x = 64 / 127 end
    local lbl = encGrp.children["value_label"]
    if lbl then lbl.values.text = GLOBAL_TUNING_DISPLAY[64] end
  end

  -- Push current fader positions to BCR2000 #1 and Launchkey on layout load.
  syncBCR1()
  syncLaunchkey()
  updateMorphEncState()
end
