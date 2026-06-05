#!/usr/bin/env python3
"""send_patch_osc.py — send a TB-3 .syx patch dump to TouchOSC via OSC.

Splits the .syx file into individual F0…F7 SysEx messages, encodes each as a
comma-separated hex string, and sends to /tb3/patch on the target host:port.

TouchOSC listens on UDP port 8000 by default.

Usage:
    python3 send_patch_osc.py path/to/patch.syx [host] [port]

    host  default: 127.0.0.1
    port  default: 8000

No external dependencies — uses only stdlib (socket + struct).

Only synthesis blocks (address prefix 10 00 xx xx) are sent; pattern/MIDI
channel blocks are skipped so they don't trigger spurious UI updates.
"""

import socket
import struct
import sys
import time

OSC_ADDRESS = "/tb3/patch"
SYNTH_BLOCK_PREFIX = 0x10   # all synthesis blocks start with 10 00 …


def split_messages(raw: bytes) -> list[bytes]:
    """Split a raw SysEx file into individual F0…F7 messages."""
    msgs, cur = [], []
    for b in raw:
        cur.append(b)
        if b == 0xF7:
            msgs.append(bytes(cur))
            cur = []
    return msgs


def is_synth_block(msg: bytes) -> bool:
    """True if this is a TB-3 Roland synthesis SysEx block (10 00 xx xx)."""
    # Structure: F0 41 10 00 00 7B 12  [a1 a2 a3 a4]  …
    return (len(msg) >= 12
            and msg[0] == 0xF0
            and msg[1] == 0x41
            and msg[7] == SYNTH_BLOCK_PREFIX)


def encode_osc_string(s: str) -> bytes:
    """Encode a string as OSC string (null-terminated, padded to 4 bytes)."""
    encoded = s.encode("ascii") + b"\x00"
    pad = (4 - len(encoded) % 4) % 4
    return encoded + b"\x00" * pad


def build_osc_message(address: str, hex_string: str) -> bytes:
    """Build a minimal OSC message with a single string argument."""
    addr_bytes = encode_osc_string(address)
    type_tag   = encode_osc_string(",s")
    arg_bytes  = encode_osc_string(hex_string)
    return addr_bytes + type_tag + arg_bytes


def send_patch(syx_path: str, host: str = "127.0.0.1", port: int = 8000,
               delay_ms: float = 20.0) -> None:
    with open(syx_path, "rb") as fh:
        raw = fh.read()

    messages = split_messages(raw)
    synth_msgs = [m for m in messages if is_synth_block(m)]
    skipped    = len(messages) - len(synth_msgs)

    print(f"File : {syx_path}  ({len(raw)} bytes, {len(messages)} messages)")
    print(f"Send : {len(synth_msgs)} synthesis blocks → {host}:{port}  "
          f"(skipping {skipped} pattern/global blocks)")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        for i, msg in enumerate(synth_msgs):
            hex_csv = ",".join(f"{b:02X}" for b in msg)
            osc_pkt = build_osc_message(OSC_ADDRESS, hex_csv)
            sock.sendto(osc_pkt, (host, port))
            addr_str = " ".join(f"{b:02X}" for b in msg[7:11])
            print(f"  [{i+1:2d}/{len(synth_msgs)}] addr {addr_str}  "
                  f"({len(msg)} bytes)")
            time.sleep(delay_ms / 1000.0)
    finally:
        sock.close()

    print("Done.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    syx_file = sys.argv[1]
    target_host = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    target_port = int(sys.argv[3]) if len(sys.argv) > 3 else 8000
    send_patch(syx_file, target_host, target_port)
