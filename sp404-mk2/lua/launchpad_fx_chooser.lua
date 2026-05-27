-- Launchpad-only effect chooser mode (8x6 grid) for selecting bus FX.
-- Uses sp404_effect_on_values.lua helpers for availability and names.

local FX_CHOOSER_COLUMNS = 8
local FX_CHOOSER_ROWS = 6
local FX_CHOOSER_DOUBLE_TAP_WINDOW_SEC = 0.35
local FX_CHOOSER_EFFECT_NAMES_FALLBACK = {
  "Filter + Drive", "Resonator", "Sync Delay", "Isolator", "DJFX Looper", "Scatter",
  "Downer", "Ha-Dou", "Ko-Da-Ma", "Zan-Zou", "To-Gu-Ro", "SBF",
  "Stopper", "Tape Echo", "TimeCtrlDly", "Super Filter", "WrmSaturator", "303 VinylSim",
  "404 VinylSim", "Cassette Sim", "Lo-fi", "Reverb", "Chorus", "JUNO Chorus",
  "Flanger", "Phaser", "Wah", "Slicer", "Tremolo/Pan", "Chromatic PS",
  "Hyper-Reso", "Ring Mod", "Crusher", "Overdrive", "Distortion", "Equalizer",
  "Compressor", "SX Reverb", "SX Delay", "Cloud Delay", "Back Spin", "DJFX Delay",
  "Auto Pitch", "Vocoder", "Harmony", "Gt Amp Sim"
}

local fxChooserActive = false
local fxChooserBusNum = 1
local fxChooserPendingFx = nil
local fxChooserLastTapFx = nil
local fxChooserLastTapAt = 0

local function launchpadFxChooserAllPadsOff()
  local sysexMessage = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0E, 0x00, 0xF7 }
  sendMIDI(sysexMessage, LAUNCHPAD_MIDI_CONNECTION)
end

local function launchpadChooserNowSec()
  return os.clock()
end

function launchpadFxChooserIsActive()
  return fxChooserActive
end

local function launchpadChooserBusButton(busNum)
  return 90 + busNum
end

function launchpadEffectIndexForNote(note)
  local col = note % 10
  local midiRow = math.floor(note / 10)
  local row = 9 - midiRow
  if col < 1 or col > FX_CHOOSER_COLUMNS then
    return nil
  end
  if row < 1 or row > FX_CHOOSER_ROWS then
    return nil
  end
  local fxIdx = (row - 1) * FX_CHOOSER_COLUMNS + col
  if fxIdx < 1 or fxIdx > #FX_CHOOSER_EFFECT_NAMES_FALLBACK then
    return nil
  end
  return fxIdx
end

local function fxChooserNameAt(index)
  if type(EFFECT_NAMES) == "table" and EFFECT_NAMES[index] then
    return EFFECT_NAMES[index]
  end
  return FX_CHOOSER_EFFECT_NAMES_FALLBACK[index]
end

local function launchpadFxChooserRefreshTouchOscPresets()
  local manager = root.children and root.children.preset_grid_manager
  if not manager then
    return
  end
  for busNum = 1, 5 do
    local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
    local busTag = busGroup and (json.toTable(busGroup.tag) or {}) or {}
    local fxNum = tonumber(busTag.fxNum) or 0
    manager:notify("refresh_presets_list", { busNum, fxNum })
  end
end

local function launchpadFxChooserNotifyPending(fxNum)
  local fxSelector = root:findByName("fx_selector_group", true)
  local selectorButtons = fxSelector and fxSelector:findByName("fx_selector_button_group", true)
  if selectorButtons then
    selectorButtons:notify("set_pending_fx", fxNum)
  end
end

