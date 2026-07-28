# -*- coding: utf-8 -*-
"""Patch ships/*.json: drone_bandwidth, attack_cycle_s, strip function_slots.count."""
from __future__ import annotations

import json
import glob
import os

SHIPS = os.path.join(os.path.dirname(__file__), "..", "godot_project", "data", "ships")
BW = {
    "frigate": 15.0,
    "destroyer": 25.0,
    "cruiser": 50.0,
    "battlecruiser": 50.0,
    "battleship": 75.0,
}


def main() -> None:
    paths = sorted(glob.glob(os.path.join(SHIPS, "*.json")))
    for p in paths:
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
        g = d.get("ship_group") or (d.get("ship_groups") or ["frigate"])[0]
        if "drone_bandwidth" not in d or float(d.get("drone_bandwidth") or 0) <= 0:
            d["drone_bandwidth"] = float(BW.get(g, 15.0))
        if float(d.get("attack_cycle_s") or 0) <= 0:
            d["attack_cycle_s"] = 2.0 if d.get("is_logistic") else 2.5
        fs = d.get("function_slots")
        if isinstance(fs, dict):
            d["function_slots"] = {"slots": list(fs.get("slots") or [])}
        d.setdefault("is_unmanned", False)
        d.setdefault("unmanned_kind", "")
        with open(p, "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False, indent=2)
            f.write("\n")
    print(f"patched {len(paths)} ships")


if __name__ == "__main__":
    main()
