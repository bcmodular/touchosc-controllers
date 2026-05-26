local manager = root.children.scene_manager

function onReceiveNotify(key, value)
  if not manager then
    return
  end
  if key == 'toggle_delete_mode' then
    manager:notify(key, value)
  elseif key == 'button_value_changed' then
    manager:notify(key, value)
  end
end
