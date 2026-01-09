function onReceiveNotify(key, value)
  if key == 'toggle_visibility' then

    if self.visible == true then
      self.visible = false
    else

      local busNum = value

      local selectorLabel = self:findByName('fx_selector_label')
      selectorLabel.values.text = 'Choose FX for Bus '..tostring(busNum)

      local selectorButtons = self:findByName('fx_selector_button_group')
      selectorButtons.tag = tostring(busNum)
      selectorButtons:notify('setup_ui')
      self.visible = true

    end
  end
end