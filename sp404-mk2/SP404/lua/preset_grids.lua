local presetGridScript = [[
local fxNum = 0
local busNum = tonumber(self.tag) or 1
local deleteMode = false
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

local function sendSysexLEDUpdate(ledIndex, color)
  -- SysEx format: F0h 00h 20h 29h 02h 10h 0Ah <LED> <Colour> F7h
  -- Decimal: (240,0,32,41,2,16,10,<LED>,<Colour>,247)
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0A, ledIndex, color, 0xF7 }
  print('sendSysexLEDUpdate', ledIndex, color)
  sendMIDI(sysexMessage)
end

local function sendSysexAllPadsOff()
  -- Clear only the 16 pads for this bus using multi-pad SysEx message
  -- SysEx format: F0h 00h 20h 29h 02h 10h 0Ah <LED1> <Colour1> <LED2> <Colour2> ... F7h
  -- Can send up to 97 LED/Color pairs in one message
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

local function refreshMIDIButtons()
  -- Build a batch of LED updates (can send up to 97 LED/Color pairs in one message)
  local ledUpdates = {}
  for i = 1, 16 do
    local button = self.children[tostring(i)]
    local midiColour = 0

    if (Color.toHexString(button.color) == BUTTON_STATE_COLORS.DELETE) then
      midiColour = 5
    elseif (Color.toHexString(button.color) == getRecallButtonColor()) then
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

  -- Send all LED updates in a single SysEx message (we have at most 16 pads, well under 97 limit)
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

local function initialiseButtons()
  for i = 1, 16 do
    self.children[tostring(i)].color = BUTTON_STATE_COLORS.AVAILABLE
  end
  sendSysexAllPadsOff()
end

local function changeState(index, color)
  --print('changeState', index, color)
  self.children[tostring(index)].color = color
end

local function refreshPresets()
  print('refreshPresets', fxNum)
  sendSysexAllPadsOff()

  -- Clear all pads for this bus when effect is unloaded (fxNum == 0) or when loading new effect
  if fxNum == 0 then
    -- Effect unloaded - clear all pads for this bus
    initialiseButtons()
    return
  end

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

  refreshMIDIButtons()
end

--local function sendNoteOffForPresetOnAllBuses(presetNum)
  -- Turn off LED for this preset on all buses that have the same fxNum loaded
  --for i = 1, 5 do
    --local busGroup = root:findByName('bus'..tostring(i)..'_group', true)
    --if busGroup then
      --local busSettings = json.toTable(busGroup.tag) or {}
      --local busFxNum = tonumber(busSettings.fxNum) or 0

      --if busFxNum == fxNum and fxNum ~= 0 then
        --local mapEntry = (i - 1) * 16 + presetNum
        --local note = presetNoteMap[mapEntry]
        --if note then
          -- Turn off LED by sending color 0
          --sendSysexLEDUpdate(note, 0)
        --end
      --end
    --end
  --end
--end

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
    --sendNoteOffForPresetOnAllBuses(presetNum)
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
  local note = presetNoteMap[mapEntry]

  if not note then
    return
  end

  local color = 0

  -- Get velocity color for this bus, with fallback for buses > 4
  local baseVelocity = velocityColours[busNum] or velocityColours[1] or 35

  -- Don't highlight DELETE buttons - they get deleted immediately and pad is set to 0
  if buttonColor == BUTTON_STATE_COLORS.DELETE then
    return
  elseif buttonColor == getRecallButtonColor() then
    -- Stored preset (recall button)
    if isPressed then
      -- Brighter version: 2 lower than regular
      color = baseVelocity - 2
    else
      -- Regular velocity
      color = baseVelocity
    end
  elseif buttonColor == BUTTON_STATE_COLORS.AVAILABLE then
    -- New preset being stored
    if isPressed then
      -- Use regular velocity for new presets (will become stored after press)
      color = baseVelocity
    end
    -- No need to restore on release for AVAILABLE buttons (they don't have MIDI state)
  end

  if color > 0 then
    sendSysexLEDUpdate(note, color)
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
  elseif key == 'button_value_changed' then
    if fxNum == 0 then
      return
    end

    local presetNum = tonumber(value[1])
    local isPressed = value[2] == 1
    -- Handle MIDI highlighting
    updateButtonMIDIHighlight(presetNum, isPressed)
    -- Handle button press action (only when pressed, not on release)
    if isPressed then
      buttonPressed(presetNum)
    end
  elseif key == 'clear_presets' then
    print('clear_presets')
    initialiseButtons()
  end
end

function init()
  -- Clear all pads on startup
  sendSysexAllPadsOff()

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
    -- Notify parent of value change (handles both MIDI highlighting and button action)
    self.parent:notify('button_value_changed', {presetNum, self.values.x})
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
