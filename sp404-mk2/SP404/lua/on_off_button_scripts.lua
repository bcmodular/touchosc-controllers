local toggleButtonScript = [[
function onValueChanged(key, value)
  if key == 'x' then
    self.parent:notify('set_state', self.values.x == 1)
  end
end
]]

local grabButtonScript = [[
function onValueChanged(key, value)
  if key == 'x' then
    self.parent:notify('set_grab_state', self.values.x == 1)
  end
end
]]

local syncButtonScript = [[
function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    self.parent:notify('sync_current_bus')
  end
end
]]

local controlBusButtonScript = [[
function onValueChanged(key, value)
  if key == 'x' then
    self.parent:notify('control_bus', self.values.x == 1)
  end
end
]]

local onOffButtonGroupScript = [[
local busGroup = self.parent.parent
local toggleButton = self:findByName('toggle_button')
local controlBusButton = self:findByName('control_bus_button')
local abletonPushHandler = root:findByName('ableton_push_handler', true)
local busSettings = json.toTable(busGroup.tag) or {}
local busNum = tonumber(busSettings['busNum']) or 1
local midiChannel = busNum - 1
local conn = { true, false, false } -- only send to connection 1

local function getBusOnMidiValue()
  print('getBusOnMidiValue', busGroup.tag)
  local latestBusSettings = json.toTable(busGroup.tag) or {}
  local fxNum = tonumber(latestBusSettings['fxNum']) or 0

  if fxNum == 0 then
    return 0
  end

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

  print('getBusOnMidiValue', fxNum, midiChannel)

  local midiValues = onButtonMidiValues[fxNum]
  if midiChannel <= 1 then
    return midiValues[1]
  elseif midiChannel <= 3 then
    return midiValues[2]
  else
    return midiValues[3]
  end
end

local function sendMIDIOn()
  print('sendMIDIOn', midiChannel, getBusOnMidiValue())
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, getBusOnMidiValue()}, conn)
end

local function sendMIDIOff()
  print('sendMIDIOff', midiChannel, 0)
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, 0 }, conn)
end

local function sendEffectState(state)
  if state then
    sendMIDIOn()
  else
    sendMIDIOff()
  end

  abletonPushHandler:notify('sync_push_lighting', busNum)
end

local function switchToEffect()
  sendMIDIOn()
  sendMIDIOff()
end

local function syncCurrentBusToDevice()
  sendEffectState(toggleButton.values.x == 1)

  local faders = busGroup:findByName('faders', true)
  if faders then
    for i = 1, 6 do
      local faderGroup = faders:findByName(tostring(i))
      if faderGroup then
        local controlFader = faderGroup:findByName('control_fader')
        if controlFader then
          controlFader:notify('sync_midi')
        end
      end
    end
  end
end

local function controlBus(state)
  if state then
    -- We're going to control this bus, so turn off all other control bus buttons
    for i = 1, 5 do
      if i ~= busNum then
        local busGroupName = 'bus'..tostring(i)..'_group'
        local otherBusGroup = root:findByName(busGroupName, true)
        local otherControlBusButton = otherBusGroup:findByName('control_bus_button', true)
        otherControlBusButton.values.x = 0
      end
    end
    abletonPushHandler:notify('set_controlled_bus', busNum)
  else
     -- We're trying to turn off the control bus, so check if this was the last active control bus button
    local activeCount = 0
    for i = 1, 5 do
      if i ~= busNum then
        local busGroupName = 'bus'..tostring(i)..'_group'
        local otherBusGroup = root:findByName(busGroupName, true)
        local otherControlBusButton = otherBusGroup:findByName('control_bus_button', true)
        if otherControlBusButton.values.x == 1 then
          activeCount = activeCount + 1
        end
      end
    end

    -- If this was the last active button, prevent it from being turned off
    if activeCount == 0 then
      controlBusButton.values.x = 1
    end
  end
end

local function setGrabState(buttonDown)
  abletonPushHandler:notify('sync_push_lighting', busNum)

  if buttonDown then
    sendMIDIOn()
  else
    sendMIDIOff()
  end
  toggleButton.values.x = buttonDown and 1 or 0
end

function onReceiveNotify(key, value)
  if key == 'sync_current_bus' then
    syncCurrentBusToDevice()
  elseif key == 'set_state' then
    sendEffectState(value)
  elseif key == 'switch_to_effect' then
    switchToEffect()
  elseif key == 'control_bus' then
    controlBus(value)
  elseif key == 'set_grab_state' then
    setGrabState(value)
  end
end
]]

local function initialiseControlBusButtons()
  -- Initialize radio button behavior: check current button states and ensure only one is active
  local activeBus = 0
  local activeCount = 0

  -- Check which bus is currently active
  for i = 1, 5 do
    local busGroupName = 'bus'..tostring(i)..'_group'
    local busGroup = root:findByName(busGroupName, true)
    local controlBusButton = busGroup:findByName('control_bus_button', true)
    if controlBusButton.values.x == 1 then
      activeBus = i
      activeCount = activeCount + 1
    end
  end

  -- If no bus is active or multiple buses are active, default to Bus 1
  if activeCount == 0 or activeCount > 1 then
    activeBus = 1
  end

  -- Set the correct radio button state
  for i = 1, 5 do
    local busGroupName = 'bus'..tostring(i)..'_group'
    local busGroup = root:findByName(busGroupName, true)
    local controlBusButton = busGroup:findByName('control_bus_button', true)
    controlBusButton.values.x = (i == activeBus) and 1 or 0
  end

  local abletonPushHandler = root:findByName('ableton_push_handler', true)
  abletonPushHandler:notify('set_controlled_bus', activeBus)
end

function init()
  local debugMode = root:findByName('debug_mode').values.x
  if debugMode == 1 then
    local onOffButtonGroups = root:findAllByName('on_off_button_group', true)

    for _, onOffButtonGroup in ipairs(onOffButtonGroups) do
      onOffButtonGroup.script = onOffButtonGroupScript

      local toggleButton = onOffButtonGroup:findByName('toggle_button')
      toggleButton.script = toggleButtonScript
      local grabButton = onOffButtonGroup:findByName('grab_button')
      grabButton.script = grabButtonScript
      local controlBusButton = onOffButtonGroup:findByName('control_bus_button')
      controlBusButton.script = controlBusButtonScript
      local syncButton = onOffButtonGroup:findByName('sync_button')
      syncButton.script = syncButtonScript
    end
  end

  initialiseControlBusButtons()
end
