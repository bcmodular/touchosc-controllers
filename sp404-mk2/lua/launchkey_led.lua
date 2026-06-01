-- launchkey_led.lua — Launchkey MK4 pad mode switching (included into root.lua).
--
-- Pad colors are configured in the Novation Connections app as standalone drum
-- custom modes. TouchOSC switches between them via MIDI on the DAW port.
--
-- Pad mode select: B6 1D <mode>  (CC ch7, CC 29)  → DAW port (connection 5)
--   mode 01h = Layout (default drum mode)
--   mode 05h = Custom Mode 1  (Hyper Reso layout)
--   mode 06h = Custom Mode 2  (Resonator layout)

local LAUNCHKEY_DAW_CONNECTION = { false, false, false, false, true } -- connection 5

-- Switch to a Launchkey drum custom mode (1-indexed).
-- Requires feature controls enabled first (9F 0B 7F) in standalone mode.
function switchLaunchkeyDrumCustomMode(modeNumber)
  sendMIDI({ 0x9F, 0x0B, 0x7F }, LAUNCHKEY_DAW_CONNECTION) -- enable feature controls
  sendMIDI({ 0xB6, 0x1D, 0x04 + modeNumber }, LAUNCHKEY_DAW_CONNECTION)
end

-- Return to the default standalone drum layout.
function resetLaunchkeyDrumMode()
  sendMIDI({ 0x9F, 0x0B, 0x7F }, LAUNCHKEY_DAW_CONNECTION) -- enable feature controls
  sendMIDI({ 0xB6, 0x1D, 0x01 }, LAUNCHKEY_DAW_CONNECTION)
end
