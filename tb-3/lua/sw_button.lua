-- sw_button.lua
-- Injected into every BUTTON node named 'sw_button' (VCO source switches,
-- LFO BPM SYNC, LFO RETRIGGER, PORTA SW).
--
-- Notifies root with key "sw_toggled" and value "section,enc,v"
-- where section = self.parent.parent.name  (e.g. "vco_group")
--       enc     = self.parent.name         (e.g. "saw_enc")
--       v       = 0 or 1

function onValueChanged(key)
  if key ~= "x" then return end
  root:notify("sw_toggled",
    self.parent.parent.name .. "," ..
    self.parent.name        .. "," ..
    tostring(math.floor(self.values.x + 0.5)))
end
