local startValues = { 0, 9, 17, 25, 33, 41, 49, 57, 65, 73, 81, 89, 97, 105, 113, 121 }
local targetGridName = "chord_grid"
local syncedFaderName = "chord_fader"
local amSyncGrid = false

function init()
  if self.name ~= targetGridName then
    self.outline = true
    self.outlineStyle = OutlineStyle.FULL
  else
    self.outline = false
  end
end

local showHideFader = self.parent.parent:findByName("", true)
local showHideFaderLabel = self.parent.parent:findByName("", true)
local showHideGrid = self.parent.parent:findByName("", true)
local showHideGridLabel = self.parent.parent:findByName("", true)

local function toggleTimeViews(showFader)
  if showHideFader and showHideFaderLabel and showHideGrid and showHideGridLabel then
    showHideFader.visible = not showFader
    showHideFaderLabel.visible = not showFader
    showHideGrid.visible = showFader
    showHideGridLabel.visible = showFader
  end
end

local function toggleFaderSync(value)
  if showHideFader then
    showHideFader:notify("sync_toggle", value)
  end
end

local function chordPadActive()
  if self.parent and self.parent.parent and self.parent.parent.name == "keys_group" then
    local keysGroup = self.parent.parent
    local tag = json.toTable(keysGroup.tag) or {}
    return tag.chordGridMode == "chord_pads"
  end
  return self.parent.tag == "1"
end

function onValueChanged(key, value)
  if self.name ~= targetGridName and key == "x" and self.values.x == 1 and chordPadActive() then
    local padIndex = self.index
    local syncedFader = self.parent.parent:findByName(syncedFaderName, true)
    if syncedFader then
      local myCCValue = startValues[padIndex]
      syncedFader:notify("new_cc_value", myCCValue)
    else
      root:notify("keyboard_ui_chord_pad", padIndex)
    end

    if amSyncGrid then
      local syncOn = (self.index == 2)
      toggleTimeViews(syncOn)
      toggleFaderSync(syncOn)
    end
  elseif self.name == targetGridName and key == "touch" then
    self.tag = 1
  end
end

function onReceiveNotify(key, value)
  if key == "new_child_value" then
    self.values.x = 1
  elseif key == "new_index" then
    local childToSelect = value
    self.tag = 0
    self.children[childToSelect]:notify("new_child_value")
    if amSyncGrid then
      local syncOn = (value == 2)
      toggleTimeViews(syncOn)
      toggleFaderSync(syncOn)
    end
  end
end
