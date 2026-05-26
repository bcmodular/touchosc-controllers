function onValueChanged(key, value)
  if key == 'x' then
    self.parent:notify('set_grab_state', self.values.x == 1)
  end
end
