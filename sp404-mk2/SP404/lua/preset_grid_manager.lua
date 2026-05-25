local fxNums = {}
local deleteMode = false
local grabMode = false
-- busNum -> presetNum currently held in grab mode (last pressed wins per bus)
local activeGrabByBus = {}
-- busNum -> morph session (Quantise + stored preset + aftertouch)
local activeMorphByBus = {}

local PRESETS_PER_BUS = 8
local NUM_BUSES = 5

-- Keep buildPresetNoteMap in sync with root.lua (Launchpad columns 1–5, preset 1 at top).
local function buildPresetNoteMap()
  local map = {}
  for bus = 1, NUM_BUSES do
    for preset = 1, PRESETS_PER_BUS do
      map[(bus - 1) * PRESETS_PER_BUS + preset] = 81 + (bus - 1) - (preset - 1) * 10
    end
  end
  return map
end

local presetNoteMap = buildPresetNoteMap()

local PRESET_LED_EMPTY_PRESS_BRIGHTNESS = 0.35

local BUTTON_STATE_COLORS = {
  AVAILABLE = "FFFFFFFF",
  DELETE = "FF0000FF"
}

local defaultCCValues = {0, 0, 0, 0, 0, 0}

-- Launchpad port 3 — LAUNCHPAD_MIDI_CONNECTION in launchpad_led.lua (include)

-- Shared references
local presetManager = root.children.preset_manager
local defaultManager = root.children.default_manager
local controlsInfo = root.children.controls_info

local function formatPresetNum(num)
  return string.format("%02d", num)
end

-- Preset “stored” colour must match root.lua BUS_ACCENT_HEX / root.tag.busAccentHex (root owns chrome).
local FALLBACK_BUS_ACCENT_HEX = {
  [1] = "00E6FFFF",
  [2] = "FFD700FF",
  [3] = "FF69B4FF",
  [4] = "4A90E2FF",
  [5] = "32CD32FF",
}

local function getRecallButtonColor(busNum)
  local meta = json.toTable(root.tag) or {}
  local t = meta.busAccentHex
  if type(t) == "table" then
    local hex = t[tostring(busNum)] or t["5"]
    if hex and hex ~= "" then
      return hex
    end
  end
  return FALLBACK_BUS_ACCENT_HEX[busNum] or FALLBACK_BUS_ACCENT_HEX[5]
end

local function midiToFloat(midiValue)
  return midiValue / 127
end

local function floatToMIDI(floatValue)
  return math.floor(floatValue * 127 + 0.5)
end

local function sendSysexAllPadsOff(busNum)
  local ledUpdates = {}
  for i = 1, PRESETS_PER_BUS do
    local mapEntry = (busNum - 1) * PRESETS_PER_BUS + i
    local note = presetNoteMap[mapEntry]
    if note then
      table.insert(ledUpdates, note)
      table.insert(ledUpdates, 0)  -- Color 0 = off
    end
  end

  if #ledUpdates > 0 then
    local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0A }
    for _, value in ipairs(ledUpdates) do
      table.insert(sysexMessage, value)
    end
    table.insert(sysexMessage, 0xF7)
    sendMIDI(sysexMessage, LAUNCHPAD_MIDI_CONNECTION)
  end
end

local function getGrid(busNum)
  local busGroup = root:findByName('bus' .. tostring(busNum) .. '_group', true)
  if busGroup then
    return busGroup:findByName('preset_grid', true)
  end
  return nil
end

local function getGrabRestoreLabel(busNum)
  return root:findByName('grab_restore_' .. tostring(busNum), true)
end

local function loadGrabRestoreCc(busNum)
  local label = getGrabRestoreLabel(busNum)
  if not label or label.tag == '' then
    return nil
  end
  local data = json.toTable(label.tag)
  if type(data) ~= 'table' or type(data.cc) ~= 'table' then
    return nil
  end
  return data.cc
end

local function saveGrabRestoreCc(busNum, ccValues)
  local label = getGrabRestoreLabel(busNum)
  if label then
    label.tag = json.fromTable({ cc = ccValues })
  end
end

local function clearGrabRestoreCc(busNum)
  local label = getGrabRestoreLabel(busNum)
  if label then
    label.tag = ''
  end
