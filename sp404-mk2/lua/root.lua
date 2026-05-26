local noteMidiChannel = 10
local DELETE_BUTTON_LED = 0x32  -- LED index for delete button (50 decimal)

local PRESETS_PER_BUS = 8
local NUM_BUSES = 5

-- Launchpad Programmer round buttons (MIDI ch noteMidiChannel).
local SHIFT_CC = 80
local CLICK_CC = 70
local UNDO_CC = 60
local DELETE_CC = 50
local QUANTISE_CC = 40
local BUS_CC_FIRST = 91
local BUS_CC_LAST = 95
local LOCK_CC_FIRST = 1
local LOCK_CC_LAST = 5

local BUS_LOCK_HEX = "FF0000FF"

local launchpadShiftHeld = false
local launchpadClickHeld = false
local launchpadUndoHeld = false
local launchpadDeleteHeld = false
local launchpadQuantiseHeld = false
-- busNum -> true while Shift+grab is held on that bus CC
local busGrabPress = {}
-- busNum -> true while Click+store is held on that bus CC
local busClickPress = {}
-- busNum -> true while Undo+recall is held on that bus CC
local busUndoPress = {}

local LAUNCHPAD_DEBUG = false

-- Keep buildPresetNoteMap in sync with preset_grid_manager.lua (Launchpad columns 1–5, preset 1 at top).
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

local function presetNoteToBusPreset(note)
  for i = 1, #presetNoteMap do
    if presetNoteMap[i] == note then
      local presetIndex = i - 1
      return math.floor(presetIndex / PRESETS_PER_BUS) + 1, (presetIndex % PRESETS_PER_BUS) + 1
    end
  end
  return nil, nil
end

local sceneNoteToScene = buildLaunchpadSceneNoteToSceneMap()

-- Launchpad Pro: port 3 — LAUNCHPAD_MIDI_CONNECTION in launchpad_led.lua (include)

-- Bus chrome (preset area, edit strip, effect chooser, perform faders). Canonical ARGB hex per bus.
local BUS_ACCENT_HEX = {
  [1] = "00E6FFFF",
  [2] = "FFD700FF",
  [3] = "FF69B4FF",
  [4] = "4A90E2FF",
  [5] = "32CD32FF",
}

local function setChromeColor(node, hexStr)
  if not node or not hexStr then return end
  node.color = hexStr
end

-- Publishes accents on root.tag.busAccentHex (string keys "1".."5") for preset_grid_manager comparisons.
local function syncBusAccentRootTag()
  local tag = json.toTable(root.tag) or {}
  tag.busAccentHex = {
    ["1"] = BUS_ACCENT_HEX[1],
    ["2"] = BUS_ACCENT_HEX[2],
    ["3"] = BUS_ACCENT_HEX[3],
    ["4"] = BUS_ACCENT_HEX[4],
    ["5"] = BUS_ACCENT_HEX[5],
  }
  root.tag = json.fromTable(tag)
end

