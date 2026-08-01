# -*- coding: utf-8 -*-
"""Fold charge damage into weapon modules; prune unused equipment; drop charges.json.

Per SHIP_STATS_V2: Autochess kits are weapons(+repair) only — ammo is baked into the gun.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev\godot_project\data")
DESIGN_EXT = Path(r"H:\game_dev\eveautochess-design\docs\_extracted")

# module_id -> charge_id (WEAPON_KIT)
FOLD = {
    453: 246,
    456: 254,
    462: 262,
    485: 185,
    491: 193,
    498: 199,
    499: 210,
    501: 209,
    561: 222,
    570: 230,
    574: 238,
}
MISSILE_MODS = {499, 501}
# Not in WEAPON_KIT / REPAIR_KIT / any ship source_* (uninstalled ewar/blaster stubs)
PRUNE = {530, 533, 573, 3242, 12709}
KEEP_REPAIR = {11355, 11357, 11359, 3586, 3596, 3606, 27932, 27930, 27904}


def bake_damage(mod: dict, charge: dict, is_missile: bool) -> None:
    mult = 1.0 if is_missile else float(mod.get("damageMultiplier") or 1.0)
    em = mult * float(charge.get("emDamage") or 0)
    th = mult * float(charge.get("thermalDamage") or 0)
    ki = mult * float(charge.get("kineticDamage") or 0)
    ex = mult * float(charge.get("explosiveDamage") or 0)
    if is_missile:
        total = em + th + ki + ex
        if total > 0:
            each = total / 4.0
            em = th = ki = ex = each
        for k in ("explosionRadius", "explosionVelocity", "aoeDamageReductionFactor"):
            if charge.get(k) is not None:
                mod[k] = float(charge[k])
    mod["emDamage"] = round(em, 4)
    mod["thermalDamage"] = round(th, 4)
    mod["kineticDamage"] = round(ki, 4)
    mod["explosiveDamage"] = round(ex, 4)
    mod["kind"] = "weapon"
    # Historical ammo id for extract/debug only — runtime does not load charges.
    mod["baked_charge_type_id"] = int(charge.get("typeID") or 0)


def main() -> None:
    mods_path = ROOT / "equipment" / "modules.json"
    charges_path = ROOT / "equipment" / "charges.json"
    mods = json.loads(mods_path.read_text(encoding="utf-8"))
    charges = json.loads(charges_path.read_text(encoding="utf-8"))

    for mid, cid in FOLD.items():
        key = str(mid)
        if key not in mods:
            raise SystemExit(f"missing module {mid}")
        if str(cid) not in charges:
            raise SystemExit(f"missing charge {cid}")
        bake_damage(mods[key], charges[str(cid)], mid in MISSILE_MODS)

    for rid in KEEP_REPAIR:
        key = str(rid)
        if key in mods:
            mods[key]["kind"] = "repair"

    for pid in PRUNE:
        mods.pop(str(pid), None)

    # Keep only folded weapons + repairs
    keep = {str(x) for x in list(FOLD.keys()) + list(KEEP_REPAIR)}
    for k in list(mods.keys()):
        if k not in keep:
            print("extra prune", k, mods[k].get("nameEN"))
            del mods[k]

    mods_path.write_text(json.dumps(mods, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if charges_path.exists():
        charges_path.unlink()
        print("deleted", charges_path)

    # Mirror into design extract modules_raw (charges_raw left as historical dump)
    raw_out = DESIGN_EXT / "modules_raw.json"
    if raw_out.parent.exists():
        raw_out.write_text(json.dumps(mods, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("wrote", raw_out)

    # Strip source_charge_type_id from ships
    n = 0
    for folder in ("ships", "unmanned_units"):
        for path in sorted((ROOT / folder).glob("*.json")):
            d = json.loads(path.read_text(encoding="utf-8"))
            if "source_charge_type_id" in d:
                del d["source_charge_type_id"]
                path.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                n += 1
    print(f"stripped source_charge_type_id from {n} files")
    print("modules left:", sorted(int(k) for k in mods.keys()))


if __name__ == "__main__":
    main()
