-- assign_slot_btn.lua
-- Injected into each of the four parameter assign slot BUTTON nodes:
--   assign_xy_mod_btn, assign_effect_knob_btn, assign_pad_x_btn, assign_pad_y_btn
--
-- tag format: "slot:xy_mod" | "slot:effect_knob" | "slot:pad_x" | "slot:pad_y"
--
-- These are TOGGLE (latch) buttons (buttonType=1).  The lit state shows that
-- assign mode is active for this slot.
--
-- Press while unlit → root enters assign mode; label shows "ASSIGNING <slot>".
--   User then touches any encoder to assign it; mode exits automatically.
-- Press while lit → root cancels assign mode (same-slot toggle-off).
--
-- Root broadcasts "assign_mode_changed" with the active slot name (or "")
-- so each button can self-update without any mutual-exclusion logic here.
--
-- updating flag: prevents the programmatic x change in onReceiveNotify from
-- re-triggering onValueChanged and cascading a spurious notify back to root.

local updating = false

function onValueChanged(key)
  if key ~= "x" then return end
  if updating then return end

  local slot = self.tag:match("slot:(.+)")
  if not slot then return end

  if self.values.x >= 0.5 then
    -- User turned button on: enter assign mode for this slot.
    root:notify("assign_slot_select", slot)
  else
    -- User turned button off (pressed the active button again): cancel.
    root:notify("assign_slot_select", "")
  end
end

function onReceiveNotify(key, value)
  if key ~= "assign_mode_changed" then return end
  local slot = self.tag:match("slot:(.+)")
  -- value = currently active slot name, or "" for none.
  local should_lit = (value == slot)
  if (self.values.x >= 0.5) ~= should_lit then
    updating = true
    self.values.x = should_lit and 1 or 0
    updating = false
  end
end
