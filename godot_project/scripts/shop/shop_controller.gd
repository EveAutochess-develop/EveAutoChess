extends Node
class_name ShopController

signal shop_changed()

var slots: Array = []  # Array of {ship_id:int, purchased:bool} size from economy
## Shop function-bucket gear (EQUIPMENT.md §1): {id:String, purchased:bool} × N.
var equipment_slots: Array = []
## Equipment category pity (A–G shop_category): window of N refreshes.
var _equip_pity_refresh_count: int = 0
var _equip_pity_seen_cat: Dictionary = {}  # shop_category -> true
var _match: MatchController
var _board: BoardController
var _recent_hits: Dictionary = {}
## Tonnage pity: after N refreshes without a unlocked tonnage, force it on next.
var _pity_refresh_count: int = 0
var _pity_seen_tonnage: Dictionary = {}  # tonnage_key -> true
## Full-pool ship_id / equip id pity (ECONOMY_AND_SHOP §3): window default 30.
var _id_pity_refresh_count: int = 0
var _id_pity_seen_ships: Dictionary = {}  # ship_id -> true
var _id_pity_seen_equips: Dictionary = {}  # equip id -> true
## SEMI_ASYNC §2 — shop rolls on match_seed stream (not global randi).
static var _auth_rng: MatchRng = null
static var _auth_stream: String = "shop"


func bind(match_ctrl: MatchController, board: BoardController) -> void:
	_match = match_ctrl
	_board = board
	AdminBus.register_handler(&"shop.purchase", _on_purchase)
	AdminBus.register_handler(&"shop.refresh", _on_refresh)
	AdminBus.register_handler(&"shop.equipment_purchase", _on_equipment_purchase)


static func bind_match_rng(rng: MatchRng, stream: String = "shop") -> void:
	_auth_rng = rng
	_auth_stream = stream if stream != "" else "shop"


static func _randi_range(from_v: int, to_v: int) -> int:
	if _auth_rng != null:
		return _auth_rng.stream_randi_range(_auth_stream, from_v, to_v)
	return randi_range(from_v, to_v)


static func _shuffle_det(arr: Array) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = _randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func refresh_shop(free: bool, persist: bool = true) -> void:
	var payload: Dictionary = {"free": free, "team": ShipUnit.TEAM_PLAYER, "persist": persist}
	AdminBus.request(&"shop.refresh", payload)

func _on_refresh(payload: Dictionary) -> Dictionary:
	var free: bool = TypedVariant.as_bool(payload.get("free", false), false)
	var persist: bool = TypedVariant.as_bool(payload.get("persist", true), true)
	var cost: int = TypedVariant.as_int(DataStore.economy.get("refresh_cost", 2), 2)
	if not free:
		if _match.player_gold < cost:
			SessionDiagnostics.log("shop.refresh", "fail reason=no_gold")
			return {"accepted": false, "reason_key": "no_gold"}
		_match.try_spend(cost)
	var n: int = TypedVariant.as_int(DataStore.economy.get("shop_slot_count", 7), 7)
	_decay_recent_hits(_recent_hits)
	slots.clear()
	var seen_counts: Dictionary = {}
	var force_tonnages: Array = _pity_force_tonnages_for_this_refresh()
	var force_ids: Array = _id_pity_force_ship_ids(n)
	var force_i: int = 0
	var force_id_i: int = 0
	for i: int in range(n):
		var sid: int = 0
		if force_id_i < force_ids.size():
			sid = TypedVariant.as_int(force_ids[force_id_i], 0)
			force_id_i += 1
			if TypedVariant.as_int(seen_counts.get(sid, 0), 0) >= maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_max_same_ship_per_refresh", 2), 2)):
				sid = 0
		if sid <= 0 and force_i < force_tonnages.size():
			sid = _roll_ship_id_for_tonnage(str(force_tonnages[force_i]), seen_counts)
			force_i += 1
		if sid <= 0:
			sid = _roll_ship_id(seen_counts)
		if sid <= 0:
			sid = 1
		seen_counts[sid] = TypedVariant.as_int(seen_counts.get(sid, 0), 0) + 1
		_recent_hits[sid] = TypedVariant.as_int(_recent_hits.get(sid, 0), 0) + 1
		slots.append({"ship_id": sid, "purchased": false})
	_roll_equipment_slots()
	_pity_record_refresh(slots)
	_id_pity_record_ship_refresh(slots)
	_id_pity_record_equip_refresh(equipment_slots)
	shop_changed.emit()
	if persist and _match and _match.has_method("request_autosave"):
		_match.request_autosave()
	SessionDiagnostics.log("shop.refresh", "ok free=%s" % free)
	return {"accepted": true}