end

local function isStoredPresetButton(busNum, presetNum)
  local grid = getGrid(busNum)
  if not grid then
    return false
  end
  local button = grid:findByName(tostring(presetNum))
  if not button then
    return false
  end
  return Color.toHexString(button.color) == getRecallButtonColor(busNum)
end

local function getBusFaderContext(busNum)
  local grid = getGrid(busNum)
  if not grid then
    return nil
  end
  local busGroup = grid.parent
  local fxNum = fxNums[busNum] or 0
  if fxNum == 0 then
    return nil
  end
  local faderGroup = busGroup:findByName('faders', true)
  local excludeMarkedPresetsButton = busGroup:findByName('exclude_tuning_from_presets_button', true)
  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)
  if not faderGroup or not controlInfoArray then
    return nil
  end
  return {
    faderGroup = faderGroup,
    controlInfoArray = controlInfoArray,
    excludeMarkedPresets = excludeMarkedPresetsButton and excludeMarkedPresetsButton.values.x == 1,
  }
end

local function snapshotFadersForGrab(busNum)
  local ctx = getBusFaderContext(busNum)
  if not ctx then
    return nil
  end
  local ccValues = {}
  for i, controlInfo in ipairs(ctx.controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)
    local fader = ctx.faderGroup:findByName(tostring(i))
    local controlFader = fader and fader:findByName('control_fader')
    if controlFader and (not isExcludable or not ctx.excludeMarkedPresets) then
      ccValues[i] = floatToMIDI(controlFader.values.x)
    end
  end
  return ccValues
end

local function restoreGrabFaders(busNum)
  local ccValues = loadGrabRestoreCc(busNum)
  if not ccValues then
    return
  end
  local ctx = getBusFaderContext(busNum)
  if not ctx then
    return
  end
  for i, controlInfo in ipairs(ctx.controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)
    local stored = ccValues[i]
    if stored ~= nil and (not isExcludable or not ctx.excludeMarkedPresets) then
      local fader = ctx.faderGroup:findByName(tostring(i))
      local controlFader = fader and fader:findByName('control_fader')
      if controlFader then
        controlFader:notify('new_value', midiToFloat(stored))
      end
    end
  end
end

local function endGrabForBus(busNum)
  restoreGrabFaders(busNum)
  clearGrabRestoreCc(busNum)
  activeGrabByBus[busNum] = nil
end

local function restoreAllActiveGrabs()
  for busNum, _ in pairs(activeGrabByBus) do
    endGrabForBus(busNum)
  end
end

local function lerpMidi(source, target, amount)
  return math.floor(source + (target - source) * amount / 127 + 0.5)
end

local function applyCcValuesToFaders(busNum, ccValues, lastAppliedCc)
  local ctx = getBusFaderContext(busNum)
  if not ctx or not ccValues then
    return
  end
  for i, controlInfo in ipairs(ctx.controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)
    local stored = ccValues[i]
    if stored ~= nil and (not isExcludable or not ctx.excludeMarkedPresets) then
      if lastAppliedCc and lastAppliedCc[i] == stored then
        -- skip duplicate CC (reduces SP-404 MIDI load during morph aftertouch)
      else
        local fader = ctx.faderGroup:findByName(tostring(i))
        local controlFader = fader and fader:findByName('control_fader')
        if controlFader then
          controlFader:notify('new_value', midiToFloat(stored))
          if lastAppliedCc then
            lastAppliedCc[i] = stored
          end
        end
      end
    end
  end
end

local function loadPresetCcValues(busNum, presetNum)
  local fxNum = fxNums[busNum] or 0
  if fxNum == 0 then
    return nil
  end
  local presetManagerChild = presetManager.children[tostring(fxNum)]
  if not presetManagerChild then
    return nil
  end
  local presetArray = json.toTable(presetManagerChild.tag) or {}
  local presetValues = presetArray[formatPresetNum(presetNum)]
  if presetValues == nil then
    return nil
  end
  local ctx = getBusFaderContext(busNum)
  if not ctx then
    return nil
  end
  local targetCc = {}
  for i, controlInfo in ipairs(ctx.controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)
    if not isExcludable or not ctx.excludeMarkedPresets then
      targetCc[i] = presetValues[i]
    end
  end
  return targetCc
