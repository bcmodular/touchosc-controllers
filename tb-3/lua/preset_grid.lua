-- preset_grid.lua
-- Group script for the preset_grid container.
-- Holds all 16 slot snapshots as JSON in self.tag:
--   {"1": {"blocks": [...]}, "2": null, ...}
-- Colours the back_N slot backings by fill state + active mode, brightens the
-- pressed slot, and highlights the morph target. Driven by notifies from root.

-- Colors (RRGGBBAA as used by Color.fromHexString in this layout)
local FILLED_COLOR  = "4A90D9FF"   -- blue — slot has a patch (default mode)
local EMPTY_COLOR   = "BFBFBFFF"   -- light gray — slot is empty

local MODE_COLORS = {
  delete = "E70000FF",  -- red   — matches delete_button
  grab   = "E6E6E6FF",  -- white — matches grab button (press → full white)
  morph  = "FF7F00FF",  -- orange (shared with SP-404; pressed/target = full bright)
}

-- Idle pads sit slightly dimmed; a press brightens to full (mirrors the SP-404).
local IDLE_FACTOR = 0.78

local currentMode        = ""
local currentMorphTarget = 0

-- Scale an RRGGBBAA hex by a 0–1 brightness factor (alpha preserved).
local function scaleHexColor(hex, factor)
  local c = Color.fromHexString(hex)
  local function ch(v)
    v = v * factor
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return math.floor(v * 255 + 0.5)
  end
  return string.format("%02X%02X%02X%02X", ch(c.r), ch(c.g), ch(c.b),
                       math.floor(c.a * 255 + 0.5))
end

-- Resting (or pressed) colour for slot i.
local function colorForSlot(i, pressed)
  local slots  = json.toTable(self.tag) or {}
  local filled = (slots[tostring(i)] ~= nil)
  -- Morph target stands out at full-bright orange.
  if currentMode == "morph" and currentMorphTarget == i and filled then
    return "FF7F00FF"
  end
  if not filled then
    return scaleHexColor(EMPTY_COLOR, pressed and 1.0 or IDLE_FACTOR)
  end
  if currentMode == "grab" then
    return pressed and "FFFFFFFF" or "E6E6E6FF"
  end
  local base = MODE_COLORS[currentMode] or FILLED_COLOR
  return scaleHexColor(base, pressed and 1.0 or IDLE_FACTOR)
end

local function refreshUI()
  local labelGrid = self.children["perform_preset_label_grid"]
  for i = 1, 16 do
    local backBtn = self.children["back_" .. i]
    if backBtn then
      backBtn.color = Color.fromHexString(colorForSlot(i, false))
    end
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
  elseif key == "morph_target" then
    currentMorphTarget = tonumber(value) or 0
    refreshUI()
  elseif key == "slot_visual" then
    -- value = "i,pressed" — brighten just one slot on press, restore on release.
    local i, p = tostring(value):match("^(%d+),([01])$")
    i = tonumber(i)
    if i then
      local backBtn = self.children["back_" .. i]
      if backBtn then
        backBtn.color = Color.fromHexString(colorForSlot(i, p == "1"))
      end
    end
  end
end

function init()
  if self.tag == nil or self.tag == "" then
    self.tag = "{}"
  end
  refreshUI()
end
