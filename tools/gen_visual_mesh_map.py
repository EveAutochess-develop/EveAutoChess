# -*- coding: utf-8 -*-
"""Rebuild visual_meshes.json + ship_textures.json for 40 ships (ASCII model_key paths)."""
import csv
import json
from pathlib import Path

CSV_PATH = Path(r"H:\game_dev\eveautochess-design\docs\_extracted\amarr_counterparts.csv")
OUT = Path(r"H:\game_dev\eveautochess-dev\godot_project\data")

rows = list(csv.DictReader(CSV_PATH.read_text(encoding="utf-8").splitlines()))
meshes = {}
textures = {}
portraits = {}
for row in rows:
    for col in ("amarr", "caldari", "minmatar", "gallente"):
        sid = row[f"{col}_id"]
        key = row[f"{col}_key"]
        meshes[sid] = f"res://assets/models/ships/{key}.glb"
        textures[sid] = f"res://assets/models/ships/{key}_ad.png"
        portraits[sid] = f"res://assets/ui/portraits/{key}.png"

(OUT / "visual_meshes.json").write_text(
    json.dumps({"ships": meshes}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
(OUT / "ship_textures.json").write_text(
    json.dumps({"ships": textures}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
portraits_path = OUT / "ship_portraits.json"
portraits_path.write_text(
    json.dumps({"ships": portraits}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
print("wrote", len(meshes), "mesh/texture/portrait entries")