end

local function clearMorphSession(busNum, restoreSource)
  local session = activeMorphByBus[busNum]
  if not session then
    return
  end
  if restoreSource and not session.pendingCommit then
    applyCcValuesToFaders(busNum, session.sourceCc, session.lastAppliedCc)
  end
  activeMorphByBus[busNum] = nil
end

local function cancelAllMorphSessions()
  for busNum, _ in pairs(activeMorphByBus) do
    clearMorphSession(busNum, true)
  end
end

local function applyMorphBlend(busNum, amount)
  local session = activeMorphByBus[busNum]
  if not session then
    return
  end
  amount = math.max(0, math.min(127, math.floor(amount)))
  session.lastAmount = amount
  local ctx = getBusFaderContext(busNum)
  if not ctx then
    return
  end
  local blended = {}
  for i, controlInfo in ipairs(ctx.controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)
    local src = session.sourceCc[i]
    local tgt = session.targetCc[i]
    if src ~= nil and tgt ~= nil and (not isExcludable or not ctx.excludeMarkedPresets) then
      blended[i] = lerpMidi(src, tgt, amount)
    end
  end
  applyCcValuesToFaders(busNum, blended, session.lastAppliedCc)
end

local function beginMorphPreset(busNum, presetNum, initialAmount)
  if not isStoredPresetButton(busNum, presetNum) then
    return
  end
  clearMorphSession(busNum, true)
  local sourceCc = snapshotFadersForGrab(busNum)
  local targetCc = loadPresetCcValues(busNum, presetNum)
  if not sourceCc or not targetCc then
    return
  end
  local lastAppliedCc = {}
  for i, cc in pairs(sourceCc) do
    lastAppliedCc[i] = cc
  end
  activeMorphByBus[busNum] = {
    presetNum = presetNum,
    sourceCc = sourceCc,
    targetCc = targetCc,
    lastAmount = 0,
    pendingCommit = false,
    lastAppliedCc = lastAppliedCc,
  }
  applyMorphBlend(busNum, initialAmount or 0)
end

local function endMorphPad(busNum, presetNum)
  local session = activeMorphByBus[busNum]
  if not session or session.presetNum ~= presetNum then
    return
  end
  applyCcValuesToFaders(busNum, session.sourceCc, session.lastAppliedCc)
  session.pendingCommit = true
end

local function commitMorphSessions()
  for busNum, session in pairs(activeMorphByBus) do
    if session.pendingCommit then
      applyMorphBlend(busNum, session.lastAmount)
    end
    activeMorphByBus[busNum] = nil
  end
end

local function handleMorphPad(busNum, presetNum, isPressed, initialAmount)
  if isPressed then
    beginMorphPreset(busNum, presetNum, initialAmount)
  else
    endMorphPad(busNum, presetNum)
  end
end

local function handleMorphPressure(busNum, presetNum, amount)
  local session = activeMorphByBus[busNum]
  if not session or session.presetNum ~= presetNum or session.pendingCommit then
    return
  end
  applyMorphBlend(busNum, amount)
end

local function getFxNumFromBusTag(busNum)
  local busGroup = root:findByName('bus' .. tostring(busNum) .. '_group', true)
  if not busGroup then return 0 end
  local settings = json.toTable(busGroup.tag) or {}
  return tonumber(settings.fxNum) or 0
end

-- Keeps fxNums in sync when init order skips refresh_presets_list or tag was updated elsewhere.
local function syncFxNumFromBusTag(busNum)
  local fxNum = getFxNumFromBusTag(busNum)
  fxNums[busNum] = fxNum
  return fxNum
end

local function initialiseButtons(busNum)
  local grid = getGrid(busNum)
  if not grid then return end

  for i = 1, PRESETS_PER_BUS do
    local button = grid:findByName(tostring(i))
    if button then
      button.color = BUTTON_STATE_COLORS.AVAILABLE
    end
  end
  sendSysexAllPadsOff(busNum)
end

