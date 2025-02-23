local controlsInfo = root.children.controls_info

--************************************************************
-- INITIALISE MAPPING
--************************************************************

-- MAPPING SCRIPTS *******************************************

local getZeroOneHundredSnippet = [[
  local function getZeroOneHundred(value)
    local midiValue = value - 1
    if midiValue == 127 then
      return 100
    else
      return math.floor((midiValue / 127.5) * 100)
    end
  end
]]

local getTapeSpeedSnippet = [[
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

  local function getTapeSpeed(value)
    return tapeSpeedMap[value]
  end
]]

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

    local function getFreq(value)
      local scaledValue = midiToFrequencyMap[value]
      return scaledValue
    end
  ]],

  getZeroOneHundred = getZeroOneHundredSnippet,

  getZeroSixty = [[
    local function getZeroSixty(value)
      local midiValue = value - 1
      if midiValue == 127 then
        return 60
      else
        return math.floor((midiValue / 127.5) * 60)
      end
    end
  ]],

  get24dB = [[
    local function get24dB(value)
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

    local function getEQ(value)
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

    local function getBipolarHundred(value)
      return bipolarHundredRangeMap[value]
    end
  ]],

  getBipolarHundredv2 = [[
    local bipolarHundredRangeMapv2 = {
      -100, -98, -96, -95, -93, -92, -90, -89, -87, -85, -84, -82, -81, -79, -78, -76, -74,
      -73, -71, -70, -68, -67, -65, -63, -62, -60, -59, -57, -56, -54, -52, -51, -49, -48,
      -46, -45, -43, -41, -40, -38, -37, -35, -34, -32, -30, -29, -27, -26, -24, -23, -21,
      -20, -18, -16, -15, -13, -12, -10, -9, -7, -5, -4, -2, -1, 0, 1, 3, 5, 6, 8, 9, 11,
      12, 14, 16, 17, 19, 20, 22, 23, 25, 27, 28, 30, 31, 33, 34, 36, 38, 39, 41, 42, 44,
      45, 47, 49, 50, 52, 53, 55, 56, 58, 60, 61, 63, 64, 66, 67, 69, 70, 72, 74, 75, 77,
      78, 80, 81, 83, 85, 86, 88, 89, 91, 92, 94, 96, 97, 100
    }

    local function getBipolarHundredv2(value)
      return bipolarHundredRangeMapv2[value]
    end
  ]],

  getBipolarHundredv3 = [[
    local bipolarHundredRangeMapv3 = {
      -100, -98, -96, -95, -93, -92, -90, -88, -87, -85, -84, -82, -81, -79, -77, -76,
      -74, -73, -71, -70, -68, -66, -65, -63, -62, -60, -59, -57, -55, -54, -52, -51,
      -49, -48, -46, -44, -43, -41, -40, -38, -37, -35, -33, -32, -30, -29, -27, -25,
      -24, -22, -21, -19, -18, -16, -14, -13, -11, -10, -8, -7, -5, -3, -2, 0,
      0, 2, 3, 5, 7, 8, 10, 11, 13, 14, 16, 18, 19, 21, 22, 24,
      25, 27, 29, 30, 32, 33, 35, 37, 38, 40, 41, 43, 44, 46, 48, 49,
      51, 52, 54, 55, 57, 59, 60, 62, 63, 65, 66, 68, 70, 71, 73, 74,
      76, 77, 79, 81, 82, 84, 85, 87, 88, 90, 92, 93, 95, 96, 98, 100
    }

    local function getBipolarHundredv3(value)
      return bipolarHundredRangeMapv3[value]
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

    local function getHundredMS(value)
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

    local function getBalance(value)
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

    local function getSBFGain(value)
      return sbfGainMap[value]
    end
  ]],

  getTapeSpeed = getTapeSpeedSnippet,

  getZeroNinetyNine = [[
    local function getZeroNinetyNine(value)
      local midiValue = value - 1
      if midiValue == 127 then
        return 99
      else
        return math.floor((midiValue / 127.5) * 99)
      end
    end
  ]],

  get48dB = [[
    local function get48dB(value)
      local midiValue = value - 1
      local dbValue = math.floor((midiValue / 127.5) * 49)
      return dbValue
    end
  ]],

  getLooperLength = [[
    local function getLooperLength(value)
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
    local function getFilterType(value)
      local filterTypes = {'HIGH-PASS', 'LOW-PASS'}
      return filterTypes[value]
    end
  ]],

  getWahFilterType = [[
    local function getWahFilterType(value)
      local filterTypes = {'LOW-PASS', 'BAND-PASS'}
      return filterTypes[value]
    end
  ]],

  getSuperFilterType = [[
    local function getSuperFilterType(value)
      local filterTypes = {'LOW-PASS', 'BAND-PASS', 'HIGH-PASS'}
      return filterTypes[value]
    end
  ]],

  getRoot = [[
    local rootNotes = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'}
    local rootOctaves = {'-1', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'}

    local function getRoot(value)
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

    local function getChord(value)
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

    local function getDelayTimes(value)
      local delayTime = delayTimes[value]
      return delayTime
    end
  ]],

  getSyncDelayTimes = getTapeSpeedSnippet..[[
    local delayTimes = {
        '1/32', '1/16T', '1/32D', '1/16',
        '1/8T', '1/16D', '1/8', '1/4T',
        '1/8D', '1/4', '1/2T', '1/4D',
        '1/2', '1/1T', '1/2D', '1/1'
    }

    local function getSyncDelayTimes(value, syncOn)
      if syncOn then
        return delayTimes[value]
      else
        return getTapeSpeed(value)..' ms'
      end
    end
  ]],

  getLDampFValues = [[
    local lDampFValues = {'FLAT', '80', '100', '125', '160', '200', '250', '315', '400', '500', '630', '800'}

    local function getLDampFValues(value)
      local lDampFValue = lDampFValues[value]
      return lDampFValue
    end
  ]],

  getHDampFValues = [[
    local hDampFValues = {'630', '800', '1000', '1250', '1600', '2000', '2500', '3150', '4000', '5000', '6300', '8000', '10000', '12500', 'FLAT'}

    local function getHDampFValues(value)
      local hDampFValue = hDampFValues[value]
      return hDampFValue
    end
  ]],

  getOnOff = [[
    local onOff = {'OFF', 'ON'}

    local function getOnOff(value)
      return onOff[value]
    end
  ]],

  getScatterSpeed = [[
    local speeds = {'SINGLE', 'DOUBLE'}

    local function getScatterSpeed(value)
      return speeds[value]
    end
  ]],

  getScatterType = [[
    local types = {'1', '2', '3', '4', '5', '6', '7', '8', '9', '10'}

    local function getScatterType(value)
      local type = types[value]
      return type
    end
  ]],

  getScatterDepth = [[
    local depths = {'10', '20', '30', '40', '50', '60', '70', '80', '90', '100'}

    local function getScatterDepth(value)
      local depth = depths[value]
      return depth
    end
  ]],

  getPitchOnOff = [[
    local pitchOnOff = {'PITCH OFF', 'PITCH ON'}

    local function getPitchOnOff(value)
      return pitchOnOff[value]
    end
  ]],

  getDownerRate = [[
    local downerRates = {'2/1', '1/1', '1/2', '1/4', '1/8', '1/16', '1/32'}

    local function getDownerRate(value)
      local downerRate = downerRates[value]
      return downerRate
    end
  ]],

  getLowCut = [[
    local lowCutValues = {'FLAT', '20', '25', '31', '40', '50', '63', '80', '100', '125', '160', '200', '250', '315', '400', '500', '630', '800'}

    local function getLowCut(value)
      local lowCutValue = lowCutValues[value]
      return lowCutValue
    end
  ]],

  getHighCut = [[
    local highCutValues = {'630', '800', '1000', '1250', '1600', '2000', '2500', '3150', '4000', '5000', '6300', '8000', '10000', '12500', 'FLAT'}

    local function getHighCut(value)
      local highCutValue = highCutValues[value]
      return highCutValue
    end
  ]],

  getKoDaMaMode = [[
    local koDaMaModes = {'SINGLE', 'PAN'}

    local function getKoDaMaMode(value)
      return koDaMaModes[value]
    end
  ]],

  getZanZouMode = [[
    local zanZouModes = {'2TAP', '3TAP', '4TAP'}

    local function getZanZouMode(value)
      local zanZouMode = zanZouModes[value]
      return zanZouMode
    end
  ]],

  getSync = [[
    local sync = {'SYNC OFF', 'SYNC ON'}

    local function getSync(value)
      return sync[value]
    end
  ]],

  getHFDampValues = [[
    local hfDampValues = {'200', '250', '315', '400', '500', '630', '800', '1000', '1250', '1600', '2000', '2500', '3150', '4000', '5000', '6300', '8000', 'OFF'}

    local function getHFDampValues(value)
      local hfDampValue = hfDampValues[value]
      return hfDampValue
    end
  ]],

  getToGuRoRate = getZeroOneHundredSnippet..[[
    local rates = {
      '2/1', '1/1', '1/2', '1/4',
      '1/8', '1/16', '1/32', '1/64',
      '1/128'
    }

    local function getToGuRoRate(value, syncOn)
      if syncOn then
        return rates[value]
      else
        return getZeroOneHundred(value)
      end
    end
  ]],

  getSBFType = [[
    local sbfTypes = {'SBF1', 'SBF2', 'SBF3', 'SBF4', 'SBF5', 'SBF6'}

    local function getSBFType(value)
      local sbfType = sbfTypes[value]
      return sbfType
    end
  ]],

  getStopperRate = [[
  local rates = {'4/1', '2/1', '1/1', '1/2', '1/4', '1/8', '1/16', '1/32', '1/64'}

    local function getStopperRate(value)
      local rate = rates[value]
      return rate
    end
  ]],

  getTapeEchoMode = [[
    local modes = {'S', 'M', 'L', 'S+M', 'S+L', 'M+L', 'S+M+L'}

    local function getTapeEchoMode(value)
      local mode = modes[value]
      return mode
    end
  ]],

  getRate = [[
    local rates = {'2/1', '1/1D', '2/1T', '1/1', '1/2D', '1/1T', '1/2', '1/4D', '1/2T', '1/4', '1/8D', '1/4T', '1/8', '1/16D', '1/8T', '1/16', '1/32D', '1/16T', '1/32', '1/32T', '1/64', '1/64T'}

    local function getRate(value)
      local rate = rates[value]
      return rate
    end
  ]],

  getFilterRate = getZeroOneHundredSnippet..[[
    local rates = {'2/1', '1/1D', '2/1T', '1/1', '1/2D', '1/1T', '1/2', '1/4D', '1/2T', '1/4', '1/8D', '1/4T', '1/8', '1/16D', '1/8T', '1/16', '1/32D', '1/16T', '1/32', '1/32T', '1/64', '1/64T'}

    local function getFilterRate(value, syncOn)
      if syncOn then
        return rates[value]
      else
        return getZeroOneHundred(value)
      end
    end
  ]],

  getPreFilter = [[
    local filters = {'1', '2', '3', '4', '5', '6'}

    local function getPreFilter(value)
      local filter = filters[value]
      return filter
    end
  ]],

  getLofiType = [[
    local types = {'1', '2', '3', '4', '5', '6', '7', '8', '9'}

    local function getLofiType(value)
      local type = types[value]
      return type
    end
  ]],

  getLofiCutoff = [[
    local frequencies = {'200', '250', '315', '400', '500', '630', '800', '1000', '1250', '1600', '2000', '2500', '3150', '4000', '5000', '6300', '8000'}

    local function getLofiCutoff(value)
      local frequency = frequencies[value]
      return frequency
    end
  ]],

  getNote = [[
    local notes = {
        "-17", "-16", "-15", "-14", "-13", "-12", "-11", "-10", "-9", "-8",
        "-7", "-6", "-5", "-4", "-3", "-2", "-1",
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "10",
        "11", "12", "13", "14", "15", "16", "17", "18"
    }

    local function getNote(value)
      local note = notes[value]
      return note
    end
  ]],

  getScale = [[
    local scales = {
      "C Maj",
      "C# Maj",
      "D Maj",
      "D# Maj",
      "E Maj",
      "F Maj",
      "F# Maj",
      "G Maj",
      "G# Maj",
      "A Maj",
      "A# Maj",
      "B Maj",
      "C Min",
      "C# Min",
      "D Min",
      "D# Min",
      "E Min",
      "F Min",
      "F# Min",
      "G Min",
      "G# Min",
      "A Min",
      "A# Min",
      "B Min"
    }

    local function getScale(value)
      local scale = scales[value]
      return scale
    end
  ]],

  getVocoderChord = [[
    local vocoderChords = {'Root', 'P5', 'Oct', 'UpDn', 'UpDnP5', '3rd', '5thUp', '5thDn', '7thUp', '7thDn'}

    local function getVocoderChord(value)
      local chord = vocoderChords[value]
      return chord
    end
  ]],

  getPitchKey = [[
    local keys = {'CHROMA', 'A', 'B♭', 'B', 'C', 'D♭', 'D', 'E♭', 'E', 'F', 'G♭', 'G', 'A♭'}

    local function getPitchKey(value)
      local key = keys[value]
      return key
    end
  ]],

  getReverbType = [[
    local types = {'AMBI', 'ROOM', 'HALL1', 'HALL2'}

    local function getReverbType(value)
      local type = types[value]
      return type
    end
  ]],

  getChorusRate = [[
    local rates = {
      "0.33", "0.35", "0.36", "0.38", "0.39", "0.41", "0.42", "0.44", "0.45", "0.47",
      "0.48", "0.50", "0.52", "0.53", "0.55", "0.56", "0.58", "0.59", "0.61", "0.62",
      "0.64", "0.65", "0.67", "0.69", "0.70", "0.72", "0.73", "0.75", "0.76", "0.78",
      "0.79", "0.81", "0.82", "0.84", "0.86", "0.87", "0.89", "0.90", "0.92", "0.93",
      "0.95", "0.96", "0.98", "0.99", "1.01", "1.03", "1.04", "1.06", "1.07", "1.09",
      "1.10", "1.12", "1.13", "1.15", "1.16", "1.18", "1.20", "1.21", "1.23", "1.24",
      "1.26", "1.27", "1.29", "1.30", "1.32", "1.33", "1.35", "1.37", "1.38", "1.40",
      "1.41", "1.43", "1.44", "1.46", "1.47", "1.49", "1.50", "1.52", "1.54", "1.55",
      "1.57", "1.58", "1.60", "1.61", "1.63", "1.64", "1.66", "1.67", "1.69", "1.71",
      "1.72", "1.74", "1.75", "1.77", "1.78", "1.80", "1.81", "1.83", "1.84", "1.86",
      "1.88", "1.89", "1.91", "1.92", "1.94", "1.95", "1.97", "1.98", "2.00", "2.01",
      "2.03", "2.05", "2.06", "2.08", "2.09", "2.11", "2.12", "2.14", "2.15", "2.17",
      "2.18", "2.20", "2.22", "2.23", "2.25", "2.26", "2.28", "2.30"
    }

    local function getChorusRate(value)
      local rate = rates[value]
      return rate
    end
  ]],

  getChorusEQ = [[
    local eqValues = {
      "-15", "-14", "-13", "-12", "-11", "-10", "-9", "-8", "-7", "-6", "-5", "-4", "-3", "-2", "-1", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15"
    }

    local function getChorusEQ(value)
      local eqValue = eqValues[value]
      return eqValue
    end
  ]],

  getJunoChorusMode = [[
    local modes = {'JUNO 1', 'JUNO 2', 'JUNO 12', 'JX-1 1', 'JX-1 2'}

    local function getJunoChorusMode(value)
      return modes[value]
    end
  ]],

  getAmpType = [[
    local types = {'JC', 'TWIN', 'BG', 'MATCH', 'MS', 'SLDN'}

    local function getAmpType(value)
      return types[value]
    end
  ]],

  getFlangerRate = [[
    local rates = {
      "4.000", "3.969", "3.938", "3.906", "3.875", "3.844", "3.813", "3.781",
      "3.750", "3.719", "3.688", "3.656", "3.625", "3.594", "3.563", "3.531",
      "3.500", "3.469", "3.438", "3.406", "3.375", "3.344", "3.313", "3.281",
      "3.250", "3.219", "3.188", "3.156", "3.125", "3.094", "3.063", "3.031",
      "3.000", "2.969", "2.938", "2.906", "2.875", "2.844", "2.813", "2.781",
      "2.750", "2.719", "2.688", "2.656", "2.625", "2.594", "2.563", "2.531",
      "2.500", "2.469", "2.438", "2.406", "2.375", "2.344", "2.313", "2.281",
      "2.250", "2.219", "2.188", "2.156", "2.125", "2.094", "2.063", "2.031",
      "2.000", "1.969", "1.938", "1.906", "1.875", "1.844", "1.813", "1.781",
      "1.750", "1.719", "1.688", "1.656", "1.625", "1.594", "1.563", "1.531",
      "1.500", "1.469", "1.438", "1.406", "1.375", "1.344", "1.313", "1.281",
      "1.250", "1.219", "1.188", "1.156", "1.125", "1.094", "1.063", "1.031",
      "1.000", "0.969", "0.938", "0.906", "0.875", "0.844", "0.813", "0.781",
      "0.750", "0.719", "0.688", "0.656", "0.625", "0.594", "0.563", "0.531",
      "0.500", "0.469", "0.438", "0.406", "0.375", "0.344", "0.313", "0.281",
      "0.250", "0.219", "0.188", "0.156", "0.125", "0.094", "0.063", "0.016"
    }

    local function getZeroOneHundred(value)
      local midiValue = value - 1
      if midiValue == 127 then
        return 100
      else
        return math.floor((midiValue / 127.5) * 100)
      end
    end

    local function getFlangerRate(value, syncOn)
      if syncOn then
        return rates[value]..' bar'
      else
        return getZeroOneHundred(value)
      end
    end
  ]],

  getWahRate = getZeroOneHundredSnippet..[[
    local rates = {
      "1.000", "0.971", "0.943", "0.917", "0.893", "0.870", "0.848", "0.827",
      "0.808", "0.788", "0.770", "0.753", "0.736", "0.720", "0.704", "0.689",
      "0.675", "0.661", "0.648", "0.634", "0.621", "0.609", "0.597", "0.585",
      "0.574", "0.563", "0.552", "0.541", "0.531", "0.521", "0.511", "0.501",
      "0.492", "0.483", "0.474", "0.465", "0.456", "0.448", "0.439", "0.431",
      "0.423", "0.416", "0.408", "0.400", "0.393", "0.386", "0.378", "0.371",
      "0.364", "0.358", "0.351", "0.344", "0.338", "0.331", "0.324", "0.318",
      "0.312", "0.306", "0.300", "0.294", "0.288", "0.283", "0.277", "0.271",
      "0.266", "0.260", "0.255", "0.249", "0.244", "0.239", "0.234", "0.229",
      "0.224", "0.219", "0.214", "0.209", "0.204", "0.199", "0.195", "0.190",
      "0.186", "0.181", "0.177", "0.172", "0.168", "0.163", "0.159", "0.155",
      "0.151", "0.146", "0.143", "0.138", "0.134", "0.130", "0.126", "0.122",
      "0.118", "0.114", "0.111", "0.107", "0.103", "0.099", "0.096", "0.092",
      "0.088", "0.084", "0.081", "0.078", "0.074", "0.070", "0.067", "0.063",
      "0.060", "0.056", "0.053", "0.050", "0.046", "0.043", "0.040", "0.037",
      "0.034", "0.030", "0.027", "0.024", "0.021", "0.018", "0.014", "0.010"
    }

    local function getWahRate(value, syncOn)
      if syncOn then
        return rates[value]..' bar'
      else
        return getZeroOneHundred(value)
      end
    end
  ]],

  getSlicerMode = [[
    local modes = {'LEGATO', 'SLASH'}

    local function getSlicerMode(value)
      return modes[value]
    end
  ]],

  getSlicerPattern = [[
    local patterns = {'1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24', '25', '26', '27', '28', '29', '30', '31', '32'}

    local function getSlicerPattern(value)
      return patterns[value]
    end
  ]],

  getTremoloPanType = [[
    local types = {'TREMOLO', 'PAN'}

    local function getTremoloPanType(value)
      return types[value]
    end
  ]],

  getTremoloPanWave = [[
    local waves = {'TRI', 'SQR', 'SIN', 'SAW1', 'SAW2', 'TRP'}

    local function getTremoloPanWave(value)
      return waves[value]
    end
  ]],

  getPan = [[
    local pans  = {
        "L50", "L49", "L48", "L48", "L47", "L46", "L45", "L44",
        "L44", "L43", "L42", "L41", "L41", "L40", "L39", "L38",
        "L37", "L37", "L36", "L35", "L34", "L33", "L33", "L32",
        "L31", "L30", "L30", "L29", "L28", "L27", "L26", "L26",
        "L25", "L24", "L23", "L23", "L22", "L21", "L20", "L19",
        "L19", "L18", "L17", "L16", "L16", "L15", "L14", "L13",
        "L12", "L12", "L11", "L10", "L9", "L8", "L8", "L7",
        "L6", "L5", "L5", "L4", "L3", "L2", "L1", "L1",
        "C",
        "R1", "R1", "R2", "R3", "R4", "R5", "R5", "R6",
        "R7", "R8", "R8", "R9", "R10", "R11", "R12", "R12",
        "R13", "R14", "R15", "R16", "R16", "R17", "R18", "R19",
        "R19", "R20", "R21", "R22", "R23", "R23", "R24", "R25",
        "R26", "R26", "R27", "R28", "R29", "R30", "R30", "R31",
        "R32", "R33", "R33", "R34", "R35", "R36", "R37", "R37",
        "R38", "R39", "R40", "R41", "R41", "R42", "R43", "R44",
        "R44", "R45", "R46", "R47", "R48", "R48", "R50"
    }

    local function getPan(value)
      return pans[value]
    end
  ]],

  getPitch = [[
    local pitches = {
      "-24", "-24", "-24", "-24", "-23", "-23", "-23", "-22",
      "-22", "-22", "-22", "-21", "-21", "-21", "-20", "-20",
      "-20", "-20", "-19", "-19", "-19", "-18", "-18", "-18",
      "-18", "-17", "-17", "-17", "-16", "-16", "-16", "-15",
      "-15", "-15", "-15", "-14", "-14", "-14", "-13", "-13",
      "-13", "-13", "-12", "-12", "-12", "-11", "-11", "-11",
      "-11", "-10", "-10", "-10", "-9", "-9", "-9", "-9",
      "-8", "-8", "-8", "-7", "-7", "-7", "-7", "-6",
      "-6", "-6", "-5", "-5", "-5", "-4", "-4", "-4",
      "-4", "-3", "-3", "-3", "-2", "-2", "-2", "-2",
      "-1", "-1", "-1", "0", "0", "0", "0", "1",
      "1", "1", "2", "2", "2", "2", "3", "3",
      "3", "4", "4", "4", "5", "5", "5", "5",
      "6", "6", "6", "7", "7", "7", "7", "8",
      "8", "8", "9", "9", "9", "9", "10", "10",
      "10", "11", "11", "11", "11", "12", "12", "12"
    }

    local function getPitch(value)
      return pitches[value]
    end
  ]],

  getSpread = [[
    local spreads = {
      'UNISON', 'TINY', 'SMALL', 'MEDIUM', 'HUGE'
    }

    local function getSpread(value)
      return spreads[value]
    end
  ]],

  getCrusherFilter = [[
    local filters = {
      331, 345, 358, 373, 388, 403, 420, 437, 454, 473, 492, 512, 533, 554, 577, 600, 625, 650, 677, 704,
      733, 763, 795, 827, 861, 897, 934, 972, 1012, 1054, 1098, 1143, 1190, 1240, 1291, 1345, 1400, 1458,
      1519, 1582, 1647, 1716, 1787, 1861, 1938, 2018, 2101, 2188, 2278, 2372, 2470, 2571, 2676, 2786, 2899,
      3017, 3139, 3266, 3397, 3533, 3674, 3820, 3971, 4127, 4288, 4455, 4626, 4803, 4986, 5173, 5366, 5564,
      5767, 5975, 6189, 6407, 6630, 6857, 7089, 7325, 7564, 7807, 8053, 8302, 8553, 8806, 9061, 9317, 9573,
      9829, 10085, 10339, 10592, 10843, 11092, 11336, 11577, 11814, 12046, 12272, 12492, 12706, 12913, 13113,
      13305, 13490, 13666, 13834, 13993, 14143, 14285, 14417, 14541, 14655, 14761, 14857, 14945, 15025, 15095,
      15158, 15213, 15259, 15299, 15330, 15355, 15374, 15386, 15392
    }

    local function getCrusherFilter(value)
      return filters[value]
    end
  ]],

  getEQLowFreq = [[
    local lowFreqs = {"20", "25", "31", "40", "50", "63", "80", "100", "125", "160", "200", "250", "315", "400"}

    local function getEQLowFreq(value)
      return lowFreqs[value]
    end
  ]],

  getEQMidFreq = [[
    local midFreqs = {"200", "250", "315", "400", "500", "630", "800", "1000", "1250", "1600", "2000", "2500", "3150", "4000", "5000", "6300", "8000"}

    local function getEQMidFreq(value)
      return midFreqs[value]
    end
  ]],

  getEQHighFreq = [[
    local highFreqs = {"2000", "2500", "3150", "4000", "5000", "6300", "8000", "10000", "12500", "16000"}

    local function getEQHighFreq(value)
      return highFreqs[value]
    end
  ]],

  getCloudPitch = [[
    local pitches = {
      "-12.0", "-12.0", "-11.8", "-11.6", "-11.4", "-11.2", "-11.0", "-10.8", "-10.6", "-10.4", "-10.2", "-10.0",
      "-9.8", "-9.6", "-9.4", "-9.2", "-9.0", "-8.8", "-8.6", "-8.4", "-8.4", "-8.2", "-8.0", "-7.8", "-7.6", "-7.4",
      "-7.2", "-7.0", "-6.8", "-6.6", "-6.4", "-6.2", "-6.0", "-5.8", "-5.6", "-5.4", "-5.2", "-5.0", "-4.8", "-4.6",
      "-4.6", "-4.4", "-4.2", "-4.0", "-3.8", "-3.6", "-3.4", "-3.2", "-3.0", "-2.8", "-2.6", "-2.4", "-2.2", "-2.0",
      "-1.8", "-1.6", "-1.4", "-1.2", "-1.0", "-1.0", "-0.8", "-0.6", "-0.4", "-0.2", "0.0", "+0.2", "+0.4", "+0.6",
      "+0.8", "+1.0", "+1.2", "+1.4", "+1.6", "+1.8", "+2.0", "+2.2", "+2.4", "+2.6", "+2.8", "+2.8", "+3.0", "+3.2",
      "+3.4", "+3.6", "+3.8", "+4.0", "+4.2", "+4.4", "+4.6", "+4.8", "+5.0", "+5.2", "+5.4", "+5.6", "+5.8", "+6.0",
      "+6.2", "+6.4", "+6.6", "+6.6", "+6.8", "+7.0", "+7.2", "+7.4", "+7.6", "+7.8", "+8.0", "+8.2", "+8.4", "+8.6",
      "+8.8", "+9.0", "+9.2", "+9.4", "+9.6", "+9.8", "+10.0", "+10.2", "+10.2", "+10.4", "+10.6", "+10.8", "+11.0",
      "+11.2", "+11.4", "+11.6", "+11.8", "+12.0"
    }

    local function getCloudPitch(value)
      return pitches[value]
    end
  ]],

  getBackSpin = [[
    local backSpins = {"1/1", "1/2", "1/4", "1/8", "1/16"}

    local function getBackSpin(value)
      return backSpins[value]
    end
  ]],

  getLoopOnOff = [[
    local loopOnOffs = {"LOOP OFF", "LOOP ON"}

    local function getLoopOnOff(value)
      return loopOnOffs[value]
    end
  ]],
}

