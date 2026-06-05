-- efx_chooser_button.lua
-- Injected into all type-select buttons in efx_1_chooser and efx_2_chooser.
-- Button name = type index (1=CS/COMP, 2=RM, ..., 10=EQ for EFX1, 9=RV for EFX2).
-- Pressing an already-active type notifies the section, which interprets it as BYPASS.
-- The section (grandparent) owns all radio-state management.

function onValueChanged(key)
  if key ~= "x" or self.values.x < 0.5 then return end
  local typeIdx = tonumber(self.name) or 1
  -- Walk up: button → efx_N_chooser GROUP → efxN_section GROUP
  self.parent.parent:notify("type_set", typeIdx)
end
