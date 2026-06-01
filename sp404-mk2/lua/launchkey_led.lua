-- launchkey_led.lua — Launchkey MK4 pad LED primitives (included into root.lua).
--
-- Protocol: Launchkey MK4 Programmer Reference Guide v2, page 14.
-- RGB SysEx (Regular SKU, channel-independent):
--   F0 00 20 29 02 14 01 43 <padID> <R> <G> <B> F7
-- padID = the MIDI note number the pad sends/receives.
-- R/G/B range: 0–127 (7-bit; test with max=127 first; may be 0–63 like Launchpad).
--
-- Sends on the primary MIDI interface (same connection index as keyboard input).
-- Hyper Reso-specific color/sync logic lives in keyboard_manager.lua (inside
-- _initKeyboard()) where it can access HYPER_RESO_PAD_MAP and getHyperResoBusState.

local LAUNCHKEY_LED_CONNECTION = { false, false, false, true } -- connection 4


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
