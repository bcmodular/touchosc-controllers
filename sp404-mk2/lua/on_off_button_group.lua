local ON_OFF_DEBUG = false

-- Port 1 = SP-404MKII, port 2 = BCR2000, port 3 = Launchpad Pro
local SP404_MIDI_OUT = { true, false, false }
local BCR_MIDI_OUT = { false, true, false }

local BCR_TOGGLE_CC = 65
local BCR_SYNC_CC = 66
local BCR_GRAB_CC = 73
local BCR_MORPH_CC = 74
local BCR_MORPH_AMOUNT_CC = 1

local function sendBcrCc(cc, value)
  local ch = tonumber(self.tag)
  if ch then
    sendMIDI({ MIDIMessageType.CONTROLCHANGE + ch, cc, value }, BCR_MIDI_OUT)
  end
end

-- BCR2000 buttons: 127 = on, 0 = off.
local function bcrButtonOn(value)
  return value > 63
end

local function debugOnOff(msg)
  if ON_OFF_DEBUG then
    print('[on_off]', msg)
  end
end

local function getToggleButton()
  return self:findByName('toggle_button', true)
end

local function getGrabButton()
  return self:findByName('grab_button', true)
end

local function getSyncButton()
  return self:findByName('sync_button', true)
end

local function setMomentaryButtonHighlight(button, midiValue)
  if button then
    button.values.x = bcrButtonOn(midiValue) and 1 or 0
  end
end

local busFxNum = 0
local busFxName = nil

-- on_off_button_group lives under control_group, not busN_group (see layout tree).
local function getBusGroup()
  local node = self.parent
  while node do
    if node.name and node.name:match("^bus(%d+)_group$") then
      return node
    end
    node = node.parent
  end
  local bcrTag = tonumber(self.tag)
  if bcrTag and bcrTag >= 5 and bcrTag <= 9 then
    return root:findByName("bus" .. tostring(bcrTag - 4) .. "_group", true)
  end
  return nil
end

local function getBusNum()
  local busGroup = getBusGroup()
  if busGroup and busGroup.name then
    local n = tonumber(busGroup.name:match("bus(%d+)_group"))
    if n then
      return n
    end
  end

  if busGroup then
    local busSettings = json.toTable(busGroup.tag) or {}
    local n = tonumber(busSettings.busNum)
    if n then
      return n
    end
  end

  local bcrTag = tonumber(self.tag)
  if bcrTag and bcrTag >= 5 and bcrTag <= 9 then
    return bcrTag - 4
  end

  return 1
end

local function getMorphChooseButton()
  return self:findByName('morph_button', true)
end

local function getPresetGrid()
  local busGroup = getBusGroup()
  return busGroup and busGroup:findByName('preset_grid', true)
end

local function setMorphEnabledState(enabled, skipBcr)
  local grid = getPresetGrid()
  if grid then
    grid:notify('set_morph_enabled', { getBusNum(), enabled })
  end
  local morphBtn = getMorphChooseButton()
  if morphBtn then
    morphBtn.values.x = enabled and 1 or 0
  end
  if not skipBcr then
    sendBcrCc(BCR_MORPH_CC, enabled and 127 or 0)
  end
end

local function getBcrPerformChannel()
  local busGroup = getBusGroup()
  local faders = busGroup and busGroup:findByName('faders', true)
  return faders and tonumber(faders.tag)
end

local function sendBcrPerformCc(cc, value)
  local ch = getBcrPerformChannel()
  if ch then
    sendMIDI({ MIDIMessageType.CONTROLCHANGE + ch, cc, value }, BCR_MIDI_OUT)
  end
end

local function notifyLaunchpadBusLedRefresh()
  root:notify('launchpad_bus_led_refresh', getBusNum())
end

local function getBusFxSettings()
  local busGroup = getBusGroup()
  local settings = busGroup and json.toTable(busGroup.tag) or {}
  if resolveBusFxNum(settings) ~= 0 then
    return settings
  end
  if busFxNum ~= 0 then
    return { fxNum = busFxNum, fxName = busFxName, busNum = getBusNum() }
  end
  if busGroup then
    local effectChooser = busGroup:findByName("effect_chooser", true)
    local label = effectChooser and effectChooser.children.label
    local name = label and label.values.text
    if name and name ~= "Choose FX..." then
      return { fxName = name, busNum = getBusNum() }
    end
  end
  return settings
