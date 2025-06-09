local performPresetGridScript = [[
local fxNum = 1
local busNum = nil
local deleteMode = false
local abletonFourBusMode = true
local defaultCCValues = {0, 0, 0, 0, 0, 0}

local BUTTON_STATE_COLORS = {
  --RECALL = "00FF00FF",
  AVAILABLE = "FFFFFFFF",
  DELETE = "FF0000FF"
}

local function getRecallButtonColor(busNum)
  if busNum == 1 then
    return "00FFFFFF"  -- cyan
  elseif busNum == 2 then
    return "FFD700FF"  -- very bright pale yellow
  elseif busNum == 3 then
    return "FF5EDCFF"  -- pale pink
  elseif busNum == 4 then
    return "0000FFFF"  -- blue
  else
    return "00FF00FF"  -- green (default)
  end
end

local function initializeButtons(grid)
  busNum = tonumber(self.parent.parent.parent.tag ~= "" and self.parent.parent.parent.tag or 0) + 1
  self.color = getRecallButtonColor(busNum)

  for i = 1, #grid.children do
    grid.children[i].color = BUTTON_STATE_COLORS.AVAILABLE
  end
end

local function changeState(parentGrid, index, color)
  parentGrid.children[index].color = color
end

local function floatToMIDI(floatValue)
  local midiValue = math.floor(floatValue * 127 + 0.5)
  return midiValue
end

local function storeFXPreset(presetNum)
  local ccValues = {unpack(defaultCCValues)}
  local faderGroup = self.parent.parent.parent:findByName('faders')

  for i = 1, 6 do
    local fader = faderGroup:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')
    ccValues[i] = floatToMIDI(controlFader.values.x)
  end

  --print('Current MIDI values:', unpack(ccValues))

  local presetManager = root.children.preset_manager
  presetManager:notify('store_preset', {fxNum, presetNum, ccValues})
  self.parent:notify('refresh_presets_list')
end

local function storeFXDefaults()
  local ccValues = {unpack(defaultCCValues)}
  local faderGroup = self.parent.parent.parent:findByName('faders')

  for i = 1, 6 do
    local fader = faderGroup:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')
    ccValues[i] = floatToMIDI(controlFader.values.x)
  end

  --print('Current MIDI values:', unpack(ccValues))

  local defaultManager = root.children.default_manager
  defaultManager:notify('store_defaults', {fxNum, ccValues})
end

local function handleDelete(value)
  local presetManager = root.children.preset_manager
  presetManager:notify('delete_preset', {fxNum, value})
  self.parent:notify('refresh_presets_list')
end

function onValueChanged(key, value)
  --print('onValueChanged called:', key, value)
  -- Interpret button presses as a child button
  if (key == 'x' and self.values.x == 1 and self.name ~= 'perform_preset_grid') then
    -- We're in child scope, so use parent's tag
    busNum = tonumber(self.parent.parent.parent.parent.tag ~= "" and self.parent.parent.parent.parent.tag or 0) + 1
    if (Color.toHexString(self.color) == BUTTON_STATE_COLORS.DELETE) then
      handleDelete(self.index)
    elseif (Color.toHexString(self.color) == getRecallButtonColor(busNum)) then
      local performRecallProxy = self.parent.parent.parent:findByName('perform_recall_proxy', true)
      performRecallProxy:notify('recall_preset', self.index)
    else
      storeFXPreset(self.index)
    end
  end
end

local function toggleDeleteMode(value)
  --print('toggleDeleteMode called:', value)
  deleteMode = value

  if self.name ~= 'perform_preset_grid' then
    busNum = tonumber(self.parent.parent.parent.parent.tag ~= "" and self.parent.parent.parent.parent.tag or 0) + 1
    -- I'm a child, so switch according to the new delete mode
    --print('I am a child, so switch according to the new delete mode', self.name)
    if Color.toHexString(self.color) == getRecallButtonColor(busNum) or Color.toHexString(self.color) == BUTTON_STATE_COLORS.DELETE then
      --print('I am a button that needs to be switched', self.name)
      if deleteMode then
        self.color = BUTTON_STATE_COLORS.DELETE
      else
        self.color = getRecallButtonColor(busNum)
      end
    end
  else
    --print('I am a parent, so notify the ableton push handler')
    for i = 1, #self.children do
      self.children[i]:notify('toggle_delete_mode', deleteMode)
    end

    if abletonFourBusMode and tonumber(busNum) <= 4 then
      local abletonPushHandler = root:findByName('ableton_push_handler', true)
      abletonPushHandler:notify('toggle_delete_mode', deleteMode)
    end
  end
end

local function refreshPresets()
  local presetManager = root.children.preset_manager
  local presetManagerChild = presetManager.children[tostring(fxNum)]
  local presetArray = json.toTable(presetManagerChild.tag) or {}

  initializeButtons(self)

  -- Set STORED state for active presets
  for index, _ in pairs(presetArray) do
    local presetNum = tonumber(index)
    if deleteMode then
      changeState(self, presetNum, BUTTON_STATE_COLORS.DELETE)
    else
      changeState(self, presetNum, getRecallButtonColor(busNum))
    end
  end

  busNum = tonumber(self.parent.parent.parent.tag ~= "" and self.parent.parent.parent.tag or 0) + 1
  --print('Bus number:', busNum, 'for', self.name)

  if abletonFourBusMode and tonumber(busNum) <= 4 then
    --print('Sending illuminate_presets to ableton_push_handler', busNum, fxNum, deleteMode)
    local abletonPushHandler = root:findByName('ableton_push_handler', true)
    abletonPushHandler:notify('illuminate_presets', {tonumber(busNum), fxNum, deleteMode})
  end
end

function onReceiveNotify(key, value)
  if key == 'init_presets_list' then
    fxNum = value
    for i = 1, #self.children do
      self.children[i]:notify('change_fx_num', fxNum)
    end
    refreshPresets()
  elseif key == 'refresh_presets_list' then
    refreshPresets()
  elseif key == 'change_fx_num' then
    fxNum = value
  elseif key == 'toggle_delete_mode' then
    toggleDeleteMode(value)
  end
end

function init()
  if self.name == 'perform_preset_grid' then
    self.outline = true
    self.outlineStyle = OutlineStyle.FULL

    initializeButtons(self)
  end
end
]]

function init()
  --print('Outer init called')
  local debugMode = root:findByName('debug_mode').values.x
  --print('Debug mode:', debugMode)
  if debugMode == 1 then
    local performPresetGrids = root:findAllByName('perform_preset_grid', true)
    --print('Found', #performPresetGrids, 'preset grids')

    for index, performPresetGrid in ipairs(performPresetGrids) do
      --print('Loading script for perform preset grid', index)
      performPresetGrid.script = performPresetGridScript
    end
  end
end
