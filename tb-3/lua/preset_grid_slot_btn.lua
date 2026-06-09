-- preset_grid_slot_btn.lua
-- Injected into slot buttons "1"–"16" under the preset_grid group.
-- Thin relay: notifies root when a slot is tapped.

function onValueChanged(key)
  if key ~= 'x' then return end
  if self.values.x == 1 then
    root:notify("patch_slot_pressed", tonumber(self.name))
  else
    root:notify("patch_slot_released", tonumber(self.name))
  end
end
