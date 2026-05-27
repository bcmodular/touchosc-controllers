-- Shared Launchpad Pro LED helpers (prepended into root.lua / preset_grid_manager.lua via toscbuild include).
-- RGB SysEx: F0 00 20 29 02 10 0B <led> <R> <G> <B> (R,G,B = 0..63)
-- Palette off: F0 ... 0A <led> 00 F7

-- Must be defined here (before helpers). TouchOSC Lua does not see locals declared later in the host script.
LAUNCHPAD_MIDI_CONNECTION = { false, false, true }

-- Profile order for User-button (CC 98) cycling.
LAUNCHPAD_BRIGHTNESS_PROFILE_ORDER = { "very_dim", "night", "normal", "day" }

LAUNCHPAD_BRIGHTNESS_PROFILES = {
  very_dim = { idle = 0.08, on = 1.0, press = 0.88, busOff = 0.01, emptyPress = 0.20 },
  night = { idle = 0.18, on = 1.0, press = 0.88, busOff = 0.02, emptyPress = 0.35 },
  normal = { idle = 0.30, on = 1.0, press = 0.88, busOff = 0.05, emptyPress = 0.45 },
  day = { idle = 0.45, on = 1.0, press = 0.88, busOff = 0.08, emptyPress = 0.55 },
}

local launchpadBrightnessProfileKey = "night"

-- Globals updated by applyLaunchpadBrightnessProfile (read everywhere Launchpad LEDs are set).
LAUNCHPAD_IDLE_BRIGHTNESS = 0.18
LAUNCHPAD_ON_BRIGHTNESS = 1.0
LAUNCHPAD_PRESS_BRIGHTNESS = 0.88
LAUNCHPAD_BUS_OFF_BRIGHTNESS = 0.02
LAUNCHPAD_EMPTY_PRESS_BRIGHTNESS = 0.35

function getLaunchpadBrightnessProfileKey()
  return launchpadBrightnessProfileKey
end

function applyLaunchpadBrightnessProfile(key)
  local profile = LAUNCHPAD_BRIGHTNESS_PROFILES[key]
  if not profile then
    key = "night"
    profile = LAUNCHPAD_BRIGHTNESS_PROFILES.night
  end
  launchpadBrightnessProfileKey = key
  LAUNCHPAD_IDLE_BRIGHTNESS = profile.idle
  LAUNCHPAD_ON_BRIGHTNESS = profile.on
  LAUNCHPAD_PRESS_BRIGHTNESS = profile.press
  LAUNCHPAD_BUS_OFF_BRIGHTNESS = profile.busOff
  LAUNCHPAD_EMPTY_PRESS_BRIGHTNESS = profile.emptyPress
end

function loadLaunchpadBrightnessFromRootTag()
  local tag = json.toTable(root.tag) or {}
  local key = tag.launchpadBrightnessProfile
  if type(key) == "string" and LAUNCHPAD_BRIGHTNESS_PROFILES[key] then
    applyLaunchpadBrightnessProfile(key)
  else
    applyLaunchpadBrightnessProfile("night")
  end
end

function saveLaunchpadBrightnessToRootTag()
  local tag = json.toTable(root.tag) or {}
  tag.launchpadBrightnessProfile = launchpadBrightnessProfileKey
  root.tag = json.fromTable(tag)
end

