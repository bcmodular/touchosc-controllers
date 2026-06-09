-- delete_button.lua
-- Mode button for delete. tag="delete" identifies this button's mode.

local updating = false

function onValueChanged(key)
  if key ~= 'x' then return end
  if updating then return end
  if self.values.x == 1 then
    root:notify("patch_mode_set", self.tag)
  end
end

function onReceiveNotify(key, value)
  if key == "patch_mode_changed" then
    updating = true
    self.values.x = (value == self.tag) and 1 or 0
    updating = false
  end
end