-- Applies bus chroma so duplicated bus groups need no per-bus color edits in the layout.
function applyBusGroupTheme(busNum)
  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then return end

  local grid = busGroup:findByName("preset_grid", true)
  if not grid then return end

  local hex = BUS_ACCENT_HEX[busNum] or BUS_ACCENT_HEX[5]

  local presetBgBox = grid:findByName("preset_grid_background_box", true)
  if presetBgBox then
    setChromeColor(presetBgBox, hex)
    local ch = presetBgBox.children
    if ch then
      for i = 1, #ch do
        setChromeColor(ch[i], hex)
      end
    end
  end

  setChromeColor(busGroup:findByName("edit_group", true), hex)

  local controlGroup = busGroup:findByName("control_group", true)
  local editModeButton = controlGroup and controlGroup:findByName("edit_mode_button", true)
  setChromeColor(editModeButton, hex)
  local editModeLabel = controlGroup and controlGroup:findByName("edit_mode_label", true)
  if editModeLabel then
    if editModeButton and editModeButton.values.x == 1 then
      editModeLabel.textColor = Color.fromHexString("000000FF")
    else
      editModeLabel.textColor = Color.fromHexString(hex)
    end
  end

  local lockButton = controlGroup and controlGroup:findByName("bus_lock_button", true)
  local lockLabel = controlGroup and controlGroup:findByName("bus_lock_label", true)
  if lockButton then
    setChromeColor(lockButton, BUS_LOCK_HEX)
    if lockLabel then
      if lockButton.values.x == 1 then
        lockLabel.textColor = Color.fromHexString("000000FF")
      else
        lockLabel.textColor = Color.fromHexString(BUS_LOCK_HEX)
      end
    end
  end

  local onOffButtonGroup = busGroup:findByName("on_off_button_group", true)
  if onOffButtonGroup then
    setChromeColor(onOffButtonGroup:findByName("toggle_button", true), hex)
    setChromeColor(onOffButtonGroup:findByName("morph_button", true), "FFFF00FF")
  end

  local effectChooser = busGroup:findByName("effect_chooser", true)
  if effectChooser then
    setChromeColor(effectChooser:findByName("choose_button", true), hex)
    setChromeColor(effectChooser:findByName("clear_button", true), hex)
    local fxLabel = effectChooser:findByName("label", true)
    if fxLabel then
      fxLabel.textColor = Color.fromHexString("FFFFFFFF")
    end
    local clearLabel = effectChooser:findByName("clear_label", true)
    if clearLabel then
      clearLabel.textColor = Color.fromHexString("FFFFFFFF")
    end
  end

  local morphGroup = busGroup:findByName("control_group", true)
  morphGroup = morphGroup and morphGroup:findByName("morph_group", true)
  if morphGroup then
    setChromeColor(morphGroup, hex)
    local morphChildren = morphGroup.children
    if morphChildren then
      for i = 1, #morphChildren do
        setChromeColor(morphChildren[i], hex)
      end
    end
  end

  local faderGroup = busGroup:findByName("faders", true)
  if faderGroup then
    for _, controlFader in ipairs(faderGroup:findAllByName("control_fader", true)) do
      setChromeColor(controlFader, hex)
    end
    for _, valueLabel in ipairs(faderGroup:findAllByName("value_label", true)) do
      valueLabel.textColor = Color.fromHexString("FFFFFFFF")
      valueLabel.color = Color.fromHexString("00000000")
    end
  end
end

local function debugLaunchpad(msg)
  if LAUNCHPAD_DEBUG then
    print("[Launchpad]", msg)
  end
end

local function busCcToBusNum(cc)
  if cc >= BUS_CC_FIRST and cc <= BUS_CC_LAST then
    return cc - 90
  end
  return nil
end

local function lockCcToBusNum(cc)
  if cc >= LOCK_CC_FIRST and cc <= LOCK_CC_LAST then
    return cc
  end
  return nil
end

local function readBusLockTable()
  local tag = json.toTable(root.tag) or {}
  if type(tag.busLock) == "table" then
    return tag.busLock
  end
  return {}
end

local function writeBusLockTable(locks)
  local tag = json.toTable(root.tag) or {}
  tag.busLock = locks
  root.tag = json.fromTable(tag)
end

local function getBusLockButton(busNum)
  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  local controlGroup = busGroup and busGroup:findByName("control_group", true)
  return controlGroup and controlGroup:findByName("bus_lock_button", true)
end

local function refreshLockButtonLED(busNum)
  local ccLed = busNum
  local brightness = LAUNCHPAD_IDLE_BRIGHTNESS
  if isBusLocked(busNum) then
    brightness = LAUNCHPAD_ON_BRIGHTNESS
  end
  local r, g, b = launchpadLockRgb(brightness)
  debugLaunchpad(string.format("lock LED %d rgb %d %d %d (bus %d)", ccLed, r, g, b, busNum))
  sendLaunchpadLedRgb(ccLed, r, g, b)
