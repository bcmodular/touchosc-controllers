function onValueChanged(key, value)
  if key == 'x' then
    local performPresetGrids = root:findAllByName('preset_grid', true)

    for _, performPresetGrid in ipairs(performPresetGrids) do
      if self.values.x == 1 then
        performPresetGrid:notify('toggle_delete_mode', true)
      else
        performPresetGrid:notify('toggle_delete_mode', false)
      end
    end
  end
end

function init()
  self.values.x = 0
end