-- CONTROL SCRIPTS *******************************************
local faderScriptTemplate = [[
  local amSyncFader = %s
  local labelName = '%s'
  %s  -- Include the mapping function definition here
  local startValues = %s
  local syncOn = false

  local function midiToFloat(midiValue)
    local floatValue = midiValue / 127
    return floatValue
  end

  local function floatToMIDI(floatValue)
    local midiValue = math.floor(floatValue * 127 + 0.5)
    return midiValue
  end

  local function findRange(ranges, target)
    print("Finding range for target: " .. tostring(target))

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
      print("Checking range " .. tostring(i) .. ": " .. tostring(rangeStart) .. " to " .. tostring(rangeEnd - 1))
      if target >= rangeStart and target < rangeEnd then
        print("Found range " .. tostring(i))
        return i
      end
    end

    -- Should never reach here if ranges are properly defined
    return 1
  end

  local function floatToRange(floatValue)

    local midiValue = math.floor(floatValue * 127 + 0.5)

    if next(startValues) == nil then
      -- Return full midi range as the range
      local index = midiValue + 1
      -- print("Returning index in full midi range:", index)
      return index
    end

    -- print("floatToRange called with floatValue:", floatValue, "startValues:", startValues)

    local index = findRange(startValues, midiValue)

    -- print("Index in grid range:", index)

    return index
  end

  local function updateLabel(value)
    local label = self.parent:findByName(labelName)
    local newText = ''
    local index = floatToRange(value)

    if amSyncFader then
      if not syncOn then
        index = floatToMIDI(value) + 1
      end
      newText = %s(index, syncOn)
    else
      newText = %s(index)
    end

    -- print("Updating label '" .. tostring(labelName) .. "' with value: " .. tostring(newText))
    label:notify('update_text', newText)
  end

  local gridToNotify = '%s'

  local function notifyGrid(value)
    local rangeIndex = value
    -- print("Fader float: " .. tostring(value) .. " to Range: " .. tostring(rangeIndex))
    local gridControl = self.parent:findByName(gridToNotify, true)
    gridControl:notify('new_index', rangeIndex)
  end

  local function syncMIDI()
    sendMIDI({ MIDIMessageType.CONTROLCHANGE + tonumber(self.tag), %s, floatToMIDI(self.values.x)})
  end

  function onReceiveNotify(key, value)
    if key == 'new_value' then
      -- print('New value:', value)
      self.values.x = value
      updateLabel(value)
    elseif key == 'new_cc_value' then
      -- print('New cc value:', value)
      local floatValue = midiToFloat(value)
      self.values.x = floatValue
      updateLabel(floatValue)
    elseif key == 'sync_toggle' then
      --  print('Toggling fader sync:', value)
      syncOn = value
      updateLabel(self.values.x)
    end
  end

  function onValueChanged(value)
    if value == 'x' then
      local gridIndex = floatToRange(self.values.x)

      updateLabel(self.values.x)
      if gridToNotify ~= '' then
        notifyGrid(gridIndex)
      end

      syncMIDI()
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

  local showHideFader = self.parent.parent:findByName('%s', true)
  local showHideFaderLabel = self.parent.parent:findByName('%s', true)
  local showHideGrid = self.parent.parent:findByName('%s', true)
  local showHideGridLabel = self.parent.parent:findByName('%s', true)

  local function toggleTimeViews(showFader)
    if showHideFader and showHideFaderLabel and showHideGrid and showHideGridLabel then
      showHideFader.visible = not showFader
      showHideFaderLabel.visible = not showFader
      showHideGrid.visible = showFader
      showHideGridLabel.visible = showFader
    end
  end

  local function toggleFaderSync(value)
    if showHideFader then
      --print('Toggling fader sync:', value)
      showHideFader:notify('sync_toggle', value)
    end
  end

  function onValueChanged(key, value)
    if self.name ~= targetGridName and key == 'x' and self.values.x == 1 and self.parent.tag == '1' then
      local myCCValue = startValues[self.index] -- Already in 0-127 range
      local syncedFader = self.parent.parent:findByName(syncedFaderName)
      syncedFader:notify('new_cc_value', myCCValue)

      if amSyncGrid then
        local syncOn = (self.index == 2)
        --print('Toggling:', syncOn)
        toggleTimeViews(syncOn)
        toggleFaderSync(syncOn)
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
      if amSyncGrid then
        local syncOn = (value == 2)
        --print('Toggling:', syncOn)
        toggleTimeViews(syncOn)
        toggleFaderSync(syncOn)
      end
    end
  end
]]

