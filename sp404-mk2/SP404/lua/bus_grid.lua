function init()
  if self.name ~= 'bus_grid' then
    self.outline = true
    self.outlineStyle = OutlineStyle.FULL
    self.name = ''
  else
    self.outline = false
    self.children[1].values.x = 1
  end
end

function onValueChanged(key, value)
  
  if self.name ~= 'bus_grid' and key == 'x' then
    
    print('Channel changed to:', tostring(self.index - 1))
    root:notify('channel', self.index - 1)
    
    if self.name ~= '' then
      local fxPage = tonumber(self.name) - 1
      
      root.children.control_pager.values.page = fxPage
      root.children.fx_preset_selector_group.visible = true
      root.children.fx_preset_handler:notify('change_fx', fxPage + 1)
    else
      root.children.control_pager.values.page = 47
      root.children.fx_preset_selector_group.visible = false
    end
    
    self.values.x = 1
    
  end
end

function onReceiveNotify(key, value)
  print('onReceiveNotify called with key:', key, 'value:', value)
  if self.name == 'bus_grid' then
    if key == 'change_name' then
      local buttonNum = value[1]
      local fxNum = value[2]
      print('Changing name of button:', buttonNum, 'to:', fxNum)
      self.children[buttonNum].name = tostring(fxNum)
    end
  end
  
end