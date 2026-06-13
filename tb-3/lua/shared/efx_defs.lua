-- efx_defs.lua — TouchOSC Shared Script (loaded via require("efx_defs")).
--
-- Canonical, single source of truth for all EFX type / slot / button layout.
-- Consumed by:
--   • patch_manager.lua (root chunk) → derives EFX_SLOT_OFFSETS_SHARED/_SPECIAL
--     (slot byte offsets only — keeps the root chunk lean).
--   • efx_section.lua (per-node chunk) → rebuilds TYPE_DEFS, resolving each
--     slot's `display` STRING KEY to a local display function (the sp404
--     controls_info.lua pattern — display fns stay local to efx_section so the
--     shared script remains pure data and never crosses chunks as a function).
--
-- Why this exists: before Task 2.2b the slot byte offsets were hand-mirrored in
-- BOTH chunks (TYPE_DEFS `off=` ↔ EFX_SLOT_OFFSETS_*). The two chunks cannot see
-- each other, so any edit to one without the other caused silent assign-mode or
-- BCR-routing bugs. Now each slot is defined exactly ONCE, here.
--
-- Shared Scripts are INDEPENDENT chunks: this file may use only its own locals,
-- cannot read a requiring control's locals, cannot require() another shared
-- script, and crosses the chunk boundary only via the table it returns.
--
-- ───────────────────────────────────────────────────────────────────────────
-- Slot row : { off, name, max [, display] [, default] [, disabledBy] }
--   off        : block-relative byte offset (0-based) — THE canonical offset.
--   name       : on-screen slot label.
--   max        : full-scale raw value (fader 0..1 maps to 0..max).
--   display    : STRING KEY into efx_section's local display-fn dispatch table;
--                omit for plain integer display.
--   default    : fader default value (0..1); omit ⇒ 0.
--   disabledBy : list of offsets whose nonzero value greys this slot.
--   Positional `nil` holes are significant — they reserve a hidden slot index
--   (consumers iterate 1..12, never ipairs). Keep them.
--
-- Button row (btns[i] = action for on-screen B(i+1)) :
--   { off, name, action [, val] }  — action "set" (radio) or "toggle".
--   Positional nil holes place buttons on the bottom row (B5–B8).
--
-- Types 0–8 (SHARED) are identical for EFX1 and EFX2. Types 9/10 live in
-- SPECIAL[efxNum] (EFX1: 9 PITCH SHIFT, 10 EQ; EFX2: 9 REVERB).
-- ───────────────────────────────────────────────────────────────────────────

local M = {}

