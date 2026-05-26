#!/usr/bin/env python3
"""
Copy layout frames from bus1_group to bus2-5.

Reads frames dynamically from bus1 (never hardcoded). Creates a timestamped backup
under sp404-mk2/SP404/backups/ before writing. Validates XML after changes.

Usage:
  python3 tools/sync_bus1_ui_to_buses.py [path/to/SP404.tosc]
  python3 tools/sync_bus1_ui_to_buses.py --diff-only [path/to/SP404.tosc]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from tosc_layout_utils import (
    backup_tosc,
    collect_frames_et,
    find_bus_group_block,
    find_bus_group_et,
    find_children_section,
    find_direct_child_block,
    find_node_by_path_in_block,
    layout_diff_vs_bus1,
    deduplicate_layout_ids,
    ensure_script_property,
    list_direct_children,
    regenerate_node_ids,
    remove_direct_child,
    set_direct_children,
    set_frame_in_range,
    tosc_read,
    tosc_write,
    validate_tosc_xml,
)

# effect_chooser header strip (bus1 is source of truth for choose_button + colours).
EFFECT_CHOOSER_HEADER_CHILDREN = ("choose_button", "label", "clear_button", "clear_label")
import xml.etree.ElementTree as ET

# Subtrees to keep identical across buses (relative to busN_group).
SYNC_PREFIXES = ("control_group", "effect_chooser", "morph_group")

# Perform-strip morph toggle (bus1 renames choose_* → morph_*).
ON_OFF_MORPH_CHILDREN = ("morph_button", "morph_label")

OLD_EDIT_MODE_SCRIPT = """function onValueChanged(key, value)

  if key == 'x' then
    local editGroup = self.parent.children.edit_group
    
    editGroup.visible = (self.values.x == 1)
    
    local editLabel = self.parent.children.edit_mode_label
    if (self.values.x == 1) then
      editLabel.textColor = Color.fromHexString("000000FF")
    else
      editLabel.textColor =  Color.fromHexString("00E6FFFF")
    end
  end
end"""

NEW_EDIT_MODE_SCRIPT = """function onValueChanged(key, value)
  if key == 'x' then
    local editGroup = self.parent.children.edit_group
    editGroup.visible = (self.values.x == 1)

    local editLabel = self.parent.children.edit_mode_label
    local busTag = json.toTable(self.parent.parent.tag) or {}
    local busNum = tonumber(busTag.busNum) or 1
    local meta = json.toTable(root.tag) or {}
    local accents = meta.busAccentHex or {}
    local accentHex = accents[tostring(busNum)] or "00E6FFFF"

    if self.values.x == 1 then
      editLabel.textColor = Color.fromHexString("000000FF")
    else
      editLabel.textColor = Color.fromHexString(accentHex)
    end
  end
