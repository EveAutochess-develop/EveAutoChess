# -*- coding: utf-8 -*-
"""Strip baked attack fields from manned ships when equipment kit is resolvable.

Unmanned units unchanged. Capitals whose source_module_type_id is not in
data/equipment/modules.json keep stars[] attack (Echoes kits pending).
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev\godot_project\data")
MODS = json.loads((ROOT / "equipment" / "modules.json").read_text(encoding="utf-8"))

STRIP_KEYS = (
    "damage",
    "repair",
    "tracking",
    "optimal",
    "falloff",
    "optimal_sig_radius",
    "explosion_radius",
    "explosion_velocity",
    "drf",
    "drs",
    "cap_cost",
)


def guns_muted(d: dict) -> bool:
    fx = str(d.get("weapon_fx", ""))
    role = str(d.get("capital_role", ""))
    return role == "carrier" or fx == "mining" or bool(d.get("is_mining_ship", False))


def should_strip(d: dict) -> bool:
    if d.get("is_unmanned"):
        return False
    if guns_muted(d):
        return True
    fx = str(d.get("weapon_fx", ""))
    logistic = bool(d.get("is_logistic", False)) or fx == "heal"
    if logistic:
        rid = int(d.get("source_repair_module_type_id") or 0)
        if rid > 0 and str(rid) in MODS:
            return True
    explicit = int(d.get("source_module_type_id") or 0)
    if explicit > 0:
        return str(explicit) in MODS
    return True


def process_file(path: Path) -> bool:
    d = json.loads(path.read_text(encoding="utf-8"))
    changed = False
    if "source_charge_type_id" in d:
        del d["source_charge_type_id"]
        changed = True
    if not should_strip(d):
        if changed:
            path.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return changed
    stars = d.get("stars")
    if not isinstance(stars, list):
        if changed:
            path.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return changed
    for star in stars:
        if not isinstance(star, dict):
            continue
        for k in STRIP_KEYS:
            if k in star:
                del star[k]
                changed = True
    if changed:
        path.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return changed


def main() -> None:
    n = 0
    for folder in ("ships", "unmanned_units"):
        for path in sorted((ROOT / folder).glob("*.json")):
            if process_file(path):
                n += 1
                print("stripped/updated", path.relative_to(ROOT))
    print(f"done, touched {n} files")


if __name__ == "__main__":
    main()
