-- morph_amount_fader.lua
-- Sends morph blend amount (0–127) to root when the fader moves.

function onValueChanged(key, value)
  if key == 'x' then
    root:notify("morph_amount_changed", math.floor(value * 127 + 0.5))
  end
end
