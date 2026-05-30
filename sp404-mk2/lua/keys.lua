local w = self.children.white.children
local b = self.children.black.children

local keys = {
  w[1], b[1], w[2], b[2], w[3],
  w[4], b[3], w[5], b[4], w[6], b[5], w[7],
  w[8], b[6], w[9], b[7], w[10],
  w[11], b[8], w[12], b[9], w[13], b[10], w[14],
}

-- 24-key layout: two chromatic octaves side by side (same as default keys view).
-- Span 1 whites: 1, 3, 5, 6, 8, 10, 12  |  Span 2 whites: 13, 15, 17, 18, 20, 22, 24
local HYPER_RESO_WHITE_SLOTS_LEFT = { 1, 3, 5, 6, 8, 10, 12 }
local HYPER_RESO_WHITE_SLOTS_RIGHT = { 13, 15, 17, 18, 20, 22, 24 }
-- UI octave 3 = C3 on the left; MIDI 60 (middle C) = degree 1.
local HYPER_RESO_ANCHOR_UI_OCTAVE = 3

function init()
  onReceiveNotify("octave", HYPER_RESO_ANCHOR_UI_OCTAVE)
end

local function tagTruthy(value)
  return value == true or value == 1
end

local function hyperResoWhiteKeys(tag)
  return tagTruthy(tag.keyboardHyperResoWhiteKeys)
end

local function spanIndexForUiOctave(uiOctave)
  return uiOctave - HYPER_RESO_ANCHOR_UI_OCTAVE
end

local function spanStartDegree(spanIndex)
  if spanIndex >= 0 then
    return spanIndex * 7 + 1
  end
  return spanIndex * 7
end

local function degreeForSpanSlot(spanIndex, slot)
  local degree = spanStartDegree(spanIndex) + (slot - 1)
  if degree == 0 or degree < -17 or degree > 18 then
    return nil
  end
  return degree
end

local function applyHyperResoSpan(activeSlots, slots, spanIndex)
  for slot = 1, #slots do
    activeSlots[slots[slot]] = degreeForSpanSlot(spanIndex, slot)
  end
end

local function applyHyperResoOctave(uiOctave)
  local leftSpan = spanIndexForUiOctave(uiOctave)
  local rightSpan = leftSpan + 1
  local activeSlots = {}
  applyHyperResoSpan(activeSlots, HYPER_RESO_WHITE_SLOTS_LEFT, leftSpan)
  if degreeForSpanSlot(rightSpan, 1) ~= nil then
    applyHyperResoSpan(activeSlots, HYPER_RESO_WHITE_SLOTS_RIGHT, rightSpan)
  end
  for i = 1, #keys do
    local key = keys[i]
    local degree = activeSlots[i]
    if degree then
      key.name = tostring(degree)
      key.visible = true
    else
      key.visible = false
      key.values.x = 0
    end
  end
  self.children.C0.values.text = "C" .. tostring(uiOctave - 1)
  self.children.C1.values.text = "C" .. tostring(uiOctave)
end

local function keyVisibleForOctave(note, octave, chromatic)
  if note > 127 then
    return false
  end
  local tag = json.toTable(root.tag) or {}
  if hyperResoWhiteKeys(tag) then
    return false
  end
  if not chromatic then
    return true
  end
  if note < 36 or note > 60 then
    return false
  end
  if octave == 3 then
    return note >= 36 and note <= 59
  end
  if octave == 4 then
    return note >= 48 and note <= 60
  end
  return false
end

function onReceiveNotify(key, value)
  if key == "hyper_reso_octave" then
    applyHyperResoOctave(value)
    return
  end

  if key == "octave" then
    local octave = value
    local tag = json.toTable(root.tag) or {}
    local chromatic = tagTruthy(tag.keyboardChromaticAttached)
    if hyperResoWhiteKeys(tag) then
      applyHyperResoOctave(octave)
      return
    end
    local index = octave * 12
    for i = 1, #keys do
      local note = index + (i - 1)
      keys[i].name = note
      keys[i].visible = keyVisibleForOctave(note, octave, chromatic)
    end
    self.children.C0.values.text = "C" .. (octave - 1)
    self.children.C1.values.text = "C" .. octave
  end
end
