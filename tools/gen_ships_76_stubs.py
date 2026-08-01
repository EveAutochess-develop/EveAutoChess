# -*- coding: utf-8 -*-
"""Generate §7.6 stub ships (ids 41+) missing from current 40 roster."""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from gen_content_data import (
    load_modules_json,
    per_slot_weapon,
    turret_attack_range_cells,
)

OUT = os.path.join(os.path.dirname(__file__), "..", "godot_project", "data", "ships")

# id, ZH, EN, race, group, cost, model_key, weapon_fx, type_id, module_id, weapon_tier, attack_bc
ROSTER = [
    (41, "预言级", "Prophecy", "amarr", "battlecruiser", 8, "am_yuyan", "laser", 16233, 462, "large", True),
    (42, "先知级", "Absolution", "amarr", "battlecruiser", 7, "am_xianzhi", "laser", 22448, 456, "medium", False),
    (43, "先驱者级", "Harbinger", "amarr", "battlecruiser", 7, "am_xianquzhe", "laser", 24696, 456, "medium", False),
    (44, "末日沙场级", "Armageddon", "amarr", "battleship", 13, "am_morishachang", "laser", 643, 462, "large", False),
    (45, "灾难级", "Apocalypse", "amarr", "battleship", 13, "am_zainan", "laser", 642, 462, "large", False),
    (46, "地狱天使级", "Abaddon", "amarr", "battleship", 13, "am_diyutienshi", "laser", 24692, 462, "large", False),
    (47, "猛鲑级", "Ferox", "caldari", "battlecruiser", 7, "jdl_menggui", "rail", 16227, 570, "medium", False),
    (48, "幼龙级", "Drake", "caldari", "battlecruiser", 7, "jdl_youlong", "missile", 24698, 501, "medium", False),
    (50, "毒蝎级", "Scorpion", "caldari", "battleship", 13, "jdl_duxie", "missile", 640, 501, "large", False),
    (51, "乌鸦级", "Raven", "caldari", "battleship", 13, "jdl_wuya", "missile", 638, 501, "large", False),
    (52, "鹏鲲级", "Rokh", "caldari", "battleship", 13, "jdl_pengkun", "rail", 24688, 574, "large", False),
    (53, "特里斯坦级", "Tristan", "gallente", "frigate", 2, "glt_telisitan", "rail", 593, 561, "small", False),
    (54, "布鲁提克斯级", "Brutix", "gallente", "battlecruiser", 7, "glt_bulutikesi", "rail", 16229, 570, "medium", False),
    (55, "弥洱米顿级", "Myrmidon", "gallente", "battlecruiser", 7, "glt_miermidun", "rail", 24700, 570, "medium", False),
    (56, "多米尼克斯级", "Dominix", "gallente", "battleship", 13, "glt_duominikesi", "rail", 645, 574, "large", False),
    (57, "万王宝座级", "Megathron", "gallente", "battleship", 13, "glt_wanwangbaozuo", "rail", 641, 574, "large", False),
    (58, "亥伯龙神级", "Hyperion", "gallente", "battleship", 13, "glt_haibolongshen", "rail", 24690, 574, "large", False),
    (59, "暴风级", "Tempest", "minmatar", "battleship", 13, "mmte_baofeng", "cannon", 639, 498, "large", False),
    (60, "飓风级", "Hurricane", "minmatar", "battlecruiser", 7, "mmte_jufeng", "cannon", 24702, 491, "medium", False),
    (61, "台风级", "Typhoon", "minmatar", "battleship", 13, "mmte_taifeng", "missile", 644, 501, "large", False),
    (62, "狂暴级", "Maelstrom", "minmatar", "battleship", 13, "mmte_kuangbao", "cannon", 24694, 498, "large", False),
    (63, "死亡漩涡级", "Hel", "minmatar", "battleship", 13, "mmte_siwangxuanwo", "missile", 22852, 501, "large", False),
    # 大炮战巡（大型武器）→ cost 8
    (64, "塔洛斯级", "Talos", "gallente", "battlecruiser", 8, "glt_taluosi", "rail", 4308, 573, "large", True),
    (65, "纳迦级", "Naga", "caldari", "battlecruiser", 8, "jdl_najia", "rail", 4306, 574, "large", True),
    (66, "龙卷风级", "Tornado", "minmatar", "battlecruiser", 8, "mmte_longjuanfeng", "cannon", 4310, 498, "large", True),
]

