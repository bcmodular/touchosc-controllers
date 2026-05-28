function onValueChanged(key, value)
  if key ~= "x" then
    return
  end
  root:notify("keyboard_chromatic_toggle", self.values.x == 1)
end
