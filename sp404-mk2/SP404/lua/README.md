# Naming Conventions

## Variable and Function Names
- Use camelCase for all variable and function names
- Use PascalCase for class names (if applicable)
- Use UPPER_SNAKE_CASE for constants
- Use snake_case ONLY for control names and UI element identifiers (e.g., 'edit_compressor_sidechain', 'ratio_fader_group')

## Examples
```lua
-- Good
local attackTimeMs = 10
local currentEnvelopeValue = 0
local isEnabled = false

-- Bad
local attack_time_ms = 10
local current_envelope_value = 0
local is_enabled = false

-- Control names (must use snake_case)
local editCompressorSidechain = compressorEditPage:findByName('edit_compressor_sidechain', true)
local ratioFaderGroup = editCompressorSidechain:findByName('ratio_fader_group', true)
```

## Rationale
- camelCase is the standard in JavaScript and many other modern languages
- snake_case for control names matches TouchOSC's internal naming conventions
- Consistent naming improves code readability and maintainability
- Reduces confusion when working with multiple files

## Enforcement
- Review all new code for consistent naming
- Update existing code to follow these conventions when modified
- Use automated tools (like linters) where possible to enforce these rules

## TouchOSC Grid Scope Rules

When working with TouchOSC grids, it's important to understand how scope works:

- In a TouchOSC grid, the parent grid and its child buttons share the same script/object definition
- Each instance (parent and children) operates in its own scope with its own `self` reference
- Child buttons **cannot** access parent variables directly
- The `tag` property is the only way to share state between parent and children
- Therefore, any shared state (like `deleteMode`) must be stored in the parent's `tag` property

Example:
```lua
-- In parent grid:
local tagData = json.toTable(self.tag) or {}
tagData.deleteMode = true
self.tag = json.fromTable(tagData)

-- In child button:
local tagData = json.toTable(self.parent.tag) or {}
local deleteMode = tagData.deleteMode or false
```

This is why the `tag` property is so important in TouchOSC - it's the only reliable way to share state between different scopes in the same grid structure, but remember that it can only store string values, so you'll need to use JSON encoding/decoding to store and retrieve complex data.

## Button State Rules

When working with button states in TouchOSC:

- Always store button states as strings in the button's `name` property
- Use `tostring()` when setting the name to ensure it's a string
- Use `tonumber()` when reading the name to convert back to a number
- Define state constants at the top of your script
- Use the state constants consistently throughout the code

Example:
```lua
local BUTTON_STATE = {
    RECALL = 1,
    DISABLED = 2
}

-- Setting state
child.name = tostring(BUTTON_STATE.RECALL)

-- Reading state
local buttonState = tonumber(self.name) or 0
if buttonState == BUTTON_STATE.RECALL then
    -- handle recall state
end
```