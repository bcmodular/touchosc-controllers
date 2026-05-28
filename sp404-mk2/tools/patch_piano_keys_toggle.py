#!/usr/bin/env python3
"""Set piano keys (keys/white/*, keys/black/*) to toggle press mode like chord pads."""

from __future__ import annotations

import re
import sys
from pathlib import Path

_TOOLS = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(_TOOLS))

from tosc_layout_utils import (  # noqa: E402
    backup_tosc,
    find_direct_child_block,
    find_node_block,
    tosc_read,
    tosc_write,
    validate_tosc_xml,
)
from toscbuild import _list_direct_child_blocks  # noqa: E402

_BUTTON_TYPE = re.compile(
    r"(<key><!\[CDATA\[buttonType\]\]></key><value>)\d+(</value>)"
)
_RELEASE = re.compile(
    r"(<key><!\[CDATA\[release\]\]></key><value>)\d+(</value>)"
)
_PRESS = re.compile(
    r"(<key><!\[CDATA\[press\]\]></key><value>)\d+(</value>)"
)


def _patch_button_block(node_xml: str) -> str:
    if "<key><![CDATA[buttonType]]></key>" not in node_xml:
        return node_xml
    node_xml = _BUTTON_TYPE.sub(r"\g<1>2\2", node_xml, count=1)
    node_xml = _PRESS.sub(r"\g<1>1\2", node_xml, count=1)
    node_xml = _RELEASE.sub(r"\g<1>0\2", node_xml, count=1)
    return node_xml


def patch_piano_keys_toggle(xml: str) -> tuple[str, int]:
    keys = find_node_block(xml, "keys")
    if not keys:
        raise ValueError("keys node not found")
    keys_block = xml[keys[0] : keys[1]]
    patched = 0
    out_parts = []
    pos = 0
    for row_name in ("white", "black"):
        row = find_direct_child_block(keys_block, row_name)
        if not row:
            continue
        row_block = keys_block[row[0] : row[1]]
        for _name, cstart, cend in _list_direct_child_blocks(row_block):
            child = row_block[cstart:cend]
            new_child = _patch_button_block(child)
            if new_child != child:
                patched += 1
            abs_start = keys[0] + row[0] + cstart
            abs_end = keys[0] + row[0] + cend
            out_parts.append((abs_start, abs_end, new_child))
    if not out_parts:
        return xml, 0
    result = xml
    for start, end, replacement in sorted(out_parts, key=lambda t: t[0], reverse=True):
        result = result[:start] + replacement + result[end:]
    return result, patched


def main() -> None:
    tosc_path = Path(__file__).resolve().parent.parent / "SP404.tosc"
    xml = tosc_read(tosc_path)
    patched_xml, count = patch_piano_keys_toggle(xml)
    validate_tosc_xml(patched_xml)
    backup_tosc(tosc_path)
    tosc_write(tosc_path, patched_xml)
    print(f"Patched {count} piano key buttons to toggle press mode.")


if __name__ == "__main__":
    main()
