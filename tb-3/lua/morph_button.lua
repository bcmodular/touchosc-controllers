-- morph_button.lua
-- Mode button for morph. tag="morph" identifies this button's mode.
-- Press toggles morph mode on/off; root broadcasts patch_mode_changed
-- back to all mode buttons to keep lit state mutually exclusive.

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
