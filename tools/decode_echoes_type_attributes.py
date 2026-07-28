# -*- coding: utf-8 -*-
"""Decode Echoes FSD (.sd) — port of Blaumeise03/eve-echoes-tools fsd2json dict+float path.

Enough to dump dogma/attributes.sd and type_attributes.sd for drone slot patching.
"""
from __future__ import annotations

import io
import json
import pickle
import re
import struct
from pathlib import Path
from typing import Any

ECHOES_HISTORY = Path(r"H:\eve手游\history")
OUT = Path(__file__).resolve().parents[1] / "godot_project" / "data" / "_extracted"
SHIPS = Path(__file__).resolve().parents[1] / "godot_project" / "data" / "ships"


def _version_key(name: str) -> tuple[int, ...]:
    m = re.match(r"(\d+)\.(\d+)\.(\d+)_unpacked$", name)
    if not m:
        return (0, 0, 0)
    return tuple(int(part) for part in m.groups())


def latest_unpack_root() -> Path:
    candidates: list[Path] = []
    if ECHOES_HISTORY.exists():
        for child in ECHOES_HISTORY.iterdir():
            dogma = child / "art_extract" / "staticdata" / "dogma"
            if child.is_dir() and child.name.endswith("_unpacked") and dogma.exists():
                candidates.append(child)
    if not candidates:
        return ECHOES_HISTORY / "1.0.0_unpacked"
    candidates.sort(key=lambda p: _version_key(p.name), reverse=True)
    return candidates[0]


DOGMA = latest_unpack_root() / "art_extract" / "staticdata" / "dogma"


def u32(b: bytes, off: int) -> int:
    return struct.unpack_from("<I", b, off)[0]


def i32(b: bytes, off: int) -> int:
    return struct.unpack_from("<i", b, off)[0]


def u64(b: bytes, off: int) -> int:
    return struct.unpack_from("<Q", b, off)[0]


def f64(b: bytes, off: int) -> float:
    return struct.unpack_from("<d", b, off)[0]


def f32(b: bytes, off: int) -> float:
    return struct.unpack_from("<f", b, off)[0]


def load_schema_and_data(path: Path) -> tuple[dict, bytes, int]:
    raw = path.read_bytes()
    schema_size = u32(raw, 0)
    schema = pickle.loads(raw[4 : 4 + schema_size])
    data_off = 4 + schema_size
    return schema, raw, data_off


def footer_key_kind(schema: dict) -> tuple[str, int]:
    """Return (kind, item_size). kinds: int, int_size, long, long_size."""
    kt = (schema.get("keyTypes") or {}).get("type", "int")
    attrs = ((schema.get("keyFooter") or {}).get("itemTypes") or {}).get("attributes") or {}
    has_size = "size" in attrs
    if kt == "int":
        return ("int_size" if has_size else "int", 12 if has_size else 8)
    return ("long_size" if has_size else "long", 16 if has_size else 12)


def parse_footer(footer: bytes, schema: dict) -> list[tuple[Any, int, int | None]]:
    count = u32(footer, 0)
    kind, item_size = footer_key_kind(schema)
    out: list[tuple[Any, int, int | None]] = []
    for i in range(count):
        o = 4 + i * item_size
        if o + item_size > len(footer):
            break
        if kind.startswith("int"):
            key = u32(footer, o)
            offset = u32(footer, o + 4)
            size = u32(footer, o + 8) if kind.endswith("size") else None
        else:
            key = u64(footer, o)
            offset = u32(footer, o + 8)
            size = u32(footer, o + 12) if kind.endswith("size") else None
        out.append((key, offset, size))
    return out


def decode_value(raw: bytes, offset: int, schema: dict) -> Any:
    t = schema.get("type")
    if t == "float":
        if schema.get("precision") == "double":
            return f64(raw, offset)
        return f32(raw, offset)
    if t == "int":
        return i32(raw, offset)
    if t == "long":
        return u64(raw, offset)
    if t == "bool":
        return raw[offset] == 255
    if t == "string":
        n = u32(raw, offset)
        return raw[offset + 4 : offset + 4 + n].decode("utf-8", errors="replace")
    if t == "dict":
        return decode_dict(raw, offset, schema)
    if t == "list":
        return decode_list(raw, offset, schema)
    if t == "object":
        return decode_object(raw, offset, schema)
    raise ValueError(f"unsupported type {t}")


