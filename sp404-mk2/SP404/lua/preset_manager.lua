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
    --print('Deleting preset:', fxNum, presetNum)
  else
    --print('Storing preset:', fxNum, presetNum, 'with values:', unpack(presetValue))
  end

  presetArray[formatPresetNum(presetNum)] = presetValue

  local jsonPresets = json.fromTable(presetArray)
  self.children[tostring(fxNum)].tag = jsonPresets
  --print('Updated presets array (json):', jsonPresets)

  if fxNum == 37 then
    local editCompressorSidechain = root:findByName('edit_compressor_sidechain', true)
    editCompressorSidechain:notify('store_preset', presetNum)
  end
end

local function deletePreset(fxNum, presetNum)
  --print('Preset manager deleting preset:', fxNum, presetNum)
  storePreset(fxNum, presetNum, nil)

  if fxNum == 37 then
    local editCompressorSidechain = root:findByName('edit_compressor_sidechain', true)
    editCompressorSidechain:notify('delete_preset', presetNum)
  end
end

local function deleteAllPresets(fxNum)
  --print('Preset manager deleting all presets for FX:', fxNum)
  self.children[tostring(fxNum)].tag = ''
end

local function deleteAllPresetsForAllFX()
  for fxNum = 1, 46 do
    deleteAllPresets(fxNum)
  end

  local performPresetGrids = root:findAllByName('perform_preset_grid', true)
  for _, presetGrid in ipairs(performPresetGrids) do
    presetGrid:notify('refresh_presets_list')
  end
end

local function storedPresetsPerFX(fxNum)
  --print('Preset manager getting stored presets for FX:', fxNum)
  local presetArray = json.toTable(self.children[tostring(fxNum)].tag) or {}

  --print('Returning stored presets for FX:', fxNum, unpack(presetArray))
  return presetArray

end

local function assignChildScripts()
  for i = 1, #self.children do
    self.children[tostring(i)].script = childScript
  end
end

function init()
  assignChildScripts()
end

function onReceiveNotify(key, value)

  --print('preset_manager received notification:', key, value)

  if key == 'store_preset' then

    local fxNum = value[1]
    local presetNum = value[2]
    local ccValues = value[3]
    --print('Storing preset:', fxNum, presetNum, 'with values:', unpack(ccValues))
    storePreset(fxNum, presetNum, ccValues)

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

    --print('Returning stored presets list to:', fxPreset
    fxPresetGrid:notify('stored_presets_list', storedPresets)

  elseif key == 'export_presets_to_osc' then

    local fullPresetArray = {}
    for fxNum = 1, 46 do
      local presetArray = json.toTable(self.children[tostring(fxNum)].tag) or {}
      fullPresetArray[fxNum] = presetArray
    end

    local jsonPresets = json.fromTable(fullPresetArray)
    --print('Full preset array:', jsonPresets)
    sendOSC('/presets', jsonPresets)

  elseif key == 'import_presets_from_osc' then

    local fullPresetArray = value

    for fxNum = 1, 46 do
      local presetArray = fullPresetArray[fxNum]
      self.children[tostring(fxNum)].tag = presetArray
    end
  end
end