-- Global performance scenes (16 slots): all buses FX + on/off + faders (+ sync state).
-- Storage: scene_manager children "01".."16" (label tags). UI: scene_grid pads 1..16.
-- Scene Launchpad notes: launchpadSceneNote() in launchpad_led.lua (cols 7–8, scene 1 at top).

local NUM_SCENES = 16
local NUM_BUSES = 5
local defaultCCValues = { 0, 0, 0, 0, 0, 0 }

local deleteMode = false
local activeSceneGrab = nil

local SCENE_GRAB_TAG_KEY = "sceneGrabRestore"

local BUTTON_STATE_COLORS = {
  AVAILABLE = "8D8D8AFF",
  STORED = "FFFFFFFF",
  DELETE = "FF0000FF",
}

local SCENE_STATE = {
  AVAILABLE = "available",
  STORED = "stored",
  DELETE = "delete",
}

local sceneStates = {}

local controlsInfo = root.children.controls_info
local recentValues = root.children.recent_values

local function formatSceneNum(num)
  return string.format("%02d", num)
end

local function midiToFloat(midiValue)
  return midiValue / 127
end

local function floatToMIDI(floatValue)
  return math.floor(floatValue * 127 + 0.5)
end

local function ccFromBusState(busState, index)
  local cc = busState.cc
  if not cc then
    return nil
  end
  return tonumber(cc[index] or cc[tostring(index)])
end

local function syncFromBusState(busState, index)
  local sync = busState.sync
  if not sync then
    return nil
  end
  return tonumber(sync[index] or sync[tostring(index)])
end

local function getSceneGrid()
  return root:findByName("scene_grid", true)
end

local function getStorageNode(sceneNum)
  return self.children[formatSceneNum(sceneNum)]
end

local function loadSceneData(sceneNum)
  local node = getStorageNode(sceneNum)
  if not node or node.tag == "" then
    return nil
  end
  return json.toTable(node.tag)
end

local function saveSceneData(sceneNum, data)
  local node = getStorageNode(sceneNum)
  if node then
    if data then
      node.tag = json.fromTable(data)
    else
      node.tag = ""
    end
  end
end

local function getSceneButton(sceneNum)
  local grid = getSceneGrid()
  if not grid then
    return nil
  end
  return grid:findByName(tostring(sceneNum))
end

local function getSceneBackButton(sceneNum)
  local grid = getSceneGrid()
  if not grid then
    return nil
  end
  return grid:findByName("back_" .. tostring(sceneNum))
end

local function setSceneState(sceneNum, state)
  sceneStates[sceneNum] = state
end

local function getSceneState(sceneNum)
  return sceneStates[sceneNum] or SCENE_STATE.AVAILABLE
end

local function scaleHexColor(hex, factor)
  local c = Color.fromHexString(hex)
  local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
  end
  local function to255(v)
    return math.floor(clamp01(v) * 255 + 0.5)
  end
  local r = to255(c.r * factor)
  local g = to255(c.g * factor)
  local b = to255(c.b * factor)
  local a = to255(c.a)
  return string.format("%02X%02X%02X%02X", r, g, b, a)
end

local function renderSceneCell(sceneNum, state, isPressed)
  local button = getSceneButton(sceneNum)
  if not button then
    return
  end
  local baseHex = BUTTON_STATE_COLORS.AVAILABLE
  if state == SCENE_STATE.STORED then
    baseHex = BUTTON_STATE_COLORS.STORED
  elseif state == SCENE_STATE.DELETE then
    baseHex = BUTTON_STATE_COLORS.DELETE
  end
  local factor = isPressed and 1.0 or 0.75

  local back = getSceneBackButton(sceneNum)
  if back then
    back.interactive = false
    back.values.x = 1
    back.color = Color.fromHexString(scaleHexColor(baseHex, factor))
    button.background = false
    button.color = Color.fromHexString("00000000")
  else
    button.background = true
    button.color = Color.fromHexString(scaleHexColor(baseHex, factor))
  end
end

local function isStoredSceneButton(sceneNum)
  return getSceneState(sceneNum) == SCENE_STATE.STORED
end

local function refreshSceneMidiLed(sceneNum)
  local note = launchpadSceneNote(sceneNum)
  if not note then
    return
  end

  local state = getSceneState(sceneNum)
  local r, g, b

  if state == SCENE_STATE.DELETE then
    r, g, b = launchpadDeleteRgb(launchpadIdleBrightness())
  elseif state == SCENE_STATE.STORED then
    r, g, b = launchpadSceneRgb(launchpadIdleBrightness())
  else
    sendLaunchpadLedOff(note)
    return
  end

  sendLaunchpadLedRgb(note, r, g, b)
end

local function refreshAllSceneMidiLeds()
  for sceneNum = 1, NUM_SCENES do
    refreshSceneMidiLed(sceneNum)
  end
end

local function refreshSceneButton(sceneNum)
  local state = SCENE_STATE.AVAILABLE
  if loadSceneData(sceneNum) then
    state = deleteMode and SCENE_STATE.DELETE or SCENE_STATE.STORED
  end
  setSceneState(sceneNum, state)
  renderSceneCell(sceneNum, state)