end"""


def get_reference_frames(xml: str) -> dict[str, tuple[str, str, str, str]]:
    root = ET.fromstring(xml.encode("utf-8")).find("node")
    ref = find_bus_group_et(root, 1)
    if ref is None:
        raise RuntimeError("bus1_group not found")
    return collect_frames_et(ref, prefixes=SYNC_PREFIXES)


def apply_frames_to_bus(block: str, frames: dict[str, tuple[str, str, str, str]]) -> str:
    for path, frame in sorted(frames.items(), key=lambda x: -len(x[0])):
        parts = path.split("/")
        r = find_node_by_path_in_block(block, parts)
        if r is None:
            print(f"  WARNING: could not find {path} in target bus", file=sys.stderr)
            continue
        block = set_frame_in_range(block, r[0], r[1], *frame)
    return block


def sync_morph_group(xml: str) -> str:
    """Replace morph_group on buses 2–5 with bus1 subtree (layout, labels, child nodes)."""
    r1 = find_bus_group_block(xml, 1)
    if not r1:
        raise RuntimeError("bus1_group not found")
    block1 = xml[r1[0] : r1[1]]
    mg1_r = find_node_by_path_in_block(block1, ["control_group", "morph_group"])
    if not mg1_r:
        raise RuntimeError("bus1 control_group/morph_group not found")
    ref_morph_xml = block1[mg1_r[0] : mg1_r[1]]

    for bus_num in range(2, 6):
        rb = find_bus_group_block(xml, bus_num)
        if not rb:
            continue
        block = xml[rb[0] : rb[1]]
        mg_r = find_node_by_path_in_block(block, ["control_group", "morph_group"])
        new_morph = regenerate_node_ids(ref_morph_xml)
        if mg_r:
            block = block[: mg_r[0]] + new_morph + block[mg_r[1] :]
        else:
            cg_r = find_node_by_path_in_block(block, ["control_group"])
            if not cg_r:
                print(f"  WARNING: bus{bus_num} control_group not found", file=sys.stderr)
                continue
            cg = block[cg_r[0] : cg_r[1]]
            cs = find_children_section(cg)
            if cs:
                pos, end = cs
                cg = cg[:end] + new_morph + cg[end:]
            else:
                inner_close = cg.rfind("</node>")
                cg = cg[:inner_close] + f"<children>{new_morph}</children>" + cg[inner_close:]
            block = block[: cg_r[0]] + cg + block[cg_r[1] :]
        xml = xml[: rb[0]] + block + xml[rb[1] :]
        print(f"  Synced morph_group bus{bus_num}")
    return xml


def sync_on_off_morph_controls(xml: str) -> str:
    """Replace choose_button/choose_label with bus1 morph_button/morph_label on buses 2–5."""
    r1 = find_bus_group_block(xml, 1)
    if not r1:
        raise RuntimeError("bus1_group not found")
    block1 = xml[r1[0] : r1[1]]
    oo1_r = find_node_by_path_in_block(block1, ["control_group", "on_off_button_group"])
    if not oo1_r:
        raise RuntimeError("bus1 on_off_button_group not found")
    oo1 = block1[oo1_r[0] : oo1_r[1]]
    ref_morph_xmls: list[str] = []
    for name in ON_OFF_MORPH_CHILDREN:
        child_r = find_direct_child_block(oo1, name)
        if not child_r:
            raise RuntimeError(f"bus1 on_off missing {name}")
        ref_morph_xmls.append(ensure_script_property(oo1[child_r[0] : child_r[1]]))

    for bus_num in range(2, 6):
        rb = find_bus_group_block(xml, bus_num)
        if not rb:
            continue
        block = xml[rb[0] : rb[1]]
        oo_r = find_node_by_path_in_block(block, ["control_group", "on_off_button_group"])
        if not oo_r:
            print(f"  WARNING: bus{bus_num} on_off_button_group not found", file=sys.stderr)
            continue
        oo = block[oo_r[0] : oo_r[1]]
        kept: list[str] = []
        for name, node_xml in list_direct_children(oo):
            if name in ("choose_button", "choose_label", *ON_OFF_MORPH_CHILDREN):
                continue
            kept.append(node_xml)
        kept.extend(regenerate_node_ids(x) for x in ref_morph_xmls)
        oo = set_direct_children(oo, kept)
        block = block[: oo_r[0]] + oo + block[oo_r[1] :]
        xml = xml[: rb[0]] + block + xml[rb[1] :]
        print(f"  Synced on_off morph controls bus{bus_num}")
    return xml


def sync_effect_chooser_header(xml: str) -> str:
    """Copy bus1 effect_chooser header nodes to all buses; preserve child order (z-index)."""
    r1 = find_bus_group_block(xml, 1)
    if not r1:
        raise RuntimeError("bus1_group not found")
    block1 = xml[r1[0] : r1[1]]
    ec1_r = find_node_by_path_in_block(block1, ["effect_chooser"])
    if not ec1_r:
        raise RuntimeError("bus1 effect_chooser not found")
    ec1 = block1[ec1_r[0] : ec1_r[1]]

    ref_child_xmls: list[str] = []
    for name, node_xml in list_direct_children(ec1):
        if name == "background":
            continue
        if name == "choose_button":
            node_xml = ensure_script_property(node_xml)
        ref_child_xmls.append(node_xml)

    for bus_num in range(1, 6):
        rb = find_bus_group_block(xml, bus_num)
        if not rb:
            continue
        block = xml[rb[0] : rb[1]]
        ec_r = find_node_by_path_in_block(block, ["effect_chooser"])
        if not ec_r:
            print(f"  WARNING: bus{bus_num} effect_chooser not found", file=sys.stderr)
            continue
        ec = block[ec_r[0] : ec_r[1]]
        child_xmls = [
            regenerate_node_ids(node_xml) for node_xml in ref_child_xmls
        ]
        ec = apply_header_children(ec, child_xmls)
        block = block[: ec_r[0]] + ec + block[ec_r[1] :]
        xml = xml[: rb[0]] + block + xml[rb[1] :]
        print(f"  Synced effect_chooser header bus{bus_num}")
    return xml


def apply_header_children(ec_block: str, child_xmls: list[str]) -> str:
    ec_block = remove_direct_child(ec_block, "background")
    for name in EFFECT_CHOOSER_HEADER_CHILDREN:
        ec_block = remove_direct_child(ec_block, name)
    return set_direct_children(ec_block, child_xmls)


def validate_unique_node_ids(xml: str) -> list[str]:
    from collections import Counter

    ids = re.findall(r"<node ID='([^']+)'", xml)
    dupes = [uid for uid, n in Counter(ids).items() if n > 1]
    if not dupes:
        return []
    return [f"{len(dupes)} duplicate node ID(s), e.g. {dupes[0]}"]


def validate_effect_chooser_header_order(xml: str) -> list[str]:
    """Return problem messages if effect_chooser child order/names differ across buses."""
    r1 = find_bus_group_block(xml, 1)
    if not r1:
        return ["bus1_group not found"]
    block1 = xml[r1[0] : r1[1]]
    ec1_r = find_node_by_path_in_block(block1, ["effect_chooser"])
    if not ec1_r:
        return ["bus1 effect_chooser not found"]
    ec1 = block1[ec1_r[0] : ec1_r[1]]
    ref_order = [n for n, _ in list_direct_children(ec1) if n != "background"]
    problems: list[str] = []
    for bus_num in range(2, 6):
        rb = find_bus_group_block(xml, bus_num)
        if not rb:
            continue
        block = xml[rb[0] : rb[1]]
        ec_r = find_node_by_path_in_block(block, ["effect_chooser"])
        if not ec_r:
            problems.append(f"bus{bus_num}: effect_chooser missing")
            continue
        ec = block[ec_r[0] : ec_r[1]]
        order = [n for n, _ in list_direct_children(ec) if n != "background"]
        if order != ref_order:
            problems.append(f"bus{bus_num} effect_chooser child order {order} != bus1 {ref_order}")
        if find_direct_child_block(ec, "background"):
            problems.append(f"bus{bus_num}: legacy effect_chooser/background still present")
    return problems


def sync_bus(xml: str, bus_num: int, frames: dict) -> str:
    r = find_bus_group_block(xml, bus_num)
    if not r:
        raise RuntimeError(f"bus{bus_num}_group not found")
    block = xml[r[0] : r[1]]
    new_block = apply_frames_to_bus(block, frames)
    return xml[: r[0]] + new_block + xml[r[1] :]


def print_diff_report(xml: str) -> int:
    total = 0
    for bus in range(2, 6):
        diffs = layout_diff_vs_bus1(xml, bus, prefixes=SYNC_PREFIXES)
        print(f"\n=== bus{bus} vs bus1 ({len(diffs)} frame diffs) ===")
        for path, f1, f2 in diffs:
            print(f"  {path}")
            print(f"    bus1: {f1}")
            print(f"    bus{bus}: {f2}")
        total += len(diffs)
    return total


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tosc", nargs="?", help="Path to SP404.tosc")
    parser.add_argument("--diff-only", action="store_true", help="Report diffs, do not write")
    parser.add_argument("--no-backup", action="store_true", help="Skip timestamped backup")
    args = parser.parse_args()

    path = Path(args.tosc) if args.tosc else Path(__file__).resolve().parents[1] / "sp404-mk2/SP404/SP404.tosc"
    if not path.is_file():
        print(f"File not found: {path}", file=sys.stderr)
        return 1

    xml = tosc_read(path)
    validate_tosc_xml(xml)

    if args.diff_only:
        n = print_diff_report(xml)
        print(f"\nTotal diffs (buses 2-5 vs bus1): {n}")
        header_issues = validate_effect_chooser_header_order(xml)
        id_issues = validate_unique_node_ids(xml)
        if header_issues:
            print("\n=== effect_chooser header issues ===")
            for msg in header_issues:
                print(f"  {msg}")
        else:
            print("\neffect_chooser header order: OK (all buses match bus1)")
        if id_issues:
            print("\n=== node ID issues ===")
            for msg in id_issues:
                print(f"  {msg}")
        else:
            print("node IDs: OK (all unique)")
        return 0

    n_before = sum(len(layout_diff_vs_bus1(xml, b, prefixes=SYNC_PREFIXES)) for b in range(2, 6))
    print(f"Frame diffs before sync: {n_before}")

    if not args.no_backup:
        backup = backup_tosc(path)
        print(f"Backup: {backup}")

    xml = sync_effect_chooser_header(xml)
    xml = sync_morph_group(xml)
    xml = sync_on_off_morph_controls(xml)
    xml, n_dup_ids = deduplicate_layout_ids(xml)
    if n_dup_ids:
        print(f"  Regenerated {n_dup_ids} duplicate node ID(s)")

    frames = get_reference_frames(xml)
    print(f"Reference frames from bus1: {len(frames)} nodes under {SYNC_PREFIXES}")

    for bus in range(2, 6):
        xml = sync_bus(xml, bus, frames)
        print(f"  Synced bus{bus}")

    if OLD_EDIT_MODE_SCRIPT in xml:
        xml = xml.replace(OLD_EDIT_MODE_SCRIPT, NEW_EDIT_MODE_SCRIPT)
        print("  Updated edit_mode_button scripts (bus accent colours)")

    validate_tosc_xml(xml)
    tosc_write(path, xml)

    n_after = sum(len(layout_diff_vs_bus1(xml, b, prefixes=SYNC_PREFIXES)) for b in range(2, 6))
    print(f"Frame diffs after sync: {n_after}")
    header_issues = validate_effect_chooser_header_order(xml)
    id_issues = validate_unique_node_ids(xml)
    if header_issues:
        print("effect_chooser header validation FAILED:", file=sys.stderr)
        for msg in header_issues:
            print(f"  {msg}", file=sys.stderr)
        return 1
    if id_issues:
        print("node ID validation FAILED:", file=sys.stderr)
        for msg in id_issues:
            print(f"  {msg}", file=sys.stderr)
        return 1
    print("effect_chooser header order: OK")
    print("node IDs: OK")
    print(f"Wrote {path}")
    return 0 if n_after == 0 else 0  # still success if warnings only


if __name__ == "__main__":
    raise SystemExit(main())
