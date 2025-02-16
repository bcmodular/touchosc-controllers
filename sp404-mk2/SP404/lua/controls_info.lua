local controlsInfoArray = {
  -- Array structure:
  -- 1) MIDI CC number
  -- 2) Fader name
  -- 3) Is excludable (true/false)
  -- 4) Label text
  -- 5) Label name
  -- 6) Label mapping function
  -- 7) Label format string
  -- 8) Synced grid (optional)
  -- 9) Synced label grid (optional)
  -- 10) Synced label grid mapping function (optional)
  -- 11) Start values of ranges (optional, used for grids)
  -- 12) Am synced fader (optional, used for sync grids)
  -- 13) Show/hide fader name (optional, used for sync grids)
  -- 14) Show/hide fader label name (optional, used for sync grids)
  -- 15) Show/hide grid name (optional, used for sync grids)
  -- 16) Show/hide grid label name (optional, used for sync grids)
  
  [1] = { -- filter + drive
    {16, 'cutoff_fader', false, 'CUTOFF', 'cutoff_label', 'getFreq', '%s Hz', ''},
    {17, 'resonance_fader', false, 'RESONANCE', 'resonance_label', 'getZeroOneHundred', '%s', ''},
    {18, 'drive_fader', false, 'DRIVE', 'drive_label', 'getZeroOneHundred', '%s', ''},
    {80, 'filter_type_fader', false, 'FILTER TYPE', 'filter_type_label', 'getFilterType', '%s', 'filter_type_grid', 'filter_type_label_grid', 'getFilterType',
      '{0, 64}'},
    {81, 'low_freq_fader', false, 'LOW FREQ', 'low_freq_label', 'getFreq', '%s Hz', ''},
    {82, 'low_gain_fader', false, 'LOW GAIN', 'low_gain_label', 'get24dB', '%s dB', ''}
  },
  [2] = { -- resonator
    {16, 'root_fader', true, 'ROOT', 'root_value_label', 'getRoot', '%s', ''},
    {17, 'bright_fader', false, 'BRIGHT', 'bright_value_label', 'getZeroOneHundred', '%s', ''},
    {18, 'feedback_fader', false, 'FEEDBACK', 'feedback_value_label', 'getZeroNinetyNine', '%s%%', ''},
    {80, 'chord_fader', true, 'CHORD', 'chord_label', 'getChord', '%s', 'chord_grid', 'chord_label_grid', 'getChord',
      '{0, 9, 17, 25, 33, 41, 49, 57, 65, 73, 81, 89, 97, 105, 113, 121}'},
    {81, 'panning_fader', false, 'PAN', 'panning_value_label', 'getZeroOneHundred', '%s', ''},
    {82, 'env_mod_fader', false, 'ENV MOD', 'env_mod_value_label', 'getZeroOneHundred', '%s', ''}
  },
  [3] = { -- sync delay
    {16, 'delay_time_fader', false, 'DELAY TIME', 'delay_time_label', 'getDelayTimes', '%s', 'delay_time_grid', 'delay_time_label_grid', 'getDelayTimes',
      '{0, 9, 17, 25, 33, 41, 49, 57, 65, 73, 81, 89, 97, 105, 113, 121}'},
    {17, 'feedback_fader', false, 'FEEDBACK', 'feedback_label', 'getZeroNinetyNine', '%s%%', ''},
    {18, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''},
    {80, 'l_damp_f_fader', false, 'L DAMP', 'l_damp_f_label', 'getLDampFValues', '%s Hz', 'l_damp_f_grid', 'l_damp_f_label_grid', 'getLDampFValues',
      '{0, 11, 22, 33, 44, 55, 65, 76, 87, 98, 109, 119}'},
    {81, 'h_damp_f_fader', false, 'H DAMP', 'h_damp_f_label', 'getHDampFValues', '%s Hz', 'h_damp_f_grid', 'h_damp_f_label_grid', 'getHDampFValues',
      '{0, 9, 18, 26, 35, 43, 52, 60, 69, 77, 86, 94, 103, 111, 120}'}
  },
  [4] = { -- isolator
    {16, 'low_fader', false, 'LOW', 'low_label', 'getEQ', '%s', ''},
    {17, 'mid_fader', false, 'MID', 'mid_label', 'getEQ', '%s', ''},
    {18, 'high_fader', false, 'HIGH', 'high_label', 'getEQ', '%s', ''}
  },
  [5] = { -- djfx looper
    {16, 'length_fader', false, 'LENGTH', 'length_label', 'getLooperLength', '%s s', ''},
    {17, 'speed_fader', false, 'SPEED', 'speed_label', 'getBipolarHundred', '%s', ''},
    {18, 'on_off_fader', false, 'ON/OFF', 'on_off_label', 'getOnOff', '%s', 'on_off_grid', 'on_off_label_grid', 'getOnOff',
        '{0, 64}'}
  },
  [6] = { -- scatter
    {16, 'scatter_type_fader', false, 'TYPE', 'scatter_type_label', 'getScatterType', '%s', 'scatter_type_grid', 'scatter_type_label_grid', 'getScatterType',
      '{0, 13, 26, 39, 52, 65, 77, 90, 103, 115}'},
    {17, 'scatter_depth_fader', false, 'DEPTH', 'scatter_depth_label', 'getScatterDepth', '%s', 'scatter_depth_grid', 'scatter_depth_label_grid', 'getScatterDepth',
      '{0, 13, 26, 39, 52, 65, 77, 90, 103, 115}'},
    {18, 'on_off_fader', false, 'ON/OFF', 'on_off_label', 'getOnOff', '%s', 'on_off_grid', 'on_off_label_grid', 'getOnOff',
      '{0, 64}'},
    {80, 'scatter_speed_fader', false, 'SPEED', 'scatter_speed_label', 'getScatterSpeed', '%s', 'scatter_speed_grid', 'scatter_speed_label_grid', 'getScatterSpeed',
      '{0, 64}'}
  },
  [7] = { -- downer
    {16, 'depth_fader', false, 'DEPTH', 'depth_label', 'getZeroOneHundred', '%s', ''},
    {17, 'rate_fader', false, 'RATE', 'rate_label', 'getDownerRate', '%s', 'rate_grid', 'rate_label_grid', 'getDownerRate',
      '{0, 19, 37, 55, 73, 91, 127}'},
    {18, 'filter_fader', false, 'FILTER', 'filter_label', 'getZeroOneHundred', '%s', ''},
    {80, 'pitch_on_off_fader', false, 'PITCH', 'pitch_on_off_label', 'getPitchOnOff', '%s', 'pitch_on_off_grid', 'pitch_on_off_label_grid', 'getPitchOnOff',
      '{0, 64}'},
    {81, 'resonance_fader', false, 'RESONANCE', 'resonance_label', 'getZeroOneHundred', '%s', ''}
  },
  [8] = { -- ha dou
    {16, 'mod_depth_fader', false, 'MOD DEPTH', 'mod_depth_label', 'getZeroOneHundred', '%s', ''},
    {17, 'time_fader', false, 'TIME', 'time_label', 'getZeroOneHundred', '%s', ''},
    {18, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''},
    {80, 'low_cut_fader', false, 'LOW CUT', 'low_cut_label', 'getLowCut', '%s', 'low_cut_grid', 'low_cut_label_grid', 'getLowCut',
      '{0, 8, 15, 22, 29, 36, 43, 50, 57, 64, 71, 78, 85, 95, 102, 109, 116, 123}'},
    {81, 'high_cut_fader', false, 'HIGH CUT', 'high_cut_label', 'getHighCut', '%s', 'high_cut_grid', 'high_cut_label_grid', 'getHighCut',
      '{0, 9, 18, 26, 35, 43, 52, 60, 69, 77, 86, 94, 103, 111, 120}'},
    {82, 'pre_delay_fader', false, 'PRE DELAY', 'pre_delay_label', 'getHundredMS', '%s ms', ''}
  },
  [9] = { -- ko da ma
    {16, 'time_fader', false, 'TIME', 'time_label', 'getDelayTimes', '%s', 'time_grid', 'time_label_grid', 'getDelayTimes',
      '{0, 9, 17, 25, 33, 41, 49, 57, 65, 73, 81, 89, 97, 105, 113, 121}'},
    {17, 'feedback_fader', false, 'FEEDBACK', 'feedback_label', 'getZeroNinetyNine', '%s%%', ''},
    {18, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''},
    {80, 'l_damp_f_fader', false, 'L DAMP', 'l_damp_f_label', 'getLDampFValues', '%s', 'l_damp_f_grid', 'l_damp_f_label_grid', 'getLDampFValues',
      '{0, 11, 22, 33, 44, 55, 65, 76, 87, 98, 109, 119}'},
    {81, 'h_damp_f_fader', false, 'H DAMP', 'h_damp_f_label', 'getHDampFValues', '%s', 'h_damp_f_grid', 'h_damp_f_label_grid', 'getHDampFValues',
      '{0, 9, 18, 26, 35, 43, 52, 60, 69, 77, 86, 94, 103, 111, 120}'},
    {82, 'mode_fader', false, 'MODE', 'mode_label', 'getKoDaMaMode', '%s', 'mode_grid', 'mode_label_grid', 'getKoDaMaMode',
      '{0, 64}'}
  },
  [10] = { -- zan zou
    {16, 'time_fader', false, 'TIME', 'time_label', 'getSyncDelayTimes', '%s', 'time_grid', 'time_label_grid', 'getSyncDelayTimes',
      '{0, 9, 17, 28, 36, 44, 52, 60, 68, 77, 87, 95, 103, 114, 122, 127}', 'true'},
    {17, 'feedback_fader', false, 'FEEDBACK', 'feedback_label', 'getZeroNinetyNine', '%s', ''},
    {18, 'hf_damp_fader', false, 'HF DAMP', 'hf_damp_label', 'getHFDampValues', '%s', 'hf_damp_grid', 'hf_damp_label_grid', 'getHFDampValues',
      '{0, 8, 15, 22, 29, 36, 43, 50, 57, 64, 71, 78, 85, 95, 102, 109, 116, 123}'},
    {80, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''},
    {81, 'mode_fader', false, 'MODE', 'mode_label', 'getZanZouMode', '%s', 'mode_grid', 'mode_label_grid', 'getZanZouMode',
      '{0, 43, 86}'},
    {82, 'sync_fader', false, 'SYNC', 'sync_label', 'getSync', '%s', 'sync_grid', 'sync_label_grid', 'getSync',
      '{0, 64}', 'false', 'time_fader', 'time_label', 'time_grid', 'time_label_grid'}
  },
  [11] = { -- to gu ro
    {16, 'depth_fader', false, 'DEPTH', 'depth_label', 'getZeroOneHundred', '%s', ''},
    {17, 'rate_fader', false, 'RATE', 'rate_label', 'getToGuRoRate', '%s', 'rate_grid', 'rate_label_grid', 'getToGuRoRate',
      '{0, 16, 32, 48, 64, 80, 96, 112, 127}', 'true'},
    {18, 'resonance_fader', false, 'RESONANCE', 'resonance_label', 'getZeroOneHundred', '%s', ''},
    {80, 'flt_mod_fader', false, 'FLT MOD', 'flt_mod_label', 'getZeroOneHundred', '%s', ''},
    {81, 'amp_mod_fader', false, 'AMP MOD', 'amp_mod_label', 'getZeroOneHundred', '%s', ''},
    {82, 'sync_fader', false, 'SYNC', 'sync_label', 'getSync', '%s', 'sync_grid', 'sync_label_grid', 'getSync',
      '{0, 64}', 'false', 'rate_fader', 'rate_label', 'rate_grid', 'rate_label_grid'},
  },
  [12] = { -- sbf
    {16, 'interval_fader', false, 'INTERVAL', 'interval_label', 'getZeroOneHundred', '%s', ''},
    {17, 'width_fader', false, 'WIDTH', 'width_label', 'getZeroOneHundred', '%s', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''},
    {80, 'sbf_type_fader', false, 'TYPE', 'sbf_type_label', 'getSBFType', '%s', 'sbf_type_grid', 'sbf_type_label_grid', 'getSBFType',
      '{0, 25, 51, 76, 102, 127}'},
    {81, 'gain_fader', false, 'GAIN', 'gain_label', 'getSBFGain', '%s dB', ''}
  },
  [13] = { -- stopper
    {16, 'depth_fader', false, 'DEPTH', 'depth_label', 'getZeroOneHundred', '%s', ''},
    {17, 'rate_fader', false, 'RATE', 'rate_label', 'getStopperRate', '%s', 'rate_grid', 'rate_label_grid', 'getStopperRate',
      '{0, 16, 32, 48, 64, 80, 96, 112, 127}'},
    {18, 'resonance_fader', false, 'RESONANCE', 'resonance_label', 'getZeroOneHundred', '%s', ''},
    {80, 'flt_mod_fader', false, 'FLT MOD', 'flt_mod_label', 'getZeroOneHundred', '%s', ''},
    {81, 'amp_mod_fader', false, 'AMP MOD', 'amp_mod_label', 'getZeroOneHundred', '%s', ''}
  },
  [14] = { -- tape echo
    {16, 'time_fader', false, 'TIME', 'time_label', 'getTapeSpeed', '%s ms', ''},
    {17, 'feedback_fader', false, 'FEEDBACK', 'feedback_label', 'getZeroNinetyNine', '%s %%', ''},
    {18, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''},
    {80, 'mode_fader', false, 'MODE', 'mode_label', 'getTapeEchoMode', '%s', 'mode_grid', 'mode_label_grid', 'getTapeEchoMode',
      '{0, 19, 37, 55, 73, 91, 110}'},
    {81, 'wf_rate_fader', false, 'WF RATE', 'wf_rate_label', 'getZeroOneHundred', '%s', ''},
    {82, 'wf_depth_fader', false, 'WF DEPTH', 'wf_depth_label', 'getZeroOneHundred', '%s', ''}
  },
  [15] = { -- time ctrl delay
    {16, 'time_fader', false, 'TIME', 'time_label', 'getSyncDelayTimes', '%s', 'time_grid', 'time_label_grid', 'getSyncDelayTimes',
      '{0, 9, 17, 26, 34, 43, 51, 60, 68, 77, 85, 94, 102, 111, 119, 127}', 'true'},
    {17, 'feedback_fader', false, 'FEEDBACK', 'feedback_label', 'getZeroNinetyNine', '%s%%', ''},
    {18, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''},
    {80, 'l_damp_f_fader', false, 'L DAMP', 'l_damp_f_label', 'getLDampFValues', '%s', 'l_damp_f_grid', 'l_damp_f_label_grid', 'getLDampFValues',
      '{0, 11, 22, 32, 43, 54, 64, 75, 85, 96, 107, 117}'},
    {81, 'h_damp_f_fader', false, 'H DAMP', 'h_damp_f_label', 'getHDampFValues', '%s', 'h_damp_f_grid', 'h_damp_f_label_grid', 'getHDampFValues',
      '{0, 9, 17, 26, 34, 43, 51, 60, 68, 77, 85, 94, 102, 111, 119, 127}'},
    {82, 'sync_fader', false, 'SYNC', 'sync_label', 'getSync', '%s', 'sync_grid', 'sync_label_grid', 'getSync',
      '{0, 64}', 'false', 'time_fader', 'time_label', 'time_grid', 'time_label_grid'}
  },
  [16] = { -- super filter
    {16, 'cutoff_fader', false, 'CUTOFF', 'cutoff_label', 'getZeroOneHundred', '%s', ''},
    {17, 'resonance_fader', false, 'RESONANCE', 'resonance_label', 'getZeroOneHundred', '%s', ''},
    {18, 'filter_type_fader', false, 'TYPE', 'filter_type_label', 'getSuperFilterType', '%s', 'filter_type_grid', 'filter_type_label_grid', 'getSuperFilterType',
      '{0, 43, 85}'},
    {80, 'depth_fader', false, 'DEPTH', 'depth_label', 'getZeroOneHundred', '%s', ''},
    {81, 'rate_fader', false, 'RATE', 'rate_label', 'getFilterRate', '%s', 'rate_grid', 'rate_label_grid', 'getFilterRate',
      '{0, 7, 13, 19, 25, 31, 37, 43, 49, 55, 61, 67, 73, 79, 85, 92, 98, 104, 110, 116, 122, 127}', 'true'},
    {82, 'sync_fader', false, 'SYNC', 'sync_label', 'getSync', '%s', 'sync_grid', 'sync_label_grid', 'getSync',
      '{0, 64}', 'false', 'rate_fader', 'rate_label', 'rate_grid', 'rate_label_grid'}
  },
  [17] = { -- wrm saturator
    {16, 'drive_fader', false, 'DRIVE', 'drive_label', 'get48dB', '%s dB', ''},
    {17, 'eq_low_fader', false, 'EQ LOW', 'eq_low_label', 'get24dB', '%s dB', ''},
    {18, 'eq_high_fader', false, 'EQ HIGH', 'eq_high_label', 'get24dB', '%s dB', ''},
    {80, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''}
  },
  [18] = { -- 303 VinylSim
    {16, 'comp_fader', false, 'COMP', 'comp_label', 'getZeroOneHundred', '%s', ''},
    {17, 'noise_fader', false, 'NOISE', 'noise_label', 'getZeroOneHundred', '%s', ''},
    {18, 'wow_flut_fader', false, 'WOW FLUT', 'wow_flut_label', 'getZeroOneHundred', '%s', ''},
    {80, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''}
  },
  [19] = { -- 404 VinylSim
    {16, 'freq_fader', false, 'FREQ', 'freq_label', 'getZeroOneHundred', '%s', ''},
    {17, 'noise_fader', false, 'NOISE', 'noise_label', 'getZeroOneHundred', '%s', ''},
    {18, 'wow_flut_fader', false, 'WOW FLUT', 'wow_flut_label', 'getZeroOneHundred', '%s', ''}
  },
  [20] = { -- Cassette Sim
    {16, 'tone_fader', false, 'TONE', 'tone_label', 'getZeroOneHundred', '%s', ''},
    {17, 'hiss_fader', false, 'HISS', 'hiss_label', 'getZeroOneHundred', '%s', ''},
    {18, 'age_fader', false, 'AGE', 'age_label', 'getZeroSixty', '%s', ''},
    {80, 'drive_fader', false, 'DRIVE', 'drive_label', 'getZeroOneHundred', '%s', ''},
    {81, 'wow_flut_fader', false, 'WOW FLUT', 'wow_flut_label', 'getZeroOneHundred', '%s', ''},
    {82, 'catch_fader', false, 'CATCH', 'catch_label', 'getZeroOneHundred', '%s', ''},
  },
  [21] = { -- Lo-fi
    {16, 'pre_filt_fader', false, 'PRE FILTER', 'pre_filt_label', 'getPreFilter', '%s', 'pre_filt_grid', 'pre_filt_label_grid', 'getPreFilter',
      '{0, 22, 43, 64, 85, 107}'},
    {17, 'lofi_type_fader', false, 'LOFI TYPE', 'lofi_type_label', 'getLofiType', '%s', 'lofi_type_grid', 'lofi_type_label_grid', 'getLofiType',
      '{0, 15, 29, 43, 57, 71, 85, 100, 114}'},
    {18, 'tone_fader', false, 'TONE', 'tone_label', 'getBipolarHundredv2', '%s', ''},
    {80, 'cutoff_fader', false, 'CUTOFF', 'cutoff_label', 'getLofiCutoff', '%s', 'cutoff_grid', 'cutoff_label_grid', 'getLofiCutoff',
      '{0, 8, 15, 23, 30, 38, 45, 53, 60, 68, 75, 83, 90, 98, 105, 113, 120}'},
    {81, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''},
    {82, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''}
  },
  [22] = { -- reverb
    {16, 'type_fader', false, 'TYPE', 'type_label', 'getReverbType', '%s', 'type_grid', 'type_label_grid', 'getReverbType',
      '{0, 32, 64, 96}'},
    {17, 'time_fader', false, 'TIME', 'time_label', 'getZeroOneHundred', '%s', ''},
    {18, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''},
    {80, 'low_cut_fader', false, 'LOW CUT', 'low_cut_label', 'getLowCut', '%s', 'low_cut_grid', 'low_cut_label_grid', 'getLowCut',
      '{0, 8, 15, 22, 29, 36, 43, 50, 57, 64, 71, 78, 85, 95, 102, 109, 116, 123}'},
    {81, 'high_cut_fader', false, 'HIGH CUT', 'high_cut_label', 'getHighCut', '%s', 'high_cut_grid', 'high_cut_label_grid', 'getHighCut',
      '{0, 9, 18, 26, 35, 43, 52, 60, 69, 77, 86, 94, 103, 111, 120}'},
    {82, 'pre_delay_fader', false, 'PRE DELAY', 'pre_delay_label', 'getHundredMS', '%s ms', ''}
  },
  [23] = { -- chorus
    {16, 'depth_fader', false, 'DEPTH', 'depth_label', 'getZeroOneHundred', '%s', ''},
    {17, 'rate_fader', false, 'RATE', 'rate_label', 'getChorusRate', '%s sec', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''},
    {80, 'eq_low_fader', false, 'EQ LOW', 'eq_low_label', 'getChorusEQ', '%s dB', 'eq_low_grid', 'eq_low_label_grid', 'getChorusEQ',
      '{0, 5, 9, 13, 17, 21, 25, 29, 33, 37, 42, 46, 50, 54, 58, 62, 66, 70, 75, 79, 83, 87, 91, 95, 99, 103, 107, 112, 116, 120, 124}'},
    {81, 'eq_high_fader', false, 'EQ HIGH', 'eq_high_label', 'getChorusEQ', '%s dB', 'eq_high_grid', 'eq_high_label_grid', 'getChorusEQ',
    '{0, 5, 9, 13, 17, 21, 25, 29, 33, 37, 42, 46, 50, 54, 58, 62, 66, 70, 75, 79, 83, 87, 91, 95, 99, 103, 107, 112, 116, 120, 124}'},
    {82, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''},
  },
  [24] = { -- juno chorus
    {16, 'mode_fader', false, 'MODE', 'mode_label', 'getJunoChorusMode', '%s', 'mode_grid', 'mode_label_grid', 'getJunoChorusMode',
      '{0, 26, 51, 77, 102}'},
    {17, 'noise_fader', false, 'NOISE', 'noise_label', 'getZeroOneHundred', '%s', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''},
  },
  [25] = { -- flanger
    {16, 'depth_fader', false, 'DEPTH', 'depth_label', 'getZeroOneHundred', '%s', ''},
    {17, 'rate_fader', false, 'RATE', 'rate_label', 'getFlangerRate', '%s', '', '', '', '', 'true'},
    {18, 'manual_fader', false, 'MANUAL', 'manual_label', 'getZeroOneHundred', '%s', ''},
    {80, 'resonance_fader', false, 'RESONANCE', 'resonance_label', 'getZeroOneHundred', '%s', ''},
    {81, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''},
    {82, 'sync_fader', false, 'SYNC', 'sync_label', 'getSync', '%s', 'sync_grid', 'sync_label_grid', 'getSync',
      '{0, 64}', 'false', 'rate_fader', '', '', ''},
  },
  [26] = { -- phaser
    {16, 'depth_fader', false, 'DEPTH', 'depth_label', 'getZeroOneHundred', '%s', ''},
    {17, 'rate_fader', false, 'RATE', 'rate_label', 'getFlangerRate', '%s', '', '', '', '', 'true'},
    {18, 'manual_fader', false, 'MANUAL', 'manual_label', 'getZeroOneHundred', '%s', ''},
    {80, 'resonance_fader', false, 'RESONANCE', 'resonance_label', 'getZeroOneHundred', '%s', ''},
    {81, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''},
    {82, 'sync_fader', false, 'SYNC', 'sync_label', 'getSync', '%s', 'sync_grid', 'sync_label_grid', 'getSync',
      '{0, 64}', 'false', 'rate_fader', '', '', ''},
  },
  [27] = { -- wah
    {16, 'peak_fader', false, 'PEAK', 'peak_label', 'getZeroOneHundred', '%s', ''},
    {17, 'rate_fader', false, 'RATE', 'rate_label', 'getWahRate', '%s', '', '', '', '', 'true'},
    {18, 'manual_fader', false, 'MANUAL', 'manual_label', 'getZeroOneHundred', '%s', ''},
    {80, 'depth_fader', false, 'DEPTH', 'depth_label', 'getZeroOneHundred', '%s', ''},
    {81, 'filter_type_fader', false, 'TYPE', 'filter_type_label', 'getWahFilterType', '%s', 'filter_type_grid', 'filter_type_label_grid', 'getWahFilterType',
      '{0, 64}'},
    {82, 'sync_fader', false, 'SYNC', 'sync_label', 'getSync', '%s', 'sync_grid', 'sync_label_grid', 'getSync',
      '{0, 64}', 'false', 'rate_fader', '', '', ''},
  },
  [28] = { -- slicer
    {16, 'pattern_fader', false, 'PATTERN', 'pattern_label', 'getSlicerPattern', '%s', 'pattern_grid', 'pattern_label_grid', 'getSlicerPattern',
      '{0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 68, 72, 76, 80, 84, 88, 92, 96, 100, 104, 108, 112, 116, 120, 124}'},
    {17, 'speed_fader', false, 'SPEED', 'speed_label', 'getZeroOneHundred', '%s', 'speed_grid', 'speed_label_grid', 'getRate',
      '{0, 7, 13, 19, 25, 31, 37, 43, 49, 55, 61, 67, 73, 79, 85, 92, 98, 104, 110, 116, 122, 127}', 'true'},
    {18, 'depth_fader', false, 'DEPTH', 'depth_label', 'getZeroOneHundred', '%s', ''},
    {80, 'shuffle_fader', false, 'SHUFFLE', 'shuffle_label', 'getZeroOneHundred', '%s', ''},
    {81, 'mode_fader', false, 'MODE', 'mode_label', 'getSlicerMode', '%s', 'mode_grid', 'mode_label_grid', 'getSlicerMode',
      '{0, 64}'},
    {82, 'sync_fader', false, 'SYNC', 'sync_label', 'getSync', '%s', 'sync_grid', 'sync_label_grid', 'getSync',
      '{0, 64}', 'false', 'speed_fader', 'speed_label', 'speed_grid', 'speed_label_grid'}
  },
  [29] = { -- tremolo/pan
    {16, 'depth_fader', false, 'DEPTH', 'depth_label', 'getZeroOneHundred', '%s', ''},
    {17, 'rate_fader', false, 'RATE', 'rate_label', 'getWahRate', '%s', '', '', '', '', 'true'},
    {18, 'type_fader', false, 'TYPE', 'type_label', 'getTremoloPanType', '%s', 'type_grid', 'type_label_grid', 'getTremoloPanType',
      '{0, 64}'},
    {80, 'wave_fader', false, 'WAVE', 'wave_label', 'getTremoloPanWave', '%s', 'wave_grid', 'wave_label_grid', 'getTremoloPanWave',
      '{0, 22, 43, 64, 85, 107}'},
    {81, 'sync_fader', false, 'SYNC', 'sync_label', 'getSync', '%s', 'sync_grid', 'sync_label_grid', 'getSync',
      '{0, 64}', 'false', 'rate_fader', '', '', ''},
  },
  [30] = { -- chromatic PS
    {16, 'pitch1_fader', false, 'PITCH 1', 'pitch1_label', 'getPitch', '%s semi', ''},
    {17, 'pitch2_fader', false, 'PITCH 2', 'pitch2_label', 'getPitch', '%s semi', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''},
    {80, 'pan1_fader', false, 'PAN 1', 'pan1_label', 'getPan', '%s', ''},
    {81, 'pan2_fader', false, 'PAN 2', 'pan2_label', 'getPan', '%s', ''},
  },
  [31] = { -- hyper-reso
    {16, 'note_fader', true, 'NOTE', 'note_value_label', 'getNote', '%s', 'note_grid', 'note_label_grid', 'getNote',
      '{0, 4, 8, 11, 15, 19, 22, 26, 30, 33, 37, 41, 44, 48, 51, 55, 59, 62, 66, 70, 73, 77, 81, 84, 88, 92, 95, 99, 102, 106, 110, 113, 117, 121, 124}'},
    {17, 'spread_fader', false, 'SPREAD', 'spread_label', 'getSpread', '%s', 'spread_grid', 'spread_label_grid', 'getSpread',
      '{0, 26, 51, 77, 102}'},
    {18, 'character_fader', false, 'CHARACTER', 'character_value_label', 'getZeroOneHundred', '%s', ''},
    {80, 'scale_fader', true, 'SCALE', 'scale_label', 'getScale', '%s', 'scale_grid', 'scale_label_grid', 'getScale',
      '{0, 6, 11, 16, 22, 27, 32, 38, 43, 48, 54, 59, 64, 70, 75, 80, 85, 91, 96, 101, 107, 112, 117, 123}'},
    {81, 'feedback_fader', false, 'FEEDBACK', 'feedback_value_label', 'getZeroNinetyNine', '%s %%', ''},
    {82, 'env_mod_fader', false, 'ENV MOD', 'env_mod_value_label', 'getZeroOneHundred', '%s', ''}
  },
  [32] = { -- ring-mod
    {16, 'frequency_fader', false, 'FREQUENCY', 'frequency_label', 'getZeroOneHundred', '%s', ''},
    {17, 'sensitivity_fader', false, 'SENSITIVITY', 'sensitivity_label', 'getZeroOneHundred', '%s', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''},
    {80, 'polarity_fader', false, 'POLARITY', 'polarity_label', 'getOnOff', '%s', 'polarity_grid', 'polarity_label_grid', 'getOnOff',
      '{0, 64}'},
    {81, 'eq_low_fader', false, 'EQ LOW', 'eq_low_label', 'getChorusEQ', '%s dB', 'eq_low_grid', 'eq_low_label_grid', 'getChorusEQ',
      '{0, 5, 9, 13, 17, 21, 25, 29, 33, 37, 42, 46, 50, 54, 58, 62, 66, 70, 75, 79, 83, 87, 91, 95, 99, 103, 107, 112, 116, 120, 124}'},
    {82, 'eq_high_fader', false, 'EQ HIGH', 'eq_high_label', 'getChorusEQ', '%s dB', 'eq_high_grid', 'eq_high_label_grid', 'getChorusEQ',
      '{0, 5, 9, 13, 17, 21, 25, 29, 33, 37, 42, 46, 50, 54, 58, 62, 66, 70, 75, 79, 83, 87, 91, 95, 99, 103, 107, 112, 116, 120, 124}'}
  },
  [33] = { -- crusher
    {16, 'filter_fader', false, 'FILTER', 'filter_label', 'getCrusherFilter', '%s Hz', ''},
    {17, 'rate_fader', false, 'RATE', 'rate_label', 'getZeroOneHundred', '%s', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''}
  },
  [34] = { -- overdrive
    {16, 'drive_fader', false, 'DRIVE', 'drive_label', 'getZeroOneHundred', '%s', ''},
    {17, 'tone_fader', false, 'TONE', 'tone_label', 'getBipolarHundredv2', '%s', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''},
    {80, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''},
  },
  [35] = { -- distortion
    {16, 'drive_fader', false, 'DRIVE', 'drive_label', 'getZeroOneHundred', '%s', ''},
    {17, 'tone_fader', false, 'TONE', 'tone_label', 'getBipolarHundredv2', '%s', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''},
    {80, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''},
  },
  [36] = { -- equalizer
    {16, 'low_gain_fader', false, 'LOW GAIN', 'low_gain_label', 'getChorusEQ', '%s dB', 'low_gain_grid', 'low_gain_label_grid', 'getChorusEQ',
      '{0, 5, 9, 13, 17, 21, 25, 29, 33, 37, 42, 46, 50, 54, 58, 62, 66, 70, 75, 79, 83, 87, 91, 95, 99, 103, 107, 112, 116, 120, 124}'},
    {17, 'mid_gain_fader', false, 'MID GAIN', 'mid_gain_label', 'getChorusEQ', '%s dB', 'mid_gain_grid', 'mid_gain_label_grid', 'getChorusEQ',
      '{0, 5, 9, 13, 17, 21, 25, 29, 33, 37, 42, 46, 50, 54, 58, 62, 66, 70, 75, 79, 83, 87, 91, 95, 99, 103, 107, 112, 116, 120, 124}'},
    {18, 'high_gain_fader', false, 'HIGH GAIN', 'high_gain_label', 'getChorusEQ', '%s dB', 'high_gain_grid', 'high_gain_label_grid', 'getChorusEQ',
      '{0, 5, 9, 13, 17, 21, 25, 29, 33, 37, 42, 46, 50, 54, 58, 62, 66, 70, 75, 79, 83, 87, 91, 95, 99, 103, 107, 112, 116, 120, 124}'},
    {80, 'low_freq_fader', false, 'LOW FREQ', 'low_freq_label', 'getEQLowFreq', '%s Hz', 'low_freq_grid', 'low_freq_label_grid', 'getEQLowFreq',
      '{0, 10, 19, 28, 37, 46, 55, 64, 73, 82, 92, 101, 110, 119}'},
    {81, 'mid_freq_fader', false, 'MID FREQ', 'mid_freq_label', 'getEQMidFreq', '%s Hz', 'mid_freq_grid', 'mid_freq_label_grid', 'getEQMidFreq',
      '{0, 8, 15, 23, 30, 38, 45, 53, 60, 68, 75, 83, 90, 98, 105, 113, 120}'},
    {82, 'high_freq_fader', false, 'HIGH FREQ', 'high_freq_label', 'getEQHighFreq', '%s Hz', 'high_freq_grid', 'high_freq_label_grid', 'getEQHighFreq',
      '{0, 13, 26, 39, 52, 64, 77, 90, 102, 115}'}
  },
  [37] = { -- compressor
    {16, 'sustain_fader', false, 'SUSTAIN', 'sustain_label', 'getZeroOneHundred', '%s', ''},
    {17, 'attack_fader', false, 'ATTACK', 'attack_label', 'getZeroOneHundred', '%s', ''},
    {18, 'ratio_fader', false, 'RATIO', 'ratio_label', 'getZeroOneHundred', '%s', ''},
    {80, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''}
  },  
  [38] = { -- sx reverb
    {16, 'time_fader', false, 'TIME', 'time_label', 'getZeroOneHundred', '%s', ''},
    {17, 'tone_fader', false, 'TONE', 'tone_label', 'getBipolarHundredv2', '%s', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''},
  },
  [39] = { -- sx delay
    {16, 'delay_time_fader', false, 'DELAY TIME', 'delay_time_label', 'getDelayTimes', '%s', 'delay_time_grid', 'delay_time_label_grid', 'getDelayTimes',
      '{0, 9, 17, 26, 34, 43, 51, 60, 68, 77, 85, 94, 102, 111, 119, 127}'},
    {17, 'feedback_fader', false, 'FEEDBACK', 'feedback_label', 'getZeroNinetyNine', '%s%%', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''}
  },
  [40] = { -- cloud delay
    {16, 'window_fader', false, 'WINDOW', 'window_label', 'getZeroOneHundred', '%s', ''},
    {17, 'pitch_fader', false, 'PITCH', 'pitch_label', 'getCloudPitch', '%s', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_label', 'getBalance', '%s %%', ''},
    {80, 'feedback_fader', false, 'FEEDBACK', 'feedback_label', 'getBipolarHundredv2', '%s', ''},
    {81, 'cloudy_fader', false, 'CLOUDY', 'cloudy_label', 'getZeroOneHundred', '%s', ''},
    {82, 'lofi_fader', false, 'LOFI', 'lofi_label', 'getOnOff', '%s', 'lofi_grid', 'lofi_label_grid', 'getOnOff',
      '{0, 64}'},
  },
  [41] = { -- back spin
    {16, 'length_fader', false, 'LENGTH', 'length_label', 'getBackSpin', '%s', 'length_grid', 'length_label_grid', 'getBackSpin',
      '{0, 32, 64, 96, 127}'},
    {17, 'speed_fader', false, 'SPEED', 'speed_label', 'getZeroOneHundred', '%s', ''},
    {18, 'back_sw_fader', false, 'BACK SW', 'back_sw_label', 'getOnOff', '%s', 'back_sw_grid', 'back_sw_label_grid', 'getOnOff',
      '{0, 64}'},
  },
  [42] = { -- djfx delay
    {16, 'length_fader', false, 'LENGTH', 'length_label', 'getLooperLength', '%s s', ''},    
    {17, 'time_fader', false, 'TIME', 'time_label', 'getSyncDelayTimes', '%s', 'time_grid', 'time_label_grid', 'getSyncDelayTimes',
      '{0, 9, 17, 26, 34, 43, 51, 60, 68, 77, 85, 94, 102, 111, 119, 127}', 'true'},
    {18, 'on_off_fader', false, 'ON/OFF', 'on_off_label', 'getLoopOnOff', '%s', 'on_off_grid', 'on_off_label_grid', 'getLoopOnOff',
      '{0, 64}'},
    {80, 'feedback_fader', false, 'FEEDBACK', 'feedback_label', 'getZeroNinetyNine', '%s %%', ''},
    {81, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''},
    {82, 'sync_fader', false, 'SYNC', 'sync_label', 'getSync', '%s', 'sync_grid', 'sync_label_grid', 'getSync',
      '{0, 64}', 'false', 'time_fader', 'time_label', 'time_grid', 'time_label_grid'}
  },
  [43] = { -- auto-pitch
    {16, 'pitch_fader', false, 'PITCH', 'pitch_value_label', 'getBipolarHundredv2', '%s', ''},
    {17, 'formant_fader', false, 'FORMANT', 'formant_value_label', 'getBipolarHundredv2', '%s', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_value_label', 'getBalance', '%s %%', ''},
    {80, 'at_pitch_fader', false, 'AT PITCH', 'at_pitch_value_label', 'getZeroOneHundred', '%s', ''},
    {81, 'key_fader', true, 'KEY', 'key_label', 'getPitchKey', '%s', 'key_grid', 'key_label_grid', 'getPitchKey',
      '{0, 10, 20, 30, 40, 49, 59, 69, 79, 89, 99, 108, 118}'},
    {82, 'on_off_fader', false, 'ON/OFF', 'on_off_label', 'getOnOff', '%s', 'on_off_grid', 'on_off_label_grid', 'getOnOff',
      '{0, 64}'}
  },
  [44] = { -- vocoder
    {16, 'note_fader', true, 'NOTE', 'note_value_label', 'getNote', '%s', 'note_grid', 'note_label_grid', 'getNote',
      '{0, 4, 8, 11, 15, 19, 22, 26, 30, 33, 37, 41, 44, 48, 51, 55, 59, 62, 66, 70, 73, 77, 81, 84, 88, 92, 95, 99, 102, 106, 110, 113, 117, 121, 124}'},
    {17, 'formant_fader', false, 'FORMANT', 'formant_value_label', 'getBipolarHundredv2', '%s', ''},
    {18, 'tone_fader', false, 'TONE', 'tone_value_label', 'getBipolarHundredv2', '%s', ''},
    {80, 'scale_fader', true, 'SCALE', 'scale_label', 'getScale', '%s', 'scale_grid', 'scale_label_grid', 'getScale',
      '{0, 6, 11, 16, 22, 27, 32, 38, 43, 48, 54, 59, 64, 70, 75, 80, 85, 91, 96, 101, 107, 112, 117, 123}'},
    {81, 'chord_fader', true, 'CHORD', 'chord_label', 'getVocoderChord', '%s', 'chord_grid', 'chord_label_grid', 'getVocoderChord',
      '{0, 13, 26, 39, 51, 64, 77, 90, 102, 115}'},
    {82, 'balance_fader', false, 'BALANCE', 'balance_value_label', 'getBalance', '%s %%', ''}
  },
  [45] = { -- harmony
    {16, 'pitch_fader', false, 'PITCH', 'pitch_value_label', 'getBipolarHundredv2', '%s', ''},
    {17, 'formant_fader', false, 'FORMANT', 'formant_value_label', 'getBipolarHundredv2', '%s', ''},
    {18, 'balance_fader', false, 'BALANCE', 'balance_value_label', 'getBalance', '%s %%', ''},
    {80, 'at_pitch_fader', false, 'AT PITCH', 'at_pitch_value_label', 'getZeroOneHundred', '%s', ''},
    {81, 'key_fader', true, 'KEY', 'key_label', 'getPitchKey', '%s', 'key_grid', 'key_label_grid', 'getPitchKey',
      '{0, 10, 20, 30, 40, 49, 59, 69, 79, 89, 99, 108, 118}'},
    {82, 'harmony_fader', false, 'HARMONY', 'harmony_label', 'getVocoderChord', '%s', 'harmony_grid', 'harmony_label_grid', 'getVocoderChord',
      '{0, 13, 26, 39, 51, 64, 77, 90, 102, 115}'}
  },
  [46] = { -- gt amp sim
    {16, 'amp_type_fader', false, 'AMP TYPE', 'amp_type_label', 'getAmpType', '%s', 'amp_type_grid', 'amp_type_label_grid', 'getAmpType',
      '{0, 22, 43, 64, 85, 107}'},
    {17, 'drive_fader', false, 'DRIVE', 'drive_label', 'getZeroOneHundred', '%s', ''},
    {18, 'level_fader', false, 'LEVEL', 'level_label', 'getZeroOneHundred', '%s', ''},
    {80, 'bass_fader', false, 'BASS', 'bass_label', 'getBipolarHundredv3', '%s', ''},
    {81, 'middle_fader', false, 'MIDDLE', 'middle_label', 'getBipolarHundredv3', '%s', ''},
    {82, 'treble_fader', false, 'TREBLE', 'treble_label', 'getBipolarHundredv3', '%s', ''},
  },
}

childScript = [[
function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
      print('Control info values:', self.tag)
  end
end
]]

function init()
  
  for i = 1, #self.children do
    local controlInfoJSON = json.fromTable(controlsInfoArray[i])
    self.children[tostring(i)].script = childScript
    self.children[tostring(i)].tag = controlInfoJSON
  end

  local controlMapper = root.children.control_mapper
  controlMapper:notify('init_control_mapper')

end