# SDE attr 51 rateOfFire (ms) — authoritative cycle before runtime cap
MODULE_CYCLE_S = {
    453: 3.5, 456: 4.05, 462: 7.875,
    561: 2.6, 570: 5.825, 573: 4.5, 574: 8.129,
    485: 3.375, 491: 5.456, 498: 40.163,
    499: 16.0, 501: 15.0,
    11355: 3.0, 11357: 6.0, 11359: 6.0,
    3586: 4.0, 3596: 8.0, 3606: 8.0,
}

RACE_FETTER = {
    "amarr": ("amarr", "laser", "defense"),
    "caldari": ("caldari", "missile", "shield"),
    "gallente": ("gallente", "hybrid", "armor"),
    "minmatar": ("minmatar", "projectile", "speed"),
}

DEF_BY_GROUP = {
    "frigate": (400, 600, 300, 8.0, 15.0),
    "battlecruiser": (1200, 1800, 900, 6.0, 50.0),
    "battleship": (2000, 2800, 1400, 5.0, 75.0),
}


def star_block(group: str, mul: float, wfx: str, weapon_tier: str, wpn: dict) -> dict:
    sh, ar, st, _rng, bw = DEF_BY_GROUP[group]
    rng = turret_attack_range_cells(wfx, group, weapon_tier)
    if rng is None:
        rng = 3 if group == "frigate" else (6 if group == "battlecruiser" else 10)
    ## Attack fields omitted — runtime ShipWeaponDerive from slots × kit.
    return {
        "attack_range": rng,
        "shield_hp": sh * mul,
        "armor_hp": ar * mul,
        "structure_hp": st * mul,
        "shield_resist": {"emp": 0.2, "thermal": 0.2, "kinetic": 0.2, "explosive": 0.2},
        "armor_resist": {"emp": 0.2, "thermal": 0.2, "kinetic": 0.2, "explosive": 0.2},
        "structure_resist": {"emp": 0.2, "thermal": 0.2, "kinetic": 0.2, "explosive": 0.2},
    }


def main() -> None:
    mods = load_modules_json()
    for row in ROSTER:
        sid, name, en, race, group, cost, key, wfx, tid, mod_id, weapon_tier, attack_bc = row
        race_f, weap_f, _def_f = RACE_FETTER[race]
        fetters = [race_f, group if group != "battlecruiser" else "battlecruiser", weap_f]
        wpn = per_slot_weapon(mods, wfx, group, weapon_tier)
        stars = [star_block(group, mul, wfx, weapon_tier, wpn) for mul in (1.0, 2.0, 3.0)]
        cycle_s = MODULE_CYCLE_S.get(mod_id, 3.5 if group == "battleship" else 2.8)
        d = {
            "id": sid,
            "name": name,
            "name_en": en,
            "type_id": tid,
            "model_key": key,
            "cost": cost,
            "ship_groups": [group],
            "ship_group": group,
            "fetter_ids": fetters,
            "tags": [race, group, weap_f],
            "is_logistic": False,
            "weapon_fx": wfx,
            "weapon_tier": weapon_tier,
            "race": race,
            "signature_radius": 400.0 if group == "battleship" else (150.0 if group == "battlecruiser" else 40.0),
            "sensor_strength": 16.0,
            "scan_resolution": 200.0 if group != "frigate" else 500.0,
            "speed": 150.0 if group == "battleship" else (200.0 if group == "battlecruiser" else 320.0),
            "mass": 10000000.0,
            "agility": 0.5,
            "capacitor_capacity": 3000.0 if group != "frigate" else 400.0,
            "capacitor_recharge_s": 500.0,
            "mid_battle_leave_allowed": False,
            "is_unmanned": False,
            "unmanned_kind": "",
            "attack_cycle_s": cycle_s,
            "drone_bandwidth": DEF_BY_GROUP[group][4],
            "function_slots": {"slots": []},
            "hi_slots": 7,
            "med_slots": 4,
            "low_slots": 6,
            "source_module_type_id": mod_id,
            "source_repair_module_type_id": 0,
            "stars": stars,
            "visual": {},
            "_stub_note": "§7.6 EVEMU-ish placeholder; model may be empty until bundle drop-in",
        }
        if attack_bc:
            d["is_attack_battlecruiser"] = True
        path = os.path.join(OUT, f"{sid}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print("wrote", path)


if __name__ == "__main__":
    main()
