local itemsScript = [[
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

local function getMappedEffects(case)
    local result = {}

    for i, value in ipairs(allMidiValues) do
        local cc1, cc2, cc3 = value[1], value[2], value[3]
        -- print(cc1, cc2, cc3)
        local cc = (case == 1 and cc1) or (case == 2 and cc2) or (case == 3 and cc3) or 0
        -- print(cc)
        if cc ~= 0 and effects[i] then
            table.insert(result, { tostring(i), effects[i], cc })
        end
    end

    return result
end
function init()

  local menu_items = {}
  local midiChannel = tonumber(self.tag) - 1

  local mappingCase = 3

  if midiChannel == 0 or midiChannel == 1 then
    mappingCase = 1
  elseif midiChannel == 2 or midiChannel == 3 then
    mappingCase = 2
  end

  local mappedEffects = getMappedEffects(mappingCase) -- Replace with 1, 2, or 3
  for _, entry in ipairs(mappedEffects) do
    local menu_item = {}
    menu_item["id"] = entry[1]
    menu_item["label"] = entry[2]
    menu_item["value"] = entry[3]
    menu_item["color"] = Color.fromHexString("FFA61AAA")
    table.insert(menu_items, menu_item)
  end

  self.parent:notify("set_menu_items", menu_items)

end
]]

function init()
  local items = root:findAllByName('_items', true)
  for _, item in ipairs(items) do
    item.script = itemsScript
  end
end
