# -*- coding: utf-8 -*-
"""Add missing 5 weapons (capital×4 + large missile) from ship body reverse-bake.

Capital: per-slot = stars[0].damage / hi_slots; RoF = attack_cycle_s×1000; keep Echoes typeIDs.
Large missile: clone 501 damage into Cruise Missile Launcher I (13320); RoF from BS cycle.
Then point large missile hulls to 13320 and strip attack fields from dread stars.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev\godot_project\data")
MODS_PATH = ROOT / "equipment" / "modules.json"
DESIGN_MODS = Path(r"H:\game_dev\eveautochess-design\docs\_extracted\modules_raw.json")

MPC = 500.0  # weapon_kit_meters_per_cell
STRIP = (
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

# dread id → capital weapon typeID already on hull
CAPITAL_SHIPS = {
    111: ("laser", "旗舰激光", "Capital Pulse Laser Kit", 11002810000),
    112: ("rail", "旗舰磁轨", "Capital Railgun Kit", 11000320000),
    113: ("missile", "旗舰导弹", "Capital Missile Launcher Kit", 11023000000),
    114: ("cannon", "旗舰加农", "Capital Autocannon Kit", 11004810000),
}

LARGE_MISSILE_ID = 13320


def load_ship(sid: int) -> dict:
    return json.loads((ROOT / "ships" / f"{sid}.json").read_text(encoding="utf-8"))


def reverse_capital(sid: int, fx: str, name_zh: str, name_en: str, tid: int) -> dict:
    d = load_ship(sid)
    slots = int(d.get("attack_weapon_slots") or d.get("hi_slots") or 1)
    slots = max(slots, 1)
    st = (d.get("stars") or [{}])[0]
    dmg = st.get("damage") or {}
    cycle_s = float(d.get("attack_cycle_s") or 1.0)
    opt_cells = float(st.get("optimal") or 0.0)
    fall_cells = float(st.get("falloff") or 0.0)
    mod = {
        "typeID": tid,
        "nameZH": name_zh,
        "nameEN": name_en,
        "nameSDE": name_en,
        "kind": "weapon",
        "weapon_fx": fx,
        "weapon_tier": "capital",
        "source_ship_id": sid,
        "emDamage": round(float(dmg.get("emp") or 0) / slots, 4),
        "thermalDamage": round(float(dmg.get("thermal") or 0) / slots, 4),
        "kineticDamage": round(float(dmg.get("kinetic") or 0) / slots, 4),
        "explosiveDamage": round(float(dmg.get("explosive") or 0) / slots, 4),
        "trackingSpeed": float(st.get("tracking") or 0.0),
        "maxRange": opt_cells * MPC,
        "falloff": fall_cells * MPC,
        "signatureResolution": float(st.get("optimal_sig_radius") or 2000.0),
        "rateOfFire": round(cycle_s * 1000.0, 3),
        "techLevel": 1.0,
        "metaLevel": 0.0,
        "metaGroupID": 1,
        "hp": 40.0,
        "_reverse_note": f"from ship {sid} ★1 damage/{slots} slots, cycle {cycle_s}s",
    }
    if fx == "missile":
        # No explosion on hull stars — inherit scaled heavy-missile ballistics.
        heavy = json.loads(MODS_PATH.read_text(encoding="utf-8")).get("501", {})
        mod["explosionRadius"] = float(heavy.get("explosionRadius") or 140.0) * 4.0
        mod["explosionVelocity"] = float(heavy.get("explosionVelocity") or 85.0) * 0.5
        mod["aoeDamageReductionFactor"] = float(heavy.get("aoeDamageReductionFactor") or 0.682)
    return mod


def make_large_missile(mods: dict) -> dict:
    heavy = mods["501"]
    # Battleship missile hulls use attack_cycle_s=15 → keep same RoF as 501.
    return {
        "typeID": LARGE_MISSILE_ID,
        "nameZH": "巡航导弹发射器",
        "nameEN": "Cruise Missile Launcher I",
        "nameSDE": "Cruise Missile Launcher I",
        "groupID": 506,
        "kind": "weapon",
        "weapon_fx": "missile",
        "weapon_tier": "large",
        "rateOfFire": float(heavy.get("rateOfFire") or 15000.0),
        "power": float(heavy.get("power") or 100.0),
        "cpu": float(heavy.get("cpu") or 50.0),
        "hp": 40.0,
        "techLevel": 1.0,
        "metaLevel": 0.0,
        "metaGroupID": 1,
        "emDamage": float(heavy.get("emDamage") or 0),
        "thermalDamage": float(heavy.get("thermalDamage") or 0),
        "kineticDamage": float(heavy.get("kineticDamage") or 0),
        "explosiveDamage": float(heavy.get("explosiveDamage") or 0),
        "explosionRadius": float(heavy.get("explosionRadius") or 140.0) * 2.0,
        "explosionVelocity": float(heavy.get("explosionVelocity") or 85.0) * 0.75,
        "aoeDamageReductionFactor": float(heavy.get("aoeDamageReductionFactor") or 0.682),
        "_reverse_note": "cloned from 501 to split large vs medium missile kits; BS cycle 15s",
    }


def strip_star_attack(d: dict) -> bool:
    changed = False
    for st in d.get("stars") or []:
        if not isinstance(st, dict):
            continue
        for k in STRIP:
            if k in st:
                del st[k]
                changed = True
    return changed


def main() -> None:
    mods = json.loads(MODS_PATH.read_text(encoding="utf-8"))
    for sid, (fx, zh, en, tid) in CAPITAL_SHIPS.items():
        mod = reverse_capital(sid, fx, zh, en, tid)
        mods[str(tid)] = mod
        print(
            "capital",
            sid,
            tid,
            "per_slot",
            {
                "emp": mod["emDamage"],
                "th": mod["thermalDamage"],
                "ki": mod["kineticDamage"],
                "ex": mod["explosiveDamage"],
            },
            "rof_ms",
            mod["rateOfFire"],
        )

    mods[str(LARGE_MISSILE_ID)] = make_large_missile(mods)
    print("large missile", LARGE_MISSILE_ID, mods[str(LARGE_MISSILE_ID)]["emDamage"])

    MODS_PATH.write_text(json.dumps(mods, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if DESIGN_MODS.parent.exists():
        DESIGN_MODS.write_text(json.dumps(mods, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # Wire dreads: ensure mid + attack_weapon_slots, strip baked attack
    for sid, (_fx, _zh, _en, tid) in CAPITAL_SHIPS.items():
        path = ROOT / "ships" / f"{sid}.json"
        d = json.loads(path.read_text(encoding="utf-8"))
        d["source_module_type_id"] = tid
        d["attack_weapon_slots"] = int(d.get("hi_slots") or 5)
        d.pop("source_charge_type_id", None)
        strip_star_attack(d)
        path.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("wired dread", sid, "→", tid)

    # Wire large missile ships (battleship + weapon_tier large / group battleship missile)
    n = 0
    for path in sorted((ROOT / "ships").glob("*.json")):
        d = json.loads(path.read_text(encoding="utf-8"))
        if str(d.get("weapon_fx", "")) != "missile":
            continue
        tier = str(d.get("weapon_tier", ""))
        group = str(d.get("ship_group", ""))
        if tier == "capital" or str(d.get("capital_role", "")) == "dreadnought":
            continue  # capital missile already wired
        if tier == "large" or group == "battleship":
            if int(d.get("source_module_type_id") or 0) == 0 and group == "battleship" and not d.get("shop_eligible", True):
                # sleeper etc. with no kit — skip if no mid and no hi
                if int(d.get("hi_slots") or 0) <= 0:
                    continue
            d["source_module_type_id"] = LARGE_MISSILE_ID
            d["weapon_tier"] = "large"
            d.pop("source_charge_type_id", None)
            path.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            n += 1
            print("wired large missile", d.get("id"), d.get("name"))
    print("large-missile hulls", n)
    print("weapon count", sum(1 for v in mods.values() if v.get("kind") == "weapon"))


if __name__ == "__main__":
    main()
