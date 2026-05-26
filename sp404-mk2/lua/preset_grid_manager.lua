local fxNums = {}
local deleteMode = false
local grabMode = false
-- busNum -> presetNum currently held in grab mode (last pressed wins per bus)
local activeGrabByBus = {}
-- busNum -> morph blend runtime while morphEnabled (source/target CC)
local activeUiMorphByBus = {}

-- Set false to silence morph UI logs in TouchOSC console.
local MORPH_DEBUG = true

local function debugMorph(msg)
  if MORPH_DEBUG then
    print('[Morph]', msg)
  end
end

-- Forward declarations: morph helpers call these before their definitions below.
local refreshPresets
local setMorphEnabled

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
  DELETE = "FF0000FF",
  -- Magenta: target-pick mode only (not bus 5 green, not delete red).
  MORPH_SELECT = "FF44CCFF",
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

local function getBusGroup(busNum)
  return root:findByName('bus' .. tostring(busNum) .. '_group', true)
end

local function getGrid(busNum)
  local busGroup = getBusGroup(busNum)
  if busGroup then
    return busGroup:findByName('preset_grid', true)
  end
  return nil
end

local function readBusTag(busNum)
  local busGroup = getBusGroup(busNum)
  if not busGroup then
    return {}
  end
  return json.toTable(busGroup.tag) or {}
end

local function writeBusTag(busNum, settings)
  local busGroup = getBusGroup(busNum)
  if busGroup then
    busGroup.tag = json.fromTable(settings)
  end
end

local function getMorphTargetPreset(busNum)
  local tag = readBusTag(busNum)
  local preset = tonumber(tag.morphTargetPreset)
  if preset and preset >= 1 and preset <= PRESETS_PER_BUS then
    return preset
  end
  return nil
end

local function isMorphEnabled(busNum)
  local tag = readBusTag(busNum)
  return tag.morphEnabled == true
end

local function echoMorphAmountBcr(busNum, amount)
  local busGroup = getBusGroup(busNum)
  local controlGroup = busGroup and busGroup:findByName('control_group', true)
  local onOff = controlGroup and controlGroup:findByName('on_off_button_group', true)
  if onOff then
    onOff:notify('echo_morph_amount_bcr', amount)
  end
end

local function syncMorphControlsUi(busNum)
  local busGroup = getBusGroup(busNum)
  if not busGroup then
    debugMorph(string.format('syncMorphControlsUi bus %d: bus group not found', busNum))
    return
  end
  local tag = readBusTag(busNum)
  local enabled = tag.morphEnabled == true
  local target = getMorphTargetPreset(busNum)
  local amount = tonumber(tag.morphAmount) or 0

  local controlGroup = busGroup:findByName('control_group', true)
  local onOff = controlGroup and controlGroup:findByName('on_off_button_group', true)
  if onOff then
    local morphBtn = onOff:findByName('morph_button', true)
    if morphBtn then
      morphBtn.values.x = enabled and 1 or 0
    end
    onOff:notify('echo_morph_bcr', enabled)
  end

  local morphGroup = controlGroup and controlGroup:findByName('morph_group', true)
  if morphGroup then
    morphGroup.visible = enabled
    if enabled then
      local amountFader = morphGroup:findByName('morph_amount_fader', true)
      local targetLabel = morphGroup:findByName('morph_target_label', true)
      local showFader = target ~= nil
      if amountFader then
        amountFader.visible = showFader
        if showFader then
          amountFader.values.x = amount / 127
        end
      end
      if targetLabel then
        targetLabel.values.text = target
          and ('TARGET PRESET: ' .. tostring(target))
          or 'CHOOSE A TARGET PRESET'
      end
    end
  end
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
  -- Use preset_manager data, not pad color (morph/delete modes change button.color).
  local fxNum = fxNums[busNum] or 0
  if fxNum == 0 or not presetManager then
    return false
  end
  local presetManagerChild = presetManager.children[tostring(fxNum)]
  if not presetManagerChild then
    return false
  end
  local presetArray = json.toTable(presetManagerChild.tag) or {}
  return presetArray[formatPresetNum(presetNum)] ~= nil
end

local function listStoredPresets(busNum)
  local list = {}
  for preset = 1, PRESETS_PER_BUS do
    if isStoredPresetButton(busNum, preset) then
      table.insert(list, preset)
    end
  end
  return list
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

local function disableMorphAllBuses()
  for busNum = 1, NUM_BUSES do
    if isMorphEnabled(busNum) then
      setMorphEnabled(busNum, false)
    end
  end
end

local function clearUiMorphRuntime(busNum)
  activeUiMorphByBus[busNum] = nil
end

