function onReceiveMIDI(message, connections)

  local presetNoteMap = {
    81, 82, 71, 72, 61, 62, 51, 52, 41, 42, 31, 32, 21, 22, 11, 12,
    83, 84, 73, 74, 63, 64, 53, 54, 43, 44, 33, 34, 23, 24, 13, 14,
    85, 86, 75, 76, 65, 66, 55, 56, 45, 46, 35, 36, 25, 26, 15, 16,
    87, 88, 77, 78, 67, 68, 57, 58, 47, 48, 37, 38, 27, 28, 17, 18
  }

  if message[1] == MIDIMessageType.NOTE_ON + 1 then
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
  elseif message[1] == MIDIMessageType.CONTROLCHANGE + 1 then
    local cc = message[2]
    if cc == 50 then
      local deleteMode = message[3] == 127
      root:findByName('delete_button', true).values.x = deleteMode and 1 or 0
      sendMIDI({ MIDIMessageType.CONTROLCHANGE + 1, 50, deleteMode and 5 or 7 }, {false, true})
    end
  end
end

function init()
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + 1, 50, 7 }, {false, true})
end
