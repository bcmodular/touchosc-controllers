-- preset_grid.lua
-- Group script for the preset_grid container.
-- Holds all 16 slot snapshots as JSON in self.tag:
--   {"1": {"blocks": [...]}, "2": null, ...}
-- Handles UI refresh notify from root.

-- Colors (RRGGBBAA as used by Color.fromHexString in this layout)
local FILLED_COLOR  = "4A90D9FF"   -- blue — slot has a patch
local EMPTY_COLOR   = "1A1A2EFF"   -- dark — slot is empty

local function refreshUI()
  local slots = json.toTable(self.tag) or {}
  local labelGrid = self.children["perform_preset_label_grid"]
  for i = 1, 16 do
    local backBtn = self.children["back_" .. i]
    if backBtn then
      local filled = (slots[tostring(i)] ~= nil)
      backBtn.color = Color.fromHexString(filled and FILLED_COLOR or EMPTY_COLOR)
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
  end
end

function init()
  if self.tag == nil or self.tag == "" then
    self.tag = "{}"
  end
  refreshUI()
end
