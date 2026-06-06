-- efx_section.lua
-- Injected into efx1_section and efx2_section GROUP nodes at build time.
-- Self-identifies as EFX1 (types 0–10) or EFX2 (types 0–9) from self.name.
--
-- Colour tiers (set dynamically via Color.fromHexString so all effects,
-- including Reverb whose type buttons span B2–B8, are coloured correctly):
--   SEL_HEX  — "selector" accent: chooser grid labels + type-option radio buttons
--   BASE_HEX — section base: knobs, SW, utility buttons (POLARITY…)
--
-- Toggle Release guard: self.tag = "prog" during all programmatic button value
-- writes so efx_button.lua / efx_chooser_button.lua can distinguish user presses
-- from re-entrant programmatic changes.
--
-- Text colour: label textColor flips black (ON_TXT) when button is active so
-- the text stays readable against the bright lit button background.
--
-- Slot display: each slot def can include a display(raw) function that converts
-- the raw SysEx value to a human-readable string (dB, Hz, ms, beat divisions…).
-- When absent, the raw integer is shown.

-- ---------------------------------------------------------------------------
-- Identity: EFX1 or EFX2
-- ---------------------------------------------------------------------------

local efxNum  = tonumber(self.name:match("efx(%d+)_section")) or 1
local BASE    = (efxNum == 1) and {0x10, 0x00, 0x10, 0x00}
                               or {0x10, 0x00, 0x12, 0x00}
local MAX_TYPE = (efxNum == 1) and 10 or 9

-- ---------------------------------------------------------------------------
-- Connection / channel constants
-- ---------------------------------------------------------------------------

local TB3_CONN = {false, false, false, false, false, true}  -- connection 6
local BCR_CONN = {false, true}                              -- connection 2
local BCR_CH   = 2                                          -- BCR2000 #2

-- ---------------------------------------------------------------------------
-- BCR CC maps
-- ---------------------------------------------------------------------------

local SLOT_CC, BTN_CC
if efxNum == 1 then
  SLOT_CC = {81,82,83,84, 89,90,91,92, 97,98,99,100}
  BTN_CC  = {65,66,67,68, 73,74,75,76}
else
  SLOT_CC = {85,86,87,88, 93,94,95,96, 101,102,103,104}
  BTN_CC  = {69,70,71,72, 77,78,79,80}
end

local TYPE_CC = (efxNum == 1) and 1 or 5

-- ---------------------------------------------------------------------------
-- Colour hex strings for Color.fromHexString (RRGGBBAA, 8 hex chars)
-- ---------------------------------------------------------------------------

local SEL_HEX  = (efxNum == 1) and "B3F2FFFF" or "FFA659FF"
local BASE_HEX = (efxNum == 1) and "33B3BFFF" or "D9611FFF"
local ON_TXT   = "000000FF"
local OFF_TXT  = "FFFFFFFF"

-- ---------------------------------------------------------------------------
-- SysEx helpers
-- ---------------------------------------------------------------------------

local function tb3Checksum(addrAndData)
  local sum = 0
  for _, b in ipairs(addrAndData) do sum = sum + b end
  return (0x100 - (sum % 256)) % 128
end

local function sendParam(off, value)
  local a1, a2, a3, a4 = BASE[1], BASE[2], BASE[3], BASE[4] + off
  local cs = tb3Checksum({a1, a2, a3, a4, value})
  sendMIDI({0xF0, 0x41, 0x10, 0x00, 0x00, 0x7B, 0x12,
            a1, a2, a3, a4, value, cs, 0xF7}, TB3_CONN)
end

local function sendBCRcc(cc, ccVal)
  sendMIDI({0xB0 + (BCR_CH - 1), cc, ccVal}, BCR_CONN)
end

-- ---------------------------------------------------------------------------
-- Module-level state
-- ---------------------------------------------------------------------------

local curType = 0
local rawData = {}

-- ---------------------------------------------------------------------------
-- Display functions
-- Source: Unofficial TB-3 FX Parameter Guide v1.07 (Dope Robot)
--
-- Each function takes a raw SysEx integer and returns a display string.
-- Referenced by name in TYPE_DEFS slot entries via the "display" field.
-- ---------------------------------------------------------------------------

-- Beat-division strings (index 1 = value 0 = "OFF", … index 21 = value 20)
-- Tremolo/Chorus/Flanger/Phaser BPM SYNC: values 0–20.
-- Delay BPM SYNC:                          values 0–13 (max=13 in slot def).
local BPM_DIVS = {
  "OFF",   "2",    "3/2",  "4/3",  "1",
  "3/4",   "2/3",  "1/2",  "3/8",  "1/3",
  "1/4",   "3/16", "1/6",  "1/8",  "3/32",
  "1/12",  "1/16", "3/64", "1/24", "1/32",
  "3/128"
}
local function dispBpmDiv(raw)
  return BPM_DIVS[raw + 1] or tostring(raw)
