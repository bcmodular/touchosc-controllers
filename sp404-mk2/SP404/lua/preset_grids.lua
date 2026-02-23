local fxNums = {}
local deleteMode = false

local presetNoteMap = {
  81, 82, 71, 72, 61, 62, 51, 52, 41, 42, 31, 32, 21, 22, 11, 12,
  83, 84, 73, 74, 63, 64, 53, 54, 43, 44, 33, 34, 23, 24, 13, 14,
  85, 86, 75, 76, 65, 66, 55, 56, 45, 46, 35, 36, 25, 26, 15, 16,
  87, 88, 77, 78, 67, 68, 57, 58, 47, 48, 37, 38, 27, 28, 17, 18
}

local velocityColours = { 35, 15, 59, 47 }

local BUTTON_STATE_COLORS = {
  AVAILABLE = "FFFFFFFF",
  DELETE = "FF0000FF"
}

local defaultCCValues = {0, 0, 0, 0, 0, 0}

-- Shared references
local presetManager = root.children.preset_manager
local defaultManager = root.children.default_manager
local controlsInfo = root.children.controls_info

local function formatPresetNum(num)
  return string.format("%02d", num)
end

local function getRecallButtonColor(busNum)
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
  return midiValue / 127
end

local function floatToMIDI(floatValue)
  return math.floor(floatValue * 127 + 0.5)
end

local function sendSysexLEDUpdate(ledIndex, color)
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0A, ledIndex, color, 0xF7 }
  print('sendSysexLEDUpdate', ledIndex, color)
  sendMIDI(sysexMessage)
end

local function sendSysexAllPadsOff(busNum)
  local ledUpdates = {}
  for i = 1, 16 do
    local mapEntry = (busNum - 1) * 16 + i
    local note = presetNoteMap[mapEntry]
    if note then
      table.insert(ledUpdates, note)
      table.insert(ledUpdates, 0)  -- Color 0 = off
    end
  end

  if #ledUpdates > 0 then
    local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0A }
    for _, value in ipairs(ledUpdates) do
      table.insert(sysexMessage, value)
    end
    table.insert(sysexMessage, 0xF7)
    print('sendSysexAllPadsOff bus', busNum, #ledUpdates / 2, 'pads')
    sendMIDI(sysexMessage)
  end
end

local function getGrid(busNum)
  local busGroup = root:findByName('bus'..tostring(busNum)..'_group', true)
  if busGroup then
    return busGroup:findByName('preset_grid', true)
  end
  return nil
end

local function initialiseButtons(busNum)
  local grid = getGrid(busNum)
  if not grid then return end

  for i = 1, 16 do
    grid.children[tostring(i)].color = BUTTON_STATE_COLORS.AVAILABLE
  end
  sendSysexAllPadsOff(busNum)
end

local function refreshMIDIButtons(busNum)
  local grid = getGrid(busNum)
  if not grid then return end

  local ledUpdates = {}
  for i = 1, 16 do
    local button = grid.children[tostring(i)]
    local midiColour = 0

    if (Color.toHexString(button.color) == BUTTON_STATE_COLORS.DELETE) then
      midiColour = 5
    elseif (Color.toHexString(button.color) == getRecallButtonColor(busNum)) then
      midiColour = velocityColours[busNum] or velocityColours[1] or 35
    end

    if midiColour ~= 0 then
      local mapEntry = (busNum - 1) * 16 + i
      local note = presetNoteMap[mapEntry]
      if note then
        table.insert(ledUpdates, note)
        table.insert(ledUpdates, midiColour)
      end
    end
  end

  if #ledUpdates > 0 then
    local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0A }
    for _, value in ipairs(ledUpdates) do
      table.insert(sysexMessage, value)
    end
    table.insert(sysexMessage, 0xF7)
    print('refreshMIDIButtons bus', busNum, #ledUpdates / 2, 'LEDs')
    sendMIDI(sysexMessage)
  end
end

local function refreshPresets(busNum, fxNum)
  if fxNum ~= nil then
    fxNums[busNum] = fxNum
  end
  fxNum = fxNums[busNum] or 0

  print('refreshPresets', busNum, fxNum)
  sendSysexAllPadsOff(busNum)

  local grid = getGrid(busNum)
  if not grid then return end

  if fxNum == 0 then
    initialiseButtons(busNum)
    return
  end

  local presetManagerChild = presetManager.children[tostring(fxNum)]
  local presetArray = json.toTable(presetManagerChild.tag) or {}

  initialiseButtons(busNum)

  -- Set STORED state for active presets
  for index, _ in pairs(presetArray) do
    local presetNum = tonumber(index)
    local color = deleteMode and BUTTON_STATE_COLORS.DELETE or getRecallButtonColor(busNum)
    grid.children[tostring(presetNum)].color = color
  end

  refreshMIDIButtons(busNum)
end

local function refreshAllBusesForFx(fxNum)
  -- Refresh all buses that have this fxNum loaded
  for busNum, busFxNum in pairs(fxNums) do
    if busFxNum == fxNum and fxNum ~= 0 then
      refreshPresets(busNum)
    end
  end
end

local function recallPreset(busNum, presetNum)
  local fxNum = fxNums[busNum] or 0

  if fxNum == 0 then return end

  local presetArray = json.toTable(presetManager.children[tostring(fxNum)].tag) or {}
  local presetValues = presetArray[formatPresetNum(presetNum)]

  if presetValues == nil then
    return
  end

  local grid = getGrid(busNum)
  if not grid then return end

  local busGroup = grid.parent
  local excludeMarkedPresetsButton = busGroup:findByName('exclude_tuning_from_presets_button', true)
  local faderGroup = busGroup:findByName('faders', true)
  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)

  local exclude_marked_presets = excludeMarkedPresetsButton.values.x == 1

  for i, controlInfo in ipairs(controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)
    local fader = faderGroup:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')

    print('recallPreset', busNum, fxNum, presetNum, i, presetValues[i])
    if not isExcludable or not exclude_marked_presets then
      controlFader:notify('new_value', midiToFloat(presetValues[i]))
    end
  end
