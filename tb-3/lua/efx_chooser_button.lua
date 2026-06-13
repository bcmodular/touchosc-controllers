-- efx_chooser_button.lua
-- Injected into all type-select buttons in efx_1_chooser and efx_2_chooser.
-- Button name = type index (1=COMP, 2=RING MOD, ..., 10=EQ for EFX1, 9=REVERB for EFX2).
--
-- Toggle Release mode: fires on both x=1 (select) and x=0 (deselect).
-- Re-pressing the currently active type tells the section to go to BYPASS.
-- Guards against re-entrant programmatic radio-state updates from efx_section.lua
-- via the "prog" flag stored in the grandparent section's tag property.

function onValueChanged(key)
  if key ~= "x" then return end
  -- self.parent = efx_N_chooser GROUP; self.parent.parent = efxN_section GROUP
  if self.parent.parent.tag == "prog" then return end
  local efxNum = tonumber(self.parent.parent.name:match("efx(%d+)_section")) or 1
  root:notify("efx_type_select", efxNum .. "," .. self.name)
end
