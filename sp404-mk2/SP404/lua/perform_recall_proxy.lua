local performRecallProxyScript = [[

local controlsInfo = root.children.controls_info
local fxNum = 1

local function formatPresetNum(num)
  return string.format("%02d", num)
end

local function midiToFloat(midiValue)
  local floatValue = midiValue / 127
  return floatValue
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

local function recallDefaults()

  local defaultManager = root.children.default_manager
  local defaultValues = json.toTable(defaultManager.children[tostring(fxNum)].tag) or {0, 0, 0, 0, 0, 0}
  print('Perform recall proxy recalling defaults:', fxNum, unpack(defaultValues))

  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)
  print('controlInfoArray:', controlInfoArray)

  print('Recalling MIDI values:', unpack(defaultValues))

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
      controlFader:notify('new_value', midiToFloat(defaultValues[i]))
    end
  end
  print('Recalled MIDI values:', unpack(defaultValues))
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
    fxNum = value
  elseif key == 'recall_defaults' then
    print('proxy received recall_defaults')
    recallDefaults()
  end
end

]]

function init()
  local performRecallProxies = root:findAllByName('perform_recall_proxy', true)
  for _, performRecallProxy in ipairs(performRecallProxies) do
    performRecallProxy.script = performRecallProxyScript
  end
end
