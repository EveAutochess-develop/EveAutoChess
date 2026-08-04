#!/usr/bin/env python3
"""Generate data/equipment/function_modules.json (EQUIPMENT.md)."""
from __future__ import annotations

import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "godot_project" / "data" / "equipment" / "function_modules.json"


def entry(**kw):
	d = {
		"shop_pool": True,
		"size": "S",
		"cost": 10,
		"passive": True,
		"effects": [],
		"blurb": "",
		"blurb_holes": {},
		"synth_next": None,
		"synth_from": None,
		"synth_into": [],
		"icon": "",
		"weapon_gate": None,
		"targeting": "none",
		"range_cells": 0.0,
		"duration_s": 0.0,
		"capacitor_need": 0.0,
		"implant": False,
	}
	d.update(kw)
	order = ["S", "M", "L", "XL"]
	si = order.index(d["size"])
	d["allowed_on"] = order[si:]
	return d


items: dict = {}


def E(id_: str, **kw):
	kw.setdefault("id", id_)
	items[id_] = entry(**kw)


def main() -> None:
	E(
		"coating_ms",
		name="全抗装甲涂层",
		typeID=1304,
		size="S",
		cost=10,
		icon="res://assets/ui/item_icons/1304.png",
		effects=[{"op": "add_resist", "layer": "armor", "amount": 11.68}],
		blurb="被动：装甲电热动爆抗性各 +{amount}。",
		blurb_holes={"amount": 11.68},
	)
	E(
		"membrane_ms",
		name="全抗充能膜",
		typeID=11267,
		size="S",
		cost=10,
		icon="res://assets/ui/item_icons/11267.png",
		effects=[{"op": "add_resist", "layer": "armor", "amount": 15}],
		blurb="被动：装甲电热动爆抗性各 +{amount}。",
		blurb_holes={"amount": 15},
	)
	E(
		"hardener_ms",
		name="全抗盾硬化",
		typeID=578,
		size="S",
		cost=10,
		passive=False,
		duration_s=10,
		capacitor_need=40,
		icon="res://assets/ui/item_icons/578.png",
		effects=[{"op": "add_resist_active", "layer": "shield", "amount": 25}],
		blurb="激活 {duration_s}s（耗电 {capacitor_need}）：护盾电热动爆抗性各 +{amount}。",
		blurb_holes={"duration_s": 10, "capacitor_need": 40, "amount": 25},
		activate="on_need",
	)
	E(
		"bulkheads",
		name="结构加强",
		typeID=1333,
		size="S",
		cost=10,
		icon="res://assets/ui/item_icons/1333.png",
		effects=[{"op": "mul_stat", "stat": "structure_hp", "mul": 1.15}],
		blurb="被动：结构 HP ×{mul}。",
		blurb_holes={"mul": 1.15},
	)
	E(
		"damage_control",
		name="损伤控制",
		typeID=2046,
		size="S",
		cost=10,
		passive=False,
		duration_s=15,
		cooldown_s=240,
		icon="res://assets/ui/item_icons/2046.png",
		effects=[{"op": "add_resist_active", "layer": "all", "amount": 90}],
		blurb="首次承伤后激活：{duration_s}s 内盾/甲/结构电热动爆抗性各 +{amount}；冷却 {cooldown_s}s。",
		blurb_holes={"duration_s": 15, "amount": 90, "cooldown_s": 240},
		activate="first_damage",
	)

	reps = [
		("armor_repairer", "装甲维修器", [523, 3528, 3538, 20701], [6, 12, 15, 30], [40, 160, 400, 2400], [69, 276, 690, 9600], "armor"),
		("shield_booster", "护盾回充", [399, 10836, 10838, 20703], [2, 3, 4, 10], [20, 60, 160, 2400], [26, 78, 207, 7200], "shield"),
		("hull_repairer", "结构维修", [524, 3653, 3663, 41511], [30, 30, 30, 60], [30, 60, 120, 720], [25, 50, 100, 1800], "structure"),
	]
	for line, name, tids, cds, caps, amts, layer in reps:
		for i, sz in enumerate(["S", "M", "L", "XL"]):
			eid = f"{line}_{sz.lower()}"
			nxt = f"{line}_{['s', 'm', 'l', 'xl'][i + 1]}" if i < 3 else None
			E(
				eid,
				name=name,
				typeID=tids[i],
				size=sz,
				cost=[1, 4, 9, 19][i],
				passive=False,
				duration_s=cds[i],
				capacitor_need=caps[i],
				line=line,
				synth_next=nxt,
				icon=f"res://assets/ui/item_icons/{tids[i]}.png",
				effects=[{"op": "repair", "layer": layer, "amount": amts[i]}],
				blurb=f"周期 {{duration_s}}s（耗电 {{capacitor_need}}）：回复{layer} {{amount}}。",
				blurb_holes={"duration_s": cds[i], "capacitor_need": caps[i], "amount": amts[i]},
				activate="periodic",
			)

	for tid, sz, cost, bonus in [(377, "S", 1, 400), (3829, "M", 4, 800), (3839, "L", 9, 1600), (40354, "XL", 19, 50000)]:
		i = ["S", "M", "L", "XL"].index(sz)
		nxt = f"shield_extender_{['s', 'm', 'l', 'xl'][i + 1]}" if i < 3 else None
		E(
			f"shield_extender_{sz.lower()}",
			name="护盾扩展",
			typeID=tid,
			size=sz,
			cost=cost,
			line="shield_extender",
			synth_next=nxt,
			icon=f"res://assets/ui/item_icons/{tid}.png",
			effects=[{"op": "add_stat", "stat": "shield_hp", "amount": bonus}],
			blurb="被动：护盾 HP +{amount}。",
			blurb_holes={"amount": bonus},
		)

	for (tid, sz, cost), hp in zip(
		[(11293, "S", 1), (11297, "M", 4), (11279, "L", 9), (40348, "XL", 19)],
		[300, 1000, 3000, 50000],
	):
		i = ["S", "M", "L", "XL"].index(sz)
		nxt = f"steel_plates_{['s', 'm', 'l', 'xl'][i + 1]}" if i < 3 else None
		E(
			f"steel_plates_{sz.lower()}",
			name="钢板",
			typeID=tid,
			size=sz,
			cost=cost,
			line="steel_plates",
			synth_next=nxt,
			icon=f"res://assets/ui/item_icons/{tid}.png",
			effects=[{"op": "add_stat", "stat": "armor_hp", "amount": hp}],
			blurb="被动：装甲 HP +{amount}。",
			blurb_holes={"amount": hp},
		)

	for tid, sz, cost, bonus in [(1185, "S", 1, 120), (2018, "M", 4, 300), (2020, "L", 9, 800), (41484, "XL", 19, 50000)]:
		i = ["S", "M", "L", "XL"].index(sz)
		nxt = f"cap_battery_{['s', 'm', 'l', 'xl'][i + 1]}" if i < 3 else None
		E(
			f"cap_battery_{sz.lower()}",
			name="电容电池",
			typeID=tid,
			size=sz,
			cost=cost,
			line="cap_battery",
			synth_next=nxt,
			icon=f"res://assets/ui/item_icons/{tid}.png",
			effects=[{"op": "add_stat", "stat": "capacitor_capacity", "amount": bonus}],
			blurb="被动：电容量 +{amount}。",
			blurb_holes={"amount": bonus},
		)

	E(
		"tracking_enhancer",
		name="索敌增强器",
		typeID=1998,
		size="S",
		cost=10,
		icon="res://assets/ui/item_icons/1998.png",
		effects=[
			{"op": "mul_stat", "stat": "optimal", "mul": 1.0725},
			{"op": "mul_stat", "stat": "falloff", "mul": 1.145},
			{"op": "mul_stat", "stat": "tracking", "mul": 1.07},
		],
		blurb="被动：optimal +{opt}% · falloff +{fo}% · tracking +{tr}%。",
		blurb_holes={"opt": 7.25, "fo": 14.5, "tr": 7},
	)
	E(
		"tracking_computer",
		name="索敌计算机",
		typeID=1977,
		size="S",
		cost=10,
		passive=False,
		duration_s=10,
		capacitor_need=7,
		icon="res://assets/ui/item_icons/1977.png",
		effects=[
			{"op": "mul_stat_active", "stat": "optimal", "mul": 1.05},
			{"op": "mul_stat_active", "stat": "falloff", "mul": 1.10},
			{"op": "mul_stat_active", "stat": "tracking", "mul": 1.10},
		],
		blurb="激活 {duration_s}s（耗电 {capacitor_need}）：optimal +{opt}% · falloff +{fo}% · tracking +{tr}%。",
		blurb_holes={"duration_s": 10, "capacitor_need": 7, "opt": 5, "fo": 10, "tr": 10},
		activate="periodic",
	)
	E(
		"tracking_disruptor",
		name="索敌扰断器",
		typeID=2108,
		size="S",
		cost=10,
		passive=False,
		range_cells=20,
		duration_s=10,
		capacitor_need=15,
		targeting="enemy",
		icon="res://assets/ui/item_icons/2108.png",
		effects=[
			{"op": "debuff_mul", "stat": "optimal", "mul": 0.847},
			{"op": "debuff_mul", "stat": "falloff", "mul": 0.847},
			{"op": "debuff_mul", "stat": "tracking", "mul": 0.847},
		],
		blurb="敌对 · {range_cells} 格 · {duration_s}s：敌方 optimal/falloff/tracking 各 −{pct}%。",
		blurb_holes={"range_cells": 20, "duration_s": 10, "pct": 15.3},
		activate="periodic",
	)
	E(
		"guidance_disruptor",
		name="制导干扰器",
		typeID=37543,
		size="S",
		cost=10,
		passive=False,
		range_cells=20,
		duration_s=10,
		capacitor_need=15,
		targeting="enemy",
		icon="res://assets/ui/item_icons/37543.png",
		effects=[
			{"op": "debuff_mul", "stat": "explosion_velocity", "mul": 0.92},
			{"op": "debuff_mul", "stat": "explosion_radius", "mul": 1.10},
		],
		blurb="敌对 · {range_cells} 格：削弱敌方导弹爆炸速度/半径。",
		blurb_holes={"range_cells": 20},
		activate="periodic",
	)
	E(
		"target_painter",
		name="目标标记",
		typeID=12709,
		size="S",
		cost=10,
		passive=False,
		range_cells=15,
		duration_s=5,
		capacitor_need=10,
		targeting="enemy",
		icon="res://assets/ui/item_icons/12709.png",
		effects=[{"op": "debuff_mul", "stat": "signature_radius", "mul": 1.25}],
		blurb="敌对 · {range_cells} 格：敌方信源半径 +{pct}%。",
		blurb_holes={"range_cells": 15, "pct": 25},
		activate="periodic",
	)
	E(
		"stasis_webifier",
		name="停滞缠绕",
		typeID=526,
		size="S",
		cost=10,
		passive=False,
		range_cells=8,
		duration_s=5,
		capacitor_need=5,
		targeting="enemy",
		no_falloff=True,
		icon="res://assets/ui/item_icons/526.png",
		effects=[{"op": "debuff_mul", "stat": "speed", "mul": 0.5}],
		blurb="敌对 · {range_cells} 格（无衰减）：敌方速度 −{pct}%。",
		blurb_holes={"range_cells": 8, "pct": 50},
		activate="periodic",
	)
	E(
		"stasis_grappler",
		name="重型停滞捕捉",
		typeID=41040,
		size="XL",
		cost=19,
		passive=False,
		range_cells=3,
		duration_s=2,
		capacitor_need=4,
		targeting="enemy",
		no_falloff=True,
		icon="res://assets/ui/item_icons/41040.png",
		effects=[{"op": "debuff_mul", "stat": "speed", "mul": 0.2}],
		blurb="敌对 · {range_cells} 格（无衰减）· 仅旗舰：敌方速度 −{pct}%。",
		blurb_holes={"range_cells": 3, "pct": 80},
		activate="periodic",
	)
	E(
		"sensor_booster",
		name="感应增强器",
		typeID=1973,
		size="S",
		cost=10,
		passive=False,
		duration_s=10,
		capacitor_need=10,
		icon="res://assets/ui/item_icons/1973.png",
		effects=[
			{"op": "mul_stat_active", "stat": "scan_resolution", "mul": 1.25},
			{"op": "mul_stat_active", "stat": "sensor_strength", "mul": 1.40},
		],
		blurb="激活 {duration_s}s：扫描分辨率 +{scan}% · 感应强度 +{sens}%。",
		blurb_holes={"duration_s": 10, "scan": 25, "sens": 40},
		activate="periodic",
	)
	E(
		"sensor_dampener",
		name="远程感应抑阻",
		typeID=1968,
		size="S",
		cost=10,
		passive=False,
		range_cells=12.5,
		duration_s=10,
		capacitor_need=30,
		targeting="enemy",
		icon="res://assets/ui/item_icons/1968.png",
		effects=[
			{"op": "debuff_mul", "stat": "scan_resolution", "mul": 0.863},
			{"op": "debuff_mul", "stat": "sensor_strength", "mul": 0.863},
		],
		blurb="敌对 · {range_cells} 格：敌方扫描/感应 −{pct}%。",
		blurb_holes={"range_cells": 12.5, "pct": 13.7},
		activate="periodic",
	)

	for tid, sz, cost, dur, cap, fac in [
		(439, "S", 1, 10, 20, 2.15),
		(12056, "M", 4, 10, 80, 2.15),
		(12066, "L", 9, 10, 320, 2.15),
		(41236, "XL", 19, 20, 8000, 2.15),
	]:
		i = ["S", "M", "L", "XL"].index(sz)
		nxt = f"afterburner_{['s', 'm', 'l', 'xl'][i + 1]}" if i < 3 else None
		E(
			f"afterburner_{sz.lower()}",
			name="加力燃烧器",
			typeID=tid,
			size=sz,
			cost=cost,
			passive=False,
			duration_s=dur,
			capacitor_need=cap,
			line="afterburner",
			synth_next=nxt,
			icon=f"res://assets/ui/item_icons/{tid}.png",
			effects=[{"op": "mul_stat_active", "stat": "speed", "mul": fac}],
			blurb="激活 {duration_s}s（耗电 {capacitor_need}）：速度 ×{mul}（可多装线性叠）。",
			blurb_holes={"duration_s": dur, "capacitor_need": cap, "mul": fac},
			activate="periodic",
		)

	for eid, name, tid, gate in [
		("heat_sink", "散热槽", 2363, "laser"),
		("gyro_stabilizer", "回转稳定器", 520, "cannon"),
		("mfs", "磁性力场稳定器", 9944, "rail"),
		("bcs", "弹道控制系统", 12274, "missile"),
	]:
		E(
			eid,
			name=name,
			typeID=tid,
			size="S",
			cost=10,
			weapon_gate=gate,
			icon=f"res://assets/ui/item_icons/{tid}.png",
			effects=[
				{"op": "mul_damage_gate", "mul": 1.07},
				{"op": "mul_stat", "stat": "attack_cycle_s", "mul": 0.92},
			],
			blurb="限 {weapon_gate}：伤害 ×{dmg} · 攻击周期 ×{cycle}。",
			blurb_holes={"weapon_gate": gate, "dmg": 1.07, "cycle": 0.92},
		)

	E(
		"missile_guidance_enhancer",
		name="导弹制导增强器",
		typeID=35770,
		size="S",
		cost=10,
		weapon_gate="missile",
		icon="res://assets/ui/item_icons/35770.png",
		effects=[
			{"op": "mul_stat", "stat": "explosion_velocity", "mul": 1.044},
			{"op": "mul_stat", "stat": "explosion_radius", "mul": 0.956},
		],
		blurb="导弹：爆炸速度 +{ev}% · 爆炸半径 −{er}%。",
		blurb_holes={"ev": 4.4, "er": 4.4},
	)
	E(
		"missile_guidance_computer",
		name="导弹制导计算机",
		typeID=35788,
		size="S",
		cost=10,
		weapon_gate="missile",
		passive=False,
		duration_s=10,
		capacitor_need=7,
		icon="res://assets/ui/item_icons/35788.png",
		effects=[
			{"op": "mul_stat_active", "stat": "explosion_velocity", "mul": 1.055},
			{"op": "mul_stat_active", "stat": "explosion_radius", "mul": 0.945},
		],
		blurb="激活 {duration_s}s：爆炸速度 +{ev}% · 爆炸半径 −{er}%。",
		blurb_holes={"duration_s": 10, "ev": 5.5, "er": 5.5},
		activate="periodic",
	)
	E(
		"omnidir_tracking",
		name="全方位索敌增强器",
		typeID=33822,
		size="S",
		cost=10,
		icon="res://assets/ui/item_icons/33822.png",
		effects=[{"op": "buff_drones", "stats": {"optimal": 1.1, "falloff": 1.1, "tracking": 1.1}}],
		blurb="无人机/舰载机：optimal/falloff/tracking 被动加成。",
		blurb_holes={},
	)
	E(
		"drone_nav",
		name="无人机导航电脑",
		typeID=24395,
		size="S",
		cost=10,
		icon="res://assets/ui/item_icons/24395.png",
		effects=[{"op": "buff_drones", "stats": {"speed": 1.25}}],
		blurb="无人机/舰载机速度 +{pct}%。",
		blurb_holes={"pct": 25},
	)
	E(
		"drone_damage_amp",
		name="无人机伤害增效",
		typeID=4393,
		size="S",
		cost=10,
		icon="res://assets/ui/item_icons/4393.png",
		effects=[{"op": "buff_drones", "stats": {"damage": 1.15}}],
		blurb="无人机/舰载机伤害 ×{mul}。",
		blurb_holes={"mul": 1.15},
	)

	for tid, sz, cost, rng, cd, cap, amt in [
		(530, "S", 1, 2, 2.5, 0, 8),
		(12257, "M", 4, 4, 5, 0, 30),
		(12261, "L", 9, 8, 10, 0, 100),
		(40665, "XL", 19, 15, 20, 0, 700),
	]:
		i = ["S", "M", "L", "XL"].index(sz)
		nxt = f"nos_{['s', 'm', 'l', 'xl'][i + 1]}" if i < 3 else None
		E(
			f"nos_{sz.lower()}",
			name="能量吸取",
			typeID=tid,
			size=sz,
			cost=cost,
			passive=False,
			range_cells=rng,
			duration_s=cd,
			capacitor_need=cap,
			targeting="enemy",
			line="nos",
			synth_next=nxt,
			icon=f"res://assets/ui/item_icons/{tid}.png",
			effects=[{"op": "nos", "amount": amt}],
			blurb="敌对 · {range_cells} 格 · 每 {duration_s}s：抽敌电容 {amount} 并回己。",
			blurb_holes={"range_cells": rng, "duration_s": cd, "amount": amt},
			activate="periodic",
		)

	for tid, sz, cost, rng, cd, cap, amt in [
		(533, "S", 1, 2, 6, 45, 45),
		(12265, "M", 4, 4, 12, 150, 150),
		(12269, "L", 9, 8, 24, 500, 500),
		(40659, "XL", 19, 15, 48, 3600, 3600),
	]:
		i = ["S", "M", "L", "XL"].index(sz)
		nxt = f"neut_{['s', 'm', 'l', 'xl'][i + 1]}" if i < 3 else None
		E(
			f"neut_{sz.lower()}",
			name="能量中和",
			typeID=tid,
			size=sz,
			cost=cost,
			passive=False,
			range_cells=rng,
			duration_s=cd,
			capacitor_need=cap,
			targeting="enemy",
			line="neut",
			synth_next=nxt,
			icon=f"res://assets/ui/item_icons/{tid}.png",
			effects=[{"op": "neut", "amount": amt}],
			blurb="敌对 · {range_cells} 格 · 每 {duration_s}s（耗电 {capacitor_need}）：敌电容 −{amount}。",
			blurb_holes={"range_cells": rng, "duration_s": cd, "capacitor_need": cap, "amount": amt},
			activate="periodic",
		)

	for tid, sz, cost, rng, cd, cap, amt in [
		(529, "S", 1, 2, 5, 38, 30),
		(12217, "M", 4, 3, 5, 113, 90),
		(12225, "L", 9, 4, 5, 338, 270),
		(12219, "XL", 19, 8, 20, 2500, 1000),
	]:
		i = ["S", "M", "L", "XL"].index(sz)
		nxt = f"remote_cap_{['s', 'm', 'l', 'xl'][i + 1]}" if i < 3 else None
		E(
			f"remote_cap_{sz.lower()}",
			name="远程电容传输",
			typeID=tid,
			size=sz,
			cost=cost,
			passive=False,
			range_cells=rng,
			duration_s=cd,
			capacitor_need=cap,
			targeting="ally_cap",
			line="remote_cap",
			synth_next=nxt,
			icon=f"res://assets/ui/item_icons/{tid}.png",
			effects=[{"op": "remote_cap", "amount": amt}],
			blurb="友军残容优先 · {range_cells} 格 · 每 {duration_s}s：灌容 {amount}（耗电 {capacitor_need}）。",
			blurb_holes={"range_cells": rng, "duration_s": cd, "amount": amt, "capacitor_need": cap},
			activate="periodic",
		)

	implants = [
		(
			"implant_focus_crystal",
			"聚焦晶体",
			"16000000001",
			"jujiaojinti",
			["shield_extender_l", "heat_sink"],
			"laser",
			"激光命中叠层：每层伤害 +{stack_pct}% ，上限 {cap_pct}%。未命中耗层回盾（等百分比），回盾冷却 {shield_cd}s。",
			{"stack_pct": 1, "cap_pct": 20, "shield_cd": 20},
			[{"op": "implant_focus_crystal", "stack_pct": 1, "cap_pct": 20, "shield_cd": 20}],
		),
		(
			"implant_pulse_crystal",
			"脉冲晶体",
			"16001000001",
			"maichongjinti",
			["heat_sink", "cap_battery_l"],
			"laser",
			"增伤态：激光伤害 +{dmg_pct}% ，每次耗容 {cap_cost_pct}%。电容 ≤{low_pct}% 时改每 {swap_s}s 用 {shield_pct}% 盾换 {gain_pct}% 容；电容 ≥{high_pct}% 恢复增伤。",
			{"dmg_pct": 15, "cap_cost_pct": 5, "low_pct": 50, "swap_s": 10, "shield_pct": 10, "gain_pct": 15, "high_pct": 90},
			[{"op": "implant_pulse_crystal", "dmg_pct": 15, "cap_cost_pct": 5, "low_pct": 50, "swap_s": 10, "shield_pct": 10, "gain_pct": 15, "high_pct": 90}],
		),
		(
			"implant_barrage",
			"弹幕压制",
			"16002000001",
			"danmuyazhi",
			["afterburner_l", "gyro_stabilizer"],
			"cannon",
			"加农射速 +{rof_pct}% ；舰船速度 +{spd_pct}%。",
			{"rof_pct": 10, "spd_pct": 10},
			[
				{"op": "mul_stat", "stat": "attack_cycle_s", "mul": 0.909},
				{"op": "mul_stat", "stat": "speed", "mul": 1.10},
			],
		),
		(
			"implant_he_coil",
			"高能线圈",
			"16003000001",
			"gaonengxianquan",
			["mfs", "stasis_grappler"],
			"rail",
			"磁轨结算无视 {pen_pct}% 抗性；被命中目标速度 −{spd_pct}%。",
			{"pen_pct": 15, "spd_pct": 10},
			[{"op": "implant_he_coil", "pen_pct": 15, "spd_pct": 10}],
		),
		(
			"implant_thermal_cycle",
			"热能循环",
			"16004000001",
			"renengxunhuang",
			["mfs", "coating_ms"],
			"rail",
			"隔轮：奇数轮磁轨伤害 +{dmg_pct}% ；偶数轮持续期内装甲四属抗性 +{res_pct}%。",
			{"dmg_pct": 15, "res_pct": 15},
			[{"op": "implant_thermal_cycle", "dmg_pct": 15, "res_pct": 15}],
		),
		(
			"implant_sniper",
			"狙击技术",
			"16005000001",
			"jujizhanshu",
			["gyro_stabilizer", "tracking_computer"],
			"cannon",
			"常态加农伤害 −100%。每 {n} 次攻击有 1 次：伤害 ×{mul} 且无视跟踪必中。",
			{"n": 10, "mul": 10},
			[{"op": "implant_sniper", "every": 10, "mul": 10}],
		),
		(
			"implant_support_proj",
			"支援投射",
			"16006000001",
			"zhiyuantoushe",
			["neut_s", "missile_guidance_computer"],
			"missile",
			"导弹命中 {strip_pct}% 概率打落 1 件装备回对方背包（满则不打落）；命中毁电 {neut_pct}%。",
			{"strip_pct": 5, "neut_pct": 1},
			[{"op": "implant_support_proj", "strip_pct": 5, "neut_pct": 1}],
		),
		(
			"implant_warhead",
			"弹头装药",
			"16007000001",
			"dangtouzhuangyao",
			["missile_guidance_enhancer", "missile_guidance_computer"],
			"missile",
			"有盾→纯电磁；有甲无盾→纯爆炸；打结构→四属均伤。",
			{},
			[{"op": "implant_warhead"}],
		),
		(
			"implant_bombing",
			"轰炸战术",
			"16008000001",
			"hongzhazhanshu",
			["drone_damage_amp", "drone_nav"],
			"drone",
			"无人机速度 +{spd_pct}%。首次放出：前 {hits} 次攻击伤害 ×2；{window_s}s 内速度再 ×2。",
			{"spd_pct": 20, "hits": 5, "window_s": 20},
			[{"op": "implant_bombing", "spd_pct": 20, "hits": 5, "window_s": 20}],
		),
		(
			"implant_shield_support",
			"护盾支援",
			"16009000001",
			"hudunzhiyuan",
			["remote_cap_l", "shield_booster_l"],
			"heal",
			"远程盾修每 {n} 轮有 1 轮回复 ×{mul}（后勤航/后勤无人机）。",
			{"n": 3, "mul": 2},
			[{"op": "implant_shield_support", "every": 3, "mul": 2}],
		),
		(
			"implant_armor_support",
			"装甲支援",
			"16010000001",
			"zhuangjiazhiyuan",
			["armor_repairer_l", "coating_ms"],
			"heal",
			"维修时目标装甲抗性 +{res_pct}% ；后勤航平分无人机；同目标不叠。",
			{"res_pct": 10},
			[{"op": "implant_armor_support", "res_pct": 10}],
		),
		(
			"implant_auto_def",
			"自动防御",
			"16011000001",
			"zidongfangyu",
			["sensor_dampener", "drone_nav"],
			"drone",
			"无人机前 {rounds} 轮：每轮 {chance}% 清锁定；tracking 与爆炸速度 +{pct}%。",
			{"rounds": 5, "chance": 50, "pct": 40},
			[{"op": "implant_auto_def", "rounds": 5, "chance": 50, "pct": 40}],
		),
	]
	## Icons: user-confirmed Echoes `implant/1600x000001` grayscale (chat assets).
	## typeID↔name is NOT the same order as EQUIPMENT.md §7 table rows.
	for eid, name, icon_id, pinyin, mats, gate, blurb, holes, effs in implants:
		E(
			eid,
			name=name,
			typeID=int(icon_id),
			size="S",
			cost=0,
			shop_pool=False,
			implant=True,
			weapon_gate=gate,
			synth_from=mats,
			icon=f"res://assets/ui/sprites/equipment_implants/{eid}.png",
			effects=effs,
			blurb=blurb,
			blurb_holes=holes,
		)

	for _iid, it in items.items():
		mats = it.get("synth_from")
		if not mats:
			continue
		for mid in mats:
			if mid in items:
				t = items[mid].setdefault("synth_into", [])
				if it["name"] not in t:
					t.append(it["name"])

	doc = {"_meta": {"doc": "EQUIPMENT.md", "note": "function bucket; no batch markers"}, "items": items}
	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
	print("wrote", OUT, "count", len(items))


if __name__ == "__main__":
	main()
