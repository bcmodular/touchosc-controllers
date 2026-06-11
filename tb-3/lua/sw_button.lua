-- sw_button.lua
-- Injected into every BUTTON node named 'sw_button' (VCO source switches,
-- LFO BPM SYNC, LFO RETRIGGER, PORTA SW).
--
-- Notifies root with key "sw_toggled" and value "section,enc,v"
-- where section = self.parent.parent.name  (e.g. "vco_group")
--       enc     = self.parent.name         (e.g. "saw_enc")
--       v       = 0 or 1
--
-- Also notifies root with "sw_touched" (same section,enc) for parameter
-- assignment mode.  When assign mode is active, root sends "assign_revert"
-- back to undo the value change so assignment doesn't actually toggle the switch.

local updating = false

local LIT_TEXT = "000000FF"   -- black on yellow button
local OFF_TEXT = "FFFFFFFF"   -- white on dark background

-- Only these encoder groups have overlay labels; TouchOSC warns on missing .children[].
local OVERLAY_LABELS = {
  lfo_rate_enc      = {"bpm_sync_label1", "bpm_sync_label2"},
  lfo_cv_offset_enc = {"retrig_label"},
}

local function refreshOverlayLabels()
  local names = OVERLAY_LABELS[self.parent.name]
  if not names then return end
  local lit = (math.floor(self.values.x + 0.5) == 1)
  local clr = Color.fromHexString(lit and LIT_TEXT or OFF_TEXT)
  for _, name in ipairs(names) do
    local lbl = self.parent.children[name]
    if lbl then lbl.textColor = clr end
  end
end

function onValueChanged(key)
  if key ~= "x" then return end
  refreshOverlayLabels()
  if updating then return end
  -- Notify root for parameter assignment mode.
  root:notify("sw_touched",
    self.parent.parent.name .. "," .. self.parent.name)
  root:notify("sw_toggled",
    self.parent.parent.name .. "," ..
    self.parent.name        .. "," ..
    tostring(math.floor(self.values.x + 0.5)))
end

function onReceiveNotify(key, value)
  if key ~= "assign_revert" then return end
  -- Flip the value back to its pre-touch state without triggering
  -- sw_touched / sw_toggled (the 'updating' guard suppresses them).
  updating = true
  self.values.x = 1 - self.values.x
  updating = false
end

function init()
  refreshOverlayLabels()
end
