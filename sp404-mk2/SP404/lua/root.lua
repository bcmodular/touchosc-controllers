local noteMidiChannel = 10
local DELETE_BUTTON_LED = 0x32  -- LED index for delete button (50 decimal)

local PRESETS_PER_BUS = 8
local NUM_BUSES = 5

-- Keep buildPresetNoteMap in sync with preset_grid_manager.lua (Launchpad columns 1–5, preset 1 at top).
local function buildPresetNoteMap()
  local map = {}
  for bus = 1, NUM_BUSES do
    for preset = 1, PRESETS_PER_BUS do
      map[(bus - 1) * PRESETS_PER_BUS + preset] = 81 + (bus - 1) - (preset - 1) * 10
    end
  end
  return map
end

local presetNoteMap = buildPresetNoteMap()

-- Launchpad Pro: TouchOSC MIDI connection 3 — sendMIDI / receive filter flags per port
local LAUNCHPAD_MIDI_CONNECTION = { false, false, true }

-- Bus chrome (preset area, edit strip, effect chooser, perform faders). Canonical ARGB hex per bus.
local BUS_ACCENT_HEX = {
  [1] = "00E6FFFF",
  [2] = "FFD700FF",
  [3] = "FF69B4FF",
  [4] = "4A90E2FF",
  [5] = "32CD32FF",
}

local function setChromeColor(node, hexStr)
  if not node or not hexStr then return end
  node.color = hexStr
end

-- Publishes accents on root.tag.busAccentHex (string keys "1".."5") for preset_grid_manager comparisons.
local function syncBusAccentRootTag()
  local tag = json.toTable(root.tag) or {}
  tag.busAccentHex = {
    ["1"] = BUS_ACCENT_HEX[1],
    ["2"] = BUS_ACCENT_HEX[2],
    ["3"] = BUS_ACCENT_HEX[3],
    ["4"] = BUS_ACCENT_HEX[4],
    ["5"] = BUS_ACCENT_HEX[5],
  }
  root.tag = json.fromTable(tag)
end

-- Applies bus chroma so duplicated bus groups need no per-bus color edits in the layout.
function applyBusGroupTheme(busNum)
  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then return end

  local grid = busGroup:findByName("preset_grid", true)
  if not grid then return end

  local hex = BUS_ACCENT_HEX[busNum] or BUS_ACCENT_HEX[5]

  local presetBgBox = grid:findByName("preset_grid_background_box", true)
  if presetBgBox then
    setChromeColor(presetBgBox, hex)
    local ch = presetBgBox.children
    if ch then
      for i = 1, #ch do
        setChromeColor(ch[i], hex)
      end
    end
  end

  setChromeColor(busGroup:findByName("edit_group", true), hex)

  local editModeButton = busGroup:findByName("edit_mode_button", true)
  setChromeColor(editModeButton, hex)
  local editModeLabel = busGroup:findByName("edit_mode_label", true)
  if editModeLabel then
    if editModeButton and editModeButton.values.x == 1 then
      editModeLabel.textColor = Color.fromHexString("000000FF")
    else
      editModeLabel.textColor = Color.fromHexString(hex)
    end
  end

  local onOffButtonGroup = busGroup:findByName("on_off_button_group", true)
  if onOffButtonGroup then
    setChromeColor(onOffButtonGroup:findByName("choose_button", true), hex)
  end

  local effectChooser = busGroup:findByName("effect_chooser", true)
  if effectChooser then
    setChromeColor(effectChooser:findByName("background", true), hex)
  else
    local parent = busGroup.parent
    if parent then
      setChromeColor(parent:findByName("background", true), hex)
    end
  end

  local faderGroup = busGroup:findByName("faders", true)
  if faderGroup then
    for _, controlFader in ipairs(faderGroup:findAllByName("control_fader", true)) do
      setChromeColor(controlFader, hex)
    end
    for _, valueLabel in ipairs(faderGroup:findAllByName("value_label", true)) do
      valueLabel.textColor = Color.fromHexString("FFFFFFFF")
      valueLabel.color = Color.fromHexString("00000000")
    end
  end
end

function onReceiveNotify(key, value)
  if key == "apply_bus_theme" then
    local busNum = value
    if busNum then
      applyBusGroupTheme(busNum)
    end
  end
end

local function midiFromLaunchpad(connections)
  if type(connections) ~= 'table' then
    return true
  end
  return connections[3] == true
end

local function midiFromBcr(connections)
  if type(connections) ~= 'table' then
    return false
  end
  return connections[2] == true
end

