-- Set true to trace UI keys / Launchkey routing in TouchOSC log.
local KEYBOARD_DEBUG = true

local LAUNCHKEY_CONNECTION_INDEX = 4
local SP404_CONNECTION = { true, false, false, false }

local MIDI_NOTE_ON = 0x90
local MIDI_CONTROL_CHANGE = 0xB0
local MIDI_PITCH_BEND = 0xE0

local LAUNCHKEY_KEYS_CHANNEL = 0 -- ch1
local LAUNCHKEY_PADS_CHANNEL = 9 -- ch10
local SUSTAIN_PEDAL_CC = 64

-- Launchkey Mk4 pads on MIDI ch 10 (empirical; differs from manual drum-mode map).
-- Screen top row (pads 9–16: Root, Oct, …) = Launchkey notes 36–39, 44–47.
-- Screen bottom row (pads 1–8: m0, m11, …) = Launchkey notes 40–43, 48–51.
local LAUNCHKEY_DRUM_PAD_NOTE_TO_INDEX = {
  [36] = 9, [37] = 10, [38] = 11, [39] = 12,
  [44] = 13, [45] = 14, [46] = 15, [47] = 16,
  [40] = 1, [41] = 2, [42] = 3, [43] = 4,
  [48] = 5, [49] = 6, [50] = 7, [51] = 8,
}

local SP404_CHROMATIC_CHANNEL = 15 -- ch16
local SP404_VOCODER_CHANNEL = 10 -- ch11

local FX_RESONATOR = 2
local FX_HYPER_RESO = 31
local FX_AUTO_PITCH = 43
local FX_VOCODER = 44
local FX_HARMONY = 45

local RESONATOR_CHORD_VALUES = { 0, 9, 17, 25, 33, 41, 49, 57, 65, 73, 81, 89, 97, 105, 113, 121 }
local VOCODER_HARMONY_VALUES = { 0, 13, 26, 39, 51, 64, 77, 90, 102, 115 }
local KEY_NOTE_VALUES = { 0, 10, 20, 30, 40, 49, 59, 69, 79, 89, 99, 108, 118 }

local KEYBOARD_KEY_SPAN = 24
local MAX_OCTAVE_GRID_VALUE = 9

local keyboardAttachedBus = nil
local keyboardChromaticEnabled = false
local keyboardSustainDown = false
local activeNotes = {}
local deferredNoteOffs = {}

local function debugKeyboard(msg)
  if KEYBOARD_DEBUG then
    print("[Keyboard]", msg)
  end
end

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function midiFromLaunchkeyKeyboard(connections)
  if type(connections) ~= "table" then
    return false
  end
  return connections[LAUNCHKEY_CONNECTION_INDEX] == true
end

local function getBusAccentHex(busNum)
  local tag = json.toTable(root.tag) or {}
  local accents = tag.busAccentHex or {}
  return accents[tostring(busNum)] or "00E6FFFF"
end

local function parseStatus(status)
  local msgType = status - (status % 16)
  local channel = status % 16
  return msgType, channel
end

local function noteKey(channel, note)
  return tostring(channel) .. ":" .. tostring(note)
end

local function sendNoteOn(channel, note, velocity)
  sendMIDI({ MIDI_NOTE_ON + channel, note, velocity }, SP404_CONNECTION)
end

local function sendNoteOff(channel, note)
  sendMIDI({ MIDI_NOTE_ON + channel, note, 0 }, SP404_CONNECTION)
end

local function removeNoteTracking(channel, note)
  local key = noteKey(channel, note)
  activeNotes[key] = nil
  deferredNoteOffs[key] = nil
end

local function sendTrackedNoteOffByKey(key)
  local channelStr, noteStr = key:match("^(%d+):(%d+)$")
  local channel = tonumber(channelStr)
  local note = tonumber(noteStr)
  if channel and note then
    sendNoteOff(channel, note)
  end
end

