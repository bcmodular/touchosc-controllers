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
  if state then
    sendMIDI({ 144, noteNum, velocity }, conn)
  else
    sendMIDI({ 128, noteNum, velocity }, conn)
  end
end

local function illuminatePresetGrids()
  for i = 1, 4 do
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

local function illuminateFeatureButtons()
  -- Turn on the on button feature buttons for the four effect buses
  local ccNums = {20, 22, 24, 26}
  for i = 1, 4 do
    local ccNum = ccNums[i]
    sendMIDI({ 176, ccNum, 22 }, conn)
  end
  -- Turn on the off button feature buttons for the four effect buses
  ccNums = {21, 23, 25, 27}
  for i = 1, 4 do
    local ccNum = ccNums[i]
    sendMIDI({ 176, ccNum, 4 }, conn)
  end
  -- Turn on the grab button feature buttons for the four effect buses
  ccNums = {102, 104, 106, 108}
  for i = 1, 4 do
    local ccNum = ccNums[i]
    sendMIDI({ 176, ccNum, pushColors.blue.bright }, conn)
  end
  -- Turn on the control button for the four effect buses
  ccNums = {103, 105, 107, 109}
  for i = 1, 4 do
    local ccNum = ccNums[i]
    sendMIDI({ 176, ccNum, pushColors.yellow.bright }, conn)
  end
end
local function turnOnEffect(busNum, ccValue)
  --print('turning on effect for bus:', busNum)
  local busGroupName = 'bus'..tostring(busNum)..'_group'
  local performBusGroup = root:findByName(busGroupName, true)
  local onButton = performBusGroup:findByName('on_button', true)
  onButton.values.x = ccValue == 127 and 1 or 0
end

local function turnOffEffect(busNum, ccValue)
  --print('turning off effect for bus:', busNum)
  local busGroupName = 'bus'..tostring(busNum)..'_group'
  local performBusGroup = root:findByName(busGroupName, true)
  local offButton = performBusGroup:findByName('off_button', true)
  offButton.values.x = ccValue == 127 and 1 or 0
end

local function grabEffect(busNum, ccValue)
  --print('grabbing effect for bus:', busNum)
  local busGroupName = 'bus'..tostring(busNum)..'_group'
  local performBusGroup = root:findByName(busGroupName, true)
  local grabButton = performBusGroup:findByName('grab_button', true)
  grabButton.values.x = ccValue == 127 and 1 or 0
end

local function controlEffect(busNum)
  --print('controlling effect for bus:', busNum)
  busToControl = busNum
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
  -- On button: 20, 22, 24, 26 are the cc numbers to turn on each of the four effect buses
  if ccNum == 20 or ccNum == 22 or ccNum == 24 or ccNum == 26 then
    local ccToBus = {
      [20] = 1,
      [22] = 2,
      [24] = 3,
      [26] = 4
    }
    local busNum = ccToBus[ccNum]
    turnOnEffect(busNum, ccValue)
  -- Off button: 21, 23, 25, 27 are the cc numbers to turn off each of the four effect buses
  elseif ccNum == 21 or ccNum == 23 or ccNum == 25 or ccNum == 27 then
    local ccToBus = {
      [21] = 1,
      [23] = 2,
      [25] = 3,
      [27] = 4
    }
    local busNum = ccToBus[ccNum]
    turnOffEffect(busNum, ccValue)
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
      if midiNote >= 36 and midiNote <= 99 then
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
    presetStates[busNum] = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false}
    for index = 1, 16 do
      illuminatePreset(busNum,index, false, inactivePresetVelocity)
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
  illuminateFeatureButtons()
end