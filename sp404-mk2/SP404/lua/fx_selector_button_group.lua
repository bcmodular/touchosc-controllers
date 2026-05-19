local effects = {
  "Filter + Drive", "Resonator", "Sync Delay", "Isolator", "DJFX Looper", "Scatter",
  "Downer", "Ha-Dou", "Ko-Da-Ma", "Zan-Zou", "To-Gu-Ro", "SBF",
  "Stopper", "Tape Echo", "TimeCtrlDly", "Super Filter", "WrmSaturator", "303 VinylSim",
  "404 VinylSim", "Cassette Sim", "Lo-fi", "Reverb", "Chorus", "JUNO Chorus",
  "Flanger", "Phaser", "Wah", "Slicer", "Tremolo/Pan", "Chromatic PS",
  "Hyper-Reso", "Ring Mod", "Crusher", "Overdrive", "Distortion", "Equalizer",
  "Compressor", "SX Reverb", "SX Delay", "Cloud Delay", "Back Spin", "DJFX Delay",
  "Auto Pitch", "Vocoder", "Harmony", "Gt Amp Sim"
}

local allMidiValues = {
  {1, 10, 0}, {2, 17, 0}, {3, 23, 0}, {4, 8, 0}, {5, 35, 0},
  {6, 36, 0}, {7, 5, 10}, {8, 21, 0}, {9, 25, 0}, {10, 22, 0},
  {11, 34, 0}, {12, 16, 0}, {13, 0, 0}, {14, 26, 0}, {15, 24, 8},
  {16, 9, 0}, {17, 11, 11}, {18, 1, 12}, {19, 2, 13}, {20, 3, 14},
  {21, 4, 15}, {22, 20, 7}, {23, 27, 5}, {24, 28, 6}, {25, 29, 0},
  {26, 30, 0}, {27, 31, 0}, {28, 32, 0}, {29, 33, 0}, {30, 19, 9},
  {31, 18, 0}, {32, 15, 0}, {33, 14, 0}, {34, 12, 0}, {35, 13, 0},
  {36, 7, 16}, {37, 6, 17}, {38, 37, 0}, {39, 38, 0}, {40, 39, 0},
  {41, 0, 0}, {42, 40, 0}, {0, 0, 1}, {0, 0, 2}, {0, 0, 3}, {0, 0, 4}
}

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
  return allMidiValues[fxIdx][midiIndex] ~= 0
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
  return tonumber(settings.fxNum) or 0
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

  if busNum == 1 or busNum == 2 then
    midiIndex = 1
  elseif busNum == 3 or busNum == 4 then
    midiIndex = 2
  else
    midiIndex = 3
  end

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
