-- dist_toggle_button.lua
-- Injected into DIST ON/OFF and DIST COLOR toggle buttons.
-- These are direct children of dist_group (no enc_group wrapper).
-- Key format: "dist_group,<self.name>"

function onValueChanged(key)
  if key ~= "x" then return end
  root:notify("sw_toggled",
    self.parent.name .. "," ..
    self.name        .. "," ..
    tostring(math.floor(self.values.x + 0.5)))
end
