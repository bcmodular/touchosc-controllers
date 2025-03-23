function init()

  SETTINGS = {}

  SETTINGS["selected_item_header"] = ""

  SETTINGS["columns_count"] = 3

  SETTINGS["fixed_item_width"] = 125

  SETTINGS["corner_radius"] = 1

  SETTINGS["global_padding"] = 5

  SETTINGS["item_height"] = 30
  SETTINGS["item_padding"] = 5
  SETTINGS["item_label_padding"] = 5
  SETTINGS["item_label_align"] = "left" -- "left" "center" or "right"
  SETTINGS["item_label_font_size"] = 15

  SETTINGS["use_default_colors"] = false
  SETTINGS["selected_item_default_color"] = Color.fromHexString("FFA61AFF")
  SETTINGS["item_default_color"] = Color.fromHexString("FFA61AFF")

  self.parent:notify("set_settings", SETTINGS)

end