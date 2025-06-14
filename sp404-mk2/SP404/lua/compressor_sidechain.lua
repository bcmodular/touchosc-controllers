local sidechainScript = [[
local busNum = tonumber(self.parent.parent.tag) + 1

--print('Initializing compressor sidechain for bus:', busNum)

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

--print('Initial state - Envelope:', currentEnvelopeValue, 'Triggered:', isTriggered, 'Enabled:', isEnabled)

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

-- Queue for pending parameter changes
local pendingChanges = {
  ratio = nil,
  level = nil,
  sustain = nil,
  attack = nil,
  release = nil,
  curve = nil
}

-- Control references
local settingsControls = nil
local ratioFader = nil
local levelFader = nil
local sustainFader = nil
local toggleSidechainButton = nil

-- Utility functions for value conversions
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

local function getSettingsControls()
  if not settingsControls then
    settingsControls = self:findByName('compressor_sidechain_settings', true)
  end
  return settingsControls
end

local function getControlValue(controlName)
  local controls = getSettingsControls()
  if not controls then return nil end

  local control = nil
  if controlName:find('_fader$') then
    -- For faders, we need to get the control_fader from within the group
    local group = controls:findByName(controlName .. '_group', true)
    if group then
      control = group:findByName('control_fader', true)
    end
  elseif controlName == 'trigger_note' then
    -- For note, we need to get the text from the label
    control = controls:findByName('note_label', true)
    if control then
      return tonumber(control.values.text) or 1
    end
  elseif controlName == 'midi_channel' then
    -- For bank select, we get the MIDI channel directly from the tag
    control = controls:findByName('bank_label', true)
    if control then
      return tonumber(control.tag) or 0
    end
  end

  if not control then return nil end
  return control.values.x
end

local function setControlValue(controlName, value)
  local controls = getSettingsControls()
  if not controls then return end

  local control = nil
  if controlName:find('_fader$') then
    -- For faders, we need to set the control_fader within the group
    local group = controls:findByName(controlName .. '_group', true)
    if group then
      control = group:findByName('control_fader', true)
    end
  elseif controlName == 'trigger_note' then
    -- For note, we need to set the text in the label
    control = controls:findByName('note_label', true)
    if control then
      control.values.text = tostring(value)
      return
    end
  elseif controlName == 'midi_channel' then
    -- For bank select, we set the MIDI channel directly in the tag
    control = controls:findByName('bank_label', true)
    if control then
      control:notify('update_midi_channel', value)
      return
    end
  end

  if not control then return end
  control.values.x = value
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
  -- Apply any pending changes if we're at the start of a new cycle
  if isTriggered and currentEnvelopeValue == 0 then
    if pendingChanges.ratio ~= nil then
      ratioMod = pendingChanges.ratio
      pendingChanges.ratio = nil
    end
    if pendingChanges.level ~= nil then
      levelMod = pendingChanges.level
      pendingChanges.level = nil
    end
    if pendingChanges.sustain ~= nil then
      sustainMod = pendingChanges.sustain
      pendingChanges.sustain = nil
    end
    if pendingChanges.attack ~= nil then
      attackTimeMs = pendingChanges.attack
      pendingChanges.attack = nil
    end
    if pendingChanges.release ~= nil then
      releaseTimeMs = pendingChanges.release
      pendingChanges.release = nil
    end
    if pendingChanges.curve ~= nil then
      curveType = pendingChanges.curve
      pendingChanges.curve = nil
    end
  end

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

-- Handle parameter updates from controls
local function handleParameterUpdates(controls)
  if not controls then return end

  -- Only update trigger-related parameters immediately
  triggerNote = padNumberToMidiNote(getControlValue('trigger_note') or 1)
  triggerMidiChannel = getControlValue('midi_channel') or 0

  -- Queue or apply other parameters based on sidechain state
  if isEnabled then
    -- If sidechain is on, apply changes immediately
    attackTimeMs = attackFaderToRange(getControlValue('attack_fader') or 0)
    releaseTimeMs = releaseFaderToRange(getControlValue('release_fader') or 0)
    curveType = curveFaderToType(getControlValue('curve_fader') or 0)
    ratioMod = getControlValue('ratio_fader') or 0
    levelMod = getControlValue('level_fader') or 0
    sustainMod = getControlValue('sustain_fader') or 0
  else
    -- If sidechain is off, queue the changes
    pendingChanges.attack = attackFaderToRange(getControlValue('attack_fader') or 0)
    pendingChanges.release = releaseFaderToRange(getControlValue('release_fader') or 0)
    pendingChanges.curve = curveFaderToType(getControlValue('curve_fader') or 0)
    pendingChanges.ratio = getControlValue('ratio_fader') or 0
    pendingChanges.level = getControlValue('level_fader') or 0
    pendingChanges.sustain = getControlValue('sustain_fader') or 0
  end

  --print('Attack time:', attackTimeMs, 'Release time:', releaseTimeMs, 'Curve type:', curveType, 'Ratio mod:', ratioMod, 'Level mod:', levelMod, 'Sustain mod:', sustainMod, 'Trigger note:', triggerNote, 'Trigger MIDI channel:', triggerMidiChannel)
end

local function usePerformModeControls()
  --print('Using perform mode controls')
  -- In perform mode, we'll use the settings component as source of truth
  handleParameterUpdates(getSettingsControls())
end

-- Update the base values for the sidechain
-- This should happen when the sidechain is enabled,
-- so we know what to return to when the sidechain is disabled
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

  if sideChainOn then
    --print('Sidechain is on')
    sustainFader.color = Color.fromHexString("2486FFFF")
    ratioFader.color = Color.fromHexString("2486FFFF")
    levelFader.color = Color.fromHexString("2486FFFF")
  else
    --print('Sidechain is off')
    sustainFader.color = Color.fromHexString("FFA61AFF")
    ratioFader.color = Color.fromHexString("FFA61AFF")
    levelFader.color = Color.fromHexString("FFA61AFF")
  end
end

local function toggleFaderInteractivity(sideChainOn)
  local faders = self.parent:findByName('faders', true)
  ratioFader = faders:findByName('3'):findByName('control_fader')
  levelFader = faders:findByName('4'):findByName('control_fader')
  sustainFader = faders:findByName('1'):findByName('control_fader')

  if sideChainOn then
    --print('Sidechain is on')
    sustainFader.interactive = false
    ratioFader.interactive = false
    levelFader.interactive = false
  else
    --print('Sidechain is off')
    sustainFader.interactive = true
    ratioFader.interactive = true
    levelFader.interactive = true
  end
end

local function toggleSidechain(newEnabledState)
  --print('ToggleSidechain - Bus:', busNum, 'New state:', newEnabledState)
  if toggleSidechainButton then
    toggleSidechainButton.values.x = newEnabledState and 1 or 0
  end
  toggleFaderColours(newEnabledState)
  toggleFaderInteractivity(newEnabledState)

  if newEnabledState then
    -- We're enabling the sidechain, so we need to update the base values
    updateBaseValues()
  else
    -- We're disabling the sidechain, so we need to return to the base values
    returnToBaseValues()
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

local function getCurrentConfig()
  return createSidechainConfig(
    padNumberToMidiNote(getControlValue('trigger_note') or 1),
    getControlValue('midi_channel') or 0,
    getControlValue('sustain_mod_fader') or 0,
    getControlValue('ratio_mod_fader') or 0,
    getControlValue('level_mod_fader') or 0,
    attackFaderToRange(getControlValue('attack_fader') or 0),
    releaseFaderToRange(getControlValue('release_fader') or 0),
    curveFaderToType(getControlValue('curve_fader') or 0),
    isEnabled
  )
end

local function storeRecentValues()
  local data = loadSidechainData()
  data.recent[tostring(busNum)] = getCurrentConfig()
  saveSidechainData(data)
end

local function storeDefaults()
  local data = loadSidechainData()
  data.defaults = getCurrentConfig()
  saveSidechainData(data)
end

local function storePreset(presetNumber)
  --print('Storing preset:', presetNumber)
  local data = loadSidechainData()
  data.presets[tostring(presetNumber)] = getCurrentConfig()
  saveSidechainData(data)
end

local function applyConfig(config)
  -- Update controls with config values
  setControlValue('trigger_note', midiNoteToPadNumber(config[1]))
  setControlValue('midi_channel', config[2] + 1)
  setControlValue('sustain_mod_fader', config[3])
  setControlValue('ratio_mod_fader', config[4])
  setControlValue('level_mod_fader', config[5])
  setControlValue('attack_fader', attackRangeToFader(config[6]))
  setControlValue('release_fader', releaseRangeToFader(config[7]))
  setControlValue('curve_fader', curveTypeToFader(config[8]))

  -- Update internal variables from controls
  handleParameterUpdates(getSettingsControls())

  -- Then switch on the sidechain if that's the setting of the config
  toggleSidechain(config[9])
end

local function recallPreset(presetNumber)
  --print('Recalling preset:', presetNumber, 'Bus:', busNum)
  -- First disable the sidechain
  toggleSidechain(false)

  local data = loadSidechainData()
  local preset = data.presets[tostring(presetNumber)]
  if not preset then
    return
  end

  applyConfig(preset)
end

local function recallRecentValues()
  -- First disable the sidechain
  toggleSidechain(false)

  local data = loadSidechainData()
  local recent = data.recent[tostring(busNum)]
  if not recent then
    return
  end

  applyConfig(recent)
end

local function recallDefaults()
  -- First disable the sidechain
  toggleSidechain(false)

  local data = loadSidechainData()
  local defaults = data.defaults
  if not defaults then
    return
  end

  applyConfig(defaults)
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
    --deletePreset(presetNumber)
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
      toggleSidechain(false)
    end
    self.visible = compressorSelected
  elseif key == 'toggle_sidechain' then
    toggleSidechain(value > 0)
  elseif key == 'trigger_sidechain' then
    isTriggered = value > 0
  elseif key == 'midi_message' then
    handleMidiMessage(value)
  elseif key == 'control_changed' then
    -- Handle control changes from the settings component
    handleParameterUpdates(getSettingsControls())
  end
end

local lastUpdateTime = 0
local updateInterval = 1 -- 1ms between updates (approximately 1kHz)
local lastEnvelopeValue = 0  -- Track last envelope value for change detection

function update()
  if isEnabled then
    local currentTime = getMillis()
    local timeDelta = currentTime - lastTime
    lastTime = currentTime

    -- Only process envelope changes every updateInterval milliseconds
    -- or if the envelope value has changed significantly
    if currentTime - lastUpdateTime >= updateInterval or
       math.abs(currentEnvelopeValue - lastEnvelopeValue) > 0.1 then
      lastUpdateTime = currentTime
      lastEnvelopeValue = currentEnvelopeValue

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
end

local function initializeFaderReferences()
  local faders = self.parent:findByName('faders', true)
  ratioFader = faders:findByName('3'):findByName('control_fader')
  levelFader = faders:findByName('4'):findByName('control_fader')
  sustainFader = faders:findByName('1'):findByName('control_fader')

  toggleSidechainButton = self.children.toggle_sidechain_button
end

function init()
  --print('Initializing compressor sidechain for bus:', busNum)
  isTriggered = false
  isEnabled = false
  initializeFaderReferences()
  usePerformModeControls()  -- Start in perform mode
  toggleSidechain(false)
  lastTime = getMillis()

  if self.tag == '' then
    local initialData = createSidechainStorage()
    saveSidechainData(initialData)
  end

  -- Initial update from controls
  handleParameterUpdates(getSettingsControls())
end
]]

function init()
  local debugMode = root:findByName('debug_mode').values.x
  if debugMode == 1 then
    --print('Debug mode enabled - Loading sidechain scripts')
    local sidechains = root:findAllByName('compressor_sidechain', true)
    for _, sidechain in ipairs(sidechains) do
      --print('Loading sidechain:', sidechain.name)
      sidechain.script = sidechainScript
    end
  end
end
