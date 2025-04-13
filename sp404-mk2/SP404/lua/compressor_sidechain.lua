-- Are we in edit mode or perform mode?
local editMode = false

-- Envelope settings
local attackTimeMs = 10
local releaseTimeMs = 500
local curveType = "exponential"

-- Internal state variables
local currentEnvelopeValue = 0
local isTriggered = false
local isEnabled = false
local lastTime = 0
local triggerMidiChannel = 0
local triggerNote = 36

-- Modulation strength values
local ratioMod = 0.7
local levelMod = 0.3
local sustainMod = 0.2

-- Store base values for parameters
local baseValues = {
  ratio = 0,
  level = 0,
  sustain = 0
}

local ratioFader = nil
local levelFader = nil
local sustainFader = nil

local function padNumberToMidiNote(padNumber)
  -- The SP404 mk2 pads are arranged in a 4x4 grid
  -- Pad numbers run 1-16 from top to bottom
  -- MIDI notes run left to right, bottom to top
  -- Pad layout (numbers show pad ordering):
  -- 1  2  3  4
  -- 5  6  7  8
  -- 9  10 11 12
  -- 13 14 15 16

  -- MIDI note layout (notes show MIDI note numbers):
  -- 48 49 50 51
  -- 44 45 46 47
  -- 40 41 42 43
  -- 36 37 38 39

  -- Convert pad number to MIDI note
  local row = math.floor((padNumber - 1) / 4)  -- 0-3
  local col = (padNumber - 1) % 4              -- 0-3
  return 36 + col + (3 - row) * 4  -- 3-row because we need to count from bottom
end

local function midiNoteToPadNumber(note)
  -- Convert MIDI note to pad number
  -- Note range is 36-51
  if note < 36 or note > 51 then
    return 1  -- Default to first pad if invalid note
  end

  local baseNote = note - 36  -- Convert to 0-15 range
  local row = 3 - math.floor(baseNote / 4)  -- 0-3 from top to bottom
  local col = baseNote % 4                   -- 0-3 from left to right
  return row * 4 + col + 1  -- Convert to 1-16 range
end

local function configureMidiMessage()
  local midiMessage = self.messages.MIDI[1]
  midiMessage.channel = triggerMidiChannel
  midiMessage.note = triggerNote
end

local function usePerformModeControls()
  local faders = self.parent:findByName('faders', true)
  ratioFader = faders:findByName('3'):findByName('control_fader')
  levelFader = faders:findByName('4'):findByName('control_fader')
  sustainFader = faders:findByName('1'):findByName('control_fader')
end

local function updateBaseValues()
  baseValues.ratio = ratioFader.values.x
  baseValues.level = levelFader.values.x
  baseValues.sustain = sustainFader.values.x
end

-- Apply curve shaping to a linear progress value (0-1)
local function applyCurve(progress, curveType)
    if curveType == "linear" then
        return progress
    elseif curveType == "exponential" then
        return 1 - ((1 - progress) * (1 - progress))  -- Exponential curve
    elseif curveType == "logarithmic" then
        return progress * progress  -- Logarithmic curve
    else
        return progress  -- Default to linear if unknown
    end
end

-- Calculate modulated value based on envelope and headroom
local function calculateModulatedValue(baseValue, modStrength, envelopeValue, shouldReduce)
    local range = shouldReduce and baseValue or (1 - baseValue)
    local shapedEnvelope = applyCurve(envelopeValue, curveType)
    local modulation = range * modStrength * shapedEnvelope
    return shouldReduce and (baseValue - modulation) or (baseValue + modulation)
end

-- Update parameters based on current envelope value
local function updateParameters()
  local ratioValue = calculateModulatedValue(
    baseValues.ratio,
    ratioMod,
    currentEnvelopeValue,
    false  -- increase ratio when triggered
  )
  ratioFader.values.x = ratioValue

  local levelValue = calculateModulatedValue(
    baseValues.level,
    levelMod,
    currentEnvelopeValue,
    true   -- decrease level when triggered
  )
  levelFader.values.x = levelValue

  local sustainValue = calculateModulatedValue(
    baseValues.sustain,
    sustainMod,
    currentEnvelopeValue,
    false  -- increase sustain when triggered
  )
  sustainFader.values.x = sustainValue
