#!/usr/bin/env python3
"""One-shot helper: add scene_manager + scene_grid to SP404.tosc (run from repo root)."""

from __future__ import annotations

import re
import sys
import uuid
from pathlib import Path

_REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_REPO / "tools"))
from tosc_layout_utils import backup_tosc, find_children_section, find_node_block, tosc_read, tosc_write, validate_tosc_xml

TOSC = _REPO / "sp404-mk2" / "SP404" / "SP404.tosc"
NUM_SCENES = 16


def _uid() -> str:
    return str(uuid.uuid4())


def _prop_bool(key: str, val: int) -> str:
    return f"<property type='b'><key><![CDATA[{key}]]></key><value>{val}</value></property>"


def _prop_int(key: str, val: int) -> str:
    return f"<property type='i'><key><![CDATA[{key}]]></key><value>{val}</value></property>"


def _prop_float(key: str, val: float) -> str:
    return f"<property type='f'><key><![CDATA[{key}]]></key><value>{val}</value></property>"


def _prop_str(key: str, val: str) -> str:
    return f"<property type='s'><key><![CDATA[{key}]]></key><value><![CDATA[{val}]]></value></property>"


def _prop_color(r: float, g: float, b: float, a: float = 1.0) -> str:
    return (
        f"<property type='c'><key><![CDATA[color]]></key>"
        f"<value><r>{r}</r><g>{g}</g><b>{b}</b><a>{a}</a></value></property>"
    )


def _prop_frame(x: float, y: float, w: float, h: float) -> str:
    return (
        f"<property type='r'><key><![CDATA[frame]]></key>"
        f"<value><x>{x}</x><y>{y}</y><w>{w}</w><h>{h}</h></value></property>"
    )


def _values_touch() -> str:
    return (
        "<values><value><key><![CDATA[touch]]></key><locked>0</locked>"
        "<lockedDefaultCurrent>0</lockedDefaultCurrent>"
        "<default><![CDATA[false]]></default><defaultPull>0</defaultPull></value></values>"
    )


def _values_button_x() -> str:
    return (
        "<values>"
        "<value><key><![CDATA[x]]></key><locked>0</locked>"
        "<lockedDefaultCurrent>0</lockedDefaultCurrent>"
        "<default><![CDATA[0]]></default><defaultPull>0</defaultPull></value>"
        "<value><key><![CDATA[touch]]></key><locked>0</locked>"
        "<lockedDefaultCurrent>0</lockedDefaultCurrent>"
        "<default><![CDATA[false]]></default><defaultPull>0</defaultPull></value>"
        "</values>"
    )


def _common_props(name: str, frame: tuple[float, float, float, float], *, visible: int = 1, interactive: int = 1) -> str:
    x, y, w, h = frame
    return "".join(
        [
            _prop_bool("background", 1),
            _prop_frame(x, y, w, h),
            _prop_bool("grabFocus", 0),
            _prop_bool("interactive", interactive),
            _prop_bool("locked", 0),
            _prop_str("name", name),
            _prop_int("orientation", 0),
            _prop_bool("outline", 1),
            _prop_int("outlineStyle", 0),
            _prop_int("pointerPriority", 0),
            _prop_bool("visible", visible),
        ]
    )


def _storage_label(name: str, y: float) -> str:
    props = "".join(
        [
            _prop_bool("background", 0),
            _prop_frame(5, y, 100, 20),
            _prop_bool("grabFocus", 0),
            _prop_bool("interactive", 0),
            _prop_bool("locked", 1),
            _prop_str("name", name),
            _prop_int("orientation", 0),
            _prop_bool("outline", 0),
            _prop_int("outlineStyle", 0),
            _prop_int("pointerPriority", 0),
            _prop_str("script", ""),
            _prop_str("tag", ""),
            _prop_bool("visible", 0),
            _prop_int("font", 0),
            _prop_int("textSize", 12),
            _prop_color(1, 1, 1, 1),
            _prop_int("textAlignH", 1),
            _prop_int("textAlignV", 1),
        ]
    )
    return (
        f"<node ID='{_uid()}' type='LABEL'><properties>{props}</properties>"
        f"{_values_touch()}</node>"
    )


def _scene_button(name: str, scene_num: int, x: float, y: float) -> str:
    props = "".join(
        [
            _prop_bool("background", 1),
            _prop_int("buttonType", 0),
            _prop_color(0.55, 0.55, 0.55, 1),
            _prop_float("cornerRadius", 1),
            _prop_frame(x, y, 48, 42),
            _prop_bool("grabFocus", 0),
            _prop_bool("interactive", 1),
            _prop_bool("locked", 0),
            _prop_str("name", name),
            _prop_int("orientation", 0),
            _prop_bool("outline", 0),
            _prop_int("outlineStyle", 1),
            _prop_int("pointerPriority", 0),
            _prop_bool("press", 1),
            _prop_bool("release", 1),
            _prop_str("script", ""),
            _prop_bool("valuePosition", 0),
            _prop_bool("visible", 1),
            _prop_str("tabLabel", str(scene_num)),
        ]
    )
    return (
        f"<node ID='{_uid()}' type='BUTTON'><properties>{props}</properties>"
        f"{_values_button_x()}</node>"
    )


