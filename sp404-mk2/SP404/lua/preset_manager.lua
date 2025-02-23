------------------
-- PRESET HANDLING
------------------
local function formatPresetNum(num)
  return string.format("%02d", num)
end

local childScript = [[
function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
      print('Current preset values:', self.tag)
  end
end
]]

local function storePreset(fxNum, presetNum, presetValue)

  local presetArray = json.toTable(self.children[tostring(fxNum)].tag) or {}

  if presetValue == nil then
    print('Deleting preset:', fxNum, presetNum)
  else
    print('Storing preset:', fxNum, presetNum, 'with values:', table.unpack(presetValue))
  end

  presetArray[formatPresetNum(presetNum)] = presetValue

  local jsonPresets = json.fromTable(presetArray)
  self.children[tostring(fxNum)].tag = jsonPresets
  print('Updated presets array (json):', jsonPresets)

end

local function recallPreset(fxNum, presetNum)
  print('Preset manager recalling preset:', fxNum, presetNum)
  local presetArray = json.toTable(self.children[tostring(fxNum)].tag) or {}
  return presetArray[formatPresetNum(presetNum)]

end

local function deletePreset(fxNum, presetNum)
  print('Preset manager deleting preset:', fxNum, presetNum)
  storePreset(fxNum, presetNum, nil)

end

local function deleteAllPresets(fxNum)
  print('Preset manager deleting all presets for FX:', fxNum)
  self.children[tostring(fxNum)].tag = ''
end

local function deleteAllPresetsForAllFX()
  for fxNum = 1, 46 do
    deleteAllPresets(fxNum)
  end
end

local function storedPresetsPerFX(fxNum)
  print('Preset manager getting stored presets for FX:', fxNum)
  local presetArray = json.toTable(self.children[tostring(fxNum)].tag) or {}

  print('Returning stored presets for FX:', fxNum, table.unpack(presetArray))
  return presetArray

end

local function assignChildScripts()
  for i = 1, #self.children do
    self.children[tostring(i)].script = childScript
  end
end

---@diagnostic disable: lowercase-global
function init()
  print('Initialising preset manager')
  assignChildScripts()
end

-- TODO: change the handling so it writes the values to the
-- children of the preset manager
function onReceiveOSC(message, connections)

  local path = message[1]
  local arguments = message[2]
  local presetJSON = arguments[1].value

  print('Received OSC message:', path, 'with preset JSON:', presetJSON)
  self.tag = presetJSON
end

function onReceiveNotify(key, value)

  print('preset_manager received notification:', key, value)

  if key == 'store_preset' then

    local fxNum = value[1]
    local presetNum = value[2]
    local ccValues = value[3]
    print('Storing preset:', fxNum, presetNum, 'with values:', table.unpack(ccValues))
    storePreset(fxNum, presetNum, ccValues)

  elseif key == 'recall_preset' then
    print('preset_manager received recall_preset notification')

    local fxNum = value[1]
    local presetNum = value[2]
    local result = recallPreset(fxNum, presetNum)
    print('recall_preset result:', table.unpack(result))

    local recallProxy = root.children.recall_proxy
    recallProxy:notify('recall_preset_response', {fxNum, result})

  elseif key == 'delete_preset' then

    local fxNum = value[1]
    local presetNum = value[2]

    deletePreset(fxNum, presetNum)

  elseif key == 'delete_all_presets' then

    local fxNum = value
    deleteAllPresets(fxNum)

  elseif key == 'delete_all_presets_for_all_fx' then

    deleteAllPresetsForAllFX()

  elseif key == 'stored_presets_list' then

    local fxPresetGrid = value[1]
    local fxNum = value[2]

    local storedPresets = storedPresetsPerFX(fxNum)

    print('Returning stored presets list to:', fxPresetGrid.name, table.unpack(storedPresets))
    fxPresetGrid:notify('stored_presets_list', storedPresets)

  end
end