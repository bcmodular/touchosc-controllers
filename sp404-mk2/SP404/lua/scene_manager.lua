-- Global performance scenes (16 slots): all buses FX + on/off + faders (+ sync state).
-- Storage: scene_manager children "01".."16" (label tags). UI: scene_grid pads 1..16.
-- Scene Launchpad notes: launchpadSceneNote() in launchpad_led.lua (cols 7–8, scene 1 at top).

local NUM_SCENES = 16
local NUM_BUSES = 5
local defaultCCValues = { 0, 0, 0, 0, 0, 0 }

local deleteMode = false

local BUTTON_STATE_COLORS = {
  AVAILABLE = "8D8D8AFF",
  STORED = "FFFFFFFF",
  DELETE = "FF0000FF",
}

local SCENE_LED_EMPTY_PRESS_BRIGHTNESS = 0.35

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

local function isStoredSceneButton(sceneNum)
  local button = getSceneButton(sceneNum)
  if not button then
    return false
  end
  return Color.toHexString(button.color) == BUTTON_STATE_COLORS.STORED
end

local function refreshSceneMidiLed(sceneNum)
  local note = launchpadSceneNote(sceneNum)
  if not note then
    return
  end

  local button = getSceneButton(sceneNum)
  if not button then
    return
  end

  local buttonColor = Color.toHexString(button.color)
  local r, g, b

  if buttonColor == BUTTON_STATE_COLORS.DELETE then
    r, g, b = launchpadDeleteRgb(LAUNCHPAD_IDLE_BRIGHTNESS)
  elseif buttonColor == BUTTON_STATE_COLORS.STORED then
    r, g, b = launchpadSceneRgb(LAUNCHPAD_IDLE_BRIGHTNESS)
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
  local button = getSceneButton(sceneNum)
  if not button then
    return
  end

  if loadSceneData(sceneNum) then
    button.color = deleteMode and BUTTON_STATE_COLORS.DELETE or BUTTON_STATE_COLORS.STORED
  else
    button.color = BUTTON_STATE_COLORS.AVAILABLE
  end
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

local function recallScene(sceneNum)
  local data = loadSceneData(sceneNum)
  if not data or not data.buses then
    return
  end

  -- Per bus: init FX → apply scene CC/sync → on/off → push all CCs to SP-404.
  for busNum = 1, NUM_BUSES do
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

  local fxSelector = root:findByName("fx_selector_group", true)
  if fxSelector then
    fxSelector:notify("hide")
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

  local button = getSceneButton(sceneNum)
  if not button then
    return
  end

  local buttonColor = Color.toHexString(button.color)
  local r, g, b

  if buttonColor == BUTTON_STATE_COLORS.DELETE then
    if not isPressed then
      return
    end
    r, g, b = launchpadDeleteRgb(LAUNCHPAD_ON_BRIGHTNESS)
  elseif buttonColor == BUTTON_STATE_COLORS.STORED then
    local brightness = isPressed and LAUNCHPAD_ON_BRIGHTNESS or LAUNCHPAD_IDLE_BRIGHTNESS
    r, g, b = launchpadSceneRgb(brightness)
  elseif buttonColor == BUTTON_STATE_COLORS.AVAILABLE then
    if isPressed then
      r, g, b = launchpadSceneRgb(SCENE_LED_EMPTY_PRESS_BRIGHTNESS)
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
  local button = getSceneButton(sceneNum)
  if not button then
    return
  end

  local buttonColor = Color.toHexString(button.color)

  if buttonColor == BUTTON_STATE_COLORS.DELETE then
    storeScene(sceneNum, true)
  elseif buttonColor == BUTTON_STATE_COLORS.STORED then
    recallScene(sceneNum)
  else
    storeScene(sceneNum, false)
  end
end

local function toggleDeleteMode(value)
  deleteMode = value
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

    updateSceneMidiPressHighlight(sceneNum, isPressed)

    if shiftHeld and isStoredSceneButton(sceneNum) then
      return
    end

    if deleteMode then
      if isPressed then
        sceneButtonPressed(sceneNum)
      end
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
