local conn = { false, true, false } -- only send midi messages to connection 2, which we designate as the Push
local presetStates = {
  [1] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false},
  [2] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false},
  [3] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false},
  [4] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false},
  [5] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false}
}
local busToControl = 1
local fxNums = {1, 1, 1, 1, 1}
local controlBusStates = {false, false, false, false, false} -- Track which bus is being controlled
local touchedKnobs = {false, false, false, false, false, false} -- Track which knobs are currently touched (0-5)
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

local inactivePresetVelocity = pushColors.off
local deletePresetVelocity = pushColors.red.normal
local pressedDeletePresetVelocity = pushColors.red.bright
local deleteMode = false

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

  -- Bus 5 doesn't have a physical location on the 64-button grid
  if busNum == 5 then
    return nil
  end

  local quadY = busToQuadrant[busNum].quadY
  local quadX = busToQuadrant[busNum].quadX

  -- Calculate relative position within quadrant
  local relX = (presetNum - 1) % 4
  local relY = math.floor((presetNum - 1) / 4)

  -- Calculate note number (92 is top-left note)
  return 92 - (quadY * 32) + (quadX * 4) - (relY * 8) + relX
end

local function illuminatePreset(busNum, presetNum, state, velocity)
  -- To illuminate a button, we need to send a MIDI note on message to the Push with the correct note number
  --print('illuminating preset:', busNum, presetNum, state)
  local noteNum = mapPresetToNote(busNum, presetNum)
  --print('noteNum', noteNum)

  -- Skip illumination if no note number (e.g., Bus 5)
  if noteNum == nil then
    return
  end

  if state then
    sendMIDI({ 144, noteNum, velocity }, conn)
  else
    sendMIDI({ 128, noteNum, velocity }, conn)
  end
end

local function illuminatePresetGrids()
  for i = 1, 5 do
    --print('illuminating preset grid', i)
    for j = 1, 16 do
      if presetStates[i][j] then
        if deleteMode then
          illuminatePreset(i, j, true, deletePresetVelocity)
        else
          illuminatePreset(i, j, true, getPresetVelocity(false, i))
        end
      else
        illuminatePreset(i, j, false, inactivePresetVelocity)
      end
    end
  end
end


local function toggleEffect(busNum, ccValue)
  local busGroupName = 'bus'..tostring(busNum)..'_group'
  local performBusGroup = root:findByName(busGroupName, true)
  local onOffButtonGroup = performBusGroup:findByName('on_off_button_group', true)
  if onOffButtonGroup then
    local toggleButton = onOffButtonGroup:findByName('toggle_button', true)
    local currentState = toggleButton and toggleButton.values.x or 0

    if ccValue == 0 then
      -- Button release - perform the actual toggle
      local newState = currentState == 1 and 0 or 1

      -- Set the new state (this will trigger the TouchOSC button to update)
      onOffButtonGroup:notify('set_state', newState == 1)

      -- Update Push button lighting immediately
      local toggleButtonCCs = {20, 22, 24, 26}
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
end

local function grabEffect(busNum, ccValue)
  --print('grabbing effect for bus:', busNum)
  local busGroupName = 'bus'..tostring(busNum)..'_group'
  local performBusGroup = root:findByName(busGroupName, true)
  local grabButton = performBusGroup:findByName('grab_button', true)
  local onOffButtonGroup = performBusGroup:findByName('on_off_button_group', true)
  local toggleButton = onOffButtonGroup and onOffButtonGroup:findByName('toggle_button', true)

  -- Get the grab button CC number for this bus
  local grabButtonCCs = {102, 104, 106, 108}
  local grabCCNum = grabButtonCCs[busNum]

  if grabButton then
        if ccValue == 127 then
      -- Button press - bright blue and turn effect on
      sendMIDI({ 176, grabCCNum, pushSecondRowCCColors.blue.bright }, conn)
      grabButton.values.x = 1

      -- Turn effect on
      if toggleButton then
        toggleButton.values.x = 1

        -- Update Push toggle button lighting
        local toggleButtonCCs = {20, 22, 24, 26}
        local toggleCCNum = toggleButtonCCs[busNum]

        -- Effect turned on - bright green
        local brightGreenValue = pushFirstRowCCColors.green.bright
        sendMIDI({ 176, toggleCCNum, brightGreenValue }, conn)
      end
    elseif ccValue == 0 then
      -- Button release - dim blue and turn effect off
      sendMIDI({ 176, grabCCNum, pushSecondRowCCColors.blue.dim }, conn)
      grabButton.values.x = 0

      -- Turn effect off
      if toggleButton then
        toggleButton.values.x = 0

        -- Update Push toggle button lighting
        local toggleButtonCCs = {20, 22, 24, 26}
        local toggleCCNum = toggleButtonCCs[busNum]

        -- Effect turned off - dim green
        local dimGreenValue = pushFirstRowCCColors.green.dim
        sendMIDI({ 176, toggleCCNum, dimGreenValue }, conn)
      end
    end
  end
