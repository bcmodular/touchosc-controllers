local conn = { false, true, false } -- only send midi messages to connection 2, which we designate as the Push
local presetStates = {
  [1] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false},
  [2] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false},
  [3] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false},
  [4] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false},
  [5] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false}
}
local busToControl = nil
local busGroups = {}
local presetManager = root.children.preset_manager
local toggleButtonCCs = {20, 22, 24, 26}
local controlButtonCCs = {103, 105, 107, 109}
local grabCCs = {102, 104, 106, 108}
local controlCCs = {103, 105, 107, 109}
local syncCCs = {21, 23, 25, 27}

-- Push LED colors
local pushColors = {
  off = 0,      -- black / off
  darkGrey = 1, -- dark grey
  grey = 2,     -- grey
  white = 3,    -- white

  red = {
    bright = 5,
    normal = 6,
    dim = 7
  },

  orange = {
    bright = 9,
    normal = 10,
    dim = 11
  },

  yellow = {
    bright = 13,
    normal = 14,
    dim = 15
  },

  green = {
    bright = 21,
    normal = 22,
    dim = 23
  },

  cyan = {
    bright = 33,
    normal = 34,
    dim = 35
  },

  blue = {
    bright = 45,
    normal = 46,
    dim = 47
  },

  purple = {
    bright = 49,
    normal = 50,
    dim = 51
  },

  pink = {
    bright = 57,
    normal = 58,
    dim = 59
  }
}

-- Push LED colors for the first row of buttons
local pushFirstRowCCColors = {
  off = 0,

  red = {
    dim = 1,
    dim_flashing = 2,
    dim_fast_flashing = 3,
    bright = 4,
    bright_flashing = 5,
    bright_fast_flashing = 6
  },

  orange = {
    dim = 7,
    dim_flashing = 8,
    dim_fast_flashing = 9,
    bright = 10,
    bright_flashing = 11,
    bright_fast_flashing = 12
  },

  yellow = {
    dim = 13,
    dim_flashing = 14,
    dim_fast_flashing = 15,
    bright = 16,
    bright_flashing = 17,
    bright_fast_flashing = 18
  },

  green = {
    dim = 19,
    dim_flashing = 20,
    dim_fast_flashing = 21,
    bright = 22,
    bright_flashing = 23,
    bright_fast_flashing = 24
  }
}

-- Push LED colors for the second row of buttons
local pushSecondRowCCColors = {
  off = 0,

  white = {
    dim = 1,
    normal = 2,
    bright = 3,
    pink = 4
  },

  red = {
    bright = 5,
    normal = 6,
    dim = 7,
    white = 8
  },

  orange = {
    bright = 9,
    normal = 10,
    dim = 11,
    white = 12
  },

  yellow = {
    bright = 13,
    normal = 14,
    dim = 15,
    white = 16
  },

  lime_green = {
    bright = 17,
    normal = 18,
    dim = 19,
    white = 20
  },

  green = {
    bright = 21,
    normal = 22,
    dim = 23,
    white = 24
  },

  light_green = {
    bright = 25,
    normal = 26,
    dim = 27,
    white = 28
  },

  blue_green = {
    bright = 29,
    normal = 30,
    dim = 31,
    white = 32
  },

  cyan = {
    bright = 33,
    normal = 34,
    dim = 35,
    white = 36
  },

  baby_blue = {
    bright = 37,
    normal = 38,
    dim = 39,
    white = 40
  },

  light_blue = {
    bright = 41,
    normal = 42,
    dim = 43,
    white = 44
  },

  blue = {
    bright = 45,
    normal = 46,
    dim = 47,
    white = 48
  },

  magenta = {
    bright = 49,
    normal = 50,
    dim = 51,
    white = 52
  },

  purple = {
    bright = 53,
    normal = 54,
    dim = 55,
    white = 56
  },

  bright_purple = {
    bright = 57,
    normal = 58,
    dim = 59
  },

  orange_red = {
    bright = 60,
    normal = 61,
    dim = 62,
    white = 63
  }
}

local deletePresetVelocity = pushColors.red.normal
local pressedDeletePresetVelocity = pushColors.red.bright
local deleteMode = false

local function initialiseBusGroups()
  for busNum = 1, 4 do
    print('init', busNum)
    local busGroupName = 'bus'..tostring(busNum)..'_group'
    local busGroup = root:findByName(busGroupName, true)
    print('busGroup', busGroup.name)
    busGroups[busNum] = busGroup
  end
end

local function getPresetVelocity(pressed, busNum)
  local colorBase = pushColors.green
  if busNum == 1 then
    colorBase = pushColors.cyan
  elseif busNum == 2 then
    colorBase = pushColors.yellow
  elseif busNum == 3 then
    colorBase = pushColors.pink
  elseif busNum == 4 then
    colorBase = pushColors.blue
  end
  if pressed then
    return colorBase.bright
  else
    return colorBase.normal
  end