end

local function refreshAllLockButtonLEDs()
  for busNum = 1, NUM_BUSES do
    refreshLockButtonLED(busNum)
  end
end

local function syncBusLockUi(busNum, locked)
  local lockBtn = getBusLockButton(busNum)
  if lockBtn then
    lockBtn.values.x = locked and 1 or 0
  end
end

local function setBusLocked(busNum, locked)
  local locks = readBusLockTable()
  local key = tostring(busNum)
  if locked then
    locks[key] = true
  else
    locks[key] = nil
  end
  writeBusLockTable(locks)
  syncBusLockUi(busNum, locked)
  refreshLockButtonLED(busNum)
  applyBusGroupTheme(busNum)
end

local function getOnOffGroup(busNum)
  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then
    return nil
  end
  return busGroup:findByName("on_off_button_group", true)
end

local function getBusFxNum(busNum)
  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then
    return 0
  end
  local settings = json.toTable(busGroup.tag) or {}
  return tonumber(settings.fxNum) or 0
end

local function busHasFxLoaded(busNum)
  return getBusFxNum(busNum) ~= 0
end

local function isBusFxOn(busNum)
  local onOff = getOnOffGroup(busNum)
  if not onOff then
    return false
  end
  local toggle = onOff:findByName("toggle_button", true)
  return toggle and toggle.values.x == 1
end

local function refreshBusButtonLED(busNum)
  local ccLed = 90 + busNum
  local brightness = LAUNCHPAD_BUS_OFF_BRIGHTNESS
  if busHasFxLoaded(busNum) and (busGrabPress[busNum] or isBusFxOn(busNum)) then
    brightness = LAUNCHPAD_ON_BRIGHTNESS
  end
  local r, g, b = launchpadBusRgb(busNum, brightness)
  debugLaunchpad(string.format("LED %d rgb %d %d %d (bus %d)", ccLed, r, g, b, busNum))
  sendLaunchpadLedRgb(ccLed, r, g, b)
end

local function refreshAllBusButtonLEDs()
  for busNum = 1, NUM_BUSES do
    refreshBusButtonLED(busNum)
  end
end

local function syncLaunchpadModifierTags()
  local tag = json.toTable(root.tag) or {}
  tag.launchpadShiftHeld = launchpadShiftHeld
  tag.launchpadQuantiseHeld = launchpadQuantiseHeld
  root.tag = json.fromTable(tag)
end

local function getPresetGridManager()
  return root.children.preset_grid_manager
end

local function notifyPresetGridManager(key, value)
  local manager = getPresetGridManager()
  if manager then
    manager:notify(key, value)
  end
end

local function busMorphEnabled(busNum)
  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then
    return false
  end
  local tag = json.toTable(busGroup.tag) or {}
  return tag.morphEnabled == true
end

local function setLaunchpadGrabMode(grabModeOn)
  local grabButton = root:findByName("grab_mode_button", true)
  if grabButton then
    grabButton.values.x = grabModeOn and 1 or 0
  end
  for busNum = 1, NUM_BUSES do
    local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
    local grid = busGroup and busGroup:findByName("preset_grid", true)
    if grid then
      grid:notify("toggle_grab_mode", grabModeOn)
    end
  end
end

local function setLaunchpadDeleteMode(deleteMode)
  launchpadDeleteHeld = deleteMode
  local deleteButton = root:findByName("delete_button", true)
  if deleteButton then
    deleteButton.values.x = deleteMode and 1 or 0
  end
  if deleteMode then
    setLaunchpadGrabMode(false)
    notifyPresetGridManager("disable_all_morph")
  end
  local dr, dg, db = launchpadDeleteRgb(deleteMode and LAUNCHPAD_ON_BRIGHTNESS or LAUNCHPAD_IDLE_BRIGHTNESS)
  sendLaunchpadLedRgb(DELETE_BUTTON_LED, dr, dg, db)
  for busNum = 1, NUM_BUSES do
    local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
    local grid = busGroup and busGroup:findByName("preset_grid", true)
    if grid then
      grid:notify("toggle_delete_mode", deleteMode)
    end
  end
  local sceneGrid = root:findByName("scene_grid", true)
  if sceneGrid then
    sceneGrid:notify("toggle_delete_mode", deleteMode)
  end
