local MORPH_DEBUG = true

local function morphBusFromControl(self)
  local busGroup = self.parent and self.parent.parent and self.parent.parent.parent
  if not busGroup then
    return nil, nil
  end
  local busNum = tonumber(busGroup.name:match('bus(%d+)_group'))
  if not busNum then
    busNum = tonumber((json.toTable(busGroup.tag) or {}).busNum)
  end
  return busNum, busGroup
end

function onValueChanged(key, value)
  if key ~= 'x' then
    return
  end
  local busNum, busGroup = morphBusFromControl(self)
  local amount = math.floor(self.values.x * 127 + 0.5)
  if MORPH_DEBUG then
    print('[Morph]', string.format('morph_amount_fader bus=%s amount=%d', tostring(busNum), amount))
  end
  if not busNum or not busGroup then
    return
  end
  local tag = json.toTable(busGroup.tag) or {}
  if amount == (tonumber(tag.morphAmount) or 0) then
    return
  end
  local grid = busGroup:findByName('preset_grid', true)
  if grid then
    grid:notify('set_morph_amount', { busNum, amount })
  end
end