-- BCR CC per fader group name "1"–"6" (must match control_mapper.lua BCR_ENCODER_CC).
local BCR_ENCODER_CC = { 81, 89, 97, 82, 90, 98 }
local BCR_CC_TO_SLOT = {}
for slot, cc in ipairs(BCR_ENCODER_CC) do
  BCR_CC_TO_SLOT[cc] = slot
end

local BCR_MIDI_DEBUG = false

local function connectionsToString(connections)
  if type(connections) ~= "table" then
    return tostring(connections)
  end
  local parts = {}
  for i = 1, #connections do
    parts[i] = connections[i] and "1" or "0"
  end
  return table.concat(parts, ",")
end

local function debugBcr(msg)
  if BCR_MIDI_DEBUG then
    print("[BCR]", msg)
  end
end

-- BCR on/off button CCs (must match on_off_button_group.lua).
local BCR_TOGGLE_CC = 65
local BCR_SYNC_CC = 66
local BCR_GRAB_CC = 73
local BCR_CHOOSE_CC = 74

local BCR_ON_OFF_CC_HANDLERS = {
  [BCR_TOGGLE_CC] = "bcr_toggle",
  [BCR_SYNC_CC] = "bcr_sync",
  [BCR_GRAB_CC] = "bcr_grab",
  [BCR_CHOOSE_CC] = "bcr_choose",
}

-- BCR top-row encoders for FX selector modal (fixed MIDI channel 6).
local FX_SELECTOR_BCR_CHANNEL = 5

local function handleBcrOnOffMidi(message)
  local status = message[1]
  local cc = message[2]
  local ccValue = message[3]
  local msgType = status - (status % 16)
  local msgChannel = status % 16

  if msgType ~= MIDIMessageType.CONTROLCHANGE then
    return false
  end

  local notifyKey = BCR_ON_OFF_CC_HANDLERS[cc]
  if not notifyKey then
    return false
  end

  local busNum = msgChannel - 4
  if busNum < 1 or busNum > NUM_BUSES then
    debugBcr(string.format("on/off skip: ch %d -> bus %d out of range", msgChannel, busNum))
    return false
  end

  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then
    return false
  end

  local onOffGroup = busGroup:findByName("on_off_button_group", true)
  if not onOffGroup then
    return false
  end

  if tonumber(onOffGroup.tag) ~= msgChannel then
    debugBcr(string.format(
      "on/off skip: bus %d tag %s != ch %d",
      busNum, tostring(onOffGroup.tag), msgChannel))
    return false
  end

  debugBcr(string.format("-> bus %d on/off %s val %d", busNum, notifyKey, ccValue))
  onOffGroup:notify(notifyKey, ccValue)
  return true
end

local function handleBcrPerformMidi(message)
  local status = message[1]
  local cc = message[2]
  local ccValue = message[3]
  local msgType = status - (status % 16)
  local msgChannel = status % 16

  if msgType ~= MIDIMessageType.CONTROLCHANGE then
    debugBcr("skip: not CC")
    return false
  end

  local slot = BCR_CC_TO_SLOT[cc]
  if not slot then
    if not BCR_ON_OFF_CC_HANDLERS[cc] then
      debugBcr("skip: cc not a perform encoder")
    end
    return false
  end

  local busNum = msgChannel - 4
  if busNum < 1 or busNum > NUM_BUSES then
    debugBcr(string.format("skip: ch %d -> bus %d out of range", msgChannel, busNum))
    return false
  end

  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then
    debugBcr("skip: bus group not found")
    return false
  end

  local controlGroup = busGroup:findByName("control_group", true)
  if not controlGroup or not controlGroup.visible then
    debugBcr(string.format("skip: bus %d control_group not visible", busNum))
    return false
  end

  local faders = busGroup:findByName("faders", true)
  if not faders then
    debugBcr("skip: faders group not found")
    return false
  end

  local faderGroup = faders:findByName(tostring(slot))
  if not faderGroup or not faderGroup.visible then
    debugBcr(string.format("skip: bus %d slot %d fader not visible", busNum, slot))
    return false
  end

  local controlFader = faderGroup:findByName("control_fader")
  if not controlFader then
    debugBcr("skip: control_fader not found")
    return false
  end

  debugBcr(string.format("-> bus %d slot %d val %d", busNum, slot, ccValue))
  controlFader:notify("set_cc_from_bcr", ccValue)
  return true
end