end

local function returnToBaseValues()
  ratioFader.values.x = baseValues.ratio
  levelFader.values.x = baseValues.level
  sustainFader.values.x = baseValues.sustain
end

-- Update function called every frame
function update()
  if isEnabled then
    local currentTime = getMillis()
    local timeDelta = currentTime - lastTime
    lastTime = currentTime
    -- Update envelope value based on trigger state
    if isTriggered and currentEnvelopeValue < 1 then
      -- Attack phase - envelope is rising
      local attackSpeed = timeDelta / attackTimeMs
      currentEnvelopeValue = math.min(1, currentEnvelopeValue + attackSpeed)
    elseif not isTriggered and currentEnvelopeValue > 0 then
      -- Release phase - envelope is falling
      local releaseSpeed = timeDelta / releaseTimeMs
      currentEnvelopeValue = math.max(0, currentEnvelopeValue - releaseSpeed)
    elseif not isTriggered and currentEnvelopeValue == 0 then
      returnToBaseValues()
    end

    -- Update parameters if envelope value changed
    updateParameters()
  end
end

local function handleMidiMessage(message)
  print('handleMidiMessage:', unpack(message))

  if message[1] - triggerMidiChannel == 144 then
    if message[2] == triggerNote then
      print('trigger note on')
      isTriggered = true
    end
  end

  if message[1] - triggerMidiChannel == 128 then
    if message[2] == triggerNote then
      print('trigger note off')
      isTriggered = false
    end
  end
end

local function toggleSidechain(value)
  isEnabled = value > 0
  if isEnabled then
    updateBaseValues()  -- Capture current state of faders
  else
    returnToBaseValues()
  end
end

local function createSidechainConfig(
  newTriggerNote,
  newTriggerMidiChannel,
  newSustainMod,
  newRatioMod,
  newLevelMod,
  newAttackMs,
  newReleaseMs,
  newCurve,
  newEnabled
)
  return {
    triggerNote = newTriggerNote or 36,
    triggerMidiChannel = newTriggerMidiChannel or 0,
    modulationStrength = {
      sustain = newSustainMod or 0.2,
      ratio = newRatioMod or 0.7,
      level = newLevelMod or 0.3
    },
    attackTimeMs = newAttackMs or 10,
    releaseTimeMs = newReleaseMs or 500,
    curveType = newCurve or "exponential",
    enabled = newEnabled or false
  }
end

-- Structure for storing all sidechain data
local function createSidechainStorage()
  return {
    defaults = createSidechainConfig(),  -- Global defaults
    presets = {},                        -- Global presets (string keys)
    recent = {}                          -- Recent values per bus (string keys)
  }
end

-- Function to save all sidechain data to the control's tag
local function saveSidechainData(data)
  self.tag = json.fromTable(data)
end

-- Function to load all sidechain data from the control's tag
local function loadSidechainData()
  local storedData = json.toTable(self.tag)
  if not storedData then
    -- Initialize with just defaults if no data exists
    storedData = createSidechainStorage()
    saveSidechainData(storedData)
  end
  return storedData
end

-- Function to update recent values for current bus
local function updateRecentValues(busNumber)
  local data = loadSidechainData()
  data.recent[tostring(busNumber)] = createSidechainConfig(
    triggerNote,
    triggerMidiChannel,
    sustainMod,
    ratioMod,
    levelMod,
    attackTimeMs,
    releaseTimeMs,
    curveType,
    isEnabled
  )
  saveSidechainData(data)
end

-- Function to store global defaults
local function storeDefaults()
  local data = loadSidechainData()
  data.defaults = createSidechainConfig(
    triggerNote,
    triggerMidiChannel,
    sustainMod,
    ratioMod,
    levelMod,
    attackTimeMs,
    releaseTimeMs,
    curveType,
    isEnabled
  )
  saveSidechainData(data)
