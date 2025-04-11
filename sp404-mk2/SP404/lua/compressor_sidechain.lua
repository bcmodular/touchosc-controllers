-- Envelope settings
local ATTACK_TIME_MS = 10      -- How quickly parameters rise when triggered
local RELEASE_TIME_MS = 500    -- How slowly parameters fall when released
local CURVE_TYPE = "exponential"  -- "linear", "exponential", or "logarithmic"

-- Internal state variables
local current_envelope_value = 0
local is_triggered = false
local is_enabled = false
local last_time = 0
local trigger_note = 36  -- MIDI note that triggers sidechain (e.g., kick drum)

-- Configuration for parameter modulation (0-1)
-- How much of the available headroom to use for each parameter
local modulation_strength = {
  ratio = 0.7,    -- Use up to 70% of available ratio headroom
  level = 0.3,    -- Use up to 30% of available level headroom
  sustain = 0.2   -- Use up to 20% of available sustain headroom
}

-- Store base values for parameters
local base_values = {
  ratio = 0,
  level = 0,
  sustain = 0
}

-- Function to read current widget values as base values
local function updateBaseValues()
  base_values.ratio = self.parent.children.ratio_fader.values.x
  base_values.level = self.parent.children.level_fader.values.x
  base_values.sustain = self.parent.children.sustain_fader.values.x
end

-- Apply curve shaping to a linear progress value (0-1)
local function applyCurve(progress, curve_type)
    if curve_type == "linear" then
        return progress
    elseif curve_type == "exponential" then
        return 1 - ((1 - progress) * (1 - progress))  -- Exponential curve
    elseif curve_type == "logarithmic" then
        return progress * progress  -- Logarithmic curve
    else
        return progress  -- Default to linear if unknown
    end
end

-- Calculate modulated value based on envelope and headroom
local function calculateModulatedValue(base_value, modulation_strength_value, envelope_value, should_reduce)
    -- Calculate available range (0-1 range in TouchOSC)
    local range = should_reduce and base_value or (1 - base_value)

    -- Calculate modulation based on envelope value with curve applied
    local shaped_envelope = applyCurve(envelope_value, CURVE_TYPE)

    -- Apply modulation based on available range
    local modulation = range * modulation_strength_value * shaped_envelope

    -- Return base value plus or minus modulation depending on should_reduce
    return should_reduce and (base_value - modulation) or (base_value + modulation)
end

-- Update parameters based on current envelope value
local function updateParameters()
  -- Calculate and set new values for each parameter
  local ratio_value = calculateModulatedValue(
    base_values.ratio,
    modulation_strength.ratio,
    current_envelope_value,
    false  -- increase ratio when triggered
  )
  self.parent.children.ratio_fader.values.x = ratio_value

  local level_value = calculateModulatedValue(
    base_values.level,
    modulation_strength.level,
    current_envelope_value,
    true   -- decrease level when triggered
  )
  self.parent.children.level_fader.values.x = level_value

  local sustain_value = calculateModulatedValue(
    base_values.sustain,
    modulation_strength.sustain,
    current_envelope_value,
    false  -- increase sustain when triggered
  )
  self.parent.children.sustain_fader.values.x = sustain_value
end

-- Handle MIDI note on event
local function onMidiNoteOn(message)
  if message[2] == trigger_note then
    is_triggered = true
  end
end

-- Handle MIDI note off event
local function onMidiNoteOff(message)
  if message[2] == trigger_note then
     is_triggered = false
  end
end

local function returnToBaseValues()
  self.parent.children.ratio_fader.values.x = base_values.ratio
  self.parent.children.level_fader.values.x = base_values.level
  self.parent.children.sustain_fader.values.x = base_values.sustain
end

-- Update function called every frame
function update()
  if is_enabled then
    local current_time = getMillis()
    local time_delta = current_time - last_time
    last_time = current_time
    --print('update')
    --print('\t is_triggered =', is_triggered)
    --print('\t current_envelope_value =', current_envelope_value)
    -- Update envelope value based on trigger state
    if is_triggered and current_envelope_value < 1 then
      -- Attack phase - envelope is rising
      local attack_speed = time_delta / ATTACK_TIME_MS
      current_envelope_value = math.min(1, current_envelope_value + attack_speed)
    elseif not is_triggered and current_envelope_value > 0 then
      -- Release phase - envelope is falling
      local release_speed = time_delta / RELEASE_TIME_MS
      current_envelope_value = math.max(0, current_envelope_value - release_speed)
    elseif not is_triggered and current_envelope_value == 0 then
      returnToBaseValues()
    end

    -- Update parameters if envelope value changed
    updateParameters()
  end
end

function onReceiveMIDI(message, connections)
  --print('onReceiveMIDI')
  --print('\t message     =', unpack(message))
  --print('\t connections =', unpack(connections))

  if message[1] >= 144 and message[1] <= 159 and message[3] > 0 then
    onMidiNoteOn(message)
  -- Note Off (status byte: 128-143 or Note On with velocity 0)
  elseif (message[1] >= 128 and message[1] <= 143) or
        (message[1] >= 144 and message[1] <= 159 and message[3] == 0) then
    onMidiNoteOff(message)
  end
end

-- Manual trigger function - can be connected to a button in TouchOSC
local function triggerSidechain(value)
    if value > 0 then
        is_triggered = true
    else
        is_triggered = false
    end
end

local function enableSidechain()
  is_enabled = true
  updateBaseValues()  -- Capture current state of faders
end

local function disableSidechain()
  is_enabled = false
  returnToBaseValues()
end

function onReceiveNotify(key, value)
  if key == 'enable_sidechain' then
    print('enable_sidechain', value)
    enableSidechain()
  elseif key == 'disable_sidechain' then
    print('disable_sidechain', value)
    disableSidechain()
  elseif key == 'trigger_sidechain' then
    print('trigger_sidechain', value)
    triggerSidechain(value)
  end
end

function init()
  is_triggered = false
  is_enabled = false
  updateBaseValues()
  last_time = getMillis()
  print("Sidechain controller initialized")
end
