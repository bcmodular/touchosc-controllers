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

function fxBusAvailability(fxPage, index, channel)
  local busAvailability = fxBusAvailability[index]
  
  if busAvailability == "1234" and channel == 4 then
    fxPage.children.bus_5_hidden.visible = false
    fxPage.children.bus_5_hidden.interactive = false
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

function onReceiveNotify(key, value)

  if key == 'channel' then
  
    local channel = value
    
    local i = 1

    for name, fxPage in pairs(fxPages) do
      
      -- Only implemented the first 5 pages so far
      if i == 6 then
        break
      end

      local controlGroup = fxPage.children.control_group
      
      if controlGroup then
        --print('Setting channel tag for:', controlGroup.name)
        setChannelTagsForChildren(controlGroup, channel)
        setFXAvailability(fxPage, i, channel)
      end
      
      i = i + 1
    end

    local fx_off_button = self.children.top_button_group.children.fx_off_button
    fx_off_button.tag = channel

    local fxSelector = root:findByName('fx_selector_label', true)
    fxSelector:notify('channel', channel)

    local midiHandler = root.children.midi_handler
    midiHandler:notify('channel', channel)
  
  end
  
end

function init()
  
  local control_pager = root.children.control_pager

  -- Until more are implemented
  --for i = 1, 46 do
  for i = 1, 5 do
    local fxPage = control_pager.children[i]

    -- if fxPage has a child called fx_page_label then set its name to the fxPage name
    local fxPageLabel = fxPage.children.fx_page_label
    
    if fxPageLabel then
      fxPageLabel.values.text = string.upper(string.gsub(fxPage.name, "_", " "))
    end

    print('Adding fx page:', fxPage.name)
    table.insert(fxPages, fxPage)
  end

end