------------------
-- PRESET HANDLING
------------------
function storePreset(presetIndex, presetValue)

  local presetArray = json.toTable(self.tag)
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
  
  local presetArray = json.toTable(self.tag)
  return presetArray[presetIndex]

end

function deletePreset(presetIndex)
  
  storePreset(presetIndex, nil)

end

function storedPresetsPerFX(fxNum)
  
  local result = {}
  local presetArray = json.toTable(self.tag)
  
  if presetArray == {} or presetArray == nil then
    return result
  end

  for key, _ in pairs(presetArray) do
    local fx, x = key:match("^(%d+) (%d+)$")
    if tonumber(fx) == fxNum then
      result[x] = true
    end
  
  end
  print('Returning stored presets for FX:', fxNum, unpack(result))
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
    print('preset_manager received recall_preset notification')
    
    local midiChannel = value[1]
    local presetIndex = value[2]
    local result = recallPreset(presetIndex)
    print('recall_preset result:', unpack(result))
    
    local recallProxy = root.children.recall_proxy
    recallProxy:notify('recall_preset_response', {midiChannel, presetIndex, result})
    
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

function initFXPresetHandler()
  local fxPresetHandler = root.children.fx_preset_handler

  local fxNum = root.children.control_pager.values.page + 1
  
  if fxNum <= 46 then
    print('Initialising preset manager for FX:', fxNum)
    fxPresetHandler:notify('change_fx', fxNum)
  end
end

function init()
  initFXPresetHandler()
end

function onReceiveOSC(message, connections)
  local path = message[1]
  local arguments = message[2]
  local presetJSON = arguments[1].value
  
  print('Received OSC message:', path, 'with preset JSON:', presetJSON)
  self.tag = presetJSON
  
  initFXPresetHandler()
end