end

local function getMidiChannel()
  return getBusNum() - 1
end

local function getBusOnMidiValue()
  local busGroup = getBusGroup()
  if not busGroup then
    debugOnOff('getBusOnMidiValue: no busGroup parent')
    return 0
  end
  local settings = getBusFxSettings()
  local busNum = getBusNum()
  local fxNum = resolveBusFxNum(settings)
  local val = getEffectOnMidiValue(fxNum, busNum)
  debugOnOff(string.format(
    'getBusOnMidiValue bus=%d fxNum=%d fxName=%s busTag=%s -> val=%d',
    busNum, fxNum, tostring(settings.fxName), tostring(busGroup.tag), val))
  return val
end

local function sendMIDIOn()
  local ch = getMidiChannel()
  local val = getBusOnMidiValue()
  debugOnOff(string.format('SP404 ON  bus=%d ch=%d cc=83 val=%d', getBusNum(), ch, val))
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + ch, 83, val }, SP404_MIDI_OUT)
end

local function sendMIDIOff()
  local ch = getMidiChannel()
  debugOnOff(string.format('SP404 OFF bus=%d ch=%d cc=83 val=0', getBusNum(), ch))
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + ch, 83, 0 }, SP404_MIDI_OUT)
end

local function sendEffectState(state, skipBcr)
  local fxNum = resolveBusFxNum(getBusFxSettings())
  debugOnOff(string.format(
    'sendEffectState bus=%d fx=%d state=%s skipBcr=%s',
    getBusNum(), fxNum, tostring(state), tostring(skipBcr)))

  if state and fxNum == 0 then
    debugOnOff('warn: toggle ON but no effect selected (fxNum=0) — load an FX first')
  end

  if state then
    sendMIDIOn()
  else
    sendMIDIOff()
  end
  if not skipBcr then
    sendBcrCc(BCR_TOGGLE_CC, state and 127 or 0)
  end
  notifyLaunchpadBusLedRefresh()
end

local function switchToEffect(keepOn)
  sendMIDIOn()
  if not keepOn then
    sendMIDIOff()
  end
end

local function syncCurrentBusToDevice(skipBcr)
  local toggle = getToggleButton()
  sendEffectState(toggle and toggle.values.x == 1, skipBcr)
  if not skipBcr then
    sendBcrCc(BCR_SYNC_CC, 127)
  end

  local busGroup = getBusGroup()
  local faders = busGroup:findByName('faders', true)
  local bcrCh = faders and tonumber(faders.tag)
  local controlMapper = root:findByName('control_mapper', true)

  if resolveBusFxNum(getBusFxSettings()) == 0 then
    if bcrCh and controlMapper then
      controlMapper:notify('bcr_zero_slots', { bcrCh, 1, 6 })
    end
    return
  end

  if faders then
    for i = 1, 6 do
      local faderGroup = faders:findByName(tostring(i))
      if faderGroup then
        local controlFader = faderGroup:findByName('control_fader')
        if controlFader then
          if faderGroup.visible then
            controlFader:notify('sync_midi')
          elseif bcrCh and controlMapper then
            controlMapper:notify('bcr_zero_slots', { bcrCh, i, i })
          end
        end
      end
    end
  end
end

-- skipBcrGrabEcho: true when grab CC originated on the BCR (do not echo grab back).
-- Toggle CC is always mirrored so the BCR FX button lights with grab.
local function setGrabState(buttonDown, skipBcrGrabEcho)
  if buttonDown then
    sendMIDIOn()
  else
    sendMIDIOff()
  end
  if not skipBcrGrabEcho then
    sendBcrCc(BCR_GRAB_CC, buttonDown and 127 or 0)
  end
  sendBcrCc(BCR_TOGGLE_CC, buttonDown and 127 or 0)
  local grab = getGrabButton()
  if grab then
    grab.values.x = buttonDown and 1 or 0
  end
  local toggle = getToggleButton()
  if toggle then
    toggle.values.x = buttonDown and 1 or 0
  end
  notifyLaunchpadBusLedRefresh()
