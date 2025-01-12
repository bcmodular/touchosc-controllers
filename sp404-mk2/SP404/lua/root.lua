local fxPages = {}

-- This array indicates which buses are valid for each effect
-- e.g. 1234 means it's available for all but 5
local fxBusAvailability = {
  "1234", "1234", "1234", "1234", "1234", "1234", "12345", "1234", "1234", "1234",
  "1234", "1234", "12", "1234", "12345", "1234", "12345", "12345", "12345", "12345",
  "12345", "12345", "12345", "12345", "1234", "1234", "1234", "1234", "1234", "12345",
  "1234", "1234", "1234", "1234", "1234", "12345", "12345", "1234", "1234", "1234",
  "12", "1234", "5", "5", "5", "5"
}

local onButtonMidiValues = {
  "1, 10, 0", "2, 17, 0", "3, 23, 0", "4, 8, 0", "5, 35, 0",
  "6, 36, 0", "7, 5, 10", "8, 21, 0", "9, 25, 0", "10, 22, 0",
  "11, 34, 0", "12, 16, 0", "13, 0, 0", "14, 26, 0", "15, 24, 8",
  "16, 9, 0", "17, 11, 11", "18, 1, 12", "19, 2, 13", "20, 3, 14",
  "21, 4, 15", "22, 20, 7", "23, 27, 5", "24, 28, 6", "25, 29, 0",
  "26, 30, 0", "27, 31, 0", "28, 32, 0", "29, 33, 0", "30, 19, 9",
  "31, 18, 0", "32, 15, 0", "33, 14, 0", "34, 12, 0", "35, 13, 0",
  "36, 7, 16", "37, 6, 17", "38, 37, 0", "39, 38, 0", "40, 39, 0",
  "41, 0, 0", "42, 40, 0", "0, 0, 1", "0, 0, 2", "0, 0, 3", "0, 0, 4"
}

local onButtonScript = [[
local midiValues = {%s}
local fxNum = %s

function onValueChanged(key, value)
  if key == 'x' and value == 0 then
    local channel = tonumber(self.tag)
    local ccValue = midiValues[1]
    
    if channel <= 1 then
      ccValue = midiValues[1]
    elseif channel <= 3 then
      ccValue = midiValues[2]
    else
      ccValue = midiValues[3]
    end
    
    -- Update the bus FX label to indicate which bus the effect is on
    local busFXLabelGrid = root:findByName('bus_fx_label_grid', true)
    local busFXLabel = busFXLabelGrid.children[channel + 1]
    local fxName = string.upper(string.gsub(self.parent.parent.parent.name, "_", " "))
    busFXLabel.values.text = fxName

    -- Change the bus FX button to enable on/off for this effect
    local busFXGrid = root:findByName('bus_fx_grid', true)
    print('Changing bus FX button state to:', ccValue, 'for busNum:', tostring(channel + 1))
    busFXGrid:notify('new_fx', {channel + 1, 'ON', ccValue})

    -- Change the name of the relevant bus_grid button to fxNum
    -- This is used to jump to the relevant fx editor when we
    -- change buses to one that has an effect assigned
    local busGrid = root:findByName('bus_grid', true)
    print('Setting bus grid button name to:', fxNum, 'for busNum:', tostring(channel + 1))
    busGrid:notify('change_name', {channel + 1, fxNum})

    sendMIDI({ MIDIMessageType.CONTROLCHANGE + self.tag, 83, ccValue })
  end
end
]]