end

-- Function to store a preset
local function storePreset(presetNumber)
  local data = loadSidechainData()
  data.presets[tostring(presetNumber)] = createSidechainConfig(
    triggerNote,
    triggerMidiChannel,
    sustainMod,
    ratioMod,
    levelMod,
    attackTimeMs,
    releaseTimeMs,
    curveType,
    isEnabled
  )
  saveSidechainData(data)
end

-- Function to recall a preset
local function recallPreset(presetNumber)
  local data = loadSidechainData()
  local preset = data.presets[tostring(presetNumber)]
  if not preset then
    return
  end

  -- Apply the preset values
  triggerNote = preset.triggerNote
  triggerMidiChannel = preset.triggerMidiChannel
  sustainMod = preset.modulationStrength.sustain
  ratioMod = preset.modulationStrength.ratio
  levelMod = preset.modulationStrength.level
  attackTimeMs = preset.attackTimeMs
  releaseTimeMs = preset.releaseTimeMs
  curveType = preset.curveType
  isEnabled = preset.enabled

  -- Update recent values after recall
  local currentBus = tonumber(self.parent.parent.name) or 1
  updateRecentValues(currentBus)
end

-- Function to recall recent values for a bus
local function recallRecent(busNumber)
  local data = loadSidechainData()
  local recent = data.recent[tostring(busNumber)]
  if not recent then
    return
  end

  -- Apply the recent values
  triggerNote = recent.triggerNote
  triggerMidiChannel = recent.triggerMidiChannel
  sustainMod = recent.modulationStrength.sustain
  ratioMod = recent.modulationStrength.ratio
  levelMod = recent.modulationStrength.level
  attackTimeMs = recent.attackTimeMs
  releaseTimeMs = recent.releaseTimeMs
  curveType = recent.curveType
  isEnabled = recent.enabled
end

-- Function to recall defaults
local function recallDefaults()
  local data = loadSidechainData()
  local defaults = data.defaults

  -- Apply the default values
  triggerNote = defaults.triggerNote
  triggerMidiChannel = defaults.triggerMidiChannel
  sustainMod = defaults.modulationStrength.sustain
  ratioMod = defaults.modulationStrength.ratio
  levelMod = defaults.modulationStrength.level
  attackTimeMs = defaults.attackTimeMs
  releaseTimeMs = defaults.releaseTimeMs
  curveType = defaults.curveType
  isEnabled = defaults.enabled

  -- Update recent values after recall
  local currentBus = tonumber(self.parent.parent.name) or 1
  updateRecentValues(currentBus)
end

local function attackRangeToFader(value)
  return value / 100
end

local function releaseRangeToFader(value)
  return value / 2000
end

local function attackFaderToRange(value)
  return value * 100
end

local function releaseFaderToRange(value)
  return value * 2000
end

local function curveTypeToFader(value)
  if value == "linear" then
    return 0
  elseif value == "exponential" then
    return 0.5
  elseif value == "logarithmic" then
    return 1
  end
end

local function curveFaderToType(value)
  if value < 0.3 then
    return 'linear'
  elseif value < 0.6 then
    return 'exponential'
  else
    return 'logarithmic'
  end
end

