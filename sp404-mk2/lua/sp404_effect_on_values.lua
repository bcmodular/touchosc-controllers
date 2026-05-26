-- Shared SP-404 CC 83 "effect on" values per effect index and bus (keep in sync across consumers).
-- Effect index matches fx_selector_button_group effects[] (1-based) and controls_info array keys.

local EFFECT_NAMES = {
  "Filter + Drive", "Resonator", "Sync Delay", "Isolator", "DJFX Looper", "Scatter",
  "Downer", "Ha-Dou", "Ko-Da-Ma", "Zan-Zou", "To-Gu-Ro", "SBF",
  "Stopper", "Tape Echo", "TimeCtrlDly", "Super Filter", "WrmSaturator", "303 VinylSim",
  "404 VinylSim", "Cassette Sim", "Lo-fi", "Reverb", "Chorus", "JUNO Chorus",
  "Flanger", "Phaser", "Wah", "Slicer", "Tremolo/Pan", "Chromatic PS",
  "Hyper-Reso", "Ring Mod", "Crusher", "Overdrive", "Distortion", "Equalizer",
  "Compressor", "SX Reverb", "SX Delay", "Cloud Delay", "Back Spin", "DJFX Delay",
  "Auto Pitch", "Vocoder", "Harmony", "Gt Amp Sim"
}

local EFFECT_ON_MIDI_VALUES = {
  {1, 10, 0}, {2, 17, 0}, {3, 23, 0}, {4, 8, 0}, {5, 35, 0},
  {6, 36, 0}, {7, 5, 10}, {8, 21, 0}, {9, 25, 0}, {10, 22, 0},
  {11, 34, 0}, {12, 16, 0}, {13, 0, 0}, {14, 26, 0}, {15, 24, 8},
  {16, 9, 0}, {17, 11, 11}, {18, 1, 12}, {19, 2, 13}, {20, 3, 14},
  {21, 4, 15}, {22, 20, 7}, {23, 27, 5}, {24, 28, 6}, {25, 29, 0},
  {26, 30, 0}, {27, 31, 0}, {28, 32, 0}, {29, 33, 0}, {30, 19, 9},
  {31, 18, 0}, {32, 15, 0}, {33, 14, 0}, {34, 12, 0}, {35, 13, 0},
  {36, 7, 16}, {37, 6, 17}, {38, 37, 0}, {39, 38, 0}, {40, 39, 0},
  {41, 0, 0}, {42, 40, 0}, {0, 0, 1}, {0, 0, 2}, {0, 0, 3}, {0, 0, 4}
}

function getMidiIndexForBus(busNum)
  busNum = tonumber(busNum) or 1
  if busNum == 1 or busNum == 2 then
    return 1
  elseif busNum == 3 or busNum == 4 then
    return 2
  end
  return 3
end

function resolveBusFxNum(busSettings)
  busSettings = busSettings or {}
  local fxNum = tonumber(busSettings.fxNum) or 0
  if fxNum ~= 0 then
    return fxNum
  end
  local fxName = busSettings.fxName
  if not fxName or fxName == 'Choose FX...' then
    return 0
  end
  for i, name in ipairs(EFFECT_NAMES) do
    if name == fxName then
      return i
    end
  end
  return 0
end

function getEffectOnMidiValue(fxNum, busNum)
  fxNum = tonumber(fxNum) or 0
  if fxNum == 0 then
    return 0
  end
  local row = EFFECT_ON_MIDI_VALUES[fxNum]
  if not row then
    return 0
  end
  return row[getMidiIndexForBus(busNum)] or 0
end

function isEffectOnMidiAvailable(fxNum, busNum)
  return getEffectOnMidiValue(fxNum, busNum) ~= 0
end
