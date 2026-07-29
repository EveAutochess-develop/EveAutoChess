# -*- coding: utf-8 -*-
"""Patch battlecruiser damage: PC SDE attack hardpoints × T1 kit DPH (×1/×2/×3 stars)."""
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
    22470: ("missile", "medium"),  # Nighthawk
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
                attrs = {int(a["attributeID"]): float(a["value"]) for a in (o.get("dogmaAttributes") or [])}
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
    mods = g.load_preferred_json(g.MODS_RAW_LATEST, g.MODS_RAW)
    charges = g.load_preferred_json(g.CHARGES_RAW_LATEST, g.CHARGES_RAW)
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
        wpn = g.per_slot_weapon(mods, charges, fx, "battlecruiser", tier)
        n = attack_slots(fx, slots)
        dmg1 = {k: round(float(v) * n, 2) for k, v in wpn["damage"].items()}
        d["hi_slots"] = slots["hi"]
        d["med_slots"] = slots["med"]
        d["low_slots"] = slots["low"]
        d["attack_weapon_slots"] = n
        d["weapon_fx"] = fx
        d["weapon_tier"] = tier
        d["attack_cycle_s"] = float(wpn.get("rate_of_fire_s") or d.get("attack_cycle_s") or 1.0)
        d["source_module_type_id"] = int(wpn.get("module_type_id") or 0)
        d["source_charge_type_id"] = int(wpn.get("charge_type_id") or 0)
        stars = d.get("stars") or []
        for i, mul in enumerate((1, 2, 3)):
            if i >= len(stars):
                break
            st = stars[i]
            st["damage"] = {k: round(v * mul, 2) for k, v in dmg1.items()}
            st["tracking"] = float(wpn.get("tracking") or st.get("tracking") or 0.0)
            st["optimal"] = float(wpn.get("optimal") or st.get("optimal") or 0.0)
            st["falloff"] = float(wpn.get("falloff") or st.get("falloff") or 0.0)
            st["optimal_sig_radius"] = float(wpn.get("optimal_sig_radius") or st.get("optimal_sig_radius") or 40.0)
            if fx == "missile":
                st["explosion_radius"] = float(wpn.get("explosion_radius") or 0.0)
                st["explosion_velocity"] = float(wpn.get("explosion_velocity") or 0.0)
                st["drf"] = float(wpn.get("drf") or 0.0)
            # Keep design-locked attack_range for turrets when present.
            fixed = g.turret_attack_range_cells(fx, "battlecruiser", tier)
            if fixed is not None:
                st["attack_range"] = int(fixed)
        path.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tot = sum(dmg1.values())
        print(
            f"{d.get('name')} tid={tid} hi={slots['hi']} atk_slots={n} "
            f"DPH1={tot:.1f} cycle={d['attack_cycle_s']:.3f}"
        )


if __name__ == "__main__":
    main()
