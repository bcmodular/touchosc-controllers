-- sw_button.lua
-- Injected into every BUTTON node named 'sw_button' (VCO source switches,
-- LFO BPM SYNC, LFO RETRIGGER, PORTA SW).
--
-- Notifies root with key "sw_toggled" and value "section,enc,v"
-- where section = self.parent.parent.name  (e.g. "vco_group")
--       enc     = self.parent.name         (e.g. "saw_enc")
--       v       = 0 or 1
--
-- Also notifies root with "sw_touched" (same section,enc) for parameter
-- assignment mode.  When assign mode is active, root sends "assign_revert"
-- back to undo the value change so assignment doesn't actually toggle the switch.

local updating = false

function onValueChanged(key)
  if key ~= "x" then return end
  if updating then return end
  -- Notify root for parameter assignment mode.
  root:notify("sw_touched",
    self.parent.parent.name .. "," .. self.parent.name)
  root:notify("sw_toggled",
    self.parent.parent.name .. "," ..
    self.parent.name        .. "," ..
    tostring(math.floor(self.values.x + 0.5)))
end

function onReceiveNotify(key, value)
  if key ~= "assign_revert" then return end
  -- Flip the value back to its pre-touch state without triggering
  -- sw_touched / sw_toggled (the 'updating' guard suppresses them).
  updating = true
  self.values.x = 1 - self.values.x
  updating = false
end