M.SHARED = {

  [0] = { name = "BYPASS" },

  -- 1: COMP — Compressor/Sustainer
  [1] = { name = "COMP",
    swOff = 0x01,
    slots = {
      {off=0x04, name="THRESHOLD", max=40,  display="dispThreshold"},
      {off=0x05, name="RATIO",     max=13,  display="dispRatio"},
      {off=0x02, name="ATTACK",    max=124, display="dispCsAttack"},
      {off=0x03, name="RELEASE",   max=124, display="dispCsRelease"},
      {off=0x06, name="KNEE",      max=9,   display="dispKnee"},
      {off=0x07, name="GAIN",      max=80,  display="dispDb40",      default=0.5},
      {off=0x08, name="BALANCE",   max=100, display="dispBipolar50", default=0.5},
    },
    btns = {},
  },

  -- 2: RING MOD
  [2] = { name = "RING MOD",
    swOff = 0x09,
    slots = {
      {off=0x0A, name="FREQ",    max=127},
      {off=0x0B, name="SENS",    max=127},
      {off=0x0F, name="BALANCE", max=100, display="dispBipolar50", default=0.5},
      {off=0x10, name="LEVEL",   max=127},
      {off=0x0D, name="EQ LOW",  max=30,  display="dispDb15",      default=0.5},
      {off=0x0E, name="EQ HIGH", max=30,  display="dispDb15",      default=0.5},
    },
    btns = {
      nil, nil, nil,
      {off=0x0C, name="UP",   action="set", val=0},
      {off=0x0C, name="DOWN", action="set", val=1},
    },
  },

  -- 3: BIT CRUSH
  [3] = { name = "BIT CRUSH",
    swOff = 0x11,
    slots = {
      {off=0x12, name="FILTER",    max=127},
      {off=0x13, name="SAMP RATE", max=127},
      {off=0x17, name="LEVEL",     max=127},
      nil,
      {off=0x15, name="EQ LOW",    max=30, display="dispDb15", default=0.5},
      {off=0x16, name="EQ HIGH",   max=30, display="dispDb15", default=0.5},
    },
    btns = {},
  },

  -- 4: TREMOLO
  [4] = { name = "TREMOLO",
    swOff = 0x18,
    slots = {
      {off=0x1C, name="BPM SYNC", max=20,  display="dispBpmDiv"},
      {off=0x1B, name="RATE",     max=100, display="dispRate", disabledBy={0x1C}},
      nil, nil,
      {off=0x1E, name="DEPTH",    max=100},
      {off=0x19, name="TYPE",     max=5,   display="dispTrType"},
      {off=0x20, name="LEVEL",    max=100},
      {off=0x1A, name="PHASE",    max=100, display="dispPhase"},
      {off=0x1D, name="SHAPE",    max=100},
    },
    btns = {
      nil, nil, nil,
      {off=0x1F, name="TREMOLO", action="set", val=0},
      {off=0x1F, name="PAN",     action="set", val=1},
    },
  },

  -- 5: CHORUS
  [5] = { name = "CHORUS",
    swOff = 0x21,
    slots = {
      {off=0x24, name="BPM SYNC", max=20,  display="dispBpmDiv"},
      {off=0x23, name="RATE",     max=100, display="dispRate", disabledBy={0x24}},
      nil, nil,
      {off=0x25, name="DEPTH",    max=100},
      {off=0x26, name="PRE DLY",  max=80,  display="dispMs"},
      {off=0x29, name="LEVEL",    max=100},
      {off=0x27, name="HPF",      max=17,  display="dispHPF"},
      {off=0x28, name="LPF",      max=14,  display="dispLPF", default=1.0},
    },
    btns = {
      nil, nil, nil,
      {off=0x22, name="MONO",    action="set", val=0},
      {off=0x22, name="STEREO1", action="set", val=1},
      {off=0x22, name="STEREO2", action="set", val=2},
    },
  },

  -- 6: FLANGER
  [6] = { name = "FLANGER",
    swOff = 0x2A,
    slots = {
      {off=0x2C, name="BPM SYNC",   max=20,  display="dispBpmDiv"},
      {off=0x2B, name="RATE",       max=100, display="dispRate", disabledBy={0x2C}},
      nil, nil,
      {off=0x2D, name="DEPTH",      max=100},
      {off=0x2E, name="MANUAL",     max=100, display="dispBipolar50", default=0.5},
      {off=0x2F, name="RESONANCE",  max=100},
      {off=0x30, name="SEPARATION", max=100},
      {off=0x31, name="HPF",        max=10,  display="dispFLHPF"},
      {off=0x32, name="EFX LVL",    max=100},
      {off=0x33, name="DIRECT LVL", max=100},
    },
    btns = {},
  },

  -- 7: PHASER
  [7] = { name = "PHASER",
    swOff = 0x34,
    slots = {
      {off=0x37, name="BPM SYNC",   max=20,  display="dispBpmDiv"},
      {off=0x36, name="RATE",       max=100, display="dispRate", disabledBy={0x37, 0x3B}},
      {off=0x3B, name="STEP RATE",  max=20,  display="dispBpmDiv"},
      nil,
      {off=0x38, name="DEPTH",      max=100},
      {off=0x39, name="MANUAL",     max=100, display="dispBipolar50", default=0.5},
      {off=0x3A, name="RESONANCE",  max=127},
      {off=0x3C, name="EFX LVL",    max=100},
      {off=0x3D, name="DIRECT LVL", max=100},
    },
    btns = {
      nil, nil, nil,
      {off=0x35, name="4STAGE",  action="set", val=0},
      {off=0x35, name="8STAGE",  action="set", val=1},
      {off=0x35, name="12STAGE", action="set", val=2},
      {off=0x35, name="BI-PH",   action="set", val=3},
    },
  },

  -- 8: DELAY
  [8] = { name = "DELAY",
    swOff = 0x3E,
    slots = {
      {off=0x42, name="BPM SYNC",   max=13,  display="dispBpmDiv"},
      {off=0x40, name="TIME",       max=100, display="dispMs", disabledBy={0x42}},
      nil, nil,
      {off=0x41, name="TAP TIME",   max=100, display="dispPct"},
      {off=0x43, name="FEEDBACK",   max=100},
      {off=0x44, name="LPF",        max=14,  display="dispLPF", default=1.0},
      {off=0x45, name="EFX LVL",    max=100},
      {off=0x46, name="DIRECT LVL", max=100},
    },
    btns = {
      nil, nil, nil,
      {off=0x3F, name="SINGLE", action="set", val=0},
      {off=0x3F, name="PAN",    action="set", val=1},
      {off=0x3F, name="STEREO", action="set", val=2},
    },
  },
}

