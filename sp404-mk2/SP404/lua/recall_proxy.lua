local controlsInfo = root.children.controls_info
local performRecallProxy = nil

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
  print('Recall proxy recalling preset:', fxNum, presetNum, unpack(presetArray))
  local presetValues = presetArray[formatPresetNum(presetNum)]

  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)
  print('controlInfoArray:', controlInfoArray)

  print('Recalling MIDI values:', unpack(presetValues))

  local fxPage = root.children.control_pager.children[fxNum]
  local controlGroup = fxPage.children.control_group

  local exclude_marked_presets = false

  if controlGroup.tag == '1' then
    print('Excluding marked presets')
    exclude_marked_presets = true
  end

  for i, controlInfo in ipairs(controlInfoArray) do
    local _, controlName, isExcludable = unpack(controlInfo)

    local controlObject = controlGroup:findByName(controlName, true)

    print(i, controlObject.name, controlObject.type, isExcludable, exclude_marked_presets)

    if not isExcludable or not exclude_marked_presets then
      controlObject:notify('new_value', midiToFloat(presetValues[i]))
    end
  end
  print('Recalled MIDI values:', unpack(presetValues))
end

local function recallDefaults()

  local defaultManager = root.children.default_manager
  local defaultValues = json.toTable(defaultManager.children[tostring(fxNum)].tag) or {0, 0, 0, 0, 0, 0}
  print('Recall proxy recalling defaults:', fxNum, unpack(defaultValues))

  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)
  print('controlInfoArray:', controlInfoArray)

  print('Recalling MIDI values:', unpack(defaultValues))

  local fxPage = root.children.control_pager.children[fxNum]
  local controlGroup = fxPage.children.control_group

  local exclude_marked_presets = false

  if controlGroup.tag == '1' then
    print('Excluding marked defaults')
    exclude_marked_presets = true
  end

  for i, controlInfo in ipairs(controlInfoArray) do
    local _, controlName, isExcludable = unpack(controlInfo)

    local controlObject = controlGroup:findByName(controlName, true)

    print(i, controlObject.name, controlObject.type, isExcludable, exclude_marked_presets)

    if not isExcludable or not exclude_marked_presets then
      controlObject:notify('new_value', midiToFloat(defaultValues[i]))
    end
  end
  print('Recalled MIDI values:', unpack(defaultValues))
end

local function setCurrentValues(values)
  print('Setting current values:', unpack(values))
  local fxPage = root.children.control_pager.children[fxNum]
  local controlGroup = fxPage.children.control_group
  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)

  for i, controlInfo in ipairs(controlInfoArray) do
    local _, controlName, _ = unpack(controlInfo)

    local controlObject = controlGroup:findByName(controlName, true)
    controlObject:notify('new_value', values[i])
  end
end

local function returnValuesToPerform()
  print('Returning values to perform')
  local values = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0}
  local fxPage = root.children.control_pager.children[fxNum]
  local controlGroup = fxPage.children.control_group
  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)

  for i, controlInfo in ipairs(controlInfoArray) do
    local _, controlName, _ = unpack(controlInfo)

    local controlObject = controlGroup:findByName(controlName, true)
    values[i] = controlObject.values.x
  end
  if performRecallProxy then
    performRecallProxy:notify('return_values_to_perform', values)
  end
end

function onReceiveNotify(key, value)
  if key == 'recall_preset' then
    print('proxy received recall_preset')
    local presetNum = value

    recallPreset(presetNum)
  elseif key == 'set_current_values' then
    print('proxy received set_current_values')
    fxNum = value[1]
    local values = value[2]
    performRecallProxy = value[3]
    setCurrentValues(values)
  elseif key == 'return_values_to_perform' then
    print('proxy received return_values_to_perform')
    returnValuesToPerform()
  elseif key == 'recall_defaults' then
    print('proxy received recall_defaults')
    recallDefaults()
  end
end