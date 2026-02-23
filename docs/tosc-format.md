# .tosc File Format Reference

Reference for the TouchOSC `.tosc` binary layout format, documented from analysis of files in this repository.

## Compression

A `.tosc` file is **zlib-compressed XML** (raw deflate, not zip/gzip). To inspect:

```python
import zlib
with open("layout.tosc", "rb") as f:
    xml = zlib.decompress(f.read()).decode("utf-8")
```

## XML Structure

Root element: `<lexml version='5'>`

The document is a tree of `<node>` elements, each with four possible child sections:

```xml
<lexml version='5'>
  <node ID='uuid' type='GROUP'>
    <properties>...</properties>
    <values>...</values>
    <messages>...</messages>
    <children>
      <node ID='uuid' type='BUTTON'>...</node>
      ...
    </children>
  </node>
</lexml>
```

## Node Types

| Type     | Description                                    |
|----------|------------------------------------------------|
| `GROUP`  | Container for other nodes                      |
| `BUTTON` | Pressable button (toggle, momentary, etc.)     |
| `FADER`  | Slider/fader control (0.0–1.0 float range)     |
| `LABEL`  | Text display element                           |
| `BOX`    | Visual rectangle (background, decoration)      |
| `GRID`   | Grid container — auto-arranges children        |
| `TEXT`   | Editable text input field                      |

## Properties

Each node has a `<properties>` block containing typed `<property>` elements:

```xml
<property type='TYPE'>
  <key><![CDATA[KEY_NAME]]></key>
  <value>VALUE</value>
</property>
```

### Property Types

| Type | Name    | Value Format                                        |
|------|---------|-----------------------------------------------------|
| `b`  | Boolean | `0` or `1`                                          |
| `i`  | Integer | Plain integer                                       |
| `f`  | Float   | Decimal number                                      |
| `s`  | String  | `<![CDATA[...]]>` wrapper                           |
| `c`  | Color   | `<r>R</r><g>G</g><b>B</b><a>A</a>` (0.0–1.0 each) |
| `r`  | Rect    | `<x>X</x><y>Y</y><w>W</w><h>H</h>`                 |

**Important:** All string values (`type='s'`) use CDATA wrappers, including `name`, `script`, `tag`, and `tabLabel`.

### Common Properties

Every node has these properties:

- `name` (s) — Element name, used for `findByName()` lookups
- `frame` (r) — Position and size `{x, y, w, h}`
- `color` (c) — Element color
- `visible` (b) — Visibility
- `interactive` (b) — Whether the element responds to touch
- `locked` (b) — Locked in editor
- `background` (b) — Renders background fill
- `outline` (b) — Renders outline
- `outlineStyle` (i) — Outline style variant
- `orientation` (i) — 0=horizontal, 1=vertical
- `cornerRadius` (f) — Corner rounding
- `grabFocus` (b) — Captures pointer focus
- `pointerPriority` (i) — Touch priority ordering
- `script` (s) — Lua script attached to this element
- `tag` (s) — Arbitrary string storage (used for state/data sharing)

### Button-Specific Properties

- `buttonType` (i) — Toggle (0), momentary (1), etc.
- `press` (b) — Trigger on press
- `release` (b) — Trigger on release
- `textColorOn` (c) — Text color when active
- `textColorOff` (c) — Text color when inactive
- `tabColorOn` (c) — Tab color when active
- `tabColorOff` (c) — Tab color when inactive

### Fader-Specific Properties

- `bar` (b) — Show fill bar
- `barDisplay` (i) — Bar display mode
- `cursor` (b) — Show cursor
- `cursorDisplay` (i) — Cursor display mode
- `response` (i) — Response curve type
- `responseFactor` (i) — Response curve factor
- `grid` (b) — Snap to grid
- `gridSteps` (i) — Number of snap positions
- `gridStart` (i) — Grid start offset
- `valuePosition` (b) — Show value position indicator

### Grid-Specific Properties

- `gridX` (i) — Number of columns
- `gridY` (i) — Number of rows
- `gridType` (i) — Grid layout type
- `gridOrder` (i) — Child ordering direction
- `gridNaming` (i) — Auto-naming scheme for children
- `exclusive` (b) — Only one child active at a time
- `gridColor` (c) — Grid line color

### Text Properties

- `font` (i) — Font index
- `textSize` (i) — Font size
- `textColor` (c) — Text color
- `textAlignH` (i) — Horizontal alignment
- `textAlignV` (i) — Vertical alignment
- `textClip` (b) — Clip overflow
- `textWrap` (b) — Wrap text
- `textLength` (i) — Max text length
- `tabLabel` (s) — Label text for tab display