end

local function getRecallDefaultsButton(busNum)
  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then
    return nil
  end
  return busGroup:findByName("recall_defaults_button", true)
end

local function getStoreDefaultsButton(busNum)
  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then
    return nil
  end
  return busGroup:findByName("store_defaults_button", true)
end

local function handleLaunchpadBusCc(busNum, pressed)
  local onOff = getOnOffGroup(busNum)
  if not onOff then
    return
  end

  if pressed then
    if launchpadDeleteHeld then
      if isBusLocked(busNum) then
        debugLaunchpad(string.format("bus %d delete+clear blocked (locked)", busNum))
      else
        local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
        if busGroup then
          busGroup:notify("clear_bus")
          refreshBusButtonLED(busNum)
          debugLaunchpad(string.format("bus %d delete+clear", busNum))
        end
      end
    elseif not busHasFxLoaded(busNum) then
      debugLaunchpad(string.format("bus %d ignored (no FX loaded)", busNum))
    elseif launchpadClickHeld then
      if isBusLocked(busNum) then
        debugLaunchpad(string.format("bus %d click+store blocked (locked)", busNum))
      else
      busClickPress[busNum] = true
      local storeBtn = getStoreDefaultsButton(busNum)
      if storeBtn then
        storeBtn.values.x = 1
      end
      local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
      local presetGrid = busGroup and busGroup:findByName("preset_grid", true)
      if presetGrid then
        presetGrid:notify("store_defaults", busNum)
      end
      debugLaunchpad(string.format("bus %d click+press (store defaults)", busNum))
      end
    elseif launchpadUndoHeld then
      busUndoPress[busNum] = true
      local recallBtn = getRecallDefaultsButton(busNum)
      if recallBtn then
        recallBtn.values.x = 1
      end
      local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
      local presetGrid = busGroup and busGroup:findByName("preset_grid", true)
      if presetGrid then
        presetGrid:notify("recall_defaults", busNum)
      end
      debugLaunchpad(string.format("bus %d undo+press (recall defaults)", busNum))
    elseif launchpadShiftHeld then
      busGrabPress[busNum] = true
      onOff:notify("set_grab_state", true)
      refreshBusButtonLED(busNum)
      debugLaunchpad(string.format("bus %d shift+grab on", busNum))
    elseif launchpadQuantiseHeld then
      local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
      local presetGrid = busGroup and busGroup:findByName("preset_grid", true)
      if presetGrid then
        presetGrid:notify("toggle_morph_enabled", busNum)
      end
      debugLaunchpad(string.format("bus %d quantise+morph toggle", busNum))
    else
      local toggle = onOff:findByName("toggle_button", true)
      local newOn = not (toggle and toggle.values.x == 1)
      onOff:notify("launchpad_toggle", newOn)
      refreshBusButtonLED(busNum)
      debugLaunchpad(string.format("bus %d toggle -> %s", busNum, tostring(newOn)))
    end
  elseif busClickPress[busNum] then
    busClickPress[busNum] = nil
    local storeBtn = getStoreDefaultsButton(busNum)
    if storeBtn then
      storeBtn.values.x = 0
    end
    debugLaunchpad(string.format("bus %d click+release store defaults", busNum))
  elseif busUndoPress[busNum] then
    busUndoPress[busNum] = nil
    local recallBtn = getRecallDefaultsButton(busNum)
    if recallBtn then
      recallBtn.values.x = 0
    end
    debugLaunchpad(string.format("bus %d undo+release recall defaults", busNum))
  elseif busGrabPress[busNum] then
    busGrabPress[busNum] = nil
    onOff:notify("set_grab_state", false)
    refreshBusButtonLED(busNum)
    debugLaunchpad(string.format("bus %d shift+grab off", busNum))
  end
