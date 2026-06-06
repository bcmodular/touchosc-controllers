-- pointer.lua — transparent overlay BOX injected into every encoder group.
-- Sits on top of the RADIAL ('control_fader' sibling) and provides:
--   • Drag up/down to change value (200px = full range)
--   • Double-tap (< 200 ms between END events) resets to default value

local function limit(x, lo, hi)
  if x > hi then return hi end
  if x < lo then return lo end
  return x
end

local controlFader
local startValue = 0
local startY     = 0
local pressTime  = 0

function init()
  controlFader = self.parent.children["control_fader"]
  startValue = 0
  startY     = 0
  pressTime  = 0
end

function onPointer(pointers)
  -- Reject all input when the containing slot is disabled (e.g. RATE encoder
  -- while BPM SYNC is active).  efx_section.lua sets parent.tag = "disabled".
  if self.parent.tag == "disabled" then return end

  for i = 1, #pointers do
    local p = pointers[i]

    if p.state == PointerState.BEGIN then
      startValue = controlFader.values.x
      startY     = p.y
      controlFader:notify("touch", true)

    elseif p.state == PointerState.MOVE then
      local distance = startY - p.y
      controlFader.values.x = limit(startValue + (distance / 200), 0, 1)

    elseif p.state == PointerState.END then
      local now = getMillis()
      if now - pressTime < 200 then
        -- Double-tap: reset to default
        controlFader.values.x =
          tonumber(controlFader:getValueField("x", ValueField.DEFAULT))
        return
      end
      pressTime = now
      controlFader:notify("touch", false)
    end
  end
end
