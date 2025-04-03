local effectChooserScript = [[
local selected_menu_index = 0
local all_items = {}
local menu_items = {}
local ITEM_WIDTH = 0

function init()
  selected_menu_index = tonumber(self.tag) or 0
  all_items = self.children.items:findAllByProperty("tag", "item", false)
end

local function initItem(index, item)

  local row_index = math.ceil(index / SETTINGS["columns_count"])
  local column_index = index - (SETTINGS["columns_count"] * (row_index - 1))

  local pos_x = SETTINGS["global_padding"] + (ITEM_WIDTH * (column_index - 1)) + (SETTINGS["item_padding"] * (column_index-1))
  local pos_y = SETTINGS["global_padding"] + SETTINGS["item_height"] + (SETTINGS["item_height"] * (row_index - 1)) + (SETTINGS["item_padding"] * row_index)

  item.frame.w = ITEM_WIDTH + 2
  item.frame.h = SETTINGS["item_height"] + 2
  item.frame.x = pos_x
  item.frame.y = pos_y
  item.name = "item_" .. tostring(index)

  -- background
  item.children.background.frame.w = ITEM_WIDTH
  item.children.background.frame.h = SETTINGS["item_height"]
  item.children.background.frame.x = 0
  item.children.background.frame.y = 0
  item.children.background.cornerRadius = SETTINGS["corner_radius"]

  -- btn
  item.children.btn.tag = index
  item.children.btn.frame.w = ITEM_WIDTH
  item.children.btn.frame.h = SETTINGS["item_height"]
  item.children.btn.frame.x = 0
  item.children.btn.frame.y = 0
  item.children.btn.cornerRadius = SETTINGS["corner_radius"]

  -- label
  item.children.label.frame.w = ITEM_WIDTH - (SETTINGS["item_label_padding"] * 2)
  item.children.label.frame.h = SETTINGS["item_height"]
  item.children.label.frame.x = SETTINGS["item_label_padding"]
  item.children.label.frame.y = 0
  item.children.label.cornerRadius = SETTINGS["corner_radius"]
  item.children.label.properties.textAlignH = SETTINGS["item_label_align"]
  item.children.label.properties.textSize = SETTINGS["item_label_font_size"]
  item.children.label.color = Color.fromHexString("000000FF")

end

local function initUI()
  -- Calculate item width based on fixed width or available space
  if SETTINGS["fixed_item_width"] then
    ITEM_WIDTH = SETTINGS["fixed_item_width"]
  else
    -- Use original calculation
    ITEM_WIDTH = (self.frame.w - (SETTINGS["global_padding"] * 2) - (SETTINGS["item_padding"] * (SETTINGS["columns_count"] - 1))) / SETTINGS["columns_count"]
  end

  -- background
  self.children.background.frame.w = self.frame.w
  self.children.background.frame.x = 0
  self.children.background.frame.y = 0
  self.children.background.cornerRadius = SETTINGS["corner_radius"]

  local selected_item_width = self.frame.w / 3 - (SETTINGS["global_padding"] * 2)

  -- selected_item group
  self.children.selected_item.frame.w = selected_item_width
  self.children.selected_item.frame.h = SETTINGS["item_height"]
  self.children.selected_item.frame.x = SETTINGS["global_padding"]
  self.children.selected_item.frame.y = SETTINGS["global_padding"]
  self.children.selected_item.cornerRadius = SETTINGS["corner_radius"]

  -- selected_item.background
  self.children.selected_item.children.background.frame.w = selected_item_width
  self.children.selected_item.children.background.frame.h = SETTINGS["item_height"]
  self.children.selected_item.children.background.frame.x = 0
  self.children.selected_item.children.background.frame.y = 0
  self.children.selected_item.children.background.cornerRadius = SETTINGS["corner_radius"]
  self.children.selected_item.children.background.visible = true
  if(SETTINGS["use_default_colors"] == true) then
    self.children.selected_item.children.background.color = SETTINGS["selected_item_default_color"]
  end

  -- selected_item.selected_item_button
  self.children.selected_item.children.selected_item_button.frame.w = selected_item_width
  self.children.selected_item.children.selected_item_button.frame.h = SETTINGS["item_height"]
  self.children.selected_item.children.selected_item_button.frame.x = 0
  self.children.selected_item.children.selected_item_button.frame.y = 0
  self.children.selected_item.children.selected_item_button.cornerRadius = SETTINGS["corner_radius"]

  -- selected_item.label
  self.children.selected_item.children.label.frame.w = selected_item_width - (SETTINGS["item_label_padding"] * 2)
  self.children.selected_item.children.label.frame.h = SETTINGS["item_height"]
  self.children.selected_item.children.label.frame.x = SETTINGS["item_label_padding"]
  self.children.selected_item.children.label.frame.y = 0
  self.children.selected_item.children.label.cornerRadius = SETTINGS["corner_radius"]
  self.children.selected_item.children.label.properties.textAlignH = SETTINGS["item_label_align"]
  self.children.selected_item.children.label.properties.textSize = SETTINGS["item_label_font_size"]

  -- selected_item.arrow_label
  self.children.selected_item.children.arrow_label.frame.x = selected_item_width - self.children.selected_item.children.arrow_label.frame.w - SETTINGS["item_label_padding"]
  self.children.selected_item.children.arrow_label.frame.y = (SETTINGS["item_height"] / 2) - (self.children.selected_item.children.arrow_label.frame.h / 2)
  self.children.selected_item.children.arrow_label.properties.textSize = SETTINGS["item_label_font_size"]

  -- items.group
  self.children.items.frame.w = self.frame.w
  self.children.items.frame.x = 0
  self.children.items.frame.y = 0

  for item_index, item in ipairs(all_items) do
    initItem(item_index, item)
  end
end

local function updateMenuItemsData()

  for _, item_group in ipairs(all_items) do
    item_group.visible = false
  end

  for index, menu_item in ipairs(menu_items) do

    if(self.children.items:findByName("item_" .. index) ~= nil) then
      local item_ui = self.children.items.children["item_" .. index]

      item_ui.children.label.values.text = menu_item["label"]
      item_ui.children.btn.tag = index

      -- selected_menu_item
      if(index == selected_menu_index) then
        if(SETTINGS["use_default_colors"] == true) then
          self.children.selected_item.children.background.color = SETTINGS["selected_item_default_color"]
        else
          if(menu_item["color"] ~= nil) then
            self.children.selected_item.children.background.color = menu_item["color"]
          else
            self.children.selected_item.children.background.color = item_ui.children.background.color
          end
        end
      end
      -- menu_item color
      if(SETTINGS["use_default_colors"] == true) then
        if(index == selected_menu_index) then
          item_ui.children.background.color = SETTINGS["selected_item_default_color"]
        else
          item_ui.children.background.color = SETTINGS["item_default_color"]
        end
      else
        if(menu_item["color"] ~= nil) then
          item_ui.children.background.color = menu_item["color"]
        end
      end
      item_ui.visible = true
    end
  end
end

local function onMenuItemsChanged()
  if(menu_items ~= nil) then
    updateMenuItemsData()
  end
end

local function getUIHeight()
  local selected_menu_item_h = SETTINGS["global_padding"] + SETTINGS["item_height"]
  local coef = math.ceil(#menu_items / SETTINGS["columns_count"])
  local menu_items_h = (SETTINGS["item_height"] + SETTINGS["item_padding"]) * coef
  local total_height = selected_menu_item_h + menu_items_h + SETTINGS["global_padding"]
  return total_height
end

local function clearBus()
  local selected_menu_item_data = menu_items[tonumber(selected_menu_index)]

  self.children.selected_item.tag = json.fromTable(selected_menu_item_data)
  self.children.selected_item.children.label.values.text = "Choose FX..."

  updateMenuItemsData()
  local controlGroup = self.parent:findByName('control_group', true)
  controlGroup.visible = false
end

local function openMenu()

  if(menu_items ~= nil) then
  self.frame.h = getUIHeight() + 1
  self.children.selected_item.children.arrow_label.values.text = "▼"
  self.children.background.frame.h = getUIHeight()
  self.children.items.frame.h = getUIHeight()

  self.children.items.visible = true
  end
end

local function closeMenu()
  self.frame.h = SETTINGS["item_height"] + (SETTINGS["global_padding"] * 2)
  self.children.background.frame.h = SETTINGS["item_height"] + (SETTINGS["global_padding"] * 2)
  self.children.selected_item.children.arrow_label.values.text = "▶"
  self.children.items.visible = false
end

local function initPresetList()
  print('initPresetList', selected_menu_index)

  if selected_menu_index == 0 then
    return
  end

  local selected_menu_item_data = menu_items[tonumber(selected_menu_index)]
  local fxNum = selected_menu_item_data["id"]

  local performPresetGrid = self.parent:findByName('perform_preset_grid', true)
  performPresetGrid:notify('init_presets_list', fxNum)
end

local function showBus()

  local performRecallProxy = self.parent:findByName('perform_recall_proxy', true)
  performRecallProxy:notify('store_current_values')

  local selected_menu_item_data = menu_items[tonumber(selected_menu_index)]

  self.children.selected_item.tag = json.fromTable(selected_menu_item_data)
  self.children.selected_item.children.label.values.text = SETTINGS["selected_item_header"] .. selected_menu_item_data["label"]

  updateMenuItemsData()

  local fxNum = selected_menu_item_data["id"]
  local midiChannel = tonumber(self.parent.tag)
  print("showBus [id: " .. fxNum .. "][label: " .. selected_menu_item_data["label"] .. "][value: " .. selected_menu_item_data["value"] .. "]")

  closeMenu()

  local controlGroup = self.parent:findByName('control_group', true)
  controlGroup.visible = true

  local performPresetHandler = self.parent:findByName('perform_preset_handler', true)
  performPresetHandler:notify('set_settings', {fxNum, midiChannel})

  local performRecallProxy = self.parent:findByName('perform_recall_proxy', true)
  performRecallProxy:notify('set_settings', {fxNum, midiChannel})

  initPresetList()

  local controlMapper = root:findByName('control_mapper', true)
  local faderGroups = self.parent:findByName('faders', true)
  local potGroups = self.parent:findByName('pots', true)
  controlMapper:notify('init_perform', {fxNum, midiChannel, faderGroups, potGroups})

  local onOffButtonGroup = self.parent:findByName('on_off_button_group', true)
  onOffButtonGroup:notify('set_settings', {fxNum, midiChannel, selected_menu_item_data["label"]})

  performRecallProxy:notify('recall_recent_values')
end

local function setUpBus()
  self.tag = selected_menu_index

  if(selected_menu_index ~= 0) then
    showBus()
  else
    clearBus()
  end
end

---@diagnostic disable: lowercase-global
function onReceiveNotify(key, value)

  print('onReceiveNotify', key, value)

  if(key == "set_menu_items") then
    menu_items = value
    onMenuItemsChanged()
    setUpBus()
    return
  end

  if(key == "set_settings") then
    SETTINGS = value
    if(SETTINGS["item_label_align"] == "left") then SETTINGS["item_label_align"] = AlignH.LEFT end
    if(SETTINGS["item_label_align"] == "center") then SETTINGS["item_label_align"] = AlignH.CENTER end
    if(SETTINGS["item_label_align"] == "right") then SETTINGS["item_label_align"] = AlignH.RIGHT end
    initUI()
    return
  end

  if(key == "openMenu") then
    openMenu()
  end

  if(key == "closeMenu") then
    print('closing menu for', self.parent.name)
    closeMenu()
  end

  if(key == "toggle_menu") then
    if(self.children.items.visible == true) then
      closeMenu()
    else
      openMenu()
    end

    local performGroup = self.parent.parent.parent:findByName('perform_group')
    performGroup:notify('hide_other_than_me', self)
  end

  if(key == "select_index") then
    if(#menu_items >= 1) then
      if(value <= #menu_items) then
        selected_menu_index = value
      else
        selected_menu_index = 1
      end
      setUpBus()
    else
      -- empty
      selected_menu_index = 0
      self.tag = selected_menu_index
      self.children.selected_item.children.label.values.text = SETTINGS["selected_item_header"] .. "None"
    end
  end

  if(key == "btn_pressed") then
    selected_menu_index = tonumber(value) or 0
    setUpBus()
    return
  end

  if(key == "init_effect_chooser") then
    setUpBus()
    return
  end

  if(key == "init_preset_list") then
    initPresetList()
    return
  end
end
]]

local selectedItemScript = [[
function onValueChanged(key)

  if(key == "touch" and self.values.touch == true) then
    self.parent.parent:notify("toggle_menu")
  end

end
]]

local itemButtonScript = [[
function onValueChanged(key)

  if(key == "touch" and self.values.touch == true) then
    self.parent.parent.parent:notify("btn_pressed", self.tag)
  end

end
]]

function init()
  local effectChoosers = root:findAllByName('effect_chooser', true)

  for _, effectChooser in ipairs(effectChoosers) do
    effectChooser.script = effectChooserScript
  end

  local buttons = root:findAllByName('btn', true)
  for _, button in ipairs(buttons) do
    button.script = itemButtonScript
  end

  local selectedItemButtons = root:findAllByName('selected_item_button', true)
  for _, button in ipairs(selectedItemButtons) do
    button.script = selectedItemScript
  end
end