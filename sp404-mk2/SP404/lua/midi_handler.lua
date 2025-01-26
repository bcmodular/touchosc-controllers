local defaultCCValues = {0, 0, 0, 0, 0, 0}
local ccValues = {unpack(defaultCCValues)}
local midiCCs = {16, 17, 18, 80, 81, 82}
local fxNum = 1
local midiChannel = 0
local presetManager = root.children.preset_manager

local controlsInfoArray = {
-- Array structure:
-- 1) Fader name
-- 2) Is excludable (true/false)
-- 3) Label name
-- 4) Label mapping function
-- 5) Label format string
-- 6) Synced grid (optional)
-- 7) Grid ranges (optional, used for grids)
-- 8) Am synced fader (optional, used for sync grids)
-- 9) Show/hide fader name (optional, used for sync grids)
-- 10) Show/hide fader label name (optional, used for sync grids)
-- 11) Show/hide grid name (optional, used for sync grids)
-- 12) Show/hide grid label name (optional, used for sync grids)

  {-- 1: filter + drive
  {'cutoff_fader', false, 'cutoff_label', 'getFreq', 'CUTOFF: %s Hz', ''},
  {'resonance_fader', false, 'resonance_label', 'getZeroOneHundred', 'RESONANCE: %s', ''},
  {'drive_fader', false, 'drive_label', 'getZeroOneHundred', 'DRIVE: %s', ''},
  {'filter_type_fader', false, 'filter_type_label', 'getFilterType', '%s', 'filter_type_grid',
    '{0, 64}'},
  {'low_freq_fader', false, 'low_freq_label', 'getFreq', 'LOW FREQ: %s Hz', ''},
  {'low_gain_fader', false, 'low_gain_label', 'get24dB', 'LOW GAIN: %s dB', ''}
  },
  {-- 2: resonator
  {'root_fader', true, 'root_value_label', 'getRoot', '%s', ''},
  {'bright_fader', false, 'bright_value_label', 'getZeroOneHundred', '%s', ''},
  {'feedback_fader', false, 'feedback_value_label', 'getZeroNinetyNine', '%s%%', ''},
  {'chord_fader', true, 'chord_label', 'getChord', '%s', 'chord_grid',
    '{0, 9, 17, 25, 33, 41, 49, 57, 65, 73, 81, 89, 97, 105, 113, 121}'},
  {'panning_fader', false, 'panning_value_label', 'getZeroOneHundred', '%s', ''},
  {'env_mod_fader', false, 'env_mod_value_label', 'getZeroOneHundred', '%s', ''}
  },
  {-- 3: sync delay
  {'delay_time_fader', false, 'delay_time_label', 'getDelayTimes', '%s', 'delay_time_grid',
    '{0, 9, 17, 25, 33, 41, 49, 57, 65, 73, 81, 89, 97, 105, 113, 121}'},
  {'feedback_fader', false, 'feedback_label', 'getZeroNinetyNine', 'FEEDBACK: %s%%', ''},
  {'level_fader', false, 'level_label', 'getZeroOneHundred', 'LEVEL: %s', ''},
  {'l_damp_f_fader', false, 'l_damp_f_label', 'getLDampFValues', '%s', 'l_damp_f_grid',
    '{0, 11, 22, 33, 44, 55, 65, 76, 87, 98, 109, 119}'},
  {'h_damp_f_fader', false, 'h_damp_f_label', 'getHDampFValues', '%s', 'h_damp_f_grid',
    '{0, 9, 18, 26, 35, 43, 52, 60, 69, 77, 86, 94, 103, 111, 120}'},
  },
  {-- 4: isolator
  {'low_fader', false, 'low_label', 'getEQ', '%s', ''},
  {'mid_fader', false, 'mid_label', 'getEQ', '%s', ''},
  {'high_fader', false, 'high_label', 'getEQ', '%s', ''}
  },
  {-- 5: djfx looper
  {'length_fader', false, 'length_label', 'getLooperLength', '%s s', ''},
  {'speed_fader', false, 'speed_label', 'getBipolarHundred', '%s', ''},
  {'on_off_fader', false, 'on_off_label', 'getOnOff', '%s', 'on_off_grid', '{0, 64}'}
  },
  {-- 6: scatter
  {'scatter_type_fader', false, 'scatter_type_label', 'getScatterType', '%s', 'scatter_type_grid',
    '{0, 13, 26, 39, 52, 65, 77, 90, 103, 115}'},
  {'scatter_depth_fader', false, 'scatter_depth_label', 'getScatterDepth', '%s', 'scatter_depth_grid',
    '{0, 13, 26, 39, 52, 65, 77, 90, 103, 115}'},
  {'on_off_fader', false, 'on_off_label', 'getOnOff', '%s', 'on_off_grid',
    '{0, 64}'},
  {'scatter_speed_fader', false, 'scatter_speed_label', 'getScatterSpeed', '%s', 'scatter_speed_grid',
    '{0, 64}'}
  },
  {-- 7: downer
  {'depth_fader', false, 'depth_label', 'getZeroOneHundred', 'DEPTH: %s', ''},
  {'downer_rate_fader', false, 'downer_rate_label', 'getDownerRate', '%s', 'downer_rate_grid',
    '{0, 19, 37, 55, 73, 91, 127}'},
  {'filter_fader', false, 'filter_label', 'getZeroOneHundred', 'FILTER: %s', ''},
  {'pitch_on_off_fader', false, 'pitch_on_off_label', 'getPitchOnOff', '%s', 'pitch_on_off_grid',
    '{0, 64}'},
  {'resonance_fader', false, 'resonance_label', 'getZeroOneHundred', 'RESONANCE: %s', ''},
  },
  {-- 8: ha dou
  {'mod_depth_fader', false, 'mod_depth_label', 'getZeroOneHundred', 'MOD DEPTH: %s', ''},
  {'time_fader', false, 'time_label', 'getZeroOneHundred', 'TIME %s', ''},
  {'level_fader', false, 'level_label', 'getZeroOneHundred', 'LEVEL: %s', ''},
  {'low_cut_fader', false, 'low_cut_label', 'getLowCut', '%s', 'low_cut_grid',
    '{0, 8, 15, 22, 29, 36, 43, 50, 57, 64, 71, 78, 85, 95, 102, 109, 116, 123}'},
  {'high_cut_fader', false, 'high_cut_label', 'getHighCut', '%s', 'high_cut_grid',
    '{0, 9, 18, 26, 35, 43, 52, 60, 69, 77, 86, 94, 103, 111, 120}'},
  {'pre_delay_fader', false, 'pre_delay_label', 'getHundredMS', 'PRE DELAY: %s ms', ''},
  },
  {-- 9: ko da ma
  {'ko_da_ma_time_fader', false, 'ko_da_ma_time_label', 'getDelayTimes', '%s', 'ko_da_ma_time_grid',
    '{0, 9, 17, 25, 33, 41, 49, 57, 65, 73, 81, 89, 97, 105, 113, 121}'},
  {'feedback_fader', false, 'feedback_label', 'getZeroNinetyNine', 'FEEDBACK: %s%%', ''},
  {'level_fader', false, 'level_label', 'getZeroOneHundred', 'LEVEL: %s', ''},
  {'l_damp_f_fader', false, 'l_damp_f_label', 'getLDampFValues', '%s', 'l_damp_f_grid',
    '{0, 11, 22, 33, 44, 55, 65, 76, 87, 98, 109, 119}'},
  {'h_damp_f_fader', false, 'h_damp_f_label', 'getHDampFValues', '%s', 'h_damp_f_grid',
    '{0, 9, 18, 26, 35, 43, 52, 60, 69, 77, 86, 94, 103, 111, 120}'},
  {'ko_da_ma_mode_fader', false, 'ko_da_ma_mode_label', 'getKoDaMaMode', '%s', 'ko_da_ma_mode_grid',
    '{0, 64}'}
  },
  {-- 10: zan zou
  {'zan_zou_time_fader', false, 'zan_zou_time_label', 'getZeroOneHundred', 'TIME: %s', 'zan_zou_time_grid',
    '{0, 9, 17, 28, 36, 44, 52, 60, 68, 77, 87, 95, 103, 114, 122, 127}', 'true'},
  {'feedback_fader', false, 'feedback_label', 'getZeroNinetyNine', 'FEEDBACK: %s', ''},
  {'hf_damp_fader', false, 'hf_damp_label', 'getHFDampValues', '%s', 'hf_damp_grid',
    '{0, 8, 15, 22, 29, 36, 43, 50, 57, 64, 71, 78, 85, 95, 102, 109, 116, 123}'},
  {'level_fader', false, 'level_label', 'getZeroOneHundred', 'LEVEL: %s', ''},
  {'zan_zou_mode_fader', false, 'zan_zou_mode_label', 'getZanZouMode', '%s', 'zan_zou_mode_grid',
    '{0, 43, 86}'},
  {'zan_zou_sync_fader', false, 'zan_zou_sync_label', 'getSync', '%s', 'zan_zou_sync_grid',
    '{0, 64}', 'false', 'zan_zou_time_fader', 'zan_zou_time_label', 'zan_zou_time_grid', 'zan_zou_time_label_grid'}
  },
  {-- 11: to gu ro
  {'depth_fader', false, 'depth_label', 'getZeroOneHundred', 'DEPTH: %s', ''},
  {'to_gu_ro_rate_fader', false, 'to_gu_ro_rate_label', 'getZeroOneHundred', 'RATE: %s', 'to_gu_ro_rate_grid',
    '{0, 16, 32, 48, 64, 80, 96, 112, 127}', 'true'},
  {'resonance_fader', false, 'resonance_label', 'getZeroOneHundred', 'RESONANCE: %s', ''},
  {'flt_mod_fader', false, 'flt_mod_label', 'getZeroOneHundred', 'FLT MOD: %s', ''},
  {'amp_mod_fader', false, 'amp_mod_label', 'getZeroOneHundred', 'AMP MOD: %s', ''},
  {'to_gu_ro_sync_fader', false, 'to_gu_ro_sync_label', 'getSync', '%s', 'to_gu_ro_sync_grid',
    '{0, 64}', 'false', 'to_gu_ro_rate_fader', 'to_gu_ro_rate_label', 'to_gu_ro_rate_grid', 'to_gu_ro_rate_label_grid'},
  },
  {-- 12: sbf
  {'interval_fader', false, 'interval_label', 'getZeroOneHundred', 'INTERVAL: %s', ''},
  {'width_fader', false, 'width_label', 'getZeroOneHundred', 'WIDTH: %s', ''},
  {'balance_fader', false, 'balance_label', 'getBalance', 'BALANCE: %s %%', ''},
  {'sbf_type_fader', false, 'sbf_type_label', 'getSBFType', '%s', 'sbf_type_grid',
    '{0, 25, 51, 76, 102, 127}'},
  {'gain_fader', false, 'gain_label', 'getSBFGain', 'GAIN: %s dB', ''}
  },
  {-- 13: stopper
  {'depth_fader', false, 'depth_label', 'getZeroOneHundred', 'DEPTH: %s', ''},
  {'stopper_rate_fader', false, 'stopper_rate_label', 'getStopperRate', '%s', 'stopper_rate_grid',
    '{0, 16, 32, 48, 64, 80, 96, 112, 127}'},
  {'resonance_fader', false, 'resonance_label', 'getZeroOneHundred', 'RESONANCE: %s', ''},
  {'flt_mod_fader', false, 'flt_mod_label', 'getZeroOneHundred', 'FLT MOD: %s', ''},
  {'amp_mod_fader', false, 'amp_mod_label', 'getZeroOneHundred', 'AMP MOD: %s', ''}
  },
  {-- 14: tape echo
  {'time_fader', false, 'time_label', 'getTapeSpeed', 'TIME: %s ms', ''},
  {'feedback_fader', false, 'feedback_label', 'getZeroNinetyNine', 'FEEDBACK: %s %%', ''},
  {'level_fader', false, 'level_label', 'getZeroOneHundred', 'LEVEL: %s', ''},
  {'tape_echo_mode_fader', false, 'tape_echo_mode_label', 'getTapeEchoMode', '%s', 'tape_echo_mode_grid',
    '{0, 19, 37, 55, 73, 91, 110}'},
  {'wf_rate_fader', false, 'wf_rate_label', 'getZeroOneHundred', 'W/F RATE: %s', ''},
  {'wf_depth_fader', false, 'wf_depth_label', 'getZeroOneHundred', 'W/F DEPTH: %s', ''}
  },
  {-- 15: time ctrl delay
  {'time_ctrl_dly_time_fader', false, 'time_ctrl_dly_time_label', 'getTapeSpeed', 'TIME: %s ms', 'time_ctrl_dly_time_grid',
    '{0, 9, 17, 26, 34, 43, 51, 60, 68, 77, 85, 94, 102, 111, 119, 127}', 'true'},
  {'feedback_fader', false, 'feedback_label', 'getZeroNinetyNine', 'FEEDBACK: %s%%', ''},
  {'level_fader', false, 'level_label', 'getZeroOneHundred', 'LEVEL: %s', ''},
  {'l_damp_f_fader', false, 'l_damp_f_label', 'getLDampFValues', '%s', 'l_damp_f_grid',
    '{0, 11, 22, 32, 43, 54, 64, 75, 85, 96, 107, 117}'},
  {'h_damp_f_fader', false, 'h_damp_f_label', 'getHDampFValues', '%s', 'h_damp_f_grid',
    '{0, 9, 17, 26, 34, 43, 51, 60, 68, 77, 85, 94, 102, 111, 119}'},
  {'time_ctrl_dly_sync_fader', false, 'time_ctrl_dly_sync_label', 'getSync', '%s', 'time_ctrl_dly_sync_grid',
    '{0, 64}', 'false', 'time_ctrl_dly_time_fader', 'time_ctrl_dly_time_label', 'time_ctrl_dly_time_grid', 'time_ctrl_dly_time_label_grid'}
  },
  {-- 16: super filter
  {'cutoff_fader', false},
  {'resonance_fader', false},
  {'filter_type_grid', false},
  {'depth_fader', false},
  {'time_fader', false},
  {'sync_grid', false}
  },
  {-- 17: wrm saturator
  {'drive_fader', false},
  {'eq_low_fader', false},
  {'eq_high_fader', false},
  {'level_fader', false}
  },
}

