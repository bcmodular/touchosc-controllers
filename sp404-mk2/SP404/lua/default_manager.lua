-------------------
-- DEFAULT HANDLING
-------------------

local childScript = [[
function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
      print('Current default values:', self.tag)
  end
end
]]

local function storeDefaults(fxNum, defaultValues)

  print('Storing defaults for FX:', fxNum, 'with values:', unpack(defaultValues))

  local jsonDefaults = json.fromTable(defaultValues)
  self.children[tostring(fxNum)].tag = jsonDefaults
  print('Updated defaults array (json):', jsonDefaults)

end

local function assignChildScripts()
  for i = 1, #self.children do
    self.children[tostring(i)].script = childScript
  end
end

function init()
  print('Initialising default manager')
  assignChildScripts()
end

function onReceiveNotify(key, value)

  print('default_manager received notification:', key, value)

  if key == 'store_defaults' then

    local fxNum = value[1]
    local defaultValues = value[2]
    print('Storing defaults for FX:', fxNum, 'with values:', unpack(defaultValues))
    storeDefaults(fxNum, defaultValues)

  end
end