function onValueChanged(key)
  if key == "x" and self.values.x == 1 then
    local backupManager = root.children.backup_manager
    if backupManager then
      backupManager:notify("export_backup_to_osc")
    end
  end
end
