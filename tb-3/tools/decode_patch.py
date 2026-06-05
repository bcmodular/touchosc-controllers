#!/usr/bin/env python3
"""decode_patch.py — TB-3 patch dump (.syx) decoder.

Reads a Roland TB-3 patch dump (11 SysEx messages, 422 bytes) and prints a
human-readable parameter table per block. Purpose: validate our SysEx address
map against the Dope Robot Ctrlr panel by loading the same .syx in both and
eyeballing the decoded values.

No external deps. Usage:
    python3 decode_patch.py path/to/patch.syx [more.syx ...]

Notes
-----
* 16-bit params are nibble-packed: value = MSB*16 + LSB (each byte 0x00-0x0F).
* "signed7" display = raw - 64   (LFO depths: -64..63).
* "signed16" display = raw - 128 (CV offset pitch: -128..127).
* EFX1 (10 00 10 00) / EFX2 (10 00 12 00) are effect-type dependent; we decode
  the TYPE byte and dump the rest as raw indexed bytes for now.
"""
import sys

SYSEX_HEADER = [0xF0, 0x41, 0x10, 0x00, 0x00, 0x7B, 0x12]

# Field spec: (offset, name, kind)
#   kind: "u7"  single byte 0-127
#         "sw"  single byte 0-1 (OFF/ON)
#         "s7"  single byte, signed display = raw-64
#         "u16" two bytes nibble-packed, 0-255
#         "s16" two bytes nibble-packed, signed display = raw-128
#         "type" distortion/efx type index (decoded with a name table)
DIST_TYPES = [
    "Mid Boost", "Clean Boost", "Treble Bst", "Blues OD", "Crunch",
    "Natural OD", "OD-1", "T-Scream", "Turbo OD", "Warm OD", "Distortion",
    "Mild DS", "Mid DS", "RAT", "GUV DS", "DST+", "Modern DS", "Solid DS",
    "Stack", "Loud", "Metal Zone", "Lead", "'60s FUZZ", "Oct FUZZ", "MUFF FUZZ",
]
EFX_TYPES = ["BYPASS", "CS", "RM", "BC", "TR", "CH", "FL", "PH", "DD", "PS", "EQ"]

