-------------------
-- MAPPING HANDLING
-------------------

-- Precomputed MIDI-to-Frequency mapping table
local midiToFrequencyMap = {
  20.0, 21.1, 22.2, 23.4, 24.7, 26.0, 27.4, 28.9, 30.4, 32.1, 33.8, 35.6, 37.5, 39.5, 41.7, 43.9, 46.3, 48.8, 51.4, 54.2, 57.1, 60.1, 63.4, 66.8, 70.4, 74.2, 78.2, 82.4, 86.8, 91.5, 96.4, 102.0, 107.0, 113.0, 119.0, 125.0, 132.0, 139.0, 147.0, 155.0, 163.0, 172.0, 181.0, 191.0, 201.0, 212.0, 223.0, 235.0, 248.0, 261.0, 275.0, 290.0, 306.0, 322.0, 339.0, 358.0, 377.0, 397.0, 418.0, 441.0, 465.0, 490.0, 516.0, 544.0, 573.0, 604.0, 637.0, 671.0, 707.0, 745.0, 785.0, 827.0, 872.0, 919.0, 968.0, 1020.0, 1075.0, 1133.0, 1194.0, 1258.0, 1326.0, 1397.0, 1473.0, 1552.0, 1636.0, 1724.0, 1816.0, 1914.0, 2017.0, 2126.0, 2240.0, 2361.0, 2488.0, 2622.0, 2763.0, 2912.0, 3068.0, 3233.0, 3407.0, 3591.0, 3784.0, 3988.0, 4202.0, 4429.0, 4667.0, 4918.0, 5183.0, 5462.0, 5756.0, 6066.0, 6392.0, 6736.0, 7099.0, 7481.0, 7884.0, 8308.0, 8755.0, 9227.0, 9723.0, 10247.0, 10798.0, 11379.0, 11992.0, 12637.0, 13318.0, 14035.0, 14790.0, 16000.0
}

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

local bipolarHundredRangeMap = {
    -100, -99, -97, -96, -94, -93, -91, -89, -88, -86, -85, -83, -82, -80, -78, -77, -75,
    -74, -72, -71, -69, -67, -66, -64, -63, -61, -60, -58, -56, -55, -53, -52, -50, -48,
    -47, -45, -44, -42, -41, -39, -37, -36, -34, -33, -31, -30, -28, -26, -25, -23, -22,
    -20, -19, -17, -15, -14, -12, -11, -9, -7, -6, -4, -3, -1, 0, 2, 4, 5, 7, 8, 10, 11,
    13, 15, 16, 18, 19, 21, 22, 24, 26, 27, 29, 30, 32, 34, 35, 37, 38, 40, 41, 43, 45,
    46, 48, 49, 51, 52, 54, 56, 57, 59, 60, 62, 63, 65, 67, 68, 70, 71, 73, 74, 76, 78,
    79, 81, 82, 84, 86, 87, 89, 90, 92, 93, 95, 97, 98, 100
}

local hundredMSRangeMap = {
    0, 0, 1, 2, 3, 3, 4, 5, 6, 7, 7, 8, 9, 10, 11, 11, 12, 13, 14, 15, 15, 16, 
    17, 18, 19, 19, 20, 21, 22, 22, 23, 24, 25, 26, 26, 27, 28, 29, 30, 30, 31, 
    32, 33, 34, 34, 35, 36, 37, 38, 38, 39, 40, 41, 41, 42, 43, 44, 45, 45, 46, 
    47, 48, 49, 49, 50, 51, 52, 53, 53, 54, 55, 56, 57, 57, 58, 59, 60, 61, 61, 
    62, 63, 64, 64, 65, 66, 67, 68, 68, 69, 70, 71, 72, 72, 73, 74, 75, 76, 76, 
    77, 78, 79, 80, 80, 81, 82, 83, 83, 84, 85, 86, 87, 87, 88, 89, 90, 91, 91, 
    92, 93, 94, 95, 95, 96, 97, 98, 99, 99, 100
}

local balanceRangeMap = {
  0, 1, 2, 2, 3, 4, 5, 5, 6, 7, 8, 9, 9, 10, 11, 12, 13, 13, 14, 15, 16, 16,
  17, 18, 19, 20, 20, 21, 22, 23, 24, 24, 25, 26, 27, 27, 28, 29, 30, 31, 31,
  32, 33, 34, 35, 35, 36, 37, 38, 38, 39, 40, 41, 42, 42, 43, 44, 45, 45, 46,
  47, 48, 49, 49, 50, 51, 52, 53, 53, 54, 55, 56, 56, 57, 58, 59, 60, 60, 61,
  62, 63, 64, 64, 65, 66, 67, 67, 68, 69, 70, 71, 71, 72, 73, 74, 75, 75, 76,
  77, 78, 78, 79, 80, 81, 82, 82, 83, 84, 85, 85, 86, 87, 88, 89, 89, 90, 91,
  92, 93, 93, 94, 95, 96, 96, 97, 98, 99, 100
}

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

