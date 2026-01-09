local noteMidiChannel = 10
local DELETE_BUTTON_LED = 0x32  -- LED index for delete button (50 decimal)

local function sendSysexLEDUpdate(ledIndex, color)
  -- SysEx format: F0h 00h 20h 29h 02h 10h 0Ah <LED> <Colour> F7h
  -- Decimal: (240,0,32,41,2,16,10,<LED>,<Colour>,247)
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0A, ledIndex, color, 0xF7 }
  print('sendSysexLEDUpdate', ledIndex, color, sysexMessage)
  sendMIDI(sysexMessage)
end

local function setLaunchpadLayout(layout)
  -- SysEx format: F0h 00h 20h 29h 02h 10h 2Ch <Layout> F7h
  -- Decimal: (240,0,32,41,2,16,44,<Layout>,247)
  -- Layout: 00h=Note, 01h=Drum, 02h=Fader, 03h=Programmer
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x2C, layout, 0xF7 }
  print('setLaunchpadLayout', layout)
  sendMIDI(sysexMessage)
end

function onReceiveMIDI(message, connections)
  -- Filter out SysEx messages to avoid processing our own messages
  if message[1] == MIDIMessageType.SYSTEMEXCLUSIVE + 1 then
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
  setLaunchpadLayout(0x03)
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0E, 0x00, 0xF7 }
  print('sendSysexAllPadsOff')
  sendMIDI(sysexMessage)
  sendSysexLEDUpdate(DELETE_BUTTON_LED, 7)
end
