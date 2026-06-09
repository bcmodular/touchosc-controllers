-- preset_grid_slot_btn.lua
-- Injected into slot buttons "1"–"16" under the preset_grid group.
-- Thin relay: notifies root when a slot is tapped.

function onValueChanged(key, value)
  if key == 'x' and value == 1 then
    root:notify("patch_slot_pressed", tonumber(self.name))
  end
end
