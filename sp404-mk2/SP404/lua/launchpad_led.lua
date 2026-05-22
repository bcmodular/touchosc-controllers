-- Shared Launchpad Pro LED helpers (prepended into root.lua / preset_grid_manager.lua via toscbuild include).
-- RGB SysEx: F0 00 20 29 02 10 0B <led> <R> <G> <B> (R,G,B = 0..63)
-- Palette off: F0 ... 0A <led> 00 F7

-- Must be defined here (before helpers). TouchOSC Lua does not see locals declared later in the host script.
LAUNCHPAD_MIDI_CONNECTION = { false, false, true }

-- Dim vs bright: wide gap so idle is visible but clearly weaker than active.
LAUNCHPAD_IDLE_BRIGHTNESS = 0.18
LAUNCHPAD_ON_BRIGHTNESS = 1.0
LAUNCHPAD_PRESS_BRIGHTNESS = 0.88
-- FX bus round buttons (CC 91–95) when effect is off — very low; ~1 step on Launchpad RGB.
LAUNCHPAD_BUS_OFF_BRIGHTNESS = 0.02

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

function launchpadShiftRgb(brightness)
  return launchpadRgb255(255, 255, 255, brightness)
end

function launchpadDeleteRgb(brightness)
  return launchpadRgb255(255, 0, 0, brightness)
end

function launchpadSceneRgb(brightness)
  return launchpadRgb255(255, 255, 255, brightness)
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
