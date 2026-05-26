function onValueChanged(key, value)
  if key == "x" and self.values.x == 0 then
    self.parent:notify("close_import_overlay")
  end
end