local function flushTrackedNotes(reason)
  for key, _ in pairs(activeNotes) do
    sendTrackedNoteOffByKey(key)
  end
  for key, _ in pairs(deferredNoteOffs) do
    sendTrackedNoteOffByKey(key)
  end
  activeNotes = {}
  deferredNoteOffs = {}
  debugKeyboard("flush tracked notes: " .. tostring(reason))
end

local function sendRoutedNote(channel, note, velocity)
  local key = noteKey(channel, note)
  if velocity > 0 then
    sendNoteOn(channel, note, velocity)
    activeNotes[key] = true
    deferredNoteOffs[key] = nil
    return
  end

  if keyboardSustainDown then
    if activeNotes[key] then
      deferredNoteOffs[key] = true
    end
  else
    sendNoteOff(channel, note)
    activeNotes[key] = nil
    deferredNoteOffs[key] = nil
  end
end

local function onSustainChanged(down)
  if keyboardSustainDown == down then
    return
  end
  keyboardSustainDown = down
  if not keyboardSustainDown then
    for key, _ in pairs(deferredNoteOffs) do
      sendTrackedNoteOffByKey(key)
      activeNotes[key] = nil
      deferredNoteOffs[key] = nil
    end
  end
end

local function getBusGroup(busNum)
  return root:findByName("bus" .. tostring(busNum) .. "_group", true)
end

local function getBusFxNum(busNum)
  local busGroup = getBusGroup(busNum)
  if not busGroup then
    return 0
  end
  local tag = json.toTable(busGroup.tag) or {}
  return tonumber(tag.fxNum) or 0
end

local function getControlsInfoNode()
  return root.children.controls_info or root:findByName("controls_info", true)
end

local function supportsKeyboardNoteTuning(fxNum)
  return fxNum == FX_RESONATOR
    or fxNum == FX_HYPER_RESO
    or fxNum == FX_AUTO_PITCH
    or fxNum == FX_HARMONY
end

local function setKeyboardHighlightingFlag(active)
  local tag = json.toTable(root.tag) or {}
  tag.keyboardHighlighting = active == true
  root.tag = json.fromTable(tag)
end

local function getPianoKeysList()
  local keysNode = root:findByName("keys", true)
  if not keysNode or not keysNode.children then
    return nil, nil
  end
  local w = keysNode.children.white and keysNode.children.white.children
  local b = keysNode.children.black and keysNode.children.black.children
  if not w or not b then
    return keysNode, nil
  end
  return keysNode, {
    w[1], b[1], w[2], b[2], w[3],
    w[4], b[3], w[5], b[4], w[6], b[5], w[7],
    w[8], b[6], w[9], b[7], w[10],
    w[11], b[8], w[12], b[9], w[13], b[10], w[14],
  }
end

local function selectPianoKeyByNote(midiNote)
  local _keysNode, keysList = getPianoKeysList()
  if not keysList then
    return
  end
  setKeyboardHighlightingFlag(true)
  for i = 1, #keysList do
    local key = keysList[i]
    local noteNum = tonumber(key.name)
    key.values.x = (noteNum == midiNote) and 1 or 0
  end
  setKeyboardHighlightingFlag(false)
end

local function applyKeysOctave(octaveValue)
  local keysNode, keysList = getPianoKeysList()
  if not keysNode or not keysList then
    return
  end
  local index = octaveValue * 12
  for i = 1, #keysList do
    local note = index + (i - 1)
    keysList[i].name = note
    keysList[i].visible = (note <= 127)
  end
  if keysNode.children.C0 then
    keysNode.children.C0.values.text = "C" .. (octaveValue - 1)
  end
  if keysNode.children.C1 then
    keysNode.children.C1.values.text = "C" .. octaveValue
  end
end

local function getCurrentOctaveValue()
  local keysGroup = root:findByName("keys_group", true)
  local octaveGrid = keysGroup and keysGroup:findByName("octave_grid", true)
  if not octaveGrid then
    return 0
  end
  for i = 1, 10 do
    local child = octaveGrid.children[tostring(i)]
    if child and child.values.x == 1 then
      return i - 1
    end
  end
  return 0
