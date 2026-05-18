function onValueChanged(key, value)
  if key == "x" and self.values.x == 0 then
    self.parent:notify("hide")
  end
end
