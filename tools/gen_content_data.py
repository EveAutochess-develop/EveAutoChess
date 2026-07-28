# -*- coding: utf-8 -*-
"""Generate ships/*.json (40) from EVEMU/SDE extract + amarr_counterparts.csv.

Does NOT overwrite balance/ or fetters/ (those are maintained separately).
Star scaling: HP / damage / repair ×1/×2/×3. Resists & base attrs unscaled.
"""
from __future__ import annotations

import csv
import json
import math
from pathlib import Path

DEV_ROOT = Path(r"H:\game_dev\eveautochess-dev\godot_project\data")
DESIGN_EXT = Path(r"H:\game_dev\eveautochess-design\docs\_extracted")
CSV_PATH = DESIGN_EXT / "amarr_counterparts.csv"
SHIPS_RAW = DESIGN_EXT / "ships_raw.json"
MODS_RAW = DESIGN_EXT / "modules_raw.json"
CHARGES_RAW = DESIGN_EXT / "charges_raw.json"
SHIPS_RAW_LATEST = DESIGN_EXT / "ships_raw_latest.json"
MODS_RAW_LATEST = DESIGN_EXT / "modules_raw_latest.json"
CHARGES_RAW_LATEST = DESIGN_EXT / "charges_raw_latest.json"
DRONE_SLOTS_JSON = DEV_ROOT / "_extracted" / "echoes_ship_drone_slots.json"
LONG_AXIS_JSON = DEV_ROOT / "_extracted" / "echoes_ship_model_long_axis.json"

METERS_PER_CELL = 500.0

UNIFIED_COST_BY_GROUP = {
    "frigate": 2,
    "destroyer": 2,
    "cruiser": 4,
    "battlecruiser": 6,
    "battleship": 12,
}

# Turret / repair attack_range (grid cells) — design-locked; see COMBAT.md §3.1
TURRET_RANGE_CELLS = {
    "small": {"rail": 2, "laser": 3, "cannon": 4},
    "medium": {"rail": 4, "laser": 6, "cannon": 8},
    "large": {"rail": 10, "laser": 13, "cannon": 16},
}
# Logistic heal range by tonnage tier (not by weapon kit)
REPAIR_RANGE_CELLS = {
    "small": 4,
    "medium": 8,
    "large": 12,
}


def ship_group_size_tier(ship_group: str, weapon_tier: str = "") -> str:
    if weapon_tier in ("small", "medium", "large"):
        return weapon_tier
    if ship_group in ("frigate", "destroyer"):
        return "small"
    if ship_group in ("cruiser", "battlecruiser"):
        return "medium"
    if ship_group == "battleship":
        return "large"
    return "small"


def weapon_kit_size_key(ship_group: str, weapon_tier: str = "") -> str:
    tier = ship_group_size_tier(ship_group, weapon_tier)
    if tier == "small":
        return "frigate"
    if tier == "large":
        return "large"
    return "cruiser"


def turret_attack_range_cells(weapon_fx: str, ship_group: str, weapon_tier: str = "") -> int | None:
    """Return fixed grid range: turrets by fx+tier; missile 999; heal by tier; else None."""
    if weapon_fx == "missile":
        return 999
    if weapon_fx == "heal":
        tier = ship_group_size_tier(ship_group, weapon_tier)
        return int(REPAIR_RANGE_CELLS.get(tier, REPAIR_RANGE_CELLS["small"]))
    if weapon_fx not in ("rail", "laser", "cannon"):
        return None
    tier = ship_group_size_tier(ship_group, weapon_tier)
    table = TURRET_RANGE_CELLS.get(tier, TURRET_RANGE_CELLS["small"])
    return int(table.get(weapon_fx, table["laser"]))

