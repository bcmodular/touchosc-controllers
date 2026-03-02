-- preset_grid.lua — Preset save/recall UI
-- Manages the 4x4 preset button grid, store/delete buttons.
-- Communicates with preset_manager for persistence and encoder faders for values.

local storeMode = false
local deleteMode = false
local slotStatus = {}  -- which slots have data (true/false per slot)

local EMPTY_COLOR = "4D4D4DFF"
local FILLED_COLOR = "3380B3FF"
local STORE_ACTIVE_COLOR = "FF6633FF"
local DELETE_ACTIVE_COLOR = "CC3333FF"

local function getPresetManager()
  return root:findByName('preset_manager', true)
end

local function getConfigNode()
  return root:findByName('config', true)
end

local function getParamsNode()
  return root:findByName('params', true)
end

local function setStatusText(text)
  local label = self:findByName('preset_status')
  if label then
    label.values.text = text
  end
end

local function updateButtonColors()
  for i = 1, 16 do
    local btn = self:findByName('preset_' .. i)
    if btn then
      if slotStatus[i] then
        btn.color = Color.fromHexString(FILLED_COLOR)
      else
        btn.color = Color.fromHexString(EMPTY_COLOR)
      end
    end
  end
end

local function captureCurrentValues()
  -- Read all encoder fader values and return as {cc = midiValue} table
  local configNode = getConfigNode()
  local paramsNode = getParamsNode()
  if not configNode or not paramsNode then return nil end

  local allParams = json.toTable(paramsNode.tag)
  if not allParams then return nil end

  local values = {}
  for _, param in ipairs(allParams) do
    local rowNum = param.row
    local col = param.col
    local encName = 'enc_' .. rowNum .. '_' .. col
    local faderName = encName .. '_fader'
    local rowGroup = root:findByName('row' .. rowNum .. '_group', true)
    if rowGroup then
      local encGroup = rowGroup:findByName(encName)
      if encGroup then
        local fader = encGroup:findByName(faderName)
        if fader then
          local midiVal = math.floor(fader.values.x * 127 + 0.5)
          values[tostring(param.cc)] = midiVal
        end
      end
    end
  end
  return values
end

local function recallValues(presetValues)
  -- Set all encoder faders from preset data
  local paramsNode = getParamsNode()
  if not paramsNode then return end

  local allParams = json.toTable(paramsNode.tag)
  if not allParams then return end

  for _, param in ipairs(allParams) do
    local ccStr = tostring(param.cc)
    local midiVal = presetValues[ccStr]
    if midiVal then
      local rowNum = param.row
      local col = param.col
      local encName = 'enc_' .. rowNum .. '_' .. col
      local faderName = encName .. '_fader'
      local rowGroup = root:findByName('row' .. rowNum .. '_group', true)
      if rowGroup then
        local encGroup = rowGroup:findByName(encName)
        if encGroup then
          local fader = encGroup:findByName(faderName)
          if fader then
            fader:notify('set_value', midiVal)
          end
        end
      end
    end
  end
end

local function handleSlotPress(slot)
  if storeMode then
    -- Store current values to this slot
    local values = captureCurrentValues()
    if values then
      local pm = getPresetManager()
      if pm then
        pm:notify('store_preset', {slot = slot, values = values})
      end
      slotStatus[slot] = true
      updateButtonColors()
      setStatusText('Stored preset ' .. slot)
    end
    storeMode = false
    return
  end

  if deleteMode then
    -- Delete this slot
    local pm = getPresetManager()
    if pm then
      pm:notify('delete_preset', slot)
    end
    slotStatus[slot] = false
    updateButtonColors()
    setStatusText('Deleted preset ' .. slot)
    deleteMode = false
    return
  end

  -- Recall mode
  if slotStatus[slot] then
    local pm = getPresetManager()
    if pm then
      pm:notify('recall_preset', slot)
    end
    setStatusText('Recall preset ' .. slot)
  else
    setStatusText('Slot ' .. slot .. ' empty')
  end
end

function init()
  -- Request slot status from preset_manager
  local pm = getPresetManager()
  if pm then
    pm:notify('get_slot_status')
  end
end

function onReceiveNotify(key, value)
  if key == 'slot_status' then
    -- value = {true, false, true, ...} for slots 1-16
    slotStatus = value
    updateButtonColors()

  elseif key == 'preset_data' then
    -- value = {slot = N, values = {cc = val, ...}}
    recallValues(value.values)

  elseif key == 'bcr_preset_recall' then
    -- value = BCR button index (1-4)
    handleSlotPress(value)
  end
end

-- Watch for button presses on preset slot buttons
function onValueChanged(key)
  -- Check store button
  local storeBtn = self:findByName('preset_store')
  if storeBtn and storeBtn.values.x == 1 then
    storeMode = true
    deleteMode = false
    setStatusText('Tap a slot to store...')
    return
  end

  -- Check delete button
  local deleteBtn = self:findByName('preset_delete')
  if deleteBtn and deleteBtn.values.x == 1 then
    deleteMode = true
    storeMode = false
    setStatusText('Tap a slot to delete...')
    return
  end

  -- Check preset slot buttons
  for i = 1, 16 do
    local btn = self:findByName('preset_' .. i)
    if btn and btn.values.x == 1 then
      btn.values.x = 0  -- reset toggle
      handleSlotPress(i)
      return
    end
  end
end
