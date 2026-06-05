-- efx_chooser_button.lua
-- Injected into buttons "1" (PREV) and "2" (NEXT) in efx_1_chooser / efx_2_chooser.
-- Sends type_step to the sibling efxN_section node via root notify relay.

function onValueChanged(key)
  if key ~= "x" or self.values.x < 0.5 then return end
  -- self.parent.name = "efx_1_chooser" or "efx_2_chooser"
  local efxNum = tonumber(self.parent.name:match("efx_(%d+)_chooser")) or 1
  local dir    = (tonumber(self.name) == 1) and -1 or 1  -- btn 1 = prev, btn 2 = next
  root:notify("efx_type_step", efxNum .. "," .. dir)
end
