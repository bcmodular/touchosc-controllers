local function resetAllChooseButtons()
  for _, btn in ipairs(root:findAllByName("choose_button", true)) do
    btn.values.x = 0
  end
end

local function hideSelector()
  self.visible = false
  resetAllChooseButtons()
  local selectorButtons = self:findByName("fx_selector_button_group")
  if selectorButtons then
    selectorButtons:notify("midi_reset")
  end
end

local function showSelector(busNum)
  local selectorLabel = self:findByName("fx_selector_label")
  local selectorButtons = self:findByName("fx_selector_button_group")
  if not selectorLabel or not selectorButtons then
    return
  end
  selectorLabel.values.text = "Choose FX for Bus " .. tostring(busNum)
  selectorButtons.tag = tostring(busNum)
  selectorButtons:notify("setup_ui")
  self.visible = true
end

function onReceiveNotify(key, value)
  if key == "show" then
    showSelector(value)
  elseif key == "toggle_visibility" then
    if self.visible == true then
      hideSelector()
    else
      showSelector(value)
    end
  elseif key == "hide" then
    hideSelector()
  end
end
