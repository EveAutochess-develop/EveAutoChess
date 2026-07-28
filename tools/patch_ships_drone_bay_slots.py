# -*- coding: utf-8 -*-
"""Patch ships drone quota from SDE/Echoes-aligned attrs.

Primary: attribute 106 droneBaySlotsLeft (发射管 / bay slots)
Fallback: maxActiveDrones (352), then floor(droneBandwidth/5)
Also refresh drone_bandwidth from attr 1271 when present.
"""
from __future__ import annotations

import csv
import io
import json
from pathlib import Path

SHIPS = Path(__file__).resolve().parents[1] / "godot_project" / "data" / "ships"
TA = Path(r"H:\game_dev\eveautochess-design\scripts\.sde_cache\dgmTypeAttributes.csv")
LIGHT_BW = 5.0

ATTR_BAY_SLOTS = 106  # droneBaySlotsLeft — 发射管
ATTR_MAX_ACTIVE = 352  # maxActiveDrones
ATTR_BANDWIDTH = 1271  # droneBandwidth
ATTR_CAPACITY = 283  # droneCapacity


def load_type_attrs() -> dict[int, dict[int, float]]:
    text = TA.read_bytes().decode("utf-8-sig")
    # strip BOM leftovers in header
    if text.startswith("\ufeff"):
        text = text[1:]
    r = csv.DictReader(io.StringIO(text))
    # normalize keys
    fields = r.fieldnames or []
    tidk = next(k for k in fields if "type" in k.lower())
    aidk = next(k for k in fields if "attr" in k.lower())
    out: dict[int, dict[int, float]] = {}
    for row in r:
        tid = int(float(str(row[tidk]).strip('"')))
        aid = int(float(row[aidk]))
        vi = row.get("valueInt") or ""
        vf = row.get("valueFloat") or ""
        val = float(vi) if str(vi).strip() not in ("", "None") else float(vf or 0)
        out.setdefault(tid, {})[aid] = val
    return out


def main() -> None:
    ta = load_type_attrs()
    report = []
    for p in sorted(SHIPS.glob("*.json")):
        d = json.loads(p.read_text(encoding="utf-8"))
        tid = int(d.get("type_id") or 0)
        attrs = ta.get(tid, {})
        bay = attrs.get(ATTR_BAY_SLOTS)
        max_act = attrs.get(ATTR_MAX_ACTIVE)
        bw = attrs.get(ATTR_BANDWIDTH)
        cap = attrs.get(ATTR_CAPACITY)

        if bw is not None:
            d["drone_bandwidth"] = float(bw)
        elif cap is not None and float(d.get("drone_bandwidth") or 0) <= 0:
            d["drone_bandwidth"] = float(cap)

        # 发射管额度 → combat drone count
        if bay is not None and bay > 0:
            slots = int(bay)
            src = "droneBaySlotsLeft"
        elif max_act is not None and max_act > 0:
            slots = int(max_act)
            src = "maxActiveDrones"
        else:
            bw_use = float(d.get("drone_bandwidth") or 0)
            slots = int(bw_use // LIGHT_BW) if bw_use > 0 else 0
            src = "bandwidth_fallback"

        d["drone_bay_slots"] = slots
        d["drone_count_cap"] = slots
        d["_drone_quota_src"] = src
        p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        report.append(f"{d.get('id')} {d.get('name')} tid={tid} slots={slots} bw={d.get('drone_bandwidth')} src={src}")

    out = Path(__file__).with_name("_drone_quota_report.txt")
    out.write_text("\n".join(report) + "\n", encoding="utf-8")
    print("patched", len(report), "wrote", out)


if __name__ == "__main__":
    main()