end

local function handleLaunchpadControlChange(cc, ccValue)
  if cc == QUANTISE_CC then
    launchpadQuantiseHeld = ccValue > 63
    syncLaunchpadModifierTags()
    local qr, qg, qb = launchpadQuantiseRgb(launchpadQuantiseHeld and LAUNCHPAD_ON_BRIGHTNESS or LAUNCHPAD_IDLE_BRIGHTNESS)
    sendLaunchpadLedRgb(QUANTISE_CC, qr, qg, qb)
    debugLaunchpad(string.format("quantise %s", launchpadQuantiseHeld and "on" or "off"))
    return true
  end

  if cc == SHIFT_CC then
    launchpadShiftHeld = ccValue > 63
    syncLaunchpadModifierTags()
    local sr, sg, sb = launchpadShiftRgb(launchpadShiftHeld and LAUNCHPAD_ON_BRIGHTNESS or LAUNCHPAD_IDLE_BRIGHTNESS)
    sendLaunchpadLedRgb(SHIFT_CC, sr, sg, sb)
    debugLaunchpad(string.format("shift %s", launchpadShiftHeld and "on" or "off"))
    return true
  end

  if cc == CLICK_CC then
    launchpadClickHeld = ccValue > 63
    local cr, cg, cb = launchpadClickRgb(launchpadClickHeld and LAUNCHPAD_ON_BRIGHTNESS or LAUNCHPAD_IDLE_BRIGHTNESS)
    sendLaunchpadLedRgb(CLICK_CC, cr, cg, cb)
    debugLaunchpad(string.format("click %s", launchpadClickHeld and "on" or "off"))
    return true
  end

  if cc == UNDO_CC then
    launchpadUndoHeld = ccValue > 63
    local ur, ug, ub = launchpadUndoRgb(launchpadUndoHeld and LAUNCHPAD_ON_BRIGHTNESS or LAUNCHPAD_IDLE_BRIGHTNESS)
    sendLaunchpadLedRgb(UNDO_CC, ur, ug, ub)
    debugLaunchpad(string.format("undo %s", launchpadUndoHeld and "on" or "off"))
    return true
  end

  if cc == DELETE_CC then
    setLaunchpadDeleteMode(ccValue > 63)
    return true
  end

  local lockBus = lockCcToBusNum(cc)
  if lockBus and ccValue > 63 then
    setBusLocked(lockBus, not isBusLocked(lockBus))
    debugLaunchpad(string.format("bus %d lock -> %s", lockBus, tostring(isBusLocked(lockBus))))
    return true
  end

  local busNum = busCcToBusNum(cc)
  if busNum then
    handleLaunchpadBusCc(busNum, ccValue > 63)
    return true
  end

  return false
end

function onReceiveNotify(key, value)
  if key == "apply_bus_theme" then
    local busNum = value
    if busNum then
      applyBusGroupTheme(busNum)
    end
  elseif key == "launchpad_bus_led_refresh" then
    if value then
      refreshBusButtonLED(value)
    else
      refreshAllBusButtonLEDs()
    end
  elseif key == "set_bus_locked" then
    if type(value) == "table" then
      local busNum = value[1]
      local locked = value[2] == true
      if busNum then
        setBusLocked(busNum, locked)
      end
    end
  end
end

local function midiFromLaunchpad(connections)
  if type(connections) ~= 'table' then
    return true
  end
  return connections[3] == true
end

local function midiFromBcr(connections)
  if type(connections) ~= 'table' then
    return false
  end
  return connections[2] == true
end

-- BCR CC per fader group name "1"–"6" (must match control_mapper.lua BCR_ENCODER_CC).
local BCR_ENCODER_CC = { 81, 89, 97, 82, 90, 98 }
local BCR_CC_TO_SLOT = {}
for slot, cc in ipairs(BCR_ENCODER_CC) do
  BCR_CC_TO_SLOT[cc] = slot
