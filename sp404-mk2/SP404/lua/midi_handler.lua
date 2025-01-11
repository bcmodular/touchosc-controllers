local defaultCCValues = {0, 0, 0, 0, 0, 0}
local ccValues = {unpack(defaultCCValues)}
local midiCCs = {16, 17, 18, 80, 81, 82}
local fxNum = 1
local midiChannel = 0
local presetManager = root.children.preset_manager

local controlsInfoArray = {
  {-- 1: filter + drive
  {'cutoff_fader', false},
  {'resonance_fader', false},
  {'drive_fader', false},
  {'filter_type_grid', false},
  {'low_freq_fader', false},
  {'low_gain_fader', false}
  },
  {-- 2: resonator
  {'root_label', true},
  {'bright_fader', false},
  {'feedback_fader', false},
  {'chord_grid', true},
  {'panning_fader', false},
  {'env_mod_fader', false}
  },
  {-- 3: sync delay
  {'time_grid', false},
  {'feedback_fader', false},
  {'level_fader', false},
  {'l_damp_f_grid', false},
  {'h_damp_f_grid', false}
  },
  {-- 4: isolator
  {'low_fader', false},
  {'mid_fader', false},
  {'high_fader', false}
  },
  {-- 5: djfx looper
  {'length_fader', false},
  {'speed_fader', false},
  {'on_off_grid', false}
  },
  {-- 6: scatter
  {'type_grid', false},
  {'depth_grid', false},
  {'on_off_grid', false},
  {'speed_grid', false}
  },
  {-- 7: downer
  {'depth_fader', false},
  {'rate_grid', false},
  {'filter_fader', false},
  {'pitch_on_off_grid', false},
  {'resonance_fader', false},
  },
  {-- 8: ha dou
  {'mod_depth_fader', false},
  {'time_fader', false},
  {'level_fader', false},
  {'low_cut_grid', false},
  {'high_cut_grid', false},
  {'pre_delay_fader', false},
  }
}

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
      exclude_marked_presets = true
    end
    
    for index, controlInfo in ipairs(controlInfoArray) do
      local controlObject = controlGroup:findByName(controlInfo[1], true)
      local isExcludable = controlInfo[2]

      --print(index, controlObject.name)
      
      if not isExcludable or not exclude_marked_presets then
      
        if controlObject.type == ControlType.LABEL then
          
          controlObject:notify('new_value', ccValues[index])
          
        elseif controlObject.type == ControlType.GRID then
          
          controlObject:notify('change_selection', ccValues[index])

        else
          
          controlObject.values.x = midiToFloat(ccValues[index])

        end

        syncMIDI(midiCCs[index], ccValues[index])

      end
    end
  
    print('Recalled MIDI values:', unpack(ccValues))
    
  end
  
end