# race → representative T1 modules / charges
WEAPON_KIT = {
    "laser": {
        "frigate": (453, 246),
        "destroyer": (453, 246),
        "cruiser": (456, 254),
        "large": (462, 262),
    },
    "rail": {
        "frigate": (561, 222),
        "destroyer": (561, 222),
        "cruiser": (570, 230),
        "large": (574, 238),
    },
    "cannon": {
        "frigate": (485, 185),
        "destroyer": (485, 185),
        "cruiser": (491, 193),
        "large": (498, 199),
    },
    "missile": {
        "frigate": (499, 210),
        "destroyer": (499, 210),
        "cruiser": (501, 209),
        "large": (501, 209),
    },
}
REPAIR_KIT = {
    # race → frigate / cruiser / large module type ids
    "amarr": (11355, 11357, 11359),  # Remote Armor Repairer I
    "caldari": (3586, 3596, 3606),  # Remote Shield Booster I
    "gallente": (27932, 27930, 27904),  # Remote Hull Repairer I (structure)
    "minmatar": (11355, 11357, 11359),  # armor RR; amount split shield/armor in build_ship
}

RACE_BY_PREFIX = {
    "amarr": "amarr",
    "caldari": "caldari",
    "minmatar": "minmatar",
    "gallente": "gallente",
}


def resonance_to_resist_pct(resonance: float) -> float:
    """EVE resonance 1.0 = 0% resist; 0.5 = 50% resist. Store as 0.0–1.0."""
    return round(1.0 - float(resonance), 4)


def sensor_strength(raw: dict) -> float:
    return max(
        float(raw.get("scanRadarStrength") or 0),
        float(raw.get("scanLadarStrength") or 0),
        float(raw.get("scanMagnetometricStrength") or 0),
        float(raw.get("scanGravimetricStrength") or 0),
    )


def dmg_dict(em=0.0, th=0.0, ki=0.0, ex=0.0) -> dict:
    return {
        "emp": round(em, 2),
        "thermal": round(th, 2),
        "kinetic": round(ki, 2),
        "explosive": round(ex, 2),
    }


def resist_dict(raw: dict, layer: str) -> dict:
    prefix = {"shield": "shield", "armor": "armor"}[layer]
    return {
        "emp": resonance_to_resist_pct(raw.get(f"{prefix}EmDamageResonance", 1.0)),
        "thermal": resonance_to_resist_pct(raw.get(f"{prefix}ThermalDamageResonance", 1.0)),
        "kinetic": resonance_to_resist_pct(raw.get(f"{prefix}KineticDamageResonance", 1.0)),
        "explosive": resonance_to_resist_pct(raw.get(f"{prefix}ExplosiveDamageResonance", 1.0)),
    }


def meters_to_cells(meters: float) -> float:
    return round(float(meters) / METERS_PER_CELL, 3)


def load_csv_rows() -> list[dict]:
    text = CSV_PATH.read_text(encoding="utf-8")
    return list(csv.DictReader(text.splitlines()))


def load_preferred_json(latest_path: Path, fallback_path: Path) -> dict:
    if latest_path.exists():
        return json.loads(latest_path.read_text(encoding="utf-8"))
    return json.loads(fallback_path.read_text(encoding="utf-8"))


def load_optional_json(path: Path) -> dict:
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {}


def resolve_cost(ship_group: str, fallback_cost: int) -> int:
    return UNIFIED_COST_BY_GROUP.get(ship_group, fallback_cost)


def expand_ships(rows: list[dict]) -> list[dict]:
    """Flatten race columns into 40 ship defs."""
    out = []
    races = [
        ("amarr", "amarr"),
        ("caldari", "caldari"),
        ("minmatar", "minmatar"),
        ("gallente", "gallente"),
    ]
    for row in rows:
        for race, col in races:
            out.append(
                {
                    "id": int(row[f"{col}_id"]),
                    "type_id": int(row[f"{col}_type_id"]),
                    "name": row[f"{col}_zh"],
                    "name_en": row[f"{col}_en"],
                    "model_key": row[f"{col}_key"],
                    "weapon_fx": row[f"{col}_weapon_fx"],
                    "race": race,
                    "role": row["role"],
                    "cost": resolve_cost(row["ship_group"], int(row["cost"])),
                    "ship_group": row["ship_group"],
                    "is_logistic": row["is_logistic"] == "1",
                    "mid_battle_leave_allowed": row["mid_battle_leave"] == "1",
                    "anchor": int(row["anchor"]),
                }
            )
    return sorted(out, key=lambda s: s["id"])