end

local function noteInVisibleKeyboardRange(midiNote, octaveValue)
  local base = octaveValue * 12
  return midiNote >= base and midiNote <= base + KEYBOARD_KEY_SPAN - 1
end

local function octaveValueForMidiNote(midiNote, currentOctaveValue)
  if noteInVisibleKeyboardRange(midiNote, currentOctaveValue) then
    return currentOctaveValue
  end
  local octave = math.floor(midiNote / 12)
  while midiNote > octave * 12 + KEYBOARD_KEY_SPAN - 1 do
    octave = octave + 1
  end
  while midiNote < octave * 12 do
    octave = octave - 1
  end
  if octave < 0 then
    return 0
  end
  if octave > MAX_OCTAVE_GRID_VALUE then
    return MAX_OCTAVE_GRID_VALUE
  end
  return octave
end

local function syncOctaveGridSelection(octaveValue)
  local keysGroup = root:findByName("keys_group", true)
  local octaveGrid = keysGroup and keysGroup:findByName("octave_grid", true)
  if not octaveGrid then
    return
  end
  setKeyboardHighlightingFlag(true)
  for i = 1, 10 do
    local child = octaveGrid.children[tostring(i)]
    if child then
      child.values.x = ((i - 1) == octaveValue) and 1 or 0
    end
  end
  setKeyboardHighlightingFlag(false)
end

local function syncKeysUiFromMidiNote(midiNote)
  if not root:findByName("keys", true) then
    return
  end
  local currentOctave = getCurrentOctaveValue()
  local octaveValue = octaveValueForMidiNote(midiNote, currentOctave)
  if octaveValue ~= currentOctave then
    syncOctaveGridSelection(octaveValue)
    applyKeysOctave(octaveValue)
  end
  selectPianoKeyByNote(midiNote)
  debugKeyboard(string.format(
    "syncKeysUiFromMidiNote: note=%d octave=%d (was %d)",
    midiNote, octaveValue, currentOctave))
end

local function updateKeysGroupRootLabel(midiNote)
  local keysGroup = root:findByName("keys_group", true)
  local rootLabel = keysGroup and keysGroup:findByName("root_label", true)
  if rootLabel then
    rootLabel:notify("new_value", midiNote)
  end
end

-- Perform faders live in bus faders/1..6/control_fader; logical names are in controls_info.
local function getPerformControlFader(busNum, controlName)
  local busGroup = getBusGroup(busNum)
  if not busGroup then
    return nil
  end

  local fxNum = getBusFxNum(busNum)
  if fxNum == 0 then
    return nil
  end

  local controlsInfo = getControlsInfoNode()
  local fxNode = controlsInfo and controlsInfo.children[tostring(fxNum)]
  if not fxNode then
    return nil
  end

  local controlInfo = json.toTable(fxNode.tag)
  if not controlInfo then
    return nil
  end

  local slotIndex = nil
  for index = 1, 6 do
    local control = controlInfo[index]
    if control and control[2] == controlName then
      slotIndex = index
      break
    end
  end
  if not slotIndex then
    return nil
  end

  local faders = busGroup:findByName("faders", true)
  local faderGroup = faders and faders.children[tostring(slotIndex)]
  return faderGroup and faderGroup.children.control_fader
end

local function applyFaderCc(busNum, controlName, ccValue)
  local cc = clamp(math.floor(ccValue + 0.5), 0, 127)
  local control = getPerformControlFader(busNum, controlName)
  if not control then
    debugKeyboard(string.format("applyFaderCc: missing %s on bus %d", controlName, busNum))
    return false
  end
  debugKeyboard(string.format("applyFaderCc: bus %d %s <- %d", busNum, controlName, cc))
  control:notify("new_cc_value", cc)
  return true
end

local function setGridIndexOnGrid(grid, index)
  if grid then
    grid:notify("new_index", index)
  end
end

