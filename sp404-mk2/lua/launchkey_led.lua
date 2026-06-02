-- launchkey_led.lua — Launchkey MK4 pad mode + encoder mode switching.
-- Included into root.lua. All messages go to the DAW port (connection 5).
--
-- Pad colors are configured in the Novation Connections app as standalone drum
-- custom modes. Encoder parameter names are also configured in Connections as
-- standalone encoder custom modes.
--
-- Pad mode select:     B6 1D <mode>  (CC ch7, CC 29)  → DAW port
--   01h = Layout (default drum mode)
--   05h = Custom Mode 1  (Hyper Reso pads)
--   06h = Custom Mode 2  (Resonator pads)
--   07h = Custom Mode 3  (Vocoder pads)
--
-- Encoder mode select: B6 1E <mode>  (CC ch7, CC 30)  → DAW port
--   06h = Custom Mode 1  (factory default / general use)
--   07h = Custom Mode 2  (Hyper Reso encoder labels)
--   08h = Custom Mode 3  (Resonator encoder labels)
--   09h = Custom Mode 4  (Vocoder encoder labels)
--
-- Feature controls (9F 0B 7F) must be enabled before mode selects work in
-- standalone mode.

local LAUNCHKEY_DAW_CONNECTION = { false, false, false, false, true } -- connection 5

-- Switch to a Launchkey drum Custom Mode (1-indexed).
-- Requires feature controls enabled (9F 0B 7F) in standalone mode.
function switchLaunchkeyDrumCustomMode(modeNumber)
  sendMIDI({ 0x9F, 0x0B, 0x7F }, LAUNCHKEY_DAW_CONNECTION) -- enable feature controls
  sendMIDI({ 0xB6, 0x1D, 0x04 + modeNumber }, LAUNCHKEY_DAW_CONNECTION) -- pad mode select
end

-- Return to the default standalone drum layout.
function resetLaunchkeyDrumMode()
  sendMIDI({ 0x9F, 0x0B, 0x7F }, LAUNCHKEY_DAW_CONNECTION)
  sendMIDI({ 0xB6, 0x1D, 0x01 }, LAUNCHKEY_DAW_CONNECTION)
end

-- Switch to a Launchkey encoder Custom Mode (1-indexed).
--   modeNumber 1 → 06h (Custom Mode 1, factory default)
--   modeNumber 2 → 07h (Custom Mode 2, Hyper Reso labels)
--   modeNumber 3 → 08h (Custom Mode 3, Resonator labels)
--   modeNumber 4 → 09h (Custom Mode 4, Vocoder labels)
function switchLaunchkeyEncoderCustomMode(modeNumber)
  sendMIDI({ 0x9F, 0x0B, 0x7F }, LAUNCHKEY_DAW_CONNECTION)
  sendMIDI({ 0xB6, 0x1E, 0x05 + modeNumber }, LAUNCHKEY_DAW_CONNECTION)
end

-- Return encoders to Custom Mode 1 (factory default set).
function resetLaunchkeyEncoderMode()
  sendMIDI({ 0x9F, 0x0B, 0x7F }, LAUNCHKEY_DAW_CONNECTION)
  sendMIDI({ 0xB6, 0x1E, 0x06 }, LAUNCHKEY_DAW_CONNECTION)
end
