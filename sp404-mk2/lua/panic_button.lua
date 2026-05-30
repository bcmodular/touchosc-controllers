function onValueChanged(key, value)
  if key ~= "x" or self.values.x ~= 1 then
    return
  end
  root:notify("keyboard_panic")
end
