-- porta_mode_button.lua
-- Injected into the standalone PORTA MODE toggle button.
-- Direct child of portamento_group (no enc_group wrapper).
-- 0 = LEGATO, 1 = ALWAYS  →  SysEx 10 00 14 02
--
-- Flips the sibling label textColor so text stays readable when button is lit.

function onValueChanged(key)
  if key ~= "x" then return end
  local v   = math.floor(self.values.x + 0.5)
  local lbl = self.parent.children["porta_mode_label"]
  if lbl then
    lbl.values.text = v == 1 and "ALWAYS" or "LEGATO"
    lbl.textColor   = Color.fromHexString(v == 1 and "000000FF" or "FFFFFFFF")
  end
  root:notify("sw_toggled",
    self.parent.name .. "," ..
    self.name        .. "," ..
    tostring(v))
end
