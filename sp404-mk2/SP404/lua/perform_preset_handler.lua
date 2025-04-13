local performPresetHandlerScript = [[

local fxNum = 1
local performPresetGrid = nil

local function handleSetSettings(value)
  fxNum = tonumber(value[1]) or 0

  local presetManager = root.children.preset_manager
  presetManager:notify('stored_presets_list', {performPresetGrid, fxNum})
end

local function handleRecall(value)
  print('perform_preset_handler received recall notification for preset:', value)
  local presetManager = root.children.preset_manager
  local recallProxy = self.parent:findByName('perform_recall_proxy')
  presetManager:notify('recall_preset', {fxNum, value, recallProxy})
end

function onReceiveNotify(key, value)
  if key == 'set_settings' then
    handleSetSettings(value)
  elseif key == 'recall' then
    handleRecall(value)
  end
end

function init()
  performPresetGrid = self.parent:findByName('perform_preset_grid', true)
end
]]

function init()
  local debugMode = root:findByName('debug_mode').values.x
  if debugMode == 1 then
    local performPresetHandlers = root:findAllByName('perform_preset_handler', true)
    for _, performPresetHandler in ipairs(performPresetHandlers) do
      performPresetHandler.script = performPresetHandlerScript
    end
  end
end
