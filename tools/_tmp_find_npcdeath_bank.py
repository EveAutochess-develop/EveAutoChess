# -*- coding: utf-8 -*-
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, r"H:\game_dev\eveautochess-dev\tools")
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

info = json.loads(Path(fetch_resfile("res:/audio/soundbanksinfo.json")).read_text(encoding="utf-8"))
banks = info["SoundBanksInfo"]["SoundBanks"]
want = (
    "npcdeath",
    "npc-death",
    "fire_wreck",
    "asteroid_death",
    "poddeath",
    "pod-explode",
    "wreck_spark",
    "shipsfx",
    "individual_explosion",
)
hits = []
for b in banks:
    media = b.get("Media") or []
    matched = []
    for m in media:
        sn = str(m.get("ShortName") or "").lower()
        if any(k in sn for k in want):
            matched.append(m.get("ShortName"))
    if matched:
        print(
            "BANK",
            b.get("ShortName"),
            "Path",
            b.get("Path"),
            "ObjectPath",
            b.get("ObjectPath"),
            "matched",
            len(matched),
        )
        for sn in matched[:25]:
            print(" ", sn)
        hits.append(b.get("ShortName"))
print("banks with hits", hits)
