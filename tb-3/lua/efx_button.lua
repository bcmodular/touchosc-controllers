-- efx_button.lua
-- Injected into efx1_b1–b8 and efx2_b1–b8 BUTTON nodes.
-- On press, notifies the parent efxN_section GROUP which handles all routing.

function onValueChanged(key)
  if key ~= "x" or self.values.x < 0.5 then return end
  local btnIdx = tonumber(self.name:match("_b(%d+)")) or 0
  self.parent:notify("btn_press", btnIdx)
end
