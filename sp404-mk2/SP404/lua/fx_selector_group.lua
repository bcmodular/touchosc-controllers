local function resetAllChooseButtons()
  for _, btn in ipairs(root:findAllByName("choose_button", true)) do
    btn.values.x = 0
  end
end

local function hideSelector()
  self.visible = false
  resetAllChooseButtons()
end

function onReceiveNotify(key, value)
  if key == "toggle_visibility" then
    if self.visible == true then
      hideSelector()
    else
      local busNum = value
      local selectorLabel = self:findByName("fx_selector_label")
      selectorLabel.values.text = "Choose FX for Bus " .. tostring(busNum)
      local selectorButtons = self:findByName("fx_selector_button_group")
      selectorButtons.tag = tostring(busNum)
      selectorButtons:notify("setup_ui")
      self.visible = true
    end
  elseif key == "hide" then
    hideSelector()
  end
end