end

local function triggerSyncButton(busNum, ccValue)
  local busGroupName = 'bus'..tostring(busNum)..'_group'
  local performBusGroup = root:findByName(busGroupName, true)

  -- Find the sync button directly
  local syncButton = performBusGroup:findByName('sync_button', true)

  -- Get the sync button CC number for this bus
  local syncButtonCCs = {21, 23, 25, 27}
  local syncCCNum = syncButtonCCs[busNum]

  if syncButton then
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
end

local function handleKnobTouch(knobIndex, isTouched)
  -- knobIndex is 0-5 (6 knobs total)
  -- isTouched is true for NOTE_ON, false for NOTE_OFF

  touchedKnobs[knobIndex + 1] = isTouched -- Convert to 1-based index

  -- Get the current controlled bus
  local controlledBus = busToControl

  -- Find the fader group for this bus
  local busGroupName = 'bus'..tostring(controlledBus)..'_group'
  local performBusGroup = root:findByName(busGroupName, true)
  if performBusGroup then
    local faders = performBusGroup:findByName('faders', true)
    if faders then
      -- Find the fader corresponding to this knob (knob 0 = fader 1, etc.)
      local faderIndex = knobIndex + 1
      local faderGroup = faders:findByName(tostring(faderIndex))
      if faderGroup then
        local controlFader = faderGroup:findByName('control_fader')
        if controlFader then
          -- Directly change the fader color
          if isTouched then
            -- Knob touched - change to darker orange
            controlFader.properties.color = 'FF6600FF' -- Even darker orange
          else
            -- Knob released - restore normal color
            controlFader.properties.color = 'FFA61AFF' -- Normal orange
          end
        end
      end
    end
  end
end

local function updateControlButtonLighting()
  -- Update lighting for all control buttons based on their states
  local controlCCs = {103, 105, 107, 109}
  for busNum = 1, 4 do
    local ccNum = controlCCs[busNum]
    if controlBusStates[busNum] then
      -- This bus is being controlled - bright yellow
      sendMIDI({ 176, ccNum, pushSecondRowCCColors.yellow.bright }, conn)
    else
      -- This bus is not being controlled - dim yellow
      sendMIDI({ 176, ccNum, pushSecondRowCCColors.yellow.dim }, conn)
    end
  end
end

local function updateBusVisualIndicators(newBusToControl)
  -- Reset all bus highlights first
  for busNum = 1, 5 do
    local busGroupName = 'bus'..tostring(busNum)..'_group'
    local performBusGroup = root:findByName(busGroupName, true)
    if performBusGroup then
      local effectChooser = performBusGroup:findByName('effect_chooser', true)
      if effectChooser then
        effectChooser:notify('reset_bus_highlight')
      end
    end
  end

  -- Update control bus states based on newBusToControl
  for i = 1, 5 do
    controlBusStates[i] = (i == newBusToControl)
  end

  -- Update control button lighting
  updateControlButtonLighting()

  -- Highlight the newly selected bus (if any)
  if newBusToControl >= 1 and newBusToControl <= 5 then
    local busGroupName = 'bus'..tostring(newBusToControl)..'_group'
    local performBusGroup = root:findByName(busGroupName, true)
    if performBusGroup then
      local effectChooser = performBusGroup:findByName('effect_chooser', true)
      if effectChooser then
        effectChooser:notify('set_bus_highlight', true)
      end
    end
  end
  -- If newBusToControl is 0, all highlighting is turned off (no additional action needed)
end

local function controlEffect(busNum)
  --print('controlling effect for bus:', busNum)
  local oldBusToControl = busToControl
  busToControl = busNum

  -- Update control bus states
  for i = 1, 5 do
    controlBusStates[i] = (i == busNum)
  end

  -- Update TouchOSC control bus buttons to maintain radio button behavior
  for i = 1, 5 do
    local busGroupName = 'bus'..tostring(i)..'_group'
    local performBusGroup = root:findByName(busGroupName, true)
    if performBusGroup then
      local onOffButtonGroup = performBusGroup:findByName('on_off_button_group', true)
      if onOffButtonGroup then
        local controlBusButton = onOffButtonGroup:findByName('control_bus_button')
        if controlBusButton then
          controlBusButton.values.x = (i == busNum) and 1 or 0
        end
      end
    end
  end

  -- Update control button lighting
  updateControlButtonLighting()

  -- Always update visual indicators when controlEffect is called
  updateBusVisualIndicators(busToControl)
