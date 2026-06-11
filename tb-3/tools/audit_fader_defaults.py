#!/usr/bin/env python3
"""
Audit double-tap defaults for all control_fader RADIAL nodes in TB3.tosc.

Rule:
  - signed=true, bipolar=true, or semitoneRange=true  → expected default 0.5 (center)
  - bipolar=true with an explicit center/max           → expected default = center/max
  - sp="global_tuning" (plain MIDI CC, no fader)      → skip
  - everything else (unipolar)                         → expected default 0.0

Prints a report of violations and intentional exceptions.
Read-only — does not modify any files.
"""

import re
import sys
import zlib
import xml.etree.ElementTree as ET
from pathlib import Path

REPO   = Path(__file__).parent.parent.parent
TB3    = Path(__file__).parent.parent / "TB3.tosc"
ENCMAP = Path(__file__).parent.parent / "lua" / "enc_map.lua"

# ---------------------------------------------------------------------------
# Parse ENC_SEND_MAP from enc_map.lua
# ---------------------------------------------------------------------------
# Pulls out each "section,enc" key and its encoding flags.  We parse the Lua
# source textually — good enough for the well-structured table.

_KEY_RE = re.compile(r'\["([^"]+)"\]\s*=\s*\{', re.DOTALL)

def _flag(text, name):
    return bool(re.search(rf'\b{name}\s*=\s*true', text))

def _num(text, name):
    m = re.search(rf'\b{name}\s*=\s*([0-9.]+)', text)
    return float(m.group(1)) if m else None

def _extract_body(src, brace_start):
    """Return the text between the opening '{' at brace_start and its matching '}'."""
    depth = 0
    i = brace_start
    while i < len(src):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                return src[brace_start + 1 : i]
        i += 1
    return ''

def parse_enc_map(lua_path):
    src = lua_path.read_text()
    # Only parse the ENC_SEND_MAP block (stop at SW_SEND_MAP)
    start = src.find('local ENC_SEND_MAP')
    end   = src.find('local SW_SEND_MAP', start)
    block = src[start:end]

    entries = {}
    for m in _KEY_RE.finditer(block):
        key        = m.group(1)
        brace_pos  = start + m.end() - 1   # position of '{' in full src (adjusted)
        # Re-find in full src to get correct absolute position for _extract_body
        abs_start  = src.find(f'["{key}"]', start, end)
        if abs_start == -1:
            continue
        brace_abs  = src.find('{', abs_start)
        body       = _extract_body(src, brace_abs)
        entries[key] = {
            'signed':        _flag(body, 'signed'),
            'bipolar':       _flag(body, 'bipolar'),
            'semitoneRange': _flag(body, 'semitoneRange'),
            'sp':            (re.search(r'sp\s*=\s*"([^"]+)"', body) or [None,None])[1],
            'center':        _num(body, 'center'),
            'max':           _num(body, 'max'),
            'bits':          int(_num(body, 'bits') or 7),
        }
    return entries

# ---------------------------------------------------------------------------
# Walk the .tosc XML and collect control_fader nodes with their parent path
# ---------------------------------------------------------------------------

def get_prop(node, key):
    for p in node.findall('properties/property'):
        if p.findtext('key') == key:
            return p.findtext('value') or ''
    return ''

def get_default(node):
    for v in node.findall('values/value'):
        if v.findtext('key') == 'x':
            return v.findtext('default') or '0'
    return '0'

def walk(node, ancestors, results):
    """Walk <node> children only (stored inside <children> elements)."""
    ntype = node.get('type', '')
    name  = get_prop(node, 'name')
    path  = ancestors + [name]
    if ntype == 'RADIAL' and name == 'control_fader':
        # path[-1]='control_fader', path[-2]=enc_group, path[-3]=section_group
        if len(path) >= 3:
            enc_grp     = path[-2]
            section_grp = path[-3]
            map_key = f"{section_grp},{enc_grp}"
        else:
            map_key = ','.join(path[:-1])
        default = get_default(node)
        results.append((map_key, float(default)))
    # Recurse into <node> elements found inside <children> containers only.
    for children_el in node.findall('children'):
        for child in children_el.findall('node'):
            walk(child, path, results)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def expected_default(enc):
    if enc.get('sp') == 'global_tuning':
        return None  # skip — no fader default to audit
    if enc['signed'] or enc['semitoneRange']:
        return 0.5
    if enc['bipolar']:
        # explicit center/max → center position on 0-1 fader
        if enc['center'] is not None and enc['max'] is not None:
            return enc['center'] / enc['max']
        return 0.5
    return 0.0

def main():
    enc_map = parse_enc_map(ENCMAP)
    raw   = zlib.decompress(TB3.read_bytes())
    tree  = ET.fromstring(raw)

    faders = []
    # <lexml> contains <node> children directly (no <children> wrapper at root).
    for root_node in tree.findall('node'):
        walk(root_node, [], faders)

    print(f"Found {len(faders)} control_fader nodes.\n")

    ok_lines      = []
    violation_lines = []
    unknown_lines = []

    for map_key, default in sorted(faders):
        enc = enc_map.get(map_key)
        if enc is None:
            unknown_lines.append(f"  UNKNOWN  key={map_key!r}  default={default}")
            continue
        exp = expected_default(enc)
        if exp is None:
            ok_lines.append(f"  SKIP     {map_key}  (global_tuning)")
            continue
        tol = 0.005
        if abs(default - exp) > tol:
            flags = []
            if enc['signed']:        flags.append('signed')
            if enc['bipolar']:       flags.append('bipolar')
            if enc['semitoneRange']: flags.append('semitoneRange')
            flag_str = ','.join(flags) if flags else 'unipolar'
            violation_lines.append(
                f"  VIOLATION  {map_key}\n"
                f"             default={default}  expected={exp:.4f}  [{flag_str}]"
            )
        else:
            ok_lines.append(f"  ok       {map_key}  default={default}  expected={exp:.4f}")

    if violation_lines:
        print("=== VIOLATIONS ===")
        for l in violation_lines:
            print(l)
        print()

    if unknown_lines:
        print("=== UNKNOWN (not in ENC_SEND_MAP — morph_enc or EFX slots) ===")
        for l in unknown_lines:
            print(l)
        print()

    print("=== OK ===")
    for l in ok_lines:
        print(l)

    print(f"\nSummary: {len(violation_lines)} violation(s), {len(unknown_lines)} unknown, {len(ok_lines)} ok")

if __name__ == '__main__':
    main()