end

-- Signed dB (range straddles 0 — use explicit sign)
local function dispDb20(raw)     -- 0-40 → −20 dB…+20 dB
  local db = raw - 20
  return (db >= 0 and "+" or "") .. db .. " dB"
end
local function dispDb15(raw)     -- 0-30 → −15 dB…+15 dB
  local db = raw - 15
  return (db >= 0 and "+" or "") .. db .. " dB"
end
local function dispDb40(raw)     -- 0-80 → −40 dB…+40 dB  (COMP GAIN)
  local db = raw - 40
  return (db >= 0 and "+" or "") .. db .. " dB"
end
local function dispThreshold(raw) -- 0-40 → −40 dB…0 dB  (always ≤ 0)
  return (raw - 40) .. " dB"
end

-- Bipolar linear (centre = max/2)
local function dispBipolar50(raw) -- 0-100 → −50…+50
  local v = raw - 50
  return (v >= 0 and "+" or "") .. v
end

-- Compressor ratio lookup (0-13)
local CS_RATIOS = {
  "1:1.0","1:1.1","1:1.2","1:1.4","1:1.6","1:1.8",
  "1:2.0","1:2.5","1:3.2","1:4.0","1:5.6","1:8.0","1:16","1:INF"
}
local function dispRatio(raw)
  return CS_RATIOS[raw + 1] or tostring(raw)
end

-- Compressor knee (0-9)
local function dispKnee(raw)
  return raw == 0 and "Hard" or ("Soft " .. raw)
end

-- Compressor attack/release (0-124, linear approximation)
local function dispCsAttack(raw)   -- 0-124 → 0-800 ms
  return math.floor(raw / 124 * 800) .. " ms"
end
local function dispCsRelease(raw)  -- 0-124 → 0-8000 ms
  return math.floor(raw / 124 * 8000) .. " ms"
end

-- HPF table (0-17): Flat → 800 Hz  (shared by Chorus, Phaser, Reverb, EQ)
local HPF_FREQS = {
  "Flat","20 Hz","25 Hz","31 Hz","40 Hz","50 Hz","63 Hz","80 Hz","100 Hz",
  "125 Hz","160 Hz","200 Hz","250 Hz","315 Hz","400 Hz","500 Hz","630 Hz","800 Hz"
}
local function dispHPF(raw)
  return HPF_FREQS[raw + 1] or tostring(raw)
end

-- Flanger HPF (0-10): Flat → 800 Hz in 11 steps (condensed from standard table).
-- Exact frequencies are approximate — verify against hardware.
local FL_HPF_FREQS = {
  "Flat","20 Hz","40 Hz","80 Hz","125 Hz","200 Hz","315 Hz","500 Hz","630 Hz","710 Hz","800 Hz"
}
local function dispFLHPF(raw)
  return FL_HPF_FREQS[raw + 1] or tostring(raw)
end

-- LPF table (0-14): 630 Hz → Flat  (shared by multiple effects)
local LPF_FREQS = {
  "630 Hz","800 Hz","1 kHz","1.25 kHz","1.6 kHz","2 kHz","2.5 kHz",
  "3.15 kHz","4 kHz","5 kHz","6.3 kHz","8 kHz","10 kHz","12.5 kHz","Flat"
}
local function dispLPF(raw)
  return LPF_FREQS[raw + 1] or tostring(raw)
end

-- EQ parametric frequency (0-27): 20 Hz → 10 kHz  (log-spaced Roland standard)
local EQ_FREQS = {
  "20 Hz","25 Hz","31 Hz","40 Hz","50 Hz","63 Hz","80 Hz","100 Hz","125 Hz",
  "160 Hz","200 Hz","250 Hz","315 Hz","400 Hz","500 Hz","630 Hz","800 Hz",
  "1 kHz","1.25 kHz","1.6 kHz","2 kHz","2.5 kHz","3.15 kHz","4 kHz",
  "5 kHz","6.3 kHz","8 kHz","10 kHz"
}
local function dispEQFreq(raw)
  return EQ_FREQS[raw + 1] or tostring(raw)
end

-- EQ Q (0-5): 0.5 → 16
local EQ_Q = {"0.5","1.0","2.0","4.0","8.0","16"}
local function dispEQQ(raw)
  return "Q " .. (EQ_Q[raw + 1] or tostring(raw))
end