local gridLabelScriptTemplate = [[
  %s -- Include the mapping function definition here
  local gridLabelName = '%s'

  function init()
    if self.name ~= gridLabelName then
      self.values.text = %s(self.index, true) -- Just use the function name directly
    end
  end
]]

local function generateAndAssignFaderScript(controlGroup, controlInfo)
  local ccNumber, faderName, _, _, labelName, labelMapping, _, gridName, _, _, startValues, amSyncFader, _, _, _, _ = table.unpack(controlInfo)

  if not startValues or startValues == '' then
    -- Just so we don't break the script
    startValues = '{}'
  end

  if not amSyncFader then
    amSyncFader = 'false'
  end

  --print('Generating fader script for:', faderName, labelName, labelMapping, gridName, startValues, amSyncFader, mappingScripts[labelMapping])

  local faderScript = string.format(faderScriptTemplate,
    amSyncFader,
    labelName,
    mappingScripts[labelMapping],
    startValues,
    labelMapping,
    labelMapping,
    gridName,
    ccNumber)

  -- Find the fader object
  local faderObject = controlGroup:findByName(faderName, true)
  if faderObject then
    -- Assign the generated script
    --print('Assigning fader script to:', faderObject.name)
    faderObject.script = faderScript
  end
end

local function generateAndAssignLabelScript(controlGroup, controlInfo)
  local ccNumber, _, _, _, labelName, _, labelFormat, _, _, _, _, _, _, _, _, _ = table.unpack(controlInfo)

  -- Generate and assign label script
  local labelObject = controlGroup:findByName(labelName, true)
  local labelScript = string.format(labelScriptTemplate, labelFormat)
  if labelObject then
    --print('Assigning label script to:', labelObject.name)
    labelObject.script = labelScript
  end
