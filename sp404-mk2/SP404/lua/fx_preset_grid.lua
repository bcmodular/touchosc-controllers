local BUTTON_STATE = {
  STORE = 1,
  RECALL = 2,
  DELETE = 3
}

local BUTTON_STATE_COLORS = {
  STORE = "FFFFFFFF",
  RECALL = "00FF00FF",
  DELETE = "FF0000FF"
}

local fxPresetHandler = root.children.fx_preset_handler
local excludeMarkedPresets = false

function changeState(child, newState)
  --print('Changing state of', child.index, 'to:', BUTTON_STATE[newState])
  child.name = BUTTON_STATE[newState]
  child.color = BUTTON_STATE_COLORS[newState]
end

function onValueChanged(key, value)
  
  -- Interpret button presses as a child button
  if (key == 'x' and self.values.x == 0 and self.name ~= 'fx_preset_grid') then
    
    local buttonState = tonumber(self.name) or 0
    --print('button state:', buttonState)

    if (buttonState == BUTTON_STATE.DELETE) then
      
      local presetToDelete = self.index - #self.parent.children / 2

      --print('delete button clicked:', tostring(presetToDelete))
      -- A delete button was clicked
      fxPresetHandler:notify('delete', presetToDelete)
      changeState(self.parent.children[presetToDelete], 'STORE')
    
    elseif (buttonState == BUTTON_STATE.STORE) then  
    
      -- A store button was clicked
      fxPresetHandler:notify('store', self.index)
      changeState(self, 'RECALL')
      
    elseif (buttonState == BUTTON_STATE.RECALL) then
    
      -- A recall button was clicked
      fxPresetHandler:notify('recall', self.index)
      
    end
  end
end

function onReceiveNotify(key, value)
  
  if key == 'change_state' then
    local newState = value
    changeState(self, newState)
  
  elseif key == 'stored_presets_list' and self.name == 'fx_preset_grid' then
    
    -- Handle the response to our initialisation request
    local storedPresets = value

    local childCount = #self.children
    local halfCount = childCount / 2

    -- Initialise the entries first
    for index = 1, childCount do
      if index <= halfCount then
        changeState(self.children[index], 'STORE')
      else
        changeState(self.children[index], 'DELETE')
      end
    end

    for index, preset in pairs(storedPresets) do
      --print('Setting state for:', tonumber(index), 'to:', preset)
      if preset then
        changeState(self.children[tonumber(index)], 'RECALL')
      end
    end
  end
  
end