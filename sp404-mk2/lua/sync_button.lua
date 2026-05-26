function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    self.parent:notify('sync_current_bus')
  end
end
