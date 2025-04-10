local pointerScript = [[
-- Limits the value and returns it to ensure it stays within [min, max]
local function limit(x, min, max)
  if (x > max) then
    return max
  end
  if (x < min) then
    return min
  end
  return x
end

function init()

  -- The ratio defines how many pixels correspond to one rotation of the knob.
  -- distance_ratio: standard sensitivity
  distance_ratio = 1/200  -- 1 rotation corresponds to 200 pixels movement
  -- distance_ratio_fine: finer sensitivity for precise control
  distance_ratio_fine = 1/1000  -- 1 rotation corresponds to 1000 pixels movement

  -- Target Object for controlling the value
  target_obj = self.parent.children['value']
  -- Original value before pointer interaction
  og_value = 0
  -- Starting y-position of the pointer
  start_y = 0
  -- Time when the pointer was last pressed
  press_time = 0
  -- Current number of active pointers (fingers)
  pointer_count = 1
end


function onPointer(pointers)
  -- Flag to determine if fine control is active (multiple pointers)
  local fine_control = false

  -- Determine the number of active pointers
  local new_pointer_count = 1
  if (#self.pointers > 1) then
    fine_control = true
    new_pointer_count = 2
  end

  -- Iterate through each pointer event
  for i = 1, #pointers do
    local pointer = pointers[i]

    -- If the number of active pointers has changed, reset start positions
    if (new_pointer_count ~= pointer_count) then
      start_y = pointer.y
      og_value = target_obj.values.x
      pointer_count = new_pointer_count
    end

    local do_move = false
    -- Handle different pointer states
    if (pointer.state == PointerState.BEGIN) then
      -- Pointer has just begun interacting
      og_value = target_obj.values.x
      start_y = pointer.y
      -- Notify the target object that it is being touched/pressed
      target_obj:notify("touch", true)
    end
    if (pointer.state == PointerState.ACTIVE) then
      -- Pointer is actively engaged
      do_move = true
    end
    if (pointer.state == PointerState.END) then
      -- Pointer interaction has ended
      do_move = false -- Do not apply cursor change on end as it can shift on release...

      -- Get the current time in milliseconds
      local new_press_time = getMillis()
      -- Check if the press duration was short (a tap)
      if (new_press_time - press_time < 200) then
        -- Reset the target object's value to its default
        target_obj.values.x = tonumber(target_obj:getValueField("x", ValueField.DEFAULT))
        return
      end
      -- Update the press_time to the current time
      press_time = new_press_time
      -- Notify the target object that touch has ended
      target_obj:notify("touch", false)
    end
    if (pointer.state == PointerState.MOVE) then
      -- Pointer is moving, set do_move to true to process movement
      do_move = true
    end

    if (do_move) then
      -- Calculate the vertical distance moved by the pointer
      local distance = start_y - pointer.y

      -- Determine which ratio to use based on control mode
      local ratio = distance_ratio
      if (fine_control) then
        ratio = distance_ratio_fine
      end

      -- Calculate the new value based on the distance and ratio
      local new_value = og_value + (distance * ratio)
      -- Ensure the new value is within the allowed range [0,1]
      new_value = limit(new_value, 0,1)

      -- Update the target object's value
      target_obj.values.x = new_value
    end
  end
end
]]

-- Initialises the various pointer objects
local function initialisePointers()
  local pointers = root:findAllByName('pointer', true)
  for _, pointer in ipairs(pointers) do
    --print('initialising pointer', pointer.name)
    pointer.script = pointerScript
  end
end

function init()
  local debugMode = tonumber(root:findByName('debug_mode').tag)
  if debugMode == 1 then
    initialisePointers()
  end
end