end

local function toggleDeleteMode(newDeleteMode)
  deleteMode = newDeleteMode
  root:findByName('delete_button', true).values.x = deleteMode and 1 or 0
  illuminatePresetGrids()
  sendMIDI({ 176, 118, deleteMode and 127 or 1 }, conn)
end

local function sendIncrementToFader(ccNum, ccValue)
  --print('sending increment to fader for bus:', busToControl)
  local busGroupName = 'bus'..tostring(busToControl)..'_group'
  local performBusGroup = root:findByName(busGroupName, true)
  local faders = performBusGroup:findByName('faders', true)
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

local function handlePresetIllumination(busNum)
  local presetManager = root.children.preset_manager
  local presetManagerChild = presetManager.children[tostring(fxNums[busNum])]
  local presetArray = json.toTable(presetManagerChild.tag) or {}
  --print('presetArray', unpack(presetArray))

  presetStates[busNum] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false}

  -- Initialise the entries first
  for index = 1, 16 do
    illuminatePreset(busNum, index, false, 0)
  end

  for index, _ in pairs(presetArray) do
    local presetNum = tonumber(index)
    --print('Setting state for:', presetNum, 'to:', true)
    if presetNum ~= nil then
      presetStates[busNum][presetNum] = true
      if deleteMode then
        illuminatePreset(busNum, presetNum, true, deletePresetVelocity)
      else
        illuminatePreset(busNum, presetNum, true, getPresetVelocity(false, busNum))
      end
    end
  end
end