func _roll_ship_id(seen_counts: Dictionary = {}) -> int:
	return _roll_ship_id_with_id_pity(
		_match.player_level, _match.battle_game_stage_count, seen_counts, _recent_hits, _shop_titan_race()
	)

func _roll_ship_id_with_id_pity(
	level: int,
	_battle_stage: int,
	seen_counts: Dictionary,
	recent_hits: Dictionary,
	titan_race: String
) -> int:
	## Same as static roll, but apply ID pity weight ramp for unseen unlocked hulls.
	var ids: Array = DataStore.ship_ids()
	if ids.is_empty():
		return 1
	var max_same: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_max_same_ship_per_refresh", 2), 2))
	var eligible_ids: Array = _eligible_ship_ids_for_level(level, ids)
	if eligible_ids.is_empty():
		return TypedVariant.as_int(ids[0], 1)
	var cap_lv: int = TypedVariant.as_int(DataStore.economy.get("shop_capital_min_level", 15), 15)
	var cap_w: int = TypedVariant.as_int(DataStore.economy.get("shop_capital_roll_weight_pct", 35), 35)
	if level >= cap_lv and cap_w > 0 and _randi_range(0, 99) < cap_w:
		var cap_costs: Array = TypedVariant.as_array(DataStore.economy.get("shop_capital_costs", [22, 24]))
		var cap_pool: Array = []
		for sid_v: Variant in eligible_ids:
			var sid_i: int = TypedVariant.as_int(sid_v, 0)
			if TypedVariant.as_int(seen_counts.get(sid_i, 0), 0) >= max_same:
				continue
			var sd: Dictionary = DataStore.get_ship(sid_i)
			var c: int = TypedVariant.as_int(sd.get("cost", 0), 0)
			var role: String = str(sd.get("capital_role", ""))
			var group: String = str(sd.get("ship_group", ""))
			if (
				c in cap_costs
				or role == "covert_cyno"
				or TypedVariant.as_bool(sd.get("requires_cyno_entry", false), false)
				or group == "capital_industrial"
			):
				cap_pool.append(sid_i)
		if not cap_pool.is_empty():
			return _pick_pseudo_random_id_pity(cap_pool, recent_hits, titan_race)
	var odds_table: Array = TypedVariant.as_array(DataStore.economy.get("shop_odds_by_level", []))
	var tier_costs: Array = TypedVariant.as_array(DataStore.economy.get("shop_tier_costs", [2, 3, 5, 7, 13]))
	var idx: int = clampi(level, 1, 5) - 1
	var weights: Array = [100, 0, 0, 0, 0]
	if idx < odds_table.size() and typeof(odds_table[idx]) == TYPE_ARRAY:
		@warning_ignore("unsafe_cast")
		weights = odds_table[idx] as Array
	for _attempt: int in range(48):
		var tier_i: int = _roll_cost_tier(weights) - 1
		var want_cost: int = 2
		if tier_i >= 0 and tier_i < tier_costs.size():
			want_cost = TypedVariant.as_int(tier_costs[tier_i], 2)
		var pool: Array = []
		for sid_v2: Variant in eligible_ids:
			var sid_i2: int = TypedVariant.as_int(sid_v2, 0)
			if TypedVariant.as_int(seen_counts.get(sid_i2, 0), 0) >= max_same:
				continue
			var ship_cost: int = TypedVariant.as_int(DataStore.get_ship(sid_i2).get("cost", 1), 1)
			if ship_cost == want_cost or (want_cost == 7 and ship_cost == 8):
				pool.append(sid_i2)
		if not pool.is_empty():
			return _pick_pseudo_random_id_pity(pool, recent_hits, titan_race)
	for _attempt2: int in range(40):
		var sid2: int = TypedVariant.as_int(eligible_ids[_randi_range(0, eligible_ids.size() - 1)], 0)
		if TypedVariant.as_int(seen_counts.get(sid2, 0), 0) >= max_same:
			continue
		return sid2
	return TypedVariant.as_int(eligible_ids[0], 0)

func _id_pity_window() -> int:
	return maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_id_pity_window", 30), 30))

