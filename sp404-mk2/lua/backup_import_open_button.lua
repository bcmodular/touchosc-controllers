function onValueChanged(key)
  if key == "x" and self.values.x == 0 then
    local importGroup = root:findByName("backup_import_group", true)
    if importGroup then
      importGroup.visible = true
      importGroup.interactive = true
    end
  end
end
