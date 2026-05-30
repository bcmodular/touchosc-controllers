local function tagTruthy(value)
  return value == true or value == 1
end

local function octaveValueFromButton()
  if self.index ~= nil then
    return self.index - 1
  end
  return tonumber(self.name) - 1
end

function onValueChanged(key, value)
  if key ~= "x" then
    return
  end

  local tag = json.toTable(root.tag) or {}
  if tagTruthy(tag.keyboardHighlighting) then
    return
  end

  if self.values.x == 1 then
    root:notify("keyboard_octave_select", octaveValueFromButton())
    return
  end

  -- Radio group: do not leave all octaves off.
  root:notify("keyboard_octave_select", octaveValueFromButton())
end