## Values

The `<values>` section defines the element's state channels:

```xml
<values>
  <value ID='uuid' key='x' default='0' defaultPull='0' locked='false'>
    <messages>...</messages>
  </value>
  <value ID='uuid' key='touch' default='0' defaultPull='0' locked='false'>
    <messages>...</messages>
  </value>
</values>
```

Common value keys: `x` (primary value), `touch` (touch state), `text` (text content).

## Messages

Messages define MIDI, OSC, and local bindings. They appear inside `<value>` blocks:

```xml
<messages>
  <midi>
    <enabled>true</enabled>
    <send>true</send>
    <receive>true</receive>
    <channel>1</channel>
    <type>CONTROLCHANGE</type>
    <data1 locked='false'>
      <messages><local><trigger>ANY</trigger><type>CONSTANT</type><conversion>INT</conversion><value>64</value></local></messages>
    </data1>
    <data2 locked='false'>
      <messages><local><trigger>ANY</trigger><type>SELF</type><conversion>MIDI</conversion></local></messages>
    </data2>
  </midi>
</messages>
```

MIDI types: `CONTROLCHANGE`, `NOTEON`, `NOTEOFF`, `SYSTEMEXCLUSIVE`.

## Script Embedding

Scripts are stored as CDATA in the `script` string property:

```xml
<property type='s'>
  <key><![CDATA[script]]></key>
  <value><![CDATA[
-- Lua code here
function init()
  print("hello")
end
  ]]></value>
</property>
```

### CDATA Preservation

Python's `xml.etree.ElementTree` **strips CDATA markers** on parse. To modify scripts without corrupting the file, use **string-level replacement** (regex) rather than XML DOM manipulation. The `toscbuild.py` tool uses this approach.

## Lua Scripting Environment

TouchOSC uses a sandboxed Lua environment based on **Lua 5.1** with select 5.2/5.3 additions.

### Available Globals

From Lua base: `error`, `ipairs`, `next`, `pairs`, `print`, `select`, `tonumber`, `tostring`, `unpack`, `type`

**Not available:** `require`, `dofile`, `loadfile`, `io`, `coroutine`, `os` (except `os.clock`, `os.time`, `os.difftime`), `debug`, `package`

### Available Libraries

- `string` — Full standard library
- `table` — Full standard library + `table.pack()`, `table.unpack()`
- `math` — Full standard library + `math.clamp(value, min, max)`
- `bit32` — Bitwise operations (from Lua 5.2)
- `utf8` — UTF-8 support (from Lua 5.3)
- `json` — `json.toTable(str)`, `json.fromTable(tbl)`

### TouchOSC API

Key functions available in scripts:

- `sendMIDI(message, connections)` — Send MIDI messages
- `sendOSC(path, ...)` — Send OSC messages
- `notify(key, ...)` — Send notification to this element's subtree
- `self` — Reference to the current element
- `root` — Reference to the root element
- `self.parent` — Parent element
- `self.children` — Child elements table
- `self.name` — Element name
- `self.tag` — Tag property (string, used for state sharing)
- `self.values.x` — Primary value (0.0–1.0 for faders)
- `self:findByName(name, recursive)` — Find child by name

### Lifecycle Callbacks

- `init()` — Called when the layout loads
- `update()` — Called each frame
- `onValueChanged(key, value)` — Called when a value changes
- `onReceiveMIDI(message, connections)` — MIDI input handler
- `onReceiveOSC(message, connections)` — OSC input handler
- `onReceiveNotify(key, ...)` — IPC notification handler

### Grid Scope Rules

In GRID elements, each child runs its own script scope. Children share data via the **`tag` property** on a common parent — always JSON-encoded using `json.toTable()`/`json.fromTable()`.

### Naming Conventions

Per `sp404-mk2/SP404/lua/README.md`:

- **Variables/functions:** camelCase (`controlFader`, `refreshPresets`)
- **Constants:** UPPER_SNAKE_CASE (`BUTTON_STATE_COLORS`, `DELETE_BUTTON_LED`)
- **Control names:** snake_case (`preset_grid`, `control_fader`, `bus1_group`)

### MIDI Value Conversion

TouchOSC faders use 0.0–1.0 float range. MIDI uses 0–127 integer range. Common conversion:

```lua
local function floatToMIDI(f) return math.floor(f * 127 + 0.5) end
local function midiToFloat(m) return m / 127 end
```
