local presetGridScript = [[
local fxNum = 0
local busNum = tonumber(self.tag) or 1
local deleteMode = false
local abletonFourBusMode = true
local defaultCCValues = {0, 0, 0, 0, 0, 0}
local presetManager = root.children.preset_manager
local excludeMarkedPresetsButton = self.parent:findByName('exclude_tuning_from_presets_button', true)
local faderGroup = self.parent:findByName('faders', true)
local defaultManager = root.children.default_manager


local presetNoteMap = {
    81, 82, 71, 72, 61, 62, 51, 52, 41, 42, 31, 32, 21, 22, 11, 12,
    83, 84, 73, 74, 63, 64, 53, 54, 43, 44, 33, 34, 23, 24, 13, 14,
    85, 86, 75, 76, 65, 66, 55, 56, 45, 46, 35, 36, 25, 26, 15, 16,
    87, 88, 77, 78, 67, 68, 57, 58, 47, 48, 37, 38, 27, 28, 17, 18
}

local velocityColours = {
  35,
  15,
  59,
  47
}

local BUTTON_STATE_COLORS = {
  --RECALL = "00FF00FF",
  AVAILABLE = "FFFFFFFF",
  DELETE = "FF0000FF"
}
local controlsInfo = root.children.controls_info

local function formatPresetNum(num)
  return string.format("%02d", num)
end

local function getRecallButtonColor()
  if busNum == 1 then
    return "00E6FFFF"  -- cyan
  elseif busNum == 2 then
    return "FFD700FF"  -- very bright pale yellow
  elseif busNum == 3 then
    return "FF69B4FF"  -- pale pink
  elseif busNum == 4 then
    return "4A90E2FF"  -- blue
  else
    return "32CD32FF"  -- green (default)
  end
end

local function midiToFloat(midiValue)
  local floatValue = midiValue / 127
  return floatValue
end

local function floatToMIDI(floatValue)
  local midiValue = math.floor(floatValue * 127 + 0.5)
  return midiValue
end

local function recallPreset(presetNum)
  local presetArray = json.toTable(presetManager.children[tostring(fxNum)].tag) or {}
  local presetValues = presetArray[formatPresetNum(presetNum)]

  if presetValues == nil then
    return
  end

  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)

  local exclude_marked_presets = excludeMarkedPresetsButton.values.x == 1

  for i, controlInfo in ipairs(controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)
    local fader = faderGroup:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')

    print('recallPreset', fxNum, presetNum, i, presetValues[i])
    print('recallPreset', faderGroup.name )
    print('recallPreset', controlFader.name)
    if not isExcludable or not exclude_marked_presets then
      controlFader:notify('new_value', midiToFloat(presetValues[i]))
    end
  end
end

local function recallDefaults()
  local defaultValues = json.toTable(defaultManager.tag)[tostring(fxNum)]

  if defaultValues == nil then
    return
  end

  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)

  local exclude_marked_presets = excludeMarkedPresetsButton.values.x == 1

  for i, controlInfo in ipairs(controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)
    local fader = faderGroup:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')

    print('recallDefaults', fxNum, i, defaultValues[i])
    print('recallDefaults', faderGroup.name )
    print('recallDefaults', controlFader.name)
    if not isExcludable or not exclude_marked_presets then
      controlFader:notify('new_value', midiToFloat(defaultValues[i]))
    end
  end
end

local function refreshMIDIButtons()
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + 1, 123, 0 }, {false, true})
  for i = 1, 16 do
    local button = self.children[tostring(i)]
    local midiColour = 0

    if (Color.toHexString(button.color) == BUTTON_STATE_COLORS.DELETE) then
      midiColour = 5
    elseif (Color.toHexString(button.color) == getRecallButtonColor()) then
      midiColour = velocityColours[busNum]
    end

    if midiColour ~= 0 then
      local mapEntry = (busNum - 1) * 16 + i
      sendMIDI({ MIDIMessageType.NOTE_ON + 1, presetNoteMap[mapEntry], midiColour }, {false, true})
    end
  end
end