local function setGridIndex(busNum, gridName, index)
  local busGroup = getBusGroup(busNum)
  if busGroup then
    setGridIndexOnGrid(busGroup:findByName(gridName, true), index)
  end

  local keysGroup = root:findByName("keys_group", true)
  if keysGroup then
    setGridIndexOnGrid(keysGroup:findByName(gridName, true), index)
  end
end

local function setTuningFromNote(busNum, fxNum, note)
  local noteValue = clamp(note, 0, 127)
  local noteClass = noteValue % 12

  if fxNum == FX_RESONATOR then
    if applyFaderCc(busNum, "root_fader", noteValue) then
      updateKeysGroupRootLabel(noteValue)
      return true
    end
    return false
  elseif fxNum == FX_HYPER_RESO then
    applyFaderCc(busNum, "note_fader", noteValue)
    return true
  elseif fxNum == FX_AUTO_PITCH then
    applyFaderCc(busNum, "key_fader", KEY_NOTE_VALUES[noteClass + 1])
    return true
  elseif fxNum == FX_HARMONY then
    applyFaderCc(busNum, "key_fader", KEY_NOTE_VALUES[noteClass + 1])
    return true
  end
  return false
end

local function applyChordPad(busNum, fxNum, padIndex)
  if fxNum == FX_RESONATOR then
    if padIndex > #RESONATOR_CHORD_VALUES then
      return false
    end
    applyFaderCc(busNum, "chord_fader", RESONATOR_CHORD_VALUES[padIndex])
    setGridIndex(busNum, "chord_grid", padIndex)
    return true
  elseif fxNum == FX_VOCODER then
    if padIndex > #VOCODER_HARMONY_VALUES then
      return false
    end
    applyFaderCc(busNum, "chord_fader", VOCODER_HARMONY_VALUES[padIndex])
    setGridIndex(busNum, "chord_grid", padIndex)
    return true
  elseif fxNum == FX_HARMONY then
    if padIndex > #VOCODER_HARMONY_VALUES then
      return false
    end
    applyFaderCc(busNum, "harmony_fader", VOCODER_HARMONY_VALUES[padIndex])
    setGridIndex(busNum, "harmony_grid", padIndex)
    return true
  end
  return false
end

local function updateKeyboardRootTag()
  local tag = json.toTable(root.tag) or {}
  tag.keyboardAttachedBus = keyboardAttachedBus
  tag.keyboardChromaticEnabled = keyboardChromaticEnabled
  tag.keyboardSustainDown = keyboardSustainDown
  root.tag = json.fromTable(tag)
end

local function refreshChromaticButton()
  local button = root:findByName("chromatic_keyboard_button", true)
  if button then
    button.values.x = keyboardChromaticEnabled and 1 or 0
  end
end

local function refreshKeysGroupVisibility()
  local keysGroup = root:findByName("keys_group", true)
  if keysGroup then
    keysGroup.visible = keyboardAttachedBus ~= nil
  end
end

local function refreshKeysGroupTheme()
  local keysGroup = root:findByName("keys_group", true)
  if not keysGroup or keyboardAttachedBus == nil then
    return
  end

  local accentHex = getBusAccentHex(keyboardAttachedBus)
  keysGroup.color = Color.fromHexString(accentHex)

  local panicButton = keysGroup:findByName("panic_button", true)
  if panicButton then
    panicButton.color = Color.fromHexString("FF4500FF")
  end
end

local function refreshKeyboardGrabButtons()
  for busNum = 1, 5 do
    local busGroup = getBusGroup(busNum)
    local controlGroup = busGroup and busGroup:findByName("control_group", true)
    local button = controlGroup and controlGroup:findByName("keyboard_grab_button", true)
    local label = controlGroup and controlGroup:findByName("keyboard_grab_label", true)
    if button then
      button.values.x = (keyboardAttachedBus == busNum) and 1 or 0
      button.color = Color.fromHexString(getBusAccentHex(busNum))
    end
    if label then
      if keyboardAttachedBus == busNum then
        label.textColor = Color.fromHexString("000000FF")
      else
        label.textColor = Color.fromHexString(getBusAccentHex(busNum))
      end
    end
  end
