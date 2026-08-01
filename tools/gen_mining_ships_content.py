# -*- coding: utf-8 -*-
"""Write mining ship + Excavator content JSON stubs from confirmed SDE stats."""
from __future__ import annotations

import json
from pathlib import Path

OUT = Path(r"H:\game_dev\eveautochess-dev\godot_project\data\ships")
FETTERS = Path(r"H:\game_dev\eveautochess-dev\godot_project\data\fetters")
PORTRAITS = Path(r"H:\game_dev\eveautochess-dev\godot_project\data\ship_portraits.json")


def star_block(shield: float, armor: float, structure: float, scale: float = 1.0) -> dict:
    return {
        "attack_range": 3,
        "damage": {"emp": 0.0, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0},
        "repair": {"shield": 0.0, "armor": 0.0, "structure": 0.0},
        "tracking": 50.0,
        "optimal": 10000.0,
        "falloff": 5000.0,
        "optimal_sig_radius": 100.0,
        "shield_hp": shield * scale,
        "armor_hp": armor * scale,
        "structure_hp": structure * scale,
        "shield_resist": {"emp": 0.0, "thermal": 0.2, "kinetic": 0.4, "explosive": 0.5},
        "armor_resist": {"emp": 0.5, "thermal": 0.35, "kinetic": 0.25, "explosive": 0.2},
        "structure_resist": {"emp": 0.33, "thermal": 0.33, "kinetic": 0.33, "explosive": 0.33},
        "is_logistic": False,
    }


def ship(
    sid: int,
    name: str,
    name_en: str,
    type_id: int,
    model_key: str,
    cost: int,
    ship_group: str,
    fetter_ids: list[str],
    shield: float,
    armor: float,
    structure: float,
    speed: float,
    sig: float,
    sensor: float,
    scan_res: float,
    long_axis: float,
    *,
    portrait: str = "",
    drone_bay_slots: int = 0,
    drone_count_cap: int = 0,
    mining_gold: int = 0,
    mining_drone_id: int = 0,
    shop_min_level: int = 0,
    is_unmanned: bool = False,
    unmanned_kind: str = "",
    source_module_type_id: int = 17482,
) -> dict:
    tags = list(fetter_ids)
    d = {
        "id": sid,
        "name": name,
        "name_en": name_en,
        "type_id": type_id,
        "model_key": model_key,
        "cost": cost,
        "ship_groups": [ship_group],
        "ship_group": ship_group,
        "fetter_ids": fetter_ids,
        "tags": tags,
        "is_logistic": False,
        "requires_cyno_entry": False,
        "capital_role": "",
        "weapon_fx": "mining",
        "race": "ore",
        "signature_radius": sig,
        "sensor_strength": sensor,
        "scan_resolution": scan_res,
        "speed": speed,
        "mining_gold_per_round": mining_gold,
        "is_mining_ship": not is_unmanned,
        "is_unmanned": is_unmanned,
        "unmanned_kind": unmanned_kind,
        "function_slots": {"slots": []},
        "hi_slots": 2,
        "med_slots": 2,
        "low_slots": 2,
        "source_module_type_id": source_module_type_id,
        "drone_bandwidth": 0.0,
        "drone_bay_slots": drone_bay_slots,
        "drone_count_cap": drone_count_cap,
        "attack_cycle_s": 5.0,
        "stars": [
            star_block(shield, armor, structure, 1.0),
            star_block(shield, armor, structure, 2.0),
            star_block(shield, armor, structure, 3.0),
        ],
        "model_long_axis": long_axis,
    }
    if portrait:
        d["portrait"] = portrait
    if mining_drone_id > 0:
        d["mining_drone_id"] = mining_drone_id
        d["mining_drone_count"] = drone_bay_slots or drone_count_cap or 4
    if shop_min_level > 0:
        d["shop_min_level"] = shop_min_level
    return d


def main() -> None:
    ships = [
        ship(
            135,
            "回旋者级",
            "Retriever",
            17478,
            "lhky_huixuanzhe",
            3,
            "mining_barge",
            ["ore", "mining_barge"],
            4000,
            3000,
            4000,
            125,
            200,
            9,
            550,
            202,
            mining_gold=25,
        ),
        ship(
            136,
            "海豚级",
            "Porpoise",
            42244,
            "lhky_haitun",
            5,
            "mining_barge",
            ["ore", "mining_barge", "mining_command"],
            6000,
            3000,
            8000,
            100,
            300,
            20,
            90,
            450,
            mining_gold=10,
        ),
        ship(
            137,
            "逆戟鲸级",
            "Orca",
            28606,
            "lhky_nijijing",
            7,
            "industrial_command",
            ["ore", "industrial_command"],
            30000,
            7000,
            45000,
            60,
            1000,
            30,
            75,
            550,
            mining_gold=40,
        ),
        ship(
            138,
            "长须鲸级",
            "Rorqual",
            28352,
            "lhky_changxujing",
            22,
            "capital_industrial",
            ["ore", "capital_industrial"],
            90000,
            60000,
            300000,
            60,
            11500,
            115,
            75,
            1100,
            portrait="res://assets/ui/ship_portraits_capital/rorqual.png",
            drone_bay_slots=4,
            drone_count_cap=4,
            mining_gold=0,
            mining_drone_id=139,
        ),
        ship(
            139,
            "采掘者采矿无人机",
            "Excavator Mining Drone",
            41030,
            "wrj_ore_excavator",
            0,
            "drone_heavy",
            ["ore"],
            1500,
            1000,
            1500,
            250,
            200,
            1,
            100,
            5,
            mining_gold=25,
            is_unmanned=True,
            unmanned_kind="mining_excavator",
            source_module_type_id=0,
        ),
    ]
    for s in ships:
        path = OUT / f"{s['id']}.json"
        path.write_text(json.dumps(s, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("wrote", path)

    fetter = {
        "id": "mining_command",
        "name": "挖矿指挥",
        "effects": [
            {
                "champion_count": 1,
                "effect_type": "MiningGoldBonus",
                "effect_value_type": "Percentage",
                "effect_target": "OtherMiningSources",
                "value": 20.0,
            }
        ],
    }
    fp = FETTERS / "mining_command.json"
    fp.write_text(json.dumps(fetter, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("wrote", fp)

    # Also stub tonnage-as-fetter ids if missing (optional shop display)
    for fid, fname in (
        ("ore", "联合矿业"),
        ("mining_barge", "采矿驳船"),
        ("industrial_command", "工业指挥"),
        ("capital_industrial", "旗舰工业"),
    ):
        p = FETTERS / f"{fid}.json"
        if not p.is_file():
            p.write_text(
                json.dumps(
                    {
                        "id": fid,
                        "name": fname,
                        "effects": [],
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            print("wrote", p)

    if PORTRAITS.is_file():
        portraits = json.loads(PORTRAITS.read_text(encoding="utf-8"))
    else:
        portraits = {}
    portraits["135"] = "res://assets/ui/portraits/lhky_huixuanzhe.png"
    portraits["136"] = "res://assets/ui/portraits/lhky_haitun.png"
    portraits["137"] = "res://assets/ui/portraits/lhky_nijijing.png"
    portraits["138"] = "res://assets/ui/ship_portraits_capital/rorqual.png"
    portraits["139"] = "res://assets/ui/portraits/wrj_ore_excavator.png"
    PORTRAITS.write_text(json.dumps(portraits, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("updated", PORTRAITS)


if __name__ == "__main__":
    main()
