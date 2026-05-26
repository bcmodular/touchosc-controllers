#!/usr/bin/env python3
"""Add bus_lock_button + bus_lock_label under control_group on all buses (clone from edit_mode)."""

from __future__ import annotations

import re
import sys
import uuid
from pathlib import Path

_SP404_ROOT = Path(__file__).resolve().parents[1]
_REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO_ROOT / "tools"))

from tosc_layout_utils import (  # noqa: E402
    backup_tosc,
    find_children_section,
    find_direct_child_block,
    find_node_by_path_in_block,
    find_bus_group_block,
    list_direct_children,
    regenerate_node_ids,
    set_direct_children,
    tosc_read,
    tosc_write,
    validate_tosc_xml,
)

TOSC = _SP404_ROOT / "SP404.tosc"
PADLOCK = "\U0001F512"
LOCK_Y_OFFSET = 31


def _reuuid(block: str) -> str:
    return re.sub(r"<node ID='[^']+'", lambda _: f"<node ID='{uuid.uuid4()}'", block)


def _rename_node(block: str, new_name: str) -> str:
    return re.sub(
        r"(<key><!\[CDATA\[name\]\]></key><value><!\[CDATA\[)[^\]]+(\]\]></value>)",
        rf"\g<1>{new_name}\2",
        block,
        count=1,
    )


def _offset_frame_y(block: str, dy: float) -> str:
    def repl(m: re.Match[str]) -> str:
        y = float(m.group(2)) + dy
        return f"{m.group(1)}{y}{m.group(3)}"

    return re.sub(
        r"(<key><!\[CDATA\[frame\]\]></key><value><x>[^<]+</x><y>)([^<]+)(</y>)",
        repl,
        block,
        count=1,
    )


def _set_label_text(block: str, text: str) -> str:
    return re.sub(
        r"(<key><!\[CDATA\[text\]\]></key><locked>0</locked>.*?<default><!\[CDATA\[)[^\]]*(\]\]></default>)",
        rf"\g<1>{text}\2",
        block,
        count=1,
    )


def _clear_script(block: str) -> str:
    return re.sub(
        r"(<key><!\[CDATA\[script\]\]></key><value><!\[CDATA\[)[^\]]*(\]\]></value>)",
        r"\1\2",
        block,
        count=1,
    )


def _clone_lock_nodes_from_edit(edit_btn_xml: str, edit_lbl_xml: str) -> tuple[str, str]:
    lock_btn = _clear_script(_offset_frame_y(_rename_node(_reuuid(edit_btn_xml), "bus_lock_button"), LOCK_Y_OFFSET))
    lock_lbl = _offset_frame_y(_rename_node(_reuuid(edit_lbl_xml), "bus_lock_label"), LOCK_Y_OFFSET + 6)
    lock_lbl = _set_label_text(lock_lbl, PADLOCK)
    return lock_btn, lock_lbl


def inject_bus_lock_on_block(bus_block: str, lock_btn: str, lock_lbl: str) -> str:
    cg_r = find_node_by_path_in_block(bus_block, ["control_group"])
    if not cg_r:
        raise RuntimeError("control_group not found in bus block")
    cg = bus_block[cg_r[0] : cg_r[1]]
    if find_direct_child_block(cg, "bus_lock_button"):
        return bus_block

    children = [xml for _, xml in list_direct_children(cg)]
    children.append(lock_btn)
    children.append(lock_lbl)
    cg = set_direct_children(cg, children)
    return bus_block[: cg_r[0]] + cg + bus_block[cg_r[1] :]


def inject(xml: str) -> str:
    r1 = find_bus_group_block(xml, 1)
    if not r1:
        raise SystemExit("bus1_group not found")
    block1 = xml[r1[0] : r1[1]]
    cg_r = find_node_by_path_in_block(block1, ["control_group"])
    if not cg_r:
        raise SystemExit("bus1 control_group not found")
    cg = block1[cg_r[0] : cg_r[1]]

    edit_btn_r = find_direct_child_block(cg, "edit_mode_button")
    edit_lbl_r = find_direct_child_block(cg, "edit_mode_label")
    if not edit_btn_r or not edit_lbl_r:
        raise SystemExit("edit_mode_button or edit_mode_label not found on bus1")

    ref_lock_btn, ref_lock_lbl = _clone_lock_nodes_from_edit(
        cg[edit_btn_r[0] : edit_btn_r[1]],
        cg[edit_lbl_r[0] : edit_lbl_r[1]],
    )

    for bus_num in range(1, 6):
        rb = find_bus_group_block(xml, bus_num)
        if not rb:
            print(f"  WARNING: bus{bus_num}_group not found", file=sys.stderr)
            continue
        block = xml[rb[0] : rb[1]]
        btn = ref_lock_btn if bus_num == 1 else regenerate_node_ids(ref_lock_btn)
        lbl = ref_lock_lbl if bus_num == 1 else regenerate_node_ids(ref_lock_lbl)
        new_block = inject_bus_lock_on_block(block, btn, lbl)
        if new_block != block:
            xml = xml[: rb[0]] + new_block + xml[rb[1] :]
            print(f"  Added bus lock controls on bus{bus_num}")
        else:
            print(f"  bus{bus_num}: bus_lock_button already present")
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
