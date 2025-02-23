local controlsInfo = root.children.controls_info

local function midiToFloat(midiValue)
  local floatValue = midiValue / 127
  return floatValue
end

local function recallPreset(fxNum, ccValues)

  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)
  print('controlInfoArray:', controlInfoArray)

  print('Recalling MIDI values:', table.unpack(ccValues))

  local fxPage = root.children.control_pager.children[fxNum]
  local controlGroup = fxPage.children.control_group

  local exclude_marked_presets = false

  if controlGroup.tag == '1' then
    print('Excluding marked presets')
    exclude_marked_presets = true
  end

  for i, controlInfo in ipairs(controlInfoArray) do
    local ccNumber, controlName, isExcludable = table.unpack(controlInfo)

    local controlObject = controlGroup:findByName(controlName, true)

    print(i, controlObject.name, controlObject.type, isExcludable, exclude_marked_presets)

    if not isExcludable or not exclude_marked_presets then
      controlObject:notify('new_value', midiToFloat(ccValues[i]))
    end
  end
  print('Recalled MIDI values:', table.unpack(ccValues))
end

---@diagnostic disable: lowercase-global
function onReceiveNotify(key, value)
  if key == 'recall_preset_response' then
    print('proxy received recall_preset_response')
    local fxNum = value[1]
    local values = value[2]

    recallPreset(fxNum, values)
  end
end