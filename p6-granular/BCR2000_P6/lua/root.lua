-- root.lua — Root-level MIDI handler for BCR2000 ↔ P-6 controller
-- Receives BCR2000 CC messages and routes them to the correct encoder fader.
-- Also receives P-6 CC messages for bidirectional sync.

local config = nil
local bcrCCToEncoder = {}   -- BCR CC → {rowGroup, encName} lookup
local p6CCToEncoder = {}    -- P-6 CC → {rowGroup, encName} lookup
local initialized = false

local function lazyInit()
  if initialized then return true end

  local configNode = self:findByName('config', true)
  local paramsNode = self:findByName('params', true)

  if not configNode or not paramsNode then return false end

  config = json.toTable(configNode.tag)
  local allParams = json.toTable(paramsNode.tag)

  if not config or not allParams then return false end

  -- Build BCR CC → encoder lookup
  for _, param in ipairs(allParams) do
    local rowNum = param.row
    local col = param.col
    local encName = 'enc_' .. rowNum .. '_' .. col
    local faderName = encName .. '_fader'
    local rowName = 'row' .. rowNum .. '_group'

    -- BCR turn CC lookup
    if config.bcrTurnCCs[rowNum] then
      local bcrCC = config.bcrTurnCCs[rowNum][col]
      if bcrCC then
        bcrCCToEncoder[bcrCC] = {row = rowName, enc = encName, fader = faderName}
      end
    end

    -- P-6 CC lookup (for bidirectional sync from P-6)
    p6CCToEncoder[param.cc] = {row = rowName, enc = encName, fader = faderName}
  end

  initialized = true
  print('root: initialized with', #allParams, 'params')
  return true
end

function onReceiveMIDI(message, connections)
  if not lazyInit() then return end

  local status = message[1]
  local cc = message[2]
  local value = message[3]

  -- Only handle CC messages
  local msgType = status - (status % 16)
  local msgChannel = status % 16

  if msgType ~= MIDIMessageType.CONTROLCHANGE then
    return
  end

  -- Check if this is from the BCR (channel match)
  if msgChannel == config.bcrChannel then
    local target = bcrCCToEncoder[cc]
    if target then
      local rowGroup = self:findByName(target.row, true)
      if rowGroup then
        local encGroup = rowGroup:findByName(target.enc)
        if encGroup then
          local fader = encGroup:findByName(target.fader)
          if fader then
            fader:notify('set_value', value)
          end
        end
      end
    end

    -- Check BCR button CCs for preset recall
    if config.bcrButtonCCs then
      for i, btnCC in ipairs(config.bcrButtonCCs) do
        if cc == btnCC and value > 0 then
          local presetGrid = self:findByName('preset_grid', true)
          if presetGrid then
            presetGrid:notify('bcr_preset_recall', i)
          end
          return
        end
      end
    end
    return
  end

  -- Check if this is from the P-6 (for bidirectional sync)
  if msgChannel == config.p6Channel then
    local target = p6CCToEncoder[cc]
    if target then
      local rowGroup = self:findByName(target.row, true)
      if rowGroup then
        local encGroup = rowGroup:findByName(target.enc)
        if encGroup then
          local fader = encGroup:findByName(target.fader)
          if fader then
            -- Use set_value_no_midi to avoid sending back to P-6
            fader:notify('set_value_no_midi', value)
          end
        end
      end
    end
    return
  end
end
