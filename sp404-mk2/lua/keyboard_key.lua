local function tagTruthy(value)
  return value == true or value == 1
end

local function pianoKeysMomentaryFromTag(tag)
  return tagTruthy(tag.keyboardKeysMomentary) or tagTruthy(tag.keyboardChromaticAttached)
end

function onValueChanged(key, value)
  if key ~= "x" then
    return
  end

  local tag = json.toTable(root.tag) or {}
  if tagTruthy(tag.keyboardHighlighting) then
    return
  end

  local note = tonumber(self.name)
  if not note then
    return
  end

  -- Value Position: x is 0.0–1.0 by touch height (bottom = loudest).
  local velocity = math.floor(self.values.x * 127 + 0.5)

  if velocity <= 0 then
    if pianoKeysMomentaryFromTag(tag) then
      root:notify("keyboard_ui_note", { note, 0 })
    end
    return
  end

  root:notify("keyboard_key_select", { note, velocity })
end
