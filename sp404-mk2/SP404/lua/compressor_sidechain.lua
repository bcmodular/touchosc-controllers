local sidechainScript = [[
-- Are we in edit mode or perform mode?
local editMode = false
local busNum = tonumber(self.parent.parent.tag) + 1
local compressorEditPage = root.children.control_pager.children[37]

print('Initializing compressor sidechain for bus:', busNum)

-- Envelope settings
local attackTimeMs = 10
local releaseTimeMs = 500
local curveType = "exponential"

-- Internal state variables
local currentEnvelopeValue = 0
local compressorSelected = false
local isTriggered = false
local isEnabled = false
local lastTime = 0
local triggerMidiChannel = 0
local triggerNote = 36

print('Initial state - Envelope:', currentEnvelopeValue, 'Triggered:', isTriggered, 'Enabled:', isEnabled)

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

local function usePerformModeControls()
  local faders = self.parent:findByName('faders', true)
  ratioFader = faders:findByName('3'):findByName('control_fader')
  levelFader = faders:findByName('4'):findByName('control_fader')
  sustainFader = faders:findByName('1'):findByName('control_fader')
end

local function updateBaseValues()
  if ratioFader then
    baseValues.ratio = ratioFader.values.x
  end
  if levelFader then
    baseValues.level = levelFader.values.x
  end
  if sustainFader then
    baseValues.sustain = sustainFader.values.x
  end
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
  if ratioFader then
    ratioFader.values.x = ratioValue
  end

  local levelValue = calculateModulatedValue(
    baseValues.level,
    levelMod,
    currentEnvelopeValue,
    true   -- decrease level when triggered
  )
  if levelFader then
    levelFader.values.x = levelValue
  end

  local sustainValue = calculateModulatedValue(
    baseValues.sustain,
    sustainMod,
    currentEnvelopeValue,
    false  -- increase sustain when triggered
  )
  if sustainFader then
    sustainFader.values.x = sustainValue
  end
end

local function returnToBaseValues()
  if ratioFader then
    ratioFader.values.x = baseValues.ratio
  end
  if levelFader then
    levelFader.values.x = baseValues.level
  end
  if sustainFader then
    sustainFader.values.x = baseValues.sustain
  end
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

local function updateEditModeControls()
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
  print('compressorEditPage:', compressorEditPage.name)

  ratioFader = compressorEditPage:findByName('ratio_fader', true)
  levelFader = compressorEditPage:findByName('level_fader', true)
  sustainFader = compressorEditPage:findByName('sustain_fader', true)

  print('found edit mode controls: ', ratioFader.name, levelFader.name, sustainFader.name)

  updateEditModeControls()
end

local function handleMidiMessage(message)
  --print('Received MIDI message:', unpack(message))

  if message[1] - triggerMidiChannel == 144 then
    if message[2] == triggerNote then
      --print('Trigger note ON - Note:', message[2], 'Channel:', triggerMidiChannel)
      isTriggered = true
    end
  end

  if message[1] - triggerMidiChannel == 128 then
    if message[2] == triggerNote then
      --print('Trigger note OFF - Note:', message[2], 'Channel:', triggerMidiChannel)
      isTriggered = false
    end
  end
end

local function toggleFaderColours(sideChainOn)
  local faders = self.parent:findByName('faders', true)
  ratioFader = faders:findByName('3'):findByName('control_fader')
  levelFader = faders:findByName('4'):findByName('control_fader')
  sustainFader = faders:findByName('1'):findByName('control_fader')

  local pots = self.parent:findByName('pots', true)
  ratioPot = pots:findByName('3'):findByName('value')
  levelPot = pots:findByName('4'):findByName('value')
  sustainPot = pots:findByName('1'):findByName('value')

  if sideChainOn then
    print('Sidechain is on')
    sustainFader.color = Color.fromHexString("2486FFFF")
    ratioFader.color = Color.fromHexString("2486FFFF")
    levelFader.color = Color.fromHexString("2486FFFF")
    ratioPot.color = Color.fromHexString("2486FFFF")
    levelPot.color = Color.fromHexString("2486FFFF")
    sustainPot.color = Color.fromHexString("2486FFFF")
  else
    print('Sidechain is off')
    sustainFader.color = Color.fromHexString("FFA61AFF")
    ratioFader.color = Color.fromHexString("FFA61AFF")
    levelFader.color = Color.fromHexString("FFA61AFF")
    ratioPot.color = Color.fromHexString("FFA61AFF")
    levelPot.color = Color.fromHexString("FFA61AFF")
    sustainPot.color = Color.fromHexString("FFA61AFF")
  end
end

local function toggleSidechain(newEnabledState, ignoreBaseValues)
  print('ToggleSidechain - Bus:', busNum, 'New state:', newEnabledState)
  self.children.enable_sidechain_button.values.x = newEnabledState and 1 or 0
  toggleFaderColours(newEnabledState)

  if newEnabledState then
    updateBaseValues()
  else
    if not ignoreBaseValues then
      returnToBaseValues()
    end
  end
  isEnabled = newEnabledState
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
    newTriggerNote or 36,
    newTriggerMidiChannel or 1,
    newSustainMod or 0.2,
    newRatioMod or 0.7,
    newLevelMod or 0.3,
    newAttackMs or 10,
    newReleaseMs or 500,
    newCurve or "exponential",
    newEnabled or false
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

local function storeRecentValues()
  local data = loadSidechainData()
  data.recent[tostring(busNum)] = createSidechainConfig(
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
  print('Storing preset:', presetNumber)
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

  print('Stored preset values:')
  print('  Trigger Note:', triggerNote)
  print('  MIDI Channel:', triggerMidiChannel)
  print('  Sustain Mod:', sustainMod)
  print('  Ratio Mod:', ratioMod)
  print('  Level Mod:', levelMod)
  print('  Attack Time:', attackTimeMs)
  print('  Release Time:', releaseTimeMs)
  print('  Curve Type:', curveType)
  print('  Enabled:', isEnabled)

  saveSidechainData(data)
end

-- Function to delete a preset
local function deletePreset(presetNumber)
  local data = loadSidechainData()
  data.presets[tostring(presetNumber)] = nil
  saveSidechainData(data)
end

-- Function to recall a preset
local function recallPreset(presetNumber)
  print('Recalling preset:', presetNumber, 'Bus:', busNum)
  toggleSidechain(false, true)

  local data = loadSidechainData()
  local preset = data.presets[tostring(presetNumber)]
  if not preset then
    return
  end

  triggerNote = preset[1]
  triggerMidiChannel = preset[2]
  sustainMod = preset[3]
  ratioMod = preset[4]
  levelMod = preset[5]
  attackTimeMs = preset[6]
  releaseTimeMs = preset[7]
  curveType = preset[8]
  isEnabled = preset[9]

  toggleSidechain(isEnabled, true)
  updateEditModeControls()
end

-- Function to recall recent values for a bus
local function recallRecentValues()
  toggleSidechain(false, true)

  local data = loadSidechainData()
  local recent = data.recent[tostring(busNum)]
  if not recent then
    return
  end

  -- Apply the recent values
  triggerNote = recent[1]
  triggerMidiChannel = recent[2]
  sustainMod = recent[3]
  ratioMod = recent[4]
  levelMod = recent[5]
  attackTimeMs = recent[6]
  releaseTimeMs = recent[7]
  curveType = recent[8]
  isEnabled = recent[9]

  toggleSidechain(isEnabled, true)
  updateEditModeControls()
end

-- Function to recall defaults
local function recallDefaults()
  toggleSidechain(false, true)

  local data = loadSidechainData()
  local defaults = data.defaults

  -- Apply the default values
  triggerNote = defaults[1]
  triggerMidiChannel = defaults[2]
  sustainMod = defaults[3]
  ratioMod = defaults[4]
  levelMod = defaults[5]
  attackTimeMs = defaults[6]
  releaseTimeMs = defaults[7]
  curveType = defaults[8]
  isEnabled = defaults[9]

  toggleSidechain(isEnabled, true)
  updateEditModeControls()
end

local function switchMode()
  if editMode then
    useEditModeControls()
  else
    usePerformModeControls()
  end
end

local function updateValue(key, value)
  print('Updating parameter:', key, 'New value:', value)
  if key == 'ratio_mod' then
    ratioMod = value
    print('Ratio modulation set to:', ratioMod)
  elseif key == 'level_mod' then
    levelMod = value
    print('Level modulation set to:', levelMod)
  elseif key == 'sustain_mod' then
    sustainMod = value
    print('Sustain modulation set to:', sustainMod)
  elseif key == 'attack_time_ms' then
    attackTimeMs = attackFaderToRange(value)
    print('Attack time set to:', attackTimeMs, 'ms')
  elseif key == 'release_time_ms' then
    releaseTimeMs = releaseFaderToRange(value)
    print('Release time set to:', releaseTimeMs, 'ms')
  elseif key == 'curve_type' then
    curveType = curveFaderToType(value)
    print('Curve type set to:', curveType)
  elseif key == 'trigger_note' then
    triggerNote = padNumberToMidiNote(value)
    print('Trigger note set to:', triggerNote, '(Pad:', value, ')')
  elseif key == 'trigger_midi_channel' then
    triggerMidiChannel = value
    print('Trigger MIDI channel set to:', triggerMidiChannel)
  end
end

local function toggleButtons(show)
    self.visible = show
end

function onReceiveNotify(key, value)
  if key == 'store_preset' then
    local presetNumber = tonumber(value)
    storePreset(presetNumber)
  elseif key == 'recall_preset' then
    local presetNumber = tonumber(value)
    recallPreset(presetNumber)
  elseif key == 'delete_preset' then
    local presetNumber = tonumber(value)
    deletePreset(presetNumber)
  elseif key == 'store_defaults' then
    storeDefaults()
  elseif key == 'recall_defaults' then
    recallDefaults()
  elseif key == 'store_recent_values' then
    storeRecentValues()
  elseif key == 'recall_recent_values' then
    recallRecentValues()
  elseif key == 'toggle_compressor' then
    compressorSelected = value
    if compressorSelected then
      recallRecentValues()
    else
      toggleSidechain(false, false)
    end
    toggleButtons(compressorSelected)
  elseif key == 'toggle_sidechain' then
    toggleSidechain(value > 0, false)
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

-- Update function called every frame
function update()
  if isEnabled then
    local currentTime = getMillis()
    local timeDelta = currentTime - lastTime
    lastTime = currentTime

    if isTriggered and currentEnvelopeValue < 1 then
      local attackSpeed = timeDelta / attackTimeMs
      currentEnvelopeValue = math.min(1, currentEnvelopeValue + attackSpeed)
    elseif not isTriggered and currentEnvelopeValue > 0 then
      local releaseSpeed = timeDelta / releaseTimeMs
      currentEnvelopeValue = math.max(0, currentEnvelopeValue - releaseSpeed)
    elseif not isTriggered and currentEnvelopeValue == 0 then
      returnToBaseValues()
    end

    updateParameters()
  end
end

function init()
  print('Initializing compressor sidechain for bus:', busNum)
  isTriggered = false
  isEnabled = false
  usePerformModeControls()
  toggleSidechain(false, false)
  lastTime = getMillis()

  if self.tag == '' then
    local initialData = createSidechainStorage()
    saveSidechainData(initialData)
  end
end
]]

function init()
  local debugMode = root:findByName('debug_mode').values.x
  if debugMode == 1 then
    print('Debug mode enabled - Loading sidechain scripts')
    local sidechains = root:findAllByName('compressor_sidechain', true)
    for _, sidechain in ipairs(sidechains) do
      print('Loading sidechain:', sidechain.name)
      sidechain.script = sidechainScript
    end
  end
end
