-- launchkey_led.lua — Launchkey MK4 pad mode control (included into root.lua).
--
-- Pad colors are configured in the Novation Connections app as custom drum modes.
-- TouchOSC enables DAW mode and switches to the appropriate custom mode.
--
-- Protocol (Launchkey MK4 Programmer Reference Guide v2):
--   Enable DAW mode:  9F 0C 7F  (Note-On ch16, note 12, vel 127)  → DAW port
--   Disable DAW mode: 9F 0C 00                                     → DAW port
--   Switch pad mode:  B6 1D <mode>  (CC ch7, CC 29)                → DAW port
--     mode 05h = Custom Mode 1  (Hyper Reso layout)
--     mode 06h = Custom Mode 2  (Resonator layout)
--
-- Connection 5 = Launchkey DAW MIDI port (second USB interface).

local LAUNCHKEY_DAW_CONNECTION = { false, false, false, false, true } -- connection 5

function enableLaunchkeyDawMode()
  sendMIDI({ 0x9F, 0x0C, 0x7F }, LAUNCHKEY_DAW_CONNECTION)
end

function disableLaunchkeyDawMode()
  sendMIDI({ 0x9F, 0x0C, 0x00 }, LAUNCHKEY_DAW_CONNECTION)
end

-- Switch to a Launchkey pad custom mode (1-indexed: 1 = Custom Mode 1, etc.).
function switchLaunchkeyDrumCustomMode(modeNumber)
  sendMIDI({ 0xB6, 0x1D, 0x04 + modeNumber }, LAUNCHKEY_DAW_CONNECTION)
end