end
local function mapNoteToPreset(note)
  --print('mapNoteToPreset', note)
  -- Map from Push 8x8 grid (notes 36-99) to four 4x4 preset grids
  -- Each 4x4 grid maps to a bus number (1-4) and preset number (1-16)

  -- Calculate which quadrant of the 8x8 grid we're in
  local quadX = math.floor((note - 36) % 8 / 4)  -- 0 or 1 (left/right)
  local quadY = 1 - math.floor((note - 36) / 32) -- 1 (top), 0 (bottom)
  local quadrantToBus = {
    [0] = { [0] = 1, [1] = 2 },  -- Top row: left=1, right=2
    [1] = { [0] = 3, [1] = 4 }   -- Bottom row: left=3, right=4
  }
  local busNum = quadrantToBus[quadY][quadX]

  -- Calculate relative position within quadrant
  local relX = (note - 36) % 4
  local relY = 3 - math.floor((note - 36) % 32 / 8)  -- 0 (top) to 3 (bottom)
  local presetNum = relX + (relY * 4) + 1            -- 1-16, top-left to bottom-right
  --print('quadX', quadX, 'quadY', quadY, 'relX', relX, 'relY', relY, 'busNum', busNum, 'presetNum', presetNum)
  return {busNum, presetNum}
end

local function mapPresetToNote(busNum, presetNum)
  -- Convert bus number to quadrant position
  local busToQuadrant = {
    [1] = { quadY = 0, quadX = 0 }, -- top-left
    [2] = { quadY = 0, quadX = 1 }, -- top-right
    [3] = { quadY = 1, quadX = 0 }, -- bottom-left
    [4] = { quadY = 1, quadX = 1 }, -- bottom-right
  }

  local quadY = busToQuadrant[busNum].quadY
  local quadX = busToQuadrant[busNum].quadX

  -- Calculate relative position within quadrant
  local relX = (presetNum - 1) % 4
  local relY = math.floor((presetNum - 1) / 4)

  -- Calculate note number (92 is top-left note)
  return 92 - (quadY * 32) + (quadX * 4) - (relY * 8) + relX
end

local function toggleEffect(busNum, ccValue)
  local busGroup = busGroups[busNum]
  local onOffButtonGroup = busGroup:findByName('on_off_button_group', true)

  local toggleButton = onOffButtonGroup:findByName('toggle_button', true)
  local currentState = toggleButton.values.x

  if ccValue == 0 then
    -- Button release - perform the actual toggle
    local newState = currentState == 1 and 0 or 1

    -- Set the new state (this will trigger the TouchOSC button to update)
    onOffButtonGroup:notify('set_state', newState == 1)

    -- Update Push button lighting immediately
    local toggleCCNum = toggleButtonCCs[busNum]

    if newState == 1 then
      -- Effect turned on - bright green
      local brightGreenValue = pushFirstRowCCColors.green.bright
      sendMIDI({ 176, toggleCCNum, brightGreenValue }, conn)
    else
      -- Effect turned off - dim green
      local dimGreenValue = pushFirstRowCCColors.green.dim
      sendMIDI({ 176, toggleCCNum, dimGreenValue }, conn)
    end
  end
end

local function grabEffect(busNum, ccValue)
  local busGroup = busGroups[busNum]
  local grabButton = busGroup:findByName('grab_button', true)
  local onOffButtonGroup = busGroup:findByName('on_off_button_group', true)
  local toggleButton = onOffButtonGroup:findByName('toggle_button', true)

  local grabCCNum = grabCCs[busNum]
  local toggleCCNum = toggleButtonCCs[busNum]

  if ccValue == 127 then
    -- Button press - bright blue and turn effect on
    sendMIDI({ 176, grabCCNum, pushSecondRowCCColors.blue.bright }, conn)
    grabButton.values.x = 1
    toggleButton.values.x = 1

    -- Effect turned on - bright green
    local brightGreenValue = pushFirstRowCCColors.green.bright
    sendMIDI({ 176, toggleCCNum, brightGreenValue }, conn)
  elseif ccValue == 0 then
    -- Button release - dim blue and turn effect off
    sendMIDI({ 176, grabCCNum, pushSecondRowCCColors.blue.dim }, conn)
    grabButton.values.x = 0
    toggleButton.values.x = 0

    -- Effect turned off - dim green
    local dimGreenValue = pushFirstRowCCColors.green.dim
    sendMIDI({ 176, toggleCCNum, dimGreenValue }, conn)
  end
end

