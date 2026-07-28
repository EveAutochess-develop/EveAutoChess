# -*- coding: utf-8 -*-
"""Minimal NeoX FSD (.sd) table reader for Echoes dogma attributes / type_attributes."""
from __future__ import annotations

import pickle
import struct
from pathlib import Path
from typing import Any


def _u32(b: bytes, off: int) -> int:
    return struct.unpack_from("<I", b, off)[0]


def load_sd(path: Path) -> tuple[dict, bytes]:
    raw = path.read_bytes()
    header_size = _u32(raw, 0)
    # Some files store schema pickle size in first u32; schema starts at 4.
    schema = pickle.loads(raw[4 : 4 + header_size] if False else raw[4:])
    # After pickle there's binary footer + rows. Find pickle end by retry.
    # pickle.loads consumes from offset 4; use Unpickler to get stop index.
    import io

    bio = io.BytesIO(raw[4:])
    schema = pickle.load(bio)
    data_off = 4 + bio.tell()
    return schema, raw[data_off:]


def _read_footer_keys(schema: dict, data: bytes) -> list[tuple[int, int, int]]:
    """Return list of (key, offset, size) from list footer at end of blob."""
    kf = schema.get("keyFooter") or {}
    fixed = int(kf.get("fixedItemSize") or 12)
    # Footer count is last u32 before? NeoX often: [rows...][footer entries][count]
    if len(data) < 4:
        return []
    count = _u32(data, len(data) - 4)
    # sanity
    if count <= 0 or count > 5_000_000:
        return []
    foot_size = count * fixed + 4
    if foot_size > len(data):
        return []
    start = len(data) - foot_size
    out = []
    for i in range(count):
        off = start + i * fixed
        key = _u32(data, off)
        offset = _u32(data, off + 4)
        size = _u32(data, off + 8)
        out.append((key, offset, size))
    return out


def read_attributes_name_map(path: Path) -> dict[str, int]:
    """attribute_name / en_name -> attribute_id from attributes.sd"""
    schema, data = load_sd(path)
    keys = _read_footer_keys(schema, data)
    vt = schema["valueTypes"]
    const = vt["constantAttributeOffsets"]
    id_off = const["attribute_id"]
    name_to_id: dict[str, int] = {}
    # variable strings: need offset table in row — simplified: scan row bytes for ascii names
    for key, offset, size in keys:
        row = data[offset : offset + size]
        if len(row) < id_off + 4:
            continue
        aid = struct.unpack_from("<i", row, id_off)[0]
        # extract printable strings from variable region
        strings = []
        i = 0
        while i < len(row):
            # length-prefixed? try cstring-like pickle strings already resolved elsewhere
            i += 1
        # brute: find ascii sequences
        for m in __import__("re").finditer(rb"[A-Za-z][A-Za-z0-9_]{3,40}", row):
            s = m.group().decode("ascii")
            if "drone" in s.lower() or s.endswith("SlotsLeft") or "Bandwidth" in s:
                name_to_id[s] = aid
    return name_to_id


if __name__ == "__main__":
    p = Path(r"H:\eve手游\history\1.0.0_unpacked\art_extract\staticdata\dogma\attributes.sd")
    m = read_attributes_name_map(p)
    out = Path(__file__).with_name("_echoes_drone_attr_ids.txt")
    lines = [f"{k}={v}" for k, v in sorted(m.items(), key=lambda x: x[0].lower())]
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("names", len(m), "wrote", out)
