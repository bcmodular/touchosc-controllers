local function saveEffectBuses(buses)
  local busesString = json.fromTable(buses)
  --print('busesString', busesString)
  self.tag = busesString
  --print('saved buses', busesString)
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

  --print('current buses', unpack(buses))
  --print('current stack', unpack(stack))

  local existingIndex = nil

  for i, effect in ipairs(stack) do
    if effect.fxNum == fxNum then
      --print('found existing effect', effect.fxNum)
      existingIndex = i
      break
    end
  end

  if existingIndex then
    local effect = table.remove(stack, existingIndex)
    effect.parameters = parameters
    table.insert(stack, 1, effect)
  else
    --print('no existing effect found for fxNum', fxNum, 'on bus', busNum)
    local newEffect = {
      fxNum = fxNum,
      parameters = parameters
    }

    table.insert(stack, 1, newEffect)

    --print('new stack', unpack(stack))

    if #stack > 16 then
      table.remove(stack)
      --print('stack after removing', unpack(stack))
    end
  end

  buses[busNum] = stack

  --print('buses after saving', unpack(buses))

  saveEffectBuses(buses)
end

function onReceiveNotify(key, value)
  if key == 'update_recent_values' then
    local busNum = value[1]
    local fxNum = value[2]
    local parameters = value[3]
    --print('update_recent_values', busNum, fxNum, unpack(parameters))
    pushEffectToBus(busNum, fxNum, parameters)
  end
end
