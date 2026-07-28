# -*- coding: utf-8 -*-
"""Patch ship drone slots from Echoes type_attributes using zh-name → item_id map."""
from __future__ import annotations

import json
from pathlib import Path

from decode_echoes_type_attributes import (
    DOGMA,
    OUT,
    SHIPS,
    decode_file,
    dump_attributes,
)

NAME_ZH = Path(r"H:\eve手游\history\asset_library\indexes\items_id_to_name_zh.json")
REPORT = Path(__file__).with_name("_echoes_drone_slots_report.txt")

# Our roster names → Echoes localization names when they differ.
NAME_ALIASES = {
    "弥尔米顿级": "弥洱米顿级",
    "密尔米顿级": "弥洱米顿级",
}


def load_name_to_echoes_ids() -> dict[str, list[int]]:
    raw = json.loads(NAME_ZH.read_text(encoding="utf-8"))
    out: dict[str, list[int]] = {}
    for k, v in raw.items():
        if not isinstance(v, str):
            continue
        try:
            iid = int(k)
        except ValueError:
            continue
        out.setdefault(v, []).append(iid)
    return out


def pick_ship_item_id(name: str, ids: list[int]) -> int | None:
    """Prefer hull-looking ids (often 10xxxxxxxxx / 105xxxxxxx), avoid skill/bp prefixes."""
    if not ids:
        return None
    if len(ids) == 1:
        return ids[0]
    # Prefer ids that exist in type_attributes and look like ships (1010... / 1030... / 1050...)
    preferred = []
    for iid in ids:
        s = str(iid)
        if s.startswith(("1010", "1011", "1012", "1013", "1030", "1031", "1050", "1051")):
            preferred.append(iid)
    return sorted(preferred or ids)[0]


def main() -> None:
    print("attributes...")
    name_to_attr = dump_attributes()
    slots_id = name_to_attr["droneSlotsLeft"]
    bw_id = name_to_attr["droneBandwidth"]
    cap_id = name_to_attr["droneCapacity"]
    print(f"slots={slots_id} bw={bw_id} cap={cap_id} zh_slots=无人机发射管")

    print("type_attributes...")
    type_attrs, _ = decode_file(DOGMA / "type_attributes.sd")
    # normalize keys to int
    ta: dict[int, dict[int, float]] = {}
    for k, v in type_attrs.items():
        if not isinstance(v, dict):
            continue
        bucket = {}
        for aid, val in v.items():
            if isinstance(val, (int, float)):
                bucket[int(aid)] = float(val)
        ta[int(k)] = bucket

    name_map = load_name_to_echoes_ids()
    lines = [
        f"droneSlotsLeft={slots_id}",
        f"droneBandwidth={bw_id}",
        f"droneCapacity={cap_id}",
        "",
        "id\tname\techoes_item\tslots\tbw\tsrc",
    ]
    missing = []
    for p in sorted(SHIPS.glob("*.json"), key=lambda x: int(x.stem)):
        d = json.loads(p.read_text(encoding="utf-8"))
        if d.get("is_unmanned"):
            continue
        name = str(d.get("name") or "")
        lookup = NAME_ALIASES.get(name, name)
        eids = name_map.get(lookup, []) or name_map.get(name, [])
        eid = pick_ship_item_id(lookup, eids)
        if eid is None or eid not in ta:
            # try exact + variants without 级
            missing.append(name)
            d["drone_bay_slots"] = int(d.get("drone_bay_slots") or 0)
            d["drone_count_cap"] = int(d.get("drone_count_cap") or 0)
            p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            lines.append(f"{d.get('id')}\t{name}\t?\t?\t?\tmissing_echoes_id")
            continue
        attrs = ta[eid]
        slots_raw = attrs.get(slots_id)
        bw_raw = attrs.get(bw_id)
        cap_raw = attrs.get(cap_id)
        if bw_raw is not None:
            d["drone_bandwidth"] = float(bw_raw)
        elif cap_raw is not None:
            d["drone_bandwidth"] = float(cap_raw)

        if slots_raw is not None and float(slots_raw) > 0:
            n = int(float(slots_raw))
            src = "echoes_droneSlotsLeft"
        else:
            bw = float(d.get("drone_bandwidth") or 0)
            n = int(bw // 5) if bw > 0 else 0
            src = "echoes_bandwidth/5" if bw > 0 else "zero"

        d["drone_bay_slots"] = n
        d["drone_count_cap"] = n
        d["echoes_item_id"] = eid
        d.pop("_drone_quota_src", None)
        p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        lines.append(
            f"{d.get('id')}\t{name}\t{eid}\t{n}\t{d.get('drone_bandwidth')}\t{src}\traw_slots={slots_raw}"
        )

    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    # slim extract for ships we care about
    slim = {}
    for p in SHIPS.glob("*.json"):
        d = json.loads(p.read_text(encoding="utf-8"))
        eid = d.get("echoes_item_id")
        if not eid:
            continue
        attrs = ta.get(int(eid), {})
        slim[str(d["id"])] = {
            "name": d.get("name"),
            "echoes_item_id": eid,
            "droneSlotsLeft": attrs.get(slots_id),
            "droneBandwidth": attrs.get(bw_id),
            "droneCapacity": attrs.get(cap_id),
            "drone_bay_slots": d.get("drone_bay_slots"),
        }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "echoes_ship_drone_slots.json").write_text(
        json.dumps(slim, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("wrote", REPORT)
    print("missing", len(missing), missing[:10])
    # print ships with slots from true droneSlotsLeft
    n_slots = sum(1 for line in lines if "echoes_droneSlotsLeft" in line)
    n_bw = sum(1 for line in lines if "echoes_bandwidth/5" in line)
    print("from_slots", n_slots, "from_bw", n_bw)


if __name__ == "__main__":
    main()
