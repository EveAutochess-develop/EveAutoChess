# -*- coding: utf-8 -*-
"""Extract Echoes dogma attribute id by name + per-type float values."""
from __future__ import annotations

import io
import pickle
import re
import struct
from pathlib import Path

DOGMA = Path(r"H:\eve手游\history\1.0.0_unpacked\art_extract\staticdata\dogma")


def load_sd(path: Path):
    raw = path.read_bytes()
    bio = io.BytesIO(raw[4:])
    schema = pickle.load(bio)
    return schema, raw[4 + bio.tell() :]


def footer_entries(schema: dict, data: bytes) -> list[tuple[int, int, int]]:
    kf = schema.get("keyFooter") or {}
    fixed = int(kf.get("fixedItemSize") or 12)
    if len(data) < 4:
        return []
    count = struct.unpack_from("<I", data, len(data) - 4)[0]
    foot = count * fixed + 4
    if count <= 0 or foot > len(data):
        return []
    start = len(data) - foot
    out = []
    for i in range(count):
        o = start + i * fixed
        out.append(struct.unpack_from("<III", data, o))
    return out


def attr_name_to_id() -> dict[str, int]:
    schema, data = load_sd(DOGMA / "attributes.sd")
    vt = schema["valueTypes"]
    const = vt["constantAttributeOffsets"]
    # Prefer footer key as id; also read embedded attribute_id field.
    id_field = const.get("attribute_id", 0)
    out: dict[str, int] = {}
    for key, offset, size in footer_entries(schema, data):
        row = data[offset : offset + size]
        aid = key
        if id_field + 4 <= len(row):
            embedded = struct.unpack_from("<i", row, id_field)[0]
            if embedded > 0:
                aid = embedded
        names = re.findall(rb"[A-Za-z][A-Za-z0-9_]{2,48}", row)
        # Prefer attribute_name-like tokens near end
        for nb in names:
            s = nb.decode("ascii")
            if s[0].islower() or s.endswith("Left") or "drone" in s.lower() or "Bandwidth" in s:
                out[s] = aid
    return out


def type_attr_values(attr_ids: set[int]) -> dict[int, dict[int, float]]:
    """Best-effort: scan type_attributes binary for (typeId, attrId, float)."""
    schema, data = load_sd(DOGMA / "type_attributes.sd")
    # type_attributes rows are often: type_id -> list of (attr_id, value)
    # Footer keys = type_id.
    out: dict[int, dict[int, float]] = {}
    entries = footer_entries(schema, data)
    vt = schema.get("valueTypes") or {}
    # Without full schema walk, scan each row for int32 pairs + float32
    for tid, offset, size in entries:
        row = data[offset : offset + size]
        vals: dict[int, float] = {}
        # Heuristic walk: look for attr id as int32 then float32 value
        i = 0
        while i + 8 <= len(row):
            aid = struct.unpack_from("<i", row, i)[0]
            if aid in attr_ids:
                # try float after 4 bytes
                fval = struct.unpack_from("<f", row, i + 4)[0]
                if abs(fval) < 1e10:
                    vals[aid] = float(fval)
            i += 1
        if vals:
            out[tid] = vals
    return out


if __name__ == "__main__":
    names = attr_name_to_id()
    want_names = [
        "droneSlotsLeft",
        "droneBandwidth",
        "droneCapacity",
        "maxActiveDrones",
        "launcherSlotsLeft",
        "turretSlotsLeft",
    ]
    lines = []
    ids = set()
    for n in want_names:
        aid = names.get(n)
        lines.append(f"{n}={aid}")
        if aid:
            ids.add(aid)
    # also dump all drone* names
    for n, aid in sorted(names.items()):
        if "drone" in n.lower() or n.endswith("SlotsLeft"):
            lines.append(f"ALL {n}={aid}")
            if aid:
                ids.add(aid)
    Path(__file__).with_name("_echoes_attr_map.txt").write_text("\n".join(lines), encoding="utf-8")

    # Sample types
    ta = type_attr_values(ids)
    sample_tids = [597, 638, 620, 582, 628]
    s_lines = []
    for tid in sample_tids:
        s_lines.append(f"type {tid}: {ta.get(tid)}")
    Path(__file__).with_name("_echoes_type_sample.txt").write_text(
        "\n".join(s_lines) + f"\n\ntypes_with_any={len(ta)}\n", encoding="utf-8"
    )
    print("map", {n: names.get(n) for n in want_names})
    print("types", len(ta))
