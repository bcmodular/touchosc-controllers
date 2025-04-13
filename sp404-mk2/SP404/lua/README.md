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