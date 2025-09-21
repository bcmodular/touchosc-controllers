local effects = {
  "Filter + Drive", "Resonator", "Sync Delay", "Isolator", "DJFX Looper", "Scatter",
  "Downer", "Ha-Dou", "Ko-Da-Ma", "Zan-Zou", "To-Gu-Ro", "SBF",
  "Stopper", "Tape Echo", "TimeCtrlDly", "Super Filter", "WrmSaturator", "303 VinylSim",
  "404 VinylSim", "Cassette Sim", "Lo-fi", "Reverb", "Chorus", "JUNO Chorus",
  "Flanger", "Phaser", "Wah", "Slicer", "Tremolo/Pan", "Chromatic PS",
  "Hyper-Reso", "Ring Mod", "Crusher", "Overdrive", "Distortion", "Equalizer",
  "Compressor", "SX Reverb", "SX Delay", "Cloud Delay", "Back Spin", "DJFX Delay",
  "Auto Pitch", "Vocoder", "Harmony", "Gt Amp Sim"
}

local allMidiValues = {
  {1, 10, 0}, {2, 17, 0}, {3, 23, 0}, {4, 8, 0}, {5, 35, 0},
  {6, 36, 0}, {7, 5, 10}, {8, 21, 0}, {9, 25, 0}, {10, 22, 0},
  {11, 34, 0}, {12, 16, 0}, {13, 0, 0}, {14, 26, 0}, {15, 24, 8},
  {16, 9, 0}, {17, 11, 11}, {18, 1, 12}, {19, 2, 13}, {20, 3, 14},
  {21, 4, 15}, {22, 20, 7}, {23, 27, 5}, {24, 28, 6}, {25, 29, 0},
  {26, 30, 0}, {27, 31, 0}, {28, 32, 0}, {29, 33, 0}, {30, 19, 9},
  {31, 18, 0}, {32, 15, 0}, {33, 14, 0}, {34, 12, 0}, {35, 13, 0},
  {36, 7, 16}, {37, 6, 17}, {38, 37, 0}, {39, 38, 0}, {40, 39, 0},
  {41, 0, 0}, {42, 40, 0}, {0, 0, 1}, {0, 0, 2}, {0, 0, 3}, {0, 0, 4}
}

local busNum = 1
local midiIndex = 1

local buttonScript = [[
function onValueChanged(key, value)
  if key == 'x' and self.values.x == 0 then
    self.parent:notify('set_fx', {self.tag, self.name})
  end
end
]]

local function setupUI()
  busNum = tonumber(self.tag) or 1

  if busNum == 1 or busNum == 2 then
    midiIndex = 1
  elseif busNum == 3 or busNum == 4 then
    midiIndex = 2
  else
    midiIndex = 3
  end

  local labelGroup = self.parent:findByName('fx_selector_label_group')

  for i = 1, #effects do
    local label = labelGroup:findByName(tostring(i))
    local button = self:findByName(effects[i])
    label.values.text = effects[i]
    label.color = Color.fromHexString("00000000")
    label.textColor = Color.fromHexString("000000FF")
    button.color = Color.fromHexString("8D8D8AFF")
    button.tag = i
    button.name = effects[i]

    if allMidiValues[i][midiIndex] ~= 0 then
      button.color = Color.fromHexString("F79000FF")
      label.textColor = Color.fromHexString("FFFFFFFF")
    end
  end
end

function onReceiveNotify(key, value)
  if key == 'setup_ui' then
    setupUI()
  elseif key == 'set_fx' then
    local busGroup = root:findByName('bus'..tostring(busNum)..'_group', true)
    busGroup:notify('set_fx', {value[1], value[2]})
  end
end

function init()
  for i = 1, #self.children do
    self.children[i].script = buttonScript
  end

  setupUI()
end
