#!/usr/bin/env python3
"""
Cosmetic fix: shift every value_label 1px left and widen it by 2px.

All 80 value_label nodes in TB3.tosc currently share the identical frame
x=6 y=38 w=89 h=25 — this script moves them to x=5 w=91 (y/h unchanged),
which keeps the label visually centred over its slightly-wider footprint
(net +1px on each side).

Safe to re-run: it reports "already at target" and makes no changes if the
frames have already been adjusted.
"""
import re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "tools"))
from tosc_layout_utils import tosc_read, tosc_write, backup_tosc, validate_tosc_xml

TOSC = Path(__file__).parent.parent / "TB3.tosc"

DX = -1   # shift left by 1px
DW = 2    # widen by 2px

NAME_PROP = (
    r"<property type='s'><key><!\[CDATA\[name\]\]></key>"
    r"<value><!\[CDATA\[{name}\]\]></value></property>"
)

FRAME_RE = re.compile(
    r"(<property type='r'><key><!\[CDATA\[frame\]\]></key>\s*<value>)"
    r"<x>([^<]*)</x><y>([^<]*)</y><w>([^<]*)</w><h>([^<]*)</h>"
    r"(</value></property>)"
)


def find_node_block_at(xml: str, name_match_start: int) -> tuple[int, int] | None:
    """Walk forward from the <node> that owns this name-property match to find
    its matching </node>, tracking nesting depth (mirrors find_node_block but
    starts from a known match position so callers can iterate every match)."""
    node_start = xml.rfind("<node ", 0, name_match_start)
    if node_start == -1:
        return None
    i = node_start
    depth = 0
    while i < len(xml):
        if xml.startswith("<node", i) and (i + 5 >= len(xml) or xml[i + 5] in " >"):
            depth += 1
            i += 5
            continue
        if xml.startswith("</node>", i):
            depth -= 1
            i += 7
            if depth == 0:
                return node_start, i
            continue
        i += 1
    return None


def adjust_frame(node_xml: str) -> tuple[str, bool, str]:
    """Shift x by DX and widen w by DW, preserving int-vs-float text formatting.
    Returns (new_node_xml, changed, description)."""

    def fmt(orig_text: str, new_val: float) -> str:
        return str(new_val) if "." in orig_text else str(int(new_val))

    state = {}

    def repl(m: re.Match) -> str:
        x_s, y_s, w_s, h_s = m.group(2), m.group(3), m.group(4), m.group(5)
        new_x = fmt(x_s, float(x_s) + DX)
        new_w = fmt(w_s, float(w_s) + DW)
        state["desc"] = f"x {x_s}→{new_x}  w {w_s}→{new_w}  (y={y_s} h={h_s} unchanged)"
        return f"{m.group(1)}<x>{new_x}</x><y>{y_s}</y><w>{new_w}</w><h>{h_s}</h>{m.group(6)}"

    new_node_xml, n = FRAME_RE.subn(repl, node_xml, count=1)
    return new_node_xml, n > 0, state.get("desc", "")


# ---------------------------------------------------------------------------

xml = tosc_read(TOSC)

name_pat = re.compile(NAME_PROP.format(name="value_label"))
blocks = []
for m in name_pat.finditer(xml):
    nb = find_node_block_at(xml, m.start())
    if nb:
        blocks.append(nb)

print(f"Found {len(blocks)} 'value_label' nodes")

# Already-adjusted check (idempotency): peek at the first block's frame.
if blocks:
    first_xml = xml[blocks[0][0]:blocks[0][1]]
    fm = FRAME_RE.search(first_xml)
    if fm and fm.group(2) == "5" and fm.group(4) == "91":
        print("Frames already at target (x=5, w=91) — nothing to do.")
        sys.exit(0)

dest = backup_tosc(TOSC)
print(f"Backed up to {dest}")

pieces = []
cursor = 0
changed = 0
descriptions = set()
for node_start, node_end in sorted(blocks):
    pieces.append(xml[cursor:node_start])
    new_node_xml, did_change, desc = adjust_frame(xml[node_start:node_end])
    pieces.append(new_node_xml)
    cursor = node_end
    if did_change:
        changed += 1
        descriptions.add(desc)
pieces.append(xml[cursor:])
new_xml = "".join(pieces)

print(f"Adjusted {changed}/{len(blocks)} frames:")
for d in sorted(descriptions):
    print(f"  {d}")

validate_tosc_xml(new_xml)
tosc_write(TOSC, new_xml)
print(f"\nWritten: {TOSC} ({TOSC.stat().st_size:,} bytes compressed)")