local function rebuildUiMorphSession(busNum)
  local targetPreset = getMorphTargetPreset(busNum)
  if not targetPreset then
    debugMorph(string.format('rebuildUiMorphSession bus %d: no morph target preset', busNum))
    return false
  end
  local sourceCc = snapshotFadersForGrab(busNum)
  local targetCc = loadPresetCcValues(busNum, targetPreset)
  if not sourceCc or not targetCc then
    debugMorph(string.format(
      'rebuildUiMorphSession bus %d target %d: snapshot=%s targetCc=%s fxNum=%d',
      busNum, targetPreset, sourceCc and 'ok' or 'nil', targetCc and 'ok' or 'nil', fxNums[busNum] or 0
    ))
    return false
  end
  local lastAppliedCc = {}
  for i, cc in pairs(sourceCc) do
    lastAppliedCc[i] = cc
  end
  activeUiMorphByBus[busNum] = {
    sourceCc = sourceCc,
    targetCc = targetCc,
    lastAppliedCc = lastAppliedCc,
  }
  debugMorph(string.format('rebuildUiMorphSession bus %d: target preset %d', busNum, targetPreset))
  return true
end

local function applyUiMorphBlend(busNum, amount)
  local session = activeUiMorphByBus[busNum]
  if not session then
    debugMorph(string.format('applyUiMorphBlend bus %d: no active session (amount=%d)', busNum, amount))
    return
  end
  amount = math.max(0, math.min(127, math.floor(amount)))
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

function setMorphEnabled(busNum, enabled)
  debugMorph(string.format('setMorphEnabled bus %d -> %s', busNum, enabled and 'on' or 'off'))
  local tag = readBusTag(busNum)
  if (fxNums[busNum] or 0) == 0 then
    debugMorph(string.format('setMorphEnabled bus %d: rejected (no FX loaded, fxNum=0)', busNum))
    syncMorphControlsUi(busNum)
    return false
  end
  if enabled then
    grabMode = false
    restoreAllActiveGrabs()
    local grabButton = root:findByName('grab_mode_button', true)
    if grabButton then
      grabButton.values.x = 0
    end
    tag.morphEnabled = true
    writeBusTag(busNum, tag)
    local target = getMorphTargetPreset(busNum)
    if target and rebuildUiMorphSession(busNum) then
      applyUiMorphBlend(busNum, tonumber(tag.morphAmount) or 0)
    end
    refreshPresets(busNum)
    debugMorph(string.format('setMorphEnabled bus %d: on (target=%s)', busNum, tostring(target)))
  else
    local amount = tonumber(tag.morphAmount) or 0
    if activeUiMorphByBus[busNum] then
      applyUiMorphBlend(busNum, amount)
    end
    tag.morphEnabled = false
    writeBusTag(busNum, tag)
    clearUiMorphRuntime(busNum)
    refreshPresets(busNum)
    debugMorph(string.format('setMorphEnabled bus %d: off (commit amount=%d)', busNum, amount))
  end
  syncMorphControlsUi(busNum)
  return true
end

local function setMorphAmount(busNum, amount, skipBcrEcho)
  amount = math.max(0, math.min(127, math.floor(amount)))
  debugMorph(string.format('setMorphAmount bus %d -> %d', busNum, amount))
  local tag = readBusTag(busNum)
  tag.morphAmount = amount
  writeBusTag(busNum, tag)
  if tag.morphEnabled == true then
    if not activeUiMorphByBus[busNum] then
      rebuildUiMorphSession(busNum)
    end
    applyUiMorphBlend(busNum, amount)
  end
  if not skipBcrEcho then
    echoMorphAmountBcr(busNum, amount)
  end
  syncMorphControlsUi(busNum)
end

local function setMorphTarget(busNum, presetNum)
  debugMorph(string.format('setMorphTarget bus %d preset %d', busNum, presetNum))
  if not isStoredPresetButton(busNum, presetNum) then
    debugMorph(string.format(
      'setMorphTarget bus %d preset %d: empty slot, clearing target (fx %d)',
      busNum, presetNum, fxNums[busNum] or 0
    ))
    local tag = readBusTag(busNum)
    tag.morphTargetPreset = nil
    tag.morphAmount = 0
    writeBusTag(busNum, tag)
    clearUiMorphRuntime(busNum)
    echoMorphAmountBcr(busNum, 0)
    syncMorphControlsUi(busNum)
    refreshPresets(busNum)
    return
  end
  local tag = readBusTag(busNum)
  tag.morphTargetPreset = presetNum
  tag.morphAmount = 0
  writeBusTag(busNum, tag)
  if tag.morphEnabled == true then
    rebuildUiMorphSession(busNum)
    applyUiMorphBlend(busNum, 0)
    echoMorphAmountBcr(busNum, 0)
  end
  syncMorphControlsUi(busNum)
  refreshPresets(busNum)
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
      elseif buttonHex == BUTTON_STATE_COLORS.MORPH_SELECT then
        r, g, b = launchpadRgb255(255, 68, 204, LAUNCHPAD_IDLE_BRIGHTNESS)
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