end

local BCR_MIDI_DEBUG = false

local function connectionsToString(connections)
  if type(connections) ~= "table" then
    return tostring(connections)
  end
  local parts = {}
  for i = 1, #connections do
    parts[i] = connections[i] and "1" or "0"
  end
  return table.concat(parts, ",")
end

local function debugBcr(msg)
  if BCR_MIDI_DEBUG then
    print("[BCR]", msg)
  end
end

-- BCR on/off button CCs (must match on_off_button_group.lua).
local BCR_TOGGLE_CC = 65
local BCR_SYNC_CC = 66
local BCR_GRAB_CC = 73
local BCR_MORPH_CC = 74
local BCR_ON_OFF_CC_HANDLERS = {
  [BCR_TOGGLE_CC] = "bcr_toggle",
  [BCR_SYNC_CC] = "bcr_sync",
  [BCR_GRAB_CC] = "bcr_grab",
  [BCR_MORPH_CC] = "bcr_morph",
}

-- Morph amount: top-row encoder CC 1 on each bus perform channel (bus N = ch 5+N).
local MORPH_BCR_AMOUNT_CC = 1

local function busHasPerformVisible(busNum)
  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then
    return false
  end
  local controlGroup = busGroup:findByName("control_group", true)
  return controlGroup and controlGroup.visible
end

local function handleBcrMorphMidi(message)
  local status = message[1]
  local cc = message[2]
  local ccValue = message[3]
  local msgType = status - (status % 16)
  local msgChannel = status % 16

  if msgType ~= MIDIMessageType.CONTROLCHANGE then
    return false
  end

  if cc ~= MORPH_BCR_AMOUNT_CC then
    return false
  end

  local busNum = msgChannel - 4
  if busNum < 1 or busNum > NUM_BUSES then
    return false
  end

  if not busHasPerformVisible(busNum) or not busHasFxLoaded(busNum) or not busMorphEnabled(busNum) then
    debugBcr(string.format("morph skip: bus %d (perform/fx/morph)", busNum))
    return false
  end

  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  local grid = busGroup and busGroup:findByName("preset_grid", true)
  if grid then
    grid:notify("set_morph_amount", { busNum, ccValue, true })
  end
  debugBcr(string.format("morph bus %d amount %d", busNum, ccValue))
  return true
end

local function handleBcrOnOffMidi(message)
  local status = message[1]
  local cc = message[2]
  local ccValue = message[3]
  local msgType = status - (status % 16)
  local msgChannel = status % 16

  if msgType ~= MIDIMessageType.CONTROLCHANGE then
    return false
  end

  local notifyKey = BCR_ON_OFF_CC_HANDLERS[cc]
  if not notifyKey then
    return false
  end

  local busNum = msgChannel - 4
  if busNum < 1 or busNum > NUM_BUSES then
    debugBcr(string.format("on/off skip: ch %d -> bus %d out of range", msgChannel, busNum))
    return false
  end

  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then
    return false
  end

  local onOffGroup = busGroup:findByName("on_off_button_group", true)
  if not onOffGroup then
    return false
  end

  if tonumber(onOffGroup.tag) ~= msgChannel then
    debugBcr(string.format(
      "on/off skip: bus %d tag %s != ch %d",
      busNum, tostring(onOffGroup.tag), msgChannel))
    return false
  end

  debugBcr(string.format("-> bus %d on/off %s val %d", busNum, notifyKey, ccValue))
  onOffGroup:notify(notifyKey, ccValue)
  return true
end

