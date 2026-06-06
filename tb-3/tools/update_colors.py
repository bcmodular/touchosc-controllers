#!/usr/bin/env python3
"""
Colour audit for TB3.tosc.

Changes applied:
  ring_mod_group   bright yellow→gold (1,0.925,0.053)   → cool purple      (0.55,0.10,0.85)
  portamento_group violet         (0.6,0.302,0.902)     → blue-indigo      (0.30,0.15,0.90)
  pitch_bend_group coral-red      (1,0.29,0.255)        → dark indigo      (0.20,0.05,0.65)
  efx2_section     teal           (0.2,0.7,0.75)        → coral/rust       (0.85,0.38,0.12)
  efx_1_chooser    teal           (same)                → bright cyan      (0.10,0.85,0.95)
  efx_2_chooser    teal→coral     (after efx2 update)   → lighter coral    (0.95,0.55,0.25)

Ring Mod is changing from a disconnected mustard to a purple that
complements Cross Mod's hot magenta while staying distinctly cooler.
Portamento and Pitch Bend unify as a blue-indigo "pitch control" pair,
separate from Distortion's red.  EFX1 stays teal; EFX2 goes coral/rust
for a clear warm/cool split.  Type-chooser buttons get a lighter/brighter
shade than the section's utility buttons.
"""

import re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "tools"))
from tosc_layout_utils import tosc_read, tosc_write, find_node_block

TOSC = Path(__file__).parent.parent / "TB3.tosc"

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------

COLOR_PROP_RE = re.compile(
    r"(<property type='c'><key><!\[CDATA\[color\]\]></key><value>)"
    r"<r>([^<]+)</r><g>([^<]+)</g><b>([^<]+)</b>"
    r"(<a>[^<]+</a>)"
    r"(</value></property>)"
)


def recolor_section(block: str, new_r: float, new_g: float, new_b: float) -> tuple[str, int]:
    """Replace every non-black, non-transparent 'color' property in block."""
    count = 0

    def replace(m: re.Match) -> str:
        nonlocal count
        r, g, b = float(m.group(2)), float(m.group(3)), float(m.group(4))
        # Skip black (backgrounds) and near-transparent
        if r < 0.1 and g < 0.1 and b < 0.1:
            return m.group(0)
        count += 1
        return (
            f"{m.group(1)}"
            f"<r>{new_r}</r><g>{new_g}</g><b>{new_b}</b>"
            f"{m.group(5)}{m.group(6)}"
        )

    return COLOR_PROP_RE.sub(replace, block), count


def update_section(xml: str, name: str,
                   new_r: float, new_g: float, new_b: float) -> str:
    bounds = find_node_block(xml, name)
    if not bounds:
        print(f"  WARNING: '{name}' not found")
        return xml
    start, end = bounds
    new_block, n = recolor_section(xml[start:end], new_r, new_g, new_b)
    print(f"  {name}: {n} colour props updated → ({new_r}, {new_g}, {new_b})")
    return xml[:start] + new_block + xml[end:]


# ---------------------------------------------------------------------------
# Apply changes
# ---------------------------------------------------------------------------

xml = tosc_read(TOSC)

print("Applying colour changes…\n")

# Ring Modulation: bright gold → cool purple
xml = update_section(xml, "ring_mod_group",   0.55, 0.10, 0.85)

# Portamento: violet → blue-indigo (pitch-control family)
xml = update_section(xml, "portamento_group", 0.30, 0.15, 0.90)

# Pitch Bend: coral-red → darker indigo (pitch-control family, darker than portamento)
xml = update_section(xml, "pitch_bend_group", 0.20, 0.05, 0.65)

# EFX2: teal → coral/rust  (warm/cool split with EFX1)
xml = update_section(xml, "efx2_section",     0.85, 0.38, 0.12)

# EFX1 type-chooser: teal → brighter cyan  (type-selector highlight)
xml = update_section(xml, "efx_1_chooser",    0.10, 0.85, 0.95)

# EFX2 type-chooser: (now coral) → lighter coral  (type-selector highlight)
# Must run AFTER efx2_section update so the chooser already has the coral value.
xml = update_section(xml, "efx_2_chooser",    0.95, 0.55, 0.25)

tosc_write(TOSC, xml)
print(f"\nWritten: {TOSC} ({TOSC.stat().st_size:,} bytes compressed)")
