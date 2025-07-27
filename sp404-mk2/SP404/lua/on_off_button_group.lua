local toggleButtonScript = [[
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
  self.tag = json.fromTable({fxNum = fxNum, midiChannel = midiChannel})
end

local conn = { true, false, false } -- only send to connection 1

function sendEffectState()
  local settings = json.toTable(self.tag)
  local fxNum = tonumber(settings.fxNum)
  local midiChannel = tonumber(settings.midiChannel)

  if self.values.x == 1 then
    -- Turn effect on
    local midiValues = onButtonMidiValues[fxNum]
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
    -- Turn effect off
    sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, 0 }, conn)
  end
end

function onValueChanged(key, value)
  if key == 'x' then
    sendEffectState()

    -- Notify Ableton Push handler of state change
    local settings = json.toTable(self.tag)
    local midiChannel = tonumber(settings.midiChannel)
    local busNum = midiChannel + 1
    local abletonPushHandler = root:findByName('ableton_push_handler', true)
    if abletonPushHandler then
      abletonPushHandler:notify('toggle_button_state_changed', {busNum, self.values.x})
    end
  end
end

function onReceiveNotify(key, value)
  if key == 'set_settings' then
    setSettings(value[1], value[2])
  elseif key == 'set_state' then
    -- Set the button state (used by Ableton Push handler)
    self.values.x = value and 1 or 0

    -- Notify Ableton Push handler of state change
    local settings = json.toTable(self.tag)
    local midiChannel = tonumber(settings.midiChannel)
    local busNum = midiChannel + 1
    local abletonPushHandler = root:findByName('ableton_push_handler', true)
    if abletonPushHandler then
      abletonPushHandler:notify('toggle_button_state_changed', {busNum, self.values.x})
    end
  elseif key == 'sync_to_device' then
    sendEffectState()
  elseif key == 'switch_to_effect' then
    -- Turn on and off quickly to switch to the effect
    local settings = json.toTable(self.tag)
    local fxNum = tonumber(settings.fxNum)
    local midiChannel = tonumber(settings.midiChannel)
    local midiValues = onButtonMidiValues[fxNum]
    local ccValue = midiValues[1]
    if midiChannel <= 1 then
      ccValue = midiValues[1]
    elseif midiChannel <= 3 then
      ccValue = midiValues[2]
    else
      ccValue = midiValues[3]
    end
    sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, ccValue }, conn)
    sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, 83, 0 }, conn)
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

    -- Notify Ableton Push handler for visual feedback
    local currentBus = tonumber(self.parent.parent.parent.tag ~= "" and self.parent.parent.parent.tag or 0) + 1
    local abletonPushHandler = root:findByName('ableton_push_handler', true)
    if abletonPushHandler then
      abletonPushHandler:notify('grab_button_state_changed', {currentBus, self.values.x})
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

    -- Also toggle the toggle button to provide visual feedback
    local toggleButton = self.parent:findByName('toggle_button')
    if toggleButton then
      toggleButton.values.x = buttonDown and 1 or 0
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
local function syncCurrentBusToDevice()
  -- Sync current bus to device
  local toggleButton = self:findByName('toggle_button')
  if toggleButton then
    toggleButton:notify('sync_to_device')
  end

  -- Also sync all control faders for this bus
  local faders = self.parent:findByName('faders', true)
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

function onReceiveNotify(key, value)
  if key == 'set_settings' then
    local fxNum = value[1]
    local midiChannel = value[2]
    local fxName = value[3]

    for i = 1, #self.children do
      local button = self.children[i]
      if button.type == ControlType.BUTTON then
        button:notify('set_settings', {fxNum, midiChannel, fxName})
      end
    end
  elseif key == 'sync_current_bus' then
    syncCurrentBusToDevice()
  elseif key == 'set_state' then
    -- Set the state of the toggle button (used by Ableton Push handler)
    local toggleButton = self:findByName('toggle_button')
    if toggleButton then
      toggleButton:notify('set_state', value)
    end
  elseif key == 'sync_button_pressed' then
    syncCurrentBusToDevice()
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

local syncButtonScript = [[
function onValueChanged(key, value)
  if key == 'x' then
    -- Get the current bus number
    local currentBus = tonumber(self.parent.parent.parent.tag ~= "" and self.parent.parent.parent.tag or 0) + 1

    -- Notify Ableton Push handler for visual feedback
    local abletonPushHandler = root:findByName('ableton_push_handler', true)
    if abletonPushHandler then
      abletonPushHandler:notify('sync_button_state_changed', {currentBus, self.values.x})
    end

    -- Trigger sync when button is released
    if self.values.x == 0 then
      local busGroupName = 'bus'..tostring(currentBus)..'_group'
      local performBusGroup = root:findByName(busGroupName, true)

      if performBusGroup then
        local onOffButtonGroup = performBusGroup:findByName('on_off_button_group', true)
        if onOffButtonGroup then
          onOffButtonGroup:notify('sync_current_bus')
        end
      end
    end
  end
end
]]

local syncAllButtonScript = [[
function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    -- Sync all control faders to device (existing pattern)
    local controlFaders = root:findAllByName('control_fader', true)
    for _, controlFader in ipairs(controlFaders) do
      controlFader:notify('sync_midi')
    end

    -- Also sync all toggle buttons to device
    local toggleButtons = root:findAllByName('toggle_button', true)
    for _, toggleButton in ipairs(toggleButtons) do
      toggleButton:notify('sync_to_device')
    end
  end
end
]]