local function triggerSyncButton(busNum, ccValue)
  local busGroup = busGroups[busNum]

  -- Find the sync button directly
  local syncButton = busGroup:findByName('sync_button', true)

  -- Get the sync button CC number for this bus
  local syncCCNum = syncCCs[busNum]

  if ccValue == 127 then
    -- Button press - bright orange and set button to pressed state
    sendMIDI({ 176, syncCCNum, pushFirstRowCCColors.orange.bright }, conn)
    syncButton.values.x = 1
  elseif ccValue == 0 then
    -- Button release - dim orange and set button to released state
    sendMIDI({ 176, syncCCNum, pushFirstRowCCColors.orange.dim }, conn)
    syncButton.values.x = 0
  end
end

local function handleKnobTouch(knobIndex, isTouched)
  -- knobIndex is 0-5 (6 knobs total)
  -- isTouched is true for NOTE_ON, false for NOTE_OFF
  if busToControl then
    local faders = busToControl:findByName('faders', true)
    -- Find the fader corresponding to this knob (knob 0 = fader 1, etc.)
    local faderIndex = knobIndex + 1
    local faderGroup = faders:findByName(tostring(faderIndex))
    local controlFader = faderGroup:findByName('control_fader')
    controlFader:notify('touched', isTouched)
  end
end

local function toggleDeleteMode(newDeleteMode)
  deleteMode = newDeleteMode
  root:findByName('delete_button', true).values.x = deleteMode and 1 or 0
  sendMIDI({ 176, 118, deleteMode and 127 or 1 }, conn)
end

local function sendIncrementToFader(ccNum, ccValue)
  --print('sending increment to fader for bus:', busToControl)
  if busToControl then
    local faders = busToControl:findByName('faders', true)
    local faderNum = tostring(ccNum - 70)
    local fader = faders.children[faderNum]:findByName('control_fader')

    local midiDelta = 0
    if ccValue > 64 then
      midiDelta = ccValue - 128  -- Negative steps
    elseif ccValue < 64 then
      midiDelta = ccValue        -- Positive steps
    end

    local delta = midiDelta / 127
    local currentValue = fader.values.x
    local newValue = currentValue + delta
    fader.values.x = newValue
  end
end

local function syncPushOnOffGroupLighting(busNum)
  initialiseBusGroups()
  local busGroup = busGroups[busNum]
  print('busNum', busNum)
  print('syncPushOnOffGroupLighting', busGroup.name)
  local onOffButtonGroup = busGroup:findByName('on_off_button_group', true)

  -- Toggle button (effect on/off)
  local effectState = onOffButtonGroup:findByName('toggle_button', true).values.x
  if effectState == 1 then
    sendMIDI({ 176, toggleButtonCCs[busNum], pushFirstRowCCColors.green.bright }, conn)
  else
    sendMIDI({ 176, toggleButtonCCs[busNum], pushFirstRowCCColors.green.dim }, conn)
  end

  -- Sync button (sync all control faders to SP404 Mk2)
  sendMIDI({ 176, syncCCs[busNum], pushFirstRowCCColors.orange.dim }, conn)

  -- Control bus button (Ableton Push controls the effect)
  local controlState = onOffButtonGroup:findByName('control_bus_button', true).values.x
  if controlState == 1 then
    sendMIDI({ 176, controlButtonCCs[busNum], pushSecondRowCCColors.yellow.bright }, conn)
  else
    sendMIDI({ 176, controlButtonCCs[busNum], pushSecondRowCCColors.yellow.dim }, conn)
  end

  -- Grab button (momentarily enables the effect)
  sendMIDI({ 176, grabCCs[busNum], pushSecondRowCCColors.blue.dim }, conn)
end

local function controlEffect(busNum)
  busToControl = busGroups[busNum]
  syncPushOnOffGroupLighting(busNum)
end

local function mapCCToFeature(ccNum, ccValue)
  -- Toggle button: 20, 22, 24, 26 are the cc numbers to toggle each of the four effect buses
  if ccNum == 20 or ccNum == 22 or ccNum == 24 or ccNum == 26 then
    local ccToBus = {
      [20] = 1,
      [22] = 2,
      [24] = 3,
      [26] = 4
    }
    local busNum = ccToBus[ccNum]
    toggleEffect(busNum, ccValue)
  -- Grab button: 102, 104, 106, 108 are the cc numbers to grab each of the four effect buses
  elseif ccNum == 102 or ccNum == 104 or ccNum == 106 or ccNum == 108 then
    local ccToBus = {
      [102] = 1,
      [104] = 2,
      [106] = 3,
      [108] = 4
    }
    local busNum = ccToBus[ccNum]
    grabEffect(busNum, ccValue)
  -- Control button: 103, 105, 107, 109 are the cc numbers to control each of the four effect buses
  elseif ccNum == 103 or ccNum == 105 or ccNum == 107 or ccNum == 109 then
    local ccToBus = {
      [103] = 1,
      [105] = 2,
      [107] = 3,
      [109] = 4
    }
    local busNum = ccToBus[ccNum]
    controlEffect(busNum)
  -- Sync button: 21, 23, 25, 27 are the cc numbers to sync each of the four effect buses
  elseif ccNum == 21 or ccNum == 23 or ccNum == 25 or ccNum == 27 then
    local ccToBus = {
      [21] = 1,
      [23] = 2,
      [25] = 3,
      [27] = 4
    }
    local busNum = ccToBus[ccNum]
    triggerSyncButton(busNum, ccValue)
  elseif ccNum >= 71 and ccNum <= 76 then
    sendIncrementToFader(ccNum, ccValue)
  elseif ccNum == 118 then
    toggleDeleteMode(ccValue == 127)
  end