local function handleBcrPerformMidi(message)
  local status = message[1]
  local cc = message[2]
  local ccValue = message[3]
  local msgType = status - (status % 16)
  local msgChannel = status % 16

  if msgType ~= MIDIMessageType.CONTROLCHANGE then
    debugBcr("skip: not CC")
    return false
  end

  local slot = BCR_CC_TO_SLOT[cc]
  if not slot then
    if not BCR_ON_OFF_CC_HANDLERS[cc] then
      debugBcr("skip: cc not a perform encoder")
    end
    return false
  end

  local busNum = msgChannel - 4
  if busNum < 1 or busNum > NUM_BUSES then
    debugBcr(string.format("skip: ch %d -> bus %d out of range", msgChannel, busNum))
    return false
  end

  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then
    debugBcr("skip: bus group not found")
    return false
  end

  local controlGroup = busGroup:findByName("control_group", true)
  if not controlGroup or not controlGroup.visible then
    debugBcr(string.format("skip: bus %d control_group not visible", busNum))
    return false
  end

  local faders = busGroup:findByName("faders", true)
  if not faders then
    debugBcr("skip: faders group not found")
    return false
  end

  local faderGroup = faders:findByName(tostring(slot))
  if not faderGroup or not faderGroup.visible then
    debugBcr(string.format("skip: bus %d slot %d fader not visible", busNum, slot))
    return false
  end

  local controlFader = faderGroup:findByName("control_fader")
  if not controlFader then
    debugBcr("skip: control_fader not found")
    return false
  end

  debugBcr(string.format("-> bus %d slot %d val %d", busNum, slot, ccValue))
  controlFader:notify("set_cc_from_bcr", ccValue)
  return true
end

local function setLaunchpadLayout(layout)
  -- SysEx format: F0h 00h 20h 29h 02h 10h 2Ch <Layout> F7h
  -- Decimal: (240,0,32,41,2,16,44,<Layout>,247)
  -- Layout: 00h=Note, 01h=Drum, 02h=Fader, 03h=Programmer
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x2C, layout, 0xF7 }
  print('setLaunchpadLayout', layout)
  sendMIDI(sysexMessage, LAUNCHPAD_MIDI_CONNECTION)
end

local function oscArgString(arguments, index)
  local arg = arguments and arguments[index]
  if arg == nil then
    return nil
  end
  if type(arg) == "string" then
    return arg
  end
  if type(arg) == "table" and arg.value ~= nil then
    return tostring(arg.value)
  end
  return tostring(arg)
end

-- TouchOSC always invokes root onReceiveOSC first (hidden import group OSC routing is unreliable).
function onReceiveOSC(message, connections)
  local path = message[1]
  if path ~= "/sp404/backup" then
    return false
  end

  local jsonBackup = oscArgString(message[2], 1)
  if not jsonBackup or jsonBackup == "" then
    print("root: /sp404/backup missing string argument")
    return true
  end

  local importGroup = root:findByName("backup_import_group", true)
  if importGroup then
    importGroup:notify("osc_backup_received", jsonBackup)
  else
    print("root: backup_import_group not found")
  end
  return true
end