--************************************************************
-- INITIALISE MAPPING
--************************************************************

-- MAPPING SCRIPTS *******************************************
local mappingScripts = {
  getFreq = [[
    local midiToFrequencyMap = {
      20.0, 21.1, 22.2, 23.4, 24.7, 26.0, 27.4, 28.9, 30.4, 32.1, 33.8, 35.6, 37.5,
      39.5, 41.7, 43.9, 46.3, 48.8, 51.4, 54.2, 57.1, 60.1, 63.4, 66.8, 70.4, 74.2,
      78.2, 82.4, 86.8, 91.5, 96.4, 102.0, 107.0, 113.0, 119.0, 125.0, 132.0, 139.0,
      147.0, 155.0, 163.0, 172.0, 181.0, 191.0, 201.0, 212.0, 223.0, 235.0, 248.0, 
      261.0, 275.0, 290.0, 306.0, 322.0, 339.0, 358.0, 377.0, 397.0, 418.0, 441.0, 
      465.0, 490.0, 516.0, 544.0, 573.0, 604.0, 637.0, 671.0, 707.0, 745.0, 785.0, 
      827.0, 872.0, 919.0, 968.0, 1020.0, 1075.0, 1133.0, 1194.0, 1258.0, 1326.0, 
      1397.0, 1473.0, 1552.0, 1636.0, 1724.0, 1816.0, 1914.0, 2017.0, 2126.0, 2240.0, 
      2361.0, 2488.0, 2622.0, 2763.0, 2912.0, 3068.0, 3233.0, 3407.0, 3591.0, 3784.0, 
      3988.0, 4202.0, 4429.0, 4667.0, 4918.0, 5183.0, 5462.0, 5756.0, 6066.0, 6392.0, 
      6736.0, 7099.0, 7481.0, 7884.0, 8308.0, 8755.0, 9227.0, 9723.0, 10247.0, 10798.0, 
      11379.0, 11992.0, 12637.0, 13318.0, 14035.0, 14790.0, 16000.0
    }

    function getFreq(value)
      local scaledValue = midiToFrequencyMap[value]
      return scaledValue
    end
  ]],

  getZeroOneHundred = [[
    function getZeroOneHundred(value)
      local midiValue = value - 1
      if midiValue == 127 then
        return 100
      else
        return math.floor((midiValue / 127.5) * 100)
      end
    end
  ]],

  get24dB = [[
    function get24dB(value)
      local midiValue = value - 1
      local dbValue = math.floor((midiValue / 127.5) * 49) - 24

      -- Correct the specific case for MIDI value 13
      if midiValue == 13 then
        return -19
      else
        return dbValue
      end
    end
  ]],

  getEQ = [[
    local midiToEQRangeMap = {
      '-INF', '-41.87', '-35.78', '-32.17', '-29.60', '-27.58', '-25.92', '-24.50',
      '-23.26', '-22.15', '-21.16', '-20.25', '-19.41', '-18.63', '-17.91', '-17.23',
      '-16.59', '-15.98', '-15.40', '-14.85', '-14.32', '-13.81', '-13.32', '-12.85',
      '-12.40', '-11.96', '-11.53', '-11.12', '-10.72', '-10.33', '-9.95', '-9.58',
      '-9.22', '-8.87', '-8.52', '-8.18', '-7.85', '-7.53', '-7.21', '-6.89',
      '-6.59', '-6.28', '-5.99', '-5.69', '-5.41', '-5.12', '-4.84', '-4.57',
      '-4.29', '-4.02', '-3.76', '-3.50', '-3.24', '-2.98', '-2.73', '-2.48',
      '-2.23', '-1.98', '-1.74', '-1.50', '-1.26', '-1.03', '-0.79', '-0.56',
      '-0.33', '0.00', '0.12', '0.35', '0.57', '0.79', '1.01', '1.23', '1.44',
      '1.66', '1.87', '2.08', '2.30', '2.50', '2.71', '2.92', '3.13', '3.33',
      '3.53', '3.74', '3.94', '4.14', '4.34', '4.54', '4.73', '4.93', '5.13',
      '5.32', '5.52', '5.71', '5.90', '6.09', '6.28', '6.47', '6.66', '6.85',
      '7.04', '7.23', '7.41', '7.60', '7.79', '7.97', '8.15', '8.34', '8.52',
      '8.70', '8.89', '9.07', '9.25', '9.43', '9.61', '9.79', '9.97', '10.15',
      '10.32', '10.50', '10.68', '10.86', '11.03', '11.21', '11.39', '11.56',
      '11.74', '12.00'
    }

    function getEQ(value)
      local scaledValue = midiToEQRangeMap[value]
      return scaledValue
    end
  ]],

  getBipolarHundred = [[
    local bipolarHundredRangeMap = {
      -100, -99, -97, -96, -94, -93, -91, -89, -88, -86, -85, -83, -82, -80, -78, -77, -75,
      -74, -72, -71, -69, -67, -66, -64, -63, -61, -60, -58, -56, -55, -53, -52, -50, -48,
      -47, -45, -44, -42, -41, -39, -37, -36, -34, -33, -31, -30, -28, -26, -25, -23, -22,
      -20, -19, -17, -15, -14, -12, -11, -9, -7, -6, -4, -3, -1, 0, 2, 4, 5, 7, 8, 10, 11,
      13, 15, 16, 18, 19, 21, 22, 24, 26, 27, 29, 30, 32, 34, 35, 37, 38, 40, 41, 43, 45,
      46, 48, 49, 51, 52, 54, 56, 57, 59, 60, 62, 63, 65, 67, 68, 70, 71, 73, 74, 76, 78,
      79, 81, 82, 84, 86, 87, 89, 90, 92, 93, 95, 97, 98, 100
    }

    function getBipolarHundred(value)
      return bipolarHundredRangeMap[value]
    end
  ]],

  getHundredMS = [[
    local hundredMSRangeMap = {
      0, 0, 1, 2, 3, 3, 4, 5, 6, 7, 7, 8, 9, 10, 11, 11, 12, 13, 14, 15, 15, 16, 
      17, 18, 19, 19, 20, 21, 22, 22, 23, 24, 25, 26, 26, 27, 28, 29, 30, 30, 31, 
      32, 33, 34, 34, 35, 36, 37, 38, 38, 39, 40, 41, 41, 42, 43, 44, 45, 45, 46, 
      47, 48, 49, 49, 50, 51, 52, 53, 53, 54, 55, 56, 57, 57, 58, 59, 60, 61, 61, 
      62, 63, 64, 64, 65, 66, 67, 68, 68, 69, 70, 71, 72, 72, 73, 74, 75, 76, 76, 
      77, 78, 79, 80, 80, 81, 82, 83, 83, 84, 85, 86, 87, 87, 88, 89, 90, 91, 91, 
      92, 93, 94, 95, 95, 96, 97, 98, 99, 99, 100
    }

    function getHundredMS(value)
      return hundredMSRangeMap[value]
    end
  ]],

  getBalance = [[
    local balanceRangeMap = {
      0, 1, 2, 2, 3, 4, 5, 5, 6, 7, 8, 9, 9, 10, 11, 12, 13, 13, 14, 15, 16, 16,
      17, 18, 19, 20, 20, 21, 22, 23, 24, 24, 25, 26, 27, 27, 28, 29, 30, 31, 31,
      32, 33, 34, 35, 35, 36, 37, 38, 38, 39, 40, 41, 42, 42, 43, 44, 45, 45, 46,
      47, 48, 49, 49, 50, 51, 52, 53, 53, 54, 55, 56, 56, 57, 58, 59, 60, 60, 61,
      62, 63, 64, 64, 65, 66, 67, 67, 68, 69, 70, 71, 71, 72, 73, 74, 75, 75, 76,
      77, 78, 78, 79, 80, 81, 82, 82, 83, 84, 85, 85, 86, 87, 88, 89, 89, 90, 91,
      92, 93, 93, 94, 95, 96, 96, 97, 98, 99, 100
    }

    function getBalance(value)
      local rangeValue = balanceRangeMap[value]
      local inverseValue = 100 - rangeValue
      local displayString = inverseValue .. '-' .. rangeValue
      return displayString
    end  
  ]],

  getSBFGain = [[
    local sbfGainMap = {
      '-INF', '-52.3', '-51.0', '-49.7', '-48.5', '-47.3', '-46.2', '-45.1',
      '-44.0', '-43.0', '-42.0', '-41.1', '-40.2', '-39.3', '-38.5', '-37.7',
      '-36.9', '-36.2', '-35.5', '-34.8', '-34.2', '-33.6', '-33.0', '-32.4',
      '-31.8', '-31.3', '-30.8', '-30.3', '-29.8', '-29.4', '-28.9', '-28.5',
      '-28.1', '-27.7', '-27.4', '-27.0', '-26.6', '-26.3', '-26.0', '-25.6',
      '-25.3', '-25.0', '-24.7', '-24.4', '-24.1', '-23.8', '-23.6', '-23.3',
      '-23.0', '-22.7', '-22.5', '-22.2', '-21.9', '-21.6', '-21.4', '-21.1',
      '-20.8', '-20.6', '-20.3', '-20.0', '-19.7', '-19.4', '-19.1', '-18.8',
      '-18.6', '-18.2', '-17.9', '-17.6', '-17.3', '-17.0', '-16.7', '-16.3',
      '-16.0', '-15.6', '-15.3', '-14.9', '-14.5', '-14.2', '-13.8', '-13.4',
      '-13.0', '-12.6', '-12.2', '-11.7', '-11.3', '-10.9', '-10.4', '-10.0',
      '-9.5', '-9.1', '-8.6', '-8.2', '-7.7', '-7.2', '-6.7', '-6.2',
      '-5.7', '-5.2', '-4.7', '-4.2', '-3.7', '-3.2', '-2.6', '-2.1',
      '-1.6', '-1.1', '-0.5', '0.0', '+0.5', '+1.1', '+1.6', '+2.1',
      '+2.6', '+3.2', '+3.7', '+4.2', '+4.7', '+5.2', '+5.7', '+6.2',
      '+6.7', '+7.2', '+7.6', '+8.1', '+8.5', '+9.0', '+9.4', '+10.0'
    }

    function getSBFGain(value)
      return sbfGainMap[value]
    end
  ]],

  getTapeSpeed = [[
    local tapeSpeedMap = {
      10, 12, 13, 15, 17, 18, 20, 22, 24, 25, 
      27, 29, 31, 33, 35, 37, 39, 42, 44, 46, 
      48, 50, 53, 55, 58, 60, 63, 65, 68, 70, 
      73, 76, 79, 82, 84, 87, 90, 93, 97, 100, 
      103, 106, 110, 113, 117, 120, 124, 127, 131, 
      135, 139, 143, 147, 151, 155, 159, 164, 168, 
      172, 177, 182, 186, 191, 196, 201, 206, 211, 
      217, 222, 227, 233, 239, 244, 250, 256, 262, 
      269, 275, 281, 288, 294, 301, 308, 315, 322, 
      330, 337, 345, 352, 360, 368, 376, 385, 393, 
      402, 410, 419, 428, 437, 447, 456, 466, 476, 
      486, 496, 507, 518, 528, 539, 551, 562, 574, 
      586, 598, 610, 623, 635, 648, 662, 675, 689, 
      703, 717, 731, 746, 761, 777, 800
    }

    function getTapeSpeed(value)
      return tapeSpeedMap[value]
    end  
  ]],

  getZeroNinetyNine = [[
    function getZeroNinetyNine(value)
      local midiValue = value - 1
      if midiValue == 127 then
        return 99
      else
        return math.floor((midiValue / 127.5) * 99)
      end    
    end  
  ]],

  get48dB = [[
    function get48dB(value)
      local midiValue = value - 1
      local dbValue = math.floor((midiValue / 127.5) * 49)
      return dbValue
    end
  ]],

  getLooperLength = [[
    function getLooperLength(value)
      local midiValue = value - 1    
      if midiValue == 127 then
        return 0.012
      else
        local looperValue = 0.230 - (midiValue / 127.5 * 0.218)
        looperValue = math.floor(looperValue * 1000 + 0.5) / 1000
        looperValue = string.format("%.3f", looperValue)
        return looperValue
      end
    end
  ]],

  getFilterType = [[
    function getFilterType(value)
      local filterTypes = {'High-pass', 'Low-pass'}
      return filterTypes[value]
    end
  ]],

  getRoot = [[
    local rootNotes = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'}
    local rootOctaves = {'-1', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'}
    
    function getRoot(value)
      local midiValue = value - 1
      local rootNote = rootNotes[(midiValue % 12) + 1]
      local rootOctave = rootOctaves[math.floor(midiValue / 12) + 1]
      return rootNote..rootOctave
    end
  ]],

  getChord = [[
    local chords = {
      'Root', 'Oct', 'UpDn', 'P5', 
      'm3', 'm5', 'm7', 'm7oct', 
      'm0', 'm11', 'M3', 'M5', 
      'M7', 'M7oct', 'M9', 'M11'
    }

    function getChord(value)
      local chord = chords[value]
      return chord
    end
  ]],

  getDelayTimes = [[
    local delayTimes = {
        '1/32', '1/16T', '1/32D', '1/16', 
        '1/8T', '1/16D', '1/8', '1/4T', 
        '1/8D', '1/4', '1/2T', '1/4D', 
        '1/2', '1/1T', '1/2D', '1/1'
    }

    function getDelayTimes(value)
      local delayTime = delayTimes[value]
      return delayTime
    end
  ]],

  getLDampFValues = [[
    local lDampFValues = {'FLAT', '80', '100', '125', '160', '200', '250', '315', '400', '500', '630', '800'}

    function getLDampFValues(value)
      local lDampFValue = lDampFValues[value]
      return lDampFValue
    end
  ]],   

  getHDampFValues = [[
    local hDampFValues = {'630', '800', '1000', '1250', '1600', '2000', '2500', '3150', '4000', '5000', '6300', '8000', '10000', '12500', 'FLAT'}

    function getHDampFValues(value)
      local hDampFValue = hDampFValues[value]
      return hDampFValue
    end
  ]],

  getOnOff = [[
    local onOff = {'Off', 'On'}
        
    function getOnOff(value)
      return onOff[value]
    end
  ]],

  getScatterSpeed = [[
    local speeds = {'SINGLE', 'DOUBLE'}
      
    function getScatterSpeed(value)
      return speeds[value]
    end
  ]],  

  getScatterType = [[
    local types = {'1', '2', '3', '4', '5', '6', '7', '8', '9', '10'}
      
    function getScatterType(value)
      local type = types[value]
      return type
    end
  ]],  
  
  getScatterDepth = [[
    local depths = {'10', '20', '30', '40', '50', '60', '70', '80', '90', '100'}
      
    function getScatterDepth(value)
      local depth = depths[value]
      return depth
    end
  ]], 
  
  getPitchOnOff = [[
    local pitchOnOff = {'PITCH OFF', 'PITCH ON'}
      
    function getPitchOnOff(value)
      return pitchOnOff[value]
    end
  ]],

  getDownerRate = [[
    local downerRates = {'2/1', '1/1', '1/2', '1/4', '1/8', '1/16', '1/32'}

    function getDownerRate(value)
      local downerRate = downerRates[value]
      return downerRate
    end
  ]],

  getLowCut = [[
    local lowCutValues = {'FLAT', '20', '25', '31', '40', '50', '63', '80', '100', '125', '160', '200', '250', '315', '400', '500', '630', '800'}

    function getLowCut(value)
      local lowCutValue = lowCutValues[value]
      return lowCutValue
    end
  ]],

  getHighCut = [[
    local highCutValues = {'630', '800', '1000', '1250', '1600', '2000', '2500', '3150', '4000', '5000', '6300', '8000', '10000', '12500', 'FLAT'}

    function getHighCut(value)
      local highCutValue = highCutValues[value]
      return highCutValue
    end
  ]],

  getKoDaMaMode = [[
    local koDaMaModes = {'SINGLE MODE', 'PAN MODE'}

    function getKoDaMaMode(value)
      return koDaMaModes[value]
    end
  ]],

  getZanZouMode = [[
    local zanZouModes = {'2TAP', '3TAP', '4TAP'}

    function getZanZouMode(value)
      local zanZouMode = zanZouModes[value]
      return zanZouMode
    end
  ]],

  getSync = [[
    local sync = {'SYNC OFF', 'SYNC ON'}

    function getSync(value)
      return sync[value]
    end
  ]],

  getHFDampValues = [[
    local hfDampValues = {'200', '250', '315', '400', '500', '630', '800', '1000', '1250', '1600', '2000', '2500', '3150', '4000', '5000', '6300', '8000', 'OFF'}

    function getHFDampValues(value)
      local hfDampValue = hfDampValues[value]
      return hfDampValue
    end
  ]],

  getToGuRoRate = [[
    local rates = {
      '2/1', '1/1', '1/2', '1/4', 
      '1/8', '1/16', '1/32', '1/64', 
      '1/128'
    }

    function getToGuRoRate(value)
      local rate = rates[value]
      return rate
    end
  ]],

  getSBFType = [[
    local sbfTypes = {'SBF1', 'SBF2', 'SBF3', 'SBF4', 'SBF5', 'SBF6'}

    function getSBFType(value)
      local sbfType = sbfTypes[value]
      return sbfType
    end
  ]],

  getStopperRate = [[
  local rates = {'4/1', '2/1', '1/1', '1/2', '1/4', '1/8', '1/16', '1/32', '1/64'}

    function getStopperRate(value)
      local rate = rates[value]
      return rate
    end
  ]],

  getTapeEchoMode = [[
    local modes = {'S', 'M', 'L', 'S+M', 'S+L', 'M+L', 'S+M+L'}

    function getTapeEchoMode(value)
      local mode = modes[value]
      return mode
    end
  ]],
}

-- CONTROL SCRIPTS *******************************************
local faderScriptTemplate = [[
  local amSyncFader = %s
  local labelName = '%s'
  %s  -- Include the mapping function definition here
  local startValues = %s

  function midiToFloat(midiValue)
    local floatValue = midiValue / 127
    return floatValue
  end

  function floatToMIDI(floatValue)
    local midiValue = math.floor(floatValue * 127 + 0.5)
    return midiValue
  end

  local function findRange(ranges, target)
    --print("Finding range for target: " .. tostring(target))
    
    for i, rangeStart in ipairs(ranges) do
      -- Special handling for the last range when it starts at 127
      if i == #ranges and rangeStart == 127 then
        if target == 127 then
          return i
        else
          return i - 1
        end
      end

      local rangeEnd = ranges[i + 1] or 128
      --print("Checking range " .. tostring(i) .. ": " .. tostring(rangeStart) .. " to " .. tostring(rangeEnd - 1))
      if target >= rangeStart and target < rangeEnd then
        --print("Found range " .. tostring(i))
        return i
      end
    end

    -- Should never reach here if ranges are properly defined
    return 1
  end

  function floatToRange(floatValue)

    local midiValue = math.floor(floatValue * 127 + 0.5)

    if next(startValues) == nil then
      -- Return full midi range as the range
      local index = midiValue + 1
      --print("Returning index in full midi range:", index)
      return index
    end

    --print("floatToRange called with floatValue:", floatValue, "startValues:", startValues)
    
    local index = findRange(startValues, midiValue)

    --print("Index in grid range:", index)
    
    return index
  end

  function updateLabel(value)
    local label = self.parent:findByName(labelName)
    local newText = %s(value)  -- Just use the function name directly
    --print("Updating label '" .. tostring(labelName) .. "' with value: " .. tostring(newText))
    label:notify('update_text', newText)
  end

  local gridToNotify = '%s'

  function notifyGrid(value)
    local rangeIndex = value
    --print("Fader float: " .. tostring(value) .. " to Range: " .. tostring(rangeIndex))
    local gridControl = self.parent:findByName(gridToNotify, true)
    gridControl:notify('new_index', rangeIndex)
  end

  function onReceiveNotify(key, value)
    if key == 'new_value' then
      self.values.x = value
      local index = 0

      if amSyncFader then
        -- Override the index, as it's being used for the grid
        -- not our label
        index = floatToMIDI(value) + 1
      else
        index = floatToRange(value)
      end

      updateLabel(index)
    elseif key == 'new_cc_value' then
      local floatValue = midiToFloat(value)
      self.values.x = floatValue

      local index = 0
      if amSyncFader then
        -- Override the index, as it's being used for the grid
        -- not our label
        index = value + 1
      else
        index = floatToRange(floatValue)
      end

      updateLabel(index)
    end
  end

  function onValueChanged(value)
    if value == 'x' then
      local index = 0
      local gridIndex = floatToRange(self.values.x)

      if amSyncFader then
        -- Override the index, as it's being used for the grid
        -- not our label
        index = floatToMIDI(self.values.x) + 1
      else
        index = gridIndex
      end

      updateLabel(index)
      if gridToNotify ~= '' then
        notifyGrid(gridIndex)
      end
    end
  end
]]

local labelScriptTemplate = [[
  local labelFormat = "%s"

  function onReceiveNotify(key, value)
    if key == 'update_text' then
      local labelText = string.format(labelFormat, tostring(value))
      self.values.text = labelText
    end
  end
]]

local gridScriptTemplate = [[
  local startValues = %s 
  local targetGridName = '%s'
  local syncedFaderName = '%s'
  local amSyncGrid = %s

  function init()
    if self.name ~= targetGridName then
      self.outline = true
      self.outlineStyle = OutlineStyle.FULL
    else
      self.outline = false
    end
  end

  function toggleTimeViews(showFader)
    local fader = self.parent.parent:findByName('%s')
    local faderLabel = self.parent.parent:findByName('%s')
    local grid = self.parent.parent:findByName('%s')
    local gridLabel = self.parent.parent:findByName('%s')
    
    fader.visible = showFader
    faderLabel.visible = showFader
    grid.visible = not showFader
    gridLabel.visible = not showFader
  end

  function onValueChanged(key, value)
    if self.name ~= targetGridName and key == 'x' and self.values.x == 1 and self.parent.tag == '1' then
      local myCCValue = startValues[self.index] -- Already in 0-127 range
      local syncedFader = self.parent.parent:findByName(syncedFaderName)
      syncedFader:notify('new_cc_value', myCCValue)
      
      if amSyncGrid then
        toggleTimeViews(self.index == 1)
      end

    elseif self.name == targetGridName and key == 'touch' then
      -- We're taking control
      self.tag = 1
    end
  end

  function onReceiveNotify(key, value)
    if key == 'new_child_value' then
      self.values.x = 1
    elseif key == 'new_index' then
      --print("Received value: " .. tostring(value))
      local childToSelect = value

      -- Relinquish control, because we received input
      -- from outside
      self.tag = 0
      self.children[childToSelect]:notify('new_child_value')
    end
  end
]]

function generateAndAssignFaderScript(controlGroup, controlInfo)
  local faderName, _, labelName, labelMapping, _, gridName, startValues, amSyncFader, _, _, _, _ = table.unpack(controlInfo)

  if not startValues or startValues == '' then
    -- Just so we don't break the script
    startValues = '{}'
  end

  if not amSyncFader then
    amSyncFader = 'false'
  end

  print('Generating fader script for:', faderName, labelName, labelMapping, gridName, startValues, amSyncFader, mappingScripts[labelMapping])

  local faderScript = string.format(faderScriptTemplate, 
    amSyncFader,
    labelName,
    mappingScripts[labelMapping],
    startValues,
    labelMapping,
    gridName)

  -- Find the fader object
  local faderObject = controlGroup:findByName(faderName, true)
  if faderObject then
    -- Assign the generated script
    faderObject.script = faderScript
  end
end

function generateAndAssignLabelScript(controlGroup, controlInfo)
  local _, _, labelName, _, labelFormat, _, _, _, _, _, _, _ = table.unpack(controlInfo)

  -- Generate and assign label script
  local labelObject = controlGroup:findByName(labelName, true)
  local labelScript = string.format(labelScriptTemplate, labelFormat)
  if labelObject then
    labelObject.script = labelScript
  end
end

function generateAndAssignGridScript(controlGroup, controlInfo)
  -- Generate and assign grid script
  local faderName, _, _, _, _, gridName, startValues, _, showHideFader, showHideFaderLabel, showHideGrid, showHideGridLabel = table.unpack(controlInfo)

  local amSyncGrid = 'true'
  if not showHideFader then
    amSyncGrid = 'false'
    showHideFader = ''
    showHideFaderLabel = ''
    showHideGrid = ''
    showHideGridLabel = ''
  end

  print('Generating grid script for:', faderName, gridName, startValues, amSyncGrid, showHideFader, showHideFaderLabel, showHideGrid, showHideGridLabel)

  local gridScript = string.format(gridScriptTemplate, 
    startValues,
    gridName,
    faderName,
    amSyncGrid,
    showHideFader,
    showHideFaderLabel,
    showHideGrid,
    showHideGridLabel)

  -- Find the grid object
  local gridObject = controlGroup:findByName(gridName, true)
  if gridObject then
    -- Assign the generated script
    gridObject.script = gridScript
  end
end

-- Example control info array elements (controlsInfoArray[i])

-- 1) Simple fader
-- {'feedback_fader', false, 'feedback_label', 'getZeroNinetyNine', 'FEEDBACK: %s', ''},

