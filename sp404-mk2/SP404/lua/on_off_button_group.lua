local offButtonScript = [[
local function sendOffMIDI()
  local midiChannel = self.tag
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, 0 })
end

function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    sendOffMIDI()
  end
end

function onReceiveNotify(key, value)
  if key == 'set_settings' then
    self.tag = value[2]
  elseif key == 'fx_off' then
    sendOffMIDI()
  end
end
]]

local onButtonScript = [[
local onButtonMidiValues = {
  {1, 10, 0}, {2, 17, 0}, {3, 23, 0}, {4, 8, 0}, {5, 35, 0},
  {6, 36, 0}, {7, 5, 10}, {8, 21, 0}, {9, 25, 0}, {10, 22, 0},
  {11, 34, 0}, {12, 16, 0}, {13, 0, 0}, {14, 26, 0}, {15, 24, 8},
  {16, 9, 0}, {17, 11, 11}, {18, 1, 12}, {19, 2, 13}, {20, 3, 14},
  {21, 4, 15}, {22, 20, 7}, {23, 27, 5}, {24, 28, 6}, {25, 29, 0},
  {26, 30, 0}, {27, 31, 0}, {28, 32, 0}, {29, 33, 0}, {30, 19, 9},
  {31, 18, 0}, {32, 15, 0}, {33, 14, 0}, {34, 12, 0}, {35, 13, 0},
  {36, 7, 16}, {37, 6, 17}, {38, 37, 0}, {39, 38, 0}, {40, 39, 0},
  {41, 0, 0}, {42, 40, 0}, {0, 0, 1}, {0, 0, 2}, {0, 0, 3}, {0, 0, 4}
}

function setSettings(fxNum, midiChannel)
  local settings = json.toTable(self.tag) or {}
  settings['fxNum'] = fxNum
  settings['midiChannel'] = midiChannel
  self.tag = json.fromTable(settings)
end

function turnEffectOn()
  local settings = json.toTable(self.tag)
  local fxNum = tonumber(settings["fxNum"])
  local midiChannel = tonumber(settings["midiChannel"])
  local midiValues = onButtonMidiValues[fxNum]

  local ccValue = onButtonMidiValues[1]

  if midiChannel <= 1 then
    ccValue = midiValues[1]
  elseif midiChannel <= 3 then
    ccValue = midiValues[2]
  else
    ccValue = midiValues[3]
  end

  sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, ccValue })
end

function turnEffectOff()
  local settings = json.toTable(self.tag)
  local midiChannel = tonumber(settings["midiChannel"])
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, 0 })
end

function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    turnEffectOn()
  end
end

function onReceiveNotify(key, value)
  if key == 'set_settings' then
    setSettings(value[1], value[2])
  elseif key == 'switch_to_effect' then
    turnEffectOn()
    turnEffectOff()
  end
end
]]

local grabButtonScript = [[
local onButtonMidiValues = {
  {1, 10, 0}, {2, 17, 0}, {3, 23, 0}, {4, 8, 0}, {5, 35, 0},
  {6, 36, 0}, {7, 5, 10}, {8, 21, 0}, {9, 25, 0}, {10, 22, 0},
  {11, 34, 0}, {12, 16, 0}, {13, 0, 0}, {14, 26, 0}, {15, 24, 8},
  {16, 9, 0}, {17, 11, 11}, {18, 1, 12}, {19, 2, 13}, {20, 3, 14},
  {21, 4, 15}, {22, 20, 7}, {23, 27, 5}, {24, 28, 6}, {25, 29, 0},
  {26, 30, 0}, {27, 31, 0}, {28, 32, 0}, {29, 33, 0}, {30, 19, 9},
  {31, 18, 0}, {32, 15, 0}, {33, 14, 0}, {34, 12, 0}, {35, 13, 0},
  {36, 7, 16}, {37, 6, 17}, {38, 37, 0}, {39, 38, 0}, {40, 39, 0},
  {41, 0, 0}, {42, 40, 0}, {0, 0, 1}, {0, 0, 2}, {0, 0, 3}, {0, 0, 4}
}

function setSettings(fxNum, midiChannel)
  local settings = json.toTable(self.tag) or {}
  settings['fxNum'] = fxNum
  settings['midiChannel'] = midiChannel
  self.tag = json.fromTable(settings)
end

function onValueChanged(key, value)

  if key == 'x' then

    local buttonDown = true

    if self.values.x == 0 then
      buttonDown = false
    end

    local settings = json.toTable(self.tag)
    local fxNum = tonumber(settings["fxNum"])
    local midiChannel = tonumber(settings["midiChannel"])
    local midiValues = onButtonMidiValues[fxNum]

    if buttonDown then
      local ccValue = midiValues[1]

      if midiChannel <= 1 then
        ccValue = midiValues[1]
      elseif midiChannel <= 3 then
        ccValue = midiValues[2]
      else
        ccValue = midiValues[3]
      end
      sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, ccValue })
    else
        sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, 0 })
    end
  end
end

function onReceiveNotify(key, value)
  if key == 'set_settings' then
    setSettings(value[1], value[2])
  end
end
]]