end

local function generateAndAssignGridScript(controlGroup, controlInfo)
  -- Generate and assign grid script
  local ccNumber, faderName, _, _, _, labelMapping, _, gridName, gridLabelName, gridLabelMapping, startValues, _, showHideFader, showHideFaderLabel, showHideGrid, showHideGridLabel = table.unpack(controlInfo)

  local amSyncGrid = 'true'
  if not showHideFader then
    amSyncGrid = 'false'
    showHideFader = ''
    showHideFaderLabel = ''
    showHideGrid = ''
    showHideGridLabel = ''
  end

  --print('Generating grid script for:', faderName, gridName, startValues, amSyncGrid, showHideFader, showHideFaderLabel, showHideGrid, showHideGridLabel)

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
    --print('Assigning grid script to:', gridObject.name)
    gridObject.script = gridScript
  end

  --print('Generating grid label script for:', gridLabelName, gridLabelMapping)

  local gridLabelObject = controlGroup:findByName(gridLabelName, true)

  local gridLabelScript = string.format(gridLabelScriptTemplate,
    mappingScripts[gridLabelMapping],
    gridLabelName,
    gridLabelMapping)

  --print('Grid label script:', gridLabelScript)

  if gridLabelObject then
    gridLabelObject.script = gridLabelScript
  end
