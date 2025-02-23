local function setChannelTagsForChildren(parentControl, channel)
  local buttons = parentControl:findAllByType(ControlType.BUTTON, true)
  local faders = parentControl:findAllByType(ControlType.FADER, true)

  for name, button in pairs(buttons) do
    button.tag = channel
  end

  for name, fader in pairs(faders) do
    fader.tag = channel
  end
end

local function setUpChannel(fxNum, channel)
  local controlPager = root.children.control_pager
  local fxPage = controlPager.children[fxNum]
  local controlGroup = fxPage[fxNum]:findByName('control_group')

  if controlGroup then
    --print('Setting channel tag for:', fxPage.name, controlGroup.name, 'index:', i)
    setChannelTagsForChildren(controlGroup, channel)
  end

  local fxPresetHandler = root.children.fx_preset_handler
  fxPresetHandler:notify('channel', channel)
end

---@diagnostic disable: lowercase-global
function onReceiveNotify(key, value)
  if key == 'channel' then
    --print('Setting channel to:', value)
    local fxNum = value[1]
    local channel = value[2]
    setUpChannel(fxNum, channel)
  end
end