local offButtonScript = [[
local midiValues = {%s}
local fxNum = %s

function onValueChanged(key, value)
  if key == 'x' and value == 0 then
    local channel = tonumber(self.tag)
    local ccValue = midiValues[1]
    
    if channel <= 1 then
      ccValue = midiValues[1]
    elseif channel <= 3 then
      ccValue = midiValues[2]
    else
      ccValue = midiValues[3]
    end
    
    -- Update the bus FX label to indicate which bus the effect is on
    local busFXLabelGrid = root:findByName('bus_fx_label_grid', true)
    local busFXLabel = busFXLabelGrid.children[channel + 1]
    local fxName = string.upper(string.gsub(self.parent.parent.parent.name, "_", " "))
    busFXLabel.values.text = fxName

    -- Change the bus FX button to enable on/off for this effect
    local busFXGrid = root:findByName('bus_fx_grid', true)
    print('Changing bus FX button state to:', ccValue, 'for busNum:', channel + 1)
    busFXGrid:notify('new_fx', {channel + 1, 'OFF', ccValue})
    
    -- Change the name of the relevant bus_grid button to fxNum
    -- This is used to jump to the relevant fx editor when we
    -- change buses to one that has an effect assigned
    local busGrid = root:findByName('bus_grid', true)
    print('Setting bus grid button name to:', fxNum, 'for busNum:', tostring(channel + 1))
    busGrid:notify('change_name', {channel + 1, fxNum})

    sendMIDI({ MIDIMessageType.CONTROLCHANGE + self.tag, 83, 0 })
  end
end
]]

function setFXBusAvailability(fxPage, index, channel)
  local busAvailability = fxBusAvailability[index]
  print('Bus availability for:', fxPage.name, busAvailability, index, channel)

  if busAvailability == "1234" then
    local bus5Hidden = fxPage:findByName('bus_5_hidden')
    
    if channel == 4 then
      bus5Hidden.visible = true
      bus5Hidden.interactive = true
    else
      bus5Hidden.visible = false
      bus5Hidden.interactive = false
    end
  end
end

function setChannelTagsForChildren(parentControl, channel)
  local buttons = parentControl:findAllByType(ControlType.BUTTON, true)
  local faders = parentControl:findAllByType(ControlType.FADER, true)
  local radios = parentControl:findAllByType(ControlType.RADIO, true)

  for name, button in pairs(buttons) do
    button.tag = channel
  end
  
  for name, fader in pairs(faders) do
    fader.tag = channel
  end
  
  for name, radio in pairs(radios) do
    radio.tag = channel
  end
end

function setUpChannel(channel)
  
  local i = 1

  for name, fxPage in pairs(fxPages) do
    
    local controlGroup = fxPage.children.control_group
    
    if controlGroup then
      print('Setting channel tag for:', fxPage.name, controlGroup.name)
      setChannelTagsForChildren(controlGroup, channel)
      setFXBusAvailability(fxPage, i, channel)
    else
      break
    end
    
    i = i + 1

  end

  local fxSelector = root:findByName('fx_selector_label', true)
  fxSelector:notify('channel', channel)

  local midiHandler = root.children.midi_handler
  midiHandler:notify('channel', channel)

end

function onReceiveNotify(key, value)

  if key == 'channel' then
    print('Setting channel to:', value)
    local channel = value
    
    setUpChannel(channel)
  
  end
  
end

function init()
  
  local control_pager = root.children.control_pager

  for i = 1, 46 do
    local fxPage = control_pager.children[i]

    -- if fxPage has a child called fx_page_label then set its name to the fxPage name
    local fxPageLabel = fxPage:findByName('fx_page_label')
    
    if fxPageLabel then
      print('Setting fx page label:', fxPage.name)
      fxPageLabel.values.text = string.upper(string.gsub(fxPage.name, "_", " "))

      local onButton = fxPage:findByName('fx_on_button', true)
      print('Assigning onButtonScript to:', fxPage.name, onButton.name)
      
      local onButtonScript = string.format(onButtonScript, onButtonMidiValues[i], i)
      onButton.script = onButtonScript

      local offButton = fxPage:findByName('fx_off_button', true)
      print('Assigning offButtonScript to:', fxPage.name, offButton.name)

      local offButtonScript = string.format(offButtonScript, onButtonMidiValues[i], i)
      offButton.script = offButtonScript

    else
      break
    end

    print('Adding fx page:', fxPage.name, 'index:', i)
    table.insert(fxPages, fxPage)
  end

  setUpChannel(0)

end