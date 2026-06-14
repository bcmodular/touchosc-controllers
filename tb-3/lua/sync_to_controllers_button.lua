-- sync_to_controllers_button.lua
-- On press: notifies root to push current patch state to both BCR2000 units.

function onValueChanged(key)
  if key == "x" and self.values.x == 1 then
    root:notify("sync_to_controllers", "")
  end
end
