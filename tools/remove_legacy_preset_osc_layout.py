#!/usr/bin/env python3
"""Remove legacy /presets OSC UI from SP404.tosc (import_group + preset export/import buttons)."""

from __future__ import annotations

import re
import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_REPO / "tools"))
from tosc_layout_utils import backup_tosc, find_node_block, tosc_read, tosc_write, validate_tosc_xml

TOSC = _REPO / "sp404-mk2" / "SP404" / "SP404.tosc"

LEGACY_NODES = [
    "import_group",
    "preset_export_button",
    "preset_export_label",
    "preset_import_button",
    "preset_import_label",
]

BACKUP_BUTTONS_AT_Y36 = [
    "backup_export_button",
    "backup_export_label",
    "backup_import_open_button",
    "backup_import_open_label",
]


def _set_frame_y(block: str, y: float) -> str:
    return re.sub(
        r"(<property type='r'><key><!\[CDATA\[frame\]\]></key><value><x>[^<]+</x><y>)[^<]+(</y>)",
        rf"\g<1>{y}\2",
        block,
        count=1,
    )


def remove_node(xml: str, name: str) -> str:
    bounds = find_node_block(xml, name)
    if not bounds:
        print(f"  skip (not found): {name}")
        return xml
    print(f"  removed: {name}")
    return xml[: bounds[0]] + xml[bounds[1] :]


def _set_label_text(block: str, text: str) -> str:
    return re.sub(
        r"(<key><!\[CDATA\[text\]\]></key><locked>0</locked>.*?<default><!\[CDATA\[)[^\]]*(\]\]></default>)",
        rf"\1{text}\2",
        block,
        count=1,
    )


def reposition_backup_buttons(xml: str) -> str:
    label_text = {
        "backup_export_label": "Export",
        "backup_import_open_label": "Import",
    }
    for name in BACKUP_BUTTONS_AT_Y36:
        bounds = find_node_block(xml, name)
        if not bounds:
            continue
        block = xml[bounds[0] : bounds[1]]
        block = _set_frame_y(block, 36)
        if name in label_text:
            block = _set_label_text(block, label_text[name])
        xml = xml[: bounds[0]] + block + xml[bounds[1] :]
        print(f"  moved to y=36: {name}")
    return xml


def main() -> None:
    xml = tosc_read(TOSC)
    for name in LEGACY_NODES:
        xml = remove_node(xml, name)
    xml = reposition_backup_buttons(xml)
    validate_tosc_xml(xml)
    dest = backup_tosc(TOSC)
    print(f"Backup: {dest}")
    tosc_write(TOSC, xml)
    print(f"Updated: {TOSC}")


if __name__ == "__main__":
    main()
