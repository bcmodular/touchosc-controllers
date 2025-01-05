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

function midiToFrequency(midiValue)

--    print("midiToFrequency called with midiValue:", midiValue)
  return midiToFrequencyMap[midiValue + 1]
  
end

function midiToEQRange(midiValue)

  print("midiToEQRange called with midiValue:", midiValue)
  return midiToEQRangeMap[midiValue + 1]
  
end

function getEQ(value)

  local scaledValue = midiToEQRange(math.floor(value * 127 + 0.5))
  print("getEQ called with value:", value, "scaledValue:", scaledValue)
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

function getMinusOneHundredToOneHundred(value)
  --TODO: This is not correct
  local midiValue = math.floor(value * 127 + 0.5)

  if midiValue == 127 then
    return 100
  elseif midiValue == 0 then
    return -100
  else
    return math.floor((midiValue / 127.5) * 200) - 100
  end

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

function getLooperLength(value)
  -- TODO
  -- Seems to be very close now - just need to check one last time
  if value == 1 then
    return 0.012
  else
    local midiValue = math.floor(value * 127 + 0.5)
    local looperValue = 0.230 - (midiValue / 127.5 * 0.218)
    looperValue = math.floor(looperValue * 1000 + 0.5) / 1000
    looperValue = string.format("%.3f", looperValue)
    print("getLooperLength called with value:", value, "looperValue:", looperValue)
    return looperValue
  end
end

function onReceiveNotify(key, value)

  --------------------------------
  -- MAPPING NOTIFICATION HANDLING
  --------------------------------

  if key == 'get_freq' then
    
    local result = getFreq(value[2])
    value[1]:notify('result', result)

  elseif key == 'get_eq' then
    
    local result = getEQ(value[2])
    value[1]:notify('result', result)

  elseif key == 'get_zero_one_hundred' then

    local result = getZeroOneHundred(value[2])
    value[1]:notify('result', result)

  elseif key == 'get_minus_one_hundred_to_one_hundred' then

    local result = getMinusOneHundredToOneHundred(value[2])
    value[1]:notify('result', result)

  elseif key == 'get_zero_ninety_nine' then

    local result = getZeroNinetyNine(value[2])
    value[1]:notify('result', result)    

  elseif key == 'get_24_dB' then

    local result = get24dB(value[2])
    value[1]:notify('result', result)

  elseif key == 'get_looper_length' then

    local result = getLooperLength(value[2])
    value[1]:notify('result', result)

  end

end