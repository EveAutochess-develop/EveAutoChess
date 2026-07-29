extends Node
class_name ShopController

signal shop_changed()

var slots: Array = []  # Array of {ship_id:int, purchased:bool} size from economy
var _match: MatchController
var _board: BoardController
var _recent_hits: Dictionary = {}
## Tonnage pity: after N refreshes without a unlocked tonnage, force it on next.
var _pity_refresh_count: int = 0
var _pity_seen_tonnage: Dictionary = {}  # tonnage_key -> true

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
	var force_tonnages: Array = _pity_force_tonnages_for_this_refresh()
	var force_i := 0
	for i in range(n):
		var sid := 0
		if force_i < force_tonnages.size():
			sid = _roll_ship_id_for_tonnage(str(force_tonnages[force_i]), seen_counts)
			force_i += 1
		if sid <= 0:
			sid = _roll_ship_id(seen_counts)
		seen_counts[sid] = int(seen_counts.get(sid, 0)) + 1
		_recent_hits[sid] = int(_recent_hits.get(sid, 0)) + 1
		slots.append({"ship_id": sid, "purchased": false})
	_pity_record_refresh(slots)
	shop_changed.emit()
	return {"accepted": true}

func _roll_ship_id(seen_counts: Dictionary = {}) -> int:
	return roll_ship_id_for_level(_match.player_level, _match.battle_game_stage_count, seen_counts, _recent_hits)

func _roll_ship_id_for_tonnage(tonnage_key: String, seen_counts: Dictionary) -> int:
	var ids: Array = DataStore.ship_ids()
	var eligible: Array = _eligible_ship_ids_for_level(_match.player_level, ids)
	var max_same: int = maxi(1, int(DataStore.economy.get("shop_max_same_ship_per_refresh", 2)))
	var pool: Array = []
	for sid in eligible:
		var sid_i := int(sid)
		if int(seen_counts.get(sid_i, 0)) >= max_same:
			continue
		if ship_tonnage_key(sid_i) == tonnage_key:
			pool.append(sid_i)
	if pool.is_empty():
		return 0
	return _pick_pseudo_random(pool, _recent_hits)

func _pity_force_tonnages_for_this_refresh() -> Array:
	var window := maxi(1, int(DataStore.economy.get("shop_tonnage_pity_window", 5)))
	if _pity_refresh_count < window:
		return []
	var missing: Array = []
	for key in _unlocked_tonnage_keys(_match.player_level):
		if not bool(_pity_seen_tonnage.get(key, false)):
			missing.append(key)
	return missing

func _pity_record_refresh(shop_slots: Array) -> void:
	var window := maxi(1, int(DataStore.economy.get("shop_tonnage_pity_window", 5)))
	## After a pity refresh (count already >= window), reset window.
	if _pity_refresh_count >= window:
		_pity_refresh_count = 0
		_pity_seen_tonnage.clear()
	for slot in shop_slots:
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		var key := ship_tonnage_key(int(slot.get("ship_id", 0)))
		if key != "":
			_pity_seen_tonnage[key] = true
	_pity_refresh_count += 1

static func ship_tonnage_key(ship_id: int) -> String:
	## Align with tonnage icons; carrier + FAX share one bucket.
	var group := str(DataStore.get_ship(ship_id).get("ship_group", ""))
	if group in ["carrier", "force_auxiliary"]:
		return "capital_aviation"
	return group

static func _unlocked_tonnage_keys(level: int) -> Array:
	var unlocks: Dictionary = DataStore.economy.get("shop_unlock_level_by_group", {})
	var keys: Array = []
	var candidates := [
		"frigate", "destroyer", "cruiser", "battlecruiser", "battleship",
		"dreadnought", "capital_aviation",
	]
	for key in candidates:
		var need := 1
		if key == "capital_aviation":
			need = mini(
				int(unlocks.get("carrier", 15)),
				int(unlocks.get("force_auxiliary", 15))
			)
		elif key == "frigate" or key == "destroyer":
			need = 1
		else:
			need = int(unlocks.get(key, 1))
		## Covert cyno (cruiser @15) doesn't unlock cruiser early; capital_aviation still 15.
		if level >= need:
			keys.append(key)
	## Capitals / cyno also require shop_capital_min_level for capital_aviation appearance intent.
	var cap_lv := int(DataStore.economy.get("shop_capital_min_level", 15))
	if level < cap_lv and "capital_aviation" in keys:
		keys.erase("capital_aviation")
	if level < cap_lv and "dreadnought" in keys:
		keys.erase("dreadnought")
	return keys

static func roll_ship_id_for_level(level: int, _battle_stage: int, seen_counts: Dictionary = {}, recent_hits: Dictionary = {}) -> int:
	## v5.3 §5.3 weighted cost tiers; shop level index = min(level, 5).
	## battle_stage kept for compatibility; level gates replace old stage-based cruiser blocks.
	var ids: Array = DataStore.ship_ids()
	if ids.is_empty():
		return 1
	var max_same: int = maxi(1, int(DataStore.economy.get("shop_max_same_ship_per_refresh", 2)))
	var eligible_ids: Array = _eligible_ship_ids_for_level(level, ids)
	if eligible_ids.is_empty():
		return int(ids[0])
	## ≥15: chance to roll capital cost pool {22,24} (not normal fee tiers).
	var cap_lv := int(DataStore.economy.get("shop_capital_min_level", 15))
	var cap_w := int(DataStore.economy.get("shop_capital_roll_weight_pct", 35))
	if level >= cap_lv and cap_w > 0 and (randi() % 100) < cap_w:
		var cap_costs: Array = DataStore.economy.get("shop_capital_costs", [22, 24])
		var cap_pool: Array = []
		for sid in eligible_ids:
			var sid_i := int(sid)
			if int(seen_counts.get(sid_i, 0)) >= max_same:
				continue
			var c := int(DataStore.get_ship(sid_i).get("cost", 0))
			var role := str(DataStore.get_ship(sid_i).get("capital_role", ""))
			## Include cost5 covert cyno + high-cost capitals in the boosted pool.
			if c in cap_costs or role == "covert_cyno" or bool(DataStore.get_ship(sid_i).get("requires_cyno_entry", false)):
				cap_pool.append(sid_i)
		if not cap_pool.is_empty():
			return _pick_pseudo_random(cap_pool, recent_hits)
	var odds_table: Array = DataStore.economy.get("shop_odds_by_level", [])
	var tier_costs: Array = DataStore.economy.get("shop_tier_costs", [2, 3, 5, 7, 13])
	var idx: int = clampi(level, 1, 5) - 1
	var weights: Array = [100, 0, 0, 0, 0]
	if idx < odds_table.size() and typeof(odds_table[idx]) == TYPE_ARRAY:
		weights = odds_table[idx]
	for _attempt in range(48):
		var tier_i := _roll_cost_tier(weights) - 1  # 0..4
		var want_cost := 2
		if tier_i >= 0 and tier_i < tier_costs.size():
			want_cost = int(tier_costs[tier_i])
		var pool: Array = []
		for sid in eligible_ids:
			var sid_i := int(sid)
			if int(seen_counts.get(sid_i, 0)) >= max_same:
				continue
			var cost := int(DataStore.get_ship(sid_i).get("cost", 1))
			## 7-fee column also includes attack battlecruisers (cost 8).
			if cost == want_cost or (want_cost == 7 and cost == 8):
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
		var ship_min := int(ship.get("shop_min_level", 0))
		if ship_min > 0:
			min_level = maxi(min_level, ship_min)
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
