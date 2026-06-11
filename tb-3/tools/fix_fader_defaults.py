#!/usr/bin/env python3
"""
One-shot fix: set correct double-tap defaults for faders with signed/bipolar/semitoneRange
encoding where the layout currently has incorrect 0.0 defaults.

Run once, then rebuild with:  python3 tools/toscbuild.py build tb-3
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "tools"))
from tosc_layout_utils import tosc_read, tosc_write, find_node_block, backup_tosc

TOSC = Path(__file__).parent.parent / "TB3.tosc"

# (section_group, enc_group, new_default_float)
VIOLATIONS = [
    # Cross Mod encoders — signed (raw 64 = 0), center at 0.5
    ("cross_mod_group", "pink_saw_enc",         0.5),
    ("cross_mod_group", "pink_sqr_enc",         0.5),
    ("cross_mod_group", "saw_saw_enc",          0.5),
    ("cross_mod_group", "saw_sqr_enc",          0.5),
    ("cross_mod_group", "sqr_saw_enc",          0.5),
    ("cross_mod_group", "sqr_sqr_enc",          0.5),
    ("cross_mod_group", "white_saw_enc",        0.5),
    ("cross_mod_group", "white_sqr_enc",        0.5),
    # Distortion — bipolar, max=100, center at 0.5
    ("dist_group",      "dist_bottom_enc",      0.5),
    ("dist_group",      "dist_tone_enc",        0.5),
    # Pitch bend range — semitoneRange; user default: max (±24 st)
    ("other_group",     "pitch_bend_range_enc", 1.0),
    # Tuning — bipolar, max=151, center=127  →  127/151 ≈ 0.8411
    ("tuning_group",    "ring_sin_tuning_enc",  127 / 151),
    ("tuning_group",    "saw_tuning_enc",       127 / 151),
    ("tuning_group",    "sqr_tuning_enc",       127 / 151),
    # Global tuning — plain MIDI CC, bipolar (center = 64/127 ≈ 0.5)
    ("tuning_group",    "tuning_enc",           0.5),
    # LFO depth — signed (raw 64 = 0), center at 0.5
    ("vca_group",       "vca_lfo_depth_enc",    0.5),
    ("vcf_group",       "vcf_lfo_depth_enc",    0.5),
    ("vco_group",       "vco_lfo_depth_enc",    0.5),
]

DEFAULT_RE = re.compile(r'<default><!\[CDATA\[[^\]]*\]\]></default>')


def set_fader_default(xml: str, section: str, enc: str, new_val: float) -> str:
    sec_bounds = find_node_block(xml, section)
    if not sec_bounds:
        print(f"  ERROR: section '{section}' not found"); return xml
    sec_start, sec_end = sec_bounds

    enc_bounds = find_node_block(xml, enc, sec_start, sec_end)
    if not enc_bounds:
        print(f"  ERROR: enc '{enc}' not found in '{section}'"); return xml
    enc_start, enc_end = enc_bounds

    fdr_bounds = find_node_block(xml, "control_fader", enc_start, enc_end)
    if not fdr_bounds:
        print(f"  ERROR: control_fader not found in '{enc}'"); return xml
    fdr_start, fdr_end = fdr_bounds

    fader_block = xml[fdr_start:fdr_end]
    replacement = f"<default><![CDATA[{new_val}]]></default>"
    new_fader_block, n = DEFAULT_RE.subn(replacement, fader_block, count=1)
    if n == 0:
        print(f"  ERROR: <default> not found in '{enc}'"); return xml

    print(f"  {section},{enc}  →  {new_val:.6f}")
    return xml[:fdr_start] + new_fader_block + xml[fdr_end:]


xml = tosc_read(TOSC)
print(f"Fixing fader defaults in {TOSC.name} ...\n")

for section, enc, new_val in VIOLATIONS:
    xml = set_fader_default(xml, section, enc, new_val)

backup_tosc(TOSC)
tosc_write(TOSC, xml)
print(f"\nDone. Written: {TOSC} ({TOSC.stat().st_size:,} bytes compressed)")
