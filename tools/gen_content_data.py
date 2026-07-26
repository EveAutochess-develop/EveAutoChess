# -*- coding: utf-8 -*-
"""Generate Godot data/*.json from design appendix numbers."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev\godot_project\data")

BALANCE = {
    "match_flow": {
        "prepare_duration_s": 16,
        "battle_duration_s": 60,
        "citadel_damage_constant": 18,
        "player_max_hp": 1000,
        "max_round_phase_value": 5,
        "death_return_delay_s": 3,
    },
    "economy": {
        "base_gold": 5,
        "base_gold_income": 5,
        "interest_divisor": 10,
        "interest_capped": False,
        "refresh_cost": 2,
        "buy_exp_gold_cost": 4,
        "buy_exp_amount": 4,
        "base_exp_income": 4,
        "initial_level_exp_demand": 4,
        "level_exp_demand_increment": 8,
        "shop_slot_count": 5,
        "sell_price_equals_cost": True,
    },
    "board": {
        "field_width": 7,
        "field_height": 4,
        "hangar_width": 9,
        "hangar_height": 1,
        "hex_offset_x": -3.0,
        "hex_row_nudge": 1.5,
        "hex_offset_z": -2.5,
        "max_deployment": 999,
        "ship_count_buff": 0,
    },
    "combat": {
        "weapon_range_scale": 3.0,
        "approach_factor": 0.9,
        "min_damage_pct": 0.25,
        "shield_overflow_pierces_armor": False,
        "logistic_heal_multiplier": 2.0,
        "attack_duration_s": 1.0,
        "logistic_attack_duration_s": 2.0,
        "retarget_interval_s": 0.5,
        "damage_bonus_effect_type": "Damage",
    },
    "ai": {
        "deploy_try_limit": 28,
        "cruiser_block_battle_stages": 3,
        "cruiser_ship_group_tag": "cruiser",
        "random_deploy": True,
        "uses_shop_economy": False,
    },
    "visual": {
        "ship_visual_scale": 0.85,
        "camera_distance": 28.0,
        "camera_height": 22.0,
        "camera_angle_deg": -55.0,
        "player_yaw_deg": 200.0,
        "ai_yaw_deg": 20.0,
    },
}

# id, name, cost, ship_groups, fetter_ids, logistic, stars[range, dmg_e, shield, armor, sres_e, ares_e]
SHIPS = [
    (1, "惩罚者级", 3, ["frigate"], ["amarr", "frigate", "defense"], False, [
        (1, 45, 200, 600, 30, 30), (1, 60, 370, 950, 60, 60), (1, 80, 420, 1300, 90, 90),
    ]),
    (2, "检察官级", 4, ["frigate"], ["amarr", "frigate", "logistic"], True, [
        (3, 20, 180, 500, 5, 5), (3, 30, 250, 750, 10, 10), (3, 40, 350, 900, 15, 15),
    ]),
    (3, "巨神兵级", 3, ["frigate"], ["amarr", "frigate", "firepower"], False, [
        (2, 65, 180, 500, 10, 10), (2, 110, 270, 800, 20, 20), (2, 145, 380, 1000, 30, 30),
    ]),
    (4, "富豪级", 3, ["frigate"], ["amarr", "frigate", "exploration"], False, [
        (1, 20, 120, 350, 10, 10), (1, 30, 180, 500, 20, 20), (1, 40, 250, 750, 30, 30),
    ]),
    (5, "强制者级", 4, ["destroyer"], ["amarr", "destroyer", "firepower"], False, [
        (4, 90, 220, 650, 15, 15), (4, 135, 370, 950, 25, 25), (4, 160, 400, 1100, 40, 40),
    ]),
    (6, "龙骑兵级", 4, ["destroyer"], ["amarr", "destroyer", "defense"], False, [
        (3, 60, 250, 750, 35, 35), (3, 90, 400, 1100, 45, 45), (3, 120, 450, 1500, 70, 70),
    ]),
    (7, "启示级", 6, ["cruiser"], ["amarr", "cruiser", "firepower"], False, [
        (5, 100, 300, 850, 25, 25), (5, 150, 410, 1200, 40, 40), (5, 200, 450, 1500, 60, 60),
    ]),
    (8, "奥格诺级", 7, ["cruiser"], ["amarr", "cruiser", "logistic"], True, [
        (6, 60, 250, 750, 15, 15), (6, 90, 370, 950, 25, 25), (6, 120, 420, 1300, 40, 40),
    ]),
    (9, "暴君级", 7, ["cruiser"], ["amarr", "cruiser", "defense"], False, [
        (4, 70, 320, 900, 40, 40), (4, 90, 500, 1550, 55, 55), (4, 110, 600, 2200, 90, 90),
    ]),
    (10, "主宰级", 6, ["cruiser"], ["amarr", "cruiser", "ewar"], False, [
        (4, 60, 250, 750, 15, 15), (4, 90, 370, 950, 25, 25), (4, 120, 420, 1300, 40, 40),
    ]),
]

FETTERS = [
    ("amarr", "艾玛", [{"champion_count": 2, "effect_type": "Damage", "effect_value_type": "Percentage", "effect_target": "SelfFetter", "value": 10.0}]),
    ("caldari", "加达里", []),
    ("gallente", "盖伦特", []),
    ("minmatar", "米玛塔尔", []),
    ("concord", "统合部航天局", []),
    ("frigate", "护卫舰", [{"champion_count": 2, "effect_type": "Damage", "effect_value_type": "Percentage", "effect_target": "SelfFetter", "value": 10.0}]),
    ("destroyer", "驱逐舰", [{"champion_count": 2, "effect_type": "Damage", "effect_value_type": "Percentage", "effect_target": "SelfFetter", "value": 10.0}]),
    ("cruiser", "巡洋舰", [{"champion_count": 2, "effect_type": "Damage", "effect_value_type": "Percentage", "effect_target": "SelfFetter", "value": 10.0}]),
    ("carrier", "航空母舰", []),
    ("firepower", "火力", [{"champion_count": 2, "effect_type": "Damage", "effect_value_type": "Percentage", "effect_target": "SelfFetter", "value": 10.0}]),
    ("logistic", "后勤", [{"champion_count": 2, "effect_type": "ArmorHeal", "effect_value_type": "Percentage", "effect_target": "SelfFetter", "value": 10.0}]),
    ("ewar", "电子战", [{"champion_count": 2, "effect_type": "Damage", "effect_value_type": "Percentage", "effect_target": "SelfFetter", "value": 10.0}]),
    ("exploration", "探索", [{"champion_count": 2, "effect_type": "Damage", "effect_value_type": "Percentage", "effect_target": "SelfFetter", "value": 10.0}]),
    ("defense", "防御", [{"champion_count": 2, "effect_type": "ArmorResist", "effect_value_type": "Percentage", "effect_target": "SelfFetter", "value": 10.0}]),
]

ADMIN_POLICIES = {
    "admin_enabled": True,
    "policies": [
        {
            "id": "dev_log_income",
            "channel": "economy.income",
            "enabled": False,
            "actions": [{"op": "mul_field", "field": "income", "factor": 1.0}],
        }
    ],
}


def star_row(t):
    ar, de, sh, armp, sr, ares = t
    z = [0, 0, 0]
    return {
        "attack_range": ar,
        "damage": {"emp": de, "thermal": 0, "kinetic": 0, "explosive": 0},
        "shield_hp": sh,
        "armor_hp": armp,
        "shield_resist": {"emp": sr, "thermal": 0, "kinetic": 0, "explosive": 0},
        "armor_resist": {"emp": ares, "thermal": 0, "kinetic": 0, "explosive": 0},
    }


def main():
    for name, obj in BALANCE.items():
        p = ROOT / "balance" / f"{name}.json"
        p.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ROOT / "admin" / "policies.json").write_text(
        json.dumps(ADMIN_POLICIES, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    for sid, name, cost, groups, fids, logistic, stars in SHIPS:
        doc = {
            "id": sid,
            "name": name,
            "cost": cost,
            "ship_groups": groups,
            "fetter_ids": fids,
            "is_logistic": logistic,
            "stars": [star_row(s) | {"is_logistic": logistic} for s in stars],
        }
        (ROOT / "ships" / f"{sid}.json").write_text(
            json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    for fid, name, effects in FETTERS:
        doc = {"id": fid, "name": name, "effects": effects}
        (ROOT / "fetters" / f"{fid}.json").write_text(
            json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    print("wrote data to", ROOT)


if __name__ == "__main__":
    main()
