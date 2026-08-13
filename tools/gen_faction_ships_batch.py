# -*- coding: utf-8 -*-
"""Generate faction ship JSON 801-822 + Guristas C drones + logistic drones 1421-1424."""
from __future__ import annotations

import json
import shutil
from copy import deepcopy
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev\godot_project")
SHIPS = ROOT / "data" / "ships"
UNMANNED = ROOT / "data" / "unmanned_units"
PORTRAITS_JSON = ROOT / "data" / "ship_portraits.json"
PORTRAIT_DIR = ROOT / "assets" / "ui" / "portraits"
FETTER_ICONS = ROOT / "assets" / "ui" / "sprites" / "FetterIcons"
FACTION_ICONS = ROOT / "assets" / "ui" / "faction_icons"
DELIRIUM_SRC = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\preview\faction_ships"
    r"\portraits\cutouts_flagship\delirium_cutout.png"
)
REVIEW_PORTRAIT = (
    ROOT / "assets" / "review" / "faction_batch_portraits" / "ss_yueshengzhe.png"
)

# EMP/Th/Kin/Ex → emp/thermal/kinetic/explosive
STRUCT_R = {"emp": 0.33, "thermal": 0.33, "kinetic": 0.33, "explosive": 0.33}

MOD = {
    "missile": {"small": 499, "medium": 501, "large": 13320, "capital": 0},
    "cannon": {"small": 485, "medium": 491, "large": 498},
    "rail": {"small": 561, "medium": 570, "large": 574},
    "laser": {"small": 453, "medium": 456, "large": 462},
}

# attack_cycle from empire same-fx frigates/cruisers/BS (approx from existing content)
CYCLE = {"missile": 4.0, "cannon": 3.5, "rail": 3.5, "laser": 3.5, "heal": 3.0}
RANGE = {
    "missile": 999.0,
    "cannon": {"frigate": 3.0, "cruiser": 6.0, "battleship": 9.0},
    "rail": {"frigate": 4.0, "cruiser": 8.0, "battleship": 12.0},
    "laser": {"frigate": 3.0, "cruiser": 6.0, "battleship": 9.0},
    "heal": {"frigate": 4.0, "cruiser": 8.0, "battleship": 12.0},
}

