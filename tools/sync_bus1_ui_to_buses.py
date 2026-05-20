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
import sys
from pathlib import Path

from tosc_layout_utils import (
    backup_tosc,
    collect_frames_et,
    find_bus_group_block,
    find_bus_group_et,
    find_node_by_path_in_block,
    layout_diff_vs_bus1,
    set_frame_in_range,
    tosc_read,
    tosc_write,
    validate_tosc_xml,
)
import xml.etree.ElementTree as ET

# Subtrees to keep identical across buses (relative to busN_group).
SYNC_PREFIXES = ("control_group", "effect_chooser")

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
        return 0

    n_before = sum(len(layout_diff_vs_bus1(xml, b, prefixes=SYNC_PREFIXES)) for b in range(2, 6))
    print(f"Frame diffs before sync: {n_before}")

    if not args.no_backup:
        backup = backup_tosc(path)
        print(f"Backup: {backup}")

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
    print(f"Wrote {path}")
    return 0 if n_after == 0 else 0  # still success if warnings only


if __name__ == "__main__":
    raise SystemExit(main())
