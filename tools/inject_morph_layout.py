#!/usr/bin/env python3
"""Add or replace morph_group UI under control_group on all busN_group nodes in SP404.tosc."""

from __future__ import annotations

import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_REPO / "tools"))
from tosc_layout_utils import (
    backup_tosc,
    find_bus_group_block,
    find_children_section,
    find_direct_child_block,
    find_node_by_path_in_block,
    regenerate_node_ids,
    tosc_read,
    tosc_write,
    validate_tosc_xml,
)
from toscbuild import _build_node_xml

TOSC = _REPO / "sp404-mk2" / "SP404" / "SP404.tosc"

# Fader hidden until morph on + target selected (preset_grid_manager syncMorphControlsUi).
MORPH_GROUP_DEF = {
    "type": "GROUP",
    "name": "morph_group",
    "frame": [5, 530, 180, 52],
    "color": [0.15, 0.15, 0.15, 1],
    "interactive": False,
    "grabFocus": False,
    "properties": {
        "background": True,
        "outline": True,
        "outlineStyle": 0,
    },
    "children": [
        {
            "type": "LABEL",
            "name": "morph_target_label",
            "frame": [4, 4, 72, 18],
            "text": "Target —",
            "interactive": False,
            "grabFocus": False,
            "properties": {
                "textSize": 13,
                "textAlignH": 1,
                "textAlignV": 1,
                "textClip": False,
                "textColor": [1, 1, 1, 1],
                "color": [0, 0, 0, 0],
            },
        },
        {
            "type": "FADER",
            "name": "morph_amount_fader",
            "frame": [80, 6, 96, 38],
            "visible": False,
            "color": [0.2, 0.2, 0.2, 1],
            "properties": {
                "orientation": 1,
                "outline": True,
                "response": 0,
                "responseFactor": 100,
            },
        },
    ],
}


def _morph_group_xml() -> str:
    return _build_node_xml(MORPH_GROUP_DEF)


def inject_bus(block: str, replace: bool = True) -> str:
    cg = find_node_by_path_in_block(block, ["control_group"])
    if not cg:
        raise RuntimeError("control_group not found")
    cg_xml = block[cg[0] : cg[1]]

    if replace:
        mg = find_direct_child_block(cg_xml, "morph_group")
        if mg:
            cg_xml = cg_xml[: mg[0]] + cg_xml[mg[1] :]
    elif find_direct_child_block(cg_xml, "morph_group"):
        return block

    cs = find_children_section(cg_xml)
    morph_xml = _morph_group_xml()
    if not cs:
        inner_close = cg_xml.rfind("</node>")
        new_cg = cg_xml[:inner_close] + f"<children>{morph_xml}</children>" + cg_xml[inner_close:]
    else:
        pos, children_close = cs
        new_cg = cg_xml[:children_close] + morph_xml + cg_xml[children_close:]

    return block[: cg[0]] + new_cg + block[cg[1] :]


def main() -> int:
    xml = tosc_read(TOSC)
    backup = backup_tosc(TOSC)
    print(f"Backup: {backup}")
    for bus in range(1, 6):
        r = find_bus_group_block(xml, bus)
        if not r:
            print(f"bus{bus}_group not found", file=sys.stderr)
            return 1
        block = xml[r[0] : r[1]]
        block = inject_bus(block, replace=True)
        block = regenerate_node_ids(block)
        xml = xml[: r[0]] + block + xml[r[1] :]
        print(f"bus{bus}: morph_group replaced")
    validate_tosc_xml(xml)
    tosc_write(TOSC, xml)
    print(f"Updated {TOSC}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
