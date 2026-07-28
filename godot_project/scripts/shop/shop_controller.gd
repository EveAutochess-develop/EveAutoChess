extends Node
class_name ShopController

signal shop_changed()

var slots: Array = []  # Array of {ship_id:int, purchased:bool} size from economy
var _match: MatchController
var _board: BoardController
var _recent_hits: Dictionary = {}

func bind(match_ctrl: MatchController, board: BoardController) -> void:
	_match = match_ctrl
	_board = board
	AdminBus.register_handler(&"shop.purchase", _on_purchase)
	AdminBus.register_handler(&"shop.refresh", _on_refresh)

func refresh_shop(free: bool) -> void:
	var payload := {"free": free, "team": ShipUnit.TEAM_PLAYER}
	AdminBus.request(&"shop.refresh", payload)

func _on_refresh(payload: Dictionary) -> Dictionary:
	var free := bool(payload.get("free", false))
	var cost := int(DataStore.economy.get("refresh_cost", 2))
	if not free:
		if _match.player_gold < cost:
			return {"accepted": false, "reason_key": "no_gold"}
		_match.try_spend(cost)
	var n := int(DataStore.economy.get("shop_slot_count", 7))
	_decay_recent_hits(_recent_hits)
	slots.clear()
	var seen_counts: Dictionary = {}
	for i in range(n):
		var sid := _roll_ship_id(seen_counts)
		seen_counts[sid] = int(seen_counts.get(sid, 0)) + 1
		_recent_hits[sid] = int(_recent_hits.get(sid, 0)) + 1
		slots.append({"ship_id": sid, "purchased": false})
	shop_changed.emit()
	return {"accepted": true}

func _roll_ship_id(seen_counts: Dictionary = {}) -> int:
	return roll_ship_id_for_level(_match.player_level, _match.battle_game_stage_count, seen_counts, _recent_hits)

static func roll_ship_id_for_level(level: int, _battle_stage: int, seen_counts: Dictionary = {}, recent_hits: Dictionary = {}) -> int:
	## v5.3 §5.3 weighted cost tiers; shop level index = min(level, 5).
	## battle_stage kept for compatibility; level gates replace old stage-based cruiser blocks.
	var ids: Array = DataStore.ship_ids()
	if ids.is_empty():
		return 1
	var odds_table: Array = DataStore.economy.get("shop_odds_by_level", [])
	var idx: int = clampi(level, 1, 5) - 1
	var weights: Array = [100, 0, 0, 0, 0]
	if idx < odds_table.size() and typeof(odds_table[idx]) == TYPE_ARRAY:
		weights = odds_table[idx]
	var max_same: int = maxi(1, int(DataStore.economy.get("shop_max_same_ship_per_refresh", 2)))
	var eligible_ids: Array = _eligible_ship_ids_for_level(level, ids)
	if eligible_ids.is_empty():
		return int(ids[0])
	for _attempt in range(48):
		var tier := _roll_cost_tier(weights)  # 1..5
		var pool: Array = []
		for sid in eligible_ids:
			var sid_i := int(sid)
			if int(seen_counts.get(sid_i, 0)) >= max_same:
				continue
			var cost := int(DataStore.get_ship(sid_i).get("cost", 1))
			if cost == tier:
				pool.append(sid_i)
		if not pool.is_empty():
			return _pick_pseudo_random(pool, recent_hits)
	## Fallback any eligible hull within duplicate cap.
	for _attempt2 in range(40):
		var sid2 := int(eligible_ids[randi() % eligible_ids.size()])
		if int(seen_counts.get(sid2, 0)) >= max_same:
			continue
		return sid2
	return int(eligible_ids[0])

static func _eligible_ship_ids_for_level(level: int, ids: Array) -> Array:
	var out: Array = []
	var unlocks: Dictionary = DataStore.economy.get("shop_unlock_level_by_group", {})
	for sid in ids:
		var sid_i := int(sid)
		var ship: Dictionary = DataStore.get_ship(sid_i)
		var group := str(ship.get("ship_group", "frigate"))
		var min_level := int(unlocks.get(group, 1))
		if level < min_level:
			continue
		out.append(sid_i)
	return out

static func _pick_pseudo_random(pool: Array, recent_hits: Dictionary) -> int:
	var window := maxi(1, int(DataStore.economy.get("shop_pseudo_random_window", 3)))
	var total := 0
	var weighted: Array = []
	for sid in pool:
		var sid_i := int(sid)
		var recent := int(recent_hits.get(sid_i, 0))
		var weight := maxi(1, window + 1 - recent)
		weighted.append({"ship_id": sid_i, "weight": weight})
		total += weight
	if total <= 0:
		return int(pool[randi() % pool.size()])
	var roll := randi() % total
	var acc := 0
	for entry in weighted:
		acc += int(entry.get("weight", 1))
		if roll < acc:
			return int(entry.get("ship_id", pool[0]))
	return int(pool[0])

static func _decay_recent_hits(recent_hits: Dictionary) -> void:
	var window := maxi(1, int(DataStore.economy.get("shop_pseudo_random_window", 3)))
	var keys := recent_hits.keys()
	for k in keys:
		var next_value := int(recent_hits.get(k, 0)) - 1
		if next_value <= 0:
			recent_hits.erase(k)
		else:
			recent_hits[k] = mini(next_value, window)

static func _roll_cost_tier(weights: Array) -> int:
	var total := 0
	for w in weights:
		total += int(w)
	if total <= 0:
		return 1
	var r := randi() % total
	var acc := 0
	for i in range(mini(5, weights.size())):
		acc += int(weights[i])
		if r < acc:
			return i + 1
	return 1

func try_buy(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= slots.size():
		return
	var slot: Dictionary = slots[slot_index]
	if slot.get("purchased", false):
		return
	var ship_id := int(slot.get("ship_id", 0))
	var cost := int(DataStore.get_ship(ship_id).get("cost", 0))
	AdminBus.request(&"shop.purchase", {
		"slot_index": slot_index,
		"ship_id": ship_id,
		"cost": cost,
		"team": ShipUnit.TEAM_PLAYER,
	})

func _on_purchase(payload: Dictionary) -> Dictionary:
	var idx := int(payload.get("slot_index", -1))
	var ship_id := int(payload.get("ship_id", 0))
	var cost := int(payload.get("cost", 0))
	if idx < 0 or idx >= slots.size():
		return {"accepted": false}
	if slots[idx].get("purchased", false):
		return {"accepted": false}
	var hangar := _board.find_empty_hangar(ShipUnit.TEAM_PLAYER)
	if hangar.x < 0:
		get_tree().call_group("match_root", "show_notice", "备战席已满")
		return {"accepted": false, "reason_key": "hangar_full"}
	if not _match.try_spend(cost):
		get_tree().call_group("match_root", "show_notice", "黄币不足")
		return {"accepted": false, "reason_key": "no_gold"}
	slots[idx]["purchased"] = true
	AdminBus.request(&"board.deploy", {
		"ship_id": ship_id,
		"star": 1,
		"team": ShipUnit.TEAM_PLAYER,
		"slot_type": "hangar",
		"x": hangar.x,
		"z": hangar.y,
	})
	_board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	shop_changed.emit()
	return {"accepted": true}

func manual_refresh() -> void:
	refresh_shop(false)
