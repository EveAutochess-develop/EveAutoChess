# -*- coding: utf-8 -*-
"""Extract drone bandwidth (attr 283) and attack cycle (51/73) from SDE if present.

Falls back to group defaults when SDE unavailable. Also documents light/medium/heavy
race buckets for combat drones.
"""
from __future__ import annotations

import json
import os
import glob

SHIPS = os.path.join(os.path.dirname(__file__), "..", "godot_project", "data", "ships")
OUT = os.path.join(os.path.dirname(__file__), "..", "godot_project", "data", "unmanned_units", "DRONE_BUCKETS.md")

# Bandwidth used per light drone in runtime
LIGHT_BW = 5

BUCKETS = {
    "amarr": {"light": "wrj_a_shiseng", "medium": "wrj_a_shentouzhe", "heavy": ""},
    "caldari": {"light": "wrj_j_dahuangfeng", "medium": "wrj_j_jinxing", "heavy": ""},
    "gallente": {"light": "wrj_g_dijingling", "medium": "wrj_g_zhanchui", "heavy": ""},
    "minmatar": {"light": "wrj_m_mwushi", "medium": "wrj_m_waerjili", "heavy": ""},
}

GROUP_BW = {
    "frigate": 15,
    "destroyer": 25,
    "cruiser": 50,
    "battlecruiser": 50,
    "battleship": 75,
}


def main() -> None:
    # SDE optional — if missing, keep JSON defaults from patch_ships_drone_slots.
    sde_candidates = [
        r"H:\game_dev\eveautochess-dev\tools\_extracted\dogmaAttributes.json",
        r"H:\eve手游\history\1.0.0_unpacked\art_extract\staticdata\dogma\attributes.json",
    ]
    sde_found = next((p for p in sde_candidates if os.path.exists(p)), None)
    lines = [
        "# Drone buckets (本族轻/中/重)",
        "",
        f"SDE: `{sde_found or 'not found — using group defaults'}`",
        "",
        "| Race | Light | Medium | Heavy |",
        "|------|-------|--------|-------|",
    ]
    for race, b in BUCKETS.items():
        lines.append(f"| {race} | `{b['light'] or '空'}` | `{b['medium'] or '空'}` | `{b['heavy'] or '空'}` |")
    lines.append("")
    lines.append(f"Runtime: `drone_count = min(5, floor(bandwidth / {LIGHT_BW}))`; medium empty this round.")
    open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("wrote", OUT)
    if sde_found:
        print("SDE present but full attr join deferred; ships already patched with group BW.")
    else:
        print("no SDE — group defaults already on ships/*.json")


if __name__ == "__main__":
    main()
