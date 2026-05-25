-- Per-instance: bus index and MIDI channel are derived from self.name (bus1_group … bus5_group).
-- Bus chrome colours are applied by root.lua (apply_bus_theme notify on root).
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

-- sceneLoad: skip recallValues + switch_to_effect (scene recall applies CC/on-off itself).
local function showBus(sceneLoad)

  effectChooser.children.label.values.text = fxName
  controlGroup.visible = true

  refreshPresetList()

  -- init_perform injects fader scripts and notifies each control_fader 'initialise' (resolves
  -- sync_fader -> linked fader reference). Do not initialise before that: the old script
  -- would be replaced and the new closure would never get syncedFader set.
  controlMapper:notify('init_perform', {fxNum, midiChannel, faders})
  onOffButtonGroup:notify('set_settings', { fxNum, midiChannel, fxName })
  if not sceneLoad then
    recallValues()
    onOffButtonGroup:notify('switch_to_effect')
  end
end

local function sendOffMIDI()
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, 0 }, { true, false, false })
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

  if onOffButtonGroup then
    onOffButtonGroup:notify("set_grab_state", false)
    onOffButtonGroup:notify("set_state", false)
  end

  local bcrCh = tonumber(faders.tag)
  if bcrCh and controlMapper then
    controlMapper:notify('bcr_zero_slots', { bcrCh, 1, 6 })
  end
  presetGrid:notify('clear_presets')
end

local function setSelectedBusHighlight(isSelected)
  local bg = effectChooser:findByName("background", true) or effectChooser.children.background
  if not bg then return end
  if isSelected then
    bg.color = Color.fromHexString("FFA61AFF")
  else
    root:notify("apply_bus_theme", busNum)
  end
end

---@diagnostic disable: lowercase-global
local function applyFx(fxNumIn, fxNameIn, sceneLoad)
  fxNum = tonumber(fxNumIn) or 0
  fxName = fxNameIn or "Choose FX..."
  if fxNum == 0 then
    clearBus()
    return
  end
  self.tag = json.fromTable({ fxNum = fxNum, fxName = fxName, busNum = busNum })
  print("set_fx", busNum, fxNum, fxName, sceneLoad and "scene" or "")
  showBus(sceneLoad == true)
end

-- value[3] = showChooser (boolean, optional): true = open FX chooser, false = close, nil = leave as-is.
-- value[4] = sceneLoad (boolean, optional): true = scene recall (skip recent-value recall + switch_to_effect).
local function applyChooserVisibility(showChooser)
  if showChooser == nil or not fxSelectorGroup then
    return
  end
  if showChooser then
    fxSelectorGroup:notify("show", busNum)
  else
    fxSelectorGroup:notify("hide")
  end
end

function onReceiveNotify(key, value)
  if (key == "set_fx") then
    applyFx(value[1], value[2], value[4] == true)
    applyChooserVisibility(value[3])
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

  presetGrid.tag = busNum

  -- BCR2000 (shared MIDI port): buses 1–4 → channels 6–9, bus 5 → channel 10 (index 4+busNum).
  local bcrMIDIChannel = 4 + busNum
  faders.tag = tostring(bcrMIDIChannel)
  onOffButtonGroup.tag = tostring(bcrMIDIChannel)
  effectChooser.tag = tostring(bcrMIDIChannel)

  if fxNum ~= 0 then
    showBus()
  else
    clearBus()
  end

  root:notify("apply_bus_theme", busNum)
end