def decode_dict(raw: bytes, offset: int, schema: dict) -> dict[Any, Any]:
    size_of_data = u32(raw, offset)
    offset_to_data = offset + 4
    # footer size lives at offset + size_of_data
    foot_size_pos = offset + size_of_data
    if foot_size_pos + 4 > len(raw):
        raise ValueError(f"footer size OOB offset={offset} size_of_data={size_of_data}")
    size_of_footer = u32(raw, foot_size_pos)
    foot_start = foot_size_pos - size_of_footer
    footer = raw[foot_start:foot_size_pos]
    entries = parse_footer(footer, schema)
    value_schema = schema["valueTypes"]
    out: dict[Any, Any] = {}
    for key, rel_off, _sz in entries:
        out[key] = decode_value(raw, offset_to_data + rel_off, value_schema)
    return out


def decode_list(raw: bytes, offset: int, schema: dict) -> list:
    count = u32(raw, offset)
    item = schema["itemTypes"]
    fixed = schema.get("fixedItemSize")
    out = []
    if fixed is not None or item.get("size") is not None:
        item_size = int(item.get("size") or fixed or 0)
        for i in range(count):
            out.append(decode_value(raw, offset + 4 + item_size * i, item))
    else:
        for i in range(count):
            rel = u32(raw, offset + 4 + 4 * i)
            out.append(decode_value(raw, offset + rel, item))
    return out


def decode_object(raw: bytes, offset: int, schema: dict) -> dict[str, Any]:
    """Subset: constantAttributeOffsets only (enough for attributes.sd rows)."""
    out: dict[str, Any] = {}
    const = schema.get("constantAttributeOffsets") or {}
    attrs = schema.get("attributes") or {}
    # optional bitfield + variable offsets (simplified)
    end_fixed = int(schema.get("endOfFixedSizeData") or 0)
    optional_lookups = schema.get("optionalValueLookups") or {}
    var_names = list(schema.get("attributesWithVariableOffsets") or [])
    offset_lookup: dict[str, int] = {}
    var_base = offset
    if var_names or optional_lookups:
        opt_field = 0
        if optional_lookups:
            opt_field = u64(raw, offset + end_fixed)
            keep = []
            for name in var_names:
                bit = optional_lookups.get(name)
                if bit is None:
                    keep.append(name)
                    continue
                # pickle may store as int
                if int(opt_field) & int(bit):
                    keep.append(name)
            var_names = keep
        arr_start = offset + end_fixed + (8 if optional_lookups else 0)
        var_base = arr_start + 4 * len(var_names)
        for i, name in enumerate(var_names):
            offset_lookup[name] = u32(raw, arr_start + 4 * i)
    for name, asch in attrs.items():
        if name in const:
            out[name] = decode_value(raw, offset + int(const[name]), asch)
        elif name in offset_lookup:
            out[name] = decode_value(raw, var_base + offset_lookup[name], asch)
        elif "default" in asch:
            out[name] = asch["default"]
    return out


def decode_file(path: Path) -> Any:
    schema, raw, data_off = load_schema_and_data(path)
    return decode_value(raw, data_off, schema), schema


