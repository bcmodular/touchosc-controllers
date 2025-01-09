------------------
-- PRESET HANDLING
------------------

local presetArray

function storePreset(presetIndex, presetValue)

  presetArray[presetIndex] = presetValue
  
  if presetValue == nil then
    print('Deleting preset:', presetIndex)
  else
    print('Storing preset:', presetIndex, 'with values:', unpack(presetValue))
  end
  
  local jsonPresets = json.fromTable(presetArray)
  self.tag = jsonPresets
  print('Updated presets array (json):', jsonPresets)
  
end

function recallPreset(presetIndex)
  
  return presetArray[presetIndex]

end

function deletePreset(presetIndex)
  
  storePreset(presetIndex, nil)

end

function storedPresetsPerFX(fxNum)
  
  local result = {}
  
  if presetArray == {} or presetArray == nil then
    return result
  end

  for key, _ in pairs(presetArray) do
    local fx, x = key:match("^(%d+) (%d+)$")
    if tonumber(fx) == fxNum then
      result[x] = true
    end
  
  end
  
  return result
  
end

function onReceiveNotify(key, value)
  if type(value) == "table" then
    print('onReceiveNotify called with key:', key, 'value:', unpack(value))
  else
    print('onReceiveNotify called with key:', key, 'value:', value)
  end

  if key == 'store_preset' then
    
    local presetIndex = value[1]
    local ccValues = value[2]
    print('Storing preset:', presetIndex, 'with values:', unpack(ccValues))
    storePreset(presetIndex, ccValues)
  
  elseif key == 'recall_preset' then
  
    local midiHandler = value[1]
    local presetIndex = value[2]
    local result = recallPreset(presetIndex)
    
    print('Notifying midiHandler:', midiHandler.name, 'to recall preset:', presetIndex, 'with values:', unpack(result))
    midiHandler:notify('recall_preset', result)
    
  elseif key == 'delete_preset' then
  
    local presetIndex = value
    
    deletePreset(presetIndex)
    
  elseif key == 'stored_presets_list' then
  
    local fxPresetGrid = value[1]
    local fxNum = value[2]
    
    local storedPresets = storedPresetsPerFX(fxNum)
    
    print('Returning stored presets list to:', fxPresetGrid.name, unpack(storedPresets))
    fxPresetGrid:notify('stored_presets_list', storedPresets)
    
  end
end

function init()
  
  local fxPresetHandler = root.children.fx_preset_handler

  if self.tag ~= '' then
    print('Initialising presetArray with:', self.tag)
    presetArray = json.toTable(self.tag)
  else
    presetArray = {}
  end
  
  local fxNum
  
  -- To be updated as more FX are implemented
  -- EDIT HERE
  if root.children.control_pager.values.page < 7 then
    fxNum = root.children.control_pager.values.page + 1
  else
    fxNum = 1
  end
  
  print('Initialising preset manager for FX:', fxNum)

  fxPresetHandler:notify('change_fx', fxNum)
  
end