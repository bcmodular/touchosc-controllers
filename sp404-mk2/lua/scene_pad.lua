function onValueChanged(key, value)
  if key == 'x' then
    local sceneNum = tonumber(self.name)
    local manager = root.children.scene_manager
    if not manager or not sceneNum then
      return
    end
    local rootTag = json.toTable(root.tag) or {}
    local shiftHeld = rootTag.launchpadShiftHeld == true
    manager:notify('button_value_changed', { sceneNum, self.values.x, shiftHeld })
  end
end
