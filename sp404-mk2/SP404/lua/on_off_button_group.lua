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

function onValueChanged(key, value)
  local settings = json.toTable(self.tag)
  local fxNum = tonumber(settings["fxNum"])
  local midiChannel = tonumber(settings["midiChannel"])
  local midiValues = onButtonMidiValues[fxNum]

  if key == 'x' and self.values.x == 0 then
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
end

function onReceiveNotify(key, value)
  if key == 'set_settings' then
    print(key, unpack(value))
    setSettings(value[1], value[2])
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
  print('collectCurrentValues', unpack(values))
  return values
end

local function goToEditPage(value)
  local settings = json.toTable(self.tag)
  local fxNum = tonumber(settings["fxNum"])
  local fxName = settings["fxName"]
  local midiChannel = tonumber(settings["midiChannel"])
  performGroupToReturnTo = value

  local performGroup = root:findByName('perform_group', true)
  performGroup:notify('hide')

  local currentValues = collectCurrentValues()
  local performRecallProxy = self.parent.parent:findByName('perform_recall_proxy', true)
  root:notify('edit_page', {fxNum, midiChannel, currentValues, performRecallProxy, fxName})
end

function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    goToEditPage(value)
  end
end

function onReceiveNotify(key, value)
  if key == 'set_settings' then
    print(key, unpack(value))
    local fxNum = value[1]
    local midiChannel = value[2]
    local fxName = value[3]
    setSettings(fxNum, midiChannel, fxName)
  end
end
]]

local performButtonScript = [[

local performGroupToReturnTo = nil

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

    root:findByName('recall_proxy', true):notify('return_values_to_perform', fxNum)
    root:findByName('perform_group', true):notify('show')
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
        print('Setting button tag:', onOffButton.tag, onOffButton.name)
        onOffButton:notify('set_settings', {fxNum, midiChannel, fxName})
      end
    end
  end
end
]]

function init()

  local onOffButtonGroups = root:findAllByName('on_off_button_group', true)

  for _, onOffButtonGroup in ipairs(onOffButtonGroups) do
    onOffButtonGroup.script = onOffButtonGroupScript

    local onButton = onOffButtonGroup:findByName('on_button')
    local offButton = onOffButtonGroup:findByName('off_button')
    local grabButton = onOffButtonGroup:findByName('grab_button')
    local editButton = onOffButtonGroup:findByName('edit_button')
    local performButton = onOffButtonGroup:findByName('perform_button')
    onButton.script = onButtonScript
    offButton.script = offButtonScript
    grabButton.script = grabButtonScript

    if editButton then
      editButton.script = editButtonScript
    end

    if performButton then
      performButton.script = performButtonScript
    end
  end
end