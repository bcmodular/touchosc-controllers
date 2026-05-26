-- effect_chooser -> busN_group; clear_bus is handled on bus_group (bus_group_instance.lua).
function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    local busGroup = self.parent and self.parent.parent
    if busGroup then
      busGroup:notify('clear_bus')
    end
  end
end
