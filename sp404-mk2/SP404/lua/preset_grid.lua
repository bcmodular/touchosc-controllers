local busNum = tonumber(self.tag) or 1
local manager = root.children.preset_grid_manager

function onReceiveNotify(key, value)
  if not manager then
    return
  end
  if key == 'refresh_presets_list' then
    manager:notify(key, {busNum, value})
  elseif key == 'toggle_delete_mode' then
    manager:notify(key, value)
  elseif key == 'store_defaults' then
    manager:notify(key, busNum)
  elseif key == 'recall_defaults' then
    manager:notify(key, busNum)
  elseif key == 'button_value_changed' then
    manager:notify(key, {busNum, value[1], value[2]})
  elseif key == 'clear_presets' then
    manager:notify(key, busNum)
  end
end
