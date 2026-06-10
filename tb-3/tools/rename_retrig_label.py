#!/usr/bin/env python3
"""
One-off: rename the RETRIG overlay label in lfo_cv_offset_enc.

lfo_cv_offset_enc had two children named name_label (title at y=89 and RETRIG
overlay at y=126). This renames the y=126 label to retrig_label.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "tools"))
from tosc_layout_utils import tosc_read, tosc_write, find_node_block

TOSC = Path(__file__).parent.parent / "TB3.tosc"

NAME_RE = re.compile(
    r"(<property type='s'><key><!\[CDATA\[name\]\]></key>"
    r"<value><!\[CDATA\[)name_label(\]\]></value></property>)"
)

FRAME_Y_RE = re.compile(
    r"<property type='r'><key><!\[CDATA\[frame\]\]></key><value>"
    r"<x>[^<]+</x><y>(\d+)</y>"
)


def main() -> None:
    xml = tosc_read(TOSC)
    bounds = find_node_block(xml, "lfo_cv_offset_enc")
    if not bounds:
        raise SystemExit("lfo_cv_offset_enc not found")
    start, end = bounds
    block = xml[start:end]

    # Find name_label nodes; rename the one whose frame y == 126.
    pos = 0
    renamed = False
    while True:
        m = NAME_RE.search(block, pos)
        if not m:
            break
        # Look backward in this node for its frame y
        node_start = block.rfind("<node ", 0, m.start())
        if node_start == -1:
            pos = m.end()
            continue
        node_end = block.find("</node>", m.end())
        if node_end == -1:
            break
        node_chunk = block[node_start:node_end + 7]
        fm = FRAME_Y_RE.search(node_chunk)
        if fm and fm.group(1) == "126":
            new_chunk = node_chunk.replace(
                "<value><![CDATA[name_label]]></value>",
                "<value><![CDATA[retrig_label]]></value>",
                1,
            )
            block = block[:node_start] + new_chunk + block[node_end + 7:]
            renamed = True
            break
        pos = m.end()

    if not renamed:
        raise SystemExit("retrig overlay name_label (y=126) not found")

    xml = xml[:start] + block + xml[end:]
    tosc_write(TOSC, xml)
    print(f"Renamed RETRIG overlay to retrig_label in {TOSC}")


if __name__ == "__main__":
    main()
