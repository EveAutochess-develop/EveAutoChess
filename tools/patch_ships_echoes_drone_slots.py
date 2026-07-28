# -*- coding: utf-8 -*-
"""Read Echoes type_attributes.sd: key=u64, value=float.

Echoes stores dogma as flat map. Empirically key packing varies; we try:
  (type_id << 32) | attr_id
  (attr_id << 32) | type_id
and also scan footer keys for our ship type_ids.
"""
from __future__ import annotations

import io
import json
import pickle
import struct
from pathlib import Path

DOGMA = Path(r"H:\eve手游\history\1.0.0_unpacked\art_extract\staticdata\dogma")
SHIPS = Path(__file__).resolve().parents[1] / "godot_project" / "data" / "ships"
OUT_REPORT = Path(__file__).with_name("_echoes_drone_slots_report.txt")

# From attributes.sd name scan + CCP SDE aliases
CANDIDATE_ATTR_NAMES = {
    "droneSlotsLeft": None,
    "droneBandwidth": None,
    "droneCapacity": None,
    "maxActiveDrones": None,
}


def load_sd(path: Path):
    raw = path.read_bytes()
    bio = io.BytesIO(raw[4:])
    schema = pickle.load(bio)
    return schema, raw, 4 + bio.tell()


def read_attr_ids() -> dict[str, int]:
    schema, raw, data_off = load_sd(DOGMA / "attributes.sd")
    data = raw[data_off:]
    kf = schema["keyFooter"]
    fixed = int(kf["fixedItemSize"])
    count = struct.unpack_from("<I", data, len(data) - 4)[0]
    start = len(data) - (count * fixed + 4)
    const = schema["valueTypes"]["constantAttributeOffsets"]
    id_off = const["attribute_id"]
    import re

    out: dict[str, int] = {}
    for i in range(count):
        key, offset, size = struct.unpack_from("<III", data, start + i * fixed)
        row = data[offset : offset + size]
        aid = key
        if id_off + 4 <= len(row):
            emb = struct.unpack_from("<i", row, id_off)[0]
            if emb > 0:
                aid = emb
        for m in re.finditer(rb"[A-Za-z][A-Za-z0-9_]{2,48}", row):
            s = m.group().decode("ascii")
            out[s] = aid
    return out


def read_type_attr_map() -> dict[int, float]:
    """Return {u64_key: float_value}."""
    schema, raw, data_off = load_sd(DOGMA / "type_attributes.sd")
    data = raw[data_off:]
    kf = schema["keyFooter"]
    fixed = int(kf["fixedItemSize"])  # 16
    count = struct.unpack_from("<I", data, len(data) - 4)[0]
    start = len(data) - (count * fixed + 4)
    out: dict[int, float] = {}
    for i in range(count):
        # key is long (8), offset 4, size 4
        key = struct.unpack_from("<Q", data, start + i * fixed)[0]
        offset = struct.unpack_from("<I", data, start + i * fixed + 8)[0]
        size = struct.unpack_from("<I", data, start + i * fixed + 12)[0]
        if size >= 8:
            # valueTypes say float with precision double size 8
            val = struct.unpack_from("<d", data, offset)[0]
        elif size >= 4:
            val = struct.unpack_from("<f", data, offset)[0]
        else:
            continue
        out[key] = float(val)
    return out


def lookup(ta: dict[int, float], tid: int, aid: int) -> float | None:
    for key in ((tid << 32) | aid, (aid << 32) | tid, (tid << 16) | aid, tid * 100000 + aid):
        if key in ta:
            return ta[key]
    return None


def main() -> None:
    names = read_attr_ids()
    for n in list(CANDIDATE_ATTR_NAMES):
        CANDIDATE_ATTR_NAMES[n] = names.get(n)
    # CCP-compatible fallbacks if Echoes names differ
    if not CANDIDATE_ATTR_NAMES["droneSlotsLeft"]:
        CANDIDATE_ATTR_NAMES["droneSlotsLeft"] = names.get("droneBaySlotsLeft")
    lines = [f"ATTR {k}={v}" for k, v in CANDIDATE_ATTR_NAMES.items()]
    ta = read_type_attr_map()
    lines.append(f"type_attr_entries={len(ta)}")

    # Detect packing by probing known Raven 638 bandwidth ~50
    bw_id = CANDIDATE_ATTR_NAMES.get("droneBandwidth")
    pack_mode = "tid_attr"
    if bw_id:
        for mode, keyfn in [
            ("tid_attr", lambda t, a: (t << 32) | a),
            ("attr_tid", lambda t, a: (a << 32) | t),
        ]:
            if keyfn(638, bw_id) in ta:
                pack_mode = mode
                break
        lines.append(f"pack_mode={pack_mode} raven_bw_key_hit={((638 << 32) | bw_id) in ta}")

    def get(tid: int, aid: int | None) -> float | None:
        if not aid:
            return None
        if pack_mode == "attr_tid":
            key = (aid << 32) | tid
        else:
            key = (tid << 32) | aid
        return ta.get(key)

    slots_id = CANDIDATE_ATTR_NAMES["droneSlotsLeft"]
    bw_id = CANDIDATE_ATTR_NAMES["droneBandwidth"]
    cap_id = CANDIDATE_ATTR_NAMES["droneCapacity"]

    for p in sorted(SHIPS.glob("*.json")):
        d = json.loads(p.read_text(encoding="utf-8"))
        tid = int(d.get("type_id") or 0)
        slots = get(tid, slots_id)
        bw = get(tid, bw_id)
        cap = get(tid, cap_id)
        if bw is not None:
            d["drone_bandwidth"] = float(bw)
        if slots is not None and slots > 0:
            d["drone_bay_slots"] = int(slots)
            d["drone_count_cap"] = int(slots)
            src = "echoes_droneSlotsLeft"
        elif bw is not None and bw > 0:
            n = int(bw // 5)
            d["drone_bay_slots"] = n
            d["drone_count_cap"] = n
            src = "echoes_bandwidth/5"
        elif cap is not None and cap > 0:
            n = int(cap // 5)
            d["drone_bay_slots"] = n
            d["drone_count_cap"] = n
            d["drone_bandwidth"] = float(cap)
            src = "echoes_capacity/5"
        else:
            src = d.get("_drone_quota_src", "unchanged")
        d["_drone_quota_src"] = src
        # strip debug? keep for now
        p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        lines.append(
            f"{d.get('id')} {d.get('name')} tid={tid} slots={d.get('drone_bay_slots')} bw={d.get('drone_bandwidth')} src={src} raw_slots={slots}"
        )

    OUT_REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote", OUT_REPORT)


if __name__ == "__main__":
    main()
