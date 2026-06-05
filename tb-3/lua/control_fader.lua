-- control_fader.lua
-- Injected into every RADIAL node named 'control_fader'.
-- Sends SysEx to the TB-3 when the fader moves, and updates value_label.
--
-- Notifies root with key "enc_moved" and value "section,enc,x"
-- where section = self.parent.parent.name (e.g. "vcf_group")
--       enc     = self.parent.name       (e.g. "vcf_cutoff_enc")
--       x       = self.values.x          (0.0–1.0 float)
--
-- Root looks up ENC_SEND_MAP[section .. "," .. enc] and sends SysEx.
-- Unknown encoders (e.g. EFX slots before Phase 4) are silently ignored.

function onValueChanged(key)
  if key ~= "x" then return end

  -- Update value_label with a 0–127 integer approximation.
  -- Refined display (signed, scaled max) can be added per-section in later phases.
  local lbl = self.parent.children["value_label"]
  if lbl then
    lbl.values.text = tostring(math.floor(self.values.x * 127 + 0.5))
  end

  root:notify("enc_moved",
    self.parent.parent.name .. "," ..
    self.parent.name        .. "," ..
    tostring(self.values.x))
end
