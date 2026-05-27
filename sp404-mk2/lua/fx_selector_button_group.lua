local effects = EFFECT_NAMES

local COLOR_UNAVAILABLE = "8D8D8AFF"
local COLOR_LABEL_UNAVAILABLE = "000000FF"
local COLOR_LABEL_AVAILABLE = "FFFFFFFF"

local busNum = 1
local pendingFxNum = nil

local buttonScript = [[
function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    local busGroup = root:findByName('bus' .. tostring(self.parent.tag) .. '_group', true)
    if busGroup then
      busGroup:notify('set_fx', { self.tag, self.name, false })
    end
  end
end
]]

local function isEffectAvailable(fxIdx)
  return isEffectOnMidiAvailable(fxIdx, busNum)
end

local function getBusAccentHex()
  local tag = json.toTable(root.tag) or {}
  local accents = tag.busAccentHex or {}
  return accents[tostring(busNum)] or "00E6FFFF"
end

local function brightenHex(hex, mix)
  local c = Color.fromHexString(hex)
  local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
  end
  local function to255(v)
    return math.floor(clamp01(v) * 255 + 0.5)
  end
  local r = to255(c.r + (1 - c.r) * mix)
  local g = to255(c.g + (1 - c.g) * mix)
  local b = to255(c.b + (1 - c.b) * mix)
  local a = to255(c.a)
  return string.format("%02X%02X%02X%02X", r, g, b, a)
end

local function getPendingHighlight()
  return self:findByName("pending_fx_highlight")
end

local paintAllButtons

paintAllButtons = function()
  local labelGroup = self.parent:findByName("fx_selector_label_group")
  local busAccent = getBusAccentHex()
  local pendingHighlight = getPendingHighlight()
  local pendingButton = nil

  if pendingHighlight then
    pendingHighlight.visible = false
    pendingHighlight.interactive = false
    pendingHighlight.values.x = 1
    pendingHighlight.color = Color.fromHexString(brightenHex(busAccent, 0.45))
  end

  for i = 1, #effects do
    local label = labelGroup:findByName(tostring(i))
    local button = self:findByName(effects[i])

    label.values.text = effects[i]
    label.background = false
    label.color = Color.fromHexString("00000000")
    button.tag = i
    button.name = effects[i]

    if pendingFxNum == i and isEffectAvailable(i) then
      -- Make the front button transparent so the movable highlight button behind is visible.
      button.color = Color.fromHexString("00000000")
      pendingButton = button
      label.textColor = Color.fromHexString("000000FF")
    elseif isEffectAvailable(i) then
      button.color = Color.fromHexString(busAccent)
      label.textColor = Color.fromHexString(COLOR_LABEL_AVAILABLE)
    else
      button.color = Color.fromHexString(COLOR_UNAVAILABLE)
      label.textColor = Color.fromHexString(COLOR_LABEL_UNAVAILABLE)
    end
  end

  if pendingHighlight and pendingButton then
    pendingHighlight.visible = true
    pendingHighlight.frame = pendingButton.frame
  end
end

local function setupUI()
  busNum = tonumber(self.tag) or 1
  pendingFxNum = nil
  paintAllButtons()
end

function onReceiveNotify(key, value)
  if key == "setup_ui" then
    setupUI()
  elseif key == "set_pending_fx" then
    local fxNum = tonumber(value)
    if fxNum and fxNum >= 1 and fxNum <= #effects and isEffectAvailable(fxNum) then
      pendingFxNum = fxNum
    else
      pendingFxNum = nil
    end
    paintAllButtons()
  end
end

function init()
  for i = 1, #self.children do
    local child = self.children[i]
    if child.name ~= "pending_fx_highlight" then
      child.script = buttonScript
    end
  end

  setupUI()
end
