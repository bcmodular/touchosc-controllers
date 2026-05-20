#!/usr/bin/env python3
"""One-off migration: 16 preset buttons -> 8 single-column per preset_grid in SP404.tosc."""

import re
import sys
import zlib
from pathlib import Path

PRESETS = 8
PAD_X, PAD_Y0, PAD_W, PAD_H, PAD_STEP = 5, 7, 41, 43, 45
BG_X, BG_Y, BG_W = 2, 4, 49
GRID_W = 49
GRID_H = PAD_Y0 + PRESETS * PAD_STEP - 2
GROUP_W, GROUP_H = 55, GRID_H + 8

NAME_PROP = (
    r"<property type='s'><key><!\[CDATA\[name\]\]></key>"
    r"<value><!\[CDATA\[{name}\]\]></value></property>"
)


def find_node_block(xml: str, name: str, start: int = 0, end=None):
    end = end or len(xml)
    name_pat = NAME_PROP.format(name=re.escape(name))
    m = re.search(name_pat, xml[start:end])
    if not m:
        return None
    mstart = start + m.start()
    node_start = xml.rfind("<node ", start, mstart)
    if node_start == -1:
        return None
    i = node_start
    depth = 0
    while i < end:
        if xml.startswith("<node", i) and (i + 5 >= end or xml[i + 5] in " >"):
            depth += 1
            i += 1
            continue
        if xml.startswith("</node>", i):
            depth -= 1
            i += 7
            if depth == 0:
                return node_start, i
            continue
        i += 1
    return None


def remove_node_by_name(block: str, name: str, node_type: str) -> str:
    while True:
        r = find_node_block(block, name)
        if not r:
            break
        snippet = block[r[0] : r[0] + 80]
        if f"type='{node_type}'" not in snippet:
            break
        block = block[: r[0]] + block[r[1] :]
    return block


def set_frame_after_name(block: str, name: str, x, y, w, h, node_type: str) -> str:
    r = find_node_block(block, name)
    if not r:
        return block
    snippet = block[r[0] : r[0] + 80]
    if f"type='{node_type}'" not in snippet:
        return block
    node = block[r[0] : r[1]]
    frame_re = (
        r"(<property type='r'><key><!\[CDATA\[frame\]\]></key>\s*<value>)"
        r"<x>[^<]*</x><y>[^<]*</y><w>[^<]*</w><h>[^<]*</h>"
        r"(</value></property>)"
    )
    repl = rf"\g<1><x>{x}</x><y>{y}</y><w>{w}</w><h>{h}</h>\g<2>"
    new_node, n = re.subn(frame_re, repl, node, count=1)
    if n == 0:
        return block
    return block[: r[0]] + new_node + block[r[1] :]


def set_int_prop_after_name(block: str, name: str, key: str, val: int, node_type: str) -> str:
    r = find_node_block(block, name)
    if not r:
        return block
    snippet = block[r[0] : r[0] + 80]
    if f"type='{node_type}'" not in snippet:
        return block
    node = block[r[0] : r[1]]
    prop_re = (
        rf"(<property type='i'><key><!\[CDATA\[{re.escape(key)}\]\]></key><value>)"
        r"\d+"
        r"(</value></property>)"
    )
    repl = rf"\g<1>{val}\g<2>"
    new_node, n = re.subn(prop_re, repl, node, count=1)
    if n == 0:
        return block
    return block[: r[0]] + new_node + block[r[1] :]


def transform_preset_grid_block(block: str) -> str:
    for n in range(16, 8, -1):
        block = remove_node_by_name(block, str(n), "BUTTON")
    for n in range(16, 8, -1):
        block = remove_node_by_name(block, str(n), "LABEL")

    for i in range(1, PRESETS + 1):
        y = PAD_Y0 + (i - 1) * PAD_STEP
        block = set_frame_after_name(block, str(i), PAD_X, y, PAD_W, PAD_H, "BUTTON")

    block = set_frame_after_name(
        block, "preset_grid_background_box", BG_X, BG_Y, BG_W, GRID_H, "BOX"
    )
    block = set_frame_after_name(
        block, "perform_preset_label_grid", BG_X, BG_Y, GRID_W, GRID_H, "GRID"
    )
    block = set_int_prop_after_name(block, "perform_preset_label_grid", "gridX", 1, "GRID")
    block = set_int_prop_after_name(block, "perform_preset_label_grid", "gridY", PRESETS, "GRID")
    block = set_frame_after_name(block, "preset_grid", 250, 12, GROUP_W, GROUP_H, "GROUP")
    return block


def find_preset_grid_blocks(xml: str) -> list[tuple[int, int]]:
    blocks = []
    start = 0
    name_pat = NAME_PROP.format(name="preset_grid")
    while True:
        m = re.search(name_pat, xml[start:])
        if not m:
            break
        pos = start + m.start()
        ns = xml.rfind("<node ", start, pos)
        if ns == -1 or "type='GROUP'" not in xml[ns : ns + 80]:
            start = pos + 1
            continue
        r = find_node_block(xml, "preset_grid", ns)
        if not r:
            start = pos + 1
            continue
        blocks.append(r)
        start = r[1]
    return blocks


def migrate(xml: str) -> str:
    blocks = find_preset_grid_blocks(xml)
    if len(blocks) != 5:
        raise RuntimeError(f"expected 5 preset_grid blocks, found {len(blocks)}")
    for r in reversed(blocks):
        old = xml[r[0] : r[1]]
        new = transform_preset_grid_block(old)
        xml = xml[: r[0]] + new + xml[r[1] :]
    return xml


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "sp404-mk2/SP404/SP404.tosc"
    data = path.read_bytes()
    xml = zlib.decompress(data).decode("utf-8")
    new_xml = migrate(xml)
    path.write_bytes(zlib.compress(new_xml.encode("utf-8")))
    print(f"Migrated {path} (5 preset grids -> 8 presets each)")


if __name__ == "__main__":
    main()
