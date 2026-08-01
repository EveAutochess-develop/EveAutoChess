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

func refresh_shop(free: bool, persist: bool = true) -> void:
	var payload := {"free": free, "team": ShipUnit.TEAM_PLAYER, "persist": persist}
	AdminBus.request(&"shop.refresh", payload)

func _on_refresh(payload: Dictionary) -> Dictionary:
	var free := bool(payload.get("free", false))
	var persist := bool(payload.get("persist", true))
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
		if sid <= 0:
			sid = 1
		seen_counts[sid] = int(seen_counts.get(sid, 0)) + 1
		_recent_hits[sid] = int(_recent_hits.get(sid, 0)) + 1
		slots.append({"ship_id": sid, "purchased": false})
	_pity_record_refresh(slots)
	shop_changed.emit()
	if persist and _match and _match.has_method("request_autosave"):
		_match.request_autosave()
	return {"accepted": true}

func _roll_ship_id(seen_counts: Dictionary = {}) -> int:
	return roll_ship_id_for_level(
		_match.player_level, _match.battle_game_stage_count, seen_counts, _recent_hits, _shop_titan_race()
	)

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
	return _pick_pseudo_random(pool, _recent_hits, _shop_titan_race())

## Local seat's titan race for shop race weight (MULTIPLAYER_PVP §2.1). Empty = no boost.
func _shop_titan_race() -> String:
	if _board == null:
		return ""
	return _board.titan_fetter_race(ShipUnit.TEAM_PLAYER)

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
	## Pity buckets = tonnage-icon categories (`UiAssets.TONNAGE_ICON_MAP` keys).
	## One icon file → one pity key (carrier ≠ force_auxiliary; mining_barge shares industrial icon).
	return str(DataStore.get_ship(ship_id).get("ship_group", ""))

static func _unlocked_tonnage_keys(level: int) -> Array:
	var unlocks: Dictionary = DataStore.economy.get("shop_unlock_level_by_group", {})
	var keys: Array = []
	## Must match TONNAGE_ICON_MAP ship (non-drone) categories.
	var candidates := [
		"frigate", "destroyer", "cruiser", "battlecruiser", "battleship",
		"dreadnought", "carrier", "force_auxiliary",
		"mining_barge", "industrial_command", "capital_industrial",
	]
	var cap_lv := int(DataStore.economy.get("shop_capital_min_level", 15))
	for key in candidates:
		var need := 1
		match key:
			"frigate", "destroyer":
				need = 1
			"mining_barge":
				need = 1
			"industrial_command":
				need = int(unlocks.get("battleship", 10))
			"capital_industrial":
				need = maxi(int(unlocks.get("carrier", 15)), cap_lv)
			"carrier", "force_auxiliary", "dreadnought":
				need = maxi(int(unlocks.get(key, 15)), cap_lv)
			_:
				need = int(unlocks.get(key, 1))
		if level >= need:
			keys.append(key)
	return keys

static func roll_ship_id_for_level(
	level: int,
	_battle_stage: int,
	seen_counts: Dictionary = {},
	recent_hits: Dictionary = {},
	titan_race: String = ""
) -> int:
	## v5.3 §5.3 weighted cost tiers; shop level index = min(level, 5).
	## battle_stage kept for compatibility; level gates replace old stage-based cruiser blocks.
	## titan_race: nullsec seat titan → ×1.10 weight for matching hulls (§2.1).
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
			var sd: Dictionary = DataStore.get_ship(sid_i)
			var c := int(sd.get("cost", 0))
			var role := str(sd.get("capital_role", ""))
			var group := str(sd.get("ship_group", ""))
			## Include cost5 covert cyno + high-cost capitals + capital industrial (Rorqual).
			if (
				c in cap_costs
				or role == "covert_cyno"
				or bool(sd.get("requires_cyno_entry", false))
				or group == "capital_industrial"
			):
				cap_pool.append(sid_i)
		if not cap_pool.is_empty():
			return _pick_pseudo_random(cap_pool, recent_hits, titan_race)
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
			return _pick_pseudo_random(pool, recent_hits, titan_race)
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
	var cap_lv := int(DataStore.economy.get("shop_capital_min_level", 15))
	for sid in ids:
		var sid_i := int(sid)
		var ship: Dictionary = DataStore.get_ship(sid_i)
		if not _shop_eligible(ship):
			continue
		var group := str(ship.get("ship_group", "frigate"))
		## Mining unlocks: barge free; Orca mirrors battleship; Rorqual mirrors capitals.
		var min_level := int(unlocks.get(group, 1))
		match group:
			"mining_barge":
				min_level = 1
			"industrial_command":
				min_level = int(unlocks.get("battleship", 10))
			"capital_industrial":
				min_level = maxi(int(unlocks.get("carrier", 15)), cap_lv)
		var ship_min := int(ship.get("shop_min_level", 0))
		if ship_min > 0:
			min_level = maxi(min_level, ship_min)
		if level < min_level:
			continue
		out.append(sid_i)
	return out

static func _shop_eligible(ship: Dictionary) -> bool:
	## Hard-exclude sleeper / freighter / titan (and any shop_eligible:false).
	if ship.has("shop_eligible") and not bool(ship.get("shop_eligible", true)):
		return false
	var tags: Array = ship.get("tags", []) as Array
	for t in tags:
		var ts := str(t)
		if ts == "shop_ineligible" or ts == "sleeper" or ts == "freighter" or ts == "titan" or ts == "pve_creep":
			return false
	var group := str(ship.get("ship_group", ""))
	if group == "titan" or group == "freighter" or group == "sleeper":
		return false
	var groups: Array = ship.get("ship_groups", []) as Array
	for g in groups:
		var gs := str(g)
		if gs == "titan" or gs == "freighter" or gs == "sleeper":
			return false
	return true

static func _pick_pseudo_random(pool: Array, recent_hits: Dictionary, titan_race: String = "") -> int:
	var window := maxi(1, int(DataStore.economy.get("shop_pseudo_random_window", 3)))
	var race_mul := float(DataStore.economy.get("titan_shop_race_weight_mul", 1.1))
	var want_race := titan_race.strip_edges().to_lower()
	var total := 0
	var weighted: Array = []
	for sid in pool:
		var sid_i := int(sid)
		var recent := int(recent_hits.get(sid_i, 0))
		var weight := float(maxi(1, window + 1 - recent))
		## Titan seat race: matching hulls get ×1.10 (MULTIPLAYER_PVP §2.1).
		if want_race != "" and race_mul > 1.0 and _ship_race_key(sid_i) == want_race:
			weight *= race_mul
		var w_i := maxi(1, int(round(weight * 100.0)))
		weighted.append({"ship_id": sid_i, "weight": w_i})
		total += w_i
	if total <= 0:
		return int(pool[randi() % pool.size()])
	var roll := randi() % total
	var acc := 0
	for entry in weighted:
		acc += int(entry.get("weight", 1))
		if roll < acc:
			return int(entry.get("ship_id", pool[0]))
	return int(pool[0])


static func _ship_race_key(ship_id: int) -> String:
	var ship: Dictionary = DataStore.get_ship(ship_id)
	var race := str(ship.get("race", "")).strip_edges().to_lower()
	if race != "":
		return race
	for t in (ship.get("fetter_ids", []) as Array):
		var k := str(t).to_lower()
		if k in ["amarr", "caldari", "gallente", "minmatar"]:
			return k
	return ""

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
	if _match and _match.has_method("request_autosave"):
		_match.request_autosave()
	return {"accepted": true}

func manual_refresh() -> void:
	refresh_shop(false)
