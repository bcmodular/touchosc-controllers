-- porta_mode_button.lua
-- Injected into the standalone PORTA MODE toggle button.
-- Direct child of portamento_group (no enc_group wrapper).
-- 0 = LEGATO, 1 = ALWAYS  →  SysEx 10 00 14 02

function onValueChanged(key)
  if key ~= "x" then return end
  local v = math.floor(self.values.x + 0.5)
  -- Update the sibling label to show current mode text.
  local lbl = self.parent.children["porta_mode_label"]
  if lbl then lbl.values.text = v == 1 and "ALWAYS" or "LEGATO" end
  root:notify("sw_toggled",
    self.parent.name .. "," ..
    self.name        .. "," ..
    tostring(v))
end