SHIPS_DEF = [
    # id, race, group, name, name_en, type_id, model_key, sof, long_axis, cost, shop_lv,
    # shield, armor, structure, speed, agility, sig, sensor, scan, cap, recharge,
    # hi, med, low, launchers, turrets, drone_bay, drone_bw, mass,
    # shield_r, armor_r, weapon_fx, slots_kind (launch|turret|heal), notes
    dict(
        id=801,
        race="guristas",
        group="frigate",
        name="毒蜥级",
        name_en="Worm",
        type_id=17930,
        model_key="gsts_duxi",
        sof_hull="cf7_t1",
        model_long_axis=80,
        cost=3,
        shop_min_level=2,
        shield=830,
        armor=500,
        structure=620,
        speed=320,
        agility=3.8,
        signature_radius=40,
        sensor_strength=15,
        scan_resolution=650,
        capacitor_capacity=380,
        capacitor_recharge_s=212,
        hi=3,
        med=4,
        low=2,
        launchers=3,
        turrets=0,
        drone_bay=25,
        drone_bw=10,
        mass=981000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.45, 0.25, 0.1),
        weapon_fx="missile",
        role="firepower",
        guristas_drones=True,
    ),
    dict(
        id=802,
        race="guristas",
        group="cruiser",
        name="潜龙级",
        name_en="Gila",
        type_id=17715,
        model_key="gsts_qianlong",
        sof_hull="cc2_t1",
        model_long_axis=174,
        cost=7,
        shop_min_level=6,
        shield=3200,
        armor=2200,
        structure=2490,
        speed=195,
        agility=0.66,
        signature_radius=145,
        sensor_strength=22,
        scan_resolution=285,
        capacitor_capacity=1400,
        capacitor_recharge_s=490,
        hi=5,
        med=6,
        low=3,
        launchers=4,
        turrets=0,
        drone_bay=100,
        drone_bw=20,
        mass=9600000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.45, 0.25, 0.1),
        weapon_fx="missile",
        role="firepower",
        guristas_drones=True,
    ),
    dict(
        id=803,
        race="guristas",
        group="battleship",
        name="响尾蛇级",
        name_en="Rattlesnake",
        type_id=17918,
        model_key="gsts_xiangweishe",
        sof_hull="cb2_t1",
        model_long_axis=450,
        cost=18,
        shop_min_level=14,
        shield=14025,
        armor=9834,
        structure=10956,
        speed=94,
        agility=0.128,
        signature_radius=450,
        sensor_strength=30,
        scan_resolution=130,
        capacitor_capacity=5350,
        capacitor_recharge_s=1154,
        hi=6,
        med=7,
        low=6,
        launchers=5,
        turrets=0,
        drone_bay=175,
        drone_bw=50,
        mass=99300000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.45, 0.25, 0.1),
        weapon_fx="missile",
        role="firepower",
        guristas_drones=True,
    ),
    dict(
        id=804,
        race="angel",
        group="frigate",
        name="德拉米尔级",
        name_en="Dramiel",
        type_id=17932,
        model_key="tsl_delamier",
        sof_hull="angf1_t1",
        model_long_axis=80,
        cost=3,
        shop_min_level=2,
        shield=590,
        armor=590,
        structure=520,
        speed=460,
        agility=3.1,
        signature_radius=30,
        sensor_strength=11,
        scan_resolution=750,
        capacitor_capacity=370,
        capacitor_recharge_s=208,
        hi=3,
        med=4,
        low=3,
        launchers=1,
        turrets=2,
        drone_bay=20,
        drone_bw=15,
        mass=950000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.6, 0.35, 0.25, 0.1),
        weapon_fx="cannon",
        role="firepower",
    ),
    dict(
        id=805,
        race="angel",
        group="cruiser",
        name="塞纳波级",
        name_en="Cynabal",
        type_id=17720,
        model_key="tsl_sainabo",
        sof_hull="angbc1_t1",
        model_long_axis=200,
        cost=7,
        shop_min_level=6,
        shield=2330,
        armor=2300,
        structure=2065,
        speed=263,
        agility=0.45,
        signature_radius=115,
        sensor_strength=18,
        scan_resolution=390,
        capacitor_capacity=1415,
        capacitor_recharge_s=490,
        hi=5,
        med=5,
        low=5,
        launchers=0,
        turrets=4,
        drone_bay=50,
        drone_bw=50,
        mass=9050000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.6, 0.35, 0.25, 0.1),
        weapon_fx="cannon",
        role="firepower",
    ),
    dict(
        id=806,
        race="angel",
        group="battleship",
        name="马克瑞级",
        name_en="Machariel",
        type_id=17738,
        model_key="tsl_makerui",
        sof_hull="angb1_t1",
        model_long_axis=450,
        cost=18,
        shop_min_level=14,
        shield=10252,
        armor=10175,
        structure=9086,
        speed=161,
        agility=0.096,
        signature_radius=380,
        sensor_strength=26,
        scan_resolution=163,
        capacitor_capacity=5800,
        capacitor_recharge_s=1154,
        hi=8,
        med=6,
        low=6,
        launchers=0,
        turrets=7,
        drone_bay=125,
        drone_bw=100,
        mass=94700000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.6, 0.35, 0.25, 0.1),
        weapon_fx="cannon",
        role="firepower",
    ),
    dict(
        id=807,
        race="serpentis",
        group="frigate",
        name="夜魔侠级",
        name_en="Daredevil",
        type_id=17928,
        model_key="ts_yemoxia",
        sof_hull="angf2_t1",
        model_long_axis=80,
        cost=3,
        shop_min_level=2,
        shield=530,
        armor=560,
        structure=630,
        speed=385,
        agility=3.2,
        signature_radius=35,
        sensor_strength=12,
        scan_resolution=650,
        capacitor_capacity=390,
        capacitor_recharge_s=230,
        hi=3,
        med=3,
        low=4,
        launchers=0,
        turrets=2,
        drone_bay=0,
        drone_bw=0,
        mass=823000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.35, 0.35, 0.1),
        weapon_fx="rail",
        role="firepower",
    ),
    dict(
        id=808,
        race="serpentis",
        group="cruiser",
        name="警惕级",
        name_en="Vigilant",
        type_id=17722,
        model_key="ts_jingti",
        sof_hull="gc4_t1",
        model_long_axis=174,
        cost=7,
        shop_min_level=6,
        shield=2175,
        armor=2500,
        structure=2625,
        speed=242,
        agility=0.48,
        signature_radius=130,
        sensor_strength=20,
        scan_resolution=300,
        capacitor_capacity=1545,
        capacitor_recharge_s=490,
        hi=5,
        med=4,
        low=6,
        launchers=0,
        turrets=5,
        drone_bay=50,
        drone_bw=50,
        mass=9830000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.35, 0.35, 0.1),
        weapon_fx="rail",
        role="firepower",
    ),
    dict(
        id=809,
        race="serpentis",
        group="battleship",
        name="复仇者级",
        name_en="Vindicator",
        type_id=17740,
        model_key="ts_fuchouzhe",
        sof_hull="gb2_t1",
        model_long_axis=450,
        cost=18,
        shop_min_level=14,
        shield=9625,
        armor=10230,
        structure=11550,
        speed=132,
        agility=0.083,
        signature_radius=400,
        sensor_strength=28,
        scan_resolution=130,
        capacitor_capacity=6330,
        capacitor_recharge_s=1154,
        hi=8,
        med=5,
        low=7,
        launchers=0,
        turrets=8,
        drone_bay=125,
        drone_bw=125,
        mass=105200000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.35, 0.35, 0.1),
        weapon_fx="rail",
        role="firepower",
    ),
    dict(
        id=810,
        race="soe",
        group="frigate",
        name="阿斯特罗级",
        name_en="Astero",
        type_id=33468,
        model_key="jmh_asiteluo",
        sof_hull="soef1_t1",
        model_long_axis=80,
        cost=3,
        shop_min_level=2,
        shield=540,
        armor=600,
        structure=600,
        speed=312,
        agility=2.87,
        signature_radius=35,
        sensor_strength=13,
        scan_resolution=620,
        capacitor_capacity=430,
        capacitor_recharge_s=195,
        hi=2,
        med=4,
        low=4,
        launchers=0,
        turrets=2,
        drone_bay=75,
        drone_bw=25,
        mass=975000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.35, 0.35, 0.1),
        weapon_fx="heal",
        role="logistic",
        is_logistic=True,
        repair_mod=11355,
    ),
    dict(
        id=811,
        race="soe",
        group="cruiser",
        name="斯特修斯级",
        name_en="Stratios",
        type_id=33470,
        model_key="jmh_sitexiusi",
        sof_hull="soec1_t1",
        model_long_axis=174,
        cost=7,
        shop_min_level=6,
        shield=1950,
        armor=2400,
        structure=2450,
        speed=182,
        agility=0.47,
        signature_radius=150,
        sensor_strength=20,
        scan_resolution=275,
        capacitor_capacity=1700,
        capacitor_recharge_s=456,
        hi=5,
        med=5,
        low=5,
        launchers=0,
        turrets=3,
        drone_bay=400,
        drone_bw=100,
        mass=9350000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.35, 0.35, 0.1),
        weapon_fx="heal",
        role="logistic",
        is_logistic=True,
        repair_mod=11357,
    ),
    dict(
        id=812,
        race="soe",
        group="battleship",
        name="涅斯托级",
        name_en="Nestor",
        type_id=33472,
        model_key="jmh_niesituo",
        sof_hull="soeb1_t1",
        model_long_axis=450,
        cost=30,
        shop_min_level=14,
        shield=9790,
        armor=10945,
        structure=10890,
        speed=70,
        agility=0.35,
        signature_radius=420,
        sensor_strength=30,
        scan_resolution=163,
        capacitor_capacity=7000,
        capacitor_recharge_s=1025,
        hi=0,  # 后编 play rule (SDE hi=7)
        med=6,
        low=6,
        launchers=0,
        turrets=5,
        drone_bay=500,
        drone_bw=125,
        mass=20000000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.35, 0.35, 0.1),
        weapon_fx="heal",
        role="logistic",
        is_logistic=True,
        nestor=True,
        repair_mod=0,
    ),
    dict(
        id=813,
        race="blood",
        group="frigate",
        name="凝血级",
        name_en="Cruor",
        type_id=17926,
        model_key="xxz_ningxue",
        sof_hull="af8_t1",
        model_long_axis=80,
        cost=3,
        shop_min_level=2,
        shield=480,
        armor=740,
        structure=580,
        speed=340,
        agility=3.4,
        signature_radius=35,
        sensor_strength=12,
        scan_resolution=760,
        capacitor_capacity=470,
        capacitor_recharge_s=205,
        hi=4,
        med=3,
        low=4,
        launchers=0,
        turrets=2,
        drone_bay=10,
        drone_bw=10,
        mass=1003000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.35, 0.25, 0.2),
        weapon_fx="laser",
        role="ewar",
    ),
    dict(
        id=814,
        race="blood",
        group="cruiser",
        name="阿什姆级",
        name_en="Ashimmu",
        type_id=17722 if False else 17922,
        model_key="xxz_ashimu",
        sof_hull="ac6_t1",
        model_long_axis=174,
        cost=7,
        shop_min_level=6,
        shield=2290,
        armor=2950,
        structure=2325,
        speed=215,
        agility=0.55,
        signature_radius=130,
        sensor_strength=19,
        scan_resolution=340,
        capacitor_capacity=1850,
        capacitor_recharge_s=530,
        hi=5,
        med=4,
        low=6,
        launchers=0,
        turrets=3,
        drone_bay=50,
        drone_bw=50,
        mass=11010000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.35, 0.25, 0.2),
        weapon_fx="laser",
        role="ewar",
    ),
    dict(
        id=815,
        race="blood",
        group="battleship",
        name="巴戈龙级",
        name_en="Bhaalgorn",
        type_id=17920,
        model_key="xxz_bagelong",
        sof_hull="ab2_t1",
        model_long_axis=450,
        cost=18,
        shop_min_level=14,
        shield=10230,
        armor=11935,
        structure=10230,
        speed=101,
        agility=0.125,
        signature_radius=400,
        sensor_strength=28,
        scan_resolution=130,
        capacitor_capacity=7500,
        capacitor_recharge_s=1154,
        hi=7,
        med=5,
        low=7,
        launchers=0,
        turrets=4,
        drone_bay=150,
        drone_bw=100,
        mass=97100000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.35, 0.25, 0.2),
        weapon_fx="laser",
        role="ewar",
    ),
    dict(
        id=816,
        race="mordu",
        group="frigate",
        name="加姆级",
        name_en="Garmur",
        type_id=33816,
        model_key="mdt_jiamu",
        sof_hull="morf1_t1",
        model_long_axis=80,
        cost=3,
        shop_min_level=2,
        shield=680,
        armor=590,
        structure=560,
        speed=415,
        agility=3.2,
        signature_radius=32,
        sensor_strength=13,
        scan_resolution=650,
        capacitor_capacity=400,
        capacitor_recharge_s=195,
        hi=3,
        med=4,
        low=3,
        launchers=3,
        turrets=0,
        drone_bay=0,
        drone_bw=0,
        mass=987000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.45, 0.25, 0.1),
        weapon_fx="missile",
        role="firepower",
    ),
    dict(
        id=817,
        race="mordu",
        group="cruiser",
        name="奥苏斯级",
        name_en="Orthrus",
        type_id=33818,
        model_key="mdt_aosusi",
        sof_hull="morc1_t1",
        model_long_axis=174,
        cost=7,
        shop_min_level=6,
        shield=2950,
        armor=2280,
        structure=2100,
        speed=230,
        agility=0.48,
        signature_radius=135,
        sensor_strength=21,
        scan_resolution=300,
        capacitor_capacity=1550,
        capacitor_recharge_s=490,
        hi=6,
        med=5,
        low=4,
        launchers=5,
        turrets=0,
        drone_bay=25,
        drone_bw=25,
        mass=9360000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.45, 0.25, 0.1),
        weapon_fx="missile",
        role="firepower",
    ),
    dict(
        id=818,
        race="mordu",
        group="battleship",
        name="巴盖斯级",
        name_en="Barghest",
        type_id=33820,
        model_key="mdt_bagaisi",
        sof_hull="morb1_t1",
        model_long_axis=450,
        cost=18,
        shop_min_level=14,
        shield=12320,
        armor=9625,
        structure=8910,
        speed=148,
        agility=0.098,
        signature_radius=370,
        sensor_strength=29,
        scan_resolution=143,
        capacitor_capacity=6100,
        capacitor_recharge_s=1155,
        hi=8,
        med=6,
        low=6,
        launchers=6,
        turrets=0,
        drone_bay=75,
        drone_bw=50,
        mass=98500000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.45, 0.25, 0.1),
        weapon_fx="missile",
        role="firepower",
    ),
    dict(
        id=819,
        race="sansha",
        group="frigate",
        name="魔女级",
        name_en="Succubus",
        type_id=17924,
        model_key="ss_monv",
        sof_hull="sf1_t1",
        model_long_axis=80,
        cost=3,
        shop_min_level=2,
        shield=650,
        armor=550,
        structure=540,
        speed=340,
        agility=3.5,
        signature_radius=33,
        sensor_strength=13,
        scan_resolution=650,
        capacitor_capacity=525,
        capacitor_recharge_s=210,
        hi=3,
        med=4,
        low=3,
        launchers=0,
        turrets=2,
        drone_bay=0,
        drone_bw=0,
        mass=965000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.35, 0.25, 0.2),
        weapon_fx="laser",
        role="firepower",
    ),
    dict(
        id=820,
        race="sansha",
        group="cruiser",
        name="幽灵级",
        name_en="Phantasm",
        type_id=17718,
        model_key="ss_youling",
        sof_hull="sc1_t1",
        model_long_axis=174,
        cost=7,
        shop_min_level=6,
        shield=2700,
        armor=2175,
        structure=2065,
        speed=228,
        agility=0.62,
        signature_radius=120,
        sensor_strength=20,
        scan_resolution=275,
        capacitor_capacity=1800,
        capacitor_recharge_s=495,
        hi=4,
        med=6,
        low=5,
        launchers=0,
        turrets=3,
        drone_bay=15,
        drone_bw=15,
        mass=9600000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.35, 0.25, 0.2),
        weapon_fx="laser",
        role="firepower",
    ),
    dict(
        id=821,
        race="sansha",
        group="battleship",
        name="噩梦级",
        name_en="Nightmare",
        type_id=17736,
        model_key="ss_emeng",
        sof_hull="sb1_t1",
        model_long_axis=450,
        cost=18,
        shop_min_level=14,
        shield=11605,
        armor=9515,
        structure=9020,
        speed=114,
        agility=0.122,
        signature_radius=370,
        sensor_strength=28,
        scan_resolution=143,
        capacitor_capacity=6950,
        capacitor_recharge_s=1154,
        hi=6,
        med=7,
        low=6,
        launchers=0,
        turrets=4,
        drone_bay=75,
        drone_bw=75,
        mass=99300000,
        shield_r=(0, 0.2, 0.4, 0.5),
        armor_r=(0.5, 0.35, 0.25, 0.2),
        weapon_fx="laser",
        role="firepower",
    ),
]