local function refreshMIDIButtons(busNum)
  local grid = getGrid(busNum)
  if not grid then return end

  local entries = {}

  for i = 1, PRESETS_PER_BUS do
    local button = grid:findByName(tostring(i))
    if button then
      local buttonHex = Color.toHexString(button.color)
      local r, g, b
      local busHex = getRecallButtonColor(busNum)

      if buttonHex == BUTTON_STATE_COLORS.DELETE then
        r, g, b = launchpadDeleteRgb(LAUNCHPAD_IDLE_BRIGHTNESS)
      elseif buttonHex == busHex then
        r, g, b = launchpadBusRgb(busNum, LAUNCHPAD_IDLE_BRIGHTNESS)
      else
        r, g, b = nil
      end

      if r then
        local mapEntry = (busNum - 1) * PRESETS_PER_BUS + i
        local note = presetNoteMap[mapEntry]
        if note then
          table.insert(entries, note)
          table.insert(entries, r)
          table.insert(entries, g)
          table.insert(entries, b)
        end
      end
    end
  end

  sendLaunchpadLedRgbBatch(entries)
end

local function refreshPresets(busNum, fxNum)
  if fxNum ~= nil then
    fxNums[busNum] = fxNum
  end
  fxNum = fxNums[busNum] or 0

  sendSysexAllPadsOff(busNum)

  local grid = getGrid(busNum)
  if not grid then return end

  if fxNum == 0 then
    initialiseButtons(busNum)
    return
  end

  if not presetManager then return end
  local presetManagerChild = presetManager.children[tostring(fxNum)]
  if not presetManagerChild then return end
  local presetArray = json.toTable(presetManagerChild.tag) or {}

  initialiseButtons(busNum)

  -- Set STORED state for active presets
  for index, _ in pairs(presetArray) do
    local presetNum = tonumber(index)
    if presetNum and presetNum >= 1 and presetNum <= PRESETS_PER_BUS then
      local button = grid:findByName(tostring(presetNum))
      if button then
        local color = deleteMode and BUTTON_STATE_COLORS.DELETE or getRecallButtonColor(busNum)
        button.color = color
      end
    end
  end

  refreshMIDIButtons(busNum)
end

local function refreshAllBusesForFx(fxNum)
  -- Refresh all buses that have this fxNum loaded
  for busNum, busFxNum in pairs(fxNums) do
    if busFxNum == fxNum and fxNum ~= 0 then
      refreshPresets(busNum)
    end
  end
end

local function recallPreset(busNum, presetNum)
  local fxNum = fxNums[busNum] or 0

  if fxNum == 0 then return end

  local presetArray = json.toTable(presetManager.children[tostring(fxNum)].tag) or {}
  local presetValues = presetArray[formatPresetNum(presetNum)]

  if presetValues == nil then
    return
  end

  local grid = getGrid(busNum)
  if not grid then return end

  local busGroup = grid.parent
  local excludeMarkedPresetsButton = busGroup:findByName('exclude_tuning_from_presets_button', true)
  local faderGroup = busGroup:findByName('faders', true)
  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)

  local exclude_marked_presets = excludeMarkedPresetsButton.values.x == 1

  for i, controlInfo in ipairs(controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)
    local fader = faderGroup:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')

    if not isExcludable or not exclude_marked_presets then
      controlFader:notify('new_value', midiToFloat(presetValues[i]))
    end
  end
end

local function beginGrabPreset(busNum, presetNum)
  if not isStoredPresetButton(busNum, presetNum) then
    return
  end
  if loadGrabRestoreCc(busNum) == nil then
    local snapshot = snapshotFadersForGrab(busNum)
    if snapshot then
      saveGrabRestoreCc(busNum, snapshot)
    end
  end
  activeGrabByBus[busNum] = presetNum
  recallPreset(busNum, presetNum)
end

local function handleGrabModePad(busNum, presetNum, isPressed)
  if isPressed then
    beginGrabPreset(busNum, presetNum)
  elseif activeGrabByBus[busNum] == presetNum then
    endGrabForBus(busNum)
  end
end

