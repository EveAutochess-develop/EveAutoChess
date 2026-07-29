# -*- coding: utf-8 -*-
import csv
import json
from pathlib import Path

SDE = Path(r"H:\game_dev\eveautochess-design\scripts\.sde_cache")
SHIPS = Path(r"H:\game_dev\eveautochess-dev\godot_project\data\ships")

SHIP_TYPE_IDS = {
    111: 19720,
    112: 19724,
    113: 19726,
    114: 19722,
    121: 23757,
    122: 23915,
    123: 23911,
    124: 24483,
    131: 37604,
    132: 37605,
    133: 37606,
    134: 37607,
}


def clean(s: str) -> str:
    return s.lstrip("\ufeff").strip().strip('"')


volumes = {}
with (SDE / "invTypes.csv").open(encoding="utf-8", newline="") as f:
    reader = csv.reader(f)
    next(reader)
    want = set(str(t) for t in SHIP_TYPE_IDS.values())
    for row in reader:
        if not row:
            continue
        tid = clean(row[0])
        if tid in want:
            volumes[int(tid)] = float(row[5])  # volume

for sid, tid in SHIP_TYPE_IDS.items():
    path = SHIPS / f"{sid}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    vol = volumes.get(tid, 0.0)
    if vol > 0:
        # Empirically long-axis ≈ 2.2 * cbrt(volume) for TQ hulls vs Echoes battleship axis.
        axis = round((vol ** (1.0 / 3.0)) * 2.2, 1)
        data["model_long_axis"] = axis
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(sid, tid, "vol", vol, "axis", axis)
    else:
        print("no volume", sid, tid)
