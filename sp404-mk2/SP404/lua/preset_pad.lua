function onValueChanged(key, value)
  if key == 'x' then
    local presetNum = tonumber(self.name)
    local busNum = tonumber(self.parent and self.parent.tag) or 1
    local manager = root.children.preset_grid_manager
    if not manager then
      return
    end
    local rootTag = json.toTable(root.tag) or {}
    local shiftHeld = rootTag.launchpadShiftHeld == true
    local quantiseHeld = rootTag.launchpadQuantiseHeld == true
    local noteVelocity = 0
    if quantiseHeld and self.values.x == 1 then
      noteVelocity = tonumber(rootTag.launchpadLastNoteVelocity) or 0
    end
    manager:notify('button_value_changed', {
      busNum, presetNum, self.values.x, shiftHeld, quantiseHeld, noteVelocity,
    })
  end
end
