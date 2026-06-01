-- All locals live inside _initKeyboard's function scope, keeping the outer chunk
-- (shared with root.lua and other includes) well under Lua's 200-local limit.
-- The three public entry points are assigned as globals inside the function so
-- root.lua can call them by name without any prefix.
function _initKeyboard()

local KEYBOARD_DEBUG = false

local LAUNCHKEY_CONNECTION_INDEX = 4
local SP404_CONNECTION = { true, false, false, false }

-- ch10 (0-based); keys may arrive on ch1 or ch2 depending on device mode
local LAUNCHKEY_PADS_CHANNEL = 9
local CHROMATIC_KEYS_FALLBACK_HEX = "FF4500FF"
local SOUNDGEN_KEYS_HEX = "4C00ADFF"
local SUSTAIN_PEDAL_CC = 64

local SP404_CHROMATIC_CHANNEL = 15 -- ch16
local SP404_VOCODER_CHANNEL = 10 -- ch11

local FX_RESONATOR = 2
local FX_HYPER_RESO = 31
local FX_VOCODER = 44

local RESONATOR_CHORD_VALUES = { 0, 9, 17, 25, 33, 41, 49, 57, 65, 73, 81, 89, 97, 105, 113, 121 }
local VOCODER_HARMONY_VALUES = { 0, 13, 26, 39, 51, 64, 77, 90, 102, 115 }

local KEYBOARD_KEY_SPAN = 24
local MAX_OCTAVE_GRID_VALUE = 9
local MAX_POLYPHONIC_VOICES = 4

-- SP-404 chromatic range is C2–C4 (MIDI 36–60). UI octave buttons 4/5 = display octaves 2/3.
local CHROMATIC_MIN_NOTE = 36
local CHROMATIC_MAX_NOTE = 60
local CHROMATIC_OCTAVE_UI_2 = 3
local CHROMATIC_OCTAVE_UI_3 = 4

