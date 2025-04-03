local function saveEffectBuses(buses)
  self.tag = json.fromTable(buses)
end

local function loadEffectBuses()
  local buses = {}

  if self.tag and self.tag ~= "" then
    buses = json.toTable(self.tag) or {}
  end

  for i = 1, 5 do
    if not buses[i] then
      buses[i] = {}
    end
  end

  return buses
end

local function pushEffectToBus(busNum, fxNum, parameters)
  local buses = loadEffectBuses()

  local stack = buses[busNum] or {}

  local existingIndex = nil

  for i, effect in ipairs(stack) do
    if effect.id == fxNum then
      existingIndex = i
      break
    end
  end

  if existingIndex then
    local effect = table.remove(stack, existingIndex)
    effect.parameters = parameters
    table.insert(stack, 1, effect)
  else
    local newEffect = {
      id = fxNum,
      parameters = parameters
    }

    table.insert(stack, 1, newEffect)

    if #stack > 16 then
      table.remove(stack)
    end
  end

  buses[busNum] = stack

  saveEffectBuses(buses)
  return buses
end

function onReceiveNotify(key, value)
  if key == 'update_recent_values' then
    local channel = value[1]
    local fxNum = value[2]
    local parameters = value[3]

    pushEffectToBus(channel, fxNum, parameters)
  end
end