def per_slot_weapon(mods: dict, charges: dict, weapon_fx: str, ship_group: str, weapon_tier: str = "") -> dict:
    if weapon_fx == "heal":
        return {
            "damage": dmg_dict(),
            "tracking": 0.0,
            "optimal": 0.0,
            "falloff": 0.0,
            "optimal_sig_radius": 40.0,
            "rate_of_fire_s": 1.0,
            "module_type_id": 0,
            "charge_type_id": 0,
            "explosion_radius": 0.0,
            "explosion_velocity": 0.0,
            "drf": 0.0,
        }
    size_key = weapon_kit_size_key(ship_group, weapon_tier)
    mod_id, charge_id = WEAPON_KIT[weapon_fx][size_key]
    mod = mods[str(mod_id)]
    charge = charges[str(charge_id)]
    mult = float(mod.get("damageMultiplier") or 1.0)
    # missiles: launcher has no multiplier; charge is full volley damage
    if weapon_fx == "missile":
        mult = 1.0
    em = mult * float(charge.get("emDamage") or 0)
    th = mult * float(charge.get("thermalDamage") or 0)
    ki = mult * float(charge.get("kineticDamage") or 0)
    ex = mult * float(charge.get("explosiveDamage") or 0)
    if weapon_fx == "missile":
        total = em + th + ki + ex
        if total > 0.0:
            each = total / 4.0
            em = each
            th = each
            ki = each
            ex = each
    rof_ms = float(mod.get("rateOfFire") or 1000.0)
    return {
        "damage": dmg_dict(em, th, ki, ex),
        "tracking": float(mod.get("trackingSpeed") or 0.0),
        "optimal": meters_to_cells(float(mod.get("maxRange") or 0.0)),
        "falloff": meters_to_cells(float(mod.get("falloff") or 0.0)),
        "optimal_sig_radius": float(mod.get("signatureResolution") or 40.0),
        "rate_of_fire_s": round(rof_ms / 1000.0, 3),
        "module_type_id": mod_id,
        "charge_type_id": charge_id,
        "explosion_radius": float(charge.get("explosionRadius") or 0.0),
        "explosion_velocity": float(charge.get("explosionVelocity") or 0.0),
        "drf": float(charge.get("aoeDamageReductionFactor") or 0.0),
    }


def per_slot_repair(mods: dict, race: str, ship_group: str, weapon_tier: str = "") -> dict:
    fri, cru, large = REPAIR_KIT[race]
    tier = ship_group_size_tier(ship_group, weapon_tier)
    if tier == "large":
        mid = large
    elif tier == "medium":
        mid = cru
    else:
        mid = fri
    mod = mods[str(mid)]
    amount = float(
        mod.get("structureDamageAmount")
        or mod.get("armorDamageAmount")
        or mod.get("shieldBonus")
        or 0.0
    )
    dur_ms = float(mod.get("duration") or mod.get("rateOfFire") or 3000.0)
    return {
        "amount": amount,
        "optimal": meters_to_cells(float(mod.get("maxRange") or 0.0)),
        "module_type_id": mid,
        "cycle_s": round(dur_ms / 1000.0, 3),
    }


def scale_dmg(d: dict, mul: float) -> dict:
    return {k: round(float(v) * mul, 2) for k, v in d.items()}