-- Hyper Reso (FX 31): NOTE = scale degree -17..18; SCALE = 24 roots (maj/min).
local HYPER_RESO_NOTE_CC_VALUES = {
  0, 4, 8, 11, 15, 19, 22, 26, 30, 33, 37, 41, 44, 48, 51, 55, 59,
  62, 66, 70, 73, 77, 81, 84, 88, 92, 95, 99, 102, 106, 110, 113, 117, 121, 124,
}
local HYPER_RESO_SCALE_CC_VALUES = {
  0, 6, 11, 16, 22, 27, 32, 38, 43, 48, 54, 59, 64, 70, 75, 80, 85, 91, 96, 101, 107, 112, 117, 123,
}
local HYPER_RESO_NOTE_MIN = -17
local HYPER_RESO_NOTE_MAX = 18
local HYPER_RESO_WHITE_KEYS_PER_OCTAVE = 7
local HYPER_RESO_OCTAVE_COUNT = 5
-- UI octave 3: left span labeled C2, right span C3; MIDI 60 (middle C) = degree 1.
local HYPER_RESO_ANCHOR_UI_OCTAVE = 3
local HYPER_RESO_ANCHOR_MIDI = 60
local HYPER_RESO_DEGREES = {}
for _d = HYPER_RESO_NOTE_MIN, -1 do
  HYPER_RESO_DEGREES[#HYPER_RESO_DEGREES + 1] = _d
end
for _d = 1, HYPER_RESO_NOTE_MAX do
  HYPER_RESO_DEGREES[#HYPER_RESO_DEGREES + 1] = _d
end
local HYPER_RESO_MIDI_TO_DEGREE = {}
local HYPER_RESO_DEGREE_TO_MIDI = {}
local HYPER_RESO_WHITE_MIDI_MIN = nil
local HYPER_RESO_WHITE_MIDI_MAX = nil

-- keys_group chord_grid pads 1-16 (top row 1-8, bottom 9-16).
local HYPER_RESO_PAD_MAP = {
  [1] = "major",
  [2] = "unused",
  [3] = 1, [4] = 3, [5] = "unused",
  [6] = 6, [7] = 8, [8] = 10,
  [9] = "minor",
  [10] = 0, [11] = 2, [12] = 4, [13] = 5, [14] = 7, [15] = 9, [16] = 11,
}
local HYPER_RESO_PAD_LABELS = {
  [1] = "Maj", [2] = "", [3] = "C#", [4] = "D#", [5] = "",
  [6] = "F#", [7] = "G#", [8] = "A#",
  [9] = "Min", [10] = "C", [11] = "D", [12] = "E", [13] = "F",
  [14] = "G", [15] = "A", [16] = "B",
}
local CHORD_GRID_MODE_HYPER_RESO = "hyper_reso_scale"
local CHORD_GRID_MODE_CHORD_PADS = "chord_pads"

-- Pitch classes that correspond to black piano keys (sharps/flats).
local HYPER_RESO_BLACK_PC = { [1]=true, [3]=true, [6]=true, [8]=true, [10]=true }

local function hyperResoPadColor(role)
  if role == "major" then
    return Color.fromHexString("FFB300FF")   -- gold
  elseif role == "minor" then
    return Color.fromHexString("0066FFFF")   -- blue
  elseif type(role) == "number" then
    if HYPER_RESO_BLACK_PC[role] then
      return Color.fromHexString("4C00ADFF") -- dark purple (black keys)
    else
      return Color.fromHexString("FFFFFFFF") -- white (natural keys)
    end
  end
end

-- Novation palette indices for Launchkey pad LEDs in Hyper Reso mode.
-- Mirrors hyperResoPadColor() colors. Selected = full brightness, unselected = dim.
-- Exact indices TBD — verify against physical device; adjust if colors look wrong.
local LAUNCHKEY_HYPER_RESO_PALETTE = {
  major = { full=60,  dim=10  }, -- gold / amber
  minor = { full=33,  dim=18  }, -- blue
  white = { full=3,   dim=1   }, -- white
  black = { full=41,  dim=19  }, -- purple
}

local function launchkeyHyperResoPalette(role, selected)
  local entry
  if role == "major" then
    entry = LAUNCHKEY_HYPER_RESO_PALETTE.major
  elseif role == "minor" then
    entry = LAUNCHKEY_HYPER_RESO_PALETTE.minor
  elseif type(role) == "number" then
    entry = HYPER_RESO_BLACK_PC[role]
      and LAUNCHKEY_HYPER_RESO_PALETTE.black
      or  LAUNCHKEY_HYPER_RESO_PALETTE.white
  end
  if not entry then return 0 end
  return selected and entry.full or entry.dim
end

-- syncLaunchkeyHyperResoPadLeds is defined after getHyperResoBusState (see below).

local keyboardAttachedBus = nil
-- Mutually exclusive with keyboardAttachedBus: SP-404 chromatic playback (MIDI ch16).
local keyboardChromaticAttached = false
-- Sound Gen: full-range momentary notes on ch16, all octaves available.
-- Mutually exclusive with keyboardChromaticAttached and keyboardAttachedBus.
local keyboardSoundGenAttached = false
local keyboardSustainDown = false
local activeNotes = {}
local deferredNoteOffs = {}
-- Insertion-order queue of active note keys for Vocoder FIFO voice eviction.
local activeNoteQueue = {}
-- UI note numbers held for chromatic / vocoder (max MAX_POLYPHONIC_VOICES).
local uiActiveNotes = {}
-- Maps activeNotes key (channel:note) -> UI midi note for sustain / release sync.
local activeNoteUi = {}
-- Launchkey keybed notes currently held (for on-screen octave window).
local launchkeyHeldNotes = {}

-- Forward declarations for functions called before their definition.
local refreshPianoKeysFromUiActive
local notesForOctaveFollow
local syncOctaveForHyperResoDegree
local syncKeyboardNoteFromPerformFaders
local getPerformControlCc
local hyperResoDegreeFromCc

local function debugKeyboard(msg)
  if KEYBOARD_DEBUG then
    print("[Keyboard]", msg)
  end
end

local function clamp(value, minValue, maxValue)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function midiFromLaunchkeyKeyboard(connections)
  if type(connections) ~= "table" then return false end
  return connections[LAUNCHKEY_CONNECTION_INDEX] == true
end

local function isLaunchkeyPadsChannel(channel)
  return channel == LAUNCHKEY_PADS_CHANNEL
end

local function noteVelocityFromMidi(msgType, velocity)
  if msgType == MIDIMessageType.NOTE_OFF then return 0 end
  return velocity or 0
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
  sendMIDI({ MIDIMessageType.NOTE_ON + channel, note, velocity }, SP404_CONNECTION)
end

local function sendNoteOff(channel, note)
  sendMIDI({ MIDIMessageType.NOTE_ON + channel, note, 0 }, SP404_CONNECTION)
end

local function sendTrackedNoteOffByKey(key)
  local channelStr, noteStr = key:match("^(%d+):(%d+)$")
  local channel = tonumber(channelStr)
  local note = tonumber(noteStr)
  if channel and note then sendNoteOff(channel, note) end
end

local function clearUiActiveNotes()
  uiActiveNotes = {}
end

local function getBusGroup(busNum)
  return root:findByName("bus" .. tostring(busNum) .. "_group", true)
end

local function getBusFxNum(busNum)
  local busGroup = getBusGroup(busNum)
  if not busGroup then return 0 end
  local tag = json.toTable(busGroup.tag) or {}
  if type(resolveBusFxNum) == "function" then
    return resolveBusFxNum(tag)
  end
  return tonumber(tag.fxNum) or 0
end

local function vocoderLiveActive(busNum, fxNum)
  return busNum == 5 and fxNum == FX_VOCODER
end

local function pianoKeysMomentary()
  if keyboardChromaticAttached or keyboardSoundGenAttached then return true end
  local busNum = keyboardAttachedBus
  if busNum then return vocoderLiveActive(busNum, getBusFxNum(busNum)) end
  return false
end

local function sustainTargetChannel()
  if keyboardChromaticAttached or keyboardSoundGenAttached then return SP404_CHROMATIC_CHANNEL end
  local busNum = keyboardAttachedBus
  if busNum and vocoderLiveActive(busNum, getBusFxNum(busNum)) then
    return SP404_VOCODER_CHANNEL
  end
  return nil
end

local function countUiActiveNotes()
  local count = 0
  for _ in pairs(uiActiveNotes) do count = count + 1 end
  return count
end

local function setUiNoteActive(uiNote, active)
  if uiNote == nil then return end
  uiActiveNotes[uiNote] = active and true or nil
end

local function releaseUiForNoteKey(key)
  local uiNote = activeNoteUi[key]
  if uiNote ~= nil then
    setUiNoteActive(uiNote, false)
    activeNoteUi[key] = nil
  end
end

local function flushTrackedNotes(reason)
  for key, _ in pairs(activeNotes) do
    sendTrackedNoteOffByKey(key)
    releaseUiForNoteKey(key)
  end
  for key, _ in pairs(deferredNoteOffs) do
    sendTrackedNoteOffByKey(key)
    releaseUiForNoteKey(key)
  end
  activeNotes = {}
  deferredNoteOffs = {}
  activeNoteQueue = {}
  clearUiActiveNotes()
  activeNoteUi = {}
  launchkeyHeldNotes = {}
  refreshPianoKeysFromUiActive()
  debugKeyboard("flush tracked notes: " .. tostring(reason))
end

local function isVocoderLive()
  return keyboardAttachedBus ~= nil
    and vocoderLiveActive(keyboardAttachedBus, getBusFxNum(keyboardAttachedBus))
end

local function canAcceptPolyphonicNote(uiNote, velocity)
  if velocity <= 0 then return true end
  if keyboardSoundGenAttached then return true end
  if not pianoKeysMomentary() then return true end
  if isVocoderLive() then return true end  -- Vocoder uses FIFO eviction, not hard cap
  if uiNote == nil then return true end
  if uiActiveNotes[uiNote] then return true end
  return countUiActiveNotes() < MAX_POLYPHONIC_VOICES
end

-- Evict the oldest active note to make room for a new one (Vocoder FIFO).
local function evictOldestActiveNote()
  while #activeNoteQueue > 0 do
    local oldest = table.remove(activeNoteQueue, 1)
    if activeNotes[oldest] then
      sendTrackedNoteOffByKey(oldest)
      releaseUiForNoteKey(oldest)
      activeNotes[oldest] = nil
      deferredNoteOffs[oldest] = nil
      return true
    end
  end
  return false
end

local function sendRoutedNote(channel, note, velocity, uiNote)
  local key = noteKey(channel, note)
  if velocity > 0 then
    if keyboardSoundGenAttached and keyboardSustainDown then
      -- Sound Gen + sustain: discard all held and deferred notes so only the new note sounds.
      for k, _ in pairs(activeNotes) do
        sendTrackedNoteOffByKey(k)
        releaseUiForNoteKey(k)
      end
      activeNotes = {}
      deferredNoteOffs = {}
      activeNoteQueue = {}
    elseif isVocoderLive()
      and not (uiNote ~= nil and uiActiveNotes[uiNote])  -- re-press of held note: no eviction needed
      and countUiActiveNotes() >= MAX_POLYPHONIC_VOICES then
      -- Vocoder FIFO: evict oldest sounding note before adding the new one.
      if evictOldestActiveNote() then
        refreshPianoKeysFromUiActive()
      end
    elseif not canAcceptPolyphonicNote(uiNote, velocity) then
      debugKeyboard(string.format("polyphony full: ignored ui note %s", tostring(uiNote)))
      return false
    end
    sendNoteOn(channel, note, velocity)
    local isNewNote = not activeNotes[key]
    activeNotes[key] = true
    deferredNoteOffs[key] = nil
    -- Always move to back of queue: new note appends, re-press removes old position first.
    if not isNewNote then
      for i = #activeNoteQueue, 1, -1 do
        if activeNoteQueue[i] == key then table.remove(activeNoteQueue, i); break end
      end
    end
    activeNoteQueue[#activeNoteQueue + 1] = key
    if pianoKeysMomentary() and uiNote ~= nil then
      activeNoteUi[key] = uiNote
      setUiNoteActive(uiNote, true)
    end
    return true
  end

  if keyboardSustainDown then
    if activeNotes[key] then deferredNoteOffs[key] = true end
    -- Keep pressed-key display until sustain releases (see onSustainChanged).
  else
    sendNoteOff(channel, note)
    activeNotes[key] = nil
    deferredNoteOffs[key] = nil
    -- Remove from FIFO queue so stale entries don't accumulate.
    for i = #activeNoteQueue, 1, -1 do
      if activeNoteQueue[i] == key then
        table.remove(activeNoteQueue, i)
        break
      end
    end
    if pianoKeysMomentary() and uiNote ~= nil then
      activeNoteUi[key] = nil
      setUiNoteActive(uiNote, false)
    end
  end
  return true
end

local function onSustainChanged(down)
  if keyboardSustainDown == down then return end
  keyboardSustainDown = down

  local channel = sustainTargetChannel()
  if channel then
    sendMIDI({
      MIDIMessageType.CONTROLCHANGE + channel,
      SUSTAIN_PEDAL_CC,
      down and 127 or 0,
    }, SP404_CONNECTION)
  end

  if not keyboardSustainDown then
    for key, _ in pairs(deferredNoteOffs) do
      sendTrackedNoteOffByKey(key)
      activeNotes[key] = nil
      deferredNoteOffs[key] = nil
      releaseUiForNoteKey(key)
    end
    activeNoteQueue = {}
    refreshPianoKeysFromUiActive()
  end
end

local function getControlsInfoNode()
  return root.children.controls_info or root:findByName("controls_info", true)
end

local function supportsKeyboardNoteTuning(fxNum)
  return fxNum == FX_RESONATOR
    or fxNum == FX_HYPER_RESO
end

local function fxSupportsKeyboard(fxNum, busNum)
  if fxNum == 0 then return false end
  if type(isEffectOnMidiAvailable) ~= "function" or not isEffectOnMidiAvailable(fxNum, busNum) then
    return false
  end
  if fxNum == FX_VOCODER then return busNum == 5 end
  return supportsKeyboardNoteTuning(fxNum)
end

local function keyboardIsAttached()
  return keyboardChromaticAttached or keyboardSoundGenAttached or keyboardAttachedBus ~= nil
end

local function parseNotifyBool(value)
  return value == true or value == 1 or value == "1" or value == "true"
end

local function setKeyboardHighlightingFlag(active)
  local tag = json.toTable(root.tag) or {}
  tag.keyboardHighlighting = active == true
  root.tag = json.fromTable(tag)
end

local function getPianoKeysList()
  local keysNode = root:findByName("keys", true)
  if not keysNode or not keysNode.children then return nil, nil end
  local w = keysNode.children.white and keysNode.children.white.children
  local b = keysNode.children.black and keysNode.children.black.children
  if not w or not b then return keysNode, nil end
  return keysNode, {
    w[1], b[1], w[2], b[2], w[3],
    w[4], b[3], w[5], b[4], w[6], b[5], w[7],
    w[8], b[6], w[9], b[7], w[10],
    w[11], b[8], w[12], b[9], w[13], b[10], w[14],
  }
end

local function isHyperResoKeyboard()
  if keyboardChromaticAttached or not keyboardAttachedBus then return false end
  return getBusFxNum(keyboardAttachedBus) == FX_HYPER_RESO
end

local function isWhiteKeyPitch(midiNote)
  local pc = midiNote % 12
  return pc == 0 or pc == 2 or pc == 4 or pc == 5 or pc == 7 or pc == 9 or pc == 11
end

local function isHyperResoDegree(value)
  value = tonumber(value)
  if not value or value == 0 then return false end
  return value >= HYPER_RESO_NOTE_MIN and value <= HYPER_RESO_NOTE_MAX
end

local function hyperResoDegreeFromInput(note)
  note = tonumber(note)
  if not note then return nil end
  if isHyperResoDegree(note) then return note end
  if not isWhiteKeyPitch(note) then return nil end
  local degree = HYPER_RESO_MIDI_TO_DEGREE[note]
  if degree then return degree end
  if HYPER_RESO_WHITE_MIDI_MIN and note < HYPER_RESO_WHITE_MIDI_MIN then
    return HYPER_RESO_NOTE_MIN
  end
  if HYPER_RESO_WHITE_MIDI_MAX and note > HYPER_RESO_WHITE_MIDI_MAX then
    return HYPER_RESO_NOTE_MAX
  end
  return nil
end

local function setPianoKeyHighlight(note, on)
  local _keysNode, keysList = getPianoKeysList()
  if not keysList or note == nil then return end
  local match = note
  if isHyperResoKeyboard() then
    match = hyperResoDegreeFromInput(note)
    if not match then return end
  end
  setKeyboardHighlightingFlag(true)
  for i = 1, #keysList do
    local key = keysList[i]
    if tonumber(key.name) == match then
      key.values.x = on and 1 or 0
      break
    end
  end
  setKeyboardHighlightingFlag(false)
end

refreshPianoKeysFromUiActive = function()
  if not pianoKeysMomentary() then return end
  local _keysNode, keysList = getPianoKeysList()
  if not keysList then return end
  setKeyboardHighlightingFlag(true)
  for i = 1, #keysList do
    local key = keysList[i]
    local noteNum = tonumber(key.name)
    local want = (noteNum and uiActiveNotes[noteNum]) and 1 or 0
    -- Only write when the value changes to avoid spurious onValueChanged on key nodes.
    if key.values.x ~= want then key.values.x = want end
  end
  setKeyboardHighlightingFlag(false)
end

local function selectPianoKeyByNote(note)
  local _keysNode, keysList = getPianoKeysList()
  if not keysList then return end
  local match = note
  if isHyperResoKeyboard() then
    match = hyperResoDegreeFromInput(note)
    if not match then return end
  end
  setKeyboardHighlightingFlag(true)
  for i = 1, #keysList do
    local key = keysList[i]
    key.values.x = (tonumber(key.name) == match) and 1 or 0
  end
  setKeyboardHighlightingFlag(false)
end

local function getCurrentOctaveValue()
  local keysGroup = root:findByName("keys_group", true)
  local octaveGrid = keysGroup and keysGroup:findByName("octave_grid", true)
  if not octaveGrid then return 0 end
  for i = 1, 10 do
    local child = octaveGrid.children[tostring(i)]
    if child and child.visible ~= false and child.values.x == 1 then
      return i - 1
    end
  end
  if keyboardChromaticAttached then return CHROMATIC_OCTAVE_UI_2 end
  return 0
end

local function isChromaticOctaveValue(octaveValue)
  return octaveValue == CHROMATIC_OCTAVE_UI_2 or octaveValue == CHROMATIC_OCTAVE_UI_3
end

local function noteVisibleInChromaticOctave(midiNote, octaveValue)
  if midiNote < CHROMATIC_MIN_NOTE or midiNote > CHROMATIC_MAX_NOTE then return false end
  if octaveValue == CHROMATIC_OCTAVE_UI_2 then return midiNote >= 36 and midiNote <= 59 end
  if octaveValue == CHROMATIC_OCTAVE_UI_3 then return midiNote >= 48 and midiNote <= 60 end
  return false
end

local function countNotesInChromaticOctave(notes, octaveValue)
  local count = 0
  for midiNote, _ in pairs(notes) do
    if noteVisibleInChromaticOctave(midiNote, octaveValue) then count = count + 1 end
  end
  return count
end

local function countNotesInOctaveWindow(notes, octaveValue)
  local base = octaveValue * 12
  local top = base + KEYBOARD_KEY_SPAN - 1
  local count = 0
  for midiNote, _ in pairs(notes) do
    if midiNote >= base and midiNote <= top then count = count + 1 end
  end
  return count
end

local function initHyperResoWhiteKeyMaps()
  HYPER_RESO_MIDI_TO_DEGREE = {}
  HYPER_RESO_DEGREE_TO_MIDI = {}
  HYPER_RESO_WHITE_MIDI_MIN = nil
  HYPER_RESO_WHITE_MIDI_MAX = nil

  local whites = {}
  for midi = 0, 127 do
    if isWhiteKeyPitch(midi) then whites[#whites + 1] = midi end
  end

  local anchorIndex = nil
  for i = 1, #whites do
    if whites[i] == HYPER_RESO_ANCHOR_MIDI then anchorIndex = i; break end
  end
  if not anchorIndex then return end

  for i = 1, #whites do
    -- Degrees skip 0: notes at or above anchor map to 1,2,3,…; notes below map to -1,-2,-3,…
    local offset = i - anchorIndex
    local degree = offset >= 0 and offset + 1 or offset
    if degree >= HYPER_RESO_NOTE_MIN and degree <= HYPER_RESO_NOTE_MAX then
      local midi = whites[i]
      HYPER_RESO_MIDI_TO_DEGREE[midi] = degree
      HYPER_RESO_DEGREE_TO_MIDI[degree] = midi
      if HYPER_RESO_WHITE_MIDI_MIN == nil then HYPER_RESO_WHITE_MIDI_MIN = midi end
      HYPER_RESO_WHITE_MIDI_MAX = midi
    end
  end
end

-- C-rooted span index: C3 span = 0 (degrees 1–7), C2 span = -1, etc.
local function hyperResoSpanIndexForDegree(degree)
  degree = tonumber(degree)
  if not degree or degree == 0 then return nil end
  if degree >= 1 then
    return math.floor((degree - 1) / HYPER_RESO_WHITE_KEYS_PER_OCTAVE)
  end
  return -math.ceil(-degree / HYPER_RESO_WHITE_KEYS_PER_OCTAVE)
end

local function hyperResoUiOctaveForDegree(degree)
  local span = hyperResoSpanIndexForDegree(degree)
  if span == nil then return nil end
  return span + HYPER_RESO_ANCHOR_UI_OCTAVE
end

local function hyperResoSpanStartDegree(spanIndex)
  if spanIndex >= 0 then return spanIndex * HYPER_RESO_WHITE_KEYS_PER_OCTAVE + 1 end
  return spanIndex * HYPER_RESO_WHITE_KEYS_PER_OCTAVE
end

local function hyperResoDegreeForSpanSlot(spanIndex, slot)
  local degree = hyperResoSpanStartDegree(spanIndex) + (slot - 1)
  if degree == 0 or degree < HYPER_RESO_NOTE_MIN or degree > HYPER_RESO_NOTE_MAX then
    return nil
  end
  return degree
end

local function hyperResoVisibleDegreeRange(uiOctave)
  local leftSpan = uiOctave - HYPER_RESO_ANCHOR_UI_OCTAVE
  local minDeg, maxDeg = nil, nil
  for _, spanIndex in ipairs({ leftSpan, leftSpan + 1 }) do
    for slot = 1, HYPER_RESO_WHITE_KEYS_PER_OCTAVE do
      local degree = hyperResoDegreeForSpanSlot(spanIndex, slot)
      if degree then
        if minDeg == nil or degree < minDeg then minDeg = degree end
        if maxDeg == nil or degree > maxDeg then maxDeg = degree end
      end
    end
  end
  return minDeg, maxDeg
end

local function bestOctaveForHeldHyperResoNotes(currentUiOctave)
  local degrees = notesForOctaveFollow()
  if next(degrees) == nil then return currentUiOctave end

  local maxHeld = nil
  for degree, _ in pairs(degrees) do
    if maxHeld == nil or degree > maxHeld then maxHeld = degree end
  end

  local uiOctave = currentUiOctave
  local _minVis, maxVis = hyperResoVisibleDegreeRange(uiOctave)
  while maxVis and maxHeld > maxVis and uiOctave < HYPER_RESO_OCTAVE_COUNT - 1 do
    uiOctave = uiOctave + 1
    _minVis, maxVis = hyperResoVisibleDegreeRange(uiOctave)
  end
  return uiOctave
end

local function clampHyperResoDegreeInput(note)
  local degree = hyperResoDegreeFromInput(note)
  if degree then return degree end
  return HYPER_RESO_NOTE_MIN
end

local function effectiveKeyboardNoteForUi(note)
  if isHyperResoKeyboard() then return hyperResoDegreeFromInput(note) end
  return note
end

local function isHyperResoOctaveValue(octaveValue)
  return octaveValue >= 0 and octaveValue < HYPER_RESO_OCTAVE_COUNT
end

notesForOctaveFollow = function()
  if not isHyperResoKeyboard() then return launchkeyHeldNotes end
  local degrees = {}
  for midiNote, _ in pairs(launchkeyHeldNotes) do
    local degree = hyperResoDegreeFromInput(midiNote)
    if degree then degrees[degree] = true end
  end
  return degrees
end

-- Pick octave grid value for held notes (Hyper-Reso: only scroll when out of range).
local function bestOctaveForHeldNotes(currentOctaveValue)
  if isHyperResoKeyboard() then return bestOctaveForHeldHyperResoNotes(currentOctaveValue) end

  local notes = notesForOctaveFollow()
  if next(notes) == nil then return currentOctaveValue end

  local octaveCandidates
  if keyboardChromaticAttached then
    octaveCandidates = { CHROMATIC_OCTAVE_UI_2, CHROMATIC_OCTAVE_UI_3 }
  else
    octaveCandidates = {}
    for octaveValue = 0, MAX_OCTAVE_GRID_VALUE do
      octaveCandidates[#octaveCandidates + 1] = octaveValue
    end
  end

  local bestOctave = currentOctaveValue
  local bestCount = keyboardChromaticAttached
    and countNotesInChromaticOctave(notes, currentOctaveValue)
    or countNotesInOctaveWindow(notes, currentOctaveValue)

  for i = 1, #octaveCandidates do
    local octaveValue = octaveCandidates[i]
    local count = keyboardChromaticAttached
      and countNotesInChromaticOctave(notes, octaveValue)
      or countNotesInOctaveWindow(notes, octaveValue)
    if count > bestCount then
      bestCount = count
      bestOctave = octaveValue
    end
  end
  return bestOctave
end

local function syncOctaveGridSelection(octaveValue)
  local keysGroup = root:findByName("keys_group", true)
  local octaveGrid = keysGroup and keysGroup:findByName("octave_grid", true)
  if not octaveGrid then return end
  setKeyboardHighlightingFlag(true)
  for i = 1, 10 do
    local child = octaveGrid.children[tostring(i)]
    if child and child.visible ~= false then
      child.values.x = ((i - 1) == octaveValue) and 1 or 0
    else
      child.values.x = 0
    end
  end
  setKeyboardHighlightingFlag(false)
end

local function selectOctave(octaveValue)
  syncOctaveGridSelection(octaveValue)
  local keysNode = root:findByName("keys", true)
  if keysNode then
    if isHyperResoKeyboard() then
      keysNode:notify("hyper_reso_octave", octaveValue)
    else
      keysNode:notify("octave", octaveValue)
    end
  end
  if pianoKeysMomentary() then
    refreshPianoKeysFromUiActive()
  else
    -- After the view shifts, re-highlight whichever key matches the currently selected
    -- note/degree. selectPianoKeyByNote sets all keys to 0 if no key matches (note not
    -- in view), which is the correct behaviour when manually scrolling away from it.
    local busNum = keyboardAttachedBus
    if busNum then
      local fxNum = getBusFxNum(busNum)
      if fxNum == FX_HYPER_RESO then
        local cc = getPerformControlCc(busNum, "note_fader")
        local degree = cc and hyperResoDegreeFromCc(cc)
        if degree then selectPianoKeyByNote(degree) end
      elseif fxNum == FX_RESONATOR then
        local cc = getPerformControlCc(busNum, "root_fader")
        if cc then selectPianoKeyByNote(cc) end
      end
    end
  end
end

local function refreshKeysNoteVisibility()
  local keysNode = root:findByName("keys", true)
  if not keysNode then return end
  local octaveValue = getCurrentOctaveValue()
  if isHyperResoKeyboard() then
    keysNode:notify("hyper_reso_octave", octaveValue)
  else
    keysNode:notify("octave", octaveValue)
  end
end

syncOctaveForHyperResoDegree = function(degree)
  if not keyboardIsAttached() or keyboardChromaticAttached then return end
  degree = hyperResoDegreeFromInput(degree) or clampHyperResoDegreeInput(degree)

  local currentOctave = getCurrentOctaveValue()
  local minVis, maxVis = hyperResoVisibleDegreeRange(currentOctave)

  -- Degree is already visible in the current two-span view: just refresh display.
  if minVis and maxVis and degree >= minVis and degree <= maxVis then
    refreshKeysNoteVisibility()
    return
  end

  local spanD = hyperResoSpanIndexForDegree(degree)
  if not spanD then return end

  local targetOctave
  if maxVis and degree > maxVis then
    -- Above the view: scroll up, placing degree in the right span (minimum scroll).
    targetOctave = clamp(spanD + HYPER_RESO_ANCHOR_UI_OCTAVE - 1, 0, HYPER_RESO_OCTAVE_COUNT - 1)
  else
    -- Below the view: scroll down, placing degree in the left span (minimum scroll).
    targetOctave = clamp(spanD + HYPER_RESO_ANCHOR_UI_OCTAVE, 0, HYPER_RESO_OCTAVE_COUNT - 1)
  end

  if targetOctave ~= currentOctave then
    selectOctave(targetOctave)
  else
    refreshKeysNoteVisibility()
  end
end

getPerformControlCc = function(busNum, controlName)
  local busGroup = getBusGroup(busNum)
  if not busGroup then return nil end

  local controlsInfo = getControlsInfoNode()
  local fxNum = getBusFxNum(busNum)
  local fxNode = controlsInfo and controlsInfo.children[tostring(fxNum)]
  if not fxNode then return nil end
  local controlInfo = json.toTable(fxNode.tag)
  if not controlInfo then return nil end

  local slotIndex = nil
  for index = 1, 6 do
    local control = controlInfo[index] or controlInfo[tostring(index)]
    if control and control[2] == controlName then slotIndex = index; break end
  end
  if not slotIndex then return nil end

  local faders = busGroup:findByName("faders", true)
  local faderGroup = faders and faders.children[tostring(slotIndex)]
  local control = faderGroup and faderGroup.children.control_fader
  if not control then return nil end
  return math.floor(control.values.x * 127 + 0.5)
end

local function refreshOctaveControlsForMode()
  local keysGroup = root:findByName("keys_group", true)
  if not keysGroup then return end
  local octaveGrid = keysGroup:findByName("octave_grid", true)
  local labelGrid = keysGroup:findByName("octave_label_grid", true)
  local chromatic = keyboardChromaticAttached
  local hyperReso = not chromatic and isHyperResoKeyboard()

  setKeyboardHighlightingFlag(true)
  for i = 1, 10 do
    local octaveValue = i - 1
    local show = true
    if chromatic then
      show = isChromaticOctaveValue(octaveValue)
    elseif hyperReso then
      show = isHyperResoOctaveValue(octaveValue)
    end
    local button = octaveGrid and octaveGrid.children[tostring(i)]
    if button then
      button.visible = show
      if not show then button.values.x = 0 end
    end
    local label = labelGrid and labelGrid.children[tostring(i)]
    if label then label.visible = show end
  end
  setKeyboardHighlightingFlag(false)

  if chromatic then
    local current = getCurrentOctaveValue()
    if not isChromaticOctaveValue(current) then
      selectOctave(CHROMATIC_OCTAVE_UI_2)
    else
      syncOctaveGridSelection(current)
      local keysNode = root:findByName("keys", true)
      if keysNode then keysNode:notify("octave", current) end
    end
  elseif hyperReso then
    local current = getCurrentOctaveValue()
    if not isHyperResoOctaveValue(current) then
      local busNum = keyboardAttachedBus
      local cc = busNum and getPerformControlCc(busNum, "note_fader")
      local degree = cc and hyperResoDegreeFromCc(cc)
      if degree then
        syncOctaveForHyperResoDegree(degree)
      else
        selectOctave(HYPER_RESO_ANCHOR_UI_OCTAVE)
      end
    else
      syncOctaveGridSelection(current)
      refreshKeysNoteVisibility()
    end
  end
end

local function syncKeysOctaveFromHeldMidiNotes()
  if not keyboardIsAttached() then return end
  local currentOctave = getCurrentOctaveValue()
  local octaveValue = bestOctaveForHeldNotes(currentOctave)
  if octaveValue == currentOctave then return end
  selectOctave(octaveValue)
  local visibleCount = keyboardChromaticAttached
    and countNotesInChromaticOctave(launchkeyHeldNotes, octaveValue)
    or countNotesInOctaveWindow(launchkeyHeldNotes, octaveValue)
  debugKeyboard(string.format(
    "syncKeysOctaveFromHeldMidiNotes: octave %d -> %d (held=%d visible)",
    currentOctave, octaveValue, visibleCount))
end

local function syncOctaveForMidiNote(midiNote)
  if not keyboardIsAttached() or keyboardChromaticAttached then return end
  if isHyperResoKeyboard() then
    syncOctaveForHyperResoDegree(midiNote)
    return
  end
  midiNote = tonumber(midiNote)
  if not midiNote then return end
  local octaveValue = 0
  for ov = 0, MAX_OCTAVE_GRID_VALUE do
    local base = ov * 12
    if midiNote >= base and midiNote <= base + KEYBOARD_KEY_SPAN - 1 then
      octaveValue = ov; break
    end
  end
  if octaveValue ~= getCurrentOctaveValue() then
    selectOctave(octaveValue)
  else
    refreshKeysNoteVisibility()
  end
end

local function findPerformControlDef(busNum, controlName)
  local fxNum = getBusFxNum(busNum)
  if fxNum == 0 then return nil, nil end
  local controlsInfo = getControlsInfoNode()
  local fxNode = controlsInfo and controlsInfo.children[tostring(fxNum)]
  if not fxNode then return nil, nil end
  local controlInfo = json.toTable(fxNode.tag)
  if not controlInfo then return nil, nil end
  for index = 1, 6 do
    local control = controlInfo[index] or controlInfo[tostring(index)]
    if control and control[2] == controlName then
      return index, tonumber(control[1])
    end
  end
  return nil, nil
end

-- Perform faders live in bus faders/1..6/control_fader; logical names are in controls_info.
local function getPerformControlFader(busNum, controlName)
  local busGroup = getBusGroup(busNum)
  if not busGroup then return nil end
  local slotIndex = findPerformControlDef(busNum, controlName)
  if not slotIndex then return nil end
  local faders = busGroup:findByName("faders", true)
  local faderGroup = faders and faders.children[tostring(slotIndex)]
  return faderGroup and faderGroup.children.control_fader
end

local function applyFaderCc(busNum, controlName, ccValue)
  local cc = clamp(math.floor(ccValue + 0.5), 0, 127)
  local _slotIndex, midiCc = findPerformControlDef(busNum, controlName)
  local control = getPerformControlFader(busNum, controlName)
  local ok = false
  if control then control:notify("new_cc_value", cc); ok = true end
  if midiCc then
    local midiChannel = busNum - 1
    sendMIDI({ MIDIMessageType.CONTROLCHANGE + midiChannel, midiCc, cc }, SP404_CONNECTION)
    ok = true
  end
  if ok then
    debugKeyboard(string.format("applyFaderCc: bus %d %s <- %d", busNum, controlName, cc))
  else
    debugKeyboard(string.format("applyFaderCc: missing %s on bus %d", controlName, busNum))
  end
  return ok
end

local function setGridIndex(busNum, gridName, index)
  local busGroup = getBusGroup(busNum)
  if busGroup then
    local grid = busGroup:findByName(gridName, true)
    if grid then grid:notify("new_index", index) end
  end
  local keysGroup = root:findByName("keys_group", true)
  if keysGroup and gridName ~= "scale_grid" then
    local grid = keysGroup:findByName(gridName, true)
    if grid then grid:notify("new_index", index) end
  end
end

local function indexFromDiscreteCcValues(ccValues, cc)
  cc = clamp(math.floor((cc or 0) + 0.5), 0, 127)
  for index = 1, #ccValues do
    if ccValues[index] == cc then return index end
  end
  for index = 1, #ccValues do
    local rangeStart = ccValues[index]
    local rangeEnd = ccValues[index + 1]
    if rangeEnd == nil then
      if cc >= rangeStart then return index end
    elseif cc >= rangeStart and cc < rangeEnd then
      return index
    end
  end
  return nil
end

local function hyperResoStateFromScaleIndex(scaleIndex)
  scaleIndex = tonumber(scaleIndex)
  if not scaleIndex then return 0, false end
  if scaleIndex >= 13 then return scaleIndex - 13, true end
  return scaleIndex - 1, false
end

local function getKeysGroupChordGrid()
  local keysGroup = root:findByName("keys_group", true)
  return keysGroup and keysGroup:findByName("chord_grid", true)
end

local function syncKeysGroupChordPadSelection(selectedPadIndex)
  selectedPadIndex = tonumber(selectedPadIndex)
  if not selectedPadIndex then return end
  local chordGrid = getKeysGroupChordGrid()
  if not chordGrid then return end
  setKeyboardHighlightingFlag(true)
  for padIndex = 1, 16 do
    local button = chordGrid.children[tostring(padIndex)]
    if button then button.values.x = (padIndex == selectedPadIndex) and 1 or 0 end
  end
  setKeyboardHighlightingFlag(false)
end

hyperResoDegreeFromCc = function(cc)
  local index = indexFromDiscreteCcValues(HYPER_RESO_NOTE_CC_VALUES, cc)
  if not index then return nil end
  return HYPER_RESO_DEGREES[index]
end

local function hyperResoDegreeToCc(degree)
  local index = degree < 0 and degree + 18 or degree + 17
  return HYPER_RESO_NOTE_CC_VALUES[index]
end

local function hyperResoScaleIndex(rootPc, isMinor)
  rootPc = clamp(math.floor(rootPc + 0.5), 0, 11)
  return isMinor and rootPc + 13 or rootPc + 1
end

local function getHyperResoBusState(busNum)
  local busGroup = getBusGroup(busNum)
  local tag = busGroup and json.toTable(busGroup.tag) or {}
  return tonumber(tag.hyperResoRoot) or 0, tag.hyperResoMinor == true
end

-- Chord grid pad index → Launchkey drum pad MIDI note.
-- Defined here (inside _initKeyboard scope) because launchkey_led.lua is compiled
-- after keyboard_manager.lua in the concatenated script, making its locals unavailable.
local LAUNCHKEY_CHORD_PAD_TO_NOTE = {
  [1]=40, [2]=41, [3]=42, [4]=43,
  [5]=48, [6]=49, [7]=50, [8]=51,
  [9]=36, [10]=37, [11]=38, [12]=39,
  [13]=44, [14]=45, [15]=46, [16]=47,
}

local function syncLaunchkeyHyperResoPadLeds(busNum)
  local rootPc, isMinor = getHyperResoBusState(busNum)
  for padIndex = 1, 16 do
    local role = HYPER_RESO_PAD_MAP[padIndex]
    local note = LAUNCHKEY_CHORD_PAD_TO_NOTE[padIndex]
    if note then
      if role == "unused" then
        sendLaunchkeyPadOff(note)
      else
        local on = (role == "major" and not isMinor)
          or (role == "minor" and isMinor)
          or (type(role) == "number" and role == rootPc)
        local colorIndex = launchkeyHyperResoPalette(role, on)
        sendLaunchkeyPadPalette(note, colorIndex)
      end
    end
  end
end

local function setHyperResoBusState(busNum, rootPc, isMinor)
  local busGroup = getBusGroup(busNum)
  if not busGroup then return end
  local tag = json.toTable(busGroup.tag) or {}
  tag.hyperResoRoot = clamp(math.floor(rootPc + 0.5), 0, 11)
  tag.hyperResoMinor = isMinor == true
  busGroup.tag = json.fromTable(tag)
end

local function applyHyperResoScale(busNum, rootPc, isMinor)
  setHyperResoBusState(busNum, rootPc, isMinor)
  local scaleIndex = hyperResoScaleIndex(rootPc, isMinor)
  local cc = HYPER_RESO_SCALE_CC_VALUES[scaleIndex]
  applyFaderCc(busNum, "scale_fader", cc)
  setGridIndex(busNum, "scale_grid", scaleIndex)
  debugKeyboard(string.format(
    "applyHyperResoScale: bus=%d root=%d minor=%s index=%d cc=%d",
    busNum, rootPc, tostring(isMinor), scaleIndex, cc))
  return true
end

local function getKeysGroupChordGridMode()
  local keysGroup = root:findByName("keys_group", true)
  if not keysGroup then return nil end
  local tag = json.toTable(keysGroup.tag) or {}
  return tag.chordGridMode
end

local function syncHyperResoScalePadUi(busNum)
  local keysGroup = root:findByName("keys_group", true)
  if not keysGroup or getKeysGroupChordGridMode() ~= CHORD_GRID_MODE_HYPER_RESO then return end
  local rootPc, isMinor = getHyperResoBusState(busNum)
  setKeyboardHighlightingFlag(true)
  local chordGrid = keysGroup:findByName("chord_grid", true)
  local labelGrid = keysGroup:findByName("chord_label_grid", true)
  for padIndex = 1, 16 do
    local role = HYPER_RESO_PAD_MAP[padIndex]
    local label = labelGrid and labelGrid.children[tostring(padIndex)]
    if label then label.values.text = HYPER_RESO_PAD_LABELS[padIndex] or "" end
    local button = chordGrid and chordGrid.children[tostring(padIndex)]
    if button then
      if role == "unused" then
        button.visible = false
        button.values.x = 0
      else
        button.visible = true
        local on = (role == "major" and not isMinor)
          or (role == "minor" and isMinor)
          or (type(role) == "number" and role == rootPc)
        button.values.x = on and 1 or 0
        local padColor = hyperResoPadColor(role)
        if padColor then button.color = padColor end
      end
    end
  end
  setKeyboardHighlightingFlag(false)
  -- Sync Launchkey pad LEDs if keyboard is attached.
  if keyboardIsAttached() then
    syncLaunchkeyHyperResoPadLeds(busNum)
  end
end

local function ensureHyperResoScaleDefaults(busNum)
  local busGroup = getBusGroup(busNum)
  if not busGroup then return end
  local tag = json.toTable(busGroup.tag) or {}
  if tag.hyperResoRoot ~= nil then return end
  local cc = getPerformControlCc(busNum, "scale_fader")
  local scaleIndex = cc and indexFromDiscreteCcValues(HYPER_RESO_SCALE_CC_VALUES, cc)
  if scaleIndex then
    local rootPc, isMinor = hyperResoStateFromScaleIndex(scaleIndex)
    setHyperResoBusState(busNum, rootPc, isMinor)
  else
    setHyperResoBusState(busNum, 0, false)
    applyHyperResoScale(busNum, 0, false)
  end
end

local function syncHyperResoScaleFromPerformFader(busNum)
  local cc = getPerformControlCc(busNum, "scale_fader")
  if cc ~= nil then
    local scaleIndex = indexFromDiscreteCcValues(HYPER_RESO_SCALE_CC_VALUES, cc)
    if scaleIndex then
      local rootPc, isMinor = hyperResoStateFromScaleIndex(scaleIndex)
      setHyperResoBusState(busNum, rootPc, isMinor)
    end
  else
    ensureHyperResoScaleDefaults(busNum)
    return
  end
  syncHyperResoScalePadUi(busNum)
end

-- Resonator pad colors by harmonic quality (pads 1-4 = perfect, 5-10 = minor, 11-16 = major).
local function resonatorPadColor(padIndex)
  if padIndex <= 4 then
    return Color.fromHexString("FFFFFFFF")   -- white (perfect intervals)
  elseif padIndex <= 10 then
    return Color.fromHexString("0066FFFF")   -- blue (minor)
  else
    return Color.fromHexString("FFB300FF")   -- gold (major)
  end
end

local function syncChordPadLabelsUi(busNum)
  -- Labels defined here since they're only needed in this function.
  local RESONATOR_CHORD_LABELS = {
    "Root", "Oct", "UpDn", "P5",
    "m3", "m5", "m7", "m7oct",
    "m9", "m11", "M3", "M5",
    "M7", "M7oct", "M9", "M11",
  }
  local VOCODER_CHORD_LABELS = {
    "Root", "P5", "Oct", "UpDn", "UpDnP5", "3rd", "5thUp", "5thDn", "7thUp", "7thDn",
  }
  local keysGroup = root:findByName("keys_group", true)
  if not keysGroup then return end
  local fxNum = getBusFxNum(busNum)
  local labels = (fxNum == FX_RESONATOR) and RESONATOR_CHORD_LABELS
    or (fxNum == FX_VOCODER and VOCODER_CHORD_LABELS)
  local chordGrid = keysGroup:findByName("chord_grid", true)
  local labelGrid = keysGroup:findByName("chord_label_grid", true)

  setKeyboardHighlightingFlag(true)
  for padIndex = 1, 16 do
    local button = chordGrid and chordGrid.children[tostring(padIndex)]
    if button then
      button.visible = true
      -- Set per-pad color for Resonator; reset to bus accent for others.
      if fxNum == FX_RESONATOR then
        button.color = resonatorPadColor(padIndex)
      else
        button.color = Color.fromHexString(getBusAccentHex(busNum))
      end
    end
    local label = labelGrid and labelGrid.children[tostring(padIndex)]
    if label then
      label.values.text = (labels and labels[padIndex]) or tostring(padIndex)
    end
  end
  if chordGrid then chordGrid.tag = "1" end

  -- Sync current pad selection from perform fader.
  local controlName = "chord_fader"
  local cc = getPerformControlCc(busNum, controlName)
  if cc ~= nil then
    local padIndex = fxNum == FX_RESONATOR
      and indexFromDiscreteCcValues(RESONATOR_CHORD_VALUES, cc)
      or indexFromDiscreteCcValues(VOCODER_HARMONY_VALUES, cc)
    if padIndex then syncKeysGroupChordPadSelection(padIndex) end
  end
  setKeyboardHighlightingFlag(false)
end

local function updateKeysGroupChordGridMode()
  local keysGroup = root:findByName("keys_group", true)
  if not keysGroup then return end
  local tag = json.toTable(keysGroup.tag) or {}
  if keyboardChromaticAttached or keyboardSoundGenAttached or not keyboardIsAttached() or isVocoderLive() then
    tag.chordGridMode = nil
  elseif getBusFxNum(keyboardAttachedBus) == FX_HYPER_RESO then
    tag.chordGridMode = CHORD_GRID_MODE_HYPER_RESO
  else
    tag.chordGridMode = CHORD_GRID_MODE_CHORD_PADS
  end
  keysGroup.tag = json.fromTable(tag)
end

local function syncKeysGroupChordPadUi(busNum)
  if not busNum then return end
  local mode = getKeysGroupChordGridMode()
  if mode == CHORD_GRID_MODE_HYPER_RESO then
    local keysGroup = root:findByName("keys_group", true)
    local chordGrid = keysGroup and keysGroup:findByName("chord_grid", true)
    if chordGrid then chordGrid.tag = "0" end
    syncHyperResoScaleFromPerformFader(busNum)
  elseif mode == CHORD_GRID_MODE_CHORD_PADS then
    syncChordPadLabelsUi(busNum)
  end
end

local function applyChordPad(busNum, fxNum, padIndex)
  if fxNum == FX_RESONATOR then
    if padIndex > #RESONATOR_CHORD_VALUES then return false end
    applyFaderCc(busNum, "chord_fader", RESONATOR_CHORD_VALUES[padIndex])
    setGridIndex(busNum, "chord_grid", padIndex)
    syncKeysGroupChordPadSelection(padIndex)
    return true
  elseif fxNum == FX_VOCODER then
    if padIndex > #VOCODER_HARMONY_VALUES then return false end
    applyFaderCc(busNum, "chord_fader", VOCODER_HARMONY_VALUES[padIndex])
    setGridIndex(busNum, "chord_grid", padIndex)
    syncKeysGroupChordPadSelection(padIndex)
    return true
  end
  return false
end

local function handleHyperResoScalePad(busNum, padIndex, pressed)
  if not pressed then syncHyperResoScalePadUi(busNum); return true end
  local role = HYPER_RESO_PAD_MAP[padIndex]
  if role == "unused" or role == nil then return false end
  local rootPc, isMinor = getHyperResoBusState(busNum)
  if role == "major" then
    applyHyperResoScale(busNum, rootPc, false)
  elseif role == "minor" then
    applyHyperResoScale(busNum, rootPc, true)
  else
    applyHyperResoScale(busNum, role, isMinor)
  end
  syncHyperResoScalePadUi(busNum)
  return true
end

local function handleChordPadPress(padIndex, pressed)
  padIndex = tonumber(padIndex)
  if not padIndex then return false end
  local busNum = keyboardAttachedBus
  if not busNum then return false end
  local mode = getKeysGroupChordGridMode()
  if mode == CHORD_GRID_MODE_HYPER_RESO then
    return handleHyperResoScalePad(busNum, padIndex, pressed == true)
  end
  if pressed and mode == CHORD_GRID_MODE_CHORD_PADS then
    return applyChordPad(busNum, getBusFxNum(busNum), padIndex)
  end
  return false
end

syncKeyboardNoteFromPerformFaders = function(busNum)
  if keyboardChromaticAttached or keyboardAttachedBus ~= busNum then return end
  local fxNum = getBusFxNum(busNum)
  if fxNum == FX_RESONATOR then
    local cc = getPerformControlCc(busNum, "root_fader")
    if cc == nil then return end
    syncOctaveForMidiNote(cc)
    selectPianoKeyByNote(cc)
  elseif fxNum == FX_HYPER_RESO then
    local cc = getPerformControlCc(busNum, "note_fader")
    if cc == nil then return end
    local degree = hyperResoDegreeFromCc(cc)
    if not degree then return end
    syncOctaveForHyperResoDegree(degree)
    selectPianoKeyByNote(degree)
  end
end

local function onPerformFaderCc(busNum, controlName, ccValue)
  busNum = tonumber(busNum)
  ccValue = tonumber(ccValue)
  if not busNum or not controlName or ccValue == nil then return end
  if keyboardChromaticAttached or keyboardAttachedBus ~= busNum then return end

  local fxNum = getBusFxNum(busNum)
  if controlName == "scale_fader" and fxNum == FX_HYPER_RESO then
    local scaleIndex = indexFromDiscreteCcValues(HYPER_RESO_SCALE_CC_VALUES, ccValue)
    if scaleIndex then
      local rootPc, isMinor = hyperResoStateFromScaleIndex(scaleIndex)
      setHyperResoBusState(busNum, rootPc, isMinor)
      syncHyperResoScalePadUi(busNum)
    end
  elseif controlName == "chord_fader" then
    if fxNum == FX_RESONATOR then
      local padIndex = indexFromDiscreteCcValues(RESONATOR_CHORD_VALUES, ccValue)
      if padIndex then syncKeysGroupChordPadSelection(padIndex) end
    elseif fxNum == FX_VOCODER then
      local padIndex = indexFromDiscreteCcValues(VOCODER_HARMONY_VALUES, ccValue)
      if padIndex then syncKeysGroupChordPadSelection(padIndex) end
    end
  elseif controlName == "root_fader" and fxNum == FX_RESONATOR then
    syncKeyboardNoteFromPerformFaders(busNum)
  elseif controlName == "note_fader" and fxNum == FX_HYPER_RESO then
    syncKeyboardNoteFromPerformFaders(busNum)
  end
end

local function setTuningFromNote(busNum, fxNum, note)
  note = tonumber(note)
  if note == nil then return false end

  if fxNum == FX_HYPER_RESO then
    local degree = hyperResoDegreeFromInput(note)
    if not degree then return false end
    if applyFaderCc(busNum, "note_fader", hyperResoDegreeToCc(degree)) then
      syncOctaveForHyperResoDegree(degree)
      selectPianoKeyByNote(degree)
      return true
    end
    return false
  end

  local noteValue = clamp(note, 0, 127)
  local noteClass = noteValue % 12

  if fxNum == FX_RESONATOR then
    if applyFaderCc(busNum, "root_fader", noteValue) then
      syncOctaveForMidiNote(noteValue)
      return true
    end
    return false
  end
  return false
end

local function applyKeysGroupChordPadButtonMode()
  local chordGrid = getKeysGroupChordGrid()
  if not chordGrid then return end
  local mode = getKeysGroupChordGridMode()
  if mode ~= CHORD_GRID_MODE_CHORD_PADS and mode ~= CHORD_GRID_MODE_HYPER_RESO then return end
  setKeyboardHighlightingFlag(true)
  for padIndex = 1, 16 do
    local button = chordGrid.children[tostring(padIndex)]
    if button then
      button.properties.buttonType = ButtonType.TOGGLE_PRESS
      button.properties.press = true
      button.properties.release = false
    end
  end
  setKeyboardHighlightingFlag(false)
end

local function applyPianoKeyPressMode()
  local _keysNode, keysList = getPianoKeysList()
  if not keysList then return end
  setKeyboardHighlightingFlag(true)
  for i = 1, #keysList do
    local key = keysList[i]
    if isVocoderLive() then
      -- Latch: toggle on press, no release event. Note-off fires when lit key is pressed
      -- (x→0, velocity=0) since pianoKeysMomentary() is true for Vocoder.
      key.properties.buttonType = ButtonType.TOGGLE_PRESS
      key.properties.press = true
      key.properties.release = false
    elseif pianoKeysMomentary() then
      -- Momentary: note plays while key is held (Chromatic, Sound Gen).
      key.properties.buttonType = ButtonType.MOMENTARY
      key.properties.press = true
      key.properties.release = true
    else
      -- Toggle: select a single key for tuning (Resonator, Hyper Reso).
      key.properties.buttonType = ButtonType.TOGGLE_PRESS
      key.properties.press = true
      key.properties.release = false
    end
    key.values.x = 0
  end
  setKeyboardHighlightingFlag(false)
end

local function updateKeyboardRootTag()
  local tag = json.toTable(root.tag) or {}
  tag.keyboardAttachedBus = keyboardAttachedBus
  tag.keyboardChromaticAttached = keyboardChromaticAttached
  tag.keyboardSoundGenAttached = keyboardSoundGenAttached
  tag.keyboardKeysMomentary = pianoKeysMomentary()
  tag.keyboardSustainDown = keyboardSustainDown
  local busNum = keyboardAttachedBus
  local fxNum = busNum and getBusFxNum(busNum) or 0
  tag.keyboardHyperResoWhiteKeys = (not keyboardChromaticAttached and fxNum == FX_HYPER_RESO) or nil
  tag.keyboardNoteRangeMin = nil
  tag.keyboardNoteRangeMax = nil
  root.tag = json.fromTable(tag)
end

local function refreshChromaticButton()
  local button = root:findByName("chromatic_keyboard_button", true)
  local label = root:findByName("chromatic_keyboard_label", true)
  if button then
    local want = keyboardChromaticAttached and 1 or 0
    if button.values.x ~= want then
      setKeyboardHighlightingFlag(true)
      button.values.x = want
      setKeyboardHighlightingFlag(false)
    end
    button.visible = true
  end
  if label then label.visible = true end
end

local function refreshSoundGenButton()
  local button = root:findByName("soundgen_keyboard_button", true)
  local label = root:findByName("soundgen_keyboard_label", true)
  if button then
    local want = keyboardSoundGenAttached and 1 or 0
    if button.values.x ~= want then
      setKeyboardHighlightingFlag(true)
      button.values.x = want
      setKeyboardHighlightingFlag(false)
    end
    button.visible = true
  end
  if label then label.visible = true end
end

local function refreshKeysGroupChordVisibility()
  local keysGroup = root:findByName("keys_group", true)
  if not keysGroup then return end
  local showChords = keyboardIsAttached()
    and not keyboardChromaticAttached
    and not keyboardSoundGenAttached
    and not isVocoderLive()
  for _, gridName in ipairs({ "chord_grid", "chord_label_grid" }) do
    local grid = keysGroup:findByName(gridName, true)
    if grid then grid.visible = showChords end
  end
  if showChords and keyboardAttachedBus then
    syncKeysGroupChordPadUi(keyboardAttachedBus)
  end
end

local function refreshKeysGroupVisibility()
  local keysGroup = root:findByName("keys_group", true)
  if keysGroup then keysGroup.visible = keyboardIsAttached() end
  refreshKeysGroupChordVisibility()
end

local function refreshKeysGroupTheme()
  local keysGroup = root:findByName("keys_group", true)
  if not keysGroup or not keyboardIsAttached() then return end
  if keyboardSoundGenAttached then
    keysGroup.color = Color.fromHexString(SOUNDGEN_KEYS_HEX)
  elseif keyboardChromaticAttached then
    local chromaticButton = root:findByName("chromatic_keyboard_button", true)
    keysGroup.color = (chromaticButton and chromaticButton.color)
      or Color.fromHexString(CHROMATIC_KEYS_FALLBACK_HEX)
  else
    keysGroup.color = Color.fromHexString(getBusAccentHex(keyboardAttachedBus))
  end
  local panicButton = keysGroup:findByName("panic_button", true)
  if panicButton then panicButton.color = Color.fromHexString("FF4500FF") end
end

local function refreshKeyboardGrabButtons()
  for busNum = 1, 5 do
    local busGroup = getBusGroup(busNum)
    local controlGroup = busGroup and busGroup:findByName("control_group", true)
    local button = controlGroup and controlGroup:findByName("keyboard_grab_button", true)
    local label = controlGroup and controlGroup:findByName("keyboard_grab_label", true)
    local fxNum = getBusFxNum(busNum)
    local supported = fxSupportsKeyboard(fxNum, busNum)
    if button then
      button.visible = supported
      button.values.x = (supported and keyboardAttachedBus == busNum) and 1 or 0
      if supported then button.color = Color.fromHexString(getBusAccentHex(busNum)) end
    end
    if label then
      label.visible = supported
      if supported then
        label.textColor = Color.fromHexString(
          keyboardAttachedBus == busNum and "000000FF" or getBusAccentHex(busNum))
      end
    end
  end
end

local function refreshKeyboardUi()
  refreshChromaticButton()
  refreshSoundGenButton()
  updateKeysGroupChordGridMode()
  refreshKeysGroupVisibility()
  refreshKeyboardGrabButtons()
  refreshKeysGroupTheme()
  refreshOctaveControlsForMode()
  applyPianoKeyPressMode()
  applyKeysGroupChordPadButtonMode()
  updateKeyboardRootTag()
  refreshKeysNoteVisibility()
  local busNum = keyboardAttachedBus
  if busNum and keyboardIsAttached() and not keyboardChromaticAttached and not keyboardSoundGenAttached then
    syncKeysGroupChordPadUi(busNum)
    syncKeyboardNoteFromPerformFaders(busNum)
  end
  -- Clear Launchkey pad LEDs when not in Hyper Reso keyboard mode.
  if getKeysGroupChordGridMode() ~= CHORD_GRID_MODE_HYPER_RESO then
    clearLaunchkeyPadLeds()
  end
end

local function detachChromatic()
  if not keyboardChromaticAttached then return end
  flushTrackedNotes("detach_chromatic")
  keyboardChromaticAttached = false
  onSustainChanged(false)
  refreshKeyboardUi()
end

local function setChromaticAttached()
  if keyboardChromaticAttached then return end
  flushTrackedNotes("attach_chromatic")
  keyboardAttachedBus = nil
  keyboardSoundGenAttached = false
  keyboardChromaticAttached = true
  onSustainChanged(false)
  refreshKeyboardUi()
end

local function detachSoundGen()
  if not keyboardSoundGenAttached then return end
  flushTrackedNotes("detach_soundgen")
  keyboardSoundGenAttached = false
  onSustainChanged(false)
  refreshKeyboardUi()
end

local function setSoundGenAttached()
  if keyboardSoundGenAttached then return end
  flushTrackedNotes("attach_soundgen")
  keyboardAttachedBus = nil
  keyboardChromaticAttached = false
  keyboardSoundGenAttached = true
  onSustainChanged(false)
  refreshKeyboardUi()
end

local function setAttachedBus(busNum)
  local fxNum = getBusFxNum(busNum)
  if not fxSupportsKeyboard(fxNum, busNum) then
    debugKeyboard(string.format("setAttachedBus: bus %d fx %d does not support keyboard", busNum, fxNum))
    return
  end
  if keyboardAttachedBus == busNum and not keyboardChromaticAttached and not keyboardSoundGenAttached then
    refreshKeyboardUi(); return
  end
  flushTrackedNotes("switch_bus")
  keyboardChromaticAttached = false
  keyboardSoundGenAttached = false
  keyboardAttachedBus = busNum
  onSustainChanged(false)
  updateKeysGroupChordGridMode()
  refreshKeyboardUi()
end

local function onBusFxChanged(busNum)
  busNum = tonumber(busNum)
  if not busNum then return end
  local fxNum = getBusFxNum(busNum)
  if keyboardAttachedBus == busNum and not fxSupportsKeyboard(fxNum, busNum) then
    flushTrackedNotes("fx_unsupported")
    keyboardAttachedBus = nil
    onSustainChanged(false)
    debugKeyboard(string.format("onBusFxChanged: detached bus %d (fx %d)", busNum, fxNum))
  end
  refreshKeyboardUi()
end

local function detachBusIfCurrent(busNum)
  if keyboardAttachedBus ~= busNum then return end
  flushTrackedNotes("detach_bus")
  keyboardAttachedBus = nil
  onSustainChanged(false)
  refreshKeyboardUi()
end

local function routeKeyboardNote(note, velocity)
  note = tonumber(note)
  if note == nil then return false end

  if keyboardChromaticAttached then
    local uiNote = clamp(note, 0, 127)
    local chromaticNote = clamp(uiNote, 36, 60)
    debugKeyboard(string.format(
      "routeKeyboardNote: chromatic note=%s vel=%s -> %d",
      tostring(note), tostring(velocity), chromaticNote))
    return sendRoutedNote(SP404_CHROMATIC_CHANNEL, chromaticNote, velocity, uiNote)
  end

  if keyboardSoundGenAttached then
    local uiNote = clamp(note, 0, 127)
    debugKeyboard(string.format(
      "routeKeyboardNote: soundgen note=%s vel=%s -> %d",
      tostring(note), tostring(velocity), uiNote))
    return sendRoutedNote(SP404_CHROMATIC_CHANNEL, uiNote, velocity, uiNote)
  end

  local busNum = keyboardAttachedBus
  if not busNum then
    debugKeyboard(string.format(
      "routeKeyboardNote: ignored note=%s vel=%s (not attached)", tostring(note), tostring(velocity)))
    return false
  end

  local fxNum = getBusFxNum(busNum)
  debugKeyboard(string.format(
    "routeKeyboardNote: bus=%d fx=%d note=%s vel=%s",
    busNum, fxNum, tostring(note), tostring(velocity)))

  if vocoderLiveActive(busNum, fxNum) then
    local uiNote = clamp(note, 0, 127)
    return sendRoutedNote(SP404_VOCODER_CHANNEL, uiNote, velocity, uiNote)
  end

  if velocity > 0 and fxNum ~= 0 and supportsKeyboardNoteTuning(fxNum) then
    if fxNum == FX_HYPER_RESO then
      if not isHyperResoDegree(note) and not isWhiteKeyPitch(note) then
        debugKeyboard(string.format("routeKeyboardNote: hyper-reso ignored black key %d", note))
        return false
      end
      local degree = hyperResoDegreeFromInput(note)
      if not degree then return false end
      if setTuningFromNote(busNum, fxNum, degree) then
        debugKeyboard(string.format("routeKeyboardNote: hyper-reso degree %d", degree))
        return true
      end
    elseif setTuningFromNote(busNum, fxNum, clamp(note, 0, 127)) then
      debugKeyboard(string.format(
        "routeKeyboardNote: setTuningFromNote ok fx=%d note=%d", fxNum, note))
      return true
    end
    debugKeyboard(string.format("routeKeyboardNote: setTuningFromNote failed fx=%d", fxNum))
  end

  debugKeyboard(velocity == 0
    and "routeKeyboardNote: note-off (no action for current mode)"
    or "routeKeyboardNote: no route applied")
  return false
end

local function updatePolyphonicKeyHighlight(note, velocity, routed)
  if not pianoKeysMomentary() or note == nil then return end
  if velocity > 0 then
    setPianoKeyHighlight(note, routed == true)
  else
    refreshPianoKeysFromUiActive()
  end
end

local function routePadNote(note, velocity)
  if velocity == 0 then return end
  local busNum = keyboardAttachedBus
  if not busNum then return end
  -- Pad note map defined here; only used in this function.
  local PAD_NOTE_TO_INDEX = {
    [36] = 9, [37] = 10, [38] = 11, [39] = 12,
    [44] = 13, [45] = 14, [46] = 15, [47] = 16,
    [40] = 1, [41] = 2, [42] = 3, [43] = 4,
    [48] = 5, [49] = 6, [50] = 7, [51] = 8,
  }
  local padIndex = PAD_NOTE_TO_INDEX[note]
  if not padIndex then
    debugKeyboard(string.format("routePadNote: unmapped drum pad note %d", note))
    return
  end
  debugKeyboard(string.format(
    "routePadNote: note=%d -> pad %d fx=%d mode=%s",
    note, padIndex, getBusFxNum(busNum), tostring(getKeysGroupChordGridMode())))
  handleChordPadPress(padIndex, true)
end

-- Public entry points — assigned as globals so root.lua can call them by name.

function handleKeyboardMidi(message, connections)
  if not midiFromLaunchkeyKeyboard(connections) then return false end
  if not keyboardIsAttached() then return false end

  local status = message[1]
  local data1 = message[2]
  local data2 = message[3]
  local msgType, channel = parseStatus(status)

  if msgType == MIDIMessageType.NOTE_ON or msgType == MIDIMessageType.NOTE_OFF then
    local note = data1
    local velocity = noteVelocityFromMidi(msgType, data2)
    if isLaunchkeyPadsChannel(channel) then
      routePadNote(note, velocity)
      return true
    else
      if isHyperResoKeyboard() and not isWhiteKeyPitch(note) then return true end
      if velocity > 0 then launchkeyHeldNotes[note] = true
      else launchkeyHeldNotes[note] = nil end
      local routed = routeKeyboardNote(note, velocity)
      local uiNote = effectiveKeyboardNoteForUi(note)
      syncKeysOctaveFromHeldMidiNotes()
      if pianoKeysMomentary() then
        updatePolyphonicKeyHighlight(uiNote, velocity, routed)
      elseif velocity > 0 then
        selectPianoKeyByNote(uiNote)
      end
      return true
    end
  end

  if msgType == MIDIMessageType.CONTROLCHANGE
    and data1 == SUSTAIN_PEDAL_CC
    and not isLaunchkeyPadsChannel(channel) then
    onSustainChanged(data2 >= 64)
    updateKeyboardRootTag()
    return true
  end

  if msgType == MIDIMessageType.PITCH_BEND then
    if keyboardChromaticAttached then return false end
    local busNum = keyboardAttachedBus
    if busNum and vocoderLiveActive(busNum, getBusFxNum(busNum)) then
      sendMIDI({ MIDIMessageType.PITCH_BEND + SP404_VOCODER_CHANNEL, data1, data2 }, SP404_CONNECTION)
      return true
    end
    return false
  end

  return false
end

function handleKeyboardNotify(key, value)
  if key == "keyboard_attach_bus" then
    setAttachedBus(tonumber(value) or 1)
  elseif key == "keyboard_detach_bus" then
    detachBusIfCurrent(tonumber(value) or -1)
  elseif key == "keyboard_attach_chromatic" then
    if parseNotifyBool(value) then setChromaticAttached() end
  elseif key == "keyboard_detach_chromatic" then
    detachChromatic()
  elseif key == "keyboard_attach_soundgen" then
    if parseNotifyBool(value) then setSoundGenAttached() end
  elseif key == "keyboard_detach_soundgen" then
    detachSoundGen()
  elseif key == "keyboard_bus_fx_changed" then
    onBusFxChanged(value)
  elseif key == "keyboard_panic" then
    flushTrackedNotes("panic_button")
    onSustainChanged(false)
    updateKeyboardRootTag()
  elseif key == "keyboard_refresh_ui" then
    refreshKeyboardUi()
  elseif key == "keyboard_octave_select" then
    local octaveValue = tonumber(value)
    if octaveValue == nil then return true end
    if keyboardChromaticAttached and not isChromaticOctaveValue(octaveValue) then return true end
    if isHyperResoKeyboard() and not isHyperResoOctaveValue(octaveValue) then return true end
    selectOctave(octaveValue)
  elseif key == "keyboard_ui_note" then
    local note, velocity
    if type(value) == "table" then
      note = tonumber(value[1]); velocity = tonumber(value[2]) or 0
    else
      note = tonumber(value); velocity = 127
    end
    debugKeyboard(string.format(
      "keyboard_ui_note: note=%s vel=%s attachedBus=%s",
      tostring(note), tostring(velocity), tostring(keyboardAttachedBus)))
    if note then
      local routed = routeKeyboardNote(note, velocity)
      updatePolyphonicKeyHighlight(effectiveKeyboardNoteForUi(note), velocity, routed)
    end
  elseif key == "keyboard_key_select" then
    local note, velocity
    if type(value) == "table" then
      note = tonumber(value[1]); velocity = tonumber(value[2]) or 0
    else
      note = tonumber(value); velocity = 127
    end
    debugKeyboard(string.format("keyboard_key_select: note=%s vel=%s", tostring(note), tostring(velocity)))
    if note then
      local routed = routeKeyboardNote(note, velocity)
      local uiNote = effectiveKeyboardNoteForUi(note)
      if pianoKeysMomentary() then
        updatePolyphonicKeyHighlight(uiNote, velocity, routed)
      elseif velocity > 0 and routed then
        selectPianoKeyByNote(uiNote)
      end
    end
  elseif key == "keyboard_ui_chord_pad" then
    local padIndex = tonumber(value)
    if padIndex then handleChordPadPress(padIndex, true) end
  elseif key == "keyboard_chord_pad" then
    local padIndex, pressed
    if type(value) == "table" then
      padIndex = tonumber(value[1]); pressed = value[2] == true or value[2] == 1
    else
      padIndex = tonumber(value); pressed = true
    end
    if padIndex then handleChordPadPress(padIndex, pressed) end
  elseif key == "keyboard_perform_cc" then
    if type(value) == "table" then onPerformFaderCc(value[1], value[2], value[3]) end
  else
    return false
  end
  return true
end

function initKeyboardManager()
  initHyperResoWhiteKeyMaps()
  local tag = json.toTable(root.tag) or {}
  keyboardAttachedBus = tonumber(tag.keyboardAttachedBus)
  keyboardChromaticAttached = tag.keyboardChromaticAttached == true
    or (tag.keyboardChromaticEnabled == true and keyboardAttachedBus == nil)
  keyboardSoundGenAttached = tag.keyboardSoundGenAttached == true
  keyboardSustainDown = false
  activeNotes = {}
  deferredNoteOffs = {}
  activeNoteQueue = {}
  clearUiActiveNotes()
  activeNoteUi = {}
  launchkeyHeldNotes = {}
  -- Enforce mutual exclusivity.
  if keyboardAttachedBus and (keyboardChromaticAttached or keyboardSoundGenAttached) then
    keyboardChromaticAttached = false
    keyboardSoundGenAttached = false
  end
  if keyboardChromaticAttached and keyboardSoundGenAttached then
    keyboardSoundGenAttached = false
  end
  if keyboardAttachedBus then
    if not fxSupportsKeyboard(getBusFxNum(keyboardAttachedBus), keyboardAttachedBus) then
      keyboardAttachedBus = nil
    end
  end
  refreshKeyboardUi()
end

end
_initKeyboard()
