#!/usr/bin/env python3
"""
One-time fix: move efx1_b_labels and efx2_b_labels from inside efxN_s01
to be direct children of efxN_section.

Root cause: insert_group_before_closing_children in add_efx_button_labels.py
used xml.find(b"</children>") which found the first slot group's </children>
instead of the section's, placing the label group inside s01.
"""
import sys
from pathlib import Path

# Add repo tools to path for tosc_layout_utils
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "tools"))
from tosc_layout_utils import (
    tosc_read, tosc_write,
    find_node_block, find_children_section, find_direct_child_block,
)

TOSC = Path(__file__).parent.parent / "TB3.tosc"


def move_labels_group(xml: str, efx_num: int) -> str:
    section_name = f"efx{efx_num}_section"
    s01_name     = f"efx{efx_num}_s01"
    labels_name  = f"efx{efx_num}_b_labels"

    # ── 1. Locate efxN_section in the full XML ──────────────────────────────
    sec_bounds = find_node_block(xml, section_name)
    if not sec_bounds:
        print(f"  ERROR: {section_name} not found")
        return xml
    sec_start, sec_end = sec_bounds
    sec_xml = xml[sec_start:sec_end]

    # ── 2. Find s01 block within the section ────────────────────────────────
    s01_rel = find_direct_child_block(sec_xml, s01_name)
    if not s01_rel:
        print(f"  ERROR: {s01_name} not found in {section_name}")
        return xml
    s01_xml = sec_xml[s01_rel[0]:s01_rel[1]]

    # ── 3. Look for b_labels INSIDE s01 (this is the misplacement to fix) ───
    # find_direct_child_block searches the full node subtree for the name
    # pattern, so we must verify the match is the top-level node, not a
    # deeper descendant.  We do that by checking the name in s01's OWN
    # children section (one level deep only).
    s01_children = find_children_section(s01_xml)
    if not s01_children:
        print(f"  {s01_name} has no children — nothing to move")
        return xml
    s01_ch_start, s01_ch_end = s01_children
    s01_children_xml = s01_xml[s01_ch_start:s01_ch_end]

    target_pattern = f"<![CDATA[{labels_name}]]>"
    if target_pattern not in s01_children_xml:
        print(f"  {labels_name} is not inside {s01_name} — nothing to move")
        return xml

    # Confirmed it's in s01's children.  Now extract it properly.
    bl_rel = find_direct_child_block(s01_xml, labels_name)
    if not bl_rel:
        print(f"  ERROR: find_direct_child_block failed for {labels_name} in {s01_name}")
        return xml
    bl_xml = s01_xml[bl_rel[0]:bl_rel[1]]
    print(f"  Found {labels_name} inside {s01_name} ({len(bl_xml)} chars) — moving")

    # ── 4. Remove b_labels from s01 ─────────────────────────────────────────
    new_s01_xml = s01_xml[:bl_rel[0]] + s01_xml[bl_rel[1]:]

    # ── 5. Rebuild section: replace s01 with the cleaned s01 ────────────────
    new_sec_xml = (
        sec_xml[:s01_rel[0]]
        + new_s01_xml
        + sec_xml[s01_rel[0] + len(s01_xml):]
    )

    # ── 6. Append b_labels as last direct child of section ──────────────────
    new_sec_children = find_children_section(new_sec_xml)
    if not new_sec_children:
        print(f"  ERROR: can't find children section in rebuilt {section_name}")
        return xml
    _, insert_at = new_sec_children          # position of </children>
    new_sec_xml = new_sec_xml[:insert_at] + bl_xml + new_sec_xml[insert_at:]

    # ── 7. Splice rebuilt section back into full XML ─────────────────────────
    xml = xml[:sec_start] + new_sec_xml + xml[sec_end:]
    print(f"  Done — {labels_name} is now a direct child of {section_name}")
    return xml


xml = tosc_read(TOSC)

for n in [1, 2]:
    print(f"\nefx{n}:")
    xml = move_labels_group(xml, n)

tosc_write(TOSC, xml)
print(f"\nWritten: {TOSC}")
