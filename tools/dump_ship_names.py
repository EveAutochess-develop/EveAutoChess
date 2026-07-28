# -*- coding: utf-8 -*-
import glob
import json
import os

ships = os.path.join(os.path.dirname(__file__), "..", "godot_project", "data", "ships")
out = []
for p in sorted(glob.glob(os.path.join(ships, "*.json")), key=lambda x: int(os.path.splitext(os.path.basename(x))[0])):
    d = json.load(open(p, encoding="utf-8"))
    out.append(f"{d['id']}\t{d['name']}\t{d.get('model_key','')}")
path = os.path.join(os.path.dirname(__file__), "_ship_names_dump.txt")
open(path, "w", encoding="utf-8").write("\n".join(out))
print("wrote", len(out), path)
