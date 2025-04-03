local performRecallProxyScript = [[

local controlsInfo = root.children.controls_info
local fxNum = 1
local channel = 1

local function formatPresetNum(num)
  return string.format("%02d", num)
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

  local presetManager = root.children.preset_manager
  local presetArray = json.toTable(presetManager.children[tostring(fxNum)].tag) or {}
  print('Perform recall proxy recalling preset:', fxNum, presetNum, unpack(presetArray))
  local presetValues = presetArray[formatPresetNum(presetNum)]

  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)
  print('controlInfoArray:', controlInfoArray)

  print('Recalling MIDI values:', unpack(presetValues))

  local faders = self.parent:findByName('faders', true)

  local exclude_marked_presets = false

  -- TODO: Add this back in
  -- if faders.tag == '1' then
  --   print('Excluding marked presets')
  --   exclude_marked_presets = true
  -- end

  for i, controlInfo in ipairs(controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)

    local faderGroup = faders:findByName(tostring(i))
    local controlFader = faderGroup:findByName('control_fader')

    print(i, controlFader.name, isExcludable, exclude_marked_presets)

    if not isExcludable or not exclude_marked_presets then
      controlFader:notify('new_value', midiToFloat(presetValues[i]))
    end
  end
  print('Recalled MIDI values:', unpack(presetValues))
end


local function getRecentValuesForBus(channel)

  local recentValues = json.toTable(root.children.recent_values.tag) or {}
  local recentValuesForBus = recentValues[tostring(channel)] or {}

  return recentValuesForBus
end

local function getEffectParametersFromBus(channel, fxNum)
  local recentValuesForBus = getRecentValuesForBus(channel)

  for _, effect in ipairs(recentValuesForBus) do
    if effect.id == fxNum then
      return effect.parameters
    end
  end

  return nil
end

local function recallValues(useDefaults)

  local defaultManager = root.children.default_manager
  local valuesToRecall = json.toTable(defaultManager.children[tostring(fxNum)].tag) or {0, 0, 0, 0, 0, 0}

  if not useDefaults then
    local recentValues = getEffectParametersFromBus(channel, fxNum)

    if recentValues then
      valuesToRecall = recentValues
    end
  end

  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)
  print('controlInfoArray:', controlInfoArray)

  print('Recalling MIDI values:', unpack(valuesToRecall))

  local faders = self.parent:findByName('faders', true)

  local exclude_marked_presets = false

  -- TODO: Add this back in
  -- if faders.tag == '1' then
  --   print('Excluding marked presets')
  --   exclude_marked_presets = true
  -- end

  for i, controlInfo in ipairs(controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)

    local faderGroup = faders:findByName(tostring(i))
    local controlFader = faderGroup:findByName('control_fader')

    print(i, controlFader.name, isExcludable, exclude_marked_presets)

    if not isExcludable or not exclude_marked_presets then
      controlFader:notify('new_value', midiToFloat(valuesToRecall[i]))
    end
  end
  print('Recalled MIDI values:', unpack(valuesToRecall))
end

local function returnValuesToPerform(values)
  print('Returning values to perform:', unpack(values))
  local faders = self.parent:findByName('faders', true)
  for i = 1, 6 do
    local faderGroup = faders:findByName(tostring(i))
    local controlFader = faderGroup:findByName('control_fader')
    controlFader:notify('new_value', values[i])
  end
end

local function storeCurrentValues()
  print('Storing current values')
  local faders = self.parent:findByName('faders', true)
  local currentValues = {}
  for i = 1, 6 do
    local faderGroup = faders:findByName(tostring(i))
    local controlFader = faderGroup:findByName('control_fader')
    currentValues[i] = floatToMIDI(controlFader.values.x)
  end
  local recentValues = root.children.recent_values
  recentValues:notify('store_current_values', {channel, fxNum, currentValues})
  print('Current values:', unpack(currentValues))
end

function onReceiveNotify(key, value)
  if key == 'recall_preset' then
    print('proxy received recall_preset')
    local presetNum = value

    recallPreset(presetNum)
  elseif key == 'return_values_to_perform' then
    print('proxy received return_values_to_perform')
    returnValuesToPerform(value)
  elseif key == 'set_settings' then
    print('proxy received set_settings: ', value)
    fxNum = value[1]
    channel = value[2]
  elseif key == 'recall_defaults' then
    print('proxy received recall_defaults')
    recallValues(true)
  elseif key == 'recall_recent_values' then
    print('proxy received recall_recent_values')
    recallValues(false)
  elseif key == 'store_current_values' then
    print('proxy received store_current_values')
    storeCurrentValues()
  end
end

]]

function init()
  local performRecallProxies = root:findAllByName('perform_recall_proxy', true)
  for _, performRecallProxy in ipairs(performRecallProxies) do
    performRecallProxy.script = performRecallProxyScript
  end
end
