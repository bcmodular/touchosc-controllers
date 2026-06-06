-- dist_toggle_button.lua
-- Injected into DIST ON/OFF and DIST COLOR toggle buttons.
-- These are direct children of dist_group (no enc_group wrapper).
-- Key format: "dist_group,<self.name>"
--
-- Also flips the sibling label's textColor so the text stays readable
-- against the button's lit (bright) background.

local LABEL_MAP = {
  dist_on_off = "dist_on_label",
  dist_color  = "dist_color_label",
}

function onValueChanged(key)
  if key ~= "x" then return end
  local isOn = self.values.x >= 0.5
  -- Update sibling label text colour
  local labelName = LABEL_MAP[self.name] or (self.name .. "_label")
  local lbl = self.parent.children[labelName]
  if lbl then
    lbl.textColor = Color.fromHexString(isOn and "000000FF" or "FFFFFFFF")
  end
  root:notify("sw_toggled",
    self.parent.name .. "," ..
    self.name        .. "," ..
    tostring(math.floor(self.values.x + 0.5)))
end