end

local function refreshKeyboardUi()
  refreshChromaticButton()
  refreshKeysGroupVisibility()
  refreshKeyboardGrabButtons()
  refreshKeysGroupTheme()
  updateKeyboardRootTag()
end

local function enableKeysGroupChordGrid()
  local keysGroup = root:findByName("keys_group", true)
  local chordGrid = keysGroup and keysGroup:findByName("chord_grid", true)
  if chordGrid then
    chordGrid.tag = "1"
  end
end

local function setAttachedBus(busNum)
  if keyboardAttachedBus == busNum then
    return
  end
  flushTrackedNotes("switch_bus")
  keyboardAttachedBus = busNum
  onSustainChanged(false)
  enableKeysGroupChordGrid()
  refreshKeyboardUi()
end

local function detachBusIfCurrent(busNum)
  if keyboardAttachedBus ~= busNum then
    return
  end
  flushTrackedNotes("detach_bus")
  keyboardAttachedBus = nil
  onSustainChanged(false)
  refreshKeyboardUi()
end

local function chromaticRouteActive()
  return keyboardChromaticEnabled
end

local function vocoderLiveActive(busNum, fxNum)
  return busNum == 5 and fxNum == FX_VOCODER
end

local function routeKeyboardNote(note, velocity)
  local busNum = keyboardAttachedBus
  if not busNum then
    debugKeyboard(string.format("routeKeyboardNote: ignored note=%s vel=%s (no bus attached)", tostring(note), tostring(velocity)))
    return
  end

  local fxNum = getBusFxNum(busNum)
  -- On-screen keys: note comes from keys.lua (octave_grid). Launchkey: use MIDI note as-is
  -- (device octave buttons change what the controller sends).
  local shifted = clamp(note, 0, 127)

  debugKeyboard(string.format(
    "routeKeyboardNote: bus=%d fx=%d note=%s vel=%s chromatic=%s",
    busNum, fxNum, tostring(note), tostring(velocity), tostring(chromaticRouteActive())))

  if vocoderLiveActive(busNum, fxNum) then
    sendRoutedNote(SP404_VOCODER_CHANNEL, shifted, velocity)
    return
  end

  -- Effect note/chord tuning wins over chromatic when this bus has a mappable effect loaded.
  if velocity > 0 and fxNum ~= 0 and supportsKeyboardNoteTuning(fxNum) then
    if setTuningFromNote(busNum, fxNum, shifted) then
      debugKeyboard(string.format("routeKeyboardNote: setTuningFromNote ok fx=%d cc=%d", fxNum, shifted))
      return
    end
    debugKeyboard(string.format("routeKeyboardNote: setTuningFromNote failed fx=%d", fxNum))
  end

  if chromaticRouteActive() then
    local chromaticNote = clamp(shifted, 36, 60)
    sendRoutedNote(SP404_CHROMATIC_CHANNEL, chromaticNote, velocity)
    return
  end

  if velocity == 0 then
    debugKeyboard("routeKeyboardNote: note-off (no action for current mode)")
  else
    debugKeyboard("routeKeyboardNote: no route applied")
  end
end

local function launchkeyPadIndexForNote(note)
  return LAUNCHKEY_DRUM_PAD_NOTE_TO_INDEX[note]
end

local function routePadNote(note, velocity)
  if velocity == 0 then
    return
  end
  local busNum = keyboardAttachedBus
  if not busNum then
    return
  end
  local padIndex = launchkeyPadIndexForNote(note)
  if not padIndex then
    debugKeyboard(string.format("routePadNote: unmapped drum pad note %d", note))
    return
  end
  local fxNum = getBusFxNum(busNum)
  debugKeyboard(string.format("routePadNote: note=%d -> pad %d fx=%d", note, padIndex, fxNum))
  applyChordPad(busNum, fxNum, padIndex)
end

