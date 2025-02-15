-- Index into the Root preset array for this FX
local fxNum = 0
local midiChannel = 0
local defaultCCValues = {0, 0, 0, 0, 0, 0}

local presetManager = root.children.preset_manager
local midiHandler = root.children.midi_handler
local fxPresetSelectorGroup = root.children.fx_preset_selector_group
local fxPresetGrid = fxPresetSelectorGroup.children.fx_preset_grid
local controlsInfo = root.children.controls_info

function floatToMIDI(floatValue)
  local midiValue = math.floor(floatValue * 127 + 0.5)
  return midiValue
end

function storeFXPreset(presetNum)
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

  local presetIndex = tostring(fxNum)..' '..tostring(presetNum)
  print('Preset Index:', presetIndex)

  presetManager:notify('store_preset', {presetIndex, ccValues})

end

function onReceiveNotify(key, value)

  print('Action requested:', key, value)
      
  if (key == 'change_fx') then
    
    fxNum = value
    
    -- Do all the things that need to happen when the FX changes
    -- Trigger an initialisation of the button state
    presetManager:notify('stored_presets_list', {fxPresetGrid, fxNum})

  elseif key == 'channel' then
  
    midiChannel = value
  
  elseif key == 'delete' then
    
    local index = tostring(fxNum)..' '..tostring(value)
    presetManager:notify('delete_preset', index)
  
  elseif key == 'delete_all' then
    
    local numPresets = #fxPresetGrid.children / 2
    for x = 1, numPresets do
    
      local index = tostring(fxNum)..' '..tostring(x)
      presetManager:notify('delete_preset', index)

    end
      
    -- Trigger an initialisation of the button state
    presetManager:notify('stored_presets_list', {fxPresetGrid, fxNum})
    
  elseif key == 'store' then
    
    local index = value
    storeFXPreset(index)

  elseif key == 'recall' then
    
    print('fx_preset_handler received recall notification for preset:', value)
    
    local index = tostring(fxNum)..' '..tostring(value)
    presetManager:notify('recall_preset', {midiChannel, index})
  
  end
end