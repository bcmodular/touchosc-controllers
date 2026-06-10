function onValueChanged(key)
  if key == "x" and self.values.x == 0 then
    local warningGroup = root:findByName('delete_all_warning_group')
    warningGroup.visible = true
    warningGroup.interactive = true
  end
end