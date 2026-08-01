# -*- coding: utf-8 -*-
"""Re-pull battleship hull HP from TQ SDE dgmTypeAttributes (SHIP_STATS_V2 §2.1).

Ships 44..63 shipped with one flat placeholder (2000/2800/1400) for every hull.
Only the three HP layers are rewritten; resists / sig / speed stay untouched.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev\godot_project")
SDE = Path(r"H:\game_dev\eveautochess-design\scripts\.sde_cache")
SHIPS = ROOT / "data" / "ships"

## id -> TQ typeID. 63 (死亡漩涡级) is excluded: its type_id 22852 is the Hel
## supercarrier, not a battleship hull — needs a design decision first.
SHIP_TYPE_IDS = {
    44: 643,    # Armageddon 末日沙场级
    45: 642,    # Apocalypse 灾难级
    46: 24692,  # Abaddon 地狱天使级
    50: 640,    # Scorpion 毒蝎级
    51: 638,    # Raven 乌鸦级
    52: 24688,  # Rokh 鹏鲲级
    56: 645,    # Dominix 多米尼克斯级
    57: 641,    # Megathron 万王宝座级
    58: 24690,  # Hyperion 亥伯龙神级
    59: 639,    # Tempest 暴风级
    61: 644,    # Typhoon 台风级
    62: 24694,  # Maelstrom 狂暴级
}

HP_ATTRS = {"shieldCapacity", "armorHP", "hp"}


def _clean(s: str) -> str:
    return s.lstrip("\ufeff").strip().strip('"')


def load_attr_names() -> dict[int, str]:
    out: dict[int, str] = {}
    with (SDE / "dgmAttributeTypes.csv").open(encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if not row or len(row) < 2 or not row[0]:
                continue
            try:
                out[int(_clean(row[0]))] = row[1]
            except ValueError:
                continue
    return out


def load_hp(type_ids: set[int], attrs: dict[int, str]) -> dict[int, dict[str, float]]:
    vals: dict[int, dict[str, float]] = {tid: {} for tid in type_ids}
    with (SDE / "dgmTypeAttributes.csv").open(encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if not row or len(row) < 2 or not row[0]:
                continue
            try:
                tid = int(_clean(row[0]))
            except ValueError:
                continue
            if tid not in type_ids:
                continue
            try:
                aid = int(_clean(row[1]))
            except ValueError:
                continue
            name = attrs.get(aid, "")
            if name not in HP_ATTRS:
                continue
            raw = row[3] if len(row) > 3 and row[3] not in ("", None) else (row[2] if len(row) > 2 else "0")
            vals[tid][name] = float(raw or 0.0)
    return vals


def patch_ship(ship_id: int, type_id: int, st: dict[str, float], apply: bool) -> None:
    path = SHIPS / f"{ship_id}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    shield = float(st["shieldCapacity"])
    armor = float(st["armorHP"])
    structure = float(st["hp"])
    star0 = (data.get("stars") or [{}])[0]
    print(
        f"{ship_id:>3} {data.get('name','')!s:<8} {data.get('name_en','')!s:<12} "
        f"old {star0.get('shield_hp',0):>6.0f}/{star0.get('armor_hp',0):>6.0f}/"
        f"{star0.get('structure_hp',0):>6.0f}  ->  new {shield:>6.0f}/{armor:>6.0f}/{structure:>6.0f}"
    )
    if not apply:
        return
    for i, star in enumerate(data.get("stars", [])):
        mul = float(i + 1)
        star["shield_hp"] = round(shield * mul, 1)
        star["armor_hp"] = round(armor * mul, 1)
        star["structure_hp"] = round(structure * mul, 1)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    apply = "--apply" in sys.argv
    attrs = load_attr_names()
    vals = load_hp(set(SHIP_TYPE_IDS.values()), attrs)
    for ship_id, type_id in SHIP_TYPE_IDS.items():
        st = vals.get(type_id, {})
        if not HP_ATTRS <= st.keys():
            print(f"WARN missing HP dogma for {ship_id} type {type_id}: {st}")
            continue
        patch_ship(ship_id, type_id, st, apply)
    print("APPLIED" if apply else "DRY RUN (pass --apply to write)")


if __name__ == "__main__":
    main()
