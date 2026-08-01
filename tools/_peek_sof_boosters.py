# -*- coding: utf-8 -*-
import json
from pathlib import Path

h = json.loads(Path("_extracted/sof_hull_boosters.json").read_text(encoding="utf-8"))
for name in [
    "af1_t1",
    "af4_t1",
    "gf4_t1",
    "cb1_t1",
    "mb1_t1",
    "oreba2_t1",
    "oreb1_t1",
    "orefr1_t1",
    "orecs1_t1",
    "adn1_t1",
]:
    info = h.get(name)
    if not info:
        print(name, "MISSING")
        continue
    items = info["items"]
    print(f"{name}: nozzles={len(items)} geo={info['geometry']}")
    for i, it in enumerate(items[:3]):
        t = it["transform"]
        print(" ", i, "trail", it["has_trail"], "xf", [[round(x, 3) for x in row] for row in t])