function onReceiveNotify(key, value)

  if key == 'midi_message' then

    local midiMessage = value
    --print('onReceiveNotify', key, unpack(midiMessage))

    if midiMessage[1] == 144 or midiMessage[1] == 128 then
      --print('MIDI message is NOTE ON/OFF:', midiMessage[2])
      local midiNote = midiMessage[2]

      -- Handle knob touch messages (notes 0-5)
      if midiNote >= 0 and midiNote <= 5 then
        local isTouched = (midiMessage[1] == 144 and midiMessage[3] > 0) -- NOTE_ON with velocity > 0 = touched, NOTE_ON with velocity 0 or NOTE_OFF = released
        handleKnobTouch(midiNote, isTouched)
      elseif midiNote >= 36 and midiNote <= 99 then
        local busNum, presetNum = unpack(mapNoteToPreset(midiNote))
        --print('busNum', busNum, 'presetNum', presetNum, presetStates[busNum][presetNum])
        if deleteMode and not presetStates[busNum][presetNum] then
          return
        end

        --print('preset to recall:', busNum, presetNum)
        local busGroupName = 'bus'..tostring(busNum)..'_group'
        --print('busGroupName', busGroupName)
        local performBusGroup = root:findByName(busGroupName, true)
        local performPresetGrid = performBusGroup:findByName('perform_preset_grid', true)

        if midiMessage[1] == 144 then
          performPresetGrid.children[presetNum].values.x = 1
          if deleteMode then
            illuminatePreset(busNum, presetNum, true, pressedDeletePresetVelocity)
          else
            illuminatePreset(busNum, presetNum, true, getPresetVelocity(true, busNum))
          end
        else
          performPresetGrid.children[presetNum].values.x = 0
          if deleteMode then
            handlePresetIllumination(busNum)
          else
            handlePresetIllumination(busNum)
            --illuminatePreset(busNum, presetNum, true, activePresetVelocity)
          end
        end
      end
    elseif midiMessage[1] == 176 then -- MIDI CC message
      local ccNum = midiMessage[2]
      local ccValue = midiMessage[3]
      -- Handle CC messages here
      --print('CC message:', ccNum, ccValue)
      mapCCToFeature(ccNum, ccValue)
    end
  elseif key == 'illuminate_presets' then
    --print('illuminate_presets', unpack(value))
    local busNum = value[1]
    fxNums[busNum] = value[2]
    deleteMode = value[3]
    print('illuminate_presets: bus', busNum, 'fxNum', value[2], 'fxNums array:', table.concat(fxNums, ','))

    handlePresetIllumination(busNum)
  elseif key == 'toggle_delete_mode' then
    --print('toggle_delete_mode', value)
    --print(unpack(presetStates[1]))
    deleteMode = value
    illuminatePresetGrids()
  elseif key == 'clear_presets' then
    local busNum = value
    if busNum == 5 then
      return
    end

        -- Get the effect number for the bus that triggered the clear
    local effectNum = fxNums[busNum]
    print('clear_presets: bus', busNum, 'effectNum', effectNum, 'fxNums array:', table.concat(fxNums, ','))

    -- Clear presets for all buses that have the same effect loaded
    for i = 1, 4 do
      if fxNums[i] == effectNum then
        print('clear_presets: clearing bus', i, 'because it has same effect', effectNum)
        presetStates[i] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false}
        for index = 1, 16 do
          illuminatePreset(i, index, false, inactivePresetVelocity)
        end
      end
    end
  elseif key == 'set_controlled_bus' then
    -- Set which bus is being controlled by Touch UI or Push
    local busNum = value
    if busNum == 0 then
      -- Clear control - reset all buses
      updateBusVisualIndicators(0)
    else
      -- Set this bus as the controlled bus
      controlEffect(busNum)
    end

        elseif key == 'toggle_button_state_changed' then
    -- Handle TouchOSC toggle button state changes
    local busNum = value[1]
    local newState = value[2]

    -- Update Push button lighting for this bus (only for buses 1-4)
    if busNum >= 1 and busNum <= 4 then
      local toggleButtonCCs = {20, 22, 24, 26}
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
      elseif key == 'sync_button_state_changed' then
    -- Handle TouchOSC sync button state changes
    local busNum = value[1]
    local buttonState = value[2]

    -- Get the sync button CC number for this bus (only for buses 1-4)
    if busNum >= 1 and busNum <= 4 then
      local syncButtonCCs = {21, 23, 25, 27}
      local syncCCNum = syncButtonCCs[busNum]

      if buttonState == 1 then
        -- Button pressed - bright orange
        sendMIDI({ 176, syncCCNum, pushFirstRowCCColors.orange.bright }, conn)
      else
        -- Button released - dim orange
        sendMIDI({ 176, syncCCNum, pushFirstRowCCColors.orange.dim }, conn)
      end
    end
  elseif key == 'grab_button_state_changed' then
    -- Handle TouchOSC grab button state changes
    local busNum = value[1]
    local buttonState = value[2]

    -- Get the grab button CC number for this bus (only for buses 1-4)
    if busNum >= 1 and busNum <= 4 then
      local grabButtonCCs = {102, 104, 106, 108}
      local grabCCNum = grabButtonCCs[busNum]

      if buttonState == 1 then
        -- Button pressed - bright blue
        sendMIDI({ 176, grabCCNum, pushSecondRowCCColors.blue.bright }, conn)
      else
        -- Button released - dim blue
        sendMIDI({ 176, grabCCNum, pushSecondRowCCColors.blue.dim }, conn)
      end
    end
  elseif key == 'control_bus_button_state_changed' then
    -- Handle TouchOSC control bus button state changes
    local busNum = value[1]
    local buttonState = value[2]

    -- Get the control button CC number for this bus (only for buses 1-4)
    if busNum >= 1 and busNum <= 4 then
      local controlButtonCCs = {103, 105, 107, 109}
      local controlCCNum = controlButtonCCs[busNum]

      if buttonState == 1 then
        -- Button pressed - bright yellow
        sendMIDI({ 176, controlCCNum, pushSecondRowCCColors.yellow.bright }, conn)
      else
        -- Button released - dim yellow
        sendMIDI({ 176, controlCCNum, pushSecondRowCCColors.yellow.dim }, conn)
      end
    end
  elseif key == 'clear_all_presets_global' then
    -- Clear presets for all buses that actually have effects loaded
    for busNum = 1, 4 do
      local busGroupName = 'bus'..tostring(busNum)..'_group'
      local performBusGroup = root:findByName(busGroupName, true)
      if performBusGroup then
        local effectChooser = performBusGroup:findByName('effect_chooser', true)
        if effectChooser then
          local selectedItem = effectChooser:findByName('selected_item')
          if selectedItem and selectedItem.tag ~= "" then
            -- This bus has an effect loaded, so clear its presets
            presetStates[busNum] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false}
            for index = 1, 16 do
              illuminatePreset(busNum, index, false, inactivePresetVelocity)
            end
          end
        end
      end
    end
  elseif key == 'add_preset' then
    local busNum = value[1]
    local presetNum = value[2]
    if busNum >= 1 and busNum <= 4 then
      presetStates[busNum][presetNum] = true
      illuminatePreset(busNum, presetNum, true, getPresetVelocity(false, busNum))
    end
  elseif key == 'sync_push_lighting' then
    -- Sync all Push button lighting with current TouchOSC states
    for busNum = 1, 4 do
      local busGroupName = 'bus'..tostring(busNum)..'_group'
      local performBusGroup = root:findByName(busGroupName, true)
      local onOffButtonGroup = performBusGroup:findByName('on_off_button_group', true)
      local toggleButton = onOffButtonGroup:findByName('toggle_button', true)
      local controlBusButton = onOffButtonGroup:findByName('control_bus_button', true)

      local effectState = toggleButton and toggleButton.values.x or 0
      local controlState = controlBusButton and controlBusButton.values.x or 0
      local toggleButtonCCs = {20, 22, 24, 26}
      local controlButtonCCs = {103, 105, 107, 109}
      local toggleCCNum = toggleButtonCCs[busNum]
      local controlCCNum = controlButtonCCs[busNum]

      if effectState == 1 then
        local brightGreenValue = pushFirstRowCCColors.green.bright
        sendMIDI({ 176, toggleCCNum, brightGreenValue }, conn)
      else
        local dimGreenValue = pushFirstRowCCColors.green.dim
        sendMIDI({ 176, toggleCCNum, dimGreenValue }, conn)
      end

      -- Sync control button lighting
      if controlState == 1 then
        local brightYellowValue = pushSecondRowCCColors.yellow.bright
        sendMIDI({ 176, controlCCNum, brightYellowValue }, conn)
      else
        local dimYellowValue = pushSecondRowCCColors.yellow.dim
        sendMIDI({ 176, controlCCNum, dimYellowValue }, conn)
      end
    end
  end
