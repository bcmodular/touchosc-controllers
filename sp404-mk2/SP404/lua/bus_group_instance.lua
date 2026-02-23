local busNum = 1
local midiChannel = 0
local fxNum = 0
local fxName = 'Choose FX...'
local effectChooser = self:findByName('effect_chooser', true)
local controlGroup = self:findByName('control_group', true)
local presetGrid = self:findByName('preset_grid', true)
local controlMapper = root:findByName('control_mapper', true)
local faders = self:findByName('faders', true)
local onOffButtonGroup = self:findByName('on_off_button_group', true)
local fxSelectorGroup = root:findByName('fx_selector_group', true)

local function midiToFloat(midiValue)
  local floatValue = midiValue / 127
  return floatValue
end

local function floatToMIDI(floatValue)
  local midiValue = math.floor(floatValue * 127 + 0.5)
  return midiValue
end

local function refreshPresetList()
  if fxNum ~= 0 then
    presetGrid:notify('refresh_presets_list', fxNum)
  end
end

local function recallValues()

  local fullDefaults = json.toTable(root.children.default_manager.tag)
  local defaultValues = fullDefaults[tostring(fxNum)] or {0, 0, 0, 0, 0, 0}
  local valuesToRecall = defaultValues

  local recentValues = json.toTable(root.children.recent_values.tag) or {}
  local recentValuesForBus = recentValues[busNum] or {}

  -- If we have recent values for this bus, use them
  for _, effect in ipairs(recentValuesForBus) do
    if effect.fxNum == fxNum then
      valuesToRecall = effect.parameters
    end
  end

  for i = 1, 6 do
    local fader = faders:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')
    controlFader:setValueField("x", ValueField.DEFAULT, midiToFloat(defaultValues[i]))
    controlFader:setValueField("x", ValueField.CURRENT, midiToFloat(valuesToRecall[i]))
  end
end

local function showBus()

  effectChooser.children.label.values.text = fxName
  controlGroup.visible = true

  for i = 1, 6 do
    local fader = faders:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')
    controlFader:notify('initialise')
  end

  refreshPresetList()

  controlMapper:notify('init_perform', {fxNum, midiChannel, faders})
  onOffButtonGroup:notify('set_settings', {fxNum, midiChannel})
  recallValues()
  onOffButtonGroup:notify('switch_to_effect')
end

local function sendOffMIDI()
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, 0 })
end

local function storeCurrentValues()
  if fxNum ~= nil then
    --print('Storing current values')
    local currentValues = {}
    for i = 1, 6 do
      local faderGroup = faders:findByName(tostring(i))
      local controlFader = faderGroup:findByName('control_fader')
      currentValues[i] = floatToMIDI(controlFader.values.x)
    end
    local recentValues = root.children.recent_values
    recentValues:notify('update_recent_values', {busNum, fxNum, currentValues})
    --print('Current values:', unpack(currentValues))
  else
    --print('No fxNum set, skipping storeCurrentValues')
  end
end

local function clearBus()
  storeCurrentValues()
  controlGroup.visible = false
  fxNum = 0
  fxName = "Choose FX..."
  self.tag = json.fromTable({fxNum = fxNum, fxName = fxName, busNum = busNum})

  effectChooser.children.label.values.text = fxName
  sendOffMIDI()
  presetGrid:notify('clear_presets')
end

local function setSelectedBusHighlight(isSelected)
  if isSelected then
    effectChooser.children.background.color = Color.fromHexString("FFA61AFF")
  else
    effectChooser.children.background.color = Color.fromHexString("FFA61AAA")
  end
end

---@diagnostic disable: lowercase-global
function onReceiveNotify(key, value)
  if (key == "set_fx") then
    fxNum = value[1]
    fxName = value[2]
    self.tag = json.fromTable({fxNum = fxNum, fxName = fxName, busNum = busNum})
    print('set_fx', busNum, fxNum, fxName)
    showBus()
    fxSelectorGroup:notify('toggle_visibility', busNum)
  elseif (key == "clear_bus") then
    clearBus()
  elseif (key == "set_bus_highlight") then
    setSelectedBusHighlight(value)
  end
end

function init()
  local settings = {}
  settings = json.toTable(self.tag) or {}

  busNum = tonumber(self.name:match("bus(%d+)_group")) or 1
  midiChannel = busNum - 1

  fxNum = tonumber(settings.fxNum) or 0
  fxName = settings.fxName or 'Choose FX...'

  self.tag = json.fromTable({fxNum = fxNum, fxName = fxName, busNum = busNum})

  effectChooser.children.selected_item_button.tag = busNum
  presetGrid.tag = busNum

  if fxNum ~= 0 then
    showBus()
  else
    clearBus()
  end
end
