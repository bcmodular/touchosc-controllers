#!/usr/bin/env python3
"""
Remove layout-level MIDI from SP404 perform controls so routing lives in Lua only.

- control_fader, toggle_button, grab_button, sync_button, choose_button:
  deletes the entire <midi>...</midi> block (keeps <local> only)

Usage:
    python3 sp404-mk2/tools/patch_sp404_disable_layout_midi.py sp404-mk2/SP404.tosc
"""

import re
import sys
import zlib
from pathlib import Path

TARGET_NAMES = frozenset({
    "control_fader",
    "toggle_button",
    "grab_button",
    "sync_button",
    "choose_button",
})

_NAME_RE = re.compile(
    r"<property type='s'><key><!\[CDATA\[name\]\]></key>"
    r"<value><!\[CDATA\[([^]]+)\]\]></value></property>"
)

_MIDI_BLOCK_RE = re.compile(r"<midi>.*?</midi>", re.DOTALL)


def get_node_name(chunk):
    m = _NAME_RE.search(chunk)
    return m.group(1) if m else None


def patch_tosc(path: Path) -> int:
    xml = zlib.decompress(path.read_bytes()).decode("utf-8")
    parts = xml.split("<node ")
    changed = 0
    new_parts = [parts[0]]

    for chunk in parts[1:]:
        name = get_node_name(chunk)
        if name in TARGET_NAMES and "<midi>" in chunk:
            new_chunk, n = _MIDI_BLOCK_RE.subn("", chunk, count=1)
            if n:
                chunk = new_chunk
                changed += 1
        new_parts.append(chunk)

    if changed:
        path.write_bytes(zlib.compress("<node ".join(new_parts).encode("utf-8")))
    return changed


def main() -> None:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path/to/SP404.tosc>", file=sys.stderr)
        sys.exit(1)
    path = Path(sys.argv[1])
    n = patch_tosc(path)
    print(f"Patched layout MIDI on {n} node(s) in {path}")


if __name__ == "__main__":
    main()
