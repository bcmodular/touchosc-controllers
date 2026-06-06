-- efx_button.lua
-- Injected into efx1_b1–b8 and efx2_b1–b8 BUTTON nodes (Toggle Release mode).
-- Fires on ANY x change (on or off) so re-pressing a lit button works.
-- Guards against re-entrant programmatic updates from efx_section.lua via
-- the "prog" flag stored in the parent section's tag property.

function onValueChanged(key)
  if key ~= "x" then return end
  if self.parent.tag == "prog" then return end
  local btnIdx = tonumber(self.name:match("_b(%d+)")) or 0
  self.parent:notify("btn_press", btnIdx)
end