end

local function illuminatePreset(busNum, presetNum, state, velocity)
  local noteNum = mapPresetToNote(busNum, presetNum)

  if state then
    sendMIDI({ 144, noteNum, velocity }, conn)
  else
    sendMIDI({ 128, noteNum, velocity }, conn)
  end
end

local function refreshPresets(busNum)
  print('refreshPresets', busNum)
  initialiseBusGroups()
  local fxNum = busGroups[busNum].tag.fxNum or 0
  presetStates[busNum] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false}

  if fxNum ~= 0 then
    local presetManagerChild = presetManager.children[tostring(fxNum)]
    local presetArray = json.toTable(presetManagerChild.tag) or {}

    for index, _ in pairs(presetArray) do
      local presetNum = tonumber(index)

      if presetNum ~= nil then
        presetStates[busNum][presetNum] = true
      end
    end
  end

  for presetNum = 1, 16 do
    if deleteMode then
      illuminatePreset(busNum, presetNum, presetStates[busNum][presetNum], deletePresetVelocity)
    else
      illuminatePreset(busNum, presetNum, presetStates[busNum][presetNum], getPresetVelocity(false, busNum))
    end
  end
end

local function resetPush()
  -- Send Note Offs (Note On with velocity 0) for all MIDI notes 0–127
  for note = 0, 127 do
    -- 0x90 = 144 = Note On, channel 1
    sendMIDI({ 144, note, 0 }, conn)
  end

  -- Send Control Change 0 to all CCs 0–127
  for cc = 0, 127 do
    -- 0xB0 = 176 = CC, channel 1
    sendMIDI({ 176, cc, 0 }, conn)
  end
end

local function initialiseFeatureButtons()
  sendMIDI({ 176, 118, 1}, conn)
end

local function initialisePushLighting()
  resetPush()
  for busNum = 1, 4 do
    refreshPresets(busNum)
    syncPushOnOffGroupLighting(busNum)
  end
  initialiseFeatureButtons()
end

local function handleMIDIMessage(midiMessage)
  -- Handle NOTE ON/OFF messages
  if midiMessage[1] == 144 or midiMessage[1] == 128 then
    local midiNote = midiMessage[2]

    -- Handle knob touch messages (notes 0-5)
    if midiNote >= 0 and midiNote <= 5 then
      local isTouched = (midiMessage[1] == 144 and midiMessage[3] > 0) -- NOTE_ON with velocity > 0 = touched, NOTE_ON with velocity 0 or NOTE_OFF = released
      handleKnobTouch(midiNote, isTouched)
    -- Handle preset grid messages (notes 36-99)
    elseif midiNote >= 36 and midiNote <= 99 then
      local busNum, presetNum = unpack(mapNoteToPreset(midiNote))

      if deleteMode and not presetStates[busNum][presetNum] then
        return
      end

      local busGroup = busGroups[busNum]
      local presetGrid = busGroup:findByName('preset_grid', true)

      if midiMessage[1] == 144 then
        presetGrid.children[tostring(presetNum)].values.x = 1
        if deleteMode then
          illuminatePreset(busNum, presetNum, true, pressedDeletePresetVelocity)
        else
          illuminatePreset(busNum, presetNum, true, getPresetVelocity(true, busNum))
        end
      else
        presetGrid.children[tostring(presetNum)].values.x = 0
      end
    end
  -- Handle CC messages
  elseif midiMessage[1] == 176 then -- MIDI CC message
    local ccNum = midiMessage[2]
    local ccValue = midiMessage[3]
    mapCCToFeature(ccNum, ccValue)
  end
end

function onReceiveNotify(key, value)
  if key == 'midi_message' then
    handleMIDIMessage(value)
  elseif key == 'toggle_delete_mode' then
    toggleDeleteMode(value)
  elseif key == 'set_controlled_bus' then
    controlEffect(value)
  elseif key == 'sync_push_lighting' then
    refreshPresets(value)
    syncPushOnOffGroupLighting(value)
  end
end

function init()
  initialiseBusGroups()
  initialisePushLighting()
end