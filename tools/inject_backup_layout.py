#!/usr/bin/env python3
"""One-shot helper: add backup_manager, backup_import_group, and backup UI to SP404.tosc."""

from __future__ import annotations

import re
import sys
import uuid
from pathlib import Path

_REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_REPO / "tools"))
from tosc_layout_utils import backup_tosc, find_children_section, find_direct_child_block, find_node_block, tosc_read, tosc_write, validate_tosc_xml

TOSC = _REPO / "sp404-mk2" / "SP404" / "SP404.tosc"

RENAME_IMPORT_GROUP = {
    "import_group": "backup_import_group",
    "import_button": "backup_import_button",
    "import_label": "backup_import_label",
    "import_information_box": "backup_import_information_box",
    "import_information_label": "backup_import_information_label",
    "exit_button": "backup_import_exit_button",
    "exit_label": "backup_import_exit_label",
}


def _reuuid_nodes(block: str) -> str:
    return re.sub(r"<node ID='[^']+'", lambda _: f"<node ID='{uuid.uuid4()}'", block)


def _rename_nodes(block: str, renames: dict[str, str]) -> str:
    for old, new in renames.items():
        block = block.replace(f"<![CDATA[{old}]]>", f"<![CDATA[{new}]]>")
    return block


def _set_frame_y(block: str, y: float) -> str:
    return re.sub(
        r"(<property type='r'><key><!\[CDATA\[frame\]\]></key><value><x>[^<]+</x><y>)[^<]+(</y>)",
        rf"\g<1>{y}\2",
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


def _clone_button(block: str, new_name: str, y: float) -> str:
    out = _reuuid_nodes(block)
    out = re.sub(
        r"<property type='s'><key><!\[CDATA\[name\]\]></key><value><!\[CDATA\[[^\]]+\]\]></value></property>",
        f"<property type='s'><key><![CDATA[name]]></key><value><![CDATA[{new_name}]]></value></property>",
        out,
        count=1,
    )
    out = _set_frame_y(out, y)
    return _clear_script(out)


def _clone_label(block: str, new_name: str, y: float, text: str) -> str:
    out = _clone_button(block, new_name, y)
    out = re.sub(
        r"(<key><!\[CDATA\[text\]\]></key><locked>0</locked>.*?<default><!\[CDATA\[)[^\]]*(\]\]></default>)",
        rf"\1{text}\2",
        out,
        count=1,
    )
    return out


def inject(xml: str) -> str:
    if find_node_block(xml, "backup_manager"):
        print("backup_manager already present — skipping layout inject")
        return xml

    import_grp = find_node_block(xml, "import_group")
    if not import_grp:
        raise SystemExit("import_group not found")
    import_block = xml[import_grp[0] : import_grp[1]]
    backup_import = _reuuid_nodes(_rename_nodes(import_block, RENAME_IMPORT_GROUP))
    backup_import = _clear_script(backup_import)
    backup_import = backup_import.replace(
        "Waiting for Preset Import from OSC. Please start sending...",
        "Waiting for backup import from OSC. Please start sending...",
    )
    backup_import = backup_import.replace(
        "<value><![CDATA[presets]]></value><scaleMin>0</scaleMin><scaleMax>1</scaleMax></partial></path><arguments></arguments>",
        "<value><![CDATA[sp404]]></value><scaleMin>0</scaleMin><scaleMax>1</scaleMax></partial>"
        "<partial><type>CONSTANT</type><conversion>STRING</conversion>"
        "<value><![CDATA[backup]]></value><scaleMin>0</scaleMin><scaleMax>1</scaleMax></partial></path>"
        "<arguments><argument><var><![CDATA[x]]></var><type>STRING</type></argument></arguments>",
    )
    insert_at = import_grp[1]
    xml = xml[:insert_at] + backup_import + xml[insert_at:]

    default = find_node_block(xml, "default_manager")
    if not default:
        raise SystemExit("default_manager not found")
    dm_block = xml[default[0] : default[1]]
    backup_mgr = _reuuid_nodes(dm_block)
    backup_mgr = re.sub(
        r"<property type='s'><key><!\[CDATA\[name\]\]></key><value><!\[CDATA\[default_manager\]\]></value></property>",
        "<property type='s'><key><![CDATA[name]]></key><value><![CDATA[backup_manager]]></value></property>",
        backup_mgr,
        count=1,
    )
    backup_mgr = _set_frame_y(backup_mgr, -133)
    backup_mgr = _clear_script(backup_mgr)
    insert_at = default[1]
    xml = xml[:insert_at] + backup_mgr + xml[insert_at:]

    all_presets = find_node_block(xml, "all_presets_group")
    if not all_presets:
        raise SystemExit("all_presets_group not found")
    ap_block = xml[all_presets[0] : all_presets[1]]
    cs = find_children_section(ap_block)
    if not cs:
        raise SystemExit("all_presets_group has no children section")

    export_btn = find_direct_child_block(ap_block, "preset_export_button")
    import_btn = find_direct_child_block(ap_block, "preset_import_button")
    export_lbl = find_direct_child_block(ap_block, "preset_export_label")
    import_lbl = find_direct_child_block(ap_block, "preset_import_label")
    if not all([export_btn, import_btn, export_lbl, import_lbl]):
        raise SystemExit("preset export/import nodes not found in all_presets_group")

    new_nodes = (
        _clone_button(ap_block[export_btn[0] : export_btn[1]], "backup_export_button", 66)
        + _clone_label(ap_block[export_lbl[0] : export_lbl[1]], "backup_export_label", 66, "Export backup")
        + _clone_button(ap_block[import_btn[0] : import_btn[1]], "backup_import_open_button", 66)
        + _clone_label(ap_block[import_lbl[0] : import_lbl[1]], "backup_import_open_label", 66, "Import backup")
    )
    insert_at = all_presets[0] + cs[1]
    xml = xml[:insert_at] + new_nodes + xml[insert_at:]

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