function refreshPresets(busNum, fxNum)
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

  local tag = readBusTag(busNum)
  local inMorphPick = tag.morphEnabled == true

  -- Set STORED state for active presets (morph target shown on morph_target_label only).
  for index, _ in pairs(presetArray) do
    local presetNum = tonumber(index)
    if presetNum and presetNum >= 1 and presetNum <= PRESETS_PER_BUS then
      local button = grid:findByName(tostring(presetNum))
      if button then
        local color
        if deleteMode and not isBusLocked(busNum) then
          color = BUTTON_STATE_COLORS.DELETE
        elseif inMorphPick then
          color = BUTTON_STATE_COLORS.MORPH_SELECT
        else
          color = getRecallButtonColor(busNum)
        end
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
  if isBusLocked(busNum) then
    return
  end

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
  if isBusLocked(busNum) then
    return
  end

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
  elseif buttonColor == BUTTON_STATE_COLORS.MORPH_SELECT then
    if isPressed then
      r, g, b = launchpadRgb255(255, 68, 204, LAUNCHPAD_ON_BRIGHTNESS)
    else
      r, g, b = launchpadRgb255(255, 68, 204, LAUNCHPAD_IDLE_BRIGHTNESS)
    end
  elseif buttonColor == BUTTON_STATE_COLORS.AVAILABLE then
    if isBusLocked(busNum) then
      if not isPressed then
        sendLaunchpadLedOff(note)
      end
      return
    end
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

  if isBusLocked(busNum) then
    if buttonColor == getRecallButtonColor(busNum) then
      recallPreset(busNum, presetNum)
    end
    return
  end

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
    disableMorphAllBuses()
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
    disableMorphAllBuses()
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
    local inGrabMode = grabMode or shiftHeld
    local morphOn = isMorphEnabled(busNum)
    local fxNum = fxNums[busNum] or 0
    if fxNum == 0 then
      fxNum = syncFxNumFromBusTag(busNum)
    end

    if fxNum == 0 then
      return
    end

    if isBusLocked(busNum) then
      local grid = getGrid(busNum)
      local button = grid and grid:findByName(tostring(presetNum))
      if button and Color.toHexString(button.color) == BUTTON_STATE_COLORS.AVAILABLE then
        if isPressed then
          button.values.x = 0
        else
          updateButtonMIDIHighlight(busNum, presetNum, false)
        end
        return
      end
    end

    updateButtonMIDIHighlight(busNum, presetNum, isPressed)

    if deleteMode then
      if isPressed and not isBusLocked(busNum) then
        buttonPressed(busNum, presetNum)
      end
      return
    end

    if morphOn then
      if isPressed then
        setMorphTarget(busNum, presetNum)
      end
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
      if isMorphEnabled(busNum) then
        setMorphEnabled(busNum, false)
      end
      clearUiMorphRuntime(busNum)
      fxNums[busNum] = 0
      initialiseButtons(busNum)
    end
  elseif key == 'disable_all_morph' then
    disableMorphAllBuses()
  elseif key == 'toggle_morph_enabled' then
    local busNum = value
    if busNum then
      setMorphEnabled(busNum, not isMorphEnabled(busNum))
    end
  elseif key == 'morph_pressure' then
    if type(value) ~= 'table' then
      return
    end
    local busNum = value[1]
    local pressure = value[3]
    if busNum and isMorphEnabled(busNum) then
      setMorphAmount(busNum, pressure)
    end
  elseif key == 'set_morph_enabled' then
    if type(value) ~= 'table' then
      debugMorph('set_morph_enabled: bad value (expected table)')
      return
    end
    setMorphEnabled(value[1], value[2] == true)
  elseif key == 'set_morph_amount' then
    if type(value) ~= 'table' then return end
    setMorphAmount(value[1], value[2], value[3] == true)
  elseif key == 'set_morph_target' then
    if type(value) ~= 'table' then return end
    setMorphTarget(value[1], value[2])
  elseif key == 'sync_morph_ui' then
    local busNum = value
    if busNum then
      syncMorphControlsUi(busNum)
    else
      for i = 1, NUM_BUSES do
        syncMorphControlsUi(i)
      end
    end
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
    syncMorphControlsUi(i)
  end
end