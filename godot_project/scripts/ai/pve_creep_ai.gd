extends RefCounted
class_name PveCreepAi
## Lock roster at Prepare→Battle: budget = floor(gold/2) + field ship cost (MATCH_FLOW §5.1.2).

var match_rng: MatchRng
var battle_serial: int = 0
var locked_roster: Array = [] ## [{ship_id, cell}]
var locked: bool = false

func setup(rng: MatchRng, serial: int) -> void:
	match_rng = rng
	battle_serial = serial

func lock_from_player_state(
	gold: int, level: int, population_limit: int, field_value: int = 0
) -> Array:
	locked_roster.clear()
	var cap: int = floori(float(population_limit) * 1.5)
	## §5.1.2: B_creep = floor(B/2) + V_field (field manned cost; hangar excluded).
	var budget: int = maxi(0, floori(float(gold) * 0.5)) + maxi(0, field_value)
	var pool: Array = _sleeper_pool_for_level(level)
	if pool.is_empty():
		locked = true
		return locked_roster
	var spent: int = 0
	var guard: int = 0
	while spent < budget and locked_roster.size() < cap and guard < 64:
		guard += 1
		var idx: int = 0
		if match_rng:
			idx = match_rng.pick_index(battle_serial, "creep_buy", pool.size())
		else:
			idx = randi() % pool.size()
		var sid: int = TypedVariant.as_int(pool[idx], 0)
		var ship_data: Dictionary = DataStore.get_ship(sid)
		var cost: int = TypedVariant.as_int(ship_data.get("cost", 1), 1)
		if cost <= 0:
			cost = 1
		## MULTIPLAYER_MATCH_FLOW §5.1.2 — mining hulls cost half for creep budget only.
		if TypedVariant.as_bool(ship_data.get("is_mining_ship", false), false):
			cost = maxi(1, ceili(float(cost) * 0.5))
		if spent + cost > budget and locked_roster.size() > 0:
			break
		spent += cost
		var cell: int = 0
		if match_rng:
			cell = match_rng.roll_int(battle_serial, "creep_cell", 0, 31)
		locked_roster.append({"ship_id": sid, "cell": cell})
	locked = true
	return locked_roster.duplicate(true)

func _sleeper_pool_for_level(level: int) -> Array:
	var out: Array = []
	for sid_v: Variant in DataStore.ship_ids():
		var sid: int = TypedVariant.as_int(sid_v, 0)
		var ship: Dictionary = DataStore.get_ship(sid)
		var tags: Array = TypedVariant.as_array(ship.get("tags", []))
		var is_sleeper: bool = false
		for t_v: Variant in tags:
			var t: String = str(t_v)
			if t == "sleeper" or t == "pve_creep":
				is_sleeper = true
				break
		if not is_sleeper:
			continue
		var group: String = str(ship.get("ship_group", "frigate"))
		var unlocks: Dictionary = TypedVariant.as_dict(DataStore.economy.get("shop_unlock_level_by_group", {}))
		var need: int = TypedVariant.as_int(unlocks.get(group, 1), 1)
		if level >= need:
			out.append(sid)
	return out
