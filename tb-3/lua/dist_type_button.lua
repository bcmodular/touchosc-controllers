-- dist_type_button.lua
-- Injected into DIST TYPE ↑ and DIST TYPE ↓ momentary buttons.
-- Notifies root to step the distortion type state machine.

function onValueChanged(key)
  if key ~= "x" or self.values.x < 0.5 then return end  -- rising edge only
  root:notify(self.name, 1)  -- "dist_type_up" or "dist_type_dn"
end