BLOCKS = {
    (0x10, 0x00, 0x00, 0x00): ("LFO", [
        (0x00, "LFO RATE", "u7"), (0x01, "LFO DELAY", "u7"),
        (0x02, "LFO WAVE SAW", "u7"), (0x03, "LFO WAVE SQR", "u7"),
        (0x04, "LFO WAVE TRI", "u7"), (0x05, "LFO WAVE SIN", "u7"),
        (0x06, "CV OFFSET (LFO)", "u7"), (0x07, "LFO WAVE S&H", "u7"),
        (0x08, "LFO DEPTH (VCO)", "s7"), (0x09, "LFO DEPTH (VCF)", "s7"),
        (0x0A, "LFO DEPTH (VCA)", "s7"), (0x0B, "BPM SYNC", "sw"),
        (0x0C, "LFO RETRIGGER", "sw"),
    ]),
    (0x10, 0x00, 0x02, 0x00): ("CV OFFSET / TUNING", [
        # CONFIRMED vs Dope Robot panel: center 128 (raw-128 ≈ panel signed).
        # SQR raw 64 → panel -64 (exact); SAW/RING within ±2 (panel rounding).
        # NB: panel's 4th "TUNING" knob is the separate global tune (CC104),
        # not part of this block.
        (0x00, "CV OFFSET SQR PITCH", "s16"),
        (0x02, "CV OFFSET SAW PITCH", "s16"),
        (0x04, "CV OFFSET RING PITCH", "s16"),
    ]),
    (0x10, 0x00, 0x04, 0x00): ("CROSS MODULATION", [
        (0x00, "XMOD SQR>SAW", "s7"), (0x02, "XMOD SAW>SAW", "s7"),
        (0x03, "XMOD WHITE>SAW", "s7"), (0x04, "XMOD PINK>SAW", "s7"),
        (0x05, "XMOD SQR>SQR", "s7"), (0x07, "XMOD SAW>SQR", "s7"),
        (0x08, "XMOD WHITE>SQR", "s7"), (0x09, "XMOD PINK>SQR", "s7"),
    ]),
    (0x10, 0x00, 0x06, 0x00): ("RING MODULATION", [
        (0x00, "RING DEPTH SAW", "u7"), (0x01, "RING DEPTH SQR", "u7"),
        (0x04, "RING DEPTH RING", "u7"), (0x05, "RING DEPTH WHITE", "u7"),
        (0x06, "RING DEPTH PINK", "u7"), (0x0B, "RING DEPTH", "u7"),
    ]),
    (0x10, 0x00, 0x08, 0x00): ("VCO", [
        (0x00, "VCO SAW LEVEL", "u7"), (0x01, "VCO SQR LEVEL", "u7"),
        (0x04, "VCO SIN LEVEL", "u7"), (0x05, "VCO WHITE LEVEL", "u7"),
        (0x06, "VCO PINK LEVEL", "u7"), (0x07, "VCO RING LEVEL", "u7"),
        (0x08, "VCO SAW SW", "sw"), (0x09, "VCO SQR SW", "sw"),
        (0x0A, "VCO SIN SW", "sw"), (0x0B, "VCO WHITE SW", "sw"),
        (0x0C, "VCO PINK SW", "sw"), (0x0D, "VCO RING SW", "sw"),
    ]),
    (0x10, 0x00, 0x0A, 0x00): ("VCF", [
        (0x00, "VCF CUTOFF", "u16"), (0x02, "VCF RESONANCE", "u16"),
        (0x04, "VCF ENV DEPTH", "u16"), (0x06, "VCF ATTACK", "u7"),
        (0x07, "VCF DECAY", "u7"), (0x08, "VCF SUSTAIN", "u7"),
        (0x09, "VCF RELEASE", "u7"), (0x0A, "VCF KEY FOLLOW", "u7"),
    ]),
    (0x10, 0x00, 0x0C, 0x00): ("VCA", [
        (0x00, "VCA ATTACK", "u7"), (0x01, "VCA DECAY", "u7"),
        (0x02, "VCA SUSTAIN", "u7"), (0x03, "VCA RELEASE", "u7"),
        (0x04, "MASTER / PATCH VOLUME", "u7"),
    ]),
    (0x10, 0x00, 0x0E, 0x00): ("DISTORTION", [
        (0x00, "DIST SW", "sw"), (0x01, "DIST TYPE", "type"),
        # BOTTOM/TONE: Dope Robot panel shows RAW 0-100 (not the ±50 musical
        # value), so we match the device/panel and display raw.
        (0x02, "DIST DRIVE", "u7"), (0x03, "DIST BOTTOM", "u7"),
        (0x04, "DIST TONE", "u7"), (0x05, "DIST EFFECT LEVEL", "u7"),
        (0x06, "DIST DRY LEVEL", "u7"), (0x07, "DIST COLOR", "sw"),
    ]),
    (0x10, 0x00, 0x14, 0x00): ("PARAMETER ASSIGN / PORTAMENTO", [
        (0x00, "PORTAMENTO SW", "sw"), (0x01, "PORTAMENTO TIME", "u7"),
        (0x02, "PORTAMENTO MODE", "sw"), (0x03, "BENDER RANGE", "u7"),
        (0x04, "PARAM ID XY PAD MOD", "u16"), (0x06, "PARAM ID EFFECT KNOB", "u16"),
        (0x08, "PARAM ID XY PAD X", "u16"), (0x0A, "PARAM ID XY PAD Y", "u16"),
        (0x0E, "ACCENT", "u16"),
    ]),
}
EFX_BLOCKS = {
    (0x10, 0x00, 0x10, 0x00): "EFX1",
    (0x10, 0x00, 0x12, 0x00): "EFX2",
}

# Additional blocks present in full Sound+Pattern dumps (from Ctrlr "Receive")
EXTRA_BLOCKS = {
    (0x01, 0x00, 0x00, 0x00): ("MIDI CHANNEL / GLOBAL", [
        (0x00, "MIDI OUT CHANNEL (0=CH1)", "u7"),
        (0x01, "MIDI IN CHANNEL  (0=CH1)", "u7"),
        (0x02, "OMNI MODE", "sw"),
    ]),
    (0x30, 0x00, 0x00, 0x00): ("PATTERN SETTING", [
        (0x00, "TRIPLET", "sw"),
        (0x01, "PATTERN LENGTH (0=1step)", "u7"),
        (0x02, "GATE TIME", "u7"),
    ]),
}
PATTERN_DATA_BLOCKS = {
    (0x30, 0x00, 0x02, 0x00): "PATTERN PITCH (steps 1–16+)",
    (0x30, 0x00, 0x04, 0x00): "PATTERN SLIDE",
    (0x30, 0x00, 0x06, 0x00): "PATTERN GATE",
    (0x30, 0x00, 0x08, 0x00): "PATTERN ACCENT",
}


