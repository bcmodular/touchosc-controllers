-- porta_mode_button.lua
-- Injected into the standalone PORTA MODE toggle button.
-- Direct child of portamento_group (no enc_group wrapper).
-- 0 = LEGATO, 1 = ALWAYS  →  SysEx 10 00 14 02

function onValueChanged(key)
  if key ~= "x" then return end
  root:notify("sw_toggled",
    self.parent.name .. "," ..
    self.name        .. "," ..
    tostring(math.floor(self.values.x + 0.5)))
end
