# -*- coding: utf-8 -*-
"""Patch battlecruiser slots + representative weapon module from PC SDE hardpoints.

Manned DPH derives at runtime from slots × modules.json (ammo baked into weapons).
"""
from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_content_data as g  # noqa: E402

ROOT = Path(r"H:\game_dev\eveautochess-dev\godot_project\data\ships")
SDE_ZIP = Path(r"H:\game_dev\eveautochess-design\scripts\.sde_cache\eve-online-static-data-latest-jsonl.zip")

# typeID → (weapon_fx, weapon_tier)
BC_FX = {
    16233: ("laser", "large"),  # Prophecy
    22448: ("laser", "medium"),  # Absolution
    24696: ("laser", "medium"),  # Harbinger
    16227: ("rail", "medium"),  # Ferox
    24698: ("missile", "medium"),  # Drake
    16229: ("rail", "medium"),  # Brutix
    24700: ("rail", "medium"),  # Myrmidon
    24702: ("cannon", "medium"),  # Hurricane
    4308: ("rail", "large"),  # Talos
    4306: ("rail", "large"),  # Naga
    4310: ("cannon", "large"),  # Tornado
}


def load_sde_slots() -> dict[int, dict]:
    out: dict[int, dict] = {}
    with zipfile.ZipFile(SDE_ZIP) as z:
        with z.open("typeDogma.jsonl") as f:
            for line in f:
                o = json.loads(line)
                tid = int(o.get("_key") or 0)
                if tid not in BC_FX:
                    continue
                attrs = {int(a["attributeID"]): float(a["value"]) for a in o.get("dogmaAttributes", [])}
                out[tid] = {
                    "hi": int(attrs.get(14, 0)),
                    "med": int(attrs.get(13, 0)),
                    "low": int(attrs.get(12, 0)),
                    "turret": int(attrs.get(102, 0)),
                    "launcher": int(attrs.get(101, 0)),
                }
    return out


def attack_slots(fx: str, slots: dict) -> int:
    if fx == "missile":
        n = int(slots.get("launcher") or 0)
    else:
        n = int(slots.get("turret") or 0)
    if n <= 0:
        n = int(slots.get("hi") or 1)
    return max(1, n)


def main() -> None:
    mods = g.load_modules_json()
    sde = load_sde_slots()
    by_tid: dict[int, Path] = {}
    for p in ROOT.glob("*.json"):
        d = json.loads(p.read_text(encoding="utf-8"))
        if d.get("ship_group") == "battlecruiser":
            by_tid[int(d.get("type_id", 0))] = p

    for tid, (fx, tier) in BC_FX.items():
        path = by_tid.get(tid)
        if path is None:
            print("skip missing json type", tid)
            continue
        slots = sde.get(tid)
        if not slots:
            print("skip missing SDE", tid)
            continue
        d = json.loads(path.read_text(encoding="utf-8"))
        wpn = g.per_slot_weapon(mods, fx, "battlecruiser", tier)
        n = attack_slots(fx, slots)
        d["hi_slots"] = slots["hi"]
        d["med_slots"] = slots["med"]
        d["low_slots"] = slots["low"]
        d["attack_weapon_slots"] = n
        d["weapon_fx"] = fx
        d["weapon_tier"] = tier
        d["attack_cycle_s"] = float(wpn.get("rate_of_fire_s") or d.get("attack_cycle_s") or 1.0)
        d["source_module_type_id"] = int(wpn.get("module_type_id") or 0)
        d.pop("source_charge_type_id", None)
        for st in d.get("stars") or []:
            if not isinstance(st, dict):
                continue
            for k in (
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
            ):
                st.pop(k, None)
            fixed = g.turret_attack_range_cells(fx, "battlecruiser", tier)
            if fixed is not None:
                st["attack_range"] = int(fixed)
        path.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tot = sum(float(v) * n for v in wpn["damage"].values())
        print(
            f"{d.get('name')} tid={tid} hi={slots['hi']} atk_slots={n} "
            f"DPH1={tot:.1f} cycle={d['attack_cycle_s']:.3f}"
        )


if __name__ == "__main__":
    main()
