local BACKUP_VERSION = 1

local function validBackupMessage(jsonBackup)
  if type(jsonBackup) ~= "string" or jsonBackup == "" then
    return false
  end
  local data = json.toTable(jsonBackup)
  if type(data) ~= "table" then
    return false
  end
  if tonumber(data.version) ~= BACKUP_VERSION then
    return false
  end
  if type(data.presets) ~= "table" then
    return false
  end
  return true
end

local function closeImportOverlay()
  self.children.backup_import_button.visible = false
  self.children.backup_import_label.visible = false
  self.children.backup_import_information_label.values.text =
    "Waiting for backup import from OSC. Please start sending..."
  self.visible = false
  self.interactive = false
end

local function handleReceivedMessage(jsonBackup)
  self.visible = true
  self.interactive = true
  if validBackupMessage(jsonBackup) then
    self.children.backup_import_button.visible = true
    self.children.backup_import_label.visible = true
    self.children.backup_import_information_label.values.text =
      "Received valid backup, click IMPORT to continue..."
    self.tag = jsonBackup
  else
    self.children.backup_import_button.visible = false
    self.children.backup_import_label.visible = false
    self.children.backup_import_information_label.values.text =
      "Received invalid backup, please try again..."
  end
end

function onReceiveNotify(key, value)
  if key == "osc_backup_received" then
    handleReceivedMessage(value)
  elseif key == "close_import_overlay" then
    closeImportOverlay()
  end
end
