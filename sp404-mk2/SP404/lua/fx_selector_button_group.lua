local effects = EFFECT_NAMES

local NUM_COLUMNS = 8
local NUM_ROWS = 6
local ENCODER_STEPS_PER_SLOT = 10

local COLOR_UNAVAILABLE = "8D8D8AFF"
local COLOR_AVAILABLE = "F79000FF"
local COLOR_PENDING = "00FF88FF"
local COLOR_LABEL_UNAVAILABLE = "000000FF"
local COLOR_LABEL_AVAILABLE = "FFFFFFFF"

local busNum = 1
local midiIndex = 1
local activeColumn = 1
local columnRow = 1
local columnAccumulator = {}
local columnEffects = {}

local buttonScript = [[
function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    local busGroup = root:findByName('bus' .. tostring(self.parent.tag) .. '_group', true)
    if busGroup then
      busGroup:notify('set_fx', { self.tag, self.name })
    end
  end
end
]]

local function effectIndexForCell(col, row)
  return (row - 1) * NUM_COLUMNS + col
end

local function buildColumnEffectLists()
  local cols = {}
  for col = 1, NUM_COLUMNS do
    cols[col] = {}
    for row = 1, NUM_ROWS do
      local fxIdx = effectIndexForCell(col, row)
      if fxIdx <= #effects then
        table.insert(cols[col], fxIdx)
      end
    end
  end
  return cols
end

columnEffects = buildColumnEffectLists()

local function isEffectAvailable(fxIdx)
  return isEffectOnMidiAvailable(fxIdx, busNum)
end

local function getAvailableForColumn(col)
  local list = {}
  for _, fxIdx in ipairs(columnEffects[col]) do
    if isEffectAvailable(fxIdx) then
      table.insert(list, fxIdx)
    end
  end
  return list
end

local function getBusAccentHex()
  local tag = json.toTable(root.tag) or {}
  local accents = tag.busAccentHex or {}
  return accents[tostring(busNum)] or "00E6FFFF"
end

local function getCurrentFxNum()
  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then
    return 0
  end
  local settings = json.toTable(busGroup.tag) or {}
  return resolveBusFxNum(settings)
end

local function findTopLeftAvailableFx()
  for row = 1, NUM_ROWS do
    for col = 1, NUM_COLUMNS do
      local fxIdx = effectIndexForCell(col, row)
      if fxIdx <= #effects and isEffectAvailable(fxIdx) then
        return col, fxIdx
      end
    end
  end
  return 1, nil
end

local function getPendingFxIndex()
  local available = getAvailableForColumn(activeColumn)
  if #available == 0 then
    return nil
  end
  local row = columnRow
  if row < 1 then
    row = 1
  end
  if row > #available then
    row = #available
  end
  return available[row]
end

local function resetColumnAccumulators()
  for col = 1, NUM_COLUMNS do
    columnAccumulator[col] = 0
  end
end

local function initPendingSelection()
  resetColumnAccumulators()
  activeColumn = 1
  columnRow = 1

  local startCol, _startFx = findTopLeftAvailableFx()
  if startCol then
    activeColumn = startCol
  end
end

local paintAllButtons

local function activateColumn(col)
  if col == activeColumn then
    return
  end
  activeColumn = col
  columnRow = 1
  columnAccumulator[col] = 0
  paintAllButtons()
end

paintAllButtons = function()
  local labelGroup = self.parent:findByName("fx_selector_label_group")
  local currentFx = getCurrentFxNum()
  local pendingFx = getPendingFxIndex()
  local busAccent = getBusAccentHex()

  for i = 1, #effects do
    local label = labelGroup:findByName(tostring(i))
    local button = self:findByName(effects[i])

    label.values.text = effects[i]
    label.color = Color.fromHexString("00000000")
    button.tag = i
    button.name = effects[i]

    if pendingFx and i == pendingFx then
      button.color = Color.fromHexString(COLOR_PENDING)
      label.textColor = Color.fromHexString(COLOR_LABEL_AVAILABLE)
    elseif i == currentFx and isEffectAvailable(i) then
      button.color = Color.fromHexString(busAccent)
      label.textColor = Color.fromHexString(COLOR_LABEL_AVAILABLE)
    elseif isEffectAvailable(i) then
      button.color = Color.fromHexString(COLOR_AVAILABLE)
      label.textColor = Color.fromHexString(COLOR_LABEL_AVAILABLE)
    else
      button.color = Color.fromHexString(COLOR_UNAVAILABLE)
      label.textColor = Color.fromHexString(COLOR_LABEL_UNAVAILABLE)
    end
  end
end

local function stepWithinColumn(delta)
  local available = getAvailableForColumn(activeColumn)
  if #available == 0 then
    return
  end

  columnRow = columnRow + delta
  if columnRow > #available then
    columnRow = 1
  elseif columnRow < 1 then
    columnRow = #available
  end
  paintAllButtons()
end

local function encoderValueToDirection(value)
  if value == 0 then
    return 0
  end
  if value == 1 then
    return 1
  end
  if value == 127 then
    return -1
  end
  if value >= 64 then
    return -1
  end
  return 1
end

local function accumulateColumnTick(col, direction)
  if direction == 0 then
    return
  end

  activateColumn(col)

  columnAccumulator[col] = (columnAccumulator[col] or 0) + direction

  if columnAccumulator[col] >= ENCODER_STEPS_PER_SLOT then
    stepWithinColumn(1)
    columnAccumulator[col] = 0
  elseif columnAccumulator[col] <= -ENCODER_STEPS_PER_SLOT then
    stepWithinColumn(-1)
    columnAccumulator[col] = 0
  end
end

-- TouchOSC does not fire onValueChanged when values are set from script (see lua/README.md).
local function selectEffectByIndex(fxIdx)
  local fxName = effects[fxIdx]
  if not fxName or not isEffectAvailable(fxIdx) then
    return
  end

  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  if not busGroup then
    print("fx_selector: bus group not found for bus", busNum)
    return
  end

  busGroup:notify("set_fx", { fxIdx, fxName })
end

local function confirmColumnSelection(col)
  if col ~= activeColumn then
    activeColumn = col
    columnRow = 1
  end

  local fxIdx = getPendingFxIndex()
  if fxIdx then
    selectEffectByIndex(fxIdx)
  end
end

local function setupUI()
  busNum = tonumber(self.tag) or 1
  midiIndex = getMidiIndexForBus(busNum)

  initPendingSelection()
  paintAllButtons()
end

function onReceiveNotify(key, value)
  if key == "setup_ui" then
    setupUI()
  elseif key == "midi_column_tick" then
    local col = value.col
    local direction = encoderValueToDirection(value.ccValue)
    if col and col >= 1 and col <= NUM_COLUMNS then
      accumulateColumnTick(col, direction)
    end
  elseif key == "midi_column_confirm" then
    local col = value.col
    if col and col >= 1 and col <= NUM_COLUMNS then
      confirmColumnSelection(col)
    end
  elseif key == "midi_reset" then
    resetColumnAccumulators()
  end
end

function init()
  for i = 1, #self.children do
    self.children[i].script = buttonScript
  end

  setupUI()
end
