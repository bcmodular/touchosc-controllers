function onValueChanged(key, value)
  if key ~= "x" then return end

  local tag = json.toTable(root.tag) or {}
  if tag.keyboardHighlighting == true then return end

  if self.values.x == 1 then
    root:notify("keyboard_attach_soundgen", true)
  else
    root:notify("keyboard_detach_soundgen", true)
  end
end