local function initialiseButtons()
  for i = 1, 16 do
    self.children[tostring(i)].color = BUTTON_STATE_COLORS.AVAILABLE
  end

  sendMIDI({ MIDIMessageType.CONTROLCHANGE + 1, 123, 0 }, {false, true})
end

local function changeState(index, color)
  --print('changeState', index, color)
  self.children[tostring(index)].color = color
end

local function refreshPresets()
  --print('refreshPresets', fxNum)
  if fxNum ~= 0 then
    local presetManagerChild = presetManager.children[tostring(fxNum)]
    local presetArray = json.toTable(presetManagerChild.tag) or {}

    initialiseButtons()

    -- Set STORED state for active presets
    for index, _ in pairs(presetArray) do
      local presetNum = tonumber(index)
      if deleteMode then
        changeState(presetNum, BUTTON_STATE_COLORS.DELETE)
      else
        changeState(presetNum, getRecallButtonColor())
      end
    end
  end
  refreshMIDIButtons()
end

local function sendNoteOffForPresetOnAllBuses(presetNum)
  -- Send note off for this preset on all buses that have the same fxNum loaded
  for i = 1, 5 do
    local busGroup = root:findByName('bus'..tostring(i)..'_group', true)
    if busGroup then
      local busSettings = json.toTable(busGroup.tag) or {}
      local busFxNum = tonumber(busSettings.fxNum) or 0

      if busFxNum == fxNum and fxNum ~= 0 then
        local mapEntry = (i - 1) * 16 + presetNum
        sendMIDI({ MIDIMessageType.NOTE_OFF + 1, presetNoteMap[mapEntry], 0 }, {false, true})
      end
    end
  end
end

local function refreshAllBuses()
  for i = 1, 5 do
    if i == busNum then
      refreshPresets()
    else
      local busGroup = root:findByName('bus'..tostring(i)..'_group', true)
      if busGroup then
        local busSettings = json.toTable(busGroup.tag) or {}
        local busFxNum = tonumber(busSettings.fxNum) or 0
        -- Only refresh buses that have the same effect loaded
        if busFxNum == fxNum and fxNum ~= 0 then
          local presetGrid = busGroup:findByName('preset_grid', true)
          if presetGrid then
            presetGrid:notify('refresh_presets_list')
          end
        end
      end
    end
  end
end

local function storePreset(presetNum, delete)
  local ccValues = {unpack(defaultCCValues)}
  local presetArray = json.toTable(presetManager.children[tostring(fxNum)].tag) or {}

  if not delete and not deleteMode then
    for i = 1, 6 do
      local fader = faderGroup:findByName(tostring(i))
      local controlFader = fader:findByName('control_fader')
      ccValues[i] = floatToMIDI(controlFader.values.x)
    end

    print('storePreset', fxNum, presetNum, ccValues)
    presetArray[formatPresetNum(presetNum)] = ccValues

  else
    print('deletePreset', fxNum, presetNum)
    -- Send explicit note off for this preset on all buses before deleting
    sendNoteOffForPresetOnAllBuses(presetNum)
    presetArray[formatPresetNum(presetNum)] = nil
  end

  local jsonPresets = json.fromTable(presetArray)
  presetManager.children[tostring(fxNum)].tag = jsonPresets

  refreshAllBuses()
end

local function deletePreset(presetNum)
  storePreset(presetNum, true)
end

local function storeDefaults()
  local ccValues = {unpack(defaultCCValues)}

  for i = 1, 6 do
    local fader = faderGroup:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')
    ccValues[i] = floatToMIDI(controlFader.values.x)

    controlFader:setValueField("x", ValueField.DEFAULT, controlFader.values.x)
  end

  print('storeDefaults', fxNum, ccValues)
  defaultManager:notify('store_defaults', {fxNum, ccValues})
end

