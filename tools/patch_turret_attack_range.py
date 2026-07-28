# -*- coding: utf-8 -*-
"""Batch-write stars[].attack_range from design-locked turret/repair/missile tables."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_content_data import turret_attack_range_cells

ships_dir = Path(__file__).resolve().parent.parent / "godot_project" / "data" / "ships"
count = 0
for fp in sorted(ships_dir.glob("*.json")):
    d = json.loads(fp.read_text(encoding="utf-8"))
    wfx = str(d.get("weapon_fx", "laser"))
    group = str(d.get("ship_group", "frigate"))
    rng = turret_attack_range_cells(wfx, group)
    if rng is None:
        continue
    for star in d.get("stars", []):
        star["attack_range"] = rng
    fp.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    count += 1
print(f"patched {count} ships")
