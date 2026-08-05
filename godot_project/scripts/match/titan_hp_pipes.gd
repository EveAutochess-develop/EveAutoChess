extends RefCounted
class_name TitanHpPipes
## Three-pipe titan HP from balance/titan_pvp.json (MULTIPLAYER_PVP §2.4).
## No C/A max quirks; no M/G first-hit reduction.

var race: String = "caldari"
var shield: int = 100
var armor: int = 100
var structure: int = 100
var shield_max: int = 100
var armor_max: int = 100
var structure_max: int = 100
## Lowsec room: 0.25. Nullsec / default: 1.0.
var pvp_loss_mul: float = 1.0

static func _cfg() -> Dictionary:
	if DataStore and typeof(DataStore.get("titan_pvp")) == TYPE_DICTIONARY:
		return TypedVariant.as_dict(DataStore.titan_pvp)
	return {}

func setup(p_race: String) -> void:
	race = p_race
	var cfg: Dictionary = _cfg()
	shield_max = TypedVariant.as_int(cfg.get("pipe_shield_max", 100), 100)
	armor_max = TypedVariant.as_int(cfg.get("pipe_armor_max", 100), 100)
	structure_max = TypedVariant.as_int(cfg.get("pipe_structure_max", 100), 100)
	shield = shield_max
	armor = armor_max
	structure = structure_max

func alive() -> bool:
	return structure > 0

func _scaled_pvp_dmg(base: int) -> int:
	return maxi(1, roundi(float(base) * pvp_loss_mul))

func apply_pvp_loss() -> int:
	var cfg: Dictionary = _cfg()
	var base: int = TypedVariant.as_int(cfg.get("pvp_loss_damage", 20), 20)
	return _apply_pipes(_scaled_pvp_dmg(base))

func _apply_pipes(dmg: int) -> int:
	var remaining: int = dmg
	var applied: int = 0
	if remaining > 0 and shield > 0:
		var take: int = mini(remaining, shield)
		shield -= take
		remaining -= take
		applied += take
	if remaining > 0 and armor > 0:
		var take2: int = mini(remaining, armor)
		armor -= take2
		remaining -= take2
		applied += take2
	if remaining > 0 and structure > 0:
		var take3: int = mini(remaining, structure)
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
	}
