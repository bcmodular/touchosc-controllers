local sidechainScript = [[
local busGroupName = root:findByName('edit_mode', true).tag
local busGroup = root:findByName(busGroupName, true)
local busCompressorSidechain = busGroup:findByName('compressor_sidechain', true)
local bankSelect = self:findByName('bank_select')

function onReceiveNotify(key, value)
  if key == 'update_bus' then
    busGroupName = root:findByName('edit_mode', true).tag
    busGroup = root:findByName(busGroupName, true)
    busCompressorSidechain = busGroup:findByName('compressor_sidechain', true)
  elseif key == 'update_value' then
    busCompressorSidechain:notify('update_value', value)
  elseif key == 'store_defaults' then
    busCompressorSidechain:notify('store_defaults', value)
  elseif key == 'recall_defaults' then
    busCompressorSidechain:notify('recall_defaults')
  elseif key == 'store_preset' then
    busCompressorSidechain:notify('store_preset', value)
  elseif key == 'recall_preset' then
    busCompressorSidechain:notify('recall_preset', value)
  else
    busCompressorSidechain:notify(key, value)
  end
end

function onValueChanged(key, value)
  if key == 'touch' then
    print('bank changed:', key, value, self.values.touch)
    busCompressorSidechain:notify('update_value', {'trigger_midi_channel', tonumber(bankSelect.tag) - 1})
    self.values.touch = false
  end
end
]]

function init()
  local debugMode = root:findByName('debug_mode').values.x
  if debugMode == 1 then
    local sidechain = root:findByName('edit_compressor_sidechain', true)
    sidechain.script = sidechainScript
  end
end