def dump_attributes() -> dict[str, int]:
    data, _schema = decode_file(DOGMA / "attributes.sd")
    # data: attr_id -> object
    name_to_id: dict[str, int] = {}
    id_to_name: dict[int, str] = {}
    for aid, obj in data.items():
        if not isinstance(obj, dict):
            continue
        name = obj.get("attribute_name") or obj.get("en_name") or ""
        if isinstance(name, bytes):
            name = name.decode("utf-8", errors="replace")
        if name:
            name_to_id[str(name)] = int(aid)
            id_to_name[int(aid)] = str(name)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "echoes_attributes_name_to_id.json").write_text(
        json.dumps(name_to_id, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return name_to_id


def dump_type_attributes() -> dict[int, dict[int, float]]:
    data, _schema = decode_file(DOGMA / "type_attributes.sd")
    # Expect: type_id -> {attr_id: float} OR flat (type<<32|attr)->float OR type->{attr:val}
    out: dict[int, dict[int, float]] = {}

    def as_float(v: Any) -> float:
        if isinstance(v, (int, float)):
            return float(v)
        raise TypeError(type(v))

    sample_keys = list(data.keys())[:5]
    sample_vals = [data[k] for k in sample_keys]
    meta = {
        "n_keys": len(data),
        "sample_keys": [str(k) for k in sample_keys],
        "sample_val_types": [type(v).__name__ for v in sample_vals],
        "sample_vals": [],
    }
    for v in sample_vals:
        if isinstance(v, dict):
            items = list(v.items())[:5]
            meta["sample_vals"].append({str(a): b for a, b in items})
        else:
            meta["sample_vals"].append(v)

    # Case A: type_id -> dict(attr_id -> float)
    if sample_vals and isinstance(sample_vals[0], dict):
        for tid, attrs in data.items():
            if not isinstance(attrs, dict):
                continue
            bucket: dict[int, float] = {}
            for aid, val in attrs.items():
                try:
                    bucket[int(aid)] = as_float(val)
                except Exception:
                    continue
            if bucket:
                out[int(tid)] = bucket
    else:
        # Case B: composite key -> float
        for key, val in data.items():
            try:
                fval = as_float(val)
            except Exception:
                continue
            k = int(key)
            tid, aid = k >> 32, k & 0xFFFFFFFF
            if tid == 0:
                # maybe attr<<32|type
                aid, tid = k >> 32, k & 0xFFFFFFFF
            out.setdefault(tid, {})[aid] = fval

    (OUT / "echoes_type_attributes_meta.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    # Don't dump full 14MB JSON unless needed — write slim drone-relevant extract later
    return out


def patch_ships(name_to_id: dict[str, int], type_attrs: dict[int, dict[int, float]]) -> None:
    slots_id = name_to_id.get("droneSlotsLeft")
    bw_id = name_to_id.get("droneBandwidth")
    cap_id = name_to_id.get("droneCapacity")
    max_id = name_to_id.get("maxActiveDrones")
    lines = [
        f"droneSlotsLeft={slots_id}",
        f"droneBandwidth={bw_id}",
        f"droneCapacity={cap_id}",
        f"maxActiveDrones={max_id}",
        "",
    ]
    for p in sorted(SHIPS.glob("*.json"), key=lambda x: int(x.stem)):
        d = json.loads(p.read_text(encoding="utf-8"))
        tid = int(d.get("type_id") or 0)
        attrs = type_attrs.get(tid, {})
        slots_raw = attrs.get(slots_id) if slots_id else None
        bw_raw = attrs.get(bw_id) if bw_id else None
        cap_raw = attrs.get(cap_id) if cap_id else None
        max_raw = attrs.get(max_id) if max_id else None

        if bw_raw is not None:
            d["drone_bandwidth"] = float(bw_raw)
        elif cap_raw is not None:
            d["drone_bandwidth"] = float(cap_raw)

        src = "none"
        if slots_raw is not None and float(slots_raw) > 0:
            n = int(float(slots_raw))
            src = "echoes_droneSlotsLeft"
        elif max_raw is not None and float(max_raw) > 0:
            n = int(float(max_raw))
            src = "echoes_maxActiveDrones"
        else:
            bw = float(d.get("drone_bandwidth") or 0)
            n = int(bw // 5) if bw > 0 else 0
            src = "echoes_bandwidth/5" if bw > 0 else "zero"

        d["drone_bay_slots"] = n
        d["drone_count_cap"] = n
        d.pop("_drone_quota_src", None)
        p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if n > 0 or (bw_raw or slots_raw):
            lines.append(
                f"{d.get('id')}\t{d.get('name')}\ttid={tid}\tslots={n}\tbw={d.get('drone_bandwidth')}\t"
                f"raw_slots={slots_raw}\traw_bw={bw_raw}\tsrc={src}"
            )

    report = Path(__file__).with_name("_echoes_drone_slots_report.txt")
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("report", report)


def main() -> None:
    print("decoding attributes.sd ...")
    name_to_id = dump_attributes()
    want = ["droneSlotsLeft", "droneBandwidth", "droneCapacity", "maxActiveDrones"]
    print({k: name_to_id.get(k) for k in want})
    print("decoding type_attributes.sd ...")
    type_attrs = dump_type_attributes()
    print("types_with_attrs", len(type_attrs))
    # sanity raven 638
    print("type 638", {k: type_attrs.get(638, {}).get(k) for k in [
        name_to_id.get("droneSlotsLeft"),
        name_to_id.get("droneBandwidth"),
        name_to_id.get("droneCapacity"),
    ]})
    patch_ships(name_to_id, type_attrs)
    print("done")


if __name__ == "__main__":
    main()
