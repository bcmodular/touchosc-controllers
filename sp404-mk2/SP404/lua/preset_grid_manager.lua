local fxNums = {}
local deleteMode = false

local PRESETS_PER_BUS = 8
local NUM_BUSES = 5
local LEGACY_PRESET_SLOT_MAX = 16

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

local velocityColours = { 35, 15, 59, 47, 21 }

local BUTTON_STATE_COLORS = {
  AVAILABLE = "FFFFFFFF",
  DELETE = "FF0000FF"
}

local defaultCCValues = {0, 0, 0, 0, 0, 0}

-- Launchpad Pro LED SysEx: TouchOSC MIDI connection 3 (same as root.lua)
local LAUNCHPAD_MIDI_CONNECTION = { false, false, true }

-- Shared references
local presetManager = root.children.preset_manager
local defaultManager = root.children.default_manager
local controlsInfo = root.children.controls_info

local function formatPresetNum(num)
  return string.format("%02d", num)
end

local function purgeLegacyPresetSlots(presetArray)
  local dirty = false
  for i = 9, LEGACY_PRESET_SLOT_MAX do
    local key = formatPresetNum(i)
    if presetArray[key] ~= nil then
      presetArray[key] = nil
      dirty = true
    end
  end
  return dirty
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

local function sendSysexLEDUpdate(ledIndex, color)
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0A, ledIndex, color, 0xF7 }
  print('sendSysexLEDUpdate', ledIndex, color)
  sendMIDI(sysexMessage, LAUNCHPAD_MIDI_CONNECTION)
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
    print('sendSysexAllPadsOff bus', busNum, #ledUpdates / 2, 'pads')
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

  local ledUpdates = {}
  for i = 1, PRESETS_PER_BUS do
    local button = grid:findByName(tostring(i))
    if button then
      local midiColour = 0

      if (Color.toHexString(button.color) == BUTTON_STATE_COLORS.DELETE) then
        midiColour = 5
      elseif (Color.toHexString(button.color) == getRecallButtonColor(busNum)) then
        midiColour = velocityColours[busNum] or velocityColours[1] or 35
      end

      if midiColour ~= 0 then
        local mapEntry = (busNum - 1) * PRESETS_PER_BUS + i
        local note = presetNoteMap[mapEntry]
        if note then
          table.insert(ledUpdates, note)
          table.insert(ledUpdates, midiColour)
        end
      end
    end
  end

  if #ledUpdates > 0 then
    local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0A }
    for _, value in ipairs(ledUpdates) do
      table.insert(sysexMessage, value)
    end
    table.insert(sysexMessage, 0xF7)
    print('refreshMIDIButtons bus', busNum, #ledUpdates / 2, 'LEDs')
    sendMIDI(sysexMessage, LAUNCHPAD_MIDI_CONNECTION)
  end
end

local function refreshPresets(busNum, fxNum)
  if fxNum ~= nil then
    fxNums[busNum] = fxNum
  end
  fxNum = fxNums[busNum] or 0

  print('refreshPresets', busNum, fxNum)
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

  if purgeLegacyPresetSlots(presetArray) then
    presetManagerChild.tag = json.fromTable(presetArray)
  end

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

    print('recallPreset', busNum, fxNum, presetNum, i, presetValues[i])
    if not isExcludable or not exclude_marked_presets then
      controlFader:notify('new_value', midiToFloat(presetValues[i]))
    end
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

    print('recallDefaults', busNum, fxNum, i, defaultValues[i])
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

    print('storePreset', busNum, fxNum, presetNum, ccValues)
    presetArray[formatPresetNum(presetNum)] = ccValues
  else
    print('deletePreset', busNum, fxNum, presetNum)
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

  print('storeDefaults', busNum, fxNum, ccValues)
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

  local color = 0
  local baseVelocity = velocityColours[busNum] or velocityColours[1] or 35

  if buttonColor == BUTTON_STATE_COLORS.DELETE then
    return
  elseif buttonColor == getRecallButtonColor(busNum) then
    if isPressed then
      color = baseVelocity - 2
    else
      color = baseVelocity
    end
  elseif buttonColor == BUTTON_STATE_COLORS.AVAILABLE then
    if isPressed then
      color = baseVelocity
    end
  end

  if color > 0 then
    sendSysexLEDUpdate(note, color)
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
  print('toggleDeleteMode', value)
  deleteMode = value

  -- Refresh all buses
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
  local vt = type(value)
  local vstr = (vt == 'table' and string.format('{%s,%s,%s}', tostring(value[1]), tostring(value[2]), tostring(value[3])))
    or tostring(value)
  print('preset_grid_manager onReceiveNotify', key, vstr, '(' .. vt .. ')')

  if key == 'refresh_presets_list' then
    if type(value) ~= 'table' then return end
    local busNum = value[1]
    local fxNum = value[2]
    if busNum then
      refreshPresets(busNum, fxNum)
    end
  elseif key == 'toggle_delete_mode' then
    toggleDeleteMode(value)
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
    local fxNum = fxNums[busNum] or 0
    if fxNum == 0 then
      fxNum = syncFxNumFromBusTag(busNum)
      if fxNum ~= 0 then
        print('preset_grid_manager synced fxNum from bus_group.tag', busNum, fxNum)
      end
    end

    if fxNum == 0 then
      print('preset_grid_manager button_value_changed ignored: no FX on bus', busNum, '(choose an effect for this bus first)')
      return
    end

    updateButtonMIDIHighlight(busNum, presetNum, isPressed)
    if isPressed then
      buttonPressed(busNum, presetNum)
    end
  elseif key == 'clear_presets' then
    local busNum = value
    if busNum then
      print('clear_presets', busNum)
      fxNums[busNum] = 0
      initialiseButtons(busNum)
    end
  end
end

-- Delegate scripts pushed onto each `preset_grid` and pad at runtime (no toscbuild required
-- for these; the manager script itself can be pasted on `preset_grid_manager` in TouchOSC).
local presetGridScript = [[
local busNum = tonumber(self.tag) or 1
local manager = root.children.preset_grid_manager

local function logValue(value)
  local t = type(value)
  if t == 'table' then
    return string.format('table{%s,%s,%s}', tostring(value[1]), tostring(value[2]), tostring(value[3]))
  end
  return tostring(value) .. ' (' .. t .. ')'
end

function onReceiveNotify(key, value)
  print('preset_grid', self.name, 'bus', busNum, 'onReceiveNotify', key, logValue(value))
  if not manager then
    print('preset_grid', self.name, 'bus', busNum, 'no root.children.preset_grid_manager')
    return
  end
  if key == 'refresh_presets_list' then
    local fxNum = value
    print('preset_grid -> manager refresh_presets_list', busNum, fxNum)
    manager:notify(key, {busNum, fxNum})
  elseif key == 'toggle_delete_mode' then
    print('preset_grid -> manager toggle_delete_mode', logValue(value))
    manager:notify(key, value)
  elseif key == 'store_defaults' then
    print('preset_grid -> manager store_defaults', busNum)
    manager:notify(key, busNum)
  elseif key == 'recall_defaults' then
    print('preset_grid -> manager recall_defaults', busNum)
    manager:notify(key, busNum)
  elseif key == 'button_value_changed' then
    print('preset_grid -> manager button_value_changed relay', busNum, logValue(value))
    manager:notify(key, {busNum, value[1], value[2]})
  elseif key == 'clear_presets' then
    print('preset_grid -> manager clear_presets', busNum)
    manager:notify(key, busNum)
  else
    print('preset_grid unhandled key', key)
  end
end
]]

local presetButtonScript = [[
function onValueChanged(key, value)
  if key == 'x' then
    local presetNum = tonumber(self.name)
    local busNum = tonumber(self.parent and self.parent.tag) or 1
    local manager = root.children.preset_grid_manager
    print('preset_pad', self.name, 'bus', busNum, 'onValueChanged x=', self.values.x, 'arg value=', value, 'manager=', manager ~= nil, 'parent.tag=', self.parent and self.parent.tag)
    if not manager then
      print('preset_pad', self.name, 'no root.children.preset_grid_manager')
      return
    end
    manager:notify('button_value_changed', {busNum, presetNum, self.values.x})
    print('preset_pad', self.name, 'notified button_value_changed', busNum, presetNum, self.values.x)
  end
end
]]

function init()
  local presetGrids = root:findAllByName('preset_grid', true)

  for _, presetGrid in ipairs(presetGrids) do
    presetGrid.script = presetGridScript
    for i = 1, PRESETS_PER_BUS do
      local button = presetGrid:findByName(tostring(i))
      if button then
        button.script = presetButtonScript
      end
    end
  end

  for i = 1, 5 do
    initializeGrid(i)
  end

  -- If bus_group inits ran after we read tags inside initializeGrid, pick up final fxNum from tags.
  for i = 1, 5 do
    local tagFx = getFxNumFromBusTag(i)
    if tagFx ~= (fxNums[i] or 0) then
      print('preset_grid_manager init resync bus', i, 'fxNum', fxNums[i], '->', tagFx)
      fxNums[i] = tagFx
      refreshPresets(i, tagFx)
    end
  end
end