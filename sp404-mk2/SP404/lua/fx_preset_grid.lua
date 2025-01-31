local BUTTON_STATE = {
  STORE = 1,
  RECALL = 2,
  DELETE = 3,
  DISABLED = 4
}

local BUTTON_STATE_COLORS = {
  STORE = "FFFFFFFF",
  RECALL = "00FF00FF",
  DELETE = "FF0000FF",
  DISABLED = "000000FF"
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
  if (key == 'x' and self.values.x == 1 and self.name ~= 'fx_preset_grid') then
    
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
  
  elseif key == 'toggle_delete_buttons' then
    
    local newState = 'DISABLED'
    
    if value == 0 then
      newState = 'DELETE'
    end

    local childCount = #self.children
    local halfCount = childCount / 2

    for index = halfCount + 1, childCount do
      changeState(self.children[index], newState)
    end

    local numLabels = self.parent.children.fx_preset_num_labels
    local delLabels = self.parent.children.fx_preset_delete_labels
    local removeLabel = self.parent.children.remove_fx_preset_label
    local removeAllButton = self.parent.children.remove_all_fx_presets_button
    
    if newState == 'DELETE' then
        self.frame.h = 106
        numLabels.frame.h = 58
        delLabels.visible = true
        removeLabel.visible = true
        removeAllButton.visible = true

        for index = 1, halfCount do
          numLabels.children[index].frame.h = 58
          self.children[index].frame.h = 54
          self.children[index + 16].visible = true
        end
    else
        self.frame.h = 212
        numLabels.frame.h = 116
        delLabels.visible = false
        removeLabel.visible = false
        removeAllButton.visible = false

        for index = 1, halfCount do
          numLabels.children[index].frame.h = 104
          self.children[index].frame.h = 100
          self.children[index + 16].visible = false
        end
    end

  elseif key == 'stored_presets_list' and self.name == 'fx_preset_grid' then
    
    -- Handle the response to our initialisation request
    local storedPresets = value

    local childCount = #self.children
    local halfCount = childCount / 2

    print('childCount:', childCount, 'halfCount:', halfCount)
    print('storedPresets:', unpack(storedPresets))
    
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