-------------------
-- DEFAULT HANDLING
-------------------

local function storeDefaults(fxNum, defaultValues)
  print('Storing defaults for FX:', fxNum, 'with values:', unpack(defaultValues))
  local fullTag = json.toTable(self.tag)
  fullTag[tostring(fxNum)] = defaultValues
  self.tag = json.fromTable(fullTag)
end

function onReceiveNotify(key, value)
  if key == 'store_defaults' then
    local fxNum = value[1]
    local defaultValues = value[2]
    storeDefaults(fxNum, defaultValues)
  end
end