end

local function refreshAllSceneButtons()
  for sceneNum = 1, NUM_SCENES do
    refreshSceneButton(sceneNum)
  end
  refreshAllSceneMidiLeds()
end

local function getBusGroup(busNum)
  return root:findByName("bus" .. tostring(busNum) .. "_group", true)
end

local function captureBusState(busNum)
  local busGroup = getBusGroup(busNum)
  if not busGroup then
    return nil
  end

  local settings = json.toTable(busGroup.tag) or {}
  local fxNum = tonumber(settings.fxNum) or 0
  local busState = {
    fxNum = fxNum,
    on = false,
    cc = { unpack(defaultCCValues) },
    sync = { 0, 0, 0, 0, 0, 0 },
  }

  if fxNum == 0 then
    return busState
  end

  local onOff = busGroup:findByName("on_off_button_group", true)
  local toggle = onOff and onOff:findByName("toggle_button", true)
  if toggle then
    busState.on = toggle.values.x == 1
  end

  local faders = busGroup:findByName("faders", true)
  if faders then
    for i = 1, 6 do
      local faderGroup = faders:findByName(tostring(i))
      if faderGroup then
        local controlFader = faderGroup:findByName("control_fader")
        if controlFader then
          busState.cc[i] = floatToMIDI(controlFader.values.x)
        end
        local syncButton = faderGroup:findByName("sync_button", true)
        if syncButton then
          busState.sync[i] = syncButton.values.x
        end
      end
    end
  end

  return busState
end

local function captureGlobalState()
  local buses = {}
  for busNum = 1, NUM_BUSES do
    buses[tostring(busNum)] = captureBusState(busNum)
  end
  return { buses = buses }
end

local function applyBusFadersAndSync(busNum, busState)
  if busState.fxNum == 0 then
    return
  end

  local busGroup = getBusGroup(busNum)
  if not busGroup then
    return
  end

  local faders = busGroup:findByName("faders", true)
  if not faders then
    return
  end

  local controlInfoArray = json.toTable(controlsInfo.children[tostring(busState.fxNum)].tag)
  if not controlInfoArray then
    return
  end

  for i, controlInfo in ipairs(controlInfoArray) do
    local faderGroup = faders:findByName(tostring(i))
    if faderGroup then
      local ccVal = ccFromBusState(busState, i)
      if ccVal ~= nil then
        local controlFader = faderGroup:findByName("control_fader")
        if controlFader then
          controlFader:notify("new_value", midiToFloat(ccVal))
        end
      end

      local syncVal = syncFromBusState(busState, i)
      if syncVal ~= nil then
        local syncButton = faderGroup:findByName("sync_button", true)
        if syncButton then
          syncButton.values.x = syncVal
        end
        local _, faderName = unpack(controlInfo)
        if faderName == "sync_fader" then
          local controlFader = faderGroup:findByName("control_fader")
          if controlFader then
            controlFader:notify("sync_toggle", syncVal == 1)
          end
        end
      end
    end
  end
end

local function applyBusOnOff(busNum, busState)
  if busState.fxNum == 0 then
    return
  end

  local busGroup = getBusGroup(busNum)
  local onOff = busGroup and busGroup:findByName("on_off_button_group", true)
  if not onOff then
    return
  end

  local toggle = onOff:findByName("toggle_button", true)
  local wantOn = busState.on and true or false
  if toggle then
    toggle.values.x = wantOn and 1 or 0
  end
  onOff:notify("set_state", wantOn)
end

local function syncBusMidiToDevice(busNum, busState)
  if busState.fxNum == 0 then
    return
  end
  local busGroup = getBusGroup(busNum)
  local onOff = busGroup and busGroup:findByName("on_off_button_group", true)
  if onOff then
    onOff:notify("sync_current_bus")
  end
end

local function refreshBusPresets(busNum, fxNum)
  local busGroup = getBusGroup(busNum)
  local presetGrid = busGroup and busGroup:findByName("preset_grid", true)
  if presetGrid and fxNum and fxNum ~= 0 then
    presetGrid:notify("refresh_presets_list", fxNum)
  end
end

local function updateRecentForBus(busNum, busState)
  if busState.fxNum == 0 or not recentValues then
    return
  end
  recentValues:notify("update_recent_values", { busNum, busState.fxNum, busState.cc })
end

local function recallBusFx(busNum, busState)
  local busGroup = getBusGroup(busNum)
  if not busGroup then
    return
  end

  if busState.fxNum == 0 then
    busGroup:notify("clear_bus")
    return
  end

  local fxName = EFFECT_NAMES[busState.fxNum]
  if not fxName then
    return
  end
  -- sceneLoad=true: skip recent-value recall; scene_manager applies CC/on-off + MIDI sync.
  busGroup:notify("set_fx", { busState.fxNum, fxName, false, true })
end

local function loadSceneGrabSnapshot()
  local tag = json.toTable(root.tag) or {}
  local data = tag[SCENE_GRAB_TAG_KEY]
  if type(data) == "table" and data.buses then
    return data
  end
  return nil