end

local function setChooserState(isOpen)
  local fxSelector = root:findByName('fx_selector_group', true)
  if not fxSelector then
    return
  end

  local busNum = getBusNum()

  if isOpen then
    local busGroup = getBusGroup()
    local busChooseButtons = busGroup and busGroup:findAllByName('choose_button', true) or {}
    for _, btn in ipairs(busChooseButtons) do
      btn.values.x = 1
    end

    local selectorLabel = fxSelector:findByName('fx_selector_label')
    local selectorButtons = fxSelector:findByName('fx_selector_button_group')
    if not selectorLabel or not selectorButtons then
      return
    end

    selectorLabel.values.text = 'Choose FX for Bus ' .. tostring(busNum)
    selectorButtons.tag = tostring(busNum)
    selectorButtons:notify('setup_ui')
    fxSelector.visible = true
    root:notify("launchpad_fx_chooser_open", busNum)
  else
    if fxSelector.visible then
      fxSelector:notify('hide')
    else
      local busGroup = getBusGroup()
      local busChooseButtons = busGroup and busGroup:findAllByName('choose_button', true) or {}
      for _, btn in ipairs(busChooseButtons) do
        btn.values.x = 0
      end
    end
  end
end

function init()
  local busGroup = getBusGroup()
  local busNum = getBusNum()
  local busLabel = self:findByName('bus_label', true)
  if busLabel then
    busLabel.values.text = 'BUS ' .. tostring(busNum)
  end
end

function onReceiveNotify(key, value)
  if key == 'sync_current_bus' then
    syncCurrentBusToDevice(false)
  elseif key == 'set_state' then
    sendEffectState(value, false)
  elseif key == 'launchpad_toggle' then
    local on = value and true or false
    local toggle = getToggleButton()
    if toggle then
      toggle.values.x = on and 1 or 0
    end
    sendEffectState(on, false)
  elseif key == 'set_settings' then
    busFxNum = tonumber(value[1]) or 0
    busFxName = value[3]
    debugOnOff(string.format('set_settings fx=%d name=%s', busFxNum, tostring(busFxName)))
  elseif key == 'switch_to_effect' then
    switchToEffect(value == true or value == 1)
  elseif key == 'set_grab_state' then
    setGrabState(value, false)
  elseif key == 'set_chooser_state' then
    setChooserState(value)
  elseif key == 'bcr_toggle' then
    local on = bcrButtonOn(value)
    debugOnOff(string.format('bcr_toggle bus=%d on=%s val=%d', getBusNum(), tostring(on), value))
    local toggle = getToggleButton()
    if toggle then
      toggle.values.x = on and 1 or 0
    else
      debugOnOff('warn: toggle_button not found')
    end
    sendEffectState(on, true)
    notifyLaunchpadBusLedRefresh()
  elseif key == 'bcr_grab' then
    local pressed = bcrButtonOn(value)
    setMomentaryButtonHighlight(getGrabButton(), value)
    setGrabState(pressed, true)
    notifyLaunchpadBusLedRefresh()
  elseif key == 'bcr_sync' then
    setMomentaryButtonHighlight(getSyncButton(), value)
    if value == 0 then
      syncCurrentBusToDevice(true)
    end
  elseif key == 'set_morph_state' then
    if type(value) ~= 'table' then
      return
    end
    setMorphEnabledState(value[1] == true, value[2] == true)
  elseif key == 'echo_morph_bcr' then
    sendBcrCc(BCR_MORPH_CC, value and 127 or 0)
  elseif key == 'echo_morph_amount_bcr' then
    sendBcrPerformCc(BCR_MORPH_AMOUNT_CC, math.max(0, math.min(127, math.floor(value))))
  elseif key == 'bcr_morph' then
    setMorphEnabledState(bcrButtonOn(value), true)
  end
end
