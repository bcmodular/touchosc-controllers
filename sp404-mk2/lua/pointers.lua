local pointersScript = [[

local function limit(x, min, max)
  if (x > max) then
    return max
  end
  if (x < min) then
    return min
  end
  return x
end

function init()
  controlFader = self.parent.children['control_fader']
  startValue = 0
  startY = 0
  pressTime = 0
end

function onPointer(pointers)
  for i = 1, #pointers do
    local pointer = pointers[i]
    if (pointer.state == PointerState.BEGIN) then
      startValue = controlFader.values.x
      startY = pointer.y
      controlFader:notify("touch", true)
    end
    if (pointer.state == PointerState.MOVE) then
      local distance = startY - pointer.y
      controlFader.values.x = limit(startValue + (distance / 200), 0, 1)
    end
    if (pointer.state == PointerState.END) then
      local newPressTime = getMillis()
      if (newPressTime - pressTime < 200) then
        controlFader.values.x = tonumber(controlFader:getValueField("x", ValueField.DEFAULT))
        return
      end
      pressTime = newPressTime
      controlFader:notify("touch", false)
    end
  end
end

]]

function init()
    local pointers = root:findAllByName('pointer', true)
    for _, pointer in ipairs(pointers) do
        pointer.script = pointersScript
    end
end
