-- dist_toggle_button.lua
-- Injected into DIST ON/OFF and DIST COLOR toggle buttons.
-- These are direct children of dist_group (no enc_group wrapper).
-- Key format for SW_PARAM_ID_MAP: "dist_group,<self.name>"
--
-- Also flips the sibling label's textColor so the text stays readable
-- against the button's lit (bright) background.
--
-- When in parameter assignment mode, root sends "assign_revert" to undo
-- the value change so assignment doesn't actually toggle the button.

local updating = false

local LABEL_MAP = {
  dist_on_off = "dist_on_label",
  dist_color  = "dist_color_label",
}

local function applyLabelColor(isOn)
  local labelName = LABEL_MAP[self.name] or (self.name .. "_label")
  local lbl = self.parent.children[labelName]
  if lbl then
    lbl.textColor = Color.fromHexString(isOn and "000000FF" or "FFFFFFFF")
  end
end

function onValueChanged(key)
  if key ~= "x" then return end
  if updating then return end
  local isOn = self.values.x >= 0.5
  applyLabelColor(isOn)
  -- Notify root for parameter assignment mode.
  root:notify("sw_touched", self.parent.name .. "," .. self.name)
  root:notify("sw_toggled",
    self.parent.name .. "," ..
    self.name        .. "," ..
    tostring(math.floor(self.values.x + 0.5)))
end

function onReceiveNotify(key, value)
  if key ~= "assign_revert" then return end
  -- Flip back to original state without triggering sw_touched / sw_toggled.
  updating = true
  self.values.x = 1 - self.values.x
  applyLabelColor(self.values.x >= 0.5)
  updating = false
end