local function recallDefaults(busNum)
  local fxNum = fxNums[busNum] or 0

  if fxNum == 0 then return end

  local defaultValues = json.toTable(defaultManager.tag)[tostring(fxNum)]

  if defaultValues == nil then
    return
  end

  local grid = getGrid(busNum)
  if not grid then return end

  local busGroup = grid.parent
  local excludeMarkedPresetsButton = busGroup:findByName('exclude_tuning_from_presets_button', true)
  local faderGroup = busGroup:findByName('faders', true)
  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)

  local exclude_marked_presets = excludeMarkedPresetsButton.values.x == 1

  for i, controlInfo in ipairs(controlInfoArray) do
    local _, _, isExcludable = unpack(controlInfo)
    local fader = faderGroup:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')

    if not isExcludable or not exclude_marked_presets then
      controlFader:notify('new_value', midiToFloat(defaultValues[i]))
    end
  end
end

local function storePreset(busNum, presetNum, delete)
  local fxNum = fxNums[busNum] or 0

  if fxNum == 0 then return end

  local grid = getGrid(busNum)
  if not grid then return end

  local busGroup = grid.parent
  local faderGroup = busGroup:findByName('faders', true)
  local ccValues = {unpack(defaultCCValues)}
  local presetArray = json.toTable(presetManager.children[tostring(fxNum)].tag) or {}

  if not delete and not deleteMode then
    for i = 1, 6 do
      local fader = faderGroup:findByName(tostring(i))
      local controlFader = fader:findByName('control_fader')
      ccValues[i] = floatToMIDI(controlFader.values.x)
    end

    presetArray[formatPresetNum(presetNum)] = ccValues
  else
    presetArray[formatPresetNum(presetNum)] = nil
  end

  local jsonPresets = json.fromTable(presetArray)
  presetManager.children[tostring(fxNum)].tag = jsonPresets

  refreshAllBusesForFx(fxNum)
end

local function storeDefaults(busNum)
  local fxNum = fxNums[busNum] or 0

  if fxNum == 0 then return end

  local grid = getGrid(busNum)
  if not grid then return end

  local busGroup = grid.parent
  local faderGroup = busGroup:findByName('faders', true)
  local ccValues = {unpack(defaultCCValues)}

  for i = 1, 6 do
    local fader = faderGroup:findByName(tostring(i))
    local controlFader = fader:findByName('control_fader')
    ccValues[i] = floatToMIDI(controlFader.values.x)

    controlFader:setValueField("x", ValueField.DEFAULT, controlFader.values.x)
  end

  defaultManager:notify('store_defaults', {fxNum, ccValues})
end

local function updateButtonMIDIHighlight(busNum, presetNum, isPressed)
  local grid = getGrid(busNum)
  if not grid then return end

  local button = grid:findByName(tostring(presetNum))
  local buttonColor = Color.toHexString(button.color)
  local mapEntry = (busNum - 1) * PRESETS_PER_BUS + presetNum
  local note = presetNoteMap[mapEntry]

  if not note then
    return
  end

  local r, g, b
  local busHex = getRecallButtonColor(busNum)

  if buttonColor == BUTTON_STATE_COLORS.DELETE then
    if not isPressed then
      return
    end
    r, g, b = launchpadDeleteRgb(LAUNCHPAD_ON_BRIGHTNESS)
  elseif buttonColor == busHex then
    local brightness = isPressed and LAUNCHPAD_ON_BRIGHTNESS or LAUNCHPAD_IDLE_BRIGHTNESS
    r, g, b = launchpadBusRgb(busNum, brightness)
  elseif buttonColor == BUTTON_STATE_COLORS.AVAILABLE then
    if isPressed then
      r, g, b = launchpadBusRgb(busNum, PRESET_LED_EMPTY_PRESS_BRIGHTNESS)
    else
      sendLaunchpadLedOff(note)
      return
    end
  end

  if r then
    sendLaunchpadLedRgb(note, r, g, b)
  end
end

local function buttonPressed(busNum, presetNum)
  local grid = getGrid(busNum)
  if not grid then return end

  local button = grid:findByName(tostring(presetNum))
  local buttonColor = Color.toHexString(button.color)

  if (buttonColor == BUTTON_STATE_COLORS.DELETE) then
    storePreset(busNum, presetNum, true)
  elseif (buttonColor == getRecallButtonColor(busNum)) then
    recallPreset(busNum, presetNum)
  else
    storePreset(busNum, presetNum, false)
  end
end