local function updateEditModeControls(compressorEditPage)
  local editCompressorSidechain = compressorEditPage:findByName('edit_compressor_sidechain', true)
  local ratioModFader = editCompressorSidechain:findByName('ratio_fader_group').children.control_fader
  local levelModFader = editCompressorSidechain:findByName('level_fader_group').children.control_fader
  local sustainModFader = editCompressorSidechain:findByName('sustain_fader_group').children.control_fader
  local attackTimeMsFader = editCompressorSidechain:findByName('attack_fader_group').children.control_fader
  local releaseTimeMsFader = editCompressorSidechain:findByName('release_fader_group').children.control_fader
  local curveTypeFader = editCompressorSidechain:findByName('curve_fader_group').children.control_fader
  local noteLabel = editCompressorSidechain:findByName('note_label', true)
  local bankSelect = editCompressorSidechain:findByName('bank_select', true)
  local enableSidechainButton = editCompressorSidechain:findByName('enable_sidechain_button', true)

  print('found edit mode controls: ', ratioModFader.name, levelModFader.name, sustainModFader.name, attackTimeMsFader.name, releaseTimeMsFader.name, curveTypeFader.name, noteLabel.name, bankSelect.name)

  ratioModFader.values.x = ratioMod
  levelModFader.values.x = levelMod
  sustainModFader.values.x = sustainMod
  attackTimeMsFader.values.x = attackRangeToFader(attackTimeMs)
  releaseTimeMsFader.values.x = releaseRangeToFader(releaseTimeMs)
  curveTypeFader.values.x = curveTypeToFader(curveType)

  noteLabel.values.text = tostring(midiNoteToPadNumber(triggerNote))
  bankSelect:notify('set', triggerMidiChannel + 1)
  enableSidechainButton.values.x = isEnabled and 1 or 0
end

local function useEditModeControls()
  local compressorEditPage = root.children.control_pager.children[37]
  print('compressorEditPage:', compressorEditPage.name)

  ratioFader = compressorEditPage:findByName('ratio_fader', true)
  levelFader = compressorEditPage:findByName('level_fader', true)
  sustainFader = compressorEditPage:findByName('sustain_fader', true)

  print('found edit mode controls: ', ratioFader.name, levelFader.name, sustainFader.name)

  updateEditModeControls(compressorEditPage)
end

local function switchMode()
  if editMode then
    useEditModeControls()
  else
    usePerformModeControls()
  end
end

local function updateValue(key, value)
  print('updateValue:', key, value)
  if key == 'ratio_mod' then
    ratioMod = value
  elseif key == 'level_mod' then
    levelMod = value
  elseif key == 'sustain_mod' then
    sustainMod = value
  elseif key == 'attack_time_ms' then
    attackTimeMs = attackFaderToRange(value)
  elseif key == 'release_time_ms' then
    releaseTimeMs = releaseFaderToRange(value)
  elseif key == 'curve_type' then
    curveType = curveFaderToType(value)
  elseif key == 'trigger_note' then
    triggerNote = padNumberToMidiNote(value)
    print('new triggerNote:', triggerNote)
  elseif key == 'trigger_midi_channel' then
    triggerMidiChannel = value
    print('new triggerMidiChannel:', triggerMidiChannel)
  end
end

-- Modify onReceiveNotify to handle the new storage system
function onReceiveNotify(key, value)
  local currentBus = tonumber(self.parent.parent.name) or 1

  if key == 'store_preset' then
    local presetNumber = tonumber(value)
    storePreset(presetNumber)
  elseif key == 'recall_preset' then
    local presetNumber = tonumber(value)
    recallPreset(presetNumber)
  elseif key == 'store_defaults' then
    storeDefaults()
  elseif key == 'recall_defaults' then
    recallDefaults()
  elseif key == 'bus_changed' then
    -- Store recent values for previous bus before switching
    updateRecentValues(currentBus)
    -- Load recent values for new bus
    local newBus = tonumber(value)
    recallRecent(newBus)
  elseif key == 'toggle_sidechain' then
    toggleSidechain(value)
  elseif key == 'trigger_sidechain' then
    isTriggered = value > 0
  elseif key == 'switch_mode' then
    editMode = root:findByName('edit_mode').values.x > 0
    switchMode()
  elseif key == 'update_value' then
    updateValue(value[1], value[2])
  elseif key == 'midi_message' then
    handleMidiMessage(value)
  end
end

function init()
  isTriggered = false
  isEnabled = false
  usePerformModeControls()
  updateBaseValues()
  lastTime = getMillis()

  -- Initialize storage if it doesn't exist
  if self.tag == '' then
    local initialData = createSidechainStorage()
    saveSidechainData(initialData)
  end
end
