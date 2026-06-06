#!/usr/bin/env python3
"""
Colour update for TB3.tosc.

Run this script whenever colours need re-tuning. It always operates on the
current .tosc state, so re-running it is safe (it replaces whatever accent
colour is there with the declared target).

Palette decisions
─────────────────
ring_mod_group   vivid purple      (0.75, 0.15, 1.00)
  Sits next to Cross Mod's hot magenta; cool purple family = coherent,
  vivid enough to be legible.

portamento_group blue-violet       (0.50, 0.30, 1.00)
pitch_bend_group medium indigo     (0.35, 0.10, 0.80)
  Pitch controls unified in blue-indigo family; Pitch Bend slightly
  darker than Portamento.  Both clearly separate from Distortion red.

EFX1 section hierarchy (base = teal 0.2/0.7/0.75):
  efx_1_chooser + efx1_b5-b8  →  warm gold    (0.95, 0.82, 0.20)
  "gold = select, teal = control" — complementary-hue contrast.

EFX2 section hierarchy (base = coral 0.85/0.38/0.12):
  efx_2_chooser + efx2_b5-b8  →  jade green   (0.30, 0.90, 0.60)
  "jade = select, coral = control" — cool/warm contrast.

The shared "selector" colour between the effect-type chooser grid and the
type-option radio buttons (B5–B8) visually groups "things that pick what
something IS" vs "things that change how it behaves".
"""

import re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "tools"))
from tosc_layout_utils import tosc_read, tosc_write, find_node_block

TOSC = Path(__file__).parent.parent / "TB3.tosc"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

COLOR_PROP_RE = re.compile(
    r"(<property type='c'><key><!\[CDATA\[color\]\]></key><value>)"
    r"<r>([^<]+)</r><g>([^<]+)</g><b>([^<]+)</b>"
    r"(<a>[^<]+</a>)"
    r"(</value></property>)"
)


def recolor_block(block: str, r: float, g: float, b: float) -> tuple[str, int]:
    """Replace every non-black, non-transparent 'color' property in block."""
    count = 0

    def replace(m: re.Match) -> str:
        nonlocal count
        cr, cg, cb = float(m.group(2)), float(m.group(3)), float(m.group(4))
        if cr < 0.1 and cg < 0.1 and cb < 0.1:   # skip black / transparent
            return m.group(0)
        count += 1
        return f"{m.group(1)}<r>{r}</r><g>{g}</g><b>{b}</b>{m.group(5)}{m.group(6)}"

    return COLOR_PROP_RE.sub(replace, block), count


def update(xml: str, name: str, r: float, g: float, b: float) -> str:
    bounds = find_node_block(xml, name)
    if not bounds:
        print(f"  WARNING: '{name}' not found"); return xml
    start, end = bounds
    new_block, n = recolor_block(xml[start:end], r, g, b)
    print(f"  {name:<22}  {n:>3} props  →  ({r}, {g}, {b})")
    return xml[:start] + new_block + xml[end:]


# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

xml = tosc_read(TOSC)
print("Applying colour changes…\n")

# ── Pitch / modulation sections ──────────────────────────────────────────────
xml = update(xml, "ring_mod_group",   0.75, 0.15, 1.00)   # vivid purple (keep)
# Blue-heavy hues look dark: raise r+g to add perceived brightness while
# keeping the violet/indigo character.
xml = update(xml, "portamento_group", 0.78, 0.60, 1.00)   # light lavender
xml = update(xml, "pitch_bend_group", 0.60, 0.38, 0.95)   # medium violet (darker than portamento)

# ── EFX1: teal section ───────────────────────────────────────────────────────
# Chooser grid + type-option buttons (B5–B8) — bright version of the same
# teal/cyan family: clearly lighter than the section base but same hue range.
xml = update(xml, "efx_1_chooser",    0.70, 0.95, 1.00)   # pale icy cyan — near-white
for btn in ["efx1_b5", "efx1_b6", "efx1_b7", "efx1_b8"]:
    xml = update(xml, btn,             0.70, 0.95, 1.00)

# ── EFX2: coral section ──────────────────────────────────────────────────────
# Bright version of the coral/orange family.
xml = update(xml, "efx_2_chooser",    1.00, 0.65, 0.35)   # bright coral-orange
for btn in ["efx2_b5", "efx2_b6", "efx2_b7", "efx2_b8"]:
    xml = update(xml, btn,             1.00, 0.65, 0.35)

tosc_write(TOSC, xml)
print(f"\nWritten: {TOSC} ({TOSC.stat().st_size:,} bytes compressed)")
