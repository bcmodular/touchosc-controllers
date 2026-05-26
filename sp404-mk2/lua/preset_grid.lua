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
  elseif key == 'toggle_grab_mode' then
    manager:notify(key, value)
  elseif key == 'store_defaults' then
    manager:notify(key, busNum)
  elseif key == 'recall_defaults' then
    manager:notify(key, busNum)
  elseif key == 'button_value_changed' then
    manager:notify(key, {busNum, value[1], value[2], value[3]})
  elseif key == 'clear_presets' then
    manager:notify(key, busNum)
  elseif key == 'set_morph_enabled' or key == 'set_morph_amount' or key == 'set_morph_target'
      or key == 'sync_morph_ui' or key == 'toggle_morph_enabled' then
    manager:notify(key, value)
  end
end
