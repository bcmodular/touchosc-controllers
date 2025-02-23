local function initialiseEffectChoosers()
  local effectChoosers = self:findAllByName('effect_chooser', true)
  for _, effectChooser in ipairs(effectChoosers) do
    print('initialising effect chooser', effectChooser.name)
    effectChooser:notify('init_effect_chooser')
  end
end

local function initialisePresetGrids()
  local performPresetGrids = self:findAllByName('perform_preset_grid', true)
  for _, performPresetGrid in ipairs(performPresetGrids) do
    print('initialising preset grid', performPresetGrid.name)
    performPresetGrid:notify('init_presets_list')
  end
end

---@diagnostic disable: lowercase-global
function onReceiveNotify(key, value)
  print('perform_group received notification:', key, value)
  if key == 'show' then
    self.visible = true
    initialiseEffectChoosers()
    initialisePresetGrids()
  elseif key == 'hide' then
    self.visible = false
  end
end

function init()
  self.visible = true
  initialiseEffectChoosers()
end