local editButtonScript = [[

local function setSettings(fxNum, midiChannel, fxName)
  local settings = json.toTable(self.tag) or {}
  settings['fxNum'] = fxNum
  settings['midiChannel'] = midiChannel
  settings['fxName'] = fxName
  self.tag = json.fromTable(settings)
end

local function collectCurrentValues()
  local values = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0}
  local faders = self.parent.parent:findByName('faders', true)

  for i = 1, 6 do
    local faderGroup = faders.children[i]
    local fader = faderGroup:findByName('control_fader', true)
    if fader then
      values[i] = fader.values.x
    end
  end
  return values
end

local function goToEditPage()
  local settings = json.toTable(self.tag)
  local fxNum = tonumber(settings["fxNum"])
  local fxName = settings["fxName"]
  local midiChannel = tonumber(settings["midiChannel"])
  local editMode = root:findByName('edit_mode', true)
  editMode.values.x = 1
  local busGroupName = 'bus' .. tostring(midiChannel + 1) .. '_group'
  editMode.tag = busGroupName

  local performGroup = root:findByName('perform_group', true)
  performGroup:notify('hide')

  local currentValues = collectCurrentValues()
  root:notify('edit_page', {fxNum, midiChannel, currentValues, fxName})

  if fxNum == 37 then
    local compressorSidechain = self.parent.parent:findByName('compressor_sidechain', true)
    compressorSidechain:notify('switch_mode')

    local editCompressorSidechain = root:findByName('edit_compressor_sidechain', true)
    editCompressorSidechain:notify('update_bus')
  end
end

function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    goToEditPage()
  end
end

function onReceiveNotify(key, value)
  if key == 'set_settings' then
    local fxNum = value[1]
    local midiChannel = value[2]
    local fxName = value[3]
    setSettings(fxNum, midiChannel, fxName)
  end
end
]]

local performButtonScript = [[

local function setSettings(fxNum, midiChannel)
  local settings = json.toTable(self.tag) or {}
  settings['fxNum'] = fxNum
  settings['midiChannel'] = midiChannel
  self.tag = json.fromTable(settings)
end

function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    local settings = json.toTable(self.tag)
    local fxNum = tonumber(settings["fxNum"])
    local midiChannel = tonumber(settings["midiChannel"])

    root:findByName('recall_proxy', true):notify('return_values_to_perform', fxNum)

    local editMode = root:findByName('edit_mode', true)
    editMode.values.x = 0
    local busGroupName = 'bus' .. tostring(midiChannel + 1) .. '_group'
    local busGroup = root:findByName(busGroupName, true)
    local compressorSidechain = busGroup:findByName('compressor_sidechain', true)
    compressorSidechain:notify('switch_mode')
  end
end

function onReceiveNotify(key, value)
  if key == 'set_settings' then
    setSettings(value[1], value[2])
  end
end
]]

local onOffButtonGroupScript = [[
function onReceiveNotify(key, value)
  if key == 'set_settings' then
    local fxNum = value[1]
    local midiChannel = value[2]
    local fxName = value[3]

    for i = 1, #self.children do
      local onOffButton = self.children[i]
      if onOffButton.type == ControlType.BUTTON then
        onOffButton:notify('set_settings', {fxNum, midiChannel, fxName})
      end
    end
  end
end
]]

local syncButtonScript = [[
function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    local controlFaders = self.parent.parent.parent:findAllByName('control_fader', true)
    for _, controlFader in ipairs(controlFaders) do
      controlFader:notify('sync_midi')
    end
  end
end
]]

local editPageSyncButtonScript = [[
local function setFXNum(fxNum)
  local settings = json.toTable(self.tag) or {}
  settings['fxNum'] = fxNum
  self.tag = json.fromTable(settings)
end

local function getFXNum()
  local settings = json.toTable(self.tag)
  return settings["fxNum"]
end

function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    local controlPager = root:findByName('control_pager')
    local fxPage = controlPager.children[getFXNum()]
    local controlGroup = fxPage:findByName('control_group', true)
    local faders = controlGroup:findAllByType(ControlType.FADER)
    for _, fader in pairs(faders) do
      fader:notify('sync_midi')
    end
  end
end

function onReceiveNotify(key, value)
  if key == 'set_settings' then
    setFXNum(value[1])
  end
end
]]

local defaultsButtonScript = [[
function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    local performRecallProxy = self.parent.parent.parent:findByName('perform_recall_proxy', true)
    performRecallProxy:notify('recall_defaults')
  end
end
]]

function init()
  local debugMode = root:findByName('debug_mode').values.x
  if debugMode == 1 then
    local onOffButtonGroups = root:findAllByName('on_off_button_group', true)

    for _, onOffButtonGroup in ipairs(onOffButtonGroups) do
      onOffButtonGroup.script = onOffButtonGroupScript

      local onButton = onOffButtonGroup:findByName('on_button')
      local offButton = onOffButtonGroup:findByName('off_button')
      local grabButton = onOffButtonGroup:findByName('grab_button')
      local editButton = onOffButtonGroup:findByName('edit_button')
      local performButton = onOffButtonGroup:findByName('perform_button')
      local syncButton = onOffButtonGroup:findByName('sync_button')
      local editPageSyncButton = onOffButtonGroup:findByName('edit_page_sync_button')
      local defaultsButton = onOffButtonGroup:findByName('defaults_button')

      onButton.script = onButtonScript
      offButton.script = offButtonScript
      grabButton.script = grabButtonScript

      if editButton then
        editButton.script = editButtonScript
      end

      if performButton then
        performButton.script = performButtonScript
      end

      if syncButton then
        syncButton.script = syncButtonScript
      end

      if editPageSyncButton then
        editPageSyncButton.script = editPageSyncButtonScript
      end

      if defaultsButton then
        defaultsButton.script = defaultsButtonScript
      end
    end
  end
end
