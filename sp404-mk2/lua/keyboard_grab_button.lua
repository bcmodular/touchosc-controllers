function onValueChanged(key, value)
  if key ~= "x" then
    return
  end

  local busGroup = self.parent and self.parent.parent
  if not busGroup then
    return
  end

  local busTag = json.toTable(busGroup.tag) or {}
  local busNum = tonumber(busTag.busNum) or tonumber(busGroup.name:match("bus(%d+)_group")) or 1

  if self.values.x == 1 then
    root:notify("keyboard_attach_bus", busNum)
  else
    root:notify("keyboard_detach_bus", busNum)
  end
end
