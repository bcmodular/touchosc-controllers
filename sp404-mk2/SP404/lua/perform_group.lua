local function initialiseEffectChoosers()
  local effectChoosers = self:findAllByName('effect_chooser', true)
  for _, effectChooser in ipairs(effectChoosers) do
    print('initialising effect chooser', effectChooser.name)
    effectChooser:notify('init_effect_chooser')
  end
end

local function initialisePresetGrids()
  local effectChoosers = self:findAllByName('effect_chooser', true)
  for _, effectChooser in ipairs(effectChoosers) do
    print('initialising preset grid', effectChooser.name)
    effectChooser:notify('init_preset_list')
  end
end

local function hideOtherThanMe(notToHide)

  local effectChoosers = self:findAllByName('effect_chooser', true)

  for _, effectChooser in ipairs(effectChoosers) do
    if effectChooser ~= notToHide then
      print('closing menu for', effectChooser.name)
      effectChooser:notify('closeMenu')
    end
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
  elseif key == 'hide_other_than_me' then
    hideOtherThanMe(value)
  end
end

function init()
  self.visible = true
  initialiseEffectChoosers()
end