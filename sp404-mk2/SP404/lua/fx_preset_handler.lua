-- Index into the Root preset array for this FX
local fxNum = 0

local presetManager = root.children.preset_manager
local midiHandler = root.children.midi_handler
local fxPresetSelectorGroup = root.children.fx_preset_selector_group
local fxPresetGrid = fxPresetSelectorGroup.children.fx_preset_grid

function init()
  fxPresetGrid.outline = true
  fxPresetGrid.outlineStyle = OutlineStyle.FULL
end

function onReceiveNotify(key, value)

  print('Action requested:', key, value)
      
  if (key == 'change_fx') then
    
    fxNum = value
    midiHandler:notify('change_fx', fxNum)
    
    -- Do all the things that need to happen when the FX changes
    -- Trigger an initialisation of the button state
    presetManager:notify('stored_presets_list', {fxPresetGrid, fxNum})

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
    midiHandler:notify('store_fx_preset', index)

  elseif key == 'recall' then
    
    local index = tostring(fxNum)..' '..tostring(value)
    local fxPresetHandler = root.children.fx_preset_handler
    presetManager:notify('recall_preset', {midiHandler, index})
  
  end
end