end

local function mapControls()
  for i = 1, 46 do
    --print('Initialising category with fxPage:', i)
    local fxPage = root.children.control_pager.children[i]
    --print('fxPage:', fxPage.name)
    local controlGroup = fxPage.children.control_group
    --print('controlGroup:', controlGroup.name)

    local controlInfo = json.toTable(controlsInfo.children[tostring(i)].tag)
    if controlInfo then
      --print('Successfully loaded controlInfo for page:', i)
      for i, control in ipairs(controlInfo) do
        --print(string.format('controlInfo[%d]:', i), table.unpack(control))
        local _, controlName, _, _, labelName, labelMapping, labelFormat, syncedGrid = table.unpack(control)

        --print('Initialising control:', controlName, labelName, labelMapping, labelFormat, syncedGrid)

        generateAndAssignFaderScript(controlGroup, control)
        generateAndAssignLabelScript(controlGroup, control)

        if syncedGrid ~= '' then
          generateAndAssignGridScript(controlGroup, control)
        end
      end
    else
      print('Failed to load controlInfo for page:', i)
    end
  end
end

local performFaderScriptTemplate = [[
  local amSyncFader = %s
  %s  -- Include the mapping function definition here
  local startValues = %s
  local syncOn = false

  local function midiToFloat(midiValue)
    local floatValue = midiValue / 127
    return floatValue
  end

  local function floatToMIDI(floatValue)
    local midiValue = math.floor(floatValue * 127 + 0.5)
    return midiValue
  end

  local function findRange(ranges, target)
    -- print("Finding range for target: " .. tostring(target))

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
      -- print("Checking range " .. tostring(i) .. ": " .. tostring(rangeStart) .. " to " .. tostring(rangeEnd - 1))
      if target >= rangeStart and target < rangeEnd then
        -- print("Found range " .. tostring(i))
        return i
      end
    end

    -- Should never reach here if ranges are properly defined
    return 1
  end

  local function floatToRange(floatValue)

    local midiValue = math.floor(floatValue * 127 + 0.5)

    if next(startValues) == nil then
      -- Return full midi range as the range
      local index = midiValue + 1
      -- print("Returning index in full midi range:", index)
      return index
    end

    -- print("floatToRange called with floatValue:", floatValue, "startValues:", startValues)

    local index = findRange(startValues, midiValue)

    -- print("Index in grid range:", index)

    return index
  end

  local function updateLabel(value)
    local label = self.parent:findByName('value_label')
    local newText = ''
    local index = floatToRange(value)

    if amSyncFader then
      if not syncOn then
        index = floatToMIDI(value) + 1
      end
      newText = %s(index, syncOn)
    else
      newText = %s(index)
    end

    -- print("Updating label '" .. label.name .. "' with value: " .. tostring(newText))
    label:notify('update_text', newText)
  end

  local function syncMIDI()
    sendMIDI({ MIDIMessageType.CONTROLCHANGE + %s, %s, floatToMIDI(self.values.x)})
  end

  function onReceiveNotify(key, value)
    if key == 'new_value' then
      -- print('New value:', value)
      self.values.x = value
      updateLabel(value)
    elseif key == 'new_cc_value' then
      -- print('New cc value:', value)
      local floatValue = midiToFloat(value)
      self.values.x = floatValue
      updateLabel(floatValue)
    elseif key == 'sync_toggle' then
      -- print('Toggling fader sync:', value)
      syncOn = value
      updateLabel(self.values.x)
    elseif key == 'update_label' then
      updateLabel(self.values.x)
    end
  end

  function onValueChanged(value)
    if value == 'x' then
      updateLabel(self.values.x)
      syncMIDI()
    end
  end

  function init()
    updateLabel(self.values.x)
  end
]]

