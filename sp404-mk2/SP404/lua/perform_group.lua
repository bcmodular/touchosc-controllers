local function initialiseEffectChoosers()
  local effectChoosers = self:findAllByName('effect_chooser')
  for _, effectChooser in ipairs(effectChoosers) do
    effectChooser:notify('init_effect_chooser')
  end
end

---@diagnostic disable: lowercase-global
function onReceiveNotify(key, value)
  if key == 'show' then
    self.visible = true
    initialiseEffectChoosers()
  elseif key == 'hide' then
    self.visible = false
  end
end

function init()
  self.visible = true
  initialiseEffectChoosers()
end