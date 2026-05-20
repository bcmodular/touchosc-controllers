function onValueChanged(key, value)
  if key == 'x' then
    self.parent:notify('set_chooser_state', self.values.x == 1)
  end
end
