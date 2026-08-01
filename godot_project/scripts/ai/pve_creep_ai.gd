extends RefCounted
class_name PveCreepAi
## Lock roster at previous round end; budget = gold snapshot; slide-in cells.

var match_rng: MatchRng
var battle_serial: int = 0
var locked_roster: Array = [] ## [{ship_id, cell}]
var locked: bool = false

func setup(rng: MatchRng, serial: int) -> void:
	match_rng = rng
	battle_serial = serial

func lock_from_player_state(gold: int, level: int, population_limit: int) -> Array:
	locked_roster.clear()
	var cap := int(floorf(float(population_limit) * 1.5))
	var budget := maxi(0, gold)
	var pool: Array = _sleeper_pool_for_level(level)
	if pool.is_empty():
		locked = true
		return locked_roster
	var spent := 0
	var guard := 0
	while spent < budget and locked_roster.size() < cap and guard < 64:
		guard += 1
		var idx := 0
		if match_rng:
			idx = match_rng.pick_index(battle_serial, "creep_buy", pool.size())
		else:
			idx = randi() % pool.size()
		var sid := int(pool[idx])
		var cost := int(DataStore.get_ship(sid).get("cost", 1))
		if cost <= 0:
			cost = 1
		if spent + cost > budget and locked_roster.size() > 0:
			break
		spent += cost
		var cell := 0
		if match_rng:
			cell = match_rng.roll_int(battle_serial, "creep_cell", 0, 31)
		locked_roster.append({"ship_id": sid, "cell": cell})
	locked = true
	return locked_roster.duplicate(true)

func _sleeper_pool_for_level(level: int) -> Array:
	var out: Array = []
	for sid in DataStore.ship_ids():
		var ship: Dictionary = DataStore.get_ship(int(sid))
		var tags: Array = ship.get("tags", []) as Array
		var is_sleeper := false
		for t in tags:
			if str(t) == "sleeper" or str(t) == "pve_creep":
				is_sleeper = true
				break
		if not is_sleeper:
			continue
		var group := str(ship.get("ship_group", "frigate"))
		var unlocks: Dictionary = DataStore.economy.get("shop_unlock_level_by_group", {})
		var need := int(unlocks.get(group, 1))
		if level >= need:
			out.append(int(sid))
	return out
