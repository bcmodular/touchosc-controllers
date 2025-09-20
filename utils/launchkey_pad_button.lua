local inControlMidiPort = {false, false, true, false}

-- Colours:
-- Bright green = 124
-- Bright red = 79
-- Light red = 65
-- Orange = 83
-- Yellow = 127
-- Off = 0
local function getPadNumber()
    -- Get the button's index within its parent grid
    local parent = self.parent
    if parent.name ~= 'pad' then
        print("I'm the parent")
        return 0
    end

    -- Find this button's index in the parent's children
    for i = 1, #parent.children do
        if parent.children[tostring(i)] == self then
            return i
        end
    end
end

-- Convert pad number to MIDI note
-- Based on Ableton Live sequence: C6 (96) and E7 (100) are the actual Launchkey Mini pad notes
-- Grid layout (top to bottom, left to right):
-- Top row: C6-G#6 (notes 96-103), Bottom row: E7-B7 (notes 112-119)
local function padNumberToMidiNote(padNumber)
    if padNumber >= 1 and padNumber <= 8 then
        -- Top row: C6 to G#6 (notes 96-103)
        return 95 + padNumber
    elseif padNumber >= 9 and padNumber <= 16 then
        -- Bottom row: E7 to C8 (notes 112-119)
        -- E7 = 112, so pad 9 = 112, pad 10 = 113, etc.
        return 103 + padNumber
    else
        print("Invalid pad number: " .. padNumber)
        return 96 -- Default to C6
    end
end

-- Handle button press/release
function onValueChanged(key, value)
  print("onValueChanged called:", key, value)
  if key == 'x' then
    local padNumber = getPadNumber()
    if padNumber == 0 then
      return
    end
    local midiNote = padNumberToMidiNote(padNumber)
    print("Pad " .. padNumber .. " -> MIDI Note " .. midiNote)

    if self.values.x == 1 then
        -- Button pressed - send Note On (Channel 1 = 0x90)
        sendMIDI({0x90, midiNote, 63}, inControlMidiPort) -- Velocity 63 like Ableton
        print("Pad " .. padNumber .. " ON (Note " .. midiNote .. ", Channel 1)")
    else
        -- Button released - send Note Off (Channel 1 = 0x80)
        sendMIDI({0x80, midiNote, 0}, inControlMidiPort)
        print("Pad " .. padNumber .. " OFF (Note " .. midiNote .. ", Channel 1)")

        -- Also try sending Note On with velocity 0 (some devices prefer this)
        --sendMIDI({0x90, midiNote, 0}, inControlMidiPort)
        --print("Pad " .. padNumber .. " OFF (Note " .. midiNote .. ", velocity 0)")
    end
  end
end

print("Launchkey pad button script loaded for pad " .. getPadNumber())