local controlBusButtonScript = [[
function onValueChanged(key, value)
  if key == 'x' then
    -- Get the current bus number for this button
    local currentBus = tonumber(self.parent.parent.parent.tag ~= "" and self.parent.parent.parent.tag or 0) + 1

    if self.values.x == 1 then
      -- Radio button behavior: turn off all other control bus buttons
      for i = 1, 5 do
        if i ~= currentBus then
          local busGroupName = 'bus'..tostring(i)..'_group'
          local performBusGroup = root:findByName(busGroupName, true)
          if performBusGroup then
            local onOffButtonGroup = performBusGroup:findByName('on_off_button_group', true)
            if onOffButtonGroup then
              local controlBusButton = onOffButtonGroup:findByName('control_bus_button')
              if controlBusButton then
                controlBusButton.values.x = 0
              end
            end
          end
        end
      end

      -- Save the controlled bus state for persistence
      root.tag = json.fromTable({controlledBus = currentBus})

      -- Notify Ableton Push handler for visual feedback (if available)
      local abletonPushHandler = root:findByName('ableton_push_handler', true)
      if abletonPushHandler then
        abletonPushHandler:notify('control_bus_button_state_changed', {currentBus, self.values.x})
        abletonPushHandler:notify('set_controlled_bus', currentBus)
      end
    else
      -- Check if this was the last active control bus button
      local activeCount = 0
      for i = 1, 5 do
        local busGroupName = 'bus'..tostring(i)..'_group'
        local performBusGroup = root:findByName(busGroupName, true)
        if performBusGroup then
          local onOffButtonGroup = performBusGroup:findByName('on_off_button_group', true)
          if onOffButtonGroup then
            local controlBusButton = onOffButtonGroup:findByName('control_bus_button')
            if controlBusButton and controlBusButton.values.x == 1 then
              activeCount = activeCount + 1
            end
          end
        end
      end

      -- If this was the last active button, prevent it from being turned off
      if activeCount == 0 then
        self.values.x = 1
        return
      end

      -- Notify Ableton Push handler for visual feedback (if available)
      local abletonPushHandler = root:findByName('ableton_push_handler', true)
      if abletonPushHandler then
        abletonPushHandler:notify('control_bus_button_state_changed', {currentBus, self.values.x})
        abletonPushHandler:notify('set_controlled_bus', 0)
      end
    end
  end
end
]]

function init()
  local debugMode = root:findByName('debug_mode').values.x
  if debugMode == 1 then
    local onOffButtonGroups = root:findAllByName('on_off_button_group', true)

    for _, onOffButtonGroup in ipairs(onOffButtonGroups) do
      onOffButtonGroup.script = onOffButtonGroupScript

    local toggleButton = onOffButtonGroup:findByName('toggle_button')
    local grabButton = onOffButtonGroup:findByName('grab_button')
    local defaultsButton = onOffButtonGroup:findByName('defaults_button')
    local controlBusButton = onOffButtonGroup:findByName('control_bus_button')

    if toggleButton then
      toggleButton.script = toggleButtonScript
    end

    if grabButton then
      grabButton.script = grabButtonScript
    end

    if defaultsButton then
      defaultsButton.script = defaultsButtonScript
    end

    if controlBusButton then
      controlBusButton.script = controlBusButtonScript
    end
    end

    -- Initialize sync buttons
    local syncButtons = root:findAllByName('sync_button', true)
    for _, syncButton in ipairs(syncButtons) do
      syncButton.script = syncButtonScript
    end

    local syncAllButton = root:findByName('sync_all_button', true)
    if syncAllButton then
      syncAllButton.script = syncAllButtonScript
    end

    -- Initialize radio button behavior: check current button states and ensure only one is active
    local activeBus = 0
    local activeCount = 0

    -- Check which bus is currently active
    for i = 1, 5 do
      local busGroupName = 'bus'..tostring(i)..'_group'
      local performBusGroup = root:findByName(busGroupName, true)
      if performBusGroup then
        local onOffButtonGroup = performBusGroup:findByName('on_off_button_group', true)
        if onOffButtonGroup then
          local controlBusButton = onOffButtonGroup:findByName('control_bus_button')
          if controlBusButton and controlBusButton.values.x == 1 then
            activeBus = i
            activeCount = activeCount + 1
          end
        end
      end
    end

    -- If no bus is active or multiple buses are active, default to Bus 1
    if activeCount == 0 or activeCount > 1 then
      activeBus = 1
    end

    -- Set the correct radio button state
    for i = 1, 5 do
      local busGroupName = 'bus'..tostring(i)..'_group'
      local performBusGroup = root:findByName(busGroupName, true)
      if performBusGroup then
        local onOffButtonGroup = performBusGroup:findByName('on_off_button_group', true)
        if onOffButtonGroup then
          local controlBusButton = onOffButtonGroup:findByName('control_bus_button')
          if controlBusButton then
            controlBusButton.values.x = (i == activeBus) and 1 or 0
          end
        end
      end
    end

    -- Notify Ableton Push handler about the restored bus selection
    local abletonPushHandler = root:findByName('ableton_push_handler', true)
    if abletonPushHandler then
      abletonPushHandler:notify('set_controlled_bus', activeBus)
    end
  end
end