end

local function saveSceneGrabSnapshot(data)
  local tag = json.toTable(root.tag) or {}
  tag[SCENE_GRAB_TAG_KEY] = data
  root.tag = json.fromTable(tag)
end

local function clearSceneGrabSnapshot()
  local tag = json.toTable(root.tag) or {}
  tag[SCENE_GRAB_TAG_KEY] = nil
  root.tag = json.fromTable(tag)
end

local function applyGlobalState(data, options)
  if not data or not data.buses then
    return
  end

  local skipLockedBuses = options and options.skipLockedBuses == true

  for busNum = 1, NUM_BUSES do
    if skipLockedBuses and isBusLocked(busNum) then
      -- skip
    else
    local busState = data.buses[tostring(busNum)]
    if busState then
      recallBusFx(busNum, busState)
      applyBusFadersAndSync(busNum, busState)
      applyBusOnOff(busNum, busState)
      syncBusMidiToDevice(busNum, busState)
      updateRecentForBus(busNum, busState)
      refreshBusPresets(busNum, busState.fxNum)
    end
    end
  end

  local fxSelector = root:findByName("fx_selector_group", true)
  if fxSelector then
    fxSelector:notify("hide")
  end
end

local function recallScene(sceneNum)
  local data = loadSceneData(sceneNum)
  if not data then
    return
  end
  applyGlobalState(data, { skipLockedBuses = true })
end

local function endSceneGrab()
  local snapshot = loadSceneGrabSnapshot()
  if snapshot then
    applyGlobalState(snapshot, { skipLockedBuses = true })
  end
  clearSceneGrabSnapshot()
  activeSceneGrab = nil
end

local function beginSceneGrab(sceneNum)
  if not isStoredSceneButton(sceneNum) then
    return
  end
  if loadSceneGrabSnapshot() == nil then
    saveSceneGrabSnapshot(captureGlobalState())
  end
  activeSceneGrab = sceneNum
  recallScene(sceneNum)
end

local function handleSceneGrabPad(sceneNum, isPressed)
  if isPressed then
    beginSceneGrab(sceneNum)
  elseif activeSceneGrab == sceneNum then
    endSceneGrab()
  end
end

local function storeScene(sceneNum, delete)
  if delete or deleteMode then
    saveSceneData(sceneNum, nil)
  else
    saveSceneData(sceneNum, captureGlobalState())
  end
  refreshSceneButton(sceneNum)
  refreshSceneMidiLed(sceneNum)
end

local function updateSceneMidiPressHighlight(sceneNum, isPressed)
  local note = launchpadSceneNote(sceneNum)
  if not note then
    return
  end

  local state = getSceneState(sceneNum)
  local r, g, b

  if state == SCENE_STATE.DELETE then
    if not isPressed then
      return
    end
    r, g, b = launchpadDeleteRgb(launchpadOnBrightness())
  elseif state == SCENE_STATE.STORED then
    local brightness = isPressed and launchpadOnBrightness() or launchpadIdleBrightness()
    r, g, b = launchpadSceneRgb(brightness)
  elseif state == SCENE_STATE.AVAILABLE then
    if isPressed then
      r, g, b = launchpadSceneRgb(launchpadEmptyPressBrightness())
    else
      sendLaunchpadLedOff(note)
      return
    end
  end

  if r then
    sendLaunchpadLedRgb(note, r, g, b)
  end
end

local function sceneButtonPressed(sceneNum)
  local state = getSceneState(sceneNum)
  if state == SCENE_STATE.DELETE then
    storeScene(sceneNum, true)
  elseif state == SCENE_STATE.STORED then
    recallScene(sceneNum)
  else
    storeScene(sceneNum, false)
  end
end

local function toggleDeleteMode(value)
  deleteMode = value
  if value then
    endSceneGrab()
  end
  refreshAllSceneButtons()
end

function onReceiveNotify(key, value)
  if key == "toggle_delete_mode" then
    toggleDeleteMode(value)
  elseif key == "button_value_changed" then
    if type(value) ~= "table" then
      return
    end
    local sceneNum = value[1]
    local isPressed = value[2] == 1
    local shiftHeld = value[3] == true

    if not sceneNum then
      return
    end

    local sceneState = getSceneState(sceneNum)
    renderSceneCell(sceneNum, sceneState, isPressed)
    updateSceneMidiPressHighlight(sceneNum, isPressed)

    if deleteMode then
      if isPressed then
        sceneButtonPressed(sceneNum)
      end
      return
    end

    if shiftHeld then
      handleSceneGrabPad(sceneNum, isPressed)
      return
    end

    if isPressed then
      sceneButtonPressed(sceneNum)
    end
  elseif key == "refresh_all_scenes" then
    refreshAllSceneButtons()
  end
end

function init()
  for i = 1, NUM_SCENES do
    local name = formatSceneNum(i)
    local child = self.children[name]
    if child and (not child.script or child.script == "") then
      child.script = "function onValueChanged(key, value) end"
    end
  end
  refreshAllSceneButtons()
end
