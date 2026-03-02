-- config.lua — MIDI channel and BCR2000 CC configuration
-- Injected into the hidden config node; other scripts read from config.tag

local CONFIG = {
  -- MIDI channels (0-indexed for sendMIDI)
  p6Channel = 4,       -- P-6 granular = channel 5 (0-indexed: 4)
  bcrChannel = 0,      -- BCR2000 = channel 1 (0-indexed: 0)

  -- BCR2000 connection index (set to match your MIDI routing)
  -- Used for loop prevention in onReceiveMIDI
  bcrConnectionIndex = 1,

  -- BCR2000 Turn CC numbers per row (8 per row)
  bcrTurnCCs = {
    -- Top row (encoder group 1): Granular Osc
    { 1,  2,  3,  4,  5,  6,  7,  8},
    -- Row 1 (encoder group 2): Playback + Tone Env
    { 9, 10, 11, 12, 13, 14, 15, 16},
    -- Row 2 (encoder group 3): Tone Env + Filter
    {17, 18, 19, 20, 21, 22, 23, 24},
    -- Row 3 (encoder group 4): Filter/Lo-Fi/Amp/Output
    {25, 26, 27, 28, 29, 30, 31, 32},
    -- Row 4 (encoder group 5): Effects + Utility
    {65, 66, 67, 68, 69, 70, 71, 72},
  },

  -- BCR2000 Push CC numbers per row (for push-encoder actions)
  bcrPushCCs = {
    {33, 34, 35, 36, 37, 38, 39, 40},
    {41, 42, 43, 44, 45, 46, 47, 48},
    {49, 50, 51, 52, 53, 54, 55, 56},
    {57, 58, 59, 60, 61, 62, 63, 64},
    {73, 74, 75, 76, 77, 78, 79, 80},
  },

  -- BCR2000 button CCs (for preset recall)
  bcrButtonCCs = {105, 106, 107, 108},
}

-- Set tag immediately at script load time (not in init())
-- so other scripts can read it during their init()
self.tag = json.fromTable(CONFIG)