end

local function recallDefaults(busNum)
  local fxNum = fxNums[busNum] or 0

  if fxNum == 0 then return end

  local defaultValues = json.toTable(defaultManager.tag)[tostring(fxNum)]

  if defaultValues == nil then
    return
  end

  local grid = getGrid(busNum)
  if not grid then return end

  local busGroup = grid.parent
  local excludeMarkedPresetsButton = busGroup:findByName('exclude_tuning_from_presets_button', true)
  local faderGroup = busGroup:findByName('faders', true)
  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)

  local exclude_marked_presets = excludeMarkedPresetsButton.values.x == 1

  for i, controlInfo in ipairs(controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)
    local fader = faderGroup:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')

    print('recallDefaults', busNum, fxNum, i, defaultValues[i])
    if not isExcludable or not exclude_marked_presets then
      controlFader:notify('new_value', midiToFloat(defaultValues[i]))
    end
  end
end

local function storePreset(busNum, presetNum, delete)
  local fxNum = fxNums[busNum] or 0

  if fxNum == 0 then return end

  local grid = getGrid(busNum)
  if not grid then return end

  local busGroup = grid.parent
  local faderGroup = busGroup:findByName('faders', true)
  local ccValues = {unpack(defaultCCValues)}
  local presetArray = json.toTable(presetManager.children[tostring(fxNum)].tag) or {}

  if not delete and not deleteMode then
    for i = 1, 6 do
      local fader = faderGroup:findByName(tostring(i))
      local controlFader = fader:findByName('control_fader')
      ccValues[i] = floatToMIDI(controlFader.values.x)
    end

    print('storePreset', busNum, fxNum, presetNum, ccValues)
    presetArray[formatPresetNum(presetNum)] = ccValues
  else
    print('deletePreset', busNum, fxNum, presetNum)
    presetArray[formatPresetNum(presetNum)] = nil
  end

  local jsonPresets = json.fromTable(presetArray)
  presetManager.children[tostring(fxNum)].tag = jsonPresets

  refreshAllBusesForFx(fxNum)
end

local function storeDefaults(busNum)
  local fxNum = fxNums[busNum] or 0

  if fxNum == 0 then return end

  local grid = getGrid(busNum)
  if not grid then return end

  local busGroup = grid.parent
  local faderGroup = busGroup:findByName('faders', true)
  local ccValues = {unpack(defaultCCValues)}

  for i = 1, 6 do
    local fader = faderGroup:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')
    ccValues[i] = floatToMIDI(controlFader.values.x)

    controlFader:setValueField("x", ValueField.DEFAULT, controlFader.values.x)
  end

  print('storeDefaults', busNum, fxNum, ccValues)
  defaultManager:notify('store_defaults', {fxNum, ccValues})
end

local function updateButtonMIDIHighlight(busNum, presetNum, isPressed)
  local grid = getGrid(busNum)
  if not grid then return end

  local button = grid:findByName(tostring(presetNum))
  local buttonColor = Color.toHexString(button.color)
  local mapEntry = (busNum - 1) * 16 + presetNum
  local note = presetNoteMap[mapEntry]

  if not note then
    return
  end

  local color = 0
  local baseVelocity = velocityColours[busNum] or velocityColours[1] or 35

  if buttonColor == BUTTON_STATE_COLORS.DELETE then
    return
  elseif buttonColor == getRecallButtonColor(busNum) then
    if isPressed then
      color = baseVelocity - 2
    else
      color = baseVelocity
    end
  elseif buttonColor == BUTTON_STATE_COLORS.AVAILABLE then
    if isPressed then
      color = baseVelocity
    end
  end

  if color > 0 then
    sendSysexLEDUpdate(note, color)
  end
