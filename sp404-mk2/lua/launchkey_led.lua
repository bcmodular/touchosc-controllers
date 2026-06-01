-- launchkey_led.lua — Launchkey MK4 pad LED control (included into root.lua).
--
-- Protocol: Launchkey MK4 Programmer Reference Guide v2, page 14.
--
-- DAW mode is required for drum pad LED coloring:
--   1. Enable DAW mode:    9F 0C 7F  (Note-On ch16, note 12, vel 127)  → DAW port
--   2. Enable drum mode:   B6 54 01  (CC ch7, CC 84, val 1)            → DAW port
--   3. Color pad LED:      99 <note> <paletteIndex>  (Note-On ch10)    → DAW port
--   4. On detach — disable drum mode: B6 54 00, then DAW mode: 9F 0C 00
--
-- Pad note numbers in DAW drum mode may differ from standalone (TBD from testing).
-- Hyper Reso-specific color/sync logic lives in keyboard_manager.lua.

local LAUNCHKEY_DAW_CONNECTION = { false, false, false, false, true } -- connection 5

-- Enable DAW mode on the Launchkey (required for LED control).
-- Confirmed working: Launchkey responds with CC29=2 (DAW layout pad mode).
-- No drum mode needed — RGB SysEx works regardless of pad mode.
function enableLaunchkeyDawMode()
  sendMIDI({ 0x9F, 0x0C, 0x7F }, LAUNCHKEY_DAW_CONNECTION) -- DAW mode on
end

-- Disable DAW mode on the Launchkey.
function disableLaunchkeyDawMode()
  sendMIDI({ 0x9F, 0x0C, 0x00 }, LAUNCHKEY_DAW_CONNECTION) -- DAW mode off
end

-- Color a pad LED via RGB SysEx (channel-independent; works in DAW mode).
-- F0 00 20 29 02 14 01 43 <padID> <R> <G> <B> F7
-- padID: the pad's MIDI note number. Range 0–127 for R/G/B.
function sendLaunchkeyPadRgb(padNote, r, g, b)
  sendMIDI({
    0xF0, 0x00, 0x20, 0x29, 0x02, 0x14, 0x01, 0x43,
    padNote,
    math.max(0, math.min(127, r)),
    math.max(0, math.min(127, g)),
    math.max(0, math.min(127, b)),
    0xF7,
  }, LAUNCHKEY_DAW_CONNECTION)
end

function sendLaunchkeyPadOff(padNote)
  sendLaunchkeyPadRgb(padNote, 0, 0, 0)
end

function clearLaunchkeyPadLeds()
  -- Drum pad notes span 36–39, 40–43, 44–47, 48–51 (16 pads total).
  for note = 36, 51 do
    sendLaunchkeyPadOff(note)
  end
end
