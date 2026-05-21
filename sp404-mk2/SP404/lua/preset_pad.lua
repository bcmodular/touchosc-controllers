function onValueChanged(key, value)
  if key == 'x' then
    local presetNum = tonumber(self.name)
    local busNum = tonumber(self.parent and self.parent.tag) or 1
    local manager = root.children.preset_grid_manager
    if not manager then
      return
    end
    manager:notify('button_value_changed', {busNum, presetNum, self.values.x})
  end
end
