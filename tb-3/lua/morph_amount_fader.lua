-- morph_amount_fader.lua
-- Sends raw 0.0–1.0 blend factor to root when the fader moves.

function onValueChanged(key)
  if key == 'x' then
    root:notify("morph_amount_changed", self.values.x)
  end
end
