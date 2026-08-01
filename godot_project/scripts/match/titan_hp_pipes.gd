extends RefCounted
class_name TitanHpPipes
## Three-pipe titan HP + racial quirks. PVP loss = 20 (with M/G first-hit rules).

var race: String = "caldari"
var shield: int = 100
var armor: int = 100
var structure: int = 100
var shield_max: int = 100
var armor_max: int = 100
var structure_max: int = 100
var flag_first_hp_hit: bool = false
var flag_first_armor_hit: bool = false

func setup(p_race: String) -> void:
	race = p_race
	shield_max = 105 if race == "caldari" else 100
	armor_max = 105 if race == "amarr" else 100
	structure_max = 100
	shield = shield_max
	armor = armor_max
	structure = structure_max
	flag_first_hp_hit = false
	flag_first_armor_hit = false

func alive() -> bool:
	return structure > 0

func apply_pvp_loss() -> int:
	## Returns damage applied (for VFX). Always doomsday presentation externally.
	var dmg := 20
	if race == "minmatar" and not flag_first_hp_hit:
		dmg = 5
		flag_first_hp_hit = true
		var take := mini(dmg, shield)
		shield -= take
		return take
	return _apply_pipes(dmg)

func _apply_pipes(dmg: int) -> int:
	var remaining := dmg
	var applied := 0
	if remaining > 0 and shield > 0:
		var take := mini(remaining, shield)
		shield -= take
		remaining -= take
		applied += take
		flag_first_hp_hit = true
	if remaining > 0 and armor > 0:
		var chunk := remaining
		if race == "gallente" and not flag_first_armor_hit:
			chunk = 5
			flag_first_armor_hit = true
		var take2 := mini(chunk, armor)
		armor -= take2
		remaining -= take2
		applied += take2
		## If gallente first armor absorbed only 5 of a larger hit, rest continues
		if race == "gallente" and chunk == 5 and remaining > 0:
			pass
	if remaining > 0 and structure > 0:
		var take3 := mini(remaining, structure)
		structure -= take3
		applied += take3
	return applied

func to_dict() -> Dictionary:
	return {
		"race": race,
		"shield": shield,
		"armor": armor,
		"structure": structure,
		"shield_max": shield_max,
		"armor_max": armor_max,
		"structure_max": structure_max,
		"flag_first_hp_hit": flag_first_hp_hit,
		"flag_first_armor_hit": flag_first_armor_hit,
	}