local function setUpPerformValueLabel(valueLabel, labelFormat)
  local labelScript = string.format(labelScriptTemplate, labelFormat)
  if valueLabel then
    -- print('Assigning label script to:', valueLabel.name)
    valueLabel.script = labelScript
  end
end

local function setUpPerformFader(controlFader, channel, controlInfo)
  local ccNumber, _, _, _, _, labelMapping, _, _, _, _, startValues, amSyncFader, _, _, _, _ = table.unpack(controlInfo)

  if not startValues or startValues == '' then
    -- Just so we don't break the script
    startValues = '{}'
  end

  if not amSyncFader then
    amSyncFader = 'false'
  end

  -- print('Generating perform fader script for:', controlFader.name, labelMapping, startValues, amSyncFader, mappingScripts[labelMapping])

  local faderScript = string.format(performFaderScriptTemplate,
    amSyncFader,
    mappingScripts[labelMapping],
    startValues,
    labelMapping,
    labelMapping,
    channel,
    ccNumber)

  controlFader.script = faderScript
  controlFader:notify('update_label')
end

local function setUpPerformFaders(fxNum, channel, faderGroups)
  -- print('Initialising perform faders')
  local controlInfo = json.toTable(controlsInfo.children[tostring(fxNum)].tag)

  for index = 1, 6 do
    local faderGroup = faderGroups.children[tostring(index)]
    -- Each element contains a control_fader, value_label and name_label
    local controlFader = faderGroup.children.control_fader
    local valueLabel = faderGroup.children.value_label
    local nameLabel = faderGroup.children.name_label

    local control = controlInfo[index]

    if control == nil then
      faderGroup.visible = false
    else
      faderGroup.visible = true

      local ccNumber, _, _, labelText, labelName, labelMapping, labelFormat = table.unpack(control)

      nameLabel.values.text = labelText
      setUpPerformFader(controlFader, channel, control)
      setUpPerformValueLabel(valueLabel, labelFormat)

    end
  end
end

local function setUpPerformPots(fxNum, channel, potGroups)
  -- print('Initialising perform pots')
  local controlInfo = json.toTable(controlsInfo.children[tostring(fxNum)].tag)

  for index = 1, 6 do
    local potGroup = potGroups.children[tostring(index)]

    local control = controlInfo[index]

    if control == nil then
      potGroup.visible = false
    else
      potGroup.visible = true
    end
  end
end

---@diagnostic disable: lowercase-global
function onReceiveNotify(key, value)
  if key == 'init_control_mapper' then
    -- print('Initialising Control Mapper')
    mapControls()
  elseif key == 'init_perform' then
    local fxNum = value[1]
    local channel = value[2]
    local faderGroups = value[3]
    local potGroups = value[4]

    setUpPerformFaders(fxNum, channel, faderGroups)
    setUpPerformPots(fxNum, channel, potGroups)
  end
end