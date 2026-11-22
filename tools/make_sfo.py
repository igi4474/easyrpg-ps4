#!/usr/bin/env python3
"""Minimal PS4 param.sfo writer (same entries OpenOrbis' add_pkg sets via PkgTool)."""
import struct, sys, argparse

def build_sfo(entries):
    # entries: list of (key, value, max_len); value str -> utf8 (0x0204), int -> int32 (0x0404)
    entries = sorted(entries, key=lambda e: e[0])
    key_table = b""
    data_table = b""
    index = b""
    for key, val, maxlen in entries:
        koff = len(key_table)
        key_table += key.encode() + b"\0"
        doff = len(data_table)
        if isinstance(val, int):
            fmt, raw, maxlen = 0x0404, struct.pack("<I", val), 4
            length = 4
        else:
            raw = val.encode("utf-8") + b"\0"
            fmt, length = 0x0204, len(raw)
            if length > maxlen:
                raise ValueError(f"{key} too long")
        data_table += raw.ljust(maxlen, b"\0")
        index += struct.pack("<HHIII", koff, fmt, length, maxlen, doff)
    while len(key_table) % 4:
        key_table += b"\0"
    key_off = 20 + len(index)
    data_off = key_off + len(key_table)
    header = struct.pack("<4sIIII", b"\0PSF", 0x0101, key_off, data_off, len(entries))
    return header + index + key_table + data_table

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--title", required=True)
    ap.add_argument("--title-id", required=True)
    ap.add_argument("--content-id", required=True)
    ap.add_argument("--version", default="01.00")
    a = ap.parse_args()
    entries = [
        ("APP_TYPE", 1, 4),
        ("APP_VER", a.version, 8),
        ("ATTRIBUTE", 0, 4),
        ("CATEGORY", "gde", 4),
        ("CONTENT_ID", a.content_id, 48),
        ("DOWNLOAD_DATA_SIZE", 0, 4),
        ("FORMAT", "obs", 4),
        ("SYSTEM_VER", 1020, 4),
        ("TITLE", a.title, 128),
        ("TITLE_ID", a.title_id, 12),
        ("VERSION", a.version, 8),
    ]
    open(a.out, "wb").write(build_sfo(entries))

if __name__ == "__main__":
    main()