-- Return true when this Launchkey message was handled (root onReceiveMIDI should return).
function handleKeyboardMidi(message, connections)
  if not midiFromLaunchkeyKeyboard(connections) then
    return false
  end

  if not keyboardAttachedBus then
    return false
  end

  local status = message[1]
  local data1 = message[2]
  local data2 = message[3]
  local msgType, channel = parseStatus(status)

  if msgType == MIDI_NOTE_ON then
    if channel == LAUNCHKEY_PADS_CHANNEL then
      routePadNote(data1, data2)
      return true
    elseif channel == LAUNCHKEY_KEYS_CHANNEL then
      routeKeyboardNote(data1, data2)
      if data2 > 0 then
        local fxNum = getBusFxNum(keyboardAttachedBus)
        if supportsKeyboardNoteTuning(fxNum) then
          syncKeysUiFromMidiNote(data1)
        end
      end
      return true
    end
    return false
  end

  if msgType == MIDI_CONTROL_CHANGE and channel == LAUNCHKEY_KEYS_CHANNEL and data1 == SUSTAIN_PEDAL_CC then
    onSustainChanged(data2 >= 64)
    updateKeyboardRootTag()
    return true
  end

  if msgType == MIDI_PITCH_BEND then
    local busNum = keyboardAttachedBus
    if busNum then
      local fxNum = getBusFxNum(busNum)
      if vocoderLiveActive(busNum, fxNum) then
        sendMIDI({ MIDI_PITCH_BEND + SP404_VOCODER_CHANNEL, data1, data2 }, SP404_CONNECTION)
        return true
      end
    end
    return false
  end

  return false
end

function handleKeyboardNotify(key, value)
  if key == "keyboard_attach_bus" then
    setAttachedBus(tonumber(value) or 1)
    return true
  elseif key == "keyboard_detach_bus" then
    detachBusIfCurrent(tonumber(value) or -1)
    return true
  elseif key == "keyboard_chromatic_toggle" then
    keyboardChromaticEnabled = value == true
    refreshKeyboardUi()
    return true
  elseif key == "keyboard_panic" then
    flushTrackedNotes("panic_button")
    onSustainChanged(false)
    updateKeyboardRootTag()
    return true
  elseif key == "keyboard_refresh_ui" then
    refreshKeyboardUi()
    return true
  elseif key == "keyboard_ui_note" then
    local note, velocity
    if type(value) == "table" then
      note = tonumber(value[1])
      velocity = tonumber(value[2]) or 0
    else
      note = tonumber(value)
      velocity = 127
    end
    debugKeyboard(string.format(
      "keyboard_ui_note: note=%s vel=%s attachedBus=%s valueType=%s",
      tostring(note), tostring(velocity), tostring(keyboardAttachedBus), type(value)))
    if note then
      routeKeyboardNote(note, velocity)
    else
      debugKeyboard("keyboard_ui_note: missing note number")
    end
    return true
  elseif key == "keyboard_key_select" then
    local note, velocity
    if type(value) == "table" then
      note = tonumber(value[1])
      velocity = tonumber(value[2]) or 0
    else
      note = tonumber(value)
      velocity = 127
    end
    debugKeyboard(string.format("keyboard_key_select: note=%s vel=%s", tostring(note), tostring(velocity)))
    if note and velocity > 0 then
      selectPianoKeyByNote(note)
      routeKeyboardNote(note, velocity)
    end
    return true
  elseif key == "keyboard_ui_chord_pad" then
    local padIndex = tonumber(value)
    if padIndex then
      local busNum = keyboardAttachedBus
      if busNum then
        applyChordPad(busNum, getBusFxNum(busNum), padIndex)
      end
    end
    return true
  end
  return false
end

function initKeyboardManager()
  local tag = json.toTable(root.tag) or {}
  keyboardAttachedBus = tonumber(tag.keyboardAttachedBus)
  keyboardChromaticEnabled = tag.keyboardChromaticEnabled == true
  keyboardSustainDown = false
  activeNotes = {}
  deferredNoteOffs = {}
  refreshKeyboardUi()
end