M.SPECIAL = {

  -- EFX1-specific types
  [1] = {

    -- 9: PITCH SHIFT (EFX1 only)
    [9] = { name = "PITCH SHIFT",
      swOff = 0x47,
      slots = {
        {off=0x49, name="PITCH 1",    max=48,  display="dispPitchSt", default=0.5},
        {off=0x4A, name="PRE DLY 1",  max=100, display="dispMs"},
        {off=0x4C, name="EFX LVL 1",  max=100},
        {off=0x4B, name="FEEDBACK",   max=100},
        {off=0x4D, name="PITCH 2",    max=48,  display="dispPitchSt", default=0.5},
        {off=0x4E, name="PRE DLY 2",  max=100, display="dispMs"},
        {off=0x50, name="EFX LVL 2",  max=100},
        {off=0x51, name="DIRECT LVL", max=100},
      },
      btns = {
        nil, nil, nil,
        {off=0x48, name="1MONO",   action="set", val=0},
        {off=0x48, name="2MONO",   action="set", val=1},
        {off=0x48, name="2STEREO", action="set", val=2},
      },
    },

    -- 10: EQ (EFX1 only)
    [10] = { name = "EQ",
      swOff = 0x53,
      slots = {
        {off=0x54, name="LOW CUT",  max=17, display="dispHPF"},
        {off=0x55, name="LOW GAIN", max=40, display="dispDb20",  default=0.5},
        {off=0x5C, name="HI CUT",   max=14, display="dispLPF",   default=1.0},
        {off=0x5D, name="HI GAIN",  max=40, display="dispDb20",  default=0.5},
        {off=0x56, name="LM FREQ",  max=27, display="dispEQFreq"},
        {off=0x57, name="LM Q",     max=5,  display="dispEQQ"},
        {off=0x58, name="LM GAIN",  max=40, display="dispDb20",  default=0.5},
        nil,
        {off=0x59, name="HM FREQ",  max=27, display="dispEQFreq"},
        {off=0x5A, name="HM Q",     max=5,  display="dispEQQ"},
        {off=0x5B, name="HM GAIN",  max=40, display="dispDb20",  default=0.5},
        {off=0x5E, name="LEVEL",    max=40, display="dispDb20",  default=0.5},
      },
      btns = {},
    },
  },

  -- EFX2-specific types
  [2] = {

    -- 9: REVERB (EFX2 only)
    [9] = { name = "REVERB",
      swOff = 0x47,
      slots = {
        {off=0x49, name="TIME",       max=99,  display="dispRevTime"},
        {off=0x4A, name="PRE DLY",    max=100, display="dispMs"},
        {off=0x4D, name="DENSITY",    max=10},
        {off=0x50, name="SPRING SNS", max=100},
        {off=0x4B, name="HPF",        max=17,  display="dispHPF"},
        {off=0x4C, name="LPF",        max=14,  display="dispLPF", default=1.0},
        {off=0x4E, name="EFX LVL",    max=100},
        {off=0x4F, name="DIRECT LVL", max=100},
      },
      btns = {
        {off=0x48, name="AMBIENT", action="set", val=0},
        {off=0x48, name="ROOM",    action="set", val=1},
        {off=0x48, name="HALL 1",  action="set", val=2},
        {off=0x48, name="HALL 2",  action="set", val=3},
        {off=0x48, name="PLATE",   action="set", val=4},
        {off=0x48, name="SPRING",  action="set", val=5},
        {off=0x48, name="MOD",     action="set", val=6},
      },
    },
  },
}

return M
