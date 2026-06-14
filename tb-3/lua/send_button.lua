-- send_button.lua
-- Injected into any BUTTON named 'send_button'.
-- On press: notifies root to send the current TouchOSC patch state to the TB-3.
-- The button should be a direct child of the root GROUP ('group').

function onValueChanged(key)
  -- self.values, not bare 'values' — TouchOSC Lua 5.1 doesn't expose it as a global.
  if key == "x" and self.values.x == 1 then
    root:notify("send_patch_to_device", 1)
  end
end
