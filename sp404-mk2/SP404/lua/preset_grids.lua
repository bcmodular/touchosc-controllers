local presetGridScript = [[
local fxNum = 0
local busNum = tonumber(self.tag) or 1
local deleteMode = false
local abletonFourBusMode = true
local defaultCCValues = {0, 0, 0, 0, 0, 0}
local presetManager = root.children.preset_manager
local excludeMarkedPresetsButton = self.parent:findByName('exclude_tuning_from_presets_button')
local faderGroup = self.parent:findByName('faders', true)
local defaultManager = root.children.default_manager
local abletonPushHandler = root:findByName('ableton_push_handler', true)

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

local function initialiseButtons()
  for i = 1, 16 do
    self.children[tostring(i)].color = BUTTON_STATE_COLORS.AVAILABLE
  end
end

local function changeState(index, color)
  --print('changeState', index, color)
  self.children[tostring(index)].color = color
end

local function refreshPresets()
  print('refreshPresets', fxNum)
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

    abletonPushHandler:notify('sync_push_lighting', busNum)
  end
end

local function refreshAllBuses()
  for i = 1, 5 do
    if i == busNum then
      refreshPresets()
    else
      local busGroup = root:findByName('bus'..tostring(i)..'_group', true)
      local presetGrid = busGroup:findByName('preset_grid', true)
      presetGrid:notify('refresh_presets_list')
    end

    if i <= 4 then
      abletonPushHandler:notify('sync_push_lighting', i)
    end
  end
end

local function storePreset(presetNum, delete)
  local ccValues = {unpack(defaultCCValues)}
  local presetArray = json.toTable(presetManager.children[tostring(fxNum)].tag) or {}

  if not delete then
    for i = 1, 6 do
      local fader = faderGroup:findByName(tostring(i))
      local controlFader = fader:findByName('control_fader')
      ccValues[i] = floatToMIDI(controlFader.values.x)
    end

    print('storePreset', fxNum, presetNum, ccValues)
    presetArray[formatPresetNum(presetNum)] = ccValues

  else
    print('deletePreset', fxNum, presetNum)
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
  end

  print('storeDefaults', fxNum, ccValues)
  defaultManager:notify('store_defaults', {fxNum, ccValues})
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

  abletonPushHandler:notify('toggle_delete_mode', deleteMode)
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
  elseif key == 'button_pressed' then
    buttonPressed(value)
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
  if key == 'x' and self.values.x == 1 then
    self.parent:notify('button_pressed', self.name)
  end
end
]]

function init()
  local debugMode = root:findByName('debug_mode').values.x

  if debugMode == 1 then
    local presetGrids = root:findAllByName('preset_grid', true)

    for _, presetGrid in ipairs(presetGrids) do
      presetGrid.script = presetGridScript
      for i = 1, 16 do
        local button = presetGrid:findByName(tostring(i))
        button.script = presetButtonScript
      end
    end
  end
end
