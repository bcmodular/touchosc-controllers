-- control_group bus lock toggle (synced with Launchpad CC 1–5 via root set_bus_locked).
function onValueChanged(key, value)
  if key ~= "x" then
    return
  end
  local busGroup = self.parent and self.parent.parent
  if not busGroup then
    return
  end
  local busTag = json.toTable(busGroup.tag) or {}
  local busNum = tonumber(busTag.busNum) or 1
  root:notify("set_bus_locked", { busNum, self.values.x == 1 })
end
