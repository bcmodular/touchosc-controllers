-- Hugo Kant - TouchOSC dropdown menu V 1.0

-- Modify _settings script
-- Modify _items script


function init()
  selected_menu_index = tonumber(self.tag)
  all_items = self.children.items:findAllByProperty("tag", "item", false)
end

function init_ui()
  
  ITEM_WIDTH = (self.frame.w - (SETTINGS["global_padding"] * 2) - (SETTINGS["item_padding"] * (SETTINGS["columns_count"] - 1))) / SETTINGS["columns_count"]
  
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
  
  -- selected_item.btn
  self.children.selected_item.children.btn.frame.w = selected_item_width
  self.children.selected_item.children.btn.frame.h = SETTINGS["item_height"]
  self.children.selected_item.children.btn.frame.x = 0
  self.children.selected_item.children.btn.frame.y = 0
  self.children.selected_item.children.btn.cornerRadius = SETTINGS["corner_radius"]
  
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
  
  -- items
  btn_script = self.children.items.children.item_1.children.btn.script
  
  for item_index, item in ipairs(all_items) do
  item.children.btn.script = btn_script
  init_item(item_index, item)
  end
  
end

function init_item(index, item)
  
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
  print(item.children.label.color)
  item.children.label.color = Color.fromHexString("000000FF")

end

function get_ui_height()
  local selected_menu_item_h = SETTINGS["global_padding"] + SETTINGS["item_height"]
  
  local coef = math.ceil(#menu_items / SETTINGS["columns_count"])
  
  local menu_items_h = (SETTINGS["item_height"] + SETTINGS["item_padding"]) * coef
  
  local total_height = selected_menu_item_h + menu_items_h + SETTINGS["global_padding"]
  
  return total_height
end

function onReceiveNotify(key, value)
  
  if(key == "set_menu_items") then
    menu_items = value
    on_menu_items_changed()
    return
  end
  if(key == "set_settings") then
    SETTINGS = value
    if(SETTINGS["item_label_align"] == "left") then SETTINGS["item_label_align"] = AlignH.LEFT end
    if(SETTINGS["item_label_align"] == "center") then SETTINGS["item_label_align"] = AlignH.CENTER end
    if(SETTINGS["item_label_align"] == "right") then SETTINGS["item_label_align"] = AlignH.RIGHT end
    init_ui()
    return
  end
  
  if(key == "open_menu") then
  open_menu()
  end
  
  if(key == "toggle_menu") then
  
  if(self.children.items.visible == true) then
    close_menu()
  else
    open_menu()
  end
  end
  
  if(key == "select_index") then
  if(#menu_items >= 1) then
    if(value <= #menu_items) then
    selected_menu_index = value
    else
    selected_menu_index = 1
    end
    on_value_changed(false)
    
  else
    -- empty
    selected_menu_index = 0
    self.tag = selected_menu_index
    self.children.selected_item.children.label.values.text = SETTINGS["selected_item_header"] .. "None"
  end
  return
  end
  
  if(key == "select_index_by_id") then
  for item_index, item in ipairs(menu_items) do
    if(item["id"] == tonumber(value)) then
    selected_menu_index = item_index
    on_value_changed()
    end
  end 
  end
  
  if(key == "select_index_by_label") then
  for item_index, item in ipairs(menu_items) do
    if(item["label"] == tostring(value)) then
    selected_menu_index = item_index
    on_value_changed()
    end
  end 
  end
  
  if(key == "btn_pressed") then
  selected_menu_index = tonumber(value)
  on_value_changed()
  return
  end
  
end

function open_menu()
  
  if(menu_items ~= nil) then
  self.frame.h = get_ui_height() + 1
  self.children.selected_item.children.arrow_label.values.text = "▼"
  self.children.background.frame.h = get_ui_height()
  self.children.items.frame.h = get_ui_height()
  
  self.children.items.visible = true
  end
end

function close_menu()
  self.frame.h = SETTINGS["item_height"] + (SETTINGS["global_padding"] * 2)
  self.children.background.frame.h = SETTINGS["item_height"] + (SETTINGS["global_padding"] * 2)
  self.children.selected_item.children.arrow_label.values.text = "▶"
  self.children.items.visible = false
end

function on_settings_changed()
  init_ui()
end

function on_menu_items_changed()
  if(menu_items ~= nil) then
    update_menu_items_data()
  end
end
function update_menu_items_data()
  
  for item_index, item_group in ipairs(all_items) do
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

function on_value_changed()
  
  if(selected_menu_index ~= 0) then
    
    local selected_menu_item_data = menu_items[tonumber(selected_menu_index)]
      
    self.tag = selected_menu_index
    self.children.selected_item.tag = json.fromTable(selected_menu_item_data)
    self.children.selected_item.children.label.values.text = SETTINGS["selected_item_header"] .. selected_menu_item_data["label"]
    
    update_menu_items_data()
    
    local fxNum = selected_menu_item_data["id"]
    print("on_value_changed() [id: " .. fxNum .. "][label: " .. selected_menu_item_data["label"] .. "][value: " .. selected_menu_item_data["value"] .. "]")

    close_menu()
    local performPresetGrid = self.parent:findByName('perform_preset_grid', true)
    performPresetGrid:notify('init_presets_list', fxNum)

    local controlMapper = root:findByName('control_mapper', true)
    local faderGroups = self.parent:findByName('faders', true)
    controlMapper:notify('init_perform_faders', {fxNum, 0, faderGroups})
  end
end