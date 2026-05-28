local NUM_BUSES = 5

local function normalizeParameters(parameters)
  local out = {}
  for i = 1, 6 do
    out[i] = tonumber(parameters[i] or parameters[tostring(i)]) or 0
  end
  return out
end

local function saveEffectBuses(buses)
  local normalized = {}
  for i = 1, NUM_BUSES do
    normalized[i] = buses[i] or buses[tostring(i)] or {}
  end
  self.tag = json.fromTable(normalized)
end

local function loadEffectBuses()
  local buses = {}
  if self.tag and self.tag ~= "" then
    buses = json.toTable(self.tag) or {}
  end
  for i = 1, NUM_BUSES do
    buses[i] = buses[i] or buses[tostring(i)] or {}
  end
  return buses
end

local function findEffectInStack(stack, fxNum)
  if type(stack) ~= "table" then
    return nil
  end
  local target = tonumber(fxNum)
  for i = 1, #stack do
    local effect = stack[i]
    if type(effect) == "table" and tonumber(effect.fxNum) == target then
      return effect
    end
  end
  for _, effect in pairs(stack) do
    if type(effect) == "table" and tonumber(effect.fxNum) == target then
      return effect
    end
  end
  return nil
end

local function pushEffectToBus(busNum, fxNum, parameters)
  local buses = loadEffectBuses()
  local busIndex = tonumber(busNum) or 1
  local stack = buses[busIndex] or {}
  local normalizedParams = normalizeParameters(parameters)
  local targetFx = tonumber(fxNum)

  local existing = findEffectInStack(stack, targetFx)
  if existing then
    existing.parameters = normalizedParams
    local newStack = { existing }
    for i = 1, #stack do
      local effect = stack[i]
      if effect ~= existing then
        newStack[#newStack + 1] = effect
      end
    end
    stack = newStack
  else
    table.insert(stack, 1, {
      fxNum = targetFx,
      parameters = normalizedParams,
    })
    if #stack > 16 then
      table.remove(stack)
    end
  end

  buses[busIndex] = stack
  saveEffectBuses(buses)
end

function onReceiveNotify(key, value)
  if key == "update_recent_values" then
    pushEffectToBus(value[1], value[2], value[3])
  end
end
