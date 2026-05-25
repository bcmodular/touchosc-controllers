function onValueChanged(key)
  if key == "x" and self.values.x == 0 then
    local jsonBackup = self.parent.tag
    local backupManager = root:findByName("backup_manager", true)
    if backupManager and jsonBackup and jsonBackup ~= "" then
      backupManager:notify("import_backup_from_osc", jsonBackup)
    end
    self.parent:notify("close_import_overlay")
  end
end
