local childScript = [[

local allMidiValues = {
  "1, 10, 0", "2, 17, 0", "3, 23, 0", "4, 8, 0", "5, 35, 0",
  "6, 36, 0", "7, 5, 10", "8, 21, 0", "9, 25, 0", "10, 22, 0",
  "11, 34, 0", "12, 16, 0", "13, 0, 0", "14, 26, 0", "15, 24, 8",
  "16, 9, 0", "17, 11, 11", "18, 1, 12", "19, 2, 13", "20, 3, 14",
  "21, 4, 15", "22, 20, 7", "23, 27, 5", "24, 28, 6", "25, 29, 0",
  "26, 30, 0", "27, 31, 0", "28, 32, 0", "29, 33, 0", "30, 19, 9",
  "31, 18, 0", "32, 15, 0", "33, 14, 0", "34, 12, 0", "35, 13, 0",
  "36, 7, 16", "37, 6, 17", "38, 37, 0", "39, 38, 0", "40, 39, 0",
  "41, 0, 0", "42, 40, 0", "0, 0, 1", "0, 0, 2", "0, 0, 3", "0, 0, 4"
}

-- Function to check the value based on fxNum and busNum
function isNonZero(fxNum, busNum)
  -- Validate fxNum is within range
  if fxNum < 1 or fxNum > #allMidiValues then
    return false
  end

  -- Parse the corresponding MIDI values string into a table
  local midiValuesStr = allMidiValues[fxNum]
  local midiValues = {}
  for value in string.gmatch(midiValuesStr, "%d+") do
    table.insert(midiValues, tonumber(value))
  end

  -- Validate busNum and check the value
  if busNum == 0 or busNum == 1 then
    return midiValues[1] > 0
  elseif busNum == 2 or busNum == 3 then
    return midiValues[2] > 0
  elseif busNum == 4 then
    return midiValues[3] > 0
  else
    return false
  end
end

function onValueChanged(key, value)

  if key == 'x' and self.values.x == 1 then
    root.children.control_pager.values.page = self.tag
    root.children.fx_preset_selector_group.visible = true
    root.children.fx_preset_handler:notify('change_fx', tonumber(self.tag) + 1)
  end
end

function toggleButtonInteractivity()
  if isNonZero(tonumber(self.tag) + 1, tonumber(self.parent.tag)) then
    self.interactive = true
    self.color = "FF5C21FF"
  else
    self.interactive = false
    self.color = "333333FF"
  end
end

function init()
  --print('Initialising editor button:', self.name, isNonZero(tonumber(self.tag) + 1, 0))
  toggleButtonInteractivity()
end

function onReceiveNotify(key, value)
  if key == 'toggle_interactivity' then
    toggleButtonInteractivity()
  end
end

]]

function init()
  setChildrenScript()
end

function setChildrenScript()
  -- Loop through all buttons dynamically
  for i = 1, #self.children do
    local button = self.children[i]
    button.script = childScript
  end
end

function onReceiveNotify(key, value)
  if key == 'channel' then
    local channel = value
    --print('Channel changed to:', channel)
    self.tag = channel
  end

  -- Loop around children telling them to update their interactivity
  for i = 1, #self.children do
    local button = self.children[i]
    button:notify('toggle_interactivity')
  end
end