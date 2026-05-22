function onValueChanged(key, value)
  if key == 'x' then
    local deleteOn = self.values.x == 1
    local performPresetGrids = root:findAllByName('preset_grid', true)

    for _, performPresetGrid in ipairs(performPresetGrids) do
      performPresetGrid:notify('toggle_delete_mode', deleteOn)
    end

    local sceneGrid = root:findByName('scene_grid', true)
    if sceneGrid then
      sceneGrid:notify('toggle_delete_mode', deleteOn)
    end
  end
end

function init()
  self.values.x = 0
end
