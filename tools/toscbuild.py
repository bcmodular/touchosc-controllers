#!/usr/bin/env python3
"""
toscbuild — TouchOSC code-first build pipeline.

Injects external Lua scripts into .tosc files based on a build manifest.
Preserves .tosc XML byte-for-byte outside of script content by using
string-level replacement (no XML parser for writes).

Usage:
    python3 toscbuild.py build <dir>       # Inject Lua scripts into .tosc
    python3 toscbuild.py extract <file>    # Extract all scripts to files
    python3 toscbuild.py tree <file>       # Print node hierarchy
    python3 toscbuild.py dev <dir>         # Watch + rebuild + open TouchOSC
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import zlib
import xml.etree.ElementTree as ET


# ---------------------------------------------------------------------------
# Core I/O
# ---------------------------------------------------------------------------

def tosc_read(path):
    """Read a .tosc file → decompressed XML string."""
    with open(path, "rb") as f:
        compressed = f.read()
    return zlib.decompress(compressed).decode("utf-8")


def tosc_write(path, xml_str):
    """Compress an XML string → write a .tosc file."""
    compressed = zlib.compress(xml_str.encode("utf-8"))
    with open(path, "wb") as f:
        f.write(compressed)


# ---------------------------------------------------------------------------
# String-level script replacement (preserves CDATA)
# ---------------------------------------------------------------------------

# Regex to match a <property> block that contains a name CDATA value.
# We use this to locate nodes by their name property.
_NAME_PROP_RE = (
    r"<property type='s'><key><!\[CDATA\[name\]\]></key>"
    r"<value><!\[CDATA\[{name}\]\]></value></property>"
)

# Regex to match the script property's CDATA content within a <properties> block.
_SCRIPT_CDATA_RE = (
    r"(<property type='s'><key><!\[CDATA\[script\]\]></key>"
    r"<value><!\[CDATA\[)(.*?)(\]\]></value></property>)"
)


def _find_node_range(xml_str, node_name):
    """Find the start/end byte offsets of the <node> containing a name property
    matching `node_name`. Returns (start, end) or None.

    For uniqueness, we match the name property and then walk backwards to find
    the enclosing <node ...> tag and forwards to find its </node> or the end
    of its <properties> block (we only need the properties section).
    """
    name_pattern = _NAME_PROP_RE.format(name=re.escape(node_name))
    m = re.search(name_pattern, xml_str)
    if not m:
        return None

    # Walk backwards from the name property to find the enclosing <node
    search_start = xml_str.rfind("<node ", 0, m.start())
    if search_start == -1:
        return None

    # Find the end of this node's <properties> block.
    # The properties block ends with </properties>.
    props_end = xml_str.find("</properties>", m.end())
    if props_end == -1:
        return None

    return (search_start, props_end + len("</properties>"))


def _find_root_node_range(xml_str):
    """Find the properties range for the root <node> (first child of <lexml>)."""
    # The root node is the first <node after <lexml ...>
    m = re.search(r"<lexml[^>]*>\s*<node ", xml_str)
    if not m:
        return None

    node_start = xml_str.find("<node ", m.start())
    props_end = xml_str.find("</properties>", node_start)
    if props_end == -1:
        return None

    return (node_start, props_end + len("</properties>"))


def replace_script(xml_str, node_name, lua_content, is_root=False):
    """Replace the script CDATA content for a node identified by name.

    Returns the modified XML string, or raises ValueError if the node or
    script property is not found.
    """
    if is_root:
        node_range = _find_root_node_range(xml_str)
        label = "root node"
    else:
        node_range = _find_node_range(xml_str, node_name)
        label = f"node '{node_name}'"

    if node_range is None:
        raise ValueError(f"Could not find {label} in .tosc XML")

    start, end = node_range
    props_section = xml_str[start:end]

    # Find and replace the script CDATA content within this section
    script_match = re.search(_SCRIPT_CDATA_RE, props_section, re.DOTALL)
    if script_match is None:
        raise ValueError(f"No script property found in {label}")

    new_props = (
        props_section[:script_match.start()]
        + script_match.group(1)
        + lua_content
        + script_match.group(3)
        + props_section[script_match.end():]
    )

    return xml_str[:start] + new_props + xml_str[end:]


# ---------------------------------------------------------------------------
# Subcommand: tree
# ---------------------------------------------------------------------------

def _get_prop(node, key):
    """Get a property value from a node (using ElementTree, read-only)."""
    props = node.find("properties")
    if props is None:
        return None
    for prop in props.findall("property"):
        k = prop.find("key")
        if k is not None and k.text == key:
            v = prop.find("value")
            return v.text if v is not None else None
    return None


def _print_tree(elem, depth=0):
    """Recursively print the node hierarchy."""
    if elem.tag == "node":
        name = _get_prop(elem, "name") or ""
        script = _get_prop(elem, "script") or ""
        ntype = elem.get("type", "?")
        tag_val = _get_prop(elem, "tag") or ""

        parts = [f"{'  ' * depth}{ntype} '{name}'"]
        if script:
            parts.append(f"[script: {len(script)} chars]")
        if tag_val:
            parts.append(f"[tag: {len(tag_val)} chars]")

        # Count MIDI messages
        messages = elem.find("messages")
        if messages is not None:
            midi_count = len(messages.findall(".//midi"))
            if midi_count:
                parts.append(f"[midi: {midi_count} msgs]")

        print(" ".join(parts))

        children = elem.find("children")
        if children is not None:
            for child in children:
                _print_tree(child, depth + 1)
    else:
        for child in elem:
            _print_tree(child, depth)


def cmd_tree(args):
    """Print node hierarchy of a .tosc file."""
    xml_str = tosc_read(args.file)
    root = ET.fromstring(xml_str)
    _print_tree(root)


# ---------------------------------------------------------------------------
# Subcommand: extract
# ---------------------------------------------------------------------------

def _extract_scripts(elem, scripts, path=""):
    """Recursively extract all non-empty scripts from nodes."""
    if elem.tag == "node":
        name = _get_prop(elem, "name") or ""
        script = _get_prop(elem, "script") or ""
        ntype = elem.get("type", "?")

        current_path = f"{path}/{name}" if path else name

        if script:
            scripts.append({
                "path": current_path,
                "name": name,
                "type": ntype,
                "script": script,
                "chars": len(script),
            })

        children = elem.find("children")
        if children is not None:
            for child in children:
                _extract_scripts(child, scripts, current_path)
    else:
        for child in elem:
            _extract_scripts(child, scripts, path)


def cmd_extract(args):
    """Extract all scripts from a .tosc file to individual .lua files."""
    xml_str = tosc_read(args.file)
    root = ET.fromstring(xml_str)

    scripts = []
    _extract_scripts(root, scripts)

    out_dir = args.output or "extracted"
    os.makedirs(out_dir, exist_ok=True)

    # Track name collisions — use path-based naming for duplicates
    name_counts = {}
    for s in scripts:
        name_counts[s["name"]] = name_counts.get(s["name"], 0) + 1

    name_indices = {}
    for s in scripts:
        name = s["name"]
        if name_counts[name] > 1:
            idx = name_indices.get(name, 0)
            name_indices[name] = idx + 1
            # Use sanitized path for uniqueness
            safe_path = s["path"].replace("/", "__")
            filename = f"{safe_path}.lua"
        else:
            filename = f"{name.replace('/', '_')}.lua"

        filepath = os.path.join(out_dir, filename)
        with open(filepath, "w") as f:
            f.write(s["script"])

    print(f"Extracted {len(scripts)} scripts to {out_dir}/")
    for s in scripts:
        print(f"  {s['type']:6s} '{s['path']}' ({s['chars']} chars)")


# ---------------------------------------------------------------------------
# Subcommand: build
# ---------------------------------------------------------------------------

def cmd_build(args):
    """Inject Lua scripts into .tosc based on toscbuild.json manifest."""
    manifest_dir = args.dir
    manifest_path = os.path.join(manifest_dir, "toscbuild.json")

    if not os.path.isfile(manifest_path):
        print(f"Error: {manifest_path} not found", file=sys.stderr)
        sys.exit(1)

    with open(manifest_path) as f:
        manifest = json.load(f)

    source_path = os.path.join(manifest_dir, manifest["source"])
    output_path = os.path.join(manifest_dir, manifest.get("output", manifest["source"]))
    lua_dir = os.path.join(manifest_dir, manifest.get("lua_dir", "lua"))

    if not os.path.isfile(source_path):
        print(f"Error: source file {source_path} not found", file=sys.stderr)
        sys.exit(1)

    # Backup unless --no-backup
    if not args.no_backup and os.path.isfile(output_path):
        backup_path = output_path + ".bak"
        shutil.copy2(output_path, backup_path)
        if not args.quiet:
            print(f"Backup: {backup_path}")

    # Read and decompress
    xml_str = tosc_read(source_path)
    original_size = len(xml_str)

    if args.dry_run:
        print("Dry run — no files will be written\n")

    # Process each mapping
    injected = 0
    for mapping in manifest["mappings"]:
        lua_file = mapping["lua"]
        lua_path = os.path.join(lua_dir, lua_file)

        if not os.path.isfile(lua_path):
            print(f"  SKIP  {lua_file} (file not found)", file=sys.stderr)
            continue

        with open(lua_path) as f:
            lua_content = f.read()

        is_root = mapping.get("node_id") == "root"

        # Support one-to-many: node_names (array) or node_name (string)
        if "node_names" in mapping:
            targets = mapping["node_names"]
        elif "node_name" in mapping:
            targets = [mapping["node_name"]]
        elif is_root:
            targets = [None]  # root doesn't need a name
        else:
            print(f"  SKIP  {lua_file} (no node_name or node_names)", file=sys.stderr)
            continue

        for node_name in targets:
            try:
                xml_str = replace_script(xml_str, node_name, lua_content, is_root=is_root)
                if not args.quiet:
                    target = "root" if is_root else node_name
                    print(f"  OK    {lua_file} → {target} ({len(lua_content)} chars)")
                injected += 1
            except ValueError as e:
                print(f"  ERROR {lua_file}: {e}", file=sys.stderr)

    if not args.dry_run:
        tosc_write(output_path, xml_str)

    if not args.quiet:
        new_size = len(xml_str)
        # Count total targets across all mappings
        total_targets = sum(
            len(m.get("node_names", [m.get("node_name", m.get("node_id"))]))
            for m in manifest["mappings"]
        )
        print(f"\nInjected {injected}/{total_targets} scripts")
        print(f"XML size: {original_size:,} → {new_size:,} bytes "
              f"({new_size - original_size:+,})")
        if not args.dry_run:
            file_size = os.path.getsize(output_path)
            print(f"Output: {output_path} ({file_size:,} bytes compressed)")


# ---------------------------------------------------------------------------
# Subcommand: dev
# ---------------------------------------------------------------------------

def _get_lua_mtimes(lua_dir, mappings):
    """Get modification times for all mapped Lua files."""
    mtimes = {}
    for mapping in mappings:
        lua_path = os.path.join(lua_dir, mapping["lua"])
        if os.path.isfile(lua_path):
            mtimes[lua_path] = os.stat(lua_path).st_mtime
    return mtimes


def cmd_dev(args):
    """Watch Lua files for changes, rebuild, and optionally open TouchOSC."""
    manifest_dir = args.dir
    manifest_path = os.path.join(manifest_dir, "toscbuild.json")

    if not os.path.isfile(manifest_path):
        print(f"Error: {manifest_path} not found", file=sys.stderr)
        sys.exit(1)

    with open(manifest_path) as f:
        manifest = json.load(f)

    lua_dir = os.path.join(manifest_dir, manifest.get("lua_dir", "lua"))
    output_path = os.path.join(manifest_dir, manifest.get("output", manifest["source"]))

    # Initial build
    print("=== Initial build ===")
    build_args = argparse.Namespace(
        dir=manifest_dir, dry_run=False, no_backup=False, quiet=False
    )
    cmd_build(build_args)

    # Open in TouchOSC if requested
    if not args.no_open and sys.platform == "darwin":
        print(f"\nOpening {output_path} in TouchOSC...")
        subprocess.run(["open", "-a", "TouchOSC", output_path])

    # Watch loop
    print(f"\nWatching {lua_dir} for changes (Ctrl+C to stop)...\n")
    last_mtimes = _get_lua_mtimes(lua_dir, manifest["mappings"])

    try:
        while True:
            time.sleep(1)
            current_mtimes = _get_lua_mtimes(lua_dir, manifest["mappings"])

            changed = []
            for path, mtime in current_mtimes.items():
                if last_mtimes.get(path) != mtime:
                    changed.append(os.path.basename(path))

            if changed:
                timestamp = time.strftime("%H:%M:%S")
                print(f"[{timestamp}] Changed: {', '.join(changed)}")
                build_args = argparse.Namespace(
                    dir=manifest_dir, dry_run=False, no_backup=True, quiet=False
                )
                try:
                    cmd_build(build_args)
                    print(f"[{timestamp}] Rebuild complete — reload in TouchOSC\n")
                except Exception as e:
                    print(f"[{timestamp}] Build error: {e}\n", file=sys.stderr)
                last_mtimes = current_mtimes

    except KeyboardInterrupt:
        print("\nStopped.")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        prog="toscbuild",
        description="TouchOSC code-first build pipeline",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # build
    p_build = subparsers.add_parser("build", help="Inject Lua scripts into .tosc")
    p_build.add_argument("dir", help="Directory containing toscbuild.json")
    p_build.add_argument("--dry-run", action="store_true",
                         help="Show what would be done without writing")
    p_build.add_argument("--no-backup", action="store_true",
                         help="Skip creating .tosc.bak backup")
    p_build.add_argument("--quiet", "-q", action="store_true",
                         help="Minimal output")
    p_build.set_defaults(func=cmd_build)

    # extract
    p_extract = subparsers.add_parser("extract", help="Extract scripts from .tosc")
    p_extract.add_argument("file", help="Path to .tosc file")
    p_extract.add_argument("--output", "-o", help="Output directory (default: extracted)")
    p_extract.set_defaults(func=cmd_extract)

    # tree
    p_tree = subparsers.add_parser("tree", help="Print node hierarchy")
    p_tree.add_argument("file", help="Path to .tosc file")
    p_tree.set_defaults(func=cmd_tree)

    # dev
    p_dev = subparsers.add_parser("dev", help="Watch + rebuild + open TouchOSC")
    p_dev.add_argument("dir", help="Directory containing toscbuild.json")
    p_dev.add_argument("--no-open", action="store_true",
                       help="Don't open TouchOSC automatically")
    p_dev.set_defaults(func=cmd_dev)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
