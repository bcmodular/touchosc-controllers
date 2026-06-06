-- porta_radio_btn.lua
-- Latch BUTTON representing one portamento mode option.
-- tag: "val:0" = LEGATO,  "val:1" = ALWAYS
--
-- User press → notifies root ("porta_mode_set") which sends SysEx and
-- re-notifies both buttons via "porta_mode_updated" for mutual exclusion.
--
-- External update via "porta_mode_updated" notify (from parseSpecial or root)
-- → silently sets self.values.x without triggering SysEx.

local updating = false

function onValueChanged(key)
  if key ~= "x" then return end
  if updating then return end

  local valStr = self.tag:match("val:(%d+)")
  if not valStr then return end
  local val = tonumber(valStr)

  if self.values.x > 0.5 then
    -- User activated: let root send SysEx and handle mutual exclusion.
    root:notify("porta_mode_set", valStr)
  else
    -- User pressed the already-active button (toggle off): re-latch to prevent
    -- both buttons being unlit at the same time.
    local sibling_name = (val == 0) and "porta_always_btn" or "porta_legato_btn"
    local sibling = root:findByName(sibling_name, true)
    if not sibling or sibling.values.x < 0.5 then
      -- No other option is active; keep this one lit.
      updating = true
      self.values.x = 1
      updating = false
    end
  end
end

function onReceiveNotify(key, value)
  if key ~= "porta_mode_updated" then return end
  local v      = tonumber(value) or 0
  local my_val = tonumber(self.tag:match("val:(%d+)")) or -1
  -- Silently set x so onValueChanged does not re-fire SysEx.
  updating = true
  self.values.x = (v == my_val) and 1 or 0
  updating = false
end