local function toggleDeleteMode(value)
  deleteMode = value
  if value then
    grabMode = false
    cancelAllMorphSessions()
    restoreAllActiveGrabs()
    local grabButton = root:findByName('grab_mode_button', true)
    if grabButton then
      grabButton.values.x = 0
    end
  end

  -- Refresh all buses
  for busNum, _ in pairs(fxNums) do
    refreshPresets(busNum)
  end
end

local function toggleGrabMode(value)
  grabMode = value
  if value then
    deleteMode = false
    cancelAllMorphSessions()
    restoreAllActiveGrabs()
    local deleteButton = root:findByName('delete_button', true)
    if deleteButton then
      deleteButton.values.x = 0
    end
  else
    restoreAllActiveGrabs()
  end

  for busNum, _ in pairs(fxNums) do
    refreshPresets(busNum)
  end
end

local function initializeGrid(busNum)
  local grid = getGrid(busNum)
  if not grid then return end

  sendSysexAllPadsOff(busNum)

  local busGroup = grid.parent
  -- Get initial fxNum from bus_group tag
  local busSettings = json.toTable(busGroup.tag) or {}
  local fxNum = tonumber(busSettings.fxNum) or 0
  fxNums[busNum] = fxNum

  refreshPresets(busNum, fxNum)
end

-- Global: TouchOSC dispatches :notify() to onReceiveNotify on this node.
function onReceiveNotify(key, value)
  if key == 'refresh_presets_list' then
    if type(value) ~= 'table' then return end
    local busNum = value[1]
    local fxNum = value[2]
    if busNum then
      refreshPresets(busNum, fxNum)
    end
  elseif key == 'toggle_delete_mode' then
    toggleDeleteMode(value)
  elseif key == 'toggle_grab_mode' then
    toggleGrabMode(value)
  elseif key == 'store_defaults' then
    local busNum = value
    if busNum then
      storeDefaults(busNum)
    end
  elseif key == 'recall_defaults' then
    local busNum = value
    if busNum then
      recallDefaults(busNum)
    end
  elseif key == 'button_value_changed' then
    if type(value) ~= 'table' then return end
    local busNum = value[1]
    local presetNum = value[2]
    local isPressed = value[3] == 1
    local shiftHeld = value[4] == true
    local quantiseHeld = value[5] == true
    local noteVelocity = tonumber(value[6]) or 0
    local inGrabMode = grabMode or shiftHeld
    local fxNum = fxNums[busNum] or 0
    if fxNum == 0 then
      fxNum = syncFxNumFromBusTag(busNum)
    end

    if fxNum == 0 then
      return
    end

    updateButtonMIDIHighlight(busNum, presetNum, isPressed)

    if deleteMode then
      if isPressed then
        buttonPressed(busNum, presetNum)
      end
      return
    end

    if quantiseHeld then
      handleMorphPad(busNum, presetNum, isPressed, noteVelocity)
      return
    end

    if inGrabMode then
      handleGrabModePad(busNum, presetNum, isPressed)
      return
    end

    if isPressed then
      buttonPressed(busNum, presetNum)
    end
  elseif key == 'clear_presets' then
    local busNum = value
    if busNum then
      clearMorphSession(busNum, true)
      fxNums[busNum] = 0
      initialiseButtons(busNum)
    end
  elseif key == 'morph_pressure' then
    if type(value) ~= 'table' then return end
    local busNum = value[1]
    local presetNum = value[2]
    local amount = value[3]
    if busNum and presetNum and amount ~= nil then
      handleMorphPressure(busNum, presetNum, amount)
    end
  elseif key == 'commit_morph_sessions' then
    commitMorphSessions()
  elseif key == 'cancel_morph_sessions' then
    cancelAllMorphSessions()
  end
end

-- preset_grid.lua and preset_pad.lua are build-injected via toscbuild (under_name for pads).

function init()
  for i = 1, 5 do
    initializeGrid(i)
  end

  -- If bus_group inits ran after we read tags inside initializeGrid, pick up final fxNum from tags.
  for i = 1, 5 do
    local tagFx = getFxNumFromBusTag(i)
    if tagFx ~= (fxNums[i] or 0) then
      fxNums[i] = tagFx
      refreshPresets(i, tagFx)
    end
  end
end