-- effect_chooser -> busN_group; clear_bus is handled on bus_group (bus_group_instance.lua).
function onValueChanged(key, value)
  if key ~= 'x' then
    return
  end

  local busGroup = self.parent and self.parent.parent
  if not busGroup then
    return
  end

  local busTag = json.toTable(busGroup.tag) or {}
  local busNum = tonumber(busTag.busNum) or 1
  if isBusLocked(busNum) then
    self.values.x = 0
    return
  end

  if self.values.x == 0 then
    busGroup:notify('clear_bus')
  end
end
