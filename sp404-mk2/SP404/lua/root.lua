local noteMidiChannel = 10
local DELETE_BUTTON_LED = 0x32  -- LED index for delete button (50 decimal)

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

  local effectChooser = busGroup:findByName("effect_chooser", true)
  if effectChooser then
    setChromeColor(effectChooser:findByName("selected_item_button", true), hex)
    setChromeColor(effectChooser:findByName("background", true), hex)
  else
    local parent = busGroup.parent
    if parent then
      setChromeColor(parent:findByName("selected_item_button", true), hex)
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

  if not midiFromLaunchpad(connections) then
    return
  end

  local presetNoteMap = {
    81, 82, 71, 72, 61, 62, 51, 52, 41, 42, 31, 32, 21, 22, 11, 12,
    83, 84, 73, 74, 63, 64, 53, 54, 43, 44, 33, 34, 23, 24, 13, 14,
    85, 86, 75, 76, 65, 66, 55, 56, 45, 46, 35, 36, 25, 26, 15, 16,
    87, 88, 77, 78, 67, 68, 57, 58, 47, 48, 37, 38, 27, 28, 17, 18
  }

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
    local busIndex = math.floor(presetIndex / 16)
    local presetNumber = (presetIndex % 16) + 1
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