func _id_pity_ship_weight_mul(sid: int) -> float:
	if TypedVariant.as_bool(_id_pity_seen_ships.get(sid, false), false):
		return 1.0
	## Ramp weight for each refresh the id stays missing in this window.
	return 1.0 + float(_id_pity_refresh_count)

func _id_pity_equip_weight_mul(eid: String) -> float:
	if TypedVariant.as_bool(_id_pity_seen_equips.get(eid, false), false):
		return 1.0
	return 1.0 + float(_id_pity_refresh_count)

func _id_pity_force_ship_ids(slot_count: int) -> Array:
	var window: int = _id_pity_window()
	if _id_pity_refresh_count < window:
		return []
	var eligible: Array = _eligible_ship_ids_for_level(_match.player_level, DataStore.ship_ids())
	var missing: Array = []
	for sid_v: Variant in eligible:
		var sid: int = TypedVariant.as_int(sid_v, 0)
		if not TypedVariant.as_bool(_id_pity_seen_ships.get(sid, false), false):
			missing.append(sid)
	if missing.is_empty():
		return []
	_shuffle_det(missing)
	return missing.slice(0, mini(slot_count, missing.size()))

func _id_pity_record_ship_refresh(shop_slots: Array) -> void:
	var window: int = _id_pity_window()
	if _id_pity_refresh_count >= window:
		_id_pity_refresh_count = 0
		_id_pity_seen_ships.clear()
		_id_pity_seen_equips.clear()
	for slot_v: Variant in shop_slots:
		if typeof(slot_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var slot: Dictionary = slot_v as Dictionary
		var sid: int = TypedVariant.as_int(slot.get("ship_id", 0), 0)
		if sid > 0:
			_id_pity_seen_ships[sid] = true
	_id_pity_refresh_count += 1

func _pick_pseudo_random_id_pity(pool: Array, recent_hits: Dictionary, titan_race: String = "") -> int:
	var window: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_pseudo_random_window", 3), 3))
	var race_mul: float = TypedVariant.as_float(DataStore.economy.get("titan_shop_race_weight_mul", 1.1), 1.1)
	var want_race: String = titan_race.strip_edges().to_lower()
	var total: int = 0
	var weighted: Array = []
	for sid_v: Variant in pool:
		var sid_i: int = TypedVariant.as_int(sid_v, 0)
		var recent: int = TypedVariant.as_int(recent_hits.get(sid_i, 0), 0)
		var weight: float = float(maxi(1, window + 1 - recent))
		if want_race != "" and race_mul > 1.0 and _ship_race_key(sid_i) == want_race:
			weight *= race_mul
		weight *= _id_pity_ship_weight_mul(sid_i)
		var w_i: int = maxi(1, roundi(weight * 100.0))
		weighted.append({"ship_id": sid_i, "weight": w_i})
		total += w_i
	if total <= 0:
		return TypedVariant.as_int(pool[_randi_range(0, pool.size() - 1)], 0)
	var roll: int = _randi_range(0, total - 1)
	var acc: int = 0
	for entry_v: Variant in weighted:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var entry: Dictionary = entry_v as Dictionary
		acc += TypedVariant.as_int(entry.get("weight", 1), 1)
		if roll < acc:
			return TypedVariant.as_int(entry.get("ship_id", 0), 0)
	return TypedVariant.as_int(pool[0], 0)

func _roll_ship_id_for_tonnage(tonnage_key: String, seen_counts: Dictionary) -> int:
	var ids: Array = DataStore.ship_ids()
	var eligible: Array = _eligible_ship_ids_for_level(_match.player_level, ids)
	var max_same: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_max_same_ship_per_refresh", 2), 2))
	var pool: Array = []
	for sid_v: Variant in eligible:
		var sid_i: int = TypedVariant.as_int(sid_v, 0)
		if TypedVariant.as_int(seen_counts.get(sid_i, 0), 0) >= max_same:
			continue
		if ship_tonnage_key(sid_i) == tonnage_key:
			pool.append(sid_i)
	if pool.is_empty():
		return 0
	return _pick_pseudo_random_id_pity(pool, _recent_hits, _shop_titan_race())

## Local seat's titan race for shop race weight (MULTIPLAYER_PVP §2.1). Empty = no boost.
func _shop_titan_race() -> String:
	if _board == null:
		return ""
	return _board.titan_fetter_race(ShipUnit.TEAM_PLAYER)

func _pity_force_tonnages_for_this_refresh() -> Array:
	var window: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_tonnage_pity_window", 5), 5))
	if _pity_refresh_count < window:
		return []
	var missing: Array = []
	for key: Variant in _unlocked_tonnage_keys(_match.player_level):
		if not TypedVariant.as_bool(_pity_seen_tonnage.get(key, false), false):
			missing.append(key)
	return missing

func _pity_record_refresh(shop_slots: Array) -> void:
	var window: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_tonnage_pity_window", 5), 5))
	## After a pity refresh (count already >= window), reset window.
	if _pity_refresh_count >= window:
		_pity_refresh_count = 0
		_pity_seen_tonnage.clear()
	for slot_v: Variant in shop_slots:
		if typeof(slot_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var slot: Dictionary = slot_v as Dictionary
		var key: String = ship_tonnage_key(TypedVariant.as_int(slot.get("ship_id", 0), 0))
		if key != "":
			_pity_seen_tonnage[key] = true
	_pity_refresh_count += 1

static func ship_tonnage_key(ship_id: int) -> String:
	## Pity buckets = tonnage-icon categories (`UiAssets.TONNAGE_ICON_MAP` keys).
	## One icon file → one pity key (carrier ≠ force_auxiliary; mining_barge shares industrial icon).
	return str(DataStore.get_ship(ship_id).get("ship_group", ""))

static func _unlocked_tonnage_keys(level: int) -> Array:
	var unlocks: Dictionary = TypedVariant.as_dict(DataStore.economy.get("shop_unlock_level_by_group", {}))
	var keys: Array = []
	## Must match TONNAGE_ICON_MAP ship (non-drone) categories.
	var candidates: Array = [
		"frigate", "destroyer", "cruiser", "battlecruiser", "battleship",
		"dreadnought", "carrier", "force_auxiliary",
		"mining_barge", "industrial_command", "capital_industrial",
	]
	var cap_lv: int = TypedVariant.as_int(DataStore.economy.get("shop_capital_min_level", 15), 15)
	for key: Variant in candidates:
		var key_s: String = str(key)
		var need: int = TypedVariant.as_int(unlocks.get(key_s, 1), 1)
		match key_s:
			"capital_industrial", "carrier", "force_auxiliary", "dreadnought":
				need = maxi(need, cap_lv)
			_:
				pass
		if level >= need:
			keys.append(key_s)
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
	var max_same: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_max_same_ship_per_refresh", 2), 2))
	var eligible_ids: Array = _eligible_ship_ids_for_level(level, ids)
	if eligible_ids.is_empty():
		return TypedVariant.as_int(ids[0], 1)
	## ≥15: chance to roll capital cost pool {22,24} (not normal fee tiers).
	var cap_lv: int = TypedVariant.as_int(DataStore.economy.get("shop_capital_min_level", 15), 15)
	var cap_w: int = TypedVariant.as_int(DataStore.economy.get("shop_capital_roll_weight_pct", 35), 35)
	if level >= cap_lv and cap_w > 0 and _randi_range(0, 99) < cap_w:
		var cap_costs: Array = TypedVariant.as_array(DataStore.economy.get("shop_capital_costs", [22, 24]))
		var cap_pool: Array = []
		for sid_v: Variant in eligible_ids:
			var sid_i: int = TypedVariant.as_int(sid_v, 0)
			if TypedVariant.as_int(seen_counts.get(sid_i, 0), 0) >= max_same:
				continue
			var sd: Dictionary = DataStore.get_ship(sid_i)
			var c: int = TypedVariant.as_int(sd.get("cost", 0), 0)
			var role: String = str(sd.get("capital_role", ""))
			var group: String = str(sd.get("ship_group", ""))
			## Include cost5 covert cyno + high-cost capitals + capital industrial (Rorqual).
			if (
				c in cap_costs
				or role == "covert_cyno"
				or TypedVariant.as_bool(sd.get("requires_cyno_entry", false), false)
				or group == "capital_industrial"
			):
				cap_pool.append(sid_i)
		if not cap_pool.is_empty():
			return _pick_pseudo_random(cap_pool, recent_hits, titan_race)
	var odds_table: Array = TypedVariant.as_array(DataStore.economy.get("shop_odds_by_level", []))
	var tier_costs: Array = TypedVariant.as_array(DataStore.economy.get("shop_tier_costs", [2, 3, 5, 7, 13]))
	var idx: int = clampi(level, 1, 5) - 1
	var weights: Array = [100, 0, 0, 0, 0]
	if idx < odds_table.size() and typeof(odds_table[idx]) == TYPE_ARRAY:
		@warning_ignore("unsafe_cast")
		weights = odds_table[idx] as Array
	for _attempt: int in range(48):
		var tier_i: int = _roll_cost_tier(weights) - 1  # 0..4
		var want_cost: int = 2
		if tier_i >= 0 and tier_i < tier_costs.size():
			want_cost = TypedVariant.as_int(tier_costs[tier_i], 2)
		var pool: Array = []
		for sid_v: Variant in eligible_ids:
			var sid_i: int = TypedVariant.as_int(sid_v, 0)
			if TypedVariant.as_int(seen_counts.get(sid_i, 0), 0) >= max_same:
				continue
			var ship_cost: int = TypedVariant.as_int(DataStore.get_ship(sid_i).get("cost", 1), 1)
			## 7-fee column also includes attack battlecruisers (cost 8).
			if ship_cost == want_cost or (want_cost == 7 and ship_cost == 8):
				pool.append(sid_i)
		if not pool.is_empty():
			return _pick_pseudo_random(pool, recent_hits, titan_race)
	## Fallback any eligible hull within duplicate cap.
	for _attempt2: int in range(40):
		var sid2: int = TypedVariant.as_int(eligible_ids[_randi_range(0, eligible_ids.size() - 1)], 0)
		if TypedVariant.as_int(seen_counts.get(sid2, 0), 0) >= max_same:
			continue
		return sid2
	return TypedVariant.as_int(eligible_ids[0], 0)

static func _eligible_ship_ids_for_level(level: int, ids: Array) -> Array:
	var out: Array = []
	var unlocks: Dictionary = TypedVariant.as_dict(DataStore.economy.get("shop_unlock_level_by_group", {}))
	var cap_lv: int = TypedVariant.as_int(DataStore.economy.get("shop_capital_min_level", 15), 15)
	for sid_v: Variant in ids:
		var sid_i: int = TypedVariant.as_int(sid_v, 0)
		var ship: Dictionary = DataStore.get_ship(sid_i)
		if not _shop_eligible(ship):
			continue
		var group: String = str(ship.get("ship_group", "frigate"))
		## Group unlock from economy.json; capital_* also respect shop_capital_min_level.
		var min_level: int = TypedVariant.as_int(unlocks.get(group, 1), 1)
		match group:
			"capital_industrial", "carrier", "force_auxiliary", "dreadnought":
				min_level = maxi(min_level, cap_lv)
			_:
				pass
		var ship_min: int = TypedVariant.as_int(ship.get("shop_min_level", 0), 0)
		if ship_min > 0:
			min_level = maxi(min_level, ship_min)
		if level < min_level:
			continue
		out.append(sid_i)
	return out

static func _shop_eligible(ship: Dictionary) -> bool:
	## Hard-exclude sleeper / freighter / titan (and any shop_eligible:false).
	if ship.has("shop_eligible") and not TypedVariant.as_bool(ship.get("shop_eligible", true), true):
		return false
	var tags: Array = TypedVariant.as_array(ship.get("tags", []))
	for t: Variant in tags:
		var ts: String = str(t)
		if ts == "shop_ineligible" or ts == "sleeper" or ts == "freighter" or ts == "titan" or ts == "pve_creep":
			return false
	var group: String = str(ship.get("ship_group", ""))
	if group == "titan" or group == "freighter" or group == "sleeper":
		return false
	var groups: Array = TypedVariant.as_array(ship.get("ship_groups", []))
	for g: Variant in groups:
		var gs: String = str(g)
		if gs == "titan" or gs == "freighter" or gs == "sleeper":
			return false
	return true

static func _pick_pseudo_random(pool: Array, recent_hits: Dictionary, titan_race: String = "") -> int:
	var window: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_pseudo_random_window", 3), 3))
	var race_mul: float = TypedVariant.as_float(DataStore.economy.get("titan_shop_race_weight_mul", 1.1), 1.1)
	var want_race: String = titan_race.strip_edges().to_lower()
	var total: int = 0
	var weighted: Array = []
	for sid_v: Variant in pool:
		var sid_i: int = TypedVariant.as_int(sid_v, 0)
		var recent: int = TypedVariant.as_int(recent_hits.get(sid_i, 0), 0)
		var weight: float = float(maxi(1, window + 1 - recent))
		## Titan seat race: matching hulls get ×1.10 (MULTIPLAYER_PVP §2.1).
		if want_race != "" and race_mul > 1.0 and _ship_race_key(sid_i) == want_race:
			weight *= race_mul
		var w_i: int = maxi(1, roundi(weight * 100.0))
		weighted.append({"ship_id": sid_i, "weight": w_i})
		total += w_i
	if total <= 0:
		return TypedVariant.as_int(pool[_randi_range(0, pool.size() - 1)], 0)
	var roll: int = _randi_range(0, total - 1)
	var acc: int = 0
	for entry_v: Variant in weighted:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var entry: Dictionary = entry_v as Dictionary
		acc += TypedVariant.as_int(entry.get("weight", 1), 1)
		if roll < acc:
			return TypedVariant.as_int(entry.get("ship_id", pool[0]), TypedVariant.as_int(pool[0], 0))
	return TypedVariant.as_int(pool[0], 0)


static func _ship_race_key(ship_id: int) -> String:
	var ship: Dictionary = DataStore.get_ship(ship_id)
	var race: String = str(ship.get("race", "")).strip_edges().to_lower()
	if race != "":
		return race
	for t: Variant in TypedVariant.as_array(ship.get("fetter_ids", [])):
		var k: String = str(t).to_lower()
		if k in ["amarr", "caldari", "gallente", "minmatar"]:
			return k
	return ""

static func _decay_recent_hits(recent_hits: Dictionary) -> void:
	var window: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_pseudo_random_window", 3), 3))
	var keys: Array = recent_hits.keys()
	for k: Variant in keys:
		var next_value: int = TypedVariant.as_int(recent_hits.get(k, 0), 0) - 1
		if next_value <= 0:
			recent_hits.erase(k)
		else:
			recent_hits[k] = mini(next_value, window)

static func _roll_cost_tier(weights: Array) -> int:
	var total: int = 0
	for w_v: Variant in weights:
		total += TypedVariant.as_int(w_v, 0)
	if total <= 0:
		return 1
	var r: int = _randi_range(0, total - 1)
	var acc: int = 0
	for i: int in range(mini(5, weights.size())):
		acc += TypedVariant.as_int(weights[i], 0)
		if r < acc:
			return i + 1
	return 1

func try_buy(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= slots.size():
		return {"accepted": false}
	var slot: Dictionary = TypedVariant.as_dict(slots[slot_index])
	if TypedVariant.as_bool(slot.get("purchased", false), false):
		return {"accepted": false}
	var ship_id: int = TypedVariant.as_int(slot.get("ship_id", 0), 0)
	var cost: int = TypedVariant.as_int(DataStore.get_ship(ship_id).get("cost", 0), 0)
	return AdminBus.request(&"shop.purchase", {
		"slot_index": slot_index,
		"ship_id": ship_id,
		"cost": cost,
		"team": ShipUnit.TEAM_PLAYER,
	})

func _on_purchase(payload: Dictionary) -> Dictionary:
	var idx: int = TypedVariant.as_int(payload.get("slot_index", -1), -1)
	var ship_id: int = TypedVariant.as_int(payload.get("ship_id", 0), 0)
	var cost: int = TypedVariant.as_int(payload.get("cost", 0), 0)
	if idx < 0 or idx >= slots.size():
		return {"accepted": false}
	var slot_at: Dictionary = TypedVariant.as_dict(slots[idx])
	if TypedVariant.as_bool(slot_at.get("purchased", false), false):
		return {"accepted": false}
	var hangar: Vector2i = _board.find_empty_hangar(ShipUnit.TEAM_PLAYER)
	if hangar.x < 0:
		get_tree().call_group("match_root", "show_notice", "备战席已满")
		SessionDiagnostics.log("shop.buy", "fail reason=hangar_full ship=%d" % ship_id)
		return {"accepted": false, "reason_key": "hangar_full"}
	if not _match.try_spend(cost):
		get_tree().call_group("match_root", "show_notice", "黄币不足")
		SessionDiagnostics.log("shop.buy", "fail reason=no_gold ship=%d" % ship_id)
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
	SessionDiagnostics.log("shop.buy", "ok ship=%d cost=%d" % [ship_id, cost])
	return {
		"accepted": true,
		"ship_id": ship_id,
		"hangar_x": hangar.x,
		"hangar_z": hangar.y,
	}

func manual_refresh() -> void:
	refresh_shop(false)


func ensure_equipment_slots() -> void:
	if equipment_slots.is_empty():
		_roll_equipment_slots()


func _equipment_shop_slot_count() -> int:
	return maxi(1, TypedVariant.as_int(DataStore.economy.get("equipment_shop_slot_count", 5), 5))


func _equipment_pity_window() -> int:
	return maxi(1, TypedVariant.as_int(DataStore.economy.get("equipment_shop_category_pity_window", 10), 10))


func _roll_equipment_slots() -> void:
	equipment_slots.clear()
	var level: int = 1
	if _match != null:
		level = _match.player_level
	var count: int = _equipment_shop_slot_count()
	var pool: Array = DataStore.function_module_shop_pool_ids_for_level(level)
	var by_cat: Dictionary = _equipment_pool_by_category(pool)
	var force_cats: Array = _equip_pity_force_categories(by_cat, count)
	var force_ids: Array = _id_pity_force_equip_ids(pool, count)
	var force_i: int = 0
	var force_id_i: int = 0
	for _i: int in range(count):
		var pick: String = ""
		if force_id_i < force_ids.size():
			pick = str(force_ids[force_id_i])
			force_id_i += 1
		if pick == "" and force_i < force_cats.size():
			pick = _pick_equipment_from_category(str(force_cats[force_i]), by_cat)
			force_i += 1
		if pick == "":
			pick = _pick_equipment_from_pool_id_pity(pool)
		equipment_slots.append({"id": pick, "purchased": false})
	_equip_pity_record_refresh(equipment_slots, by_cat)


func _id_pity_force_equip_ids(pool: Array, slot_count: int) -> Array:
	var window: int = _id_pity_window()
	if _id_pity_refresh_count < window:
		return []
	var missing: Array = []
	for id_v: Variant in pool:
		var id_s: String = str(id_v)
		if id_s == "":
			continue
		if not TypedVariant.as_bool(_id_pity_seen_equips.get(id_s, false), false):
			missing.append(id_s)
	if missing.is_empty():
		return []
	_shuffle_det(missing)
	return missing.slice(0, mini(slot_count, missing.size()))


func _id_pity_record_equip_refresh(slots_arr: Array) -> void:
	for slot_v: Variant in slots_arr:
		if typeof(slot_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var slot: Dictionary = slot_v as Dictionary
		var eid: String = str(slot.get("id", "")).strip_edges()
		if eid != "":
			_id_pity_seen_equips[eid] = true


func _pick_equipment_from_pool_id_pity(pool: Array) -> String:
	if pool.is_empty():
		return ""
	var total: int = 0
	var weighted: Array = []
	for id_v: Variant in pool:
		var id_s: String = str(id_v)
		if id_s == "":
			continue
		var w: float = 1.0 * _id_pity_equip_weight_mul(id_s)
		var w_i: int = maxi(1, roundi(w * 100.0))
		weighted.append({"id": id_s, "weight": w_i})
		total += w_i
	if total <= 0:
		return str(pool[_randi_range(0, pool.size() - 1)])
	var roll: int = _randi_range(0, total - 1)
	var acc: int = 0
	for entry_v: Variant in weighted:
		@warning_ignore("unsafe_cast")
		var entry: Dictionary = entry_v as Dictionary
		acc += TypedVariant.as_int(entry.get("weight", 1), 1)
		if roll < acc:
			return str(entry.get("id", ""))
	if weighted.is_empty():
		return ""
	var first: Dictionary = TypedVariant.as_dict(weighted[0])
	return str(first.get("id", ""))


func _equipment_pool_by_category(pool: Array) -> Dictionary:
	var by_cat: Dictionary = {}
	for id_v: Variant in pool:
		var id_s: String = str(id_v)
		var cat: String = DataStore.function_module_shop_category(id_s)
		if cat == "":
			continue
		if not by_cat.has(cat):
			by_cat[cat] = []
		var bucket: Array = TypedVariant.as_array(by_cat[cat])
		bucket.append(id_s)
		by_cat[cat] = bucket
	return by_cat


func _equip_pity_force_categories(by_cat: Dictionary, slot_count: int) -> Array:
	## Progressive guarantee: within a window of N refreshes, every eligible category
	## must appear ≥1. Force enough missing cats so remaining refreshes can cover the rest.
	var window: int = _equipment_pity_window()
	var pos: int = _equip_pity_refresh_count % window  # 0 .. window-1
	var remaining_refreshes: int = window - pos
	var missing: Array = []
	for cat: Variant in by_cat.keys():
		if not TypedVariant.as_bool(_equip_pity_seen_cat.get(cat, false), false):
			missing.append(cat)
	if missing.is_empty():
		return []
	var later_capacity: int = maxi(0, remaining_refreshes - 1) * slot_count
	var force_n: int = maxi(0, missing.size() - later_capacity)
	force_n = mini(force_n, mini(slot_count, missing.size()))
	if force_n <= 0:
		return []
	_shuffle_det(missing)
	return missing.slice(0, force_n)


func _equip_pity_record_refresh(slots_arr: Array, by_cat: Dictionary) -> void:
	var window: int = _equipment_pity_window()
	for slot_v: Variant in slots_arr:
		if typeof(slot_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var slot: Dictionary = slot_v as Dictionary
		var cat: String = DataStore.function_module_shop_category(str(slot.get("id", "")))
		if cat != "" and by_cat.has(cat):
			_equip_pity_seen_cat[cat] = true
	_equip_pity_refresh_count += 1
	if _equip_pity_refresh_count % window == 0:
		_equip_pity_seen_cat.clear()


func _pick_equipment_from_category(cat: String, by_cat: Dictionary) -> String:
	if not by_cat.has(cat):
		return ""
	var arr: Array = TypedVariant.as_array(by_cat[cat])
	if arr.is_empty():
		return ""
	return str(arr[_randi_range(0, arr.size() - 1)])


func _pick_equipment_from_pool(pool: Array) -> String:
	if pool.is_empty():
		return ""
	return str(pool[_randi_range(0, pool.size() - 1)])


func try_buy_equipment(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= equipment_slots.size():
		return
	var slot: Dictionary = TypedVariant.as_dict(equipment_slots[slot_index])
	if TypedVariant.as_bool(slot.get("purchased", false), false):
		return
	var item_id: String = str(slot.get("id", ""))
	if item_id == "":
		return
	var mod: Dictionary = DataStore.get_function_module(item_id)
	if mod.is_empty():
		return
	var cost: int = TypedVariant.as_int(mod.get("cost", 10), 10)
	AdminBus.request(&"shop.equipment_purchase", {
		"slot_index": slot_index,
		"item_id": item_id,
		"cost": cost,
		"team": ShipUnit.TEAM_PLAYER,
	})


func _on_equipment_purchase(payload: Dictionary) -> Dictionary:
	var idx: int = TypedVariant.as_int(payload.get("slot_index", -1), -1)
	var item_id: String = str(payload.get("item_id", ""))
	var cost: int = TypedVariant.as_int(payload.get("cost", 0), 0)
	if idx < 0 or idx >= equipment_slots.size():
		return {"accepted": false}
	var slot_at: Dictionary = TypedVariant.as_dict(equipment_slots[idx])
	if TypedVariant.as_bool(slot_at.get("purchased", false), false):
		return {"accepted": false}
	if item_id == "" or DataStore.get_function_module(item_id).is_empty():
		return {"accepted": false}
	if _match == null or not _match.has_method("find_empty_equipment_inventory_slot"):
		return {"accepted": false}
	if _match.find_empty_equipment_inventory_slot() < 0:
		get_tree().call_group("match_root", "show_notice", "装备背包已满")
		SessionDiagnostics.log("shop.equipment_buy", "fail reason=bag_full item=%s" % item_id)
		return {"accepted": false, "reason_key": "equipment_bag_full"}
	if not _match.try_spend(cost):
		get_tree().call_group("match_root", "show_notice", "黄币不足")
		SessionDiagnostics.log("shop.equipment_buy", "fail reason=no_gold item=%s" % item_id)
		return {"accepted": false, "reason_key": "no_gold"}
	if not _match.add_equipment_to_inventory(item_id):
		get_tree().call_group("match_root", "show_notice", "装备背包已满")
		return {"accepted": false, "reason_key": "equipment_bag_full"}
	equipment_slots[idx]["purchased"] = true
	shop_changed.emit()
	if _match and _match.has_method("request_autosave"):
		_match.request_autosave()
	SessionDiagnostics.log("shop.equipment_buy", "ok item=%s cost=%d" % [item_id, cost])
	return {"accepted": true}
