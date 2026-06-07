-- save_to_library_btn.lua
-- Momentary BUTTON (buttonType 0).
-- On press: notifies root to build a JSON export blob from cached SysEx blocks
-- and send it to the Python preset manager via OSC /tb3/backup.
-- Requires a prior SYNC FROM TB-3 to have populated the SysEx cache.

function onValueChanged(key)
  if key ~= "x" then return end
  if self.values.x == 1 then
    root:notify("save_to_library", "")
  end
end
