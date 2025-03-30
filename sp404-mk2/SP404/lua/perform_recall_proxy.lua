local performRecallProxyScript = [[

local controlsInfo = root.children.controls_info

local function midiToFloat(midiValue)
  local floatValue = midiValue / 127
  return floatValue
end

local function recallPreset(fxNum, ccValues)

  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)
  print('controlInfoArray:', controlInfoArray)

  print('Recalling MIDI values:', unpack(ccValues))

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
      controlFader:notify('new_value', midiToFloat(ccValues[i]))
    end
  end
  print('Recalled MIDI values:', unpack(ccValues))
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
  if key == 'recall_preset_response' then
    print('proxy received recall_preset_response')
    local fxNum = value[1]
    local values = value[2]

    recallPreset(fxNum, values)
  elseif key == 'return_values_to_perform' then
    print('proxy received return_values_to_perform')
    returnValuesToPerform(value)
  end
end

]]

function init()
  local performRecallProxies = root:findAllByName('perform_recall_proxy', true)
  for _, performRecallProxy in ipairs(performRecallProxies) do
    performRecallProxy.script = performRecallProxyScript
  end
end
