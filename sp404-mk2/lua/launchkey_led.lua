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

-- Chord grid pad index → Launchkey drum pad MIDI note.
-- Inverse of PAD_NOTE_TO_INDEX in keyboard_manager.lua:routePadNote.
local LAUNCHKEY_CHORD_PAD_TO_NOTE = {
  [1]=40, [2]=41, [3]=42, [4]=43,
  [5]=48, [6]=49, [7]=50, [8]=51,
  [9]=36, [10]=37, [11]=38, [12]=39,
  [13]=44, [14]=45, [15]=46, [16]=47,
}

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
  for _, note in pairs(LAUNCHKEY_CHORD_PAD_TO_NOTE) do
    sendLaunchkeyPadOff(note)
  end
end
