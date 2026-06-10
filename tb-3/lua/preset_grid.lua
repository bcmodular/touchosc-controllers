-- preset_grid.lua
-- Group script for the preset_grid container.
-- Holds all 16 slot snapshots as JSON in self.tag:
--   {"1": {"blocks": [...]}, "2": null, ...}
-- Handles UI refresh notify from root.

-- Colors (RRGGBBAA as used by Color.fromHexString in this layout)
local FILLED_COLOR  = "4A90D9FF"   -- blue — slot has a patch (default mode)
local EMPTY_COLOR   = "BFBFBFFF"   -- light gray — slot is empty

local MODE_COLORS = {
  delete = "E70000FF",  -- matches delete_button red
  grab   = "FF9500FF",  -- orange — grab mode
  morph  = "00E6FFFF",  -- matches morph_button cyan
}

local currentMode = ""

local function refreshUI()
  local slots = json.toTable(self.tag) or {}
  local modeColor = MODE_COLORS[currentMode]
  local labelGrid = self.children["perform_preset_label_grid"]
  for i = 1, 16 do
    local backBtn = self.children["back_" .. i]
    if backBtn then
      local filled = (slots[tostring(i)] ~= nil)
      local color
      if filled and modeColor then
        color = modeColor
      elseif filled then
        color = FILLED_COLOR
      else
        color = EMPTY_COLOR
      end
      backBtn.color = Color.fromHexString(color)
    end
    -- Update slot number labels via the label grid
    if labelGrid then
      local lbl = labelGrid.children[tostring(i)]
      if lbl then
        lbl.values.text = tostring(i)
      end
    end
  end
end

function onReceiveNotify(key, value)
  if key == "refresh_preset_ui" then
    refreshUI()
  elseif key == "patch_mode_changed" then
    currentMode = value or ""
    refreshUI()
  end
end

function init()
  if self.tag == nil or self.tag == "" then
    self.tag = "{}"
  end
  refreshUI()
end
