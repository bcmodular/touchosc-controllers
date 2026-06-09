-- delete_all_presets_button.lua
-- Clears all 16 patch slots. Fires on release (value 1→0).

function onValueChanged(key)
  if key == 'x' and self.values.x == 0 then
    root:notify("patch_clear_all", "")
  end
end

function init()
  self.values.x = 0
end
