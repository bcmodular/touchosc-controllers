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

local function parameterMidiAt(parameters, index)
  if type(parameters) ~= "table" then
    return 0
  end
  return tonumber(parameters[index] or parameters[tostring(index)]) or 0
end

local function findRecentParameters(fxNumIn)
  local recentValues = json.toTable(root.children.recent_values.tag) or {}
  local stack = recentValues[busNum] or recentValues[tostring(busNum)]
  if type(stack) ~= "table" then
    return nil
  end
  local targetFx = tonumber(fxNumIn)
  for i = 1, #stack do
    local effect = stack[i]
    if type(effect) == "table" and tonumber(effect.fxNum) == targetFx then
      return effect.parameters
    end
  end
  for _, effect in pairs(stack) do
    if type(effect) == "table" and tonumber(effect.fxNum) == targetFx then
      return effect.parameters
    end
  end
  return nil
end

local function refreshPresetList()
  if fxNum ~= 0 then
    presetGrid:notify('refresh_presets_list', fxNum)
  end
end

local function recallValues(pushMidi)
  local fullDefaults = json.toTable(root.children.default_manager.tag)
  local defaultValues = fullDefaults[tostring(fxNum)] or {0, 0, 0, 0, 0, 0}
  local recentParams = findRecentParameters(fxNum)
  local valuesToRecall = {}
  local source = recentParams or defaultValues
  for i = 1, 6 do
    valuesToRecall[i] = parameterMidiAt(source, i)
  end

  for i = 1, 6 do
    local fader = faders:findByName(tostring(i))
    local controlFader = fader and fader:findByName('control_fader')
    if controlFader then
      local recalledFloat = midiToFloat(parameterMidiAt(valuesToRecall, i))
      controlFader:setValueField("x", ValueField.DEFAULT, midiToFloat(parameterMidiAt(defaultValues, i)))
      controlFader:setValueField("x", ValueField.CURRENT, recalledFloat)
      if pushMidi and fader.visible then
        controlFader:notify("new_value", recalledFloat)
      end
    end
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
    recallValues(false)
    onOffButtonGroup:notify('switch_to_effect')
    -- SP-404 applies effect after CC 83 pulse; push defaults/recent after select (scene_manager pattern).
    recallValues(true)
  end
  presetGrid:notify('sync_morph_ui', busNum)
end

local function sendOffMIDI()
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, 0 }, { true, false, false })
end

local function storeCurrentValues()
  if fxNum == 0 then
    return
  end
  local currentValues = {}
  for i = 1, 6 do
    local faderGroup = faders:findByName(tostring(i))
    if faderGroup and faderGroup.visible then
      local controlFader = faderGroup:findByName('control_fader')
      if controlFader then
        currentValues[i] = floatToMIDI(controlFader.values.x)
      end
    end
  end
  root.children.recent_values:notify('update_recent_values', { busNum, fxNum, currentValues })
end

local function clearBus()
  if isBusLocked(busNum) then
    return
  end
  storeCurrentValues()
  controlGroup.visible = false
  fxNum = 0
  fxName = "Choose FX..."
  local tag = json.toTable(self.tag) or {}
  tag.fxNum = fxNum
  tag.fxName = fxName
  tag.busNum = busNum
  if tag.morphEnabled == nil then
    tag.morphEnabled = false
  end
  if tag.morphAmount == nil then
    tag.morphAmount = 0
  end
  self.tag = json.fromTable(tag)

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
  presetGrid:notify('sync_morph_ui', busNum)
end

---@diagnostic disable: lowercase-global
local function applyFx(fxNumIn, fxNameIn, sceneLoad)
  local newFxNum = tonumber(fxNumIn) or 0
  local newFxName = fxNameIn or "Choose FX..."
  if newFxNum == 0 then
    clearBus()
    return
  end

  if not sceneLoad and fxNum ~= 0 then
    storeCurrentValues()
  end

  fxNum = newFxNum
  fxName = newFxName
  local tag = json.toTable(self.tag) or {}
  tag.fxNum = fxNum
  tag.fxName = fxName
  tag.busNum = busNum
  if tag.morphEnabled == nil then
    tag.morphEnabled = false
  end
  if tag.morphAmount == nil then
    tag.morphAmount = 0
  end
  self.tag = json.fromTable(tag)
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
  end
end

function init()
  local settings = {}
  settings = json.toTable(self.tag) or {}

  busNum = tonumber(self.name:match("bus(%d+)_group")) or 1
  midiChannel = busNum - 1

  fxNum = tonumber(settings.fxNum) or 0
  fxName = settings.fxName or 'Choose FX...'

  local tag = json.toTable(self.tag) or {}
  tag.fxNum = fxNum
  tag.fxName = fxName
  tag.busNum = busNum
  if tag.morphEnabled == nil then
    tag.morphEnabled = false
  end
  if tag.morphAmount == nil then
    tag.morphAmount = 0
  end
  self.tag = json.fromTable(tag)

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
