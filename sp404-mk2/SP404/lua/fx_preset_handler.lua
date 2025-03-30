-- Index into the Root preset array for this FX
local fxNum = 1
local fxPresetGrid = nil
local defaultCCValues = {0, 0, 0, 0, 0, 0}

local function floatToMIDI(floatValue)
  local midiValue = math.floor(floatValue * 127 + 0.5)
  return midiValue
end

local function storeFXDefaults()
  local controlsInfo = root.children.controls_info
  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)
  print('controlInfoArray:', controlInfoArray)

  local ccValues = {unpack(defaultCCValues)}

  local fxPage = root.children.control_pager.children[fxNum]
  local controlGroup = fxPage.children.control_group

  for i, controlInfo in ipairs(controlInfoArray) do
    local controlObject = controlGroup:findByName(controlInfo[2], true)
    if controlObject then
      print('Control object:', controlObject.name)
      ccValues[i] = floatToMIDI(controlObject.values.x)
    else
      print('Control object not found:', controlInfo[2])
      ccValues[i] = 0
    end
  end

  print('Current MIDI values:', unpack(ccValues))

  local defaultManager = root.children.default_manager
  defaultManager:notify('store_defaults', {fxNum, ccValues})

end
local function storeFXPreset(presetNum)
  local controlsInfo = root.children.controls_info
  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)
  print('controlInfoArray:', controlInfoArray)

  local ccValues = {unpack(defaultCCValues)}

  local fxPage = root.children.control_pager.children[fxNum]
  local controlGroup = fxPage.children.control_group

  for i, controlInfo in ipairs(controlInfoArray) do
    local controlObject = controlGroup:findByName(controlInfo[2], true)
    if controlObject then
      print('Control object:', controlObject.name)
      ccValues[i] = floatToMIDI(controlObject.values.x)
    else
      print('Control object not found:', controlInfo[2])
      ccValues[i] = 0
    end
  end

  print('Current MIDI values:', unpack(ccValues))

  local presetManager = root.children.preset_manager
  presetManager:notify('store_preset', {fxNum, presetNum, ccValues})

end

local function handleSetSettings(value)
  fxNum = tonumber(value[1]) or 0

  local presetManager = root.children.preset_manager
  presetManager:notify('stored_presets_list', {fxPresetGrid, fxNum})
end

local function handleDelete(value)
  local presetManager = root.children.preset_manager
  presetManager:notify('delete_preset', {fxNum, value})
end

local function handleDeleteAll()
  local presetManager = root.children.preset_manager
  presetManager:notify('delete_all_presets', fxNum)
  presetManager:notify('stored_presets_list', {fxPresetGrid, fxNum})
end

local function handleDeleteAllFX()
  local presetManager = root.children.preset_manager
  presetManager:notify('delete_all_presets_for_all_fx')
  presetManager:notify('stored_presets_list', {fxPresetGrid, fxNum})
end

local function handleRecall(value)
  print('fx_preset_handler received recall notification for preset:', value)
  local recallProxy = root.children.recall_proxy

  recallProxy:notify('recall_preset', value)
end

function onReceiveNotify(key, value)
  if key == 'set_settings' then
    handleSetSettings(value)
  elseif key == 'delete' then
    handleDelete(value)
  elseif key == 'delete_all' then
    handleDeleteAll()
  elseif key == 'delete_all_presets_for_all_fx' then
    handleDeleteAllFX()
  elseif key == 'store' then
    storeFXPreset(value)
  elseif key == 'recall' then
    handleRecall(value)
  elseif key == 'store_defaults' then
    storeFXDefaults()
  end
end

function init()
  fxPresetGrid = root:findByName('fx_preset_grid', true)
end