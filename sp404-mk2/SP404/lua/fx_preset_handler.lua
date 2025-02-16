-- Index into the Root preset array for this FX
local fxNum = 0
local midiChannel = 0
local defaultCCValues = {0, 0, 0, 0, 0, 0}

function floatToMIDI(floatValue)
  local midiValue = math.floor(floatValue * 127 + 0.5)
  return midiValue
end

function storeFXPreset(presetNum)
  local controlsInfo = root.children.controls_info
  local controlInfoArray = json.toTable(controlsInfo.children[fxNum].tag)
  print('controlInfoArray:', controlInfoArray)
  
  local ccValues = {unpack(defaultCCValues)}

  local fxPage = root.children.control_pager.children[fxNum]
  local controlGroup = fxPage.children.control_group

  for i, controlInfo in ipairs(controlInfoArray) do
    local controlObject = controlGroup:findByName(controlInfo[2], true)
    print('Control object:', controlObject.name)
    ccValues[i] = floatToMIDI(controlObject.values.x)
  end

  print('Current MIDI values:', unpack(ccValues))

  local presetManager = root.children.preset_manager
  presetManager:notify('store_preset', {fxNum, presetNum, ccValues})

end

function onReceiveNotify(key, value)

  local fxPresetSelectorGroup = root.children.fx_preset_selector_group
  local fxPresetGrid = fxPresetSelectorGroup.children.fx_preset_grid

  print('Action requested:', key, value)
      
  if (key == 'change_fx') then
    
    fxNum = value
    
    -- Do all the things that need to happen when the FX changes
    -- Trigger an initialisation of the button state
    local presetManager = root.children.preset_manager
    presetManager:notify('stored_presets_list', {fxPresetGrid, fxNum})

  elseif key == 'channel' then
  
    midiChannel = value
  
  elseif key == 'delete' then

    local presetManager = root.children.preset_manager
    presetManager:notify('delete_preset', {fxNum, value})
  
  elseif key == 'delete_all' then
    
    local presetManager = root.children.preset_manager
    presetManager:notify('delete_all_presets', fxNum)

    -- Trigger an initialisation of the button state
    presetManager:notify('stored_presets_list', {fxPresetGrid, fxNum})
    
  elseif key == 'delete_all_presets_for_all_fx' then
    
    local presetManager = root.children.preset_manager
    presetManager:notify('delete_all_presets_for_all_fx')

    -- Trigger an initialisation of the button state
    presetManager:notify('stored_presets_list', {fxPresetGrid, fxNum})
    
  elseif key == 'store' then
    
    local index = value
    storeFXPreset(index)

  elseif key == 'recall' then
    
    print('fx_preset_handler received recall notification for preset:', value)
    local presetManager = root.children.preset_manager
    presetManager:notify('recall_preset', {midiChannel, fxNum, value})
  
  end
end