local childScript = [[
function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
      print('Current preset values:', self.tag)
  end
end
]]

local function deleteAllPresetsForAllFX()
  for fxNum = 1, 46 do
    self.children[tostring(fxNum)].tag = ''
  end

  local presetGrids = root:findAllByName('preset_grid', true)
  for _, presetGrid in ipairs(presetGrids) do
    presetGrid:notify('refresh_presets_list')
  end

  local abletonPushHandler = root:findByName('ableton_push_handler', true)
  for busNum = 1, 4 do
    abletonPushHandler:notify('sync_push_lighting', busNum)
  end
end

local function exportPresetsToOSC()
  local fullPresetArray = {}
  for fxNum = 1, 46 do
    local presetArray = json.toTable(self.children[tostring(fxNum)].tag) or {}
    fullPresetArray[fxNum] = presetArray
  end

  local jsonPresets = json.fromTable(fullPresetArray)
  sendOSC('/presets', jsonPresets)
end

local function importPresetsFromOSC(fullPresetArray)
  for fxNum = 1, 46 do
    local presetArray = fullPresetArray[fxNum]
    self.children[tostring(fxNum)].tag = presetArray
  end
end

function onReceiveNotify(key, value)
  if key == 'delete_all_presets_for_all_fx' then
    deleteAllPresetsForAllFX()
  elseif key == 'export_presets_to_osc' then
    exportPresetsToOSC()
  elseif key == 'import_presets_from_osc' then
    importPresetsFromOSC(value)
  end
end

function init()
  for i = 1, #self.children do
    self.children[tostring(i)].script = childScript
  end
end