def resist_tuple(t):
    return {
        "emp": float(t[0]),
        "thermal": float(t[1]),
        "kinetic": float(t[2]),
        "explosive": float(t[3]),
    }


def star_block(d, mul: int, attack_range: float, is_logistic: bool) -> dict:
    return {
        "armor_hp": float(d["armor"] * mul),
        "armor_resist": resist_tuple(d["armor_r"]),
        "attack_range": float(attack_range),
        "is_logistic": bool(is_logistic),
        "shield_hp": float(d["shield"] * mul),
        "shield_resist": resist_tuple(d["shield_r"]),
        "structure_hp": float(d["structure"] * mul),
        "structure_resist": dict(STRUCT_R),
    }


def weapon_tier_for(group: str) -> str:
    return {
        "frigate": "small",
        "cruiser": "medium",
        "battleship": "large",
        "carrier": "capital",
    }[group]


def attack_range_for(d) -> float:
    fx = d["weapon_fx"]
    if fx == "missile":
        return 999.0
    return float(RANGE[fx][d["group"]])


def build_ship(d: dict) -> dict:
    race = d["race"]
    group = d["group"]
    role = d["role"]
    fx = d["weapon_fx"]
    is_log = bool(d.get("is_logistic", False))
    tier = weapon_tier_for(group)
    if fx == "heal":
        src_mod = 0
        repair = int(d.get("repair_mod", 0))
        atk_slots = 0 if d.get("nestor") else max(1, int(d["hi"]))
    elif fx == "missile":
        src_mod = MOD["missile"][tier]
        repair = 0
        atk_slots = int(d["launchers"])
    else:
        src_mod = MOD[fx][tier]
        repair = 0
        atk_slots = int(d["turrets"]) if d["turrets"] else int(d["launchers"])

    fetter_ids = [race, group, role]
    if d.get("nestor"):
        fetter_ids = [race, group, "logistic"]
    tags = list(fetter_ids)

    ar = attack_range_for(d)
    out = {
        "agility": float(d["agility"]),
        "attack_cycle_s": float(CYCLE.get(fx, 3.5)),
        "attack_weapon_slots": float(atk_slots),
        "capacitor_capacity": float(d["capacitor_capacity"]),
        "capacitor_recharge_s": float(d["capacitor_recharge_s"]),
        "cost": float(d["cost"]),
        "drone_bandwidth": float(d["drone_bw"]),
        "drone_bay_slots": float(2 if d.get("guristas_drones") else (4 if d.get("nestor") else 0)),
        "drone_count_cap": float(2 if d.get("guristas_drones") else (4 if d.get("nestor") else 0)),
        "echoes_item_id": 0.0,
        "faction_ship": True,
        "fetter_ids": fetter_ids,
        "function_slots": {"slots": []},
        "hi_slots": float(d["hi"]),
        "id": float(d["id"]),
        "is_logistic": is_log,
        "low_slots": float(d["low"]),
        "mass": float(d["mass"]),
        "med_slots": float(d["med"]),
        "mid_battle_leave_allowed": False,
        "model_key": d["model_key"],
        "model_long_axis": float(d["model_long_axis"]),
        "name": d["name"],
        "name_en": d["name_en"],
        "portrait": f"res://assets/ui/portraits/{d['model_key']}.png",
        "race": race,
        "scan_resolution": float(d["scan_resolution"]),
        "sensor_strength": float(d["sensor_strength"]),
        "ship_group": group,
        "ship_groups": [group],
        "shop_min_level": float(d["shop_min_level"]),
        "signature_radius": float(d["signature_radius"]),
        "sof_hull": d["sof_hull"],
        "source_module_type_id": float(src_mod),
        "source_repair_module_type_id": float(repair),
        "speed": float(d["speed"]),
        "stars": [star_block(d, 1, ar, is_log), star_block(d, 2, ar, is_log), star_block(d, 3, ar, is_log)],
        "tags": tags,
        "type_id": float(d["type_id"]),
        "weapon_fx": fx,
        "weapon_tier": tier,
    }
    if d.get("guristas_drones"):
        # 后编: forced 2 drone slots; C drones ×2 via unit ids
        size = {"frigate": 1502, "cruiser": 1506, "battleship": 1512}[group]
        out["drone_unit_ids"] = [size, size]
        out["drone_bay_slots"] = 2.0
        out["drone_count_cap"] = 2.0
    if d.get("nestor"):
        out["battle_equip_aura"] = True  # 后编
        out["drone_unit_ids"] = [1421, 1422, 1423, 1424]
        out["source_module_type_id"] = 0.0
    return out


