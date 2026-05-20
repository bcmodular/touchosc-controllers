#!/usr/bin/env python3
"""Shared helpers for .tosc layout backup, validation, and bus UI sync."""

from __future__ import annotations

import re
import shutil
import zlib
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path

NAME_PROP = (
    r"<property type='s'><key><!\[CDATA\[name\]\]></key>"
    r"<value><!\[CDATA\[{name}\]\]></value></property>"
)


def tosc_read(path: Path | str) -> str:
    return zlib.decompress(Path(path).read_bytes()).decode("utf-8")


def tosc_write(path: Path | str, xml: str) -> None:
    Path(path).write_bytes(zlib.compress(xml.encode("utf-8")))


def validate_tosc_xml(xml: str) -> None:
    ET.fromstring(xml.encode("utf-8") if isinstance(xml, str) else xml)


def backup_tosc(path: Path | str, backups_dir: Path | str | None = None) -> Path:
    """Copy .tosc to backups/SP404_YYYYMMDD_HHMMSS.tosc (never use git for layout recovery)."""
    path = Path(path)
    if backups_dir is None:
        backups_dir = path.parent / "backups"
    backups_dir = Path(backups_dir)
    backups_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    dest = backups_dir / f"{path.stem}_{stamp}{path.suffix}"
    shutil.copy2(path, dest)
    return dest


def find_node_block(xml: str, name: str, start: int = 0, end: int | None = None) -> tuple[int, int] | None:
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


def find_children_section(node_block: str) -> tuple[int, int] | None:
    """Return (content_start, content_end) for this node's direct <children> section."""
    values_end = node_block.find("</values>")
    search_from = values_end + len("</values>") if values_end >= 0 else 0
    children_open = node_block.find("<children>", search_from)
    if children_open == -1:
        return None
    pos = children_open + len("<children>")
    depth = 0
    i = pos
    while i < len(node_block):
        if node_block.startswith("<children>", i):
            depth += 1
            i += 10
            continue
        if node_block.startswith("</children>", i):
            if depth == 0:
                return pos, i
            depth -= 1
            i += 11
            continue
        i += 1
    return None


def find_direct_child_block(parent_block: str, child_name: str) -> tuple[int, int] | None:
    """Find a direct child <node> by name within parent_block."""
    section_bounds = find_children_section(parent_block)
    if not section_bounds:
        return None
    pos, children_close = section_bounds
    section = parent_block[pos:children_close]
    offset = pos
    i = 0
    while i < len(section):
        if section.startswith("<node", i) and (i + 5 >= len(section) or section[i + 5] in " >"):
            node_start = i
            depth = 0
            j = i
            while j < len(section):
                if section.startswith("<node", j) and (j + 5 >= len(section) or section[j + 5] in " >"):
                    depth += 1
                    j += 5
                    continue
                if section.startswith("</node>", j):
                    depth -= 1
                    j += 7
                    if depth == 0:
                        node_xml = section[node_start:j]
                        name_pat = NAME_PROP.format(name=re.escape(child_name))
                        if re.search(name_pat, node_xml):
                            return offset + node_start, offset + j
                        i = j
                        break
                    continue
                j += 1
            else:
                break
        else:
            i += 1
    return None


def find_node_by_path_in_block(block: str, path_parts: list[str]) -> tuple[int, int] | None:
    """Resolve a path using direct child links only (avoids false matches in script CDATA)."""
    if not path_parts:
        return None
    rel = find_direct_child_block(block, path_parts[0])
    if not rel:
        return None
    abs_start, abs_end = rel[0], rel[1]
    for part in path_parts[1:]:
        rel = find_direct_child_block(block[abs_start:abs_end], part)
        if not rel:
            return None
        abs_start, abs_end = abs_start + rel[0], abs_start + rel[1]
    return abs_start, abs_end


def set_frame_in_range(block: str, start: int, end: int, x, y, w, h) -> str:
    node = block[start:end]
    frame_re = (
        r"(<property type='r'><key><!\[CDATA\[frame\]\]></key>\s*<value>)"
        r"<x>[^<]*</x><y>[^<]*</y><w>[^<]*</w><h>[^<]*</h>"
        r"(</value></property>)"
    )
    repl = rf"\g<1><x>{x}</x><y>{y}</y><w>{w}</w><h>{h}</h>\g<2>"
    new_node, n = re.subn(frame_re, repl, node, count=1)
    if n == 0:
        return block
    return block[:start] + new_node + block[end:]


def get_prop_et(elem, key: str):
    props = elem.find("properties")
    if props is None:
        return None
    for prop in props.findall("property"):
        k = prop.find("key")
        if k is not None and k.text == key:
            v = prop.find("value")
            if key == "frame":
                return (
                    v.find("x").text,
                    v.find("y").text,
                    v.find("w").text,
                    v.find("h").text,
                )
            return v.text if v is not None else None
    return None


def get_name_et(elem) -> str | None:
    return get_prop_et(elem, "name")


def normalize_bus_path(path: str) -> str:
    """Strip busN_group prefix so paths are comparable across buses."""
    parts = path.split("/")
    if parts and parts[0].endswith("_group"):
        parts = parts[1:]
    return "/".join(parts)


def collect_frames_et(elem, base: str = "", prefixes: tuple[str, ...] = ()) -> dict[str, tuple[str, str, str, str]]:
    """Collect frame tuples keyed by path (e.g. control_group/preset_grid/1)."""
    out: dict[str, tuple[str, str, str, str]] = {}
    name = get_name_et(elem) or elem.get("type", "?")
    path = f"{base}/{name}" if base else name
    rel = normalize_bus_path(path)
    frame = get_prop_et(elem, "frame")
    parts = rel.split("/")
    if frame and (not prefixes or any(p in parts for p in prefixes)):
        out[rel] = frame
    children = elem.find("children")
    if children is not None:
        for child in children.findall("node"):
            out.update(collect_frames_et(child, path, prefixes))
    return out


def find_bus_group_et(root, bus_num: int):
    for elem in root.iter("node"):
        if get_name_et(elem) == f"bus{bus_num}_group":
            return elem
    return None


def find_bus_group_block(xml: str, bus_num: int) -> tuple[int, int] | None:
    return find_node_block(xml, f"bus{bus_num}_group")


def layout_diff_vs_bus1(xml: str, bus_num: int, prefixes: tuple[str, ...] = ("control_group", "effect_chooser")) -> list[tuple[str, tuple, tuple]]:
    root = ET.fromstring(xml.encode("utf-8"))
    bus_root = root.find("node")
    ref = find_bus_group_et(bus_root, 1)
    tgt = find_bus_group_et(bus_root, bus_num)
    ref_frames = collect_frames_et(ref, prefixes=prefixes)
    tgt_frames = collect_frames_et(tgt, prefixes=prefixes)
    diffs = []
    for path in sorted(set(ref_frames) | set(tgt_frames)):
        f1 = ref_frames.get(path)
        f2 = tgt_frames.get(path)
        if f1 != f2:
            diffs.append((path, f1, f2))
    return diffs