local function handleFxSelectorBcrMidi(message)
  local fxSelector = root:findByName('fx_selector_group', true)
  if not fxSelector or not fxSelector.visible then
    return
  end

  local status = message[1]
  local cc = message[2]
  local ccValue = message[3]
  local msgType = status - (status % 16)
  local msgChannel = status % 16

  if msgType ~= MIDIMessageType.CONTROLCHANGE or msgChannel ~= FX_SELECTOR_BCR_CHANNEL then
    return
  end

  local selectorButtons = fxSelector:findByName('fx_selector_button_group')
  if not selectorButtons then
    return
  end

  if cc >= 1 and cc <= 8 then
    selectorButtons:notify('midi_column_tick', { col = cc, ccValue = ccValue })
  elseif cc >= 9 and cc <= 16 and ccValue == 0 then
    selectorButtons:notify('midi_column_confirm', { col = cc - 8 })
  end
end

local function sendSysexLEDUpdate(ledIndex, color)
  -- SysEx format: F0h 00h 20h 29h 02h 10h 0Ah <LED> <Colour> F7h
  -- Decimal: (240,0,32,41,2,16,10,<LED>,<Colour>,247)
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0A, ledIndex, color, 0xF7 }
  print('sendSysexLEDUpdate', ledIndex, color, sysexMessage)
  sendMIDI(sysexMessage, LAUNCHPAD_MIDI_CONNECTION)
end

local function setLaunchpadLayout(layout)
  -- SysEx format: F0h 00h 20h 29h 02h 10h 2Ch <Layout> F7h
  -- Decimal: (240,0,32,41,2,16,44,<Layout>,247)
  -- Layout: 00h=Note, 01h=Drum, 02h=Fader, 03h=Programmer
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x2C, layout, 0xF7 }
  print('setLaunchpadLayout', layout)
  sendMIDI(sysexMessage, LAUNCHPAD_MIDI_CONNECTION)
end

function onReceiveMIDI(message, connections)
  -- Filter out SysEx messages to avoid processing our own messages
  if message[1] == MIDIMessageType.SYSTEMEXCLUSIVE + 1 then
    return
  end

  if midiFromBcr(connections) then
    debugBcr(string.format(
      "onReceiveMIDI status=%d cc=%d val=%d connections=%s",
      message[1], message[2], message[3], connectionsToString(connections)))
    if handleBcrOnOffMidi(message) then
      return
    end
    if handleBcrPerformMidi(message) then
      return
    end
    handleFxSelectorBcrMidi(message)
    return
  end

  if not midiFromLaunchpad(connections) then
    return
  end

  if message[1] == MIDIMessageType.NOTE_ON + noteMidiChannel - 1 then
    local note = message[2]
    local velocity = message[3]

    local noteIndex = nil
    for i = 1, #presetNoteMap do
      if presetNoteMap[i] == note then
        noteIndex = i
        break
      end
    end

    if noteIndex == nil then
      return
    end

    print('onReceiveMIDI', note, velocity, noteIndex)

    local presetIndex = noteIndex - 1
    local busIndex = math.floor(presetIndex / PRESETS_PER_BUS)
    local presetNumber = (presetIndex % PRESETS_PER_BUS) + 1
    print('onReceiveMIDI', busIndex, presetNumber)

    local presetGridEntry = root:findByName('bus'..tostring(busIndex + 1)..'_group', true):findByName('preset_grid', true).children[tostring(presetNumber)]

    if velocity > 0 then
      presetGridEntry.values.x = 1
    else
      presetGridEntry.values.x = 0
    end
  elseif message[1] == MIDIMessageType.CONTROLCHANGE + noteMidiChannel - 1 then
    local cc = message[2]
    if cc == 50 then
      local deleteMode = message[3] == 127
      root:findByName('delete_button', true).values.x = deleteMode and 1 or 0
      -- Update delete button LED using SysEx (color 5 for active, 7 for inactive)
      local deleteButtonColor = deleteMode and 5 or 7
      sendSysexLEDUpdate(DELETE_BUTTON_LED, deleteButtonColor)
    end
  end
end

-- Defer one frame so layout init() handlers on bus groups are ready before startup MIDI sync.
local pendingStartupMidiSync = true

function update()
  if not pendingStartupMidiSync then
    return
  end
  pendingStartupMidiSync = false
  for busNum = 1, 5 do
    local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
    if busGroup then
      local onOff = busGroup:findByName("on_off_button_group", true)
      if onOff then
        onOff:notify("sync_current_bus")
      end
    end
  end
  print("startup: sync_all_buses_midi")
end

function init()
  syncBusAccentRootTag()
  for busNum = 1, 5 do
    applyBusGroupTheme(busNum)
  end

  setLaunchpadLayout(0x03)
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0E, 0x00, 0xF7 }
  print('sendSysexAllPadsOff')
  sendMIDI(sysexMessage, LAUNCHPAD_MIDI_CONNECTION)
  sendSysexLEDUpdate(DELETE_BUTTON_LED, 7)
end