def _scene_grid_node() -> str:
    children = [
        (
            "<node ID='"
            + _uid()
            + "' type='BOX'><properties>"
            + _prop_bool("background", 1)
            + _prop_color(0.8, 0.8, 0.8, 1)
            + _prop_float("cornerRadius", 1)
            + _prop_frame(2, 4, 108, 368)
            + _prop_bool("grabFocus", 1)
            + _prop_bool("interactive", 0)
            + _prop_bool("locked", 0)
            + _prop_str("name", "scene_grid_background_box")
            + _prop_int("orientation", 0)
            + _prop_bool("outline", 1)
            + _prop_int("outlineStyle", 0)
            + _prop_int("pointerPriority", 0)
            + _prop_int("shape", 1)
            + _prop_bool("visible", 1)
            + "</properties>"
            + _values_touch()
            + "</node>"
        )
    ]
    row_h = 45
    for slot in range(1, 9):
        y = 7 + (slot - 1) * row_h
        children.append(_scene_button(str(slot), slot, 5, y))
        children.append(_scene_button(str(8 + slot), 8 + slot, 58, y))

    inner = "".join(children)
    props = "".join(
        [
            _prop_bool("background", 1),
            _prop_color(0, 0, 0, 0),
            _prop_float("cornerRadius", 1),
            _prop_frame(1620, 30, 115, 380),
            _prop_bool("grabFocus", 0),
            _prop_bool("interactive", 0),
            _prop_bool("locked", 0),
            _prop_str("name", "scene_grid"),
            _prop_int("orientation", 0),
            _prop_bool("outline", 1),
            _prop_int("outlineStyle", 0),
            _prop_int("pointerPriority", 0),
            _prop_str("script", ""),
            _prop_str("tag", ""),
            _prop_bool("visible", 1),
        ]
    )
    return (
        f"<node ID='{_uid()}' type='GROUP'><properties>{props}</properties>"
        f"{_values_touch()}<children>{inner}</children></node>"
    )


def _scene_manager_node() -> str:
    labels = "".join(_storage_label(f"{i:02d}", 5 + (i - 1) * 22) for i in range(1, NUM_SCENES + 1))
    props = "".join(
        [
            _prop_bool("background", 1),
            _prop_color(0, 0, 0, 0),
            _prop_float("cornerRadius", 1),
            _prop_frame(2230, -59, 118, 400),
            _prop_bool("grabFocus", 0),
            _prop_bool("interactive", 0),
            _prop_bool("locked", 0),
            _prop_str("name", "scene_manager"),
            _prop_int("orientation", 0),
            _prop_bool("outline", 1),
            _prop_int("outlineStyle", 0),
            _prop_int("pointerPriority", 0),
            _prop_str("script", ""),
            _prop_bool("visible", 1),
        ]
    )
    return (
        f"<node ID='{_uid()}' type='GROUP'><properties>{props}</properties>"
        f"{_values_touch()}<children>{labels}</children></node>"
    )


def inject(xml: str) -> str:
    if find_node_block(xml, "scene_grid") or find_node_block(xml, "scene_manager"):
        print("scene_grid or scene_manager already present — skipping layout inject")
        return xml

    perform = find_node_block(xml, "perform_group")
    if not perform:
        raise SystemExit("perform_group not found")
    pblock = xml[perform[0] : perform[1]]
    cs = find_children_section(pblock)
    if not cs:
        raise SystemExit("perform_group has no children section")
    insert_at = perform[0] + cs[1]
    xml = xml[:insert_at] + _scene_grid_node() + xml[insert_at:]

    root = find_node_block(xml, "group")
    if not root:
        raise SystemExit("root group not found")
    rblock = xml[root[0] : root[1]]
    cs = find_children_section(rblock)
    if not cs:
        raise SystemExit("root has no children section")
    insert_at = root[0] + cs[1]
    xml = xml[:insert_at] + _scene_manager_node() + xml[insert_at:]

    return xml


def main() -> None:
    xml = tosc_read(TOSC)
    xml = inject(xml)
    validate_tosc_xml(xml)
    backup = backup_tosc(TOSC)
    print(f"Backup: {backup}")
    tosc_write(TOSC, xml)
    print(f"Updated: {TOSC}")


if __name__ == "__main__":
    main()
