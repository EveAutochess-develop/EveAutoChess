# -*- coding: utf-8 -*-
"""Generate capital/cyno/FAX/fighter content + copy confirm-pack PNGs to English names."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev\godot_project")
CONFIRM = Path(r"H:\game_dev\eveautochess-design\docs\_review\capital_cyno_assets_confirm")
SHIPS = ROOT / "data" / "ships"
UNMANNED = ROOT / "data" / "unmanned_units"
UI_SHIPS = ROOT / "assets" / "ui" / "ship_portraits_capital"
UI_EQUIP = ROOT / "assets" / "ui" / "item_icons_capital"
UI_FIGHTERS = ROOT / "assets" / "ui" / "fighter_icons"
UI_DRONES = ROOT / "assets" / "ui" / "heavy_repair_drone_icons"


def star_tank(shield: float, armor: float, structure: float, damage: dict, repair: dict | None = None, **extra) -> dict:
    repair = repair or {"shield": 0, "armor": 0, "structure": 0}
    resist = {"emp": 0.2, "thermal": 0.2, "kinetic": 0.2, "explosive": 0.2}
    base = {
        "attack_range": int(extra.pop("attack_range", 999)),
        "damage": damage,
        "repair": repair,
        "tracking": float(extra.pop("tracking", 0.008)),
        "optimal": float(extra.pop("optimal", 50000.0)),
        "falloff": float(extra.pop("falloff", 10000.0)),
        "optimal_sig_radius": float(extra.pop("optimal_sig_radius", 400.0)),
        "shield_hp": float(shield),
        "armor_hp": float(armor),
        "structure_hp": float(structure),
        "shield_resist": dict(resist),
        "armor_resist": dict(resist),
        "structure_resist": dict(resist),
    }
    base.update(extra)
    return base


def scale_stars(s1: dict) -> list[dict]:
    out = []
    for mul in (1, 2, 3):
        s = json.loads(json.dumps(s1))
        for k in ("shield_hp", "armor_hp", "structure_hp"):
            s[k] = round(s[k] * mul, 1)
        for dk in s["damage"]:
            s["damage"][dk] = round(s["damage"][dk] * mul, 2)
        for rk in s["repair"]:
            s["repair"][rk] = round(s["repair"][rk] * mul, 2)
        out.append(s)
    return out


def write_ship(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def copy_png(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def main() -> None:
    # --- portraits / icons (English names) ---
    portrait_map = {
        "01_主宰级隐匿型.png": "pilgrim.png",
        "02_黑鸟级隐匿型.png": "falcon.png",
        "03_星空级隐匿型.png": "arazu.png",
        "04_挑战级隐匿型.png": "rapier.png",
        "15_神示级.png": "revelation.png",
        "14_莫洛级.png": "moros.png",
        "13_凤凰级.png": "phoenix.png",
        "16_娜迦法级.png": "naglfar.png",
        "执政官.png": "archon.png",
        "奇美拉.png": "chimera.png",
        "绝念.png": "thanatos.png",
        "12_尼铎格尔级.png": "nidhoggur.png",
        "使徒.png": "apostle.png",
        "龙鸟.png": "minokawa.png",
        "立夫.png": "lif.png",
        "尼纳苏.png": "ninazu.png",
    }
    for zh, en in portrait_map.items():
        copy_png(CONFIRM / "ships" / zh, UI_SHIPS / en)

    equip_map = {
        "00_诱导.png": "cyno.png",
        "01_旗舰鱼雷.png": "capital_torpedo.png",
        "02_旗舰加农.png": "capital_autocannon.png",
        "03_旗舰激光.png": "capital_pulse_laser.png",
        "04_旗舰磁轨.png": "capital_blaster.png",
    }
    for zh, en in equip_map.items():
        copy_png(CONFIRM / "equip" / zh, UI_EQUIP / en)

    fighter_map = {
        "01_骑士_Equite.png": "equite.png",
        "02_蚂蚱_Locust.png": "locust.png",
        "03_萨梯_Satyr.png": "satyr.png",
        "04_拉格墨_Gram.png": "gram.png",
    }
    for zh, en in fighter_map.items():
        copy_png(CONFIRM / "fighters" / zh, UI_FIGHTERS / en)

    drone_map = {
        "01_重型a后勤无人机.png": "heavy_repair_amarr.png",
        "02_重型c后勤无人机.png": "heavy_repair_caldari.png",
        "03_重型g后勤无人机.png": "heavy_repair_gallente.png",
        "04_重型m后勤无人机.png": "heavy_repair_minmatar.png",
    }
    for zh, en in drone_map.items():
        copy_png(CONFIRM / "heavy_repair_drones" / zh, UI_DRONES / en)

    # item icon by type id for UiAssets.item_icon
    item_icons = ROOT / "assets" / "ui" / "sprites" / "item_icons"
    item_icons.mkdir(parents=True, exist_ok=True)
    id_copy = {
        "11114010000.png": UI_EQUIP / "cyno.png",
        "11023000000.png": UI_EQUIP / "capital_torpedo.png",
        "11004810000.png": UI_EQUIP / "capital_autocannon.png",
        "11002810000.png": UI_EQUIP / "capital_pulse_laser.png",
        "11000320000.png": UI_EQUIP / "capital_blaster.png",
        "15100000000.png": UI_FIGHTERS / "equite.png",
        "15100000010.png": UI_FIGHTERS / "locust.png",
        "15100000020.png": UI_FIGHTERS / "satyr.png",
        "15100000030.png": UI_FIGHTERS / "gram.png",
        "14000200000.png": UI_DRONES / "heavy_repair_amarr.png",
        "14000200005.png": UI_DRONES / "heavy_repair_caldari.png",
        "14000200010.png": UI_DRONES / "heavy_repair_gallente.png",
        "14000200015.png": UI_DRONES / "heavy_repair_minmatar.png",
    }
    for name, src in id_copy.items():
        shutil.copy2(src, item_icons / name)

    # --- hulls ---
    cyno_slot = {
        "slots": [
            {
                "id": "covert_cyno",
                "name": "诱导",
                "name_en": "Covert Cynosural Field",
                "icon_item_id": 11114010000,
                "duration_s": 90.0,
                "kind": "cyno",
            }
        ]
    }

    recon = [
        (101, "主宰级隐匿型", "Pilgrim", 11965, "amarr", 850, 1800, 1050, 198, 150, 4, 5, 5),
        (102, "黑鸟级隐匿型", "Falcon", 11957, "caldari", 1750, 940, 945, 192, 165, 4, 7, 3),
        (103, "星空级隐匿型", "Arazu", 11969, "gallente", 1180, 1430, 1080, 207, 155, 4, 6, 4),
        (104, "挑战级隐匿型", "Rapier", 11963, "minmatar", 1480, 1075, 850, 230, 125, 4, 6, 4),
    ]
    for sid, zh, en, tid, race, sh, ar, st, spd, sig, hi, med, low in recon:
        s1 = star_tank(sh, ar, st, {"emp": 0, "thermal": 0, "kinetic": 0, "explosive": 0}, tracking=0.01, optimal_sig_radius=sig)
        write_ship(
            SHIPS / f"{sid}.json",
            {
                "id": sid,
                "name": zh,
                "name_en": en,
                "type_id": tid,
                "model_key": en.lower(),
                "portrait": f"res://assets/ui/ship_portraits_capital/{en.lower()}.png",
                "cost": 4,
                "shop_min_level": 15,
                "ship_groups": ["cruiser"],
                "ship_group": "cruiser",
                "capital_role": "covert_cyno",
                "fetter_ids": [race, "cruiser", "ewar"],
                "tags": [race, "cruiser", "ewar", "cyno"],
                "is_logistic": False,
                "weapon_fx": "laser",
                "weapon_tier": "medium",
                "race": race,
                "signature_radius": float(sig),
                "speed": float(spd),
                "attack_cycle_s": 90.0,
                "drone_bandwidth": 0.0,
                "function_slots": cyno_slot,
                "hi_slots": hi,
                "med_slots": med,
                "low_slots": low,
                "source_module_type_id": 11114010000,
                "source_repair_module_type_id": 0,
                "requires_cyno_entry": False,
                "deploy_enemy_half_only": True,
                "allow_enemy_cell_overlap": True,
                "immobile_in_combat": True,
                "stars": scale_stars(s1),
            },
        )

    dreads = [
        # id, zh, en, tid, race, sh, ar, st, fx, dmg, cycle, tracking, module_icon, extra star keys
        (
            111,
            "神示级",
            "Revelation",
            19720,
            "amarr",
            78100,
            113000,
            113000,
            "laser",
            {"emp": 2100.0, "thermal": 1500.0, "kinetic": 0, "explosive": 0},
            12.0,
            0.004,
            11002810000,
            {},
        ),
        (
            112,
            "摩洛级",
            "Moros",
            19724,
            "gallente",
            86800,
            104200,
            121500,
            "rail",
            {"emp": 0, "thermal": 1574.0, "kinetic": 2204.0, "explosive": 0},
            10.0,
            0.004,
            11000320000,
            {},
        ),
        (
            113,
            "凤凰级",
            "Phoenix",
            19726,
            "caldari",
            104200,
            86800,
            104200,
            "missile",
            {"emp": 0, "thermal": 10263.0, "kinetic": 0, "explosive": 0},
            25.65,
            0.0,
            11023000000,
            {"explosion_radius": 10000.0, "explosion_velocity": 42.0, "drf": 4.5},
        ),
        (
            114,
            "纳迦法级",
            "Naglfar",
            19722,
            "minmatar",
            95500,
            95500,
            95500,
            "cannon",
            {"emp": 599.0, "thermal": 0, "kinetic": 67.0, "explosive": 133.0},
            4.0,
            0.004,
            11004810000,
            {},
        ),
    ]
    for sid, zh, en, tid, race, sh, ar, st, fx, dmg, cycle, track, mod, extra in dreads:
        s1 = star_tank(sh, ar, st, dmg, tracking=track, optimal=1e9, falloff=1e9, optimal_sig_radius=2000.0, **extra)
        write_ship(
            SHIPS / f"{sid}.json",
            {
                "id": sid,
                "name": zh,
                "name_en": en,
                "type_id": tid,
                "model_key": en.lower(),
                "portrait": f"res://assets/ui/ship_portraits_capital/{en.lower()}.png",
                "cost": 24,
                "ship_groups": ["dreadnought"],
                "ship_group": "dreadnought",
                "capital_role": "dreadnought",
                "fetter_ids": [race, "dreadnought", "firepower"],
                "tags": [race, "dreadnought"],
                "is_logistic": False,
                "weapon_fx": fx,
                "weapon_tier": "capital",
                "race": race,
                "signature_radius": 2000.0,
                "speed": 75.0,
                "attack_cycle_s": cycle,
                "drone_bandwidth": 0.0,
                "function_slots": {"slots": []},
                "hi_slots": 5,
                "med_slots": 4,
                "low_slots": 7,
                "source_module_type_id": mod,
                "source_repair_module_type_id": 0,
                "requires_cyno_entry": True,
                "unlimited_weapon_range": True,
                "stars": scale_stars(s1),
            },
        )

    carriers = [
        (121, "执政官级", "Archon", 23757, "amarr", 53000, 72000, 76300, "equite", 1401, "am_zhizhengguan"),
        (122, "奇美拉级", "Chimera", 23915, "caldari", 68000, 61000, 69400, "locust", 1402, "jdl_qimeila"),
        (123, "绝念级", "Thanatos", 23911, "gallente", 55500, 69500, 83500, "satyr", 1403, "glt_juenian"),
        (124, "尼铎格尔级", "Nidhoggur", 24483, "minmatar", 67000, 66000, 62500, "gram", 1404, "mmte_niyigeer"),
    ]
    for sid, zh, en, tid, race, sh, ar, st, fighter_key, fighter_id, mkey in carriers:
        s1 = star_tank(sh, ar, st, {"emp": 0, "thermal": 0, "kinetic": 0, "explosive": 0})
        write_ship(
            SHIPS / f"{sid}.json",
            {
                "id": sid,
                "name": zh,
                "name_en": en,
                "type_id": tid,
                "model_key": mkey,
                "portrait": f"res://assets/ui/ship_portraits_capital/{en.lower()}.png",
                "cost": 22,
                "ship_groups": ["carrier"],
                "ship_group": "carrier",
                "capital_role": "carrier",
                "fetter_ids": [race, "carrier", "firepower"],
                "tags": [race, "carrier"],
                "is_logistic": False,
                "weapon_fx": "missile",
                "weapon_tier": "capital",
                "race": race,
                "signature_radius": 3000.0,
                "speed": 80.0,
                "attack_cycle_s": 3.5,
                "drone_bandwidth": 0.0,
                "function_slots": {"slots": []},
                "hi_slots": 5,
                "med_slots": 4,
                "low_slots": 6,
                "source_module_type_id": 0,
                "source_repair_module_type_id": 0,
                "requires_cyno_entry": True,
                "fighter_squadrons": 3,
                "fighter_tubes_per_squadron": 3,
                "fighter_unit_id": fighter_id,
                "fighter_key": fighter_key,
                "stars": scale_stars(s1),
            },
        )

    fax = [
        (131, "使徒级", "Apostle", 37604, "amarr", 62000, 114500, 124000, 1411, "heavy_repair_amarr"),
        (132, "龙鸟级", "Minokawa", 37605, "caldari", 105000, 80000, 110000, 1412, "heavy_repair_caldari"),
        (133, "立夫级", "Lif", 37606, "minmatar", 100000, 90000, 100000, 1414, "heavy_repair_minmatar"),
        (134, "尼纳苏级", "Ninazu", 37607, "gallente", 73000, 105000, 135000, 1413, "heavy_repair_gallente"),
    ]
    for sid, zh, en, tid, race, sh, ar, st, drone_id, drone_key in fax:
        s1 = star_tank(sh, ar, st, {"emp": 0, "thermal": 0, "kinetic": 0, "explosive": 0})
        write_ship(
            SHIPS / f"{sid}.json",
            {
                "id": sid,
                "name": zh,
                "name_en": en,
                "type_id": tid,
                "model_key": en.lower(),
                "portrait": f"res://assets/ui/ship_portraits_capital/{en.lower()}.png",
                "cost": 22,
                "ship_groups": ["force_auxiliary"],
                "ship_group": "force_auxiliary",
                "capital_role": "force_auxiliary",
                "fetter_ids": [race, "force_auxiliary", "logistic"],
                "tags": [race, "force_auxiliary", "logistic"],
                "is_logistic": False,
                "weapon_fx": "heal",
                "weapon_tier": "capital",
                "race": race,
                "signature_radius": 10500.0,
                "speed": 80.0,
                "attack_cycle_s": 5.0,
                "drone_bandwidth": 0.0,
                "function_slots": {"slots": []},
                "hi_slots": 5,
                "med_slots": 5,
                "low_slots": 5,
                "source_module_type_id": 0,
                "source_repair_module_type_id": 0,
                "requires_cyno_entry": True,
                "hull_repair_zero": True,
                "heavy_repair_drone_count": 4,
                "heavy_repair_drone_id": drone_id,
                "heavy_repair_drone_key": drone_key,
                "stars": scale_stars(s1),
            },
        )

    # fighters
    fighters = [
        (1401, "骑士", "Equite I", 40358, "amarr", {"emp": 152.0, "thermal": 0, "kinetic": 0, "explosive": 0}),
        (1402, "蚂蚱", "Locust I", 40359, "caldari", {"emp": 0, "thermal": 0, "kinetic": 160.0, "explosive": 0}),
        (1403, "萨梯", "Satyr I", 40360, "gallente", {"emp": 0, "thermal": 168.0, "kinetic": 0, "explosive": 0}),
        (1404, "拉格墨", "Gram I", 40361, "minmatar", {"emp": 0, "thermal": 0, "kinetic": 0, "explosive": 144.0}),
    ]
    UNMANNED.mkdir(parents=True, exist_ok=True)
    for sid, zh, en, tid, race, dmg in fighters:
        key = en.split()[0].lower()
        # EVE light fighters = missile ability; per-tube DPH = ability×12/3.
        # optimal cells = board orbit (≤2 keeps missile flight delay short).
        s1 = star_tank(
            850,
            425,
            425,
            dmg,
            tracking=0.0,
            optimal=2.0,
            falloff=0.0,
            optimal_sig_radius=40.0,
            explosion_radius=40.0,
            explosion_velocity=300.0,
            drf=1.0,
            drs=1.0,
            attack_range=999,
        )
        # per-tube HP 1700 total across layers roughly
        s1["shield_hp"] = 700
        s1["armor_hp"] = 500
        s1["structure_hp"] = 500
        write_ship(
            UNMANNED / f"{sid}.json",
            {
                "id": sid,
                "name": zh,
                "name_en": en,
                "type_id": tid,
                "model_key": key,
                "portrait": f"res://assets/ui/fighter_icons/{key}.png",
                "cost": 0,
                "ship_groups": ["fighter"],
                "ship_group": "fighter",
                "fetter_ids": [],
                "tags": [race, "fighter"],
                "is_logistic": False,
                "weapon_fx": "missile",
                "weapon_tier": "light",
                "race": race,
                "signature_radius": 88.0,
                "scan_resolution": 850.0,
                "speed": {"amarr": 1000.0, "caldari": 905.0, "gallente": 857.0, "minmatar": 1048.0}.get(race, 1000.0),
                "attack_cycle_s": 3.5,
                "is_unmanned": True,
                "unmanned_kind": "fighter",
                "tube_hp": 1700,
                "function_slots": {"slots": []},
                "hi_slots": 0,
                "med_slots": 0,
                "low_slots": 0,
                "source_module_type_id": 0,
                "stars": scale_stars(s1),
            },
        )

    # heavy repair drones: 60/5s; amarr/gallente armor, caldari/minmatar shield-ish — plan says armor/shield by race
    repair_drones = [
        (1411, "重型a后勤无人机", "Heavy Repair Amarr", "amarr", {"armor": 60}, True),
        (1412, "重型c后勤无人机", "Heavy Repair Caldari", "caldari", {"shield": 60}, False),
        (1413, "重型g后勤无人机", "Heavy Repair Gallente", "gallente", {"armor": 60}, True),
        (1414, "重型m后勤无人机", "Heavy Repair Minmatar", "minmatar", {"shield": 60}, False),
    ]
    for sid, zh, en, race, rep, armor_bot in repair_drones:
        key = f"heavy_repair_{race}"
        repair = {"shield": float(rep.get("shield", 0)), "armor": float(rep.get("armor", 0)), "structure": 0}
        s1 = star_tank(200, 200, 200, {"emp": 0, "thermal": 0, "kinetic": 0, "explosive": 0}, repair=repair, tracking=0.01, optimal=10000, falloff=2000)
        write_ship(
            UNMANNED / f"{sid}.json",
            {
                "id": sid,
                "name": zh,
                "name_en": en,
                "type_id": 23523 if armor_bot else 22765,
                "model_key": key,
                "portrait": f"res://assets/ui/heavy_repair_drone_icons/{key}.png",
                "cost": 0,
                "ship_groups": ["repair_drone"],
                "ship_group": "repair_drone",
                "fetter_ids": [],
                "tags": [race, "repair_drone"],
                "is_logistic": True,
                "weapon_fx": "heal",
                "weapon_tier": "medium",
                "race": race,
                "signature_radius": 50.0,
                "speed": 300.0,
                "attack_cycle_s": 5.0,
                "is_unmanned": True,
                "unmanned_kind": "heavy_repair_drone",
                "function_slots": {"slots": []},
                "hi_slots": 0,
                "med_slots": 0,
                "low_slots": 0,
                "source_module_type_id": 0,
                "source_repair_module_type_id": 23523 if armor_bot else 22765,
                "stars": scale_stars(s1),
            },
        )

    # mapping note
    mapping = {
        "portraits": portrait_map,
        "equip": equip_map,
        "fighters": fighter_map,
        "heavy_repair_drones": drone_map,
        "ship_ids": {
            "pilgrim": 101,
            "falcon": 102,
            "arazu": 103,
            "rapier": 104,
            "revelation": 111,
            "moros": 112,
            "phoenix": 113,
            "naglfar": 114,
            "archon": 121,
            "chimera": 122,
            "thanatos": 123,
            "nidhoggur": 124,
            "apostle": 131,
            "minokawa": 132,
            "lif": 133,
            "ninazu": 134,
        },
    }
    (CONFIRM / "ENGLISH_ASSET_MAP.json").write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("ships/unmanned/assets written")


if __name__ == "__main__":
    main()
