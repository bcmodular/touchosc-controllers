-- launchkey_led.lua — Launchkey MK4 pad LED primitives (included into root.lua).
--
-- Protocol: Launchkey MK4 Programmer Reference Guide v2, page 14.
--
-- Approach A — Note-On ch1 (palette index as velocity):
--   Status: 0x90 (Note-On ch1)  Note: pad MIDI note  Velocity: palette color index
--   "For all controls... a note matching those described in the reports can be sent
--    to colour the corresponding LED... Channel 1: Set stationary colour."
--   Test whether this works for standalone drum pads (they report on ch10 in standalone).
--
-- Approach B — RGB SysEx (kept for reference; requires DAW mode):
--   F0 00 20 29 02 14 01 43 <padID> <R> <G> <B> F7
--
-- Novation color palette indices (approximate — verify against physical device):
--   0 = off    3 = white    5 = white bright
--  33 = blue  41 = purple  45 = gold/amber   60 = amber  62 = yellow
-- Hyper Reso-specific color/sync logic lives in keyboard_manager.lua (inside
-- _initKeyboard()) where it can access HYPER_RESO_PAD_MAP and getHyperResoBusState.

local LAUNCHKEY_LED_CONNECTION = { false, false, false, true } -- connection 4

-- Send an RGB color to a pad LED via SysEx.
function sendLaunchkeyPadRgb(padNote, r, g, b)
  sendMIDI({
    0xF0, 0x00, 0x20, 0x29, 0x02, 0x14, 0x01, 0x43,
    padNote,
    math.max(0, math.min(127, r)),
    math.max(0, math.min(127, g)),
    math.max(0, math.min(127, b)),
    0xF7,
  }, LAUNCHKEY_LED_CONNECTION)
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