def build_delirium() -> dict:
    chim = json.loads((SHIPS / "122.json").read_text(encoding="utf-8"))
    out = deepcopy(chim)
    out.update(
        {
            "id": 822.0,
            "name": "跃升者级",
            "name_en": "Delirium",
            "model_key": "ss_yueshengzhe",
            "sof_hull": "sca1_t1",
            "model_long_axis": 1100.0,
            "mass": 1.24e9,  # 后编 ESI Chimera
            "race": "sansha",
            "cost": 37.0,
            "shop_min_level": 16.0,
            "faction_ship": True,
            "type_id": 0.0,
            "echoes_item_id": 0.0,
            "portrait": "res://assets/ui/portraits/ss_yueshengzhe.png",
            "fetter_ids": ["sansha", "carrier", "firepower"],
            "tags": ["sansha", "carrier", "firepower"],
            "capital_role": "carrier",
            "requires_cyno_entry": True,
            "fighter_unit_id": 0.0,
            "fighter_unit_ids": [1401, 1402, 1403, 1404],
            "fighter_squadrons": 4.0,
            "fighter_tubes_per_squadron": 3.0,
            "fighter_squadron_pool": 10.0,
            "fighter_key": "multi",
            "source_module_type_id": 0.0,
            "source_repair_module_type_id": 0.0,
            "weapon_fx": "missile",
            "weapon_tier": "capital",
            "hi_slots": 0.0,
            "mid_battle_leave_allowed": False,
        }
    )
    # keep chimera stars/cap/speed from 122
    return out


