#!/usr/bin/env python3
"""
Add empty script properties to EFX section and button nodes that need them
for toscbuild.py to inject Lua scripts into.

Targets:
  - efx1_section, efx2_section  (GROUP nodes)
  - efx1_b1..b8, efx2_b1..b8  (BUTTON nodes, direct children of their sections)
  - buttons "1" and "2" inside efx_1_chooser and efx_2_chooser
"""
import zlib, sys, re
from pathlib import Path

TOSC = Path(__file__).parent.parent / "TB3.tosc"

SCRIPT_PROP = (
    b"<property type='s'>"
    b"<key><![CDATA[script]]></key>"
    b"<value><![CDATA[]]></value>"
    b"</property>"
)

def add_script_after_name(xml: bytes, node_name: str) -> tuple[bytes, int]:
    """
    Insert SCRIPT_PROP immediately after the first <property> block whose
    <key> CDATA contains node_name (i.e. after the 'name' property of that node),
    but only if the node doesn't already have a script property.
    """
    target = f"<![CDATA[{node_name}]]>".encode()
    count = 0

    pos = 0
    while True:
        idx = xml.find(target, pos)
        if idx == -1:
            break

        # Walk forward to find </property> closing the name property
        end = xml.find(b"</property>", idx)
        if end == -1:
            break
        end += len(b"</property>")

        # Check we're actually inside a 'name' property block, not something else
        prop_start = xml.rfind(b"<property", 0, idx)
        prop_inner = xml[prop_start:end]
        if b"<key><![CDATA[name]]></key>" not in prop_inner:
            pos = end
            continue

        # Check this node doesn't already have a script property nearby
        next_chunk = xml[end:end + 600]
        # If script property exists before the next node boundary, skip
        next_node = next_chunk.find(b"<node ")
        check_range = next_chunk[:next_node] if next_node != -1 else next_chunk
        if b"<key><![CDATA[script]]>" in check_range:
            pos = end
            continue

        # Insert SCRIPT_PROP after the name property closing tag
        xml = xml[:end] + SCRIPT_PROP + xml[end:]
        count += 1
        pos = end + len(SCRIPT_PROP)

    return xml, count


def add_script_for_child(xml: bytes, parent_name: str, child_name: str) -> tuple[bytes, int]:
    """
    Find nodes named child_name that appear as children of parent_name,
    and add script properties to them.
    """
    parent_target = f"<![CDATA[{parent_name}]]>".encode()
    child_target  = f"<![CDATA[{child_name}]]>".encode()
    count = 0

    pos = 0
    while True:
        parent_idx = xml.find(parent_target, pos)
        if parent_idx == -1:
            break

        # Find the closing tag of the parent node (simplified: look for next <node )
        # Walk forward to <children> then find child with name
        children_start = xml.find(b"<children>", parent_idx)
        if children_start == -1:
            break

        # Find child node by name within this parent's children section.
        # We look for child_name within a reasonable range after children_start.
        search_end = children_start + 20000  # generous window

        child_pos = children_start
        while True:
            ci = xml.find(child_target, child_pos, search_end)
            if ci == -1:
                break

            # Verify it's a name property
            prop_start = xml.rfind(b"<property", 0, ci)
            prop_end_tag = xml.find(b"</property>", ci)
            if prop_end_tag == -1:
                break
            prop_end = prop_end_tag + len(b"</property>")
            prop_inner = xml[prop_start:prop_end]

            if b"<key><![CDATA[name]]></key>" not in prop_inner:
                child_pos = prop_end
                continue

            # Check no script property already exists
            next_chunk = xml[prop_end:prop_end + 600]
            next_node = next_chunk.find(b"<node ")
            check_range = next_chunk[:next_node] if next_node != -1 else next_chunk
            if b"<key><![CDATA[script]]>" in check_range:
                child_pos = prop_end
                continue

            xml = xml[:prop_end] + SCRIPT_PROP + xml[prop_end:]
            count += 1
            child_pos = prop_end + len(SCRIPT_PROP)
            # Only patch first occurrence per parent for safety
            break

        pos = parent_idx + 1

    return xml, count


raw = TOSC.read_bytes()
xml = zlib.decompress(raw)
total = 0

# EFX section GROUP nodes
for name in ("efx1_section", "efx2_section"):
    xml, n = add_script_after_name(xml, name)
    print(f"  {name}: +{n}")
    total += n

# EFX buttons (direct children of their section — simple name match is fine
# since these names are unique in the layout)
btn_names = (
    [f"efx1_b{i}" for i in range(1, 9)] +
    [f"efx2_b{i}" for i in range(1, 9)]
)
for name in btn_names:
    xml, n = add_script_after_name(xml, name)
    print(f"  {name}: +{n}")
    total += n

# Chooser buttons named "1" and "2" — use parent-scoped search
for parent in ("efx_1_chooser", "efx_2_chooser"):
    for child in ("1", "2"):
        xml, n = add_script_for_child(xml, parent, child)
        print(f"  {parent}>{child}: +{n}")
        total += n

print(f"Total script properties added: {total}")

compressed = zlib.compress(xml)
TOSC.write_bytes(compressed)
print(f"Written: {TOSC} ({len(compressed)} bytes)")
