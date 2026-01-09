-- Global variables
local currentVelocity = 127
local inControlMidiPort = {false, false, true, false}

-- Function to activate InControl mode
local function activateInControl()
    print("Activating Launchkey Mini InControl mode...")
    sendMIDI({0x90, 0x0C, 0x7F}, inControlMidiPort) -- C-1, velocity 127
end

-- TouchOSC callback functions
function init()
    -- Auto-activate InControl mode when script loads
    activateInControl()
    print("Launchkey Mini InControl script loaded!")
end
