-- Unified backup: presets, scenes, defaults, recent, bus FX selection.
-- OSC: /sp404/backup (export via sendOSC; import via backup_import_group → import_backup_from_osc).

local BACKUP_VERSION = 1
local OSC_PATH = "/sp404/backup"
local NUM_FX = 46
local NUM_SCENES = 16
local NUM_BUSES = 5

local presetManager = root.children.preset_manager
local sceneManager = root.children.scene_manager
local defaultManager = root.children.default_manager
local recentValues = root.children.recent_values

local function getBusGroup(busNum)
  return root:findByName("bus" .. tostring(busNum) .. "_group", true)
end

local function collectPresets()
  local presets = {}
  for fxNum = 1, NUM_FX do
    local key = tostring(fxNum)
    local tag = presetManager.children[key].tag
    if tag and tag ~= "" then
      presets[key] = json.toTable(tag) or {}
    else
      presets[key] = {}
    end
  end
  return presets
end

local function collectScenes()
  local scenes = {}
  for sceneNum = 1, NUM_SCENES do
    local key = string.format("%02d", sceneNum)
    local tag = sceneManager.children[key].tag
    if tag and tag ~= "" then
      scenes[key] = json.toTable(tag) or {}
    else
      scenes[key] = {}
    end
  end
  return scenes
end

local function collectDefaults()
  if defaultManager.tag and defaultManager.tag ~= "" then
    return json.toTable(defaultManager.tag) or {}
  end
  return {}
end

local function collectRecent()
  if recentValues.tag and recentValues.tag ~= "" then
    return json.toTable(recentValues.tag) or {}
  end
  return {}
end

local function collectBuses()
  local buses = {}
  for busNum = 1, NUM_BUSES do
    local key = tostring(busNum)
    local busGroup = getBusGroup(busNum)
    if busGroup and busGroup.tag and busGroup.tag ~= "" then
      buses[key] = json.toTable(busGroup.tag) or {}
    else
      buses[key] = { fxNum = 0, fxName = "Choose FX...", busNum = busNum }
    end
  end
  return buses
end

local function exportBackupToOSC()
  local dump = {
    version = BACKUP_VERSION,
    name = "",
    createdAt = tostring(os.time()),
    presets = collectPresets(),
    scenes = collectScenes(),
    defaults = collectDefaults(),
    recent = collectRecent(),
    buses = collectBuses(),
  }
  sendOSC(OSC_PATH, json.fromTable(dump))
end

local function sectionTable(data, key)
  local section = data[key]
  if type(section) == "table" then
    return section
  end
  return {}
end

local function writePresets(presets)
  for fxNum = 1, NUM_FX do
    local key = tostring(fxNum)
    local presetArray = presets[key] or presets[fxNum]
    if type(presetArray) == "table" and next(presetArray) then
      presetManager.children[key].tag = json.fromTable(presetArray)
    else
      presetManager.children[key].tag = ""
    end
  end
end

local function writeScenes(scenes)
  for sceneNum = 1, NUM_SCENES do
    local key = string.format("%02d", sceneNum)
    local sceneData = scenes[key] or scenes[sceneNum]
    if type(sceneData) == "table" and next(sceneData) then
      sceneManager.children[key].tag = json.fromTable(sceneData)
    else
      sceneManager.children[key].tag = ""
    end
  end
end

local function writeDefaults(defaults)
  defaultManager.tag = json.fromTable(defaults)
end

local function writeRecent(recent)
  recentValues.tag = json.fromTable(recent)
end

local function writeBuses(buses)
  for busNum = 1, NUM_BUSES do
    local key = tostring(busNum)
    local busData = buses[key] or buses[busNum]
    local busGroup = getBusGroup(busNum)
    if busGroup and type(busData) == "table" then
      busData.busNum = busNum
      busGroup.tag = json.fromTable(busData)
      local fxNum = tonumber(busData.fxNum) or 0
      local fxName = busData.fxName or "Choose FX..."
      if fxNum == 0 then
        busGroup:notify("clear_bus")
      else
        busGroup:notify("set_fx", { fxNum, fxName, false })
      end
    end
  end
end

local function turnOffBusEffectsAfterImport(buses)
  -- Backups store FX selection and parameters, not on/off; avoid leaving stale toggle state.
  for busNum = 1, NUM_BUSES do
    local key = tostring(busNum)
    local busData = buses[key] or buses[busNum]
    if type(busData) == "table" then
      local fxNum = tonumber(busData.fxNum) or 0
      if fxNum ~= 0 then
        local busGroup = getBusGroup(busNum)
        local onOff = busGroup and busGroup:findByName("on_off_button_group", true)
        if onOff then
          local toggle = onOff:findByName("toggle_button", true)
          if toggle then
            toggle.values.x = 0
          end
          onOff:notify("set_grab_state", false)
          onOff:notify("set_state", false)
        end
      end
    end
  end
end

local function refreshAfterImport()
  for busNum = 1, NUM_BUSES do
    local busGroup = getBusGroup(busNum)
    if busGroup then
      local settings = json.toTable(busGroup.tag) or {}
      local fxNum = tonumber(settings.fxNum) or 0
      local presetGrid = busGroup:findByName("preset_grid", true)
      if presetGrid then
        presetGrid:notify("refresh_presets_list", fxNum)
      end
    end
  end
  sceneManager:notify("refresh_all_scenes")
end

local function importBackupFromOSC(payload)
  local data = payload
  if type(data) == "string" then
    data = json.toTable(data)
  end
  if type(data) ~= "table" then
    return false
  end
  if tonumber(data.version) ~= BACKUP_VERSION then
    return false
  end

  writePresets(sectionTable(data, "presets"))
  writeScenes(sectionTable(data, "scenes"))
  writeDefaults(sectionTable(data, "defaults"))
  writeRecent(sectionTable(data, "recent"))
  local buses = sectionTable(data, "buses")
  writeBuses(buses)
  turnOffBusEffectsAfterImport(buses)
  refreshAfterImport()
  return true
end

function onReceiveNotify(key, value)
  if key == "export_backup_to_osc" then
    exportBackupToOSC()
  elseif key == "import_backup_from_osc" then
    importBackupFromOSC(value)
  end
end