function refreshLaunchpadFxChooserLeds()
  if not fxChooserActive then
    return
  end

  launchpadFxChooserAllPadsOff()

  local entries = {}
  for row = 1, FX_CHOOSER_ROWS do
    for col = 1, FX_CHOOSER_COLUMNS do
      local midiRow = 9 - row
      local note = midiRow * 10 + col
      local fxIdx = launchpadEffectIndexForNote(note)
      if fxIdx and isEffectOnMidiAvailable(fxIdx, fxChooserBusNum) then
        if fxChooserPendingFx == fxIdx then
          local pr, pg, pb = launchpadBusRgb(fxChooserBusNum, LAUNCHPAD_ON_BRIGHTNESS)
          table.insert(entries, note)
          table.insert(entries, pr)
          table.insert(entries, pg)
          table.insert(entries, pb)
        else
          local r, g, b = launchpadBusRgb(fxChooserBusNum, LAUNCHPAD_IDLE_BRIGHTNESS)
          table.insert(entries, note)
          table.insert(entries, r)
          table.insert(entries, g)
          table.insert(entries, b)
        end
      end
    end
  end

  local br, bg, bb = launchpadBusRgb(fxChooserBusNum, LAUNCHPAD_ON_BRIGHTNESS)
  table.insert(entries, launchpadChooserBusButton(fxChooserBusNum))
  table.insert(entries, br)
  table.insert(entries, bg)
  table.insert(entries, bb)

  sendLaunchpadLedRgbBatch(entries)
end

local function launchpadFxChooserCloseUi()
  local fxSelector = root:findByName("fx_selector_group", true)
  if fxSelector then
    fxSelector:notify("hide")
  end
end

function exitLaunchpadFxChooser()
  if not fxChooserActive then
    return
  end

  fxChooserActive = false
  fxChooserPendingFx = nil
  fxChooserLastTapFx = nil
  fxChooserLastTapAt = 0

  launchpadFxChooserNotifyPending(nil)
  launchpadFxChooserAllPadsOff()
  launchpadFxChooserCloseUi()
  if type(refreshLaunchpadControlLeds) == "function" then
    refreshLaunchpadControlLeds()
  else
    root:notify("launchpad_full_led_refresh")
  end
  local sceneManager = root.children and root.children.scene_manager
  if sceneManager then
    sceneManager:notify("refresh_all_scenes")
  end
  launchpadFxChooserRefreshTouchOscPresets()
end

function enterLaunchpadFxChooser(busNum)
  busNum = tonumber(busNum) or 1
  if busNum < 1 or busNum > 5 then
    return
  end
  if fxChooserActive and fxChooserBusNum == busNum then
    return
  end

  fxChooserActive = true
  fxChooserBusNum = busNum
  fxChooserPendingFx = nil
  fxChooserLastTapFx = nil
  fxChooserLastTapAt = 0

  local busGroup = root:findByName("bus" .. tostring(busNum) .. "_group", true)
  local onOffGroup = busGroup and busGroup:findByName("on_off_button_group", true)
  if onOffGroup then
    onOffGroup:notify("set_chooser_state", true)
  end
  launchpadFxChooserNotifyPending(nil)
  refreshLaunchpadFxChooserLeds()
end

local function launchpadFxChooserConfirm(fxIdx)
  local busGroup = root:findByName("bus" .. tostring(fxChooserBusNum) .. "_group", true)
  local fxName = fxChooserNameAt(fxIdx)
  if busGroup and fxName then
    busGroup:notify("set_fx", { fxIdx, fxName, false })
  end
  exitLaunchpadFxChooser()
end

function handleLaunchpadFxChooserNote(note, velocity)
  if not fxChooserActive then
    return false
  end

  local fxIdx = launchpadEffectIndexForNote(note)
  if not fxIdx then
    return true
  end
  if velocity <= 0 then
    return true
  end
  if not isEffectOnMidiAvailable(fxIdx, fxChooserBusNum) then
    return true
  end

  local now = launchpadChooserNowSec()
  local isDoubleTap = (fxChooserLastTapFx == fxIdx) and
    ((now - fxChooserLastTapAt) <= FX_CHOOSER_DOUBLE_TAP_WINDOW_SEC)

  if fxChooserPendingFx == fxIdx or isDoubleTap then
    launchpadFxChooserConfirm(fxIdx)
    return true
  end

  fxChooserPendingFx = fxIdx
  fxChooserLastTapFx = fxIdx
  fxChooserLastTapAt = now
  launchpadFxChooserNotifyPending(fxIdx)
  refreshLaunchpadFxChooserLeds()
  return true
end
