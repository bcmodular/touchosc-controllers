local offButtonScript = [[
local conn = { true, false, false } -- only send to connection 1

local function sendOffMIDI()
  local midiChannel = self.tag
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, 0 }, conn)
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

local conn = { true, false, false } -- only send to connection 1

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

  sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, ccValue }, conn)
end

function turnEffectOff()
  local settings = json.toTable(self.tag)
  local midiChannel = tonumber(settings["midiChannel"])
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, 0 }, conn)
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
local conn = { true, false, false } -- only send to connection 1

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
      sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, ccValue }, conn)
    else
        sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, 0 }, conn)
    end
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
      local defaultsButton = onOffButtonGroup:findByName('defaults_button')

      onButton.script = onButtonScript
      offButton.script = offButtonScript
      grabButton.script = grabButtonScript

      if defaultsButton then
        defaultsButton.script = defaultsButtonScript
      end
    end
  end
end
