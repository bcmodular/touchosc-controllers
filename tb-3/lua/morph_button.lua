-- morph_button.lua
local MODE = "morph"
local updating = false

function onValueChanged(key)
  if key ~= 'x' then return end
  if updating then return end
  root:notify("patch_mode_set", MODE)
end

function onReceiveNotify(key, value)
  if key == "patch_mode_changed" then
    updating = true
    self.values.x = (value == MODE) and 1 or 0
    updating = false
  end
end
