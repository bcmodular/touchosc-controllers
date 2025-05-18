local compressorSidechains = root:findAllByName('compressor_sidechain', true)
local function initialiseFaders(parentControl, channel)
  local faders = parentControl:findAllByType(ControlType.FADER, true)

  for _, fader in pairs(faders) do
    fader:notify('initialise', channel)
  end
end

local function goToEditPage(fxNum, midiChannel, currentValues)
  local controlPager = root.children.control_pager
  local fxPage = controlPager.children[fxNum]
  local controlGroup = fxPage:findByName('control_group')

  if controlGroup then
    print('Initialising faders for:', fxPage.name, controlGroup.name, 'fxNum:', fxNum)
    initialiseFaders(controlGroup, midiChannel)
    controlPager.values.page = tonumber(fxNum) - 1
  end

  local onOffButtonGroup = root:findByName('on_off_button_group', true)
  onOffButtonGroup:notify('set_settings', {fxNum, midiChannel})

  local recallProxy = root:findByName('recall_proxy', true)
  recallProxy:notify('set_current_values', {fxNum, midiChannel, currentValues})

  local fxPresetHandler = root:findByName('fx_preset_handler', true)
  fxPresetHandler:notify('set_settings', {fxNum, midiChannel})
end

function onReceiveMIDI(message)
  for i = 1, #compressorSidechains do
    compressorSidechains[i]:notify('midi_message', message)
  end
end

function onReceiveNotify(key, value)
  if key == 'edit_page' then
    --print('Setting channel to:', value)
    local fxNum = value[1]
    local channel = value[2]
    local currentValues = value[3]
    local fxName = value[4]
    local busNum = tostring(tonumber(channel + 1))

    local fxPageLabelText = 'Bus '..busNum..' - '..fxName
    print('Setting fx page label to:', fxPageLabelText)
    local fxPageLabel = root:findByName('fx_page_label')
    fxPageLabel.values.text = fxPageLabelText

    goToEditPage(fxNum, channel, currentValues)
  end
end