function midiToFrequency(midiValue)

--    print("midiToFrequency called with midiValue:", midiValue)
  return midiToFrequencyMap[midiValue + 1]
  
end

function midiToEQRange(midiValue)

--  print("midiToEQRange called with midiValue:", midiValue)
  return midiToEQRangeMap[midiValue + 1]
  
end

function getEQ(value)

  local scaledValue = midiToEQRange(math.floor(value * 127 + 0.5))
--  print("getEQ called with value:", value, "scaledValue:", scaledValue)
  return scaledValue
  
end

function getFreq(value)

  local scaledValue = midiToFrequency(math.floor(value * 127 + 0.5))
--    print("getFreq called with value:", value, "scaledValue:", scaledValue)
  return scaledValue
  
end

function getZeroOneHundred(value)

  local midiValue = math.floor(value * 127 + 0.5)

  if midiValue == 127 then
    return 100
  else
    return math.floor((midiValue / 127.5) * 100)
  end

end

function getBipolarHundred(value)
 
  local midiValue = math.floor(value * 127 + 0.5)

  return bipolarHundredRangeMap[midiValue + 1]

end

function getBalance(value)
 
  local midiValue = math.floor(value * 127 + 0.5)

  return balanceRangeMap[midiValue + 1]

end

function getHundredMS(value)
 
  local midiValue = math.floor(value * 127 + 0.5)

  return hundredMSRangeMap[midiValue + 1]

end

function getTapeSpeed(value)
 
  local midiValue = math.floor(value * 127 + 0.5)

  return tapeSpeedMap[midiValue + 1]

end

function getZeroNinetyNine(value)

  local midiValue = math.floor(value * 127 + 0.5)

  if midiValue == 127 then
    return 99
  else
    return math.floor((midiValue / 127.5) * 99)
  end
    
end

function get24dB(value)

  local midiValue = math.floor(value * 127 + 0.5)
  local dbValue = math.floor((midiValue / 127.5) * 49) - 24

  -- Correct the specific case for MIDI value 13
  if midiValue == 13 then
    return -19
  else
    return dbValue
  end

end

function getSBFGain(value)

  local midiValue = math.floor(value * 127 + 0.5)

  return sbfGainMap[midiValue + 1]

end

function getLooperLength(value)
  local midiValue = math.floor(value * 127 + 0.5)
    
  if midiValue == 127 then
    return 0.012
  else
    local looperValue = 0.230 - (midiValue / 127.5 * 0.218)
    looperValue = math.floor(looperValue * 1000 + 0.5) / 1000
    looperValue = string.format("%.3f", looperValue)
    
    return looperValue
  end
end

function onReceiveNotify(key, value)

  --------------------------------
  -- MAPPING NOTIFICATION HANDLING
  --------------------------------
  local resultKey = 'result'
  
  if value[3] ~= nil then
    resultKey = value[3]
  end
    
  if key == 'get_freq' then
    
    local result = getFreq(value[2])
    value[1]:notify(resultKey, result)

  elseif key == 'get_eq' then
    
    local result = getEQ(value[2])
    value[1]:notify(resultKey, result)

  elseif key == 'get_zero_one_hundred' then

    local result = getZeroOneHundred(value[2])
    value[1]:notify(resultKey, result)

  elseif key == 'get_hundred_ms' then

    local result = getHundredMS(value[2])
    value[1]:notify(resultKey, result)

  elseif key == 'get_tape_speed' then

    local result = getTapeSpeed(value[2])
    value[1]:notify(resultKey, result)

  elseif key == 'get_bipolar_hundred' then

    local result = getBipolarHundred(value[2])
    value[1]:notify(resultKey, result)

  elseif key == 'get_balance' then

    local result = getBalance(value[2])
    value[1]:notify(resultKey, result)

  elseif key == 'get_zero_ninety_nine' then

    local result = getZeroNinetyNine(value[2])
    value[1]:notify(resultKey, result)    

  elseif key == 'get_24_dB' then

    local result = get24dB(value[2])
    value[1]:notify(resultKey, result)

  elseif key == 'get_sbf_gain' then

    local result = getSBFGain(value[2])
    value[1]:notify(resultKey, result)

  elseif key == 'get_looper_length' then

    local result = getLooperLength(value[2])
    value[1]:notify(resultKey, result)

  end

end