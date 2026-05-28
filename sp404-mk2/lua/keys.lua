local w = self.children.white.children
local b = self.children.black.children

local key_script = [[
function onValueChanged(key, value)
  if key ~= "x" then
    return
  end

  local tag = json.toTable(root.tag) or {}
  if tag.keyboardHighlighting == true then
    return
  end

  local note = tonumber(self.name)
  if not note then
    return
  end

  local velocity = math.floor(self.values.x * 127 + 0.5)

  if velocity <= 0 then
    if tag.keyboardChromaticEnabled == true then
      root:notify("keyboard_ui_note", { note, 0 })
    end
    return
  end

  root:notify("keyboard_key_select", { note, velocity })
end
]]

local keys = {
  w[1], b[1], w[2], b[2], w[3],
  w[4], b[3], w[5], b[4], w[6], b[5], w[7],
  w[8], b[6], w[9], b[7], w[10],
  w[11], b[8], w[12], b[9], w[13], b[10], w[14],
}

local function applyKeyScripts()
  for i = 1, #keys do
    keys[i].script = key_script
  end
end

function init()
  onReceiveNotify("octave", 2)
  applyKeyScripts()
end

function onReceiveNotify(key, value)
  if key == "octave" then
    local octave = value
    local index = octave * 12
    for i = 1, #keys do
      local note = index + (i - 1)
      keys[i].name = note
      keys[i].visible = (note <= 127)
    end
    self.children.C0.values.text = "C" .. (octave - 1)
    self.children.C1.values.text = "C" .. octave
    applyKeyScripts()
  end
end