-- Tremolo waveform type (0-5)
local TR_TYPES = {"TRI","UP SAW","DN SAW","SIN","SQR","RND"}
local function dispTrType(raw)
  return TR_TYPES[raw + 1] or tostring(raw)
end

-- Tremolo phase (0-100 → 0°–360°)
local function dispPhase(raw)
  return math.floor(raw * 3.6 + 0.5) .. "\194\176"  -- \194\176 = UTF-8 degree sign
end

-- Rate/period (0-100 → ~8000 ms … 20 ms, linear approximation)
-- Real mapping is logarithmic; this first-pass display is directionally correct.
local function dispRate(raw)
  return math.floor((1 - raw / 100) * 7980 + 20) .. " ms"
end

-- Direct millisecond mappings (value = ms)
local function dispMs(raw)   return raw .. " ms"  end
local function dispPct(raw)  return raw .. "%"     end

-- Reverb time (0-99 → 0.0 s … 9.9 s in 0.1 s steps)
local function dispRevTime(raw)
  return string.format("%.1f s", raw / 10)
end

-- Pitch shift in semitones (0-48, centre 24 = 0 st)
local function dispPitchSt(raw)
  local st = raw - 24
  return (st >= 0 and "+" or "") .. st .. " st"
end

-- ---------------------------------------------------------------------------
-- EFX type definitions
-- ---------------------------------------------------------------------------
-- slot  : { off, name, max [, display] }
--   display(raw) → string — optional human-readable conversion.
--   Omit for plain 0-N integer display.
--
-- btn   : { off, name, action [, val, max] }
--   action "set"    → radio preset; write val; light this, unlight siblings
--   action "toggle" → binary flip at offset
--
-- Type-option ("set") buttons sit at the bottom row (btns[4]–[7] = B5–B8).
-- Reverb fills all 7 B-button slots B2–B8 (btns[1]–[7]).
-- BPM SYNC / STEP RATE are regular slots — not buttons.

local TYPE_DEFS = {

  [0] = { name="BYPASS" },

  -- 1: COMP — Compressor/Sustainer
  --    CS ATTACK 0-124 = 0-800ms  |  CS RELEASE 0-124 = 0-8000ms
  --    CS THRESHOLD 0-40 = −40 to 0 dB  |  CS RATIO 0-13 = 14 ratios
  --    CS KNEE 0-9 = Hard/Soft1-9  |  CS GAIN 0-80 = ±40 dB
  --    CS BALANCE 0-100 = −50…+50
  [1] = { name="COMP",
    swOff = 0x01,
    slots = {
      {off=0x04, name="THRESHOLD", max=40,  display=dispThreshold},
      {off=0x05, name="RATIO",     max=13,  display=dispRatio},
      {off=0x02, name="ATTACK",    max=124, display=dispCsAttack},
      {off=0x03, name="RELEASE",   max=124, display=dispCsRelease},
      {off=0x06, name="KNEE",      max=9,   display=dispKnee},
      {off=0x07, name="GAIN",      max=80,  display=dispDb40},
      {off=0x08, name="BALANCE",   max=100, display=dispBipolar50},
    },
    btns = {
      nil, nil, nil,
      {off=0x05, name="1:2",   action="set", val=6},
      {off=0x05, name="1:4",   action="set", val=8},
      {off=0x05, name="1:INF", action="set", val=13},
    },
  },

  -- 2: RING MOD
  --    EQ LOW/HIGH 0-30 = ±15 dB  |  BALANCE 0-100 = −50…+50
  --    POLARITY 0=UP, 1=DOWN — two radio buttons (B2/B3)
  [2] = { name="RING MOD",
    swOff = 0x09,
    slots = {
      {off=0x0A, name="FREQ",    max=127},
      {off=0x0B, name="SENS",    max=127},
      {off=0x0F, name="BALANCE", max=100, display=dispBipolar50},
      {off=0x10, name="LEVEL",   max=127},
      {off=0x0D, name="EQ LOW",  max=30,  display=dispDb15},
      {off=0x0E, name="EQ HIGH", max=30,  display=dispDb15},
    },
    btns = {
      {off=0x0C, name="UP",   action="set", val=0},
      {off=0x0C, name="DOWN", action="set", val=1},
    },
  },

  -- 3: BIT CRUSH
  --    EQ LOW/HIGH 0-30 = ±15 dB
  [3] = { name="BIT CRUSH",
    swOff = 0x11,
    slots = {
      {off=0x12, name="FILTER",    max=127},
      {off=0x13, name="SAMP RATE", max=127},
      {off=0x17, name="LEVEL",     max=127},
      nil,
      {off=0x15, name="EQ LOW",    max=30, display=dispDb15},
      {off=0x16, name="EQ HIGH",   max=30, display=dispDb15},
    },
    btns = {},
  },

  -- 4: TREMOLO
  --    S01-S04: dedicated time row — BPM SYNC, RATE (greyed when SYNC ≠ OFF), nil×2
  --    S05+: sound parameters
  --    TYPE 0-5 = TRI/UP SAW/DN SAW/SIN/SQR/RND  |  PHASE 0-100 = 0°-360°
  [4] = { name="TREMOLO",
    swOff = 0x18,
    slots = {
      {off=0x1C, name="BPM SYNC", max=20,  display=dispBpmDiv},
      {off=0x1B, name="RATE",     max=100, display=dispRate, disabledBy={0x1C}},
      nil, nil,
      {off=0x1E, name="DEPTH",    max=100},
      {off=0x19, name="TYPE",     max=5,   display=dispTrType},
      {off=0x20, name="LEVEL",    max=100},
      {off=0x1A, name="PHASE",    max=100, display=dispPhase},
      {off=0x1D, name="SHAPE",    max=100},
    },
    btns = {
      nil, nil, nil,
      {off=0x1F, name="TREMOLO", action="set", val=0},
      {off=0x1F, name="PAN",     action="set", val=1},
    },
  },

  -- 5: CHORUS
  --    S01-S04: dedicated time row — BPM SYNC, RATE (greyed when SYNC ≠ OFF), nil×2
  --    S05+: sound parameters
  --    PRE DLY 0-80 = 0-80 ms  |  HPF 0-17 = Flat-800 Hz  |  LPF 0-14 = 630 Hz-Flat
  [5] = { name="CHORUS",
    swOff = 0x21,
    slots = {
      {off=0x24, name="BPM SYNC", max=20,  display=dispBpmDiv},
      {off=0x23, name="RATE",     max=100, display=dispRate, disabledBy={0x24}},
      nil, nil,
      {off=0x25, name="DEPTH",    max=100},
      {off=0x26, name="PRE DLY",  max=80,  display=dispMs},
      {off=0x29, name="LEVEL",    max=100},
      {off=0x27, name="HPF",      max=17,  display=dispHPF},
      {off=0x28, name="LPF",      max=14,  display=dispLPF},
    },
    btns = {
      nil, nil, nil,
      {off=0x22, name="MONO",    action="set", val=0},
      {off=0x22, name="STEREO1", action="set", val=1},
      {off=0x22, name="STEREO2", action="set", val=2},
    },
  },

  -- 6: FLANGER
  --    S01-S04: dedicated time row — BPM SYNC, RATE (greyed when SYNC ≠ OFF), nil×2
  --    S05+: sound parameters
  --    MANUAL 0-100 = −50…+50  |  HPF 0-10 = Flat-800 Hz (verify against hardware)
  [6] = { name="FLANGER",
    swOff = 0x2A,
    slots = {
      {off=0x2C, name="BPM SYNC",   max=20,  display=dispBpmDiv},
      {off=0x2B, name="RATE",       max=100, display=dispRate, disabledBy={0x2C}},
      nil, nil,
      {off=0x2D, name="DEPTH",      max=100},
      {off=0x2E, name="MANUAL",     max=100, display=dispBipolar50},
      {off=0x2F, name="RESONANCE",  max=100},
      {off=0x30, name="SEPARATN",   max=100},
      {off=0x31, name="HPF",        max=10,  display=dispFLHPF},
      {off=0x32, name="EFX LVL",    max=100},
      {off=0x33, name="DIRECT LVL", max=100},
    },
    btns = {},
  },

  -- 7: PHASER
  --    S01-S04: dedicated time row — BPM SYNC, RATE (greyed when S01 or S03 ≠ OFF),
  --             STEP RATE, nil (Phaser fills 3 of 4 time slots)
  --    S05+: sound parameters  |  MANUAL 0-100 = −50…+50
  [7] = { name="PHASER",
    swOff = 0x34,
    slots = {
      {off=0x37, name="BPM SYNC",   max=20,  display=dispBpmDiv},
      {off=0x36, name="RATE",       max=100, display=dispRate, disabledBy={0x37, 0x3B}},
      {off=0x3B, name="STEP RATE",  max=20,  display=dispBpmDiv},
      nil,
      {off=0x38, name="DEPTH",      max=100},
      {off=0x39, name="MANUAL",     max=100, display=dispBipolar50},
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
  --    S01-S04: dedicated time row — BPM SYNC, TIME (greyed when SYNC ≠ OFF), nil×2
  --    S05+: sound parameters (TAP TIME first since it's time-adjacent)
  --    BPM SYNC 0-13 = 14 beat divisions (Delay has a shorter sync range than others)
  --    LPF 0-14 = 630 Hz-Flat
  [8] = { name="DELAY",
    swOff = 0x3E,
    slots = {
      {off=0x42, name="BPM SYNC",   max=13,  display=dispBpmDiv},
      {off=0x40, name="TIME",       max=100, display=dispMs, disabledBy={0x42}},
      nil, nil,
      {off=0x41, name="TAP TIME",   max=100, display=dispPct},
      {off=0x43, name="FEEDBACK",   max=100},
      {off=0x44, name="LPF",        max=14,  display=dispLPF},
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

-- ---------------------------------------------------------------------------
-- EFX1-specific types (PITCH SHIFT type 9, EQ type 10)
-- ---------------------------------------------------------------------------

if efxNum == 1 then

  -- 9: PITCH SHIFT (EFX1 only)
  --    PITCH 0-48 = −24…+24 semitones (raw 24 = 0 st)
  --    PRE DLY 0-100 = 0-100 ms
  TYPE_DEFS[9] = { name="PITCH SHIFT",
    swOff = 0x47,
    slots = {
      {off=0x49, name="PITCH 1",    max=48,  display=dispPitchSt},
      {off=0x4A, name="PRE DLY 1",  max=100, display=dispMs},
      {off=0x4C, name="EFX LVL 1",  max=100},
      {off=0x4B, name="FEEDBACK",   max=100},
      {off=0x4D, name="PITCH 2",    max=48,  display=dispPitchSt},
      {off=0x4E, name="PRE DLY 2",  max=100, display=dispMs},
      {off=0x50, name="EFX LVL 2",  max=100},
      {off=0x51, name="DIRECT LVL", max=100},
    },
    btns = {
      nil, nil, nil,
      {off=0x48, name="1MONO",   action="set", val=0},
      {off=0x48, name="2MONO",   action="set", val=1},
      {off=0x48, name="2STEREO", action="set", val=2},
    },
  }

  -- 10: EQ (EFX1 only)
  --    GAIN params 0-40 = ±20 dB
  --    LOW/HI CUT: HPF (0-17) / LPF (0-14) tables
  --    FREQ 0-27 = 20 Hz-10 kHz  |  Q 0-5 = 0.5-16
  TYPE_DEFS[10] = { name="EQ",
    swOff = 0x53,
    slots = {
      {off=0x54, name="LOW CUT",  max=17, display=dispHPF},
      {off=0x55, name="LOW GAIN", max=40, display=dispDb20},
      {off=0x5C, name="HI CUT",   max=14, display=dispLPF},
      {off=0x5D, name="HI GAIN",  max=40, display=dispDb20},
      {off=0x56, name="LM FREQ",  max=27, display=dispEQFreq},
      {off=0x57, name="LM Q",     max=5,  display=dispEQQ},
      {off=0x58, name="LM GAIN",  max=40, display=dispDb20},
      nil,
      {off=0x59, name="HM FREQ",  max=27, display=dispEQFreq},
      {off=0x5A, name="HM Q",     max=5,  display=dispEQQ},
      {off=0x5B, name="HM GAIN",  max=40, display=dispDb20},
      {off=0x5E, name="LEVEL",    max=40, display=dispDb20},
    },
    btns = {},
  }

-- ---------------------------------------------------------------------------
-- EFX2-specific types (REVERB type 9)
-- ---------------------------------------------------------------------------

else

  -- 9: REVERB (EFX2 only)
  --    TIME 0-99 = 0.0-9.9 s  |  PRE DLY 0-100 = 0-100 ms
  --    HPF 0-17 = Flat-800 Hz  |  LPF 0-14 = 630 Hz-Flat
  --    All 7 B-buttons (B2–B8) are reverb-type presets.
  TYPE_DEFS[9] = { name="REVERB",
    swOff = 0x47,
    slots = {
      {off=0x49, name="TIME",       max=99,  display=dispRevTime},
      {off=0x4A, name="PRE DLY",    max=100, display=dispMs},
      {off=0x4D, name="DENSITY",    max=10},
      {off=0x50, name="SPRING SNS", max=100},
      {off=0x4B, name="HPF",        max=17,  display=dispHPF},
      {off=0x4C, name="LPF",        max=14,  display=dispLPF},
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
  }

end

-- ---------------------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------------------

local function slotGroupName(i)
  return string.format("efx%d_s%02d", efxNum, i)
end

local function btnNodeName(i)
  return string.format("efx%d_b%d", efxNum, i)
end

local function updateLabel(text)
  local lbl = self.children["efx" .. efxNum .. "_label"]
  if lbl then lbl.values.text = text end
end

local function chooserGroup()
  return self.children["efx_" .. efxNum .. "_chooser"]
end

local function chooserLabelsGroup()
  return self.children["efx_" .. efxNum .. "_chooser_labels"]
end

local function btnLabelsGroup()
  return self.children["efx" .. efxNum .. "_b_labels"]
end

-- ---------------------------------------------------------------------------
-- refreshDisabledLabels
-- Dims the name_label of any slot whose disabledBy condition is currently met.
-- Called from applyType (inline) and after every slot send so the rate label
-- updates immediately when the user changes BPM SYNC via an encoder.
-- ---------------------------------------------------------------------------

local DIM_COLOR = "777777FF"   -- greyed name text → parameter currently bypassed
local LIT_COLOR = "FFFFFFFF"   -- normal name text

local function refreshDisabledLabels(def)
  if not def or not def.slots then return end
  for i = 1, 12 do
    local slotDef = def.slots[i]
    local slotGrp = self.children[slotGroupName(i)]
    if slotGrp then
      local nameLbl = slotGrp.children["name_label"]
      local valLbl  = slotGrp.children["value_label"]
      if slotDef and slotDef.disabledBy then
        local disabled = false
        for _, dOff in ipairs(slotDef.disabledBy) do
          if (rawData[dOff + 1] or 0) > 0 then
            disabled = true; break
          end
        end
        local clr = disabled and DIM_COLOR or LIT_COLOR
        if nameLbl then nameLbl.textColor = Color.fromHexString(clr) end
        if valLbl  then valLbl.textColor  = Color.fromHexString(clr) end
        slotGrp.tag = disabled and "disabled" or ""
      else
        -- No disabledBy condition — always interactive.
        -- Reset any stale dim colours left over from a previous effect type
        -- that had a disabledBy slot at this same index (e.g. switching from
        -- Chorus RATE at S01 to EQ LOW CUT at S01).
        if nameLbl then nameLbl.textColor = Color.fromHexString(LIT_COLOR) end
        if valLbl  then valLbl.textColor  = Color.fromHexString(LIT_COLOR) end
        slotGrp.tag = ""
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- applyType — remaps slots, buttons, colours, labels, BCR rings.
--
-- Slot display: if slotDef.display is set, calls display(raw) for the label.
-- Button colour: "set" → SEL_HEX, everything else → BASE_HEX.
-- ---------------------------------------------------------------------------

local function applyType(typeIdx)
  curType = typeIdx
  local def = TYPE_DEFS[typeIdx]

  updateLabel("EFX" .. efxNum .. ": " .. (def and def.name or "???"))

  local typeCCval = (MAX_TYPE > 0) and math.floor(typeIdx / MAX_TYPE * 127 + 0.5) or 0
  sendBCRcc(TYPE_CC, typeCCval)

  -- ── Chooser radio + chooser label text colours ──────────────────────────
  local cgrp  = chooserGroup()
  local clGrp = chooserLabelsGroup()
  self.tag = "prog"
  if cgrp then
    for i = 1, MAX_TYPE do
      local cb = cgrp.children[tostring(i)]
      local cl = clGrp and clGrp.children[tostring(i)]
      local isActive = (i == curType)
      if cb then cb.values.x = isActive and 1 or 0 end
      if cl then cl.textColor = Color.fromHexString(isActive and ON_TXT or OFF_TXT) end
    end
  end
  self.tag = ""

  -- ── Slot faders (S01–S12) ────────────────────────────────────────────────
  for i = 1, 12 do
    local slotGrp = self.children[slotGroupName(i)]
    if slotGrp then
      local slotDef = def and def.slots and def.slots[i]
      slotGrp.visible = (slotDef ~= nil)
      if slotDef then
        local fader   = slotGrp.children["control_fader"]
        local nameLbl = slotGrp.children["name_label"]
        local valLbl  = slotGrp.children["value_label"]
        if nameLbl then nameLbl.values.text = slotDef.name end
        if #rawData > 0 then
          local raw = rawData[slotDef.off + 1] or 0
          local x   = math.max(0, math.min(1, raw / slotDef.max))
          local txt = slotDef.display and slotDef.display(raw) or tostring(raw)
          if fader  then fader.values.x    = x end
          if valLbl then valLbl.values.text = txt end
          sendBCRcc(SLOT_CC[i], math.floor(x * 127 + 0.5))
        else
          if fader  then fader.values.x    = 0 end
          if valLbl then valLbl.values.text = "--" end
          sendBCRcc(SLOT_CC[i], 0)
        end
      else
        sendBCRcc(SLOT_CC[i], 0)
      end
    end
  end

  -- Dim name labels for any slot that is currently bypassed by BPM SYNC etc.
  refreshDisabledLabels(def)

  -- ── B buttons + labels ───────────────────────────────────────────────────
  local lblGrp = btnLabelsGroup()
  self.tag = "prog"

  -- B1: EFX SW (always utility colour)
  local hasSW = (def ~= nil and def.swOff ~= nil)
  local b1    = self.children[btnNodeName(1)]
  local lbl1  = lblGrp and lblGrp.children["1"]
  if b1 then
    b1.visible = hasSW
    b1.color   = Color.fromHexString(BASE_HEX)
    if hasSW then
      local swVal = (#rawData > 0) and (rawData[def.swOff + 1] or 0) or 0
      b1.values.x = swVal
      if lbl1 then lbl1.textColor = Color.fromHexString(swVal >= 0.5 and ON_TXT or OFF_TXT) end
      sendBCRcc(BTN_CC[1], swVal * 127)
    else
      b1.values.x = 0
      sendBCRcc(BTN_CC[1], 0)
    end
  end
  if lbl1 then
    lbl1.visible     = hasSW
    lbl1.values.text = "ON/OFF"
  end

  -- B2–B8: per-effect action buttons ("set" or "toggle")
  for i = 2, 8 do
    local btn    = self.children[btnNodeName(i)]
    local lbl    = lblGrp and lblGrp.children[tostring(i)]
    local btnDef = def and def.btns and def.btns[i - 1]
    local bcrVal = 0
    local uiVal  = 0

    if btnDef then
      if btnDef.action == "toggle" then
        local cur = (#rawData > 0) and (rawData[btnDef.off + 1] or 0) or 0
        uiVal  = (cur > 0) and 1 or 0
        bcrVal = uiVal * 127
      elseif btnDef.action == "set" then
        local cur = (#rawData > 0) and rawData[btnDef.off + 1] or nil
        uiVal  = (cur ~= nil and cur == btnDef.val) and 1 or 0
        bcrVal = uiVal * 127
      end
    end

    local clrHex = (btnDef and btnDef.action == "set") and SEL_HEX or BASE_HEX

    if btn then
      btn.visible  = (btnDef ~= nil)
      btn.values.x = uiVal
      btn.color    = Color.fromHexString(clrHex)
    end
    if lbl then
      lbl.visible     = (btnDef ~= nil)
      lbl.values.text = btnDef and btnDef.name or ""
      lbl.textColor   = Color.fromHexString(uiVal >= 0.5 and ON_TXT or OFF_TXT)
    end
    sendBCRcc(BTN_CC[i], bcrVal)
  end

  self.tag = ""
end

-- ---------------------------------------------------------------------------
-- Slot SysEx send helpers
-- Uses slotDef.display for label when available; falls back to tostring(raw).
-- ---------------------------------------------------------------------------

local function sendSlotFromFloat(slotIdx, x)
  local def     = TYPE_DEFS[curType]
  local slotDef = def and def.slots and def.slots[slotIdx]
  if not slotDef then return end
  local raw = math.floor(x * slotDef.max + 0.5)
  sendParam(slotDef.off, raw)
  rawData[slotDef.off + 1] = raw
  local slotGrp = self.children[slotGroupName(slotIdx)]
  if slotGrp then
    local valLbl = slotGrp.children["value_label"]
    local txt    = slotDef.display and slotDef.display(raw) or tostring(raw)
    if valLbl then valLbl.values.text = txt end
  end
  -- Re-check disabled labels in case this change affected a RATE slot.
  refreshDisabledLabels(def)
end

local function sendSlotFromCC(slotIdx, ccVal)
  local def     = TYPE_DEFS[curType]
  local slotDef = def and def.slots and def.slots[slotIdx]
  if not slotDef then return end
  local raw = math.floor(ccVal / 127 * slotDef.max + 0.5)
  sendParam(slotDef.off, raw)
  rawData[slotDef.off + 1] = raw
  local slotGrp = self.children[slotGroupName(slotIdx)]
  if slotGrp then
    local fader  = slotGrp.children["control_fader"]
    local valLbl = slotGrp.children["value_label"]
    local txt    = slotDef.display and slotDef.display(raw) or tostring(raw)
    if fader  then fader.values.x     = raw / slotDef.max end
    if valLbl then valLbl.values.text = txt end
  end
  -- Re-check disabled labels in case this change affected a RATE slot.
  refreshDisabledLabels(def)
end

-- ---------------------------------------------------------------------------
-- onReceiveNotify
-- ---------------------------------------------------------------------------

function onReceiveNotify(key, value)

  if key == "type_cc" then
    local ccVal   = tonumber(value) or 0
    local typeIdx = math.floor(ccVal / 127 * MAX_TYPE + 0.5)
    sendParam(0x00, typeIdx)
    rawData[1] = typeIdx
    applyType(typeIdx)
    return
  end

  if key == "type_set" then
    local typeIdx = math.min(math.max(tonumber(value) or 0, 0), MAX_TYPE)
    if typeIdx ~= 0 and typeIdx == curType then typeIdx = 0 end
    sendParam(0x00, typeIdx)
    rawData[1] = typeIdx
    applyType(typeIdx)
    return
  end

  if key == "type_step" then
    local dir     = tonumber(value) or 0
    local typeIdx = ((curType + dir) % (MAX_TYPE + 1) + (MAX_TYPE + 1)) % (MAX_TYPE + 1)
    sendParam(0x00, typeIdx)
    rawData[1] = typeIdx
    applyType(typeIdx)
    return
  end

  if key == "patch_data" then
    rawData = {}
    for hex in value:gmatch("[^,]+") do
      rawData[#rawData + 1] = tonumber(hex, 16) or 0
    end
    local typeIdx = rawData[1] or 0
    applyType(typeIdx)
    return
  end

  if key == "slot_cc" then
    local si, cv = value:match("^(%d+),(%d+)$")
    local slotIdx = tonumber(si)
    local ccVal   = tonumber(cv) or 0
    if not slotIdx then return end
    sendSlotFromCC(slotIdx, ccVal)
    return
  end

  if key == "slot_moved" then
    local encName, xs = value:match("^([^,]+),(.+)$")
    if not encName then return end
    local slotIdx = tonumber(encName:match("efx%d+_s(%d+)"))
    if not slotIdx then return end
    local x = tonumber(xs) or 0
    sendSlotFromFloat(slotIdx, x)
    sendBCRcc(SLOT_CC[slotIdx], math.floor(x * 127 + 0.5))
    return
  end

  if key == "btn_press" then
    local btnIdx = tonumber(value) or 0
    if btnIdx < 1 or btnIdx > 8 then return end
    local def    = TYPE_DEFS[curType]
    local lblGrp = btnLabelsGroup()

    -- B1: EFX SW toggle
    if btnIdx == 1 then
      if not def or not def.swOff then return end
      local cur = rawData[def.swOff + 1] or 0
      local nxt = 1 - cur
      sendParam(def.swOff, nxt)
      rawData[def.swOff + 1] = nxt
      self.tag = "prog"
      local b1  = self.children[btnNodeName(1)]
      local lbl = lblGrp and lblGrp.children["1"]
      if b1  then b1.values.x   = nxt end
      if lbl then lbl.textColor = Color.fromHexString(nxt >= 0.5 and ON_TXT or OFF_TXT) end
      self.tag = ""
      sendBCRcc(BTN_CC[1], nxt * 127)
      return
    end

    local btnDef = def and def.btns and def.btns[btnIdx - 1]
    if not btnDef then return end

    if btnDef.action == "set" then
      sendParam(btnDef.off, btnDef.val)
      rawData[btnDef.off + 1] = btnDef.val
      self.tag = "prog"
      for bi = 2, 8 do
        local bd  = def.btns and def.btns[bi - 1]
        local bb  = self.children[btnNodeName(bi)]
        local bl  = lblGrp and lblGrp.children[tostring(bi)]
        if bd and bd.action == "set" and bd.off == btnDef.off then
          local isActive = (bi == btnIdx)
          if bb  then bb.values.x   = isActive and 1 or 0 end
          if bl  then bl.textColor  = Color.fromHexString(isActive and ON_TXT or OFF_TXT) end
          sendBCRcc(BTN_CC[bi], isActive and 127 or 0)
        end
      end
      self.tag = ""

    elseif btnDef.action == "toggle" then
      local cur = rawData[btnDef.off + 1] or 0
      local nxt = 1 - cur
      sendParam(btnDef.off, nxt)
      rawData[btnDef.off + 1] = nxt
      self.tag = "prog"
      local btn = self.children[btnNodeName(btnIdx)]
      local lbl = lblGrp and lblGrp.children[tostring(btnIdx)]
      if btn then btn.values.x   = nxt end
      if lbl then lbl.textColor  = Color.fromHexString(nxt >= 0.5 and ON_TXT or OFF_TXT) end
      self.tag = ""
      sendBCRcc(BTN_CC[btnIdx], nxt * 127)
    end

    return
  end
end

-- ---------------------------------------------------------------------------
-- init
-- ---------------------------------------------------------------------------

function init()
  applyType(0)
end
