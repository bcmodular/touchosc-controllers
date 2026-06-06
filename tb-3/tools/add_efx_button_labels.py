#!/usr/bin/env python3
"""
Phase 4 layout updates:
1. Add script property placeholders to remaining chooser buttons
   (efx_1_chooser buttons '3'-'10'; efx_2_chooser buttons '3'-'9')
2. Add efx1_b_labels / efx2_b_labels GROUP nodes (children of each section)
   containing 8 LABEL nodes positioned over the B1-B8 buttons.
   These labels display per-type button function names set by efx_section.lua.
"""
import zlib, re, uuid
from pathlib import Path

TOSC = Path(__file__).parent.parent / "TB3.tosc"

SCRIPT_PROP = (
    b"<property type='s'>"
    b"<key><![CDATA[script]]></key>"
    b"<value><![CDATA[]]></value>"
    b"</property>"
)

# Button frame positions (relative to each section, confirmed from XML)
EFX1_BTN_FRAMES = {
    1: (5,   166, 105, 36),
    2: (120, 166, 105, 36),
    3: (235, 166, 105, 36),
    4: (350, 166, 105, 36),
    5: (5,   210, 105, 36),
    6: (120, 210, 105, 36),
    7: (235, 210, 105, 36),
    8: (350, 210, 105, 36),
}
EFX2_BTN_FRAMES = {
    1: (12,  164, 105, 36),
    2: (127, 164, 105, 36),
    3: (242, 164, 105, 36),
    4: (357, 164, 105, 36),
    5: (12,  208, 105, 36),
    6: (127, 208, 105, 36),
    7: (242, 208, 105, 36),
    8: (357, 208, 105, 36),
}

def make_label_node(name, x, y, w, h):
    """Generate a small non-interactive LABEL node XML."""
    uid = str(uuid.uuid4())
    return (
        f"<node ID='{uid}' type='LABEL'>"
        f"<properties>"
        f"<property type='b'><key><![CDATA[background]]></key><value>0</value></property>"
        f"<property type='c'><key><![CDATA[color]]></key><value>"
        f"<r>0</r><g>0</g><b>0</b><a>0</a></value></property>"
        f"<property type='i'><key><![CDATA[font]]></key><value>0</value></property>"
        f"<property type='r'><key><![CDATA[frame]]></key><value>"
        f"<x>{x}</x><y>{y}</y><w>{w}</w><h>{h}</h></value></property>"
        f"<property type='b'><key><![CDATA[interactive]]></key><value>0</value></property>"
        f"<property type='b'><key><![CDATA[locked]]></key><value>0</value></property>"
        f"<property type='s'><key><![CDATA[name]]></key><value><![CDATA[{name}]]></value></property>"
        f"<property type='b'><key><![CDATA[outline]]></key><value>0</value></property>"
        f"<property type='i'><key><![CDATA[textAlignH]]></key><value>2</value></property>"
        f"<property type='i'><key><![CDATA[textAlignV]]></key><value>2</value></property>"
        f"<property type='b'><key><![CDATA[textClip]]></key><value>0</value></property>"
        f"<property type='c'><key><![CDATA[textColor]]></key><value>"
        f"<r>1</r><g>1</g><b>1</b><a>0.85</a></value></property>"
        f"<property type='i'><key><![CDATA[textSize]]></key><value>11</value></property>"
        f"<property type='b'><key><![CDATA[visible]]></key><value>1</value></property>"
        f"</properties>"
        f"<values>"
        f"<value><key><![CDATA[text]]></key><locked>0</locked>"
        f"<lockedDefaultCurrent>0</lockedDefaultCurrent>"
        f"<default><![CDATA[]]></default><defaultPull>0</defaultPull></value>"
        f"</values>"
        f"</node>"
    ).encode()


def make_label_group(group_name, frames_dict, section_w=470, section_h=270):
    """Generate a transparent GROUP containing 8 LABEL nodes."""
    uid = str(uuid.uuid4())
    children_xml = b"".join(
        make_label_node(str(i), *frames_dict[i]) for i in range(1, 9)
    )
    return (
        f"<node ID='{uid}' type='GROUP'>"
        f"<properties>"
        f"<property type='r'><key><![CDATA[frame]]></key><value>"
        f"<x>0</x><y>0</y><w>{section_w}</w><h>{section_h}</h></value></property>"
        f"<property type='b'><key><![CDATA[interactive]]></key><value>0</value></property>"
        f"<property type='b'><key><![CDATA[locked]]></key><value>0</value></property>"
        f"<property type='s'><key><![CDATA[name]]></key>"
        f"<value><![CDATA[{group_name}]]></value></property>"
        f"<property type='b'><key><![CDATA[visible]]></key><value>1</value></property>"
        f"</properties><values/><children>"
    ).encode() + children_xml + b"</children></node>"


