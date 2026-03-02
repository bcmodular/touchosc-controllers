-- encoder_mapper.lua — Dynamic per-encoder script generator
-- Injected into each row group. On init, reads params and config,
-- then generates and injects scripts into each encoder's fader + value label.

-- =========================================================================
-- MAPPING FUNCTION SNIPPETS
-- Each snippet defines a local function that converts a MIDI value (1-128)
-- to a display string. Injected into fader scripts via string.format.
-- =========================================================================

local mappingSnippets = {
  getZeroHundred = [[
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      if v == 127 then return "100" end
      return tostring(math.floor((v / 127.5) * 100))
    end
  ]],

  getPercent = [[
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      if v == 127 then return "100%%" end
      return tostring(math.floor((v / 127.5) * 100)) .. "%%"
    end
  ]],

  getBipolar = [[
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      local scaled = math.floor((v / 127) * 200 - 100 + 0.5)
      if scaled > 0 then return "+" .. tostring(scaled) end
      return tostring(scaled)
    end
  ]],

  getCoarseTune = [[
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      local semi = math.floor((v / 127) * 48 - 24 + 0.5)
      if semi > 0 then return "+" .. tostring(semi) end
      return tostring(semi)
    end
  ]],

  getFineTune = [[
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      local cent = math.floor((v / 127) * 100 - 50 + 0.5)
      if cent > 0 then return "+" .. tostring(cent) end
      return tostring(cent)
    end
  ]],

  getGrains = [[
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      local grains = math.floor((v / 127) * 7 + 0.5) + 1
      return tostring(grains)
    end
  ]],

  getStartMode = [[
    local modes = {"COLD", "HOT"}
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      local idx = v < 64 and 1 or 2
      return modes[idx]
    end
  ]],

  getTEnvMode = [[
    local modes = {"ADSR", "ADR", "ADA"}
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      local idx = math.floor((v / 127) * 2 + 0.5) + 1
      if idx > 3 then idx = 3 end
      return modes[idx]
    end
  ]],

  getFilterType = [[
    local types = {"OFF", "LPF", "BPF", "HPF", "PKG"}
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      local idx = math.floor((v / 127) * 4 + 0.5) + 1
      if idx > 5 then idx = 5 end
      return types[idx]
    end
  ]],

  getPan = [[
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      if v == 64 then return "C" end
      if v < 64 then
        return "L" .. tostring(64 - v)
      else
        return "R" .. tostring(v - 64)
      end
    end
  ]],

  getOnOff = [[
    local states = {"OFF", "ON"}
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      return states[v < 64 and 1 or 2]
    end
  ]],

  getOutputBus = [[
    local buses = {"A", "B", "EFFECT"}
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      local idx = math.floor((v / 127) * 2 + 0.5) + 1
      if idx > 3 then idx = 3 end
      return buses[idx]
    end
  ]],

  getAutoPan = [[
    local modes = {"OFF", "ALT", "SWING", "RANDOM"}
    local function getDisplayValue(midiVal)
      local v = midiVal - 1
      local idx = math.floor((v / 127) * 3 + 0.5) + 1
      if idx > 4 then idx = 4 end
      return modes[idx]
    end
  ]],

  getSample = [[
    local function getDisplayValue(midiVal)
      return tostring(midiVal - 1)
    end
  ]],
}

-- =========================================================================
-- FADER SCRIPT TEMPLATE
-- Injected into each encoder's fader element.
-- Placeholders: %s = mapping snippet, %d = P-6 CC, %d = P-6 channel,
--               %d = BCR CC, %d = BCR channel
-- =========================================================================

local faderScriptTemplate = [[
  local P6_CC = %d
  local P6_CH = %d
  local BCR_CC = %d
  local BCR_CH = %d

  %s

  local function floatToMIDI(f)
    return math.floor(f * 127 + 0.5)
  end

  local function midiToFloat(m)
    return m / 127
  end

  local function updateLabel(floatVal)
    local midiVal = floatToMIDI(floatVal) + 1  -- 1-indexed for display function
    local label = self.parent:findByName('%s_value')
    if label then
      label.values.text = getDisplayValue(midiVal)
    end
  end

  local function sendP6()
    sendMIDI({MIDIMessageType.CONTROLCHANGE + P6_CH, P6_CC, floatToMIDI(self.values.x)})
  end

  local function sendBCR()
    sendMIDI({MIDIMessageType.CONTROLCHANGE + BCR_CH, BCR_CC, floatToMIDI(self.values.x)})
  end

  function onValueChanged(key)
    if key == 'x' then
      updateLabel(self.values.x)
      sendP6()
      sendBCR()
    end
  end

  function onReceiveNotify(key, value)
    if key == 'set_value' then
      self.values.x = midiToFloat(value)
      updateLabel(self.values.x)
      sendP6()
      -- Don't send BCR here to avoid loop
    elseif key == 'set_value_no_midi' then
      self.values.x = midiToFloat(value)
      updateLabel(self.values.x)
    elseif key == 'update_label' then
      updateLabel(self.values.x)
    end
  end

  function init()
    updateLabel(self.values.x)
  end
]]

-- =========================================================================
-- VALUE LABEL SCRIPT TEMPLATE
-- Simple label that accepts text updates via notify.
-- =========================================================================

local valueLabelScriptTemplate = [[
  function onReceiveNotify(key, value)
    if key == 'update_text' then
      self.values.text = tostring(value)
    end
  end
]]

-- =========================================================================
-- INIT — Read config + params, inject scripts into this row's encoders
-- Uses update() for deferred init so sibling tag data is available.
-- =========================================================================

local initialized = false

function update()
  if initialized then return end
  initialized = true

  local configNode = root:findByName('config', true)
  local paramsNode = root:findByName('params', true)

  if not configNode or not paramsNode then
    print('encoder_mapper: config or params not found')
    return
  end

  local config = json.toTable(configNode.tag)
  local allParams = json.toTable(paramsNode.tag)

  if not config or not allParams then
    print('encoder_mapper: failed to parse config or params')
    return
  end

  -- Determine which row we are from our name (row1_group → row 1)
  local rowNum = tonumber(string.match(self.name, 'row(%d+)_group'))
  if not rowNum then
    print('encoder_mapper: cannot determine row number from name:', self.name)
    return
  end

  local bcrTurnCCs = config.bcrTurnCCs[rowNum]
  if not bcrTurnCCs then
    print('encoder_mapper: no BCR turn CCs for row', rowNum)
    return
  end

  -- Find params for this row
  for col = 1, 8 do
    local encName = 'enc_' .. rowNum .. '_' .. col
    local encGroup = self:findByName(encName)
    if encGroup then
      -- Find matching param
      local param = nil
      for _, p in ipairs(allParams) do
        if p.row == rowNum and p.col == col then
          param = p
          break
        end
      end

      if not param then
        -- No param for this position — hide the encoder
        encGroup.visible = false
      else
        local fader = encGroup:findByName(encName .. '_fader')
        if fader then
          local snippet = mappingSnippets[param.display]
          if not snippet then
            print('encoder_mapper: unknown display function:', param.display)
            snippet = mappingSnippets['getZeroHundred']
          end

          local bcrCC = bcrTurnCCs[col] or 0

          local faderScript = string.format(faderScriptTemplate,
            param.cc,
            config.p6Channel,
            bcrCC,
            config.bcrChannel,
            snippet,
            encName  -- for label lookup
          )

          fader.script = faderScript
        end
      end
    end
  end
end