def double_drone(src_name: str, new_id: int, new_name: str, out_name: str) -> None:
    src = json.loads((UNMANNED / src_name).read_text(encoding="utf-8"))
    src["id"] = new_id
    src["name"] = new_name
    src["name_en"] = f"Guristas {src.get('name_en', 'Drone')}"
    src["race"] = "guristas"
    tags = list(src.get("tags", []))
    tags = [("guristas" if t == "caldari" else t) for t in tags]
    if "guristas" not in tags:
        tags.append("guristas")
    src["tags"] = tags
    for st in src.get("stars", []):
        dmg = st.get("damage", {})
        for k in list(dmg.keys()):
            dmg[k] = float(dmg[k]) * 2.0
        st["damage"] = dmg
        for hk in ("shield_hp", "armor_hp", "structure_hp"):
            if hk in st:
                st[hk] = float(st[hk]) * 2.0
    (UNMANNED / out_name).write_text(
        json.dumps(src, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def clone_logistic_drone(src: str, new_id: int, name: str, out_name: str, race: str) -> None:
    # Prefer FAX light logistics if present; else invent minimal from combat drone + heal
    path = UNMANNED / src
    if path.exists():
        src_d = json.loads(path.read_text(encoding="utf-8"))
    else:
        # fallback: light combat drone shell
        src_d = json.loads((UNMANNED / "caldari_light.json").read_text(encoding="utf-8"))
        src_d["is_logistic"] = True
        src_d["weapon_fx"] = "heal"
        for st in src_d.get("stars", []):
            st["damage"] = {"emp": 0, "thermal": 0, "kinetic": 0, "explosive": 0}
            st["repair"] = {"shield": 0, "armor": 40, "structure": 0}
            st["is_logistic"] = True
    src_d["id"] = new_id
    src_d["name"] = name
    src_d["race"] = race
    src_d["is_logistic"] = True
    src_d["is_unmanned"] = True
    src_d["weapon_fx"] = "heal"
    src_d["unmanned_kind"] = "logistic_drone"
    tags = [race, "drone", "logistic"]
    src_d["tags"] = tags
    src_d["fetter_ids"] = []
    for st in src_d.get("stars", []):
        st["is_logistic"] = True
        # armor-only repair baseline 后编
        rep = st.get("repair", {})
        if not isinstance(rep, dict):
            rep = {}
        armor = float(rep.get("armor", 0) or 0)
        if armor <= 0:
            armor = 40.0
        st["repair"] = {"shield": 0, "armor": armor, "structure": 0}
        st["damage"] = {"emp": 0.0, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0}
    (UNMANNED / out_name).write_text(
        json.dumps(src_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def patch_ore() -> None:
    for sid in (135, 136, 137, 138):
        p = SHIPS / f"{sid}.json"
        d = json.loads(p.read_text(encoding="utf-8"))
        d["faction_ship"] = True
        if sid == 138:
            d.pop("requires_cyno_entry", None)
            d["requires_cyno_entry"] = False
        p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_fetters() -> None:
    fetters = {
        "guristas": {
            "id": "guristas",
            "name": "古斯塔斯",
            "effects": [
                {
                    "champion_count": 3,
                    "effect_type": "ShieldResist",
                    "effect_value_type": "Percentage",
                    "effect_target": "SelfFetter",
                    "value": 10,
                },
                {
                    "champion_count": 3,
                    "effect_type": "ArmorResist",
                    "effect_value_type": "Percentage",
                    "effect_target": "SelfFetter",
                    "value": 10,
                },
            ],
        },
        "angel": {
            "id": "angel",
            "name": "天使",
            "effects": [
                {
                    "champion_count": 3,
                    "effect_type": "AttackSpeed",
                    "effect_value_type": "Percentage",
                    "effect_target": "SelfFetter",
                    "value": 10,
                }
            ],
        },
        "serpentis": {
            "id": "serpentis",
            "name": "天蛇",
            "effects": [
                {
                    "champion_count": 3,
                    "effect_type": "Damage",
                    "effect_value_type": "Percentage",
                    "effect_target": "SelfFetter",
                    "value": 15,
                }
            ],
        },
        "soe": {
            "id": "soe",
            "name": "姐妹会",
            "effects": [
                {
                    "champion_count": 3,
                    "effect_type": "SensorStrength",
                    "effect_value_type": "Percentage",
                    "effect_target": "SelfFetter",
                    "value": 30,
                }
            ],
        },
        "blood": {
            "id": "blood",
            "name": "血袭者",
            "effects": [
                {
                    "champion_count": 3,
                    "effect_type": "CapWarfare",
                    "effect_value_type": "Percentage",
                    "effect_target": "SelfFetter",
                    "value": 30,
                }
            ],
        },
        "mordu": {
            "id": "mordu",
            "name": "莫德团",
            "effects": [
                {
                    "champion_count": 3,
                    "effect_type": "AttackSpeed",
                    "effect_value_type": "Percentage",
                    "effect_target": "SelfFetter",
                    "value": 10,
                }
            ],
        },
        "sansha": {
            "id": "sansha",
            "name": "萨沙",
            "effects": [
                {
                    "champion_count": 3,
                    "effect_type": "ShieldHP",
                    "effect_value_type": "Percentage",
                    "effect_target": "SelfFetter",
                    "value": 5,
                }
            ],
        },
    }
    # titan faction shells (shop weight UI + ewar/cap note); combat [0] mild ShieldHP like caldari
    for race, name in [
        ("guristas", "古斯塔斯"),
        ("angel", "天使"),
        ("serpentis", "天蛇"),
        ("soe", "姐妹会"),
        ("blood", "血袭者"),
        ("mordu", "莫德团"),
        ("sansha", "萨沙"),
    ]:
        fetters[f"titan_{race}"] = {
            "id": f"titan_{race}",
            "name": f"{name}泰坦",
            "meta": True,
            "effects": [
                {
                    "champion_count": 0,
                    "effect_type": "ShieldHP",
                    "effect_value_type": "Percentage",
                    "effect_target": "SelfAll",
                    "value": 5,
                },
                {
                    "champion_count": 0,
                    "effect_type": "ShopRaceWeight",
                    "effect_value_type": "Percentage",
                    "effect_target": "SelfAll",
                    "value": 10,
                },
                {
                    "champion_count": 0,
                    "effect_type": "EwarCapWarfare",
                    "effect_value_type": "Percentage",
                    "effect_target": "SelfAll",
                    "value": 10,
                },
            ],
        }
    fdir = ROOT / "data" / "fetters"
    for fid, body in fetters.items():
        (fdir / f"{fid}.json").write_text(
            json.dumps(body, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )


def copy_icons() -> None:
    FETTER_ICONS.mkdir(parents=True, exist_ok=True)
    for fid in ("guristas", "angel", "serpentis", "soe", "blood", "mordu", "sansha"):
        src = FACTION_ICONS / f"{fid}.png"
        if src.exists():
            shutil.copy2(src, FETTER_ICONS / f"{fid}.png")


def ingest_delirium_portrait() -> None:
    PORTRAIT_DIR.mkdir(parents=True, exist_ok=True)
    src = DELIRIUM_SRC if DELIRIUM_SRC.exists() else REVIEW_PORTRAIT
    if not src.exists():
        print("WARN: no delirium portrait", src)
        return
    dst = PORTRAIT_DIR / "ss_yueshengzhe.png"
    shutil.copy2(src, dst)
    print("portrait", src, "->", dst)


def patch_portraits_json(ids_keys: list[tuple[int, str]]) -> None:
    data = json.loads(PORTRAITS_JSON.read_text(encoding="utf-8"))
    ships = data.setdefault("ships", {})
    for sid, key in ids_keys:
        ships[str(sid)] = f"res://assets/ui/portraits/{key}.png"
    PORTRAITS_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    portrait_pairs = []
    for d in SHIPS_DEF:
        ship = build_ship(d)
        path = SHIPS / f"{d['id']}.json"
        path.write_text(json.dumps(ship, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        portrait_pairs.append((d["id"], d["model_key"]))
        print("wrote", path.name, d["name"])

    delirium = build_delirium()
    (SHIPS / "822.json").write_text(
        json.dumps(delirium, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    portrait_pairs.append((822, "ss_yueshengzhe"))
    print("wrote 822.json 跃升者级")

    double_drone("caldari_light.json", 1502, "古斯塔斯轻型无人机", "guristas_light.json")
    double_drone("caldari_medium.json", 1506, "古斯塔斯中型无人机", "guristas_medium.json")
    double_drone("caldari_heavy.json", 1512, "古斯塔斯重型无人机", "guristas_heavy.json")
    print("wrote guristas drones 1502/1506/1512")

    # Nestor logistic drones 后编 1421-1424 (armor-only)
    clone_logistic_drone("amarr_light.json", 1421, "艾玛后勤轻无人", "nestor_amarr_logistic.json", "amarr")
    clone_logistic_drone("caldari_light.json", 1422, "加达里后勤轻无人", "nestor_caldari_logistic.json", "caldari")
    clone_logistic_drone("gallente_light.json", 1423, "加勒后勤轻无人", "nestor_gallente_logistic.json", "gallente")
    clone_logistic_drone("minmatar_light.json", 1424, "米玛塔尔后勤轻无人", "nestor_minmatar_logistic.json", "minmatar")
    print("wrote nestor logistics 1421-1424")

    patch_ore()
    print("patched ORE 135-138")

    write_fetters()
    print("wrote 7+titan fetters")

    copy_icons()
    ingest_delirium_portrait()
    patch_portraits_json(portrait_pairs)
    print("done")


if __name__ == "__main__":
    main()
