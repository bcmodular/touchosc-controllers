-- params.lua — P-6 granular parameter definitions
-- Injected into the hidden params node; encoder_mapper reads from params.tag
--
-- Each parameter entry:
--   name       = display name for the encoder
--   cc         = P-6 MIDI CC number
--   display    = mapping function name (see encoder_mapper.lua)
--   row        = row index (1=top, 2-5=rows 1-4)
--   col        = column position (1-8)

local PARAMS = {
  -- TOP ROW: Granular Oscillator
  {name = "Coarse Tune",  cc = 76, display = "getCoarseTune",  row = 1, col = 1},
  {name = "Fine Tune",    cc = 18, display = "getFineTune",    row = 1, col = 2},
  {name = "Detune",       cc = 13, display = "getZeroHundred", row = 1, col = 3},
  {name = "Grains",       cc = 21, display = "getGrains",      row = 1, col = 4},
  {name = "Grain Shape",  cc = 15, display = "getZeroHundred", row = 1, col = 5},
  {name = "Grain Size",   cc = 23, display = "getZeroHundred", row = 1, col = 6},
  {name = "Spread",       cc = 25, display = "getZeroHundred", row = 1, col = 7},
  {name = "Start Mode",   cc = 79, display = "getStartMode",   row = 1, col = 8},

  -- ROW 1: Playback + Tone Envelope
  {name = "Head Pos",     cc = 19, display = "getZeroHundred", row = 2, col = 1},
  {name = "Head Speed",   cc = 20, display = "getZeroHundred", row = 2, col = 2},
  {name = "Time KF",      cc = 16, display = "getZeroHundred", row = 2, col = 3},
  {name = "Reverse Prob", cc =  3, display = "getPercent",     row = 2, col = 4},
  {name = "Time Jitter",  cc = 68, display = "getZeroHundred", row = 2, col = 5},
  {name = "T.Env Atk",    cc = 73, display = "getZeroHundred", row = 2, col = 6},
  {name = "T.Env Dec",    cc = 75, display = "getZeroHundred", row = 2, col = 7},
  {name = "T.Env Sus",    cc = 30, display = "getZeroHundred", row = 2, col = 8},

  -- ROW 2: Tone Envelope + Filter
  {name = "T.Env Rel",    cc = 72, display = "getZeroHundred", row = 3, col = 1},
  {name = "T.Env Time KF",cc = 77, display = "getZeroHundred", row = 3, col = 2},
  {name = "T.Env Mode",   cc = 29, display = "getTEnvMode",    row = 3, col = 3},
  {name = "Filter Cutoff", cc = 74, display = "getZeroHundred", row = 3, col = 4},
  {name = "Filter Reso",  cc = 71, display = "getZeroHundred", row = 3, col = 5},
  {name = "Filter Env",   cc = 24, display = "getBipolar",     row = 3, col = 6},
  {name = "Filter KF",    cc = 26, display = "getZeroHundred", row = 3, col = 7},
  {name = "Filter Vel",   cc = 78, display = "getZeroHundred", row = 3, col = 8},

  -- ROW 3: Filter/Lo-Fi/Amp/Output
  {name = "Filter Type",  cc = 12, display = "getFilterType",  row = 4, col = 1},
  {name = "Lo-Fi Sw",     cc = 87, display = "getOnOff",       row = 4, col = 2},
  {name = "Lo-Fi Amt",    cc = 17, display = "getZeroHundred", row = 4, col = 3},
  {name = "Amp Switch",   cc = 28, display = "getOnOff",       row = 4, col = 4},
  {name = "Send Reverb",  cc = 86, display = "getZeroHundred", row = 4, col = 5},
  {name = "Send Delay",   cc = 85, display = "getZeroHundred", row = 4, col = 6},
  {name = "Pan",          cc = 10, display = "getPan",         row = 4, col = 7},
  {name = "Level",        cc =  7, display = "getZeroHundred", row = 4, col = 8},

  -- ROW 4: Effects + Utility
  {name = "Reverb Time",  cc = 89, display = "getZeroHundred", row = 5, col = 1},
  {name = "Delay Time",   cc = 90, display = "getZeroHundred", row = 5, col = 2},
  {name = "Reverb Lvl",   cc = 91, display = "getZeroHundred", row = 5, col = 3},
  {name = "Delay Lvl",    cc = 92, display = "getZeroHundred", row = 5, col = 4},
  {name = "Level Jitter", cc = 14, display = "getZeroHundred", row = 5, col = 5},
  {name = "Auto Pan",     cc =  9, display = "getAutoPan",     row = 5, col = 6},
  {name = "Output Bus",   cc = 84, display = "getOutputBus",   row = 5, col = 7},
  {name = "Sample",       cc = 88, display = "getSample",      row = 5, col = 8},
}

-- Set tag immediately at script load time (not in init())
-- so other scripts can read it during their init()
self.tag = json.fromTable(PARAMS)
