local sidechainScript = [[
local busGroupName = root:findByName('edit_mode', true).tag
local busGroup = root:findByName(busGroupName, true)
local busCompressorSidechain = busGroup:findByName('compressor_sidechain', true)
local bankSelect = self:findByName('bank_select')

local function toggleFaderColours(sideChainOn)
  local sustainFader = self.parent:findByName('sustain_fader', true)
  local ratioFader = self.parent:findByName('ratio_fader', true)
  local levelFader = self.parent:findByName('level_fader', true)

  if sideChainOn then
    print('Sidechain is on')
    sustainFader.color = Color.fromHexString("2486FFFF")
    ratioFader.color = Color.fromHexString("2486FFFF")
    levelFader.color = Color.fromHexString("2486FFFF")
  else
    print('Sidechain is off')
    sustainFader.color = Color.fromHexString("FFA61AFF")
    ratioFader.color = Color.fromHexString("FFA61AFF")
    levelFader.color = Color.fromHexString("FFA61AFF")
  end
end

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
  elseif key == 'toggle_sidechain' then
    toggleFaderColours(value == 1)
    busCompressorSidechain:notify('toggle_sidechain', value)
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