def add_script_for_child(xml: bytes, parent_name: str, child_name: str) -> tuple[bytes, int]:
    parent_target = f"<![CDATA[{parent_name}]]>".encode()
    child_target  = f"<![CDATA[{child_name}]]>".encode()
    count = 0
    pos = 0
    while True:
        parent_idx = xml.find(parent_target, pos)
        if parent_idx == -1:
            break
        children_start = xml.find(b"<children>", parent_idx)
        if children_start == -1:
            break
        search_end = children_start + 30000  # EFX1 chooser button '10' is at ~20117
        child_pos = children_start
        while True:
            ci = xml.find(child_target, child_pos, search_end)
            if ci == -1:
                break
            prop_start = xml.rfind(b"<property", 0, ci)
            prop_end_tag = xml.find(b"</property>", ci)
            if prop_end_tag == -1:
                break
            prop_end = prop_end_tag + len(b"</property>")
            prop_inner = xml[prop_start:prop_end]
            if b"<key><![CDATA[name]]></key>" not in prop_inner:
                child_pos = prop_end
                continue
            next_chunk = xml[prop_end:prop_end + 600]
            next_node = next_chunk.find(b"<node ")
            check_range = next_chunk[:next_node] if next_node != -1 else next_chunk
            if b"<key><![CDATA[script]]>" in check_range:
                child_pos = prop_end
                continue
            xml = xml[:prop_end] + SCRIPT_PROP + xml[prop_end:]
            count += 1
            child_pos = prop_end + len(SCRIPT_PROP)
            break
        pos = parent_idx + 1
    return xml, count


def insert_group_before_closing_children(xml: bytes, parent_name: str,
                                          group_xml: bytes) -> tuple[bytes, int]:
    """Append group_xml as the last child of the named parent node.

    Uses depth tracking to find the correct </children> for the named parent,
    avoiding false matches on nested children tags inside child nodes.
    """
    target = f"<![CDATA[{parent_name}]]>".encode()
    pos = 0
    while True:
        idx = xml.find(target, pos)
        if idx == -1:
            return xml, 0
        # Find the <children> block of this parent
        children_open = xml.find(b"<children>", idx)
        if children_open == -1:
            pos = idx + 1
            continue
        # Walk forward with depth tracking to find the MATCHING </children>
        search_pos = children_open + len(b"<children>")
        depth = 0
        children_close = None
        i = search_pos
        while i < len(xml):
            if xml[i:i+10] == b"<children>":
                depth += 1
                i += 10
            elif xml[i:i+11] == b"</children>":
                if depth == 0:
                    children_close = i
                    break
                depth -= 1
                i += 11
            else:
                i += 1
        if children_close is None:
            pos = idx + 1
            continue
        # Check the group name doesn't already exist as a direct child
        if group_xml[:60] in xml[children_open:children_close + 100]:
            return xml, 0  # already present
        xml = xml[:children_close] + group_xml + xml[children_close:]
        return xml, 1


raw = TOSC.read_bytes()
xml = zlib.decompress(raw)
total_scripts = 0
total_groups  = 0

# 1. Add script properties to remaining chooser buttons
print("Adding script placeholders to chooser buttons...")
for btn_num in range(3, 11):  # EFX1 buttons 3–10
    xml, n = add_script_for_child(xml, "efx_1_chooser", str(btn_num))
    if n: print(f"  efx_1_chooser/{btn_num}: +{n}")
    total_scripts += n

for btn_num in range(3, 10):  # EFX2 buttons 3–9
    xml, n = add_script_for_child(xml, "efx_2_chooser", str(btn_num))
    if n: print(f"  efx_2_chooser/{btn_num}: +{n}")
    total_scripts += n

# 2. Add button label groups to each section
print("\nAdding button label groups...")

grp1 = make_label_group("efx1_b_labels", EFX1_BTN_FRAMES)
xml, n = insert_group_before_closing_children(xml, "efx1_section", grp1)
print(f"  efx1_b_labels group: +{n}")
total_groups += n

grp2 = make_label_group("efx2_b_labels", EFX2_BTN_FRAMES)
xml, n = insert_group_before_closing_children(xml, "efx2_section", grp2)
print(f"  efx2_b_labels group: +{n}")
total_groups += n

print(f"\nScript props added: {total_scripts}")
print(f"Label groups added: {total_groups}")

compressed = zlib.compress(xml)
TOSC.write_bytes(compressed)
print(f"Written: {TOSC} ({len(compressed)} bytes)")