end

local function buttonPressed(busNum, presetNum)
  local grid = getGrid(busNum)
  if not grid then return end

  local button = grid:findByName(tostring(presetNum))
  local buttonColor = Color.toHexString(button.color)

  if (buttonColor == BUTTON_STATE_COLORS.DELETE) then
    storePreset(busNum, presetNum, true)
  elseif (buttonColor == getRecallButtonColor(busNum)) then
    recallPreset(busNum, presetNum)
  else
    storePreset(busNum, presetNum, false)
  end
end

local function toggleDeleteMode(value)
  print('toggleDeleteMode', value)
  deleteMode = value

  -- Refresh all buses
  for busNum, _ in pairs(fxNums) do
    refreshPresets(busNum)
  end
end

local function initializeGrid(busNum)
  local grid = getGrid(busNum)
  if not grid then return end

  sendSysexAllPadsOff(busNum)

  local busGroup = grid.parent
  local background = grid:findByName('preset_grid_background_box')
  background.color = getRecallButtonColor(busNum)

  local selectedItemButton = busGroup.parent:findByName('selected_item_button', true)
  selectedItemButton.color = getRecallButtonColor(busNum)
  local selectedItemBackground = busGroup.parent:findByName('background', true)
  selectedItemBackground.color = getRecallButtonColor(busNum)

  local faderGroup = busGroup:findByName('faders', true)
  local controlFaders = faderGroup:findAllByName('control_fader', true)
  for _, controlFader in ipairs(controlFaders) do
    controlFader.color = getRecallButtonColor(busNum)
  end

  local valueLabels = faderGroup:findAllByName('value_label', true)
  for _, valueLabel in ipairs(valueLabels) do
    valueLabel.textColor = Color.fromHexString("FFFFFFFF")
    valueLabel.color = Color.fromHexString("00000000")
  end

  -- Get initial fxNum from bus_group tag
  local busSettings = json.toTable(busGroup.tag) or {}
  local fxNum = tonumber(busSettings.fxNum) or 0
  fxNums[busNum] = fxNum

  refreshPresets(busNum, fxNum)
end

-- Manager notification handler
local function onReceiveNotify(key, value)
  if key == 'refresh_presets_list' then
    local busNum = value[1]
    local fxNum = value[2]
    if busNum then
      refreshPresets(busNum, fxNum)
    end
  elseif key == 'toggle_delete_mode' then
    toggleDeleteMode(value)
  elseif key == 'store_defaults' then
    local busNum = value
    if busNum then
      storeDefaults(busNum)
    end
  elseif key == 'recall_defaults' then
    local busNum = value
    if busNum then
      recallDefaults(busNum)
    end
  elseif key == 'button_value_changed' then
    local busNum = value[1]
    local presetNum = value[2]
    local isPressed = value[3] == 1
    local fxNum = fxNums[busNum] or 0

    if fxNum == 0 then
      return
    end

    updateButtonMIDIHighlight(busNum, presetNum, isPressed)
    if isPressed then
      buttonPressed(busNum, presetNum)
    end
  elseif key == 'clear_presets' then
    local busNum = value
    if busNum then
      print('clear_presets', busNum)
      initialiseButtons(busNum)
    end
  end
end

-- Simplified preset grid script - delegates to manager
local presetGridScript = [[
local busNum = tonumber(self.tag) or 1
local manager = root.children.preset_grid_manager

function onReceiveNotify(key, value)
  if key == 'refresh_presets_list' then
    -- value can be fxNum (number) or nil
    local fxNum = value
    manager:notify(key, {busNum, fxNum})
  elseif key == 'toggle_delete_mode' then
    manager:notify(key, value)
  elseif key == 'store_defaults' then
    manager:notify(key, busNum)
  elseif key == 'recall_defaults' then
    manager:notify(key, busNum)
  elseif key == 'button_value_changed' then
    manager:notify(key, {busNum, value[1], value[2]})
  elseif key == 'clear_presets' then
    manager:notify(key, busNum)
  end
end
]]

-- Simplified button script - notifies manager
local presetButtonScript = [[
function onValueChanged(key, value)
  if key == 'x' then
    local presetNum = tonumber(self.name)
    local busNum = tonumber(self.parent.tag) or 1
    local manager = root.children.preset_grid_manager
    manager:notify('button_value_changed', {busNum, presetNum, self.values.x})
  end
end
]]

function init()
  -- Expose manager functions for the manager script to call
  root.preset_grid_manager = {
    onReceiveNotify = onReceiveNotify
  }

  local presetGrids = root:findAllByName('preset_grid', true)

  for _, presetGrid in ipairs(presetGrids) do
    presetGrid.script = presetGridScript
    for i = 1, 16 do
      local button = presetGrid:findByName(tostring(i))
      button.script = presetButtonScript
    end
  end

  -- Initialize all grids
  for i = 1, 5 do
    initializeGrid(i)
  end
end
