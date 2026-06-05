-- receive_button.lua
-- Injected into any BUTTON named 'receive_button'.
-- On press: notifies root to send all 11 RQ1 dump requests to the TB-3.
-- The button should be a direct child of the root GROUP ('group').

function onValueChanged(key)
  if key == "x" and values.x == 1 then
    self.parent:notify("request_patch_dump", 1)
  end
end