def build_ship(def_row: dict, raw: dict, mods: dict, charges: dict, drone_slots_map: dict, long_axis_map: dict | None = None) -> dict:
    long_axis_map = long_axis_map or {}
    hi = int(raw.get("hiSlots") or 0)
    med = int(raw.get("medSlots") or 0)
    low = int(raw.get("lowSlots") or 0)
    race = def_row["race"]
    group = def_row["ship_group"]
    fx = def_row["weapon_fx"]
    logistic = def_row["is_logistic"]
    weapon_tier = str(def_row.get("weapon_tier", ""))

    wpn = per_slot_weapon(mods, charges, "laser" if fx == "heal" else fx, group, weapon_tier)
    # heal fx ships still get a racial default gun profile for token damage if not logistic-only
    if fx == "heal":
        # racial default gun for token DPS while repairs dominate
        default_fx = {"amarr": "laser", "caldari": "rail", "minmatar": "cannon", "gallente": "rail"}[race]
        wpn = per_slot_weapon(mods, charges, default_fx, group, weapon_tier)
        fx_out = "heal"
    else:
        fx_out = fx

    slot_dmg = wpn["damage"]
    total_dmg_1 = {k: round(v * hi, 2) for k, v in slot_dmg.items()}

    rep_slot = per_slot_repair(mods, race, group, weapon_tier) if logistic else {"amount": 0.0, "optimal": 0.0, "module_type_id": 0, "cycle_s": 0.0}
    # logistics: repair uses hiSlots as repair hardpoints
    rep_amount_1 = float(rep_slot["amount"]) * hi if logistic else 0.0
    if logistic:
        # racial repair distribution for star rows
        if race == "amarr":
            rep1 = {"shield": 0.0, "armor": rep_amount_1, "structure": 0.0}
        elif race == "caldari":
            rep1 = {"shield": rep_amount_1, "armor": 0.0, "structure": 0.0}
        elif race == "gallente":
            rep1 = {"shield": 0.0, "armor": 0.0, "structure": rep_amount_1}
        else:  # minmatar split
            half = rep_amount_1 / 2.0
            sh = math.ceil(half)
            ar = math.floor(half)
            rep1 = {"shield": float(sh), "armor": float(ar), "structure": 0.0}
    else:
        rep1 = {"shield": 0.0, "armor": 0.0, "structure": 0.0}

    sh_hp = float(raw.get("shieldCapacity") or 0)
    ar_hp = float(raw.get("armorHP") or 0)
    st_hp = float(raw.get("hp") or 0)
    sh_res = resist_dict(raw, "shield")
    ar_res = resist_dict(raw, "armor")
    # structure resist: copy armor as baseline (EVE hull resists are separate; keep simple)
    st_res = dict(ar_res)

    fixed_range = turret_attack_range_cells(fx_out, group, weapon_tier)
    if fixed_range is not None:
        attack_range = fixed_range
    else:
        attack_range = max(1, int(round(wpn["optimal"])))

    stars = []
    for mul in (1, 2, 3):
        star = {
            "attack_range": attack_range,
            "damage": scale_dmg(total_dmg_1, mul),
            "repair": {k: round(v * mul, 2) for k, v in rep1.items()},
            "tracking": wpn["tracking"],
            "optimal": wpn["optimal"] if not logistic else (rep_slot["optimal"] or wpn["optimal"]),
            "falloff": wpn["falloff"],
            "optimal_sig_radius": wpn["optimal_sig_radius"] or 40.0,
            "shield_hp": round(sh_hp * mul, 2),
            "armor_hp": round(ar_hp * mul, 2),
            "structure_hp": round(st_hp * mul, 2),
            "shield_resist": sh_res,
            "armor_resist": ar_res,
            "structure_resist": st_res,
            "is_logistic": logistic,
        }
        if fx_out == "missile" or def_row["weapon_fx"] == "missile":
            star["explosion_radius"] = wpn["explosion_radius"]
            star["explosion_velocity"] = wpn["explosion_velocity"]
            star["drf"] = wpn["drf"]
        stars.append(star)

    role = def_row["role"]
    fetter_ids = [race, group, role]
    # exploration role keeps exploration tag
    if role == "exploration":
        pass

    drone_info = drone_slots_map.get(str(def_row["id"]), {})
    long_info = long_axis_map.get(str(def_row["id"]), {})
    drone_bw = drone_info.get("droneBandwidth")
    if drone_bw is None:
        drone_bw = drone_info.get("droneCapacity", 0.0)
    drone_slots = int(drone_info.get("drone_bay_slots", drone_info.get("droneSlotsLeft", 0)) or 0)
    long_axis = float(long_info.get("model_long_axis", drone_info.get("model_long_axis", 0)) or 0)
    attack_cycle_s = float(rep_slot.get("cycle_s", 0.0) if logistic else wpn.get("rate_of_fire_s", 0.0))
    doc = {
        "id": def_row["id"],
        "name": def_row["name"],
        "name_en": def_row["name_en"],
        "type_id": def_row["type_id"],
        "model_key": def_row["model_key"],
        "cost": def_row["cost"],
        "ship_groups": [group],
        "ship_group": group,
        "fetter_ids": fetter_ids,
        "tags": fetter_ids,
        "is_logistic": logistic,
        "weapon_fx": fx_out,
        "race": race,
        "signature_radius": float(raw.get("signatureRadius") or 0),
        "sensor_strength": sensor_strength(raw),
        "scan_resolution": float(raw.get("scanResolution") or 0),
        "speed": float(raw.get("maxVelocity") or 0),
        "mass": float(raw.get("mass") or 0),
        "agility": float(raw.get("agility") or 0),
        "capacitor_capacity": float(raw.get("capacitorCapacity") or 0),
        "capacitor_recharge_s": round(float(raw.get("rechargeRate") or 0) / 1000.0, 3),
        "mid_battle_leave_allowed": def_row["mid_battle_leave_allowed"],
        "function_slots": {"slots": []},
        "hi_slots": hi,
        "med_slots": med,
        "low_slots": low,
        "source_module_type_id": wpn["module_type_id"],
        "source_charge_type_id": wpn["charge_type_id"],
        "source_repair_module_type_id": rep_slot["module_type_id"],
        "drone_bandwidth": float(drone_bw or 0.0),
        "drone_bay_slots": drone_slots,
        "drone_count_cap": drone_slots,
        "echoes_item_id": int(drone_info.get("echoes_item_id", 0) or 0),
        "attack_cycle_s": attack_cycle_s,
        "stars": stars,
    }
    if weapon_tier:
        doc["weapon_tier"] = weapon_tier
    if bool(def_row.get("is_attack_battlecruiser", False)):
        doc["is_attack_battlecruiser"] = True
    if long_axis > 0:
        doc["model_long_axis"] = round(long_axis, 3)
    return doc


