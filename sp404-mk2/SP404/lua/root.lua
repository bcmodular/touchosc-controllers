local function setChannelTagsForChildren(parentControl, channel)
  local faders = parentControl:findAllByType(ControlType.FADER, true)

  for name, fader in pairs(faders) do
    fader.tag = channel
  end
end

local function goToEditPage(fxNum, midiChannel, currentValues, performRecallProxy)
  local controlPager = root.children.control_pager
  local fxPage = controlPager.children[fxNum]
  local controlGroup = fxPage:findByName('control_group')

  if controlGroup then
    print('Setting channel tag for:', fxPage.name, controlGroup.name, 'fxNum:', fxNum)
    setChannelTagsForChildren(controlGroup, midiChannel)
    controlPager.values.page = tonumber(fxNum) - 1
  end

  local onOffButtonGroup = root:findByName('on_off_button_group', true)
  onOffButtonGroup:notify('set_settings', {fxNum, midiChannel})

  local recallProxy = root:findByName('recall_proxy', true)
  recallProxy:notify('set_current_values', {fxNum, currentValues, performRecallProxy})

  local fxPresetHandler = root:findByName('fx_preset_handler', true)
  fxPresetHandler:notify('set_settings', {fxNum, midiChannel})
end

---@diagnostic disable: lowercase-global
function onReceiveNotify(key, value)
  if key == 'edit_page' then
    --print('Setting channel to:', value)
    local fxNum = value[1]
    local channel = value[2]
    local currentValues = value[3]
    local performRecallProxy = value[4]
    goToEditPage(fxNum, channel, currentValues, performRecallProxy)
  end
end