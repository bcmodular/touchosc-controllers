local BUTTON_STATE = {
  EMPTY = 1,
  ON = 2,
  OFF = 3
}

local BUTTON_STATE_COLORS = {
  EMPTY = "FFA61AFF",
  ON = "00FF00FF",
  OFF = "FF0000FF"
}

local ccValues = {0, 0, 0, 0, 0}

function setButtonState(child, newState)
  print('Changing state of', child.index, 'to:', newState)
  child.name = BUTTON_STATE[newState]
  child.color = BUTTON_STATE_COLORS[newState]
end

function init()
  if self.name ~= 'bus_fx_grid' then
    setButtonState(self, 'EMPTY')
    self.outline = true
    self.outlineStyle = OutlineStyle.FULL
  else
    self.outline = false
  end
end

function onValueChanged(key, value)
  if self.name ~= 'bus_fx_grid' and key == 'x' and self.values.x == 0 then
    print('onValueChanged called with key:', key, 'value:', value)
    local buttonState = tonumber(self.name)
    print('Button state:', buttonState)
    
    if buttonState == BUTTON_STATE.OFF then
      
      print('Turning FX on for channel:', tostring(self.index))
      self.parent:notify('turn_on', self.index)
    
    elseif buttonState == BUTTON_STATE.ON then

        print('Turning FX off for channel:', tostring(self.index))
        self.parent:notify('turn_off', self.index)
    
    end  
  end
end

function onReceiveNotify(key, value)
  print('onReceiveNotify called with key:', key, 'value:', value)
  
  if self.name == 'bus_fx_grid' then
  
    if key == 'new_fx' then
      print('New FX:', unpack(value))
      local busNum = value[1]
      local newState = value[2]
      local ccValue = value[3]
      print('Changing state of bus:', busNum, 'to:', newState, 'with ccValue:', ccValue)

      ccValues[busNum] = ccValue
      setButtonState(self.children[busNum], newState)

    elseif key == 'turn_off' then

      local busNum = value
      print('Turning off bus:', busNum)
      setButtonState(self.children[busNum], 'OFF')
      sendMIDI({ MIDIMessageType.CONTROLCHANGE + busNum - 1, 83, 0 })

    elseif key == 'turn_on' then

      local busNum = value
      print('Turning on bus:', busNum)
      setButtonState(self.children[busNum], 'ON')
      sendMIDI({ MIDIMessageType.CONTROLCHANGE + busNum - 1, 83, ccValues[busNum] })

    end
  end
end