def split_messages(raw):
    msgs, cur = [], []
    for b in raw:
        cur.append(b)
        if b == 0xF7:
            msgs.append(cur)
            cur = []
    return msgs


def checksum_ok(msg):
    # msg = F0 41 10 00 00 7B 12 [addr+data] cs F7
    body = msg[7:-2]
    cs = msg[-2]
    calc = (0x100 - (sum(body) % 256)) % 128
    return calc == cs, calc, cs


def decode_field(data, off, kind):
    if off >= len(data):
        return "  --   (missing)"
    raw = data[off]
    if kind == "u7":
        return f"{raw:3d}"
    if kind == "sw":
        return f"{raw:3d}  ({'ON' if raw else 'OFF'})"
    if kind == "s7":
        return f"{raw:3d}  (signed {raw - 64:+d})"
    if kind == "s7_50":  # 0-100, centered on 50 (DIST BOTTOM/TONE)
        return f"{raw:3d}  (signed {raw - 50:+d})"
    if kind == "type":
        name = DIST_TYPES[raw] if 0 <= raw < len(DIST_TYPES) else "?"
        return f"{raw:3d}  ({name})"
    if kind in ("u16", "s16"):
        if off + 1 >= len(data):
            return "  --   (missing)"
        val = data[off] * 16 + data[off + 1]
        if kind == "s16":
            return f"{val:3d}  (signed {val - 128:+d})"
        return f"{val:3d}"
    return f"{raw:3d}"


def decode_file(path):
    with open(path, "rb") as fh:
        raw = list(fh.read())
    print(f"\n{'='*70}\n{path}  ({len(raw)} bytes)\n{'='*70}")
    for msg in split_messages(raw):
        if msg[:7] != SYSEX_HEADER:
            print(f"  [skip] non-TB-3 message, {len(msg)} bytes")
            continue
        addr = tuple(msg[7:11])
        data = msg[11:-2]
        ok, calc, cs = checksum_ok(msg)
        cs_note = "" if ok else f"  !! CHECKSUM {calc:02X} != {cs:02X}"
        a = " ".join(f"{x:02X}" for x in addr)
        if addr in BLOCKS:
            name, fields = BLOCKS[addr]
            print(f"\n  [{a}] {name}  ({len(data)} data bytes){cs_note}")
            for off, label, kind in fields:
                print(f"      {label:24s} = {decode_field(data, off, kind)}")
        elif addr in EFX_BLOCKS:
            name = EFX_BLOCKS[addr]
            t = data[0] if data else -1
            tname = EFX_TYPES[t] if 0 <= t < len(EFX_TYPES) else "?"
            print(f"\n  [{a}] {name}  ({len(data)} data bytes){cs_note}")
            print(f"      TYPE = {t:3d}  ({tname})")
            rawbytes = " ".join(f"{x:02X}" for x in data[1:])
            print(f"      raw slots: {rawbytes}")
        elif addr in EXTRA_BLOCKS:
            name, fields = EXTRA_BLOCKS[addr]
            print(f"\n  [{a}] {name}  ({len(data)} data bytes){cs_note}")
            for off, label, kind in fields:
                print(f"      {label:30s} = {decode_field(data, off, kind)}")
        elif addr in PATTERN_DATA_BLOCKS:
            name = PATTERN_DATA_BLOCKS[addr]
            rawbytes = " ".join(f"{x:02X}" for x in data)
            print(f"\n  [{a}] {name}  ({len(data)} data bytes){cs_note}")
            print(f"      raw: {rawbytes}")
        else:
            print(f"\n  [{a}] UNKNOWN BLOCK ({len(data)} data bytes){cs_note}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    for p in sys.argv[1:]:
        decode_file(p)
