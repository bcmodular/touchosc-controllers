local BUTTON_STATE = {
    RECALL = 1,
    DISABLED = 2
  }

local BUTTON_STATE_COLORS = {
  RECALL = "00FF00FF",
  DISABLED = "000000FF"
}

local function changeState(child, newState)
  print('Changing state of', child.index, 'to:', BUTTON_STATE[newState])
  child.name = BUTTON_STATE[newState]
  child.color = BUTTON_STATE_COLORS[newState]
end

---@diagnostic disable: lowercase-global
  function onValueChanged(key, value)

  -- Interpret button presses as a child button
  if (key == 'x' and self.values.x == 1 and self.name ~= 'perform_preset_grid') then

    local buttonState = tonumber(self.name) or 0
    print('button state:', buttonState)

    if (buttonState == BUTTON_STATE.RECALL) then
      local performPresetHandler = self.parent.parent:findByName('perform_preset_handler')
      performPresetHandler:notify('recall', self.index)
    end
  end
end

function onReceiveNotify(key, value)

  if key == 'init_presets_list' and self.name == 'perform_preset_grid' then
    -- Handle the response to our initialisation request
    local effectChooser = self.parent.parent:findByName('effect_chooser')
    local fxNum = effectChooser.tag
    local presetManager = root.children.preset_manager
    local presetArray = json.toTable(presetManager.children[tostring(fxNum)].tag) or {}
    print('presetArray:', table.unpack(presetArray), 'fxNum:', fxNum)

    local childCount = #self.children

    print('storedPresets:', table.unpack(presetArray))

    -- Initialise the entries first
    for index = 1, childCount do
      changeState(self.children[index], 'DISABLED')
    end

    for index, preset in pairs(presetArray) do
      --print('Setting state for:', tonumber(index), 'to:', preset)
      if preset then
        changeState(self.children[tonumber(index)], 'RECALL')
      end
    end
  end

end

  function init()
    if self.name == 'perform_preset_grid' then
      self.outline = true
      self.outlineStyle = OutlineStyle.FULL
    end
  end