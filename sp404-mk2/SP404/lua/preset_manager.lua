local childScript = [[
function onValueChanged(key, value)
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
end

function onReceiveNotify(key, value)
  if key == 'delete_all_presets_for_all_fx' then
    deleteAllPresetsForAllFX()
  end
end

function init()
  for i = 1, #self.children do
    self.children[tostring(i)].script = childScript
  end
end
