-- preset_manager.lua — Persistent preset storage
-- Stores presets as JSON in the tag property of this hidden node.
-- Each preset is a table of {cc = midiValue} pairs for all 40 parameters.

local presets = {}  -- presets[slotNum] = {cc1 = val, cc2 = val, ...}

function init()
  -- Restore saved presets from tag
  if self.tag and self.tag ~= '' then
    local saved = json.toTable(self.tag)
    if saved then
      presets = saved
    end
  end
end

local function saveToTag()
  self.tag = json.fromTable(presets)
end

function onReceiveNotify(key, value)
  if key == 'store_preset' then
    -- value = {slot = N, values = {cc1 = val, cc2 = val, ...}}
    local slot = value.slot
    local vals = value.values
    presets[tostring(slot)] = vals
    saveToTag()
    print('preset_manager: stored preset', slot)

  elseif key == 'recall_preset' then
    -- value = slot number
    local slot = tostring(value)
    local preset = presets[slot]
    if preset then
      -- Notify the caller back with the preset data
      local presetGrid = root:findByName('preset_grid', true)
      if presetGrid then
        presetGrid:notify('preset_data', {slot = value, values = preset})
      end
    end

  elseif key == 'delete_preset' then
    local slot = tostring(value)
    presets[slot] = nil
    saveToTag()
    print('preset_manager: deleted preset', value)

  elseif key == 'get_slot_status' then
    -- Return which slots have data
    local status = {}
    for i = 1, 16 do
      status[i] = presets[tostring(i)] ~= nil
    end
    local presetGrid = root:findByName('preset_grid', true)
    if presetGrid then
      presetGrid:notify('slot_status', status)
    end
  end
end