function onReceiveMIDI(message, connections)
  -- Filter out SysEx messages to avoid processing our own messages
  if message[1] == MIDIMessageType.SYSTEMEXCLUSIVE + 1 then
    return
  end

  if midiFromBcr(connections) then
    debugBcr(string.format(
      "onReceiveMIDI status=%d cc=%d val=%d connections=%s",
      message[1], message[2], message[3], connectionsToString(connections)))
    if handleBcrMorphMidi(message) then
      return
    end
    if handleBcrOnOffMidi(message) then
      return
    end
    if handleBcrPerformMidi(message) then
      return
    end
    return
  end

  if not midiFromLaunchpad(connections) then
    return
  end

  if message[1] == MIDIMessageType.NOTE_ON + noteMidiChannel - 1 then
    local note = message[2]
    local velocity = message[3]

    local sceneNum = sceneNoteToScene[note]
    if sceneNum then
      local sceneGrid = root:findByName("scene_grid", true)
      local pad = sceneGrid and sceneGrid:findByName(tostring(sceneNum))
      if pad then
        if velocity > 0 then
          pad.values.x = 1
        else
          pad.values.x = 0
        end
      end
      return
    end

    local noteIndex = nil
    for i = 1, #presetNoteMap do
      if presetNoteMap[i] == note then
        noteIndex = i
        break
      end
    end

    if noteIndex == nil then
      return
    end

    local presetIndex = noteIndex - 1
    local busIndex = math.floor(presetIndex / PRESETS_PER_BUS)
    local presetNumber = (presetIndex % PRESETS_PER_BUS) + 1

    local presetGridEntry = root:findByName('bus'..tostring(busIndex + 1)..'_group', true):findByName('preset_grid', true).children[tostring(presetNumber)]

    if velocity > 0 then
      local tag = json.toTable(root.tag) or {}
      tag.launchpadLastNoteVelocity = velocity
      root.tag = json.fromTable(tag)
      presetGridEntry.values.x = 1
    else
      presetGridEntry.values.x = 0
    end
  elseif message[1] == MIDIMessageType.POLYPRESSURE + noteMidiChannel - 1 then
    local note = message[2]
    local pressure = message[3]
    if sceneNoteToScene[note] then
      return
    end
    local busNum, presetNum = presetNoteToBusPreset(note)
    if busNum and busMorphEnabled(busNum) then
      notifyPresetGridManager("morph_pressure", { busNum, presetNum, pressure })
    end
  elseif message[1] == MIDIMessageType.CONTROLCHANGE + noteMidiChannel - 1 then
    handleLaunchpadControlChange(message[2], message[3])
  end
end

-- Defer one frame so layout init() handlers on bus groups are ready before startup MIDI sync.
local pendingStartupMidiSync = true

function update()
  if not pendingStartupMidiSync then
    return
  end
  pendingStartupMidiSync = false
  for busNum = 1, NUM_BUSES do
    local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
    if busGroup then
      local onOff = busGroup:findByName("on_off_button_group", true)
      if onOff then
        onOff:notify("sync_current_bus")
      end
    end
  end
  refreshAllBusButtonLEDs()
  refreshAllLockButtonLEDs()
  print("startup: sync_all_buses_midi")
end

function init()
  syncBusAccentRootTag()
  for busNum = 1, 5 do
    applyBusGroupTheme(busNum)
  end

  setLaunchpadLayout(0x03)
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0E, 0x00, 0xF7 }
  print('sendSysexAllPadsOff')
  sendMIDI(sysexMessage, LAUNCHPAD_MIDI_CONNECTION)
  setLaunchpadDeleteMode(false)
  setLaunchpadGrabMode(false)
  launchpadQuantiseHeld = false
  syncLaunchpadModifierTags()
  do
    local ur, ug, ub = launchpadUndoRgb(LAUNCHPAD_IDLE_BRIGHTNESS)
    sendLaunchpadLedRgb(UNDO_CC, ur, ug, ub)
    local cr, cg, cb = launchpadClickRgb(LAUNCHPAD_IDLE_BRIGHTNESS)
    sendLaunchpadLedRgb(CLICK_CC, cr, cg, cb)
    local sr, sg, sb = launchpadShiftRgb(LAUNCHPAD_IDLE_BRIGHTNESS)
    sendLaunchpadLedRgb(SHIFT_CC, sr, sg, sb)
    local qr, qg, qb = launchpadQuantiseRgb(LAUNCHPAD_IDLE_BRIGHTNESS)
    sendLaunchpadLedRgb(QUANTISE_CC, qr, qg, qb)
  end
  refreshAllBusButtonLEDs()
  do
    local locks = readBusLockTable()
    for busNum = 1, NUM_BUSES do
      local locked = locks[tostring(busNum)] == true
      syncBusLockUi(busNum, locked)
      refreshLockButtonLED(busNum)
    end
  end
  if root.children.scene_manager then
    root.children.scene_manager:notify("refresh_all_scenes")
  end
end
