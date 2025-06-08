local performPresetGridScript = [[
local fxNum = 1
local busNum = self.tag
local deleteMode = false
local defaultCCValues = {0, 0, 0, 0, 0, 0}

local BUTTON_STATE_COLORS = {
  RECALL = "00FF00FF",
  AVAILABLE = "FFFFFFFF",
  DELETE = "FF0000FF"
}

local function initializeButtons(grid)
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

  print('Current MIDI values:', unpack(ccValues))

  local presetManager = root.children.preset_manager
  presetManager:notify('store_preset', {fxNum, presetNum, ccValues})
  self.parent:notify('init_presets_list', fxNum)
end

local function handleDelete(value)
  local presetManager = root.children.preset_manager
  presetManager:notify('delete_preset', {fxNum, value})
  self.parent:notify('init_presets_list', fxNum)
end

function onValueChanged(key, value)
  --print('onValueChanged called:', key, value)
  -- Interpret button presses as a child button
  if (key == 'x' and self.values.x == 1 and self.name ~= 'perform_preset_grid') then
    print('Button press detected on child:', self.index)
    -- We're in child scope, so use parent's tag

    if (Color.toHexString(self.color) == BUTTON_STATE_COLORS.DELETE) then
      handleDelete(self.index)
    elseif (Color.toHexString(self.color) == BUTTON_STATE_COLORS.RECALL) then
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
    -- I'm a child, so switch according to the new delete mode
    --print('I am a child, so switch according to the new delete mode', self.name)
    if Color.toHexString(self.color) == BUTTON_STATE_COLORS.RECALL or Color.toHexString(self.color) == BUTTON_STATE_COLORS.DELETE then
      --print('I am a button that needs to be switched', self.name)
      if deleteMode then
        self.color = BUTTON_STATE_COLORS.DELETE
      else
        self.color = BUTTON_STATE_COLORS.RECALL
      end
    end
  else
    --print('I am a parent, so notify the ableton push handler')
    for i = 1, #self.children do
      self.children[i]:notify('toggle_delete_mode', deleteMode)
    end
    local abletonPushHandler = root:findByName('ableton_push_handler', true)
    abletonPushHandler:notify('toggle_delete_mode', deleteMode)
  end
end

function onReceiveNotify(key, value)
  --print('onReceiveNotify called:', key, value)
  if key == 'init_presets_list' and self.name == 'perform_preset_grid' then
    print('Handling init_presets_list')
    -- Handle the response to our initialisation request
    fxNum = value

    print('init_presets_list', fxNum)

    if fxNum ~= '0' then
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
          changeState(self, presetNum, BUTTON_STATE_COLORS.RECALL)
        end
      end
      print('presetArray', presetManagerChild.tag)
      local abletonPushHandler = root:findByName('ableton_push_handler', true)
      abletonPushHandler:notify('illuminate_presets', {tonumber(busNum), fxNum, deleteMode})
    end
  elseif key == 'toggle_delete_mode' then
    toggleDeleteMode(value)
  end
end

function init()
  -- Only run init on the grid itself, not on child buttons
  if self.name == 'perform_preset_grid' then
    self.outline = true
    self.outlineStyle = OutlineStyle.FULL
    initializeButtons(self)
  end
end
]]

function init()
  print('Outer init called')
  local debugMode = root:findByName('debug_mode').values.x
  print('Debug mode:', debugMode)
  if debugMode == 1 then
    local performPresetGrids = root:findAllByName('perform_preset_grid', true)
    print('Found', #performPresetGrids, 'preset grids')

    for index, performPresetGrid in ipairs(performPresetGrids) do
      print('Loading script for perform preset grid', index)
      performPresetGrid.script = performPresetGridScript
    end
  end
end