-- 2) Fader with synced grid
-- {'zan_zou_time_fader', false, 'zan_zou_time_label', 'getZeroOneHundred', 'TIME: %s', 'zan_zou_time_grid'},
--   '{0, 9, 17, 28, 36, 44, 52, 60, 68, 77, 87, 95, 103, 114, 122, 127}'}

-- 3) Synced fader
--  {'zan_zou_sync_fader', false, 'zan_zou_sync_label', 'getSync', '%s', 'zan_zou_sync_grid',
-- '{0, 64}', 'zan_zou_time_fader', 'zan_zou_time_label', 'zan_zou_time_grid', 'zan_zou_time_label_grid'}

-- Full list of control info parameters:
-- 1) Fader name
-- 2) Is excludable (true/false)
-- 3) Label name
-- 4) Label mapping function
-- 5) Label format string
-- 6) Synced grid (optional)
-- 7) Grid ranges (optional, used for grids)
-- 8) Am synced fader (optional, used for sync grids)
-- 9) Show/hide fader name (optional, used for sync grids)
-- 10) Show/hide fader label name (optional, used for sync grids)
-- 11) Show/hide grid name (optional, used for sync grids)
-- 12) Show/hide grid label name (optional, used for sync grids)

function init()
  for i, category in ipairs(controlsInfoArray) do
    print('Initialising category with fxPage:', i)
    local fxPage = root.children.control_pager.children[i]
    print('fxPage:', fxPage.name)
    local controlGroup = fxPage.children.control_group
    print('controlGroup:', controlGroup.name)
        
    for _, controlInfo in ipairs(category) do
      local controlName, _, labelName, labelMapping, labelFormat, syncedGrid = table.unpack(controlInfo)
      
      -- Skip controls without extra values (while WIP)
      -- Can remove this check once all controls have been updated
      if labelName then
        print('Initialising control:', controlName, labelName, labelMapping, labelFormat, syncedGrid)
        
        generateAndAssignFaderScript(controlGroup, controlInfo)
        generateAndAssignLabelScript(controlGroup, controlInfo)
        
        if syncedGrid ~= '' then
          generateAndAssignGridScript(controlGroup, controlInfo)
        end
      end
    end
  end