function cycleLaunchpadBrightnessProfile()
  local order = LAUNCHPAD_BRIGHTNESS_PROFILE_ORDER
  local currentIdx = 1
  for i, key in ipairs(order) do
    if key == launchpadBrightnessProfileKey then
      currentIdx = i
      break
    end
  end
  local nextKey = order[(currentIdx % #order) + 1]
  applyLaunchpadBrightnessProfile(nextKey)
  saveLaunchpadBrightnessToRootTag()
  return nextKey
end

local function activeLaunchpadBrightnessProfile()
  local tag = json.toTable(root.tag) or {}
  local key = tag.launchpadBrightnessProfile
  local profile = LAUNCHPAD_BRIGHTNESS_PROFILES[key]
  if not profile then
    profile = LAUNCHPAD_BRIGHTNESS_PROFILES.night
  end
  return profile
end

function launchpadIdleBrightness()
  return activeLaunchpadBrightnessProfile().idle
end

function launchpadOnBrightness()
  return activeLaunchpadBrightnessProfile().on
end

function launchpadPressBrightness()
  return activeLaunchpadBrightnessProfile().press
end

function launchpadBusOffBrightness()
  return activeLaunchpadBrightnessProfile().busOff
end

function launchpadEmptyPressBrightness()
  return activeLaunchpadBrightnessProfile().emptyPress
end

-- Saturated RGBCMY-style primaries for buses (Launchpad only; TouchOSC UI keeps its own hex).
local LAUNCHPAD_BUS_RGB = {
  [1] = { 0, 255, 255 },   -- Cyan
  [2] = { 255, 255, 0 },   -- Yellow
  [3] = { 255, 0, 255 },   -- Magenta
  [4] = { 0, 0, 255 },     -- Blue
  [5] = { 0, 255, 0 },     -- Green
}

function launchpadRgb255(r, g, b, brightness)
  brightness = brightness or LAUNCHPAD_ON_BRIGHTNESS
  local function ch(v)
    return math.max(0, math.min(63, math.floor(v / 255 * 63 * brightness + 0.5)))
  end
  return ch(r), ch(g), ch(b)
end

function launchpadBusRgb(busNum, brightness)
  local rgb = LAUNCHPAD_BUS_RGB[busNum] or LAUNCHPAD_BUS_RGB[1]
  return launchpadRgb255(rgb[1], rgb[2], rgb[3], brightness)
end

function sendLaunchpadLedPalette(ledIndex, paletteIndex)
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0A, ledIndex, paletteIndex, 0xF7 }
  sendMIDI(sysexMessage, LAUNCHPAD_MIDI_CONNECTION)
end

function sendLaunchpadLedRgb(ledIndex, r, g, b)
  local sysexMessage = {
    0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0B,
    ledIndex,
    math.max(0, math.min(63, r)),
    math.max(0, math.min(63, g)),
    math.max(0, math.min(63, b)),
    0xF7,
  }
  sendMIDI(sysexMessage, LAUNCHPAD_MIDI_CONNECTION)
end

function sendLaunchpadLedRgbBatch(entries)
  if not entries or #entries == 0 then
    return
  end
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0B }
  for i = 1, #entries, 4 do
    table.insert(sysexMessage, entries[i])
    table.insert(sysexMessage, entries[i + 1])
    table.insert(sysexMessage, entries[i + 2])
    table.insert(sysexMessage, entries[i + 3])
  end
  table.insert(sysexMessage, 0xF7)
  sendMIDI(sysexMessage, LAUNCHPAD_MIDI_CONNECTION)
end

function sendLaunchpadLedOff(ledIndex)
  sendLaunchpadLedPalette(ledIndex, 0)
end

function launchpadUndoRgb(brightness)
  return launchpadRgb255(255, 0, 255, brightness)
end

function launchpadClickRgb(brightness)
  return launchpadRgb255(0, 255, 0, brightness)
end

function launchpadShiftRgb(brightness)
  return launchpadRgb255(255, 255, 255, brightness)
end

function launchpadQuantiseRgb(brightness)
  return launchpadRgb255(255, 128, 0, brightness)
end

function launchpadDeleteRgb(brightness)
  return launchpadRgb255(255, 0, 0, brightness)
end

function launchpadDeviceRgb(brightness)
  return launchpadRgb255(51, 153, 255, brightness)
end

function launchpadUserRgb(brightness)
  return launchpadRgb255(200, 200, 255, brightness)
end

function launchpadSceneRgb(brightness)
  return launchpadRgb255(255, 255, 255, brightness)
end

function launchpadLockRgb(brightness)
  return launchpadRgb255(255, 0, 0, brightness)
end

function isBusLocked(busNum)
  local tag = json.toTable(root.tag) or {}
  local locks = tag.busLock
  return type(locks) == "table" and locks[tostring(busNum)] == true
end

-- Programmer layout: note = 10 * row + col (row 1 = bottom, row 8 = top).
-- Scene slot 1 = top → same shape as preset note = bus + 80 - (slot - 1) * 10.
function launchpadSceneNote(sceneNum)
  sceneNum = tonumber(sceneNum) or 1
  local col = (sceneNum <= 8) and 7 or 8
  local slot = ((sceneNum - 1) % 8) + 1
  return col + 80 - (slot - 1) * 10
end

function buildLaunchpadSceneNoteToSceneMap()
  local map = {}
  for sceneNum = 1, 16 do
    map[launchpadSceneNote(sceneNum)] = sceneNum
  end
  return map
end