local function updateButtonMIDIHighlight(presetNum, isPressed)
  local button = self:findByName(tostring(presetNum))
  local buttonColor = Color.toHexString(button.color)
  local mapEntry = (busNum - 1) * 16 + presetNum
  local velocity = 0

  -- Don't highlight DELETE buttons - they get deleted immediately and pad is set to 0
  if buttonColor == BUTTON_STATE_COLORS.DELETE then
    return
  elseif buttonColor == getRecallButtonColor() then
    -- Stored preset (recall button)
    if isPressed then
      -- Brighter version: 2 lower than regular
      velocity = velocityColours[busNum] - 2
    else
      -- Regular velocity
      velocity = velocityColours[busNum]
    end
  elseif buttonColor == BUTTON_STATE_COLORS.AVAILABLE then
    -- New preset being stored
    if isPressed then
      -- Use regular velocity for new presets (will become stored after press)
      velocity = velocityColours[busNum]
    end
    -- No need to restore on release for AVAILABLE buttons (they don't have MIDI state)
  end

  if velocity > 0 then
    sendMIDI({ MIDIMessageType.NOTE_ON + 1, presetNoteMap[mapEntry], velocity }, {false, true})
  end
end

local function buttonPressed(index)
  local button = self:findByName(tostring(index))

  if (Color.toHexString(button.color) == BUTTON_STATE_COLORS.DELETE) then
    deletePreset(index)
  elseif (Color.toHexString(button.color) == getRecallButtonColor()) then
    recallPreset(index)
  else
    storePreset(index, false)
  end
end

local function toggleDeleteMode(value)
  print('toggleDeleteMode', value, busNum)
  deleteMode = value

  for i = 1, 16 do
    local button = self:findByName(tostring(i))

    if Color.toHexString(button.color) == getRecallButtonColor() or Color.toHexString(button.color) == BUTTON_STATE_COLORS.DELETE then
      --print('I am a button that needs to be switched', self.name)
      if deleteMode then
        button.color = BUTTON_STATE_COLORS.DELETE
      else
        button.color = getRecallButtonColor()
      end
    end
  end

  refreshAllBuses()
end

function onReceiveNotify(key, value)
  if key == 'refresh_presets_list' then
    if value ~= nil then
      fxNum = value
    end
    refreshPresets()
  elseif key == 'toggle_delete_mode' then
    toggleDeleteMode(value)
  elseif key == 'store_defaults' then
    storeDefaults()
  elseif key == 'recall_defaults' then
    recallDefaults()
  elseif key == 'button_pressed' then
    buttonPressed(value)
  elseif key == 'button_value_changed' then
    local presetNum = tonumber(value[1])
    local isPressed = value[2] == 1
    updateButtonMIDIHighlight(presetNum, isPressed)
  elseif key == 'clear_presets' then
    initialiseButtons()
  end
end

function init()
  local background = self:findByName('preset_grid_background_box')
  background.color = getRecallButtonColor()

  local selectedItemButton = self.parent.parent:findByName('selected_item_button', true)
  selectedItemButton.color = getRecallButtonColor()
  local selectedItemBackground = self.parent.parent:findByName('background', true)
  selectedItemBackground.color = getRecallButtonColor()

  local controlFaders = faderGroup:findAllByName('control_fader', true)
  for _, controlFader in ipairs(controlFaders) do
    controlFader.color = getRecallButtonColor()
  end

  local valueLabel = faderGroup:findAllByName('value_label', true)
  for _, valueLabel in ipairs(valueLabel) do
    valueLabel.textColor = Color.fromHexString("FFFFFFFF")
    valueLabel.color = Color.fromHexString("00000000")
  end

  refreshPresets()
end
]]

local presetButtonScript = [[
function onValueChanged(key, value)
  if key == 'x' then
    local presetNum = tonumber(self.name)
    self.parent:notify('button_value_changed', {presetNum, self.values.x})

    if self.values.x == 1 then
      self.parent:notify('button_pressed', self.name)
    end
  end
end
]]

function init()
  local presetGrids = root:findAllByName('preset_grid', true)

  for _, presetGrid in ipairs(presetGrids) do
    presetGrid.script = presetGridScript
    for i = 1, 16 do
      local button = presetGrid:findByName(tostring(i))
      button.script = presetButtonScript
    end
  end
end