end

--************************************************************
-- MIDI HANDLING
--************************************************************
function floatToMIDI(floatValue)
  local midiValue = math.floor(floatValue * 127 + 0.5)
  return midiValue
end

function midiToFloat(midiValue)
  local floatValue = midiValue / 127
  return floatValue
end

function syncMIDI(midiCC, ccValue)
  sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, midiCC, ccValue })
end

function onReceiveNotify(key, value)
  print('Action requested:', key, value)
  if key == 'change_fx' then
    fxNum = value
  elseif key == 'channel' then
    midiChannel = value
  elseif key == 'store_fx_preset' then
    
    local controlInfoArray = controlsInfoArray[fxNum]
    ccValues = defaultCCValues
  
    local fxPage = root.children.control_pager.children[fxNum]
    local controlGroup = fxPage.children.control_group

    -- Debugging information
    print('fxNum:', fxNum)
    print('Storing MIDI values:', unpack(ccValues))
    print('Controls:', unpack(controlInfoArray))
    print('Control group:', controlGroup.name)
    print('Control group tag:', controlGroup.tag)
    
    for index, controlInfo in ipairs(controlInfoArray) do
      local controlObject = controlGroup:findByName(controlInfo[1], true)
      --print('Control object:', controlObject.name)
      if controlObject.type == ControlType.LABEL or controlObject.type == ControlType.GRID then
        ccValues[index] = tonumber(controlObject.tag)
      else
        ccValues[index] = floatToMIDI(controlObject.values.x)
      end
    end

    print('Current MIDI values:', unpack(ccValues))

    local presetNum = value
    local presetIndex = tostring(fxNum)..' '..tostring(presetNum)
    --print('Preset Index:', presetIndex)

    presetManager:notify('store_preset', {presetIndex, ccValues})
  
  elseif key == 'recall_preset' then
    local controlInfoArray = controlsInfoArray[fxNum]
    ccValues = value
    print('Recalling MIDI values:', unpack(ccValues))

    local fxPage = root.children.control_pager.children[fxNum]
    local controlGroup = fxPage.children.control_group

    local exclude_marked_presets = false
    
    if controlGroup.tag == '1' then
      --print('Excluding marked presets')
      exclude_marked_presets = true
    end
    
    for index, controlInfo in ipairs(controlInfoArray) do
      local controlObject = controlGroup:findByName(controlInfo[1], true)
      local isExcludable = controlInfo[2]

      print(index, controlObject.name, controlObject.type, isExcludable, exclude_marked_presets)
      
      if not isExcludable or not exclude_marked_presets then
        if controlObject.type == ControlType.LABEL then
          controlObject:notify('new_value', ccValues[index])
        elseif controlObject.type == ControlType.GRID then
          controlObject:notify('change_selection', ccValues[index])
        else
          -- Need to force update here
          controlObject:notify('new_value', midiToFloat(ccValues[index]))
        end

        syncMIDI(midiCCs[index], ccValues[index])
      end
    end
    print('Recalled MIDI values:', unpack(ccValues))
  end
end