def main():
    ships_raw = load_preferred_json(SHIPS_RAW_LATEST, SHIPS_RAW)
    mods = load_preferred_json(MODS_RAW_LATEST, MODS_RAW)
    charges = load_preferred_json(CHARGES_RAW_LATEST, CHARGES_RAW)
    drone_slots_map = load_optional_json(DRONE_SLOTS_JSON)
    long_axis_map = load_optional_json(LONG_AXIS_JSON).get("ships", {})
    defs = expand_ships(load_csv_rows())
    assert len(defs) == 40, len(defs)

    out_dir = DEV_ROOT / "ships"
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for d in defs:
        raw = ships_raw[str(d["type_id"])]
        doc = build_ship(d, raw, mods, charges, drone_slots_map, long_axis_map)
        path = out_dir / f"{d['id']}.json"
        path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        written.append(d["id"])

    # summary for Amarr before/after spot-check
    a1 = json.loads((out_dir / "1.json").read_text(encoding="utf-8"))
    print(f"wrote {len(written)} ships -> {out_dir}")
    print(
        "sample Punisher 1★:",
        a1["name"],
        "shield",
        a1["stars"][0]["shield_hp"],
        "armor",
        a1["stars"][0]["armor_hp"],
        "struct",
        a1["stars"][0]["structure_hp"],
        "dmg",
        a1["stars"][0]["damage"],
        "cap",
        a1["capacitor_capacity"],
        "recharge_s",
        a1["capacitor_recharge_s"],
    )
    print(
        "raw source:",
        "ships", SHIPS_RAW_LATEST.name if SHIPS_RAW_LATEST.exists() else SHIPS_RAW.name,
        "mods", MODS_RAW_LATEST.name if MODS_RAW_LATEST.exists() else MODS_RAW.name,
        "charges", CHARGES_RAW_LATEST.name if CHARGES_RAW_LATEST.exists() else CHARGES_RAW.name,
    )


if __name__ == "__main__":
    main()