end

local function reset_push()
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

function init()
  reset_push()
  illuminatePresetGrids()

  -- Sync Push lighting with current TouchOSC states
  for busNum = 1, 4 do
    local busGroupName = 'bus'..tostring(busNum)..'_group'
    local performBusGroup = root:findByName(busGroupName, true)
    local onOffButtonGroup = performBusGroup:findByName('on_off_button_group', true)
    local toggleButton = onOffButtonGroup:findByName('toggle_button', true)
    local controlBusButton = onOffButtonGroup:findByName('control_bus_button', true)

    local effectState = toggleButton and toggleButton.values.x or 0
    local controlState = controlBusButton and controlBusButton.values.x or 0
    local toggleButtonCCs = {20, 22, 24, 26}
    local controlButtonCCs = {103, 105, 107, 109}
    local toggleCCNum = toggleButtonCCs[busNum]
    local controlCCNum = controlButtonCCs[busNum]

    if effectState == 1 then
      local brightGreenValue = pushFirstRowCCColors.green.bright
      sendMIDI({ 176, toggleCCNum, brightGreenValue }, conn)
    else
      local dimGreenValue = pushFirstRowCCColors.green.dim
      sendMIDI({ 176, toggleCCNum, dimGreenValue }, conn)
    end

    -- Initialize control button lighting
    if controlState == 1 then
      local brightYellowValue = pushSecondRowCCColors.yellow.bright
      sendMIDI({ 176, controlCCNum, brightYellowValue }, conn)
    else
      local dimYellowValue = pushSecondRowCCColors.yellow.dim
      sendMIDI({ 176, controlCCNum, dimYellowValue }, conn)
    end
  end

  -- Illuminate other feature buttons
  local grabCCs = {102, 104, 106, 108}
  for i = 1, 4 do
    local ccNum = grabCCs[i]
    sendMIDI({ 176, ccNum, pushSecondRowCCColors.blue.dim }, conn)
  end
  local controlCCs = {103, 105, 107, 109}
  for i = 1, 4 do
    local ccNum = controlCCs[i]
    sendMIDI({ 176, ccNum, pushSecondRowCCColors.yellow.dim }, conn)
  end
  -- Illuminate sync buttons with dim orange
  local syncCCs = {21, 23, 25, 27}
  for i = 1, 4 do
    local ccNum = syncCCs[i]
    sendMIDI({ 176, ccNum, pushFirstRowCCColors.orange.dim }, conn)
  end

  -- Initialize delete button lighting (CC 118)
  local deleteButtonValue = deleteMode and 127 or 1
  sendMIDI({ 176, 118, deleteButtonValue }, conn)

  -- Initialize visual indicators for the default bus (bus 1)
  updateBusVisualIndicators(busToControl)
end