-- Perform strip morph_button (on_off_button_group only): morph on/off toggle.
function onValueChanged(key, value)
  if key ~= 'x' then
    return
  end
  local onOff = self.parent
  if not onOff or onOff.name ~= 'on_off_button_group' then
    return
  end
  onOff:notify('set_morph_state', { self.values.x == 1, false })
end
