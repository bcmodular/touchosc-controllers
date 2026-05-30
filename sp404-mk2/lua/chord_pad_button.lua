-- chord_grid direct child (pads 1-16). keys_group: keyboard_manager scale/chord modes.
-- Perform strip: legacy chord/harmony fader sync (same grid names on bus control_group).

local RESONATOR_CHORD_CC = {
  0, 9, 17, 25, 33, 41, 49, 57, 65, 73, 81, 89, 97, 105, 113, 121,
}

local function tagTruthy(value)
  return value == true or value == 1
end

local function isKeysGroupChordGrid()
  local parent = self.parent
  return parent and parent.name == "chord_grid"
    and parent.parent and parent.parent.name == "keys_group"
end

local function keysGroupChordGridMode()
  local keysGroup = root:findByName("keys_group", true)
  if not keysGroup then
    return nil
  end
  local tag = json.toTable(keysGroup.tag) or {}
  return tag.chordGridMode
end

local function padIndexFromSelf()
  return tonumber(self.name) or self.index
end

local function handlePerformStripChordPad()
  if self.values.x ~= 1 then
    return
  end
  local padIndex = padIndexFromSelf()
  if not padIndex then
    return
  end
  local controlGroup = self.parent and self.parent.parent
  if not controlGroup then
    return
  end
  for _, faderName in ipairs({ "chord_fader", "harmony_fader" }) do
    local syncedFader = controlGroup:findByName(faderName, true)
    if syncedFader and padIndex <= #RESONATOR_CHORD_CC then
      syncedFader:notify("new_cc_value", RESONATOR_CHORD_CC[padIndex])
      return
    end
  end
end

function onValueChanged(key, value)
  if key ~= "x" then
    return
  end

  local tag = json.toTable(root.tag) or {}
  if tagTruthy(tag.keyboardHighlighting) then
    return
  end

  if isKeysGroupChordGrid() then
    local mode = keysGroupChordGridMode()
    if mode == "chord_pads" and self.values.x ~= 1 then
      return
    end
    root:notify("keyboard_chord_pad", { padIndexFromSelf(), self.values.x == 1 })
    return
  end

  handlePerformStripChordPad()
end
