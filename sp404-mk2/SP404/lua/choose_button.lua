-- Perform strip: parent is on_off_button_group. Header: parent is effect_chooser -> notify on_off on same bus.
function onValueChanged(key, value)
  if key == 'x' then
    local onOff = self.parent
    if onOff.name ~= 'on_off_button_group' then
      local busGroup = onOff.parent
      onOff = busGroup and busGroup:findByName('on_off_button_group', true)
    end
    if onOff then
      onOff:notify('set_chooser_state', self.values.x == 1)
    end
  end
end
