extends Node
class_name AiController
## AI is a rule-following player: same economy/shop/hangar with income ×2 buff.
## Weight files: WeightDrivenAi (farm stays in EVEautochessAI-main). Unloaded → §2.

var _board: BoardController
var _match: MatchController
var endless: bool = false
var weight_policy: OnnxCpuPolicy = OnnxCpuPolicy.new()

var ai_gold: int = 0
var ai_level: int = 1
var ai_exp: int = 0
var up_level_demand: int = 4
var win_streak: int = 0
var loss_streak: int = 0
var shop_slots: Array = []  # {ship_id, purchased}
## Independent of player shop/bag (AI_PLAYER_HANDBOOK §2.8).
var equipment_slots: Array = []  # {id, purchased}
var equipment_inventory: Array = []  # 16 × item id or ""
var _recent_shop_hits: Dictionary = {}
var _pity_refresh_count: int = 0
var _pity_seen_tonnage: Dictionary = {}
var _equip_pity_refresh_count: int = 0
var _equip_pity_seen_cat: Dictionary = {}
var _id_pity_refresh_count: int = 0
var _id_pity_seen_ships: Dictionary = {}
var _id_pity_seen_equips: Dictionary = {}
## Cells AI has already deployed onto this match ("x,z"); prefer fresh cells each place/reshuffle.
var _used_field_cells: Dictionary = {}
## Prepare-sliced Shop loop (handbook §0.2): infer off main thread.
var _eco_active: bool = false
var _eco_guard: int = 0
var _eco_task_id: int = -1
var _eco_busy: bool = false
var _eco_ignore_id: int = -1
var _eco_logits: PackedFloat32Array = PackedFloat32Array()
var _eco_obs: PackedFloat32Array = PackedFloat32Array()
var _eco_filtered: Array = []
var _eco_actions: int = 0
var _onnx_shop_prepare: bool = false
const ECO_MODE_ONNX: String = "onnx"
const ECO_MODE_LIMITED: String = "limited"
const ECO_WORKER_TIMEOUT_MS: int = 2000
const ECO_DISPATCH_FAIL_MAX: int = 3
const _SHOP_SNAP_NET_LIST: Array[String] = ["match_global", "ops", "shop"]
var _eco_mode: String = ECO_MODE_ONNX
var _eco_fail_streak: int = 0
var _eco_worker_started_msec: int = 0
static var _worker_logits: PackedFloat32Array = PackedFloat32Array()


func bind(match_ctrl: MatchController, board: BoardController) -> void:
	_match = match_ctrl
	_board = board
	add_to_group("ai_controller")
	AdminBus.register_handler(&"ai.deploy_ship", _on_deploy)
	AdminBus.after_handoff.connect(_on_after)
	weight_policy.try_autoload()
	_log_onnx_load("bind")


func reload_weight_policy() -> bool:
	if weight_policy == null:
		weight_policy = OnnxCpuPolicy.new()
	var ok: bool = weight_policy.try_autoload()
	_log_onnx_load("reload")
	return ok


func eco_mode_label() -> String:
	return _eco_mode


func onnx_load_detail() -> Dictionary:
	if weight_policy == null:
		return {}
	return weight_policy.load_status_detail()


func _log_onnx_load(tag: String) -> void:
	if weight_policy == null:
		SessionDiagnostics.log_critical("ai.onnx.load", "tag=%s policy=null" % tag)
		return
	var d: Dictionary = weight_policy.load_status_detail()
	SessionDiagnostics.log_critical(
		"ai.onnx.load",
		"tag=%s ready=%d loaded=%d/%d hash=%s fallback=%d %s" % [
			tag,
			TypedVariant.as_int(d.get("ready", 0), 0),
			TypedVariant.as_int(d.get("loaded", 0), 0),
			TypedVariant.as_int(d.get("total", 6), 6),
			str(d.get("hash", "")),
			TypedVariant.as_int(d.get("fallback_ready", 0), 0),
			SessionDiagnostics.mem_detail(),
		]
	)


func _uses_onnx_eco() -> bool:
	return _eco_mode == ECO_MODE_ONNX and _policy_nets_live()


func _is_first_prepare() -> bool:
	return _match != null and _match.battle_game_stage_count == 0


func _enter_limited_eco(reason: String) -> void:
	if _eco_mode == ECO_MODE_LIMITED:
		return
	cancel_economy_work()
	_eco_mode = ECO_MODE_LIMITED
	_onnx_shop_prepare = false
	_eco_fail_streak = 0
	SessionDiagnostics.log_critical(
		"ai.onnx.fallback",
		"reason=%s mode=%s %s" % [reason, str(_match.mode) if _match else "", SessionDiagnostics.mem_detail()]
	)
	if reason == "worker_timeout":
		SessionDiagnostics.log_critical("ai.onnx.worker_timeout", "ms=%d" % ECO_WORKER_TIMEOUT_MS)


func _policy_nets_live() -> bool:
	return weight_policy != null and weight_policy.nets_ready()


func _ai_titan_id() -> String:
	if _board == null:
		return "caldari"
	var race: String = _board.titan_fetter_race(ShipUnit.TEAM_AI)
	if race.is_empty():
		return "caldari"
	return race

func init_economy() -> void:
	## Seat opening only — no shopping. Nullsec builds the rival hulls per PVP round.
	cancel_economy_work()
	endless = _match.mode == "endless"
	var eco: Dictionary = DataStore.economy
	ai_gold = TypedVariant.as_int(eco.get("base_gold", 5), 5)
	ai_level = 1
	ai_exp = 0
	up_level_demand = TypedVariant.as_int(eco.get("initial_level_exp_demand", 4), 4)
	win_streak = 0
	loss_streak = 0
	_ensure_equipment_inventory()
	equipment_slots.clear()
	_used_field_cells.clear()
	_refresh_shop()

func init_army() -> void:
	init_economy()
	_run_economy_turn()

func rebuild_round_army() -> void:
	## Nullsec PVP draws a different rival every round, so the hulls are rebuilt from
	## scratch — but out of the seat's accumulated level/gold, never a fresh level-1
	## opening (MULTIPLAYER_MATCH_FLOW §5.0: 人机玩家与真人同套).
	cancel_economy_work()
	_used_field_cells.clear()
	_refresh_shop()
	_run_economy_turn()

func after_round() -> void:
	_grant_exp(TypedVariant.as_int(DataStore.economy.get("base_exp_income", 4), 4))
	if _match.mode == "nullsec":
		## Hulls bought here would be wiped when the next round's board is authored, so
		## the seat only banks gold/exp and spends it when it is actually the rival.
		return
	_used_field_cells.clear()
	_refresh_shop()
	_run_economy_turn()

func population_limit() -> int:
	return mini(
		ai_level + TypedVariant.as_int(DataStore.board.get("ship_count_buff", 0), 0),
		TypedVariant.as_int(DataStore.board.get("max_deployment", 999), 999)
	)

func field_cap() -> int:
	## min(AI pop, floor(player pop × 2.0))
	var ai_pop: int = maxi(1, population_limit())
	## Nullsec seats use their own population, same as humans: the asymmetric cap below
	## is 1v1 Versus only (MULTIPLAYER_MATCH_FLOW §5.0).
	if _match and _match.mode == "nullsec":
		return ai_pop
	var player_pop: int = maxi(1, _match.population_limit())
	var mult: float = TypedVariant.as_float(DataStore.ai.get("field_cap_vs_player_pop", 2.0), 2.0)
	var vs_player: int = maxi(1, floori(float(player_pop) * mult))
	return mini(ai_pop, vs_player)

func update_streaks(won: bool) -> void:
	if won:
		win_streak += 1
		loss_streak = 0
	else:
		loss_streak += 1
		win_streak = 0

func apply_income(won: bool, kills: int) -> void:
	## Prefer MatchController stop_combat dual grant; this path is fallback for solo AI tests.
	if _match != null and _match.has_method("_apply_income"):
		_match._apply_income(ShipUnit.TEAM_AI, won, kills)
		return
	var eco: Dictionary = DataStore.economy
	var interest: int = floori(float(ai_gold) / TypedVariant.as_float(eco.get("interest_divisor", 10), 10.0))
	var cap: int = TypedVariant.as_int(eco.get("interest_cap", 5), 5)
	if TypedVariant.as_bool(eco.get("interest_capped", true), true):
		interest = mini(interest, cap)
	var base: int = _match._base_income_for_round() if _match.has_method("_base_income_for_round") else TypedVariant.as_int(eco.get("base_gold_income", 5), 5)
	var win_g: int = TypedVariant.as_int(eco.get("win_gold", 1), 1) if won else 0
	var streak_g: int = 0
	if won:
		streak_g = _match._streak_bonus(win_streak) if _match.has_method("_streak_bonus") else 0
	var kill_g: int = kills * TypedVariant.as_int(eco.get("kill_gold_per_ship", 1), 1)
	var mining_g: int = _match._mining_gold_for_team(ShipUnit.TEAM_AI) if _match.has_method("_mining_gold_for_team") else 0
	var income: int = base + interest + win_g + streak_g + kill_g + mining_g
	var mul: float = TypedVariant.as_float(DataStore.ai.get("ai_gold_income_buff_mul", 2.0), 2.0)
	var combat_part: int = income - mining_g
	income = roundi(float(combat_part) * mul) + mining_g
	ai_gold += income

func add_gold(amount: int) -> void:
	ai_gold += amount

func _grant_exp(amount: int) -> void:
	ai_exp += amount
	var eco: Dictionary = DataStore.economy
	var inc: int = TypedVariant.as_int(eco.get("level_exp_demand_increment", 8), 8)
	while ai_exp >= up_level_demand:
		ai_exp -= up_level_demand
		ai_level += 1
		up_level_demand += inc

func _refresh_shop() -> void:
	var prev_stream: String = ShopController._auth_stream
	ShopController._auth_stream = "shop_ai"
	var n: int = TypedVariant.as_int(DataStore.economy.get("shop_slot_count", 6), 6)
	ShopController._decay_recent_hits(_recent_shop_hits)
	shop_slots.clear()
	var seen_counts: Dictionary = {}
	var force_tonnages: Array = []
	var window: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_tonnage_pity_window", 5), 5))
	if _pity_refresh_count >= window:
		for key: Variant in ShopController._unlocked_tonnage_keys(ai_level):
			if not TypedVariant.as_bool(_pity_seen_tonnage.get(key, false), false):
				force_tonnages.append(key)
	var id_window: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_id_pity_window", 30), 30))
	var force_ids: Array = []
	if _id_pity_refresh_count >= id_window:
		var eligible: Array = ShopController._eligible_ship_ids_for_level(ai_level, DataStore.ship_ids())
		for sid_v: Variant in eligible:
			var sid_m: int = TypedVariant.as_int(sid_v, 0)
			if not ShopController.ship_participates_shop_pity(sid_m):
				continue
			if not TypedVariant.as_bool(_id_pity_seen_ships.get(sid_m, false), false):
				force_ids.append(sid_m)
		force_ids.shuffle()
		if force_ids.size() > n:
			force_ids = force_ids.slice(0, n)
	var force_i: int = 0
	var force_id_i: int = 0
	var max_same: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_max_same_ship_per_refresh", 2), 2))
	for i: int in range(n):
		var sid: int = 0
		if force_id_i < force_ids.size():
			sid = TypedVariant.as_int(force_ids[force_id_i], 0)
			force_id_i += 1
			if TypedVariant.as_int(seen_counts.get(sid, 0), 0) >= max_same:
				sid = 0
		if sid <= 0 and force_i < force_tonnages.size():
			## Reuse player shop helper via temporary ShopController statics.
			var pool: Array = []
			var eligible2: Array = ShopController._eligible_ship_ids_for_level(ai_level, DataStore.ship_ids())
			var want: String = str(force_tonnages[force_i])
			force_i += 1
			for cand: Variant in eligible2:
				var cid: int = TypedVariant.as_int(cand, 0)
				if not ShopController.ship_participates_shop_pity(cid):
					continue
				if TypedVariant.as_int(seen_counts.get(cid, 0), 0) >= max_same:
					continue
				if ShopController.ship_tonnage_key(cid) == want:
					pool.append(cid)
			if not pool.is_empty():
				sid = _ai_pick_ship_id_pity(pool)
		if sid <= 0:
			sid = _roll_ship_id(seen_counts)
		seen_counts[sid] = TypedVariant.as_int(seen_counts.get(sid, 0), 0) + 1
		_recent_shop_hits[sid] = TypedVariant.as_int(_recent_shop_hits.get(sid, 0), 0) + 1
		shop_slots.append({"ship_id": sid, "purchased": false})
	if _pity_refresh_count >= window:
		_pity_refresh_count = 0
		_pity_seen_tonnage.clear()
	for slot: Variant in shop_slots:
		var slot_dict: Dictionary = TypedVariant.as_dict(slot)
		var sid_rec: int = TypedVariant.as_int(slot_dict.get("ship_id", 0), 0)
		if not ShopController.ship_participates_shop_pity(sid_rec):
			continue
		var key: String = ShopController.ship_tonnage_key(sid_rec)
		if key != "":
			_pity_seen_tonnage[key] = true
	_pity_refresh_count += 1
	## Capture equip force list before ID-pity window reset.
	var force_equip_ids: Array = []
	if _id_pity_refresh_count >= id_window:
		var epool: Array = DataStore.function_module_shop_pool_ids_for_level(ai_level)
		for id_v: Variant in epool:
			var id_s: String = str(id_v)
			if id_s != "" and ShopController.equip_participates_shop_pity(id_s) and not TypedVariant.as_bool(_id_pity_seen_equips.get(id_s, false), false):
				force_equip_ids.append(id_s)
		force_equip_ids.shuffle()
	if _id_pity_refresh_count >= id_window:
		_id_pity_refresh_count = 0
		_id_pity_seen_ships.clear()
		_id_pity_seen_equips.clear()
	for slot2: Variant in shop_slots:
		var sd2: Dictionary = TypedVariant.as_dict(slot2)
		var sid2: int = TypedVariant.as_int(sd2.get("ship_id", 0), 0)
		if sid2 > 0 and ShopController.ship_participates_shop_pity(sid2):
			_id_pity_seen_ships[sid2] = true
	_id_pity_refresh_count += 1
	_roll_equipment_shop(force_equip_ids)
	ShopController._auth_stream = prev_stream


func _ai_pick_ship_id_pity(pool: Array) -> int:
	if pool.is_empty():
		return 0
	var pr_window: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_pseudo_random_window", 3), 3))
	var race_mul: float = TypedVariant.as_float(DataStore.economy.get("titan_shop_race_weight_mul", 1.1), 1.1)
	var want_race: String = _ai_titan_race().strip_edges().to_lower()
	var total: int = 0
	var weighted: Array = []
	for sid_v: Variant in pool:
		var sid_i: int = TypedVariant.as_int(sid_v, 0)
		var recent: int = TypedVariant.as_int(_recent_shop_hits.get(sid_i, 0), 0)
		var weight: float = float(maxi(1, pr_window + 1 - recent))
		if want_race != "" and ShopController._ship_race_key(sid_i) == want_race:
			weight *= race_mul
		if ShopController.ship_participates_shop_pity(sid_i) and not TypedVariant.as_bool(_id_pity_seen_ships.get(sid_i, false), false):
			weight *= 1.0 + float(_id_pity_refresh_count)
		var w_i: int = maxi(1, roundi(weight * 100.0))
		weighted.append({"ship_id": sid_i, "weight": w_i})
		total += w_i
	if total <= 0:
		return TypedVariant.as_int(pool[randi() % pool.size()], 0)
	var roll: int = randi() % total
	var acc: int = 0
	for entry_v: Variant in weighted:
		var entry: Dictionary = TypedVariant.as_dict(entry_v)
		acc += TypedVariant.as_int(entry.get("weight", 1), 1)
		if roll < acc:
			return TypedVariant.as_int(entry.get("ship_id", 0), 0)
	return TypedVariant.as_int(pool[0], 0)


func _ensure_equipment_inventory() -> void:
	var n: int = 16
	if _match != null:
		n = int(_match.EQUIPMENT_INVENTORY_SIZE)
	while equipment_inventory.size() < n:
		equipment_inventory.append("")
	if equipment_inventory.size() > n:
		equipment_inventory.resize(n)


func _roll_equipment_shop(force_ids: Array = []) -> void:
	equipment_slots.clear()
	var count: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("equipment_shop_slot_count", 4), 4))
	var window: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("equipment_shop_category_pity_window", 10), 10))
	var pool: Array = DataStore.function_module_shop_pool_ids_for_level(ai_level)
	var by_cat: Dictionary = {}
	for id: Variant in pool:
		var cat: String = DataStore.function_module_shop_category(str(id))
		if cat == "":
			continue
		if not by_cat.has(cat):
			by_cat[cat] = []
		var cat_arr: Array = TypedVariant.as_array(by_cat[cat])
		cat_arr.append(str(id))
		by_cat[cat] = cat_arr
	var pos: int = _equip_pity_refresh_count % window
	var remaining_refreshes: int = window - pos
	var missing: Array = []
	for cat: Variant in by_cat.keys():
		var cat_s: String = str(cat)
		var has_pity: bool = false
		for id_v: Variant in TypedVariant.as_array(by_cat[cat_s]):
			if ShopController.equip_participates_shop_pity(str(id_v)):
				has_pity = true
				break
		if not has_pity:
			continue
		if not TypedVariant.as_bool(_equip_pity_seen_cat.get(cat_s, false), false):
			missing.append(cat_s)
	var force_cats: Array = []
	if not missing.is_empty():
		var later_capacity: int = maxi(0, remaining_refreshes - 1) * count
		var force_n: int = maxi(0, missing.size() - later_capacity)
		force_n = mini(force_n, mini(count, missing.size()))
		if force_n > 0:
			missing.shuffle()
			force_cats = missing.slice(0, force_n)
	var use_force_ids: Array = force_ids.duplicate()
	if use_force_ids.size() > count:
		use_force_ids = use_force_ids.slice(0, count)
	var force_i: int = 0
	var force_id_i: int = 0
	for _i: int in range(count):
		var pick: String = ""
		if force_id_i < use_force_ids.size():
			pick = str(use_force_ids[force_id_i])
			force_id_i += 1
		if pick == "" and force_i < force_cats.size():
			var cat2: String = str(force_cats[force_i])
			force_i += 1
			var arr: Array = TypedVariant.as_array(by_cat.get(cat2, []))
			var pity_arr: Array = []
			for id_c: Variant in arr:
				if ShopController.equip_participates_shop_pity(str(id_c)):
					pity_arr.append(str(id_c))
			var pick_arr: Array = pity_arr if not pity_arr.is_empty() else arr
			if not pick_arr.is_empty():
				pick = str(pick_arr[randi() % pick_arr.size()])
		if pick == "" and not pool.is_empty():
			var total: int = 0
			var weighted: Array = []
			for pid_v: Variant in pool:
				var pid: String = str(pid_v)
				var w: float = 1.0
				if ShopController.equip_participates_shop_pity(pid) and not TypedVariant.as_bool(_id_pity_seen_equips.get(pid, false), false):
					w *= 1.0 + float(maxi(0, _id_pity_refresh_count - 1))
				var wi: int = maxi(1, roundi(w * 100.0))
				weighted.append({"id": pid, "weight": wi})
				total += wi
			var roll: int = randi() % maxi(1, total)
			var acc: int = 0
			for ev: Variant in weighted:
				var ed: Dictionary = TypedVariant.as_dict(ev)
				acc += TypedVariant.as_int(ed.get("weight", 1), 1)
				if roll < acc:
					pick = str(ed.get("id", ""))
					break
			if pick == "":
				pick = str(pool[randi() % pool.size()])
		equipment_slots.append({"id": pick, "purchased": false})
		if pick != "" and ShopController.equip_participates_shop_pity(pick):
			var seen_cat: String = DataStore.function_module_shop_category(pick)
			if seen_cat != "" and by_cat.has(seen_cat):
				_equip_pity_seen_cat[seen_cat] = true
			_id_pity_seen_equips[pick] = true
	_equip_pity_refresh_count += 1
	if _equip_pity_refresh_count % window == 0:
		_equip_pity_seen_cat.clear()


func _find_empty_equipment_inv() -> int:
	_ensure_equipment_inventory()
	for i: int in range(equipment_inventory.size()):
		if str(equipment_inventory[i]).strip_edges() == "":
			return i
	return -1


func add_equipment_to_inventory(item_id: String) -> bool:
	var mid: String = str(item_id).strip_edges()
	if mid == "":
		return false
	var bag: int = _find_empty_equipment_inv()
	if bag < 0:
		return false
	equipment_inventory[bag] = mid
	return true


func _random_buy_equipment() -> void:
	if equipment_slots.is_empty():
		_roll_equipment_shop()
	_ensure_equipment_inventory()
	var chance: float = TypedVariant.as_float(DataStore.ai.get("ai_equipment_buy_chance", 0.55), 0.55)
	var max_buys: int = TypedVariant.as_int(DataStore.ai.get("ai_equipment_max_buys_per_turn", 3), 3)
	var order: Array = []
	for i: int in range(equipment_slots.size()):
		order.append(i)
	order.shuffle()
	var buys: int = 0
	for idx_v: Variant in order:
		if buys >= max_buys:
			break
		var idx: int = TypedVariant.as_int(idx_v, 0)
		var slot: Dictionary = TypedVariant.as_dict(equipment_slots[idx])
		if TypedVariant.as_bool(slot.get("purchased", false), false):
			continue
		if randf() > chance:
			continue
		var item_id: String = str(slot.get("id", "")).strip_edges()
		if item_id == "":
			continue
		var mod: Dictionary = DataStore.get_function_module(item_id)
		if mod.is_empty() or TypedVariant.as_bool(mod.get("implant", false), false):
			continue
		var cost: int = TypedVariant.as_int(mod.get("cost", 10), 10)
		if ai_gold < cost:
			continue
		var bag: int = _find_empty_equipment_inv()
		if bag < 0:
			break
		ai_gold -= cost
		equipment_slots[idx]["purchased"] = true
		equipment_inventory[bag] = item_id
		buys += 1
	if buys > 0:
		SessionDiagnostics.log("ai.equipment_buy", "buys=%d gold=%d" % [buys, ai_gold])


func _random_distribute_equipment() -> void:
	if _board == null:
		return
	_ensure_equipment_inventory()
	var ships: Array = []
	for s: ShipUnit in _board.all_ships():
		if s == null or not is_instance_valid(s):
			continue
		if s.team_id != ShipUnit.TEAM_AI:
			continue
		if str(s.slot_type) != "field":
			continue
		if s.is_unmanned:
			continue
		var sd: Dictionary = DataStore.get_ship(s.ship_id)
		if not FunctionFit.ship_allows_function_fit(sd):
			continue
		if s.get_function_fit().size() >= FunctionFit.MAX_SLOTS:
			continue
		ships.append(s)
	if ships.is_empty():
		return
	var inv_order: Array = []
	for i: int in range(equipment_inventory.size()):
		if str(equipment_inventory[i]).strip_edges() != "":
			inv_order.append(i)
	inv_order.shuffle()
	var fitted: int = 0
	for idx_v: Variant in inv_order:
		var inv_i: int = TypedVariant.as_int(idx_v, 0)
		var item_id: String = str(equipment_inventory[inv_i]).strip_edges()
		if item_id == "":
			continue
		ships.shuffle()
		for s_any: Variant in ships:
			if not (s_any is ShipUnit):
				continue
			var s: ShipUnit = s_any
			if s == null or not is_instance_valid(s):
				continue
			if s.get_function_fit().size() >= FunctionFit.MAX_SLOTS:
				continue
			var res: Dictionary = s.try_fit_function_module(item_id)
			if TypedVariant.as_bool(res.get("ok", false), false):
				equipment_inventory[inv_i] = ""
				fitted += 1
				SessionDiagnostics.log(
					"ai.decide",
					"net=fit item=%s ship=%d ok=true" % [item_id, s.ship_id]
				)
				break
	if fitted > 0:
		SessionDiagnostics.log("ai.equipment_fit", "fitted=%d" % fitted)


func _roll_ship_id(seen_counts: Dictionary = {}) -> int:
	## Prefer ID-pity weighted pick from a full eligible tier roll.
	var sid: int = ShopController.roll_ship_id_for_level(
		ai_level, _match.battle_game_stage_count, seen_counts, _recent_shop_hits, _ai_titan_race()
	)
	## Soft reweight: if unseen pity hull, occasionally swap toward an unseen eligible.
	## Mod hulls without shop_pity are never soft-forced (MODS §3.2).
	if sid > 0 and (
		not ShopController.ship_participates_shop_pity(sid)
		or not TypedVariant.as_bool(_id_pity_seen_ships.get(sid, false), false)
	):
		return sid
	var eligible: Array = ShopController._eligible_ship_ids_for_level(ai_level, DataStore.ship_ids())
	var unseen: Array = []
	var max_same: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("shop_max_same_ship_per_refresh", 2), 2))
	for sid_v: Variant in eligible:
		var s: int = TypedVariant.as_int(sid_v, 0)
		if not ShopController.ship_participates_shop_pity(s):
			continue
		if TypedVariant.as_int(seen_counts.get(s, 0), 0) >= max_same:
			continue
		if not TypedVariant.as_bool(_id_pity_seen_ships.get(s, false), false):
			unseen.append(s)
	if unseen.is_empty():
		return sid
	## Weight ramp: higher chance to pick unseen as window progresses.
	var chance: float = clampf(float(_id_pity_refresh_count) / 30.0, 0.0, 0.85)
	if randf() < chance:
		return _ai_pick_ship_id_pity(unseen)
	return sid


## Rival seat titan in nullsec PVP; empty for PVE creeps / versus (no titan shop boost).
func _ai_titan_race() -> String:
	if _board == null:
		return ""
	return _board.titan_fetter_race(ShipUnit.TEAM_AI)

func _run_economy_turn() -> void:
	begin_economy_turn()


func begin_economy_turn() -> void:
	if not TypedVariant.as_bool(DataStore.ai.get("uses_shop_economy", true), true):
		_deploy_legacy_quota()
		return
	if _eco_busy and _eco_task_id >= 0 and not WorkerThreadPool.is_task_completed(_eco_task_id):
		_eco_ignore_id = _eco_task_id
	_eco_active = true
	_eco_guard = 40
	_eco_actions = 0
	_eco_filtered = []
	_eco_fail_streak = 0
	if _is_first_prepare():
		_eco_mode = ECO_MODE_LIMITED
		_onnx_shop_prepare = false
		_eco_guard = 1
		SessionDiagnostics.log("ai.onnx.fallback", "reason=first_prepare_round")
		return
	if _policy_nets_live():
		_eco_mode = ECO_MODE_ONNX
		_onnx_shop_prepare = true
	else:
		_eco_mode = ECO_MODE_LIMITED
		_onnx_shop_prepare = false
		SessionDiagnostics.log("ai.onnx.fallback", "reason=load_not_ready phase=begin_economy")


func is_economy_busy() -> bool:
	return _eco_active or _eco_busy


func cancel_economy_work() -> void:
	_eco_active = false
	if _eco_task_id >= 0:
		if not WorkerThreadPool.is_task_completed(_eco_task_id):
			WorkerThreadPool.wait_for_task_completion(_eco_task_id)
		_eco_task_id = -1
	_eco_busy = false


func force_finish_economy() -> void:
	if not _eco_active and not _eco_busy:
		return
	if _eco_busy and _eco_task_id >= 0:
		_eco_ignore_id = _eco_task_id
	_eco_active = false
	_eco_busy = false
	_finish_economy_apply()
	if _board != null:
		var on_field: int = _board.count_field(ShipUnit.TEAM_AI)
		var hangar_n: int = _count_ai_hangar()
		if on_field <= 0 and hangar_n > 0:
			sync_field_for_prepare()
			SessionDiagnostics.log_critical(
				"ai.deploy.guarantee",
				"field=%d hangar=%d %s" % [on_field, hangar_n, SessionDiagnostics.mem_detail()]
			)


func tick_economy_turn() -> bool:
	if not _eco_active and not _eco_busy:
		return false
	if _eco_mode == ECO_MODE_LIMITED or not _policy_nets_live():
		return _tick_legacy_economy()
	return _tick_onnx_economy()


func _tick_legacy_economy() -> bool:
	if not _eco_active:
		return false
	if _eco_guard <= 0 or not _try_buy_one():
		_eco_active = false
		_finish_economy_apply()
		return true
	_eco_guard -= 1
	_eco_actions += 1
	return false


func _tick_onnx_economy() -> bool:
	if _eco_busy:
		if _eco_task_id < 0 or not WorkerThreadPool.is_task_completed(_eco_task_id):
			if Time.get_ticks_msec() - _eco_worker_started_msec > ECO_WORKER_TIMEOUT_MS:
				_enter_limited_eco("worker_timeout")
				if _eco_active:
					return _tick_legacy_economy()
			return false
		WorkerThreadPool.wait_for_task_completion(_eco_task_id)
		var tid: int = _eco_task_id
		_eco_task_id = -1
		_eco_busy = false
		if tid == _eco_ignore_id:
			_eco_ignore_id = -1
			if not _eco_active:
				return false
			return false
		if not _eco_active:
			return false
		_eco_logits = _worker_logits.duplicate()
		var infer_usec: int = maxi(0, Time.get_ticks_msec() - _eco_worker_started_msec)
		SessionDiagnostics.log(
			"ai.onnx.infer_done",
			"logits=%d usec=%d task=%d" % [_eco_logits.size(), infer_usec * 1000, tid]
		)
		if _eco_logits.is_empty():
			_enter_limited_eco("empty_logits")
			if _eco_active:
				return _tick_legacy_economy()
			return false
		var ok: bool = _dispatch_shop_policy(_eco_logits, _eco_obs, _eco_filtered, ECO_MODE_ONNX)
		_eco_actions += 1
		if not ok:
			_eco_fail_streak += 1
			if _eco_fail_streak >= ECO_DISPATCH_FAIL_MAX:
				_enter_limited_eco("dispatch_fail")
				if _eco_active:
					return _tick_legacy_economy()
		else:
			_eco_fail_streak = 0
		if _eco_guard <= 0:
			_eco_active = false
			_finish_economy_apply()
			return true
		if not ok:
			return false
		return false
	if not _eco_active:
		return false
	if _eco_guard <= 0:
		_eco_active = false
		_finish_economy_apply()
		return true
	if InMatchSlowLearn.has_slice_work():
		return false
	return _kick_eco_worker()


func _kick_eco_worker() -> bool:
	if _eco_busy or not _eco_active or weight_policy == null:
		return false
	var filtered: Array = _collect_shop_legal()
	if filtered.is_empty():
		_eco_active = false
		_finish_economy_apply()
		return true
	_eco_guard -= 1
	_eco_filtered = filtered
	var ctx: Dictionary = _policy_obs_ctx().duplicate(true)
	var snap: Dictionary = weight_policy.snapshot_for_infer(PackedStringArray(_SHOP_SNAP_NET_LIST))
	var snap_nets: Dictionary = TypedVariant.as_dict(snap.get("nets", {}))
	if snap_nets.is_empty():
		_enter_limited_eco("empty_snapshot")
		return false
	_eco_obs = PolicyObs.encode_shop_from_snapshot(snap, ctx)
	_worker_logits = PackedFloat32Array()
	_eco_busy = true
	_eco_worker_started_msec = Time.get_ticks_msec()
	_eco_task_id = WorkerThreadPool.add_task(_shop_infer_task.bind(snap, _eco_obs))
	SessionDiagnostics.log(
		"ai.onnx.infer_begin",
		"legal=%d task=%d %s" % [filtered.size(), _eco_task_id, SessionDiagnostics.mem_detail()]
	)
	return false


static func _shop_infer_task(snap: Dictionary, obs: PackedFloat32Array) -> void:
	_worker_logits = OnnxCpuPolicy.infer_shop_logits(snap, obs)


func _finish_economy_apply() -> void:
	sync_field_for_prepare()
	if _is_first_prepare():
		return
	if not _uses_onnx_eco():
		_random_buy_equipment()
		_random_distribute_equipment()


func _collect_shop_legal() -> Array:
	var seat_state: Dictionary = _seat_state_for_legal()
	var legal: Array = LegalActions.list_legal_actions("prepare", seat_state)
	var filtered: Array = []
	for la_v: Variant in legal:
		var la: Dictionary = TypedVariant.as_dict(la_v)
		var at: String = LegalActions.action_type_of(la)
		if at == "prepare_commit":
			continue
		if at == "shop_buy_equip":
			var ei: int = TypedVariant.as_int(la.get("slot_index", -1), -1)
			if ei < 0 or ei >= equipment_slots.size():
				continue
			var es: Dictionary = TypedVariant.as_dict(equipment_slots[ei])
			var item_id: String = str(es.get("id", "")).strip_edges()
			if item_id == "":
				continue
			var mod: Dictionary = DataStore.get_function_module(item_id)
			if mod.is_empty() or TypedVariant.as_bool(mod.get("implant", false), false):
				continue
		filtered.append(la)
	return filtered

func _seat_state_for_legal() -> Dictionary:
	var hangar: Vector2i = Vector2i(-1, -1)
	if _board != null:
		hangar = _board.find_empty_hangar(ShipUnit.TEAM_AI)
	var on_field: int = 0
	if _board != null:
		on_field = _board.count_field(ShipUnit.TEAM_AI)
	var bag_free: bool = false
	for id_v: Variant in equipment_inventory:
		if str(id_v) == "":
			bag_free = true
			break
	return {
		"seat_id": -1,
		"gold": ai_gold,
		"hangar_free": hangar.x >= 0,
		"field_free": on_field < field_cap(),
		"bag_free": bag_free,
		"shop_slots": shop_slots,
		"equipment_slots": equipment_slots,
		"refresh_cost": TypedVariant.as_int(DataStore.economy.get("refresh_cost", 2), 2),
		"buy_exp_cost": TypedVariant.as_int(DataStore.economy.get("buy_exp_gold_cost", 4), 4),
		"can_prepare_commit": false,
		"level_capped": false,
	}


func apply_protocol_economy(action: Dictionary) -> Dictionary:
	## Handbook §0.2: ONNX/LLM shop/exp spend ai_gold and AI hangar, never player shop.
	var at: String = LegalActions.action_type_of(action)
	if at == "shop_buy_ship":
		var si: int = TypedVariant.as_int(action.get("slot_index", -1), -1)
		if not _buy_ai_shop_slot(si):
			return {"accepted": false, "reason_key": "buy_failed"}
		return {"accepted": true}
	if at == "shop_buy_equip":
		var ei: int = TypedVariant.as_int(action.get("slot_index", -1), -1)
		if not _buy_ai_equip_slot(ei):
			return {"accepted": false, "reason_key": "buy_failed"}
		return {"accepted": true}
	if at == "shop_refresh":
		var free: bool = TypedVariant.as_bool(action.get("free", false), false)
		var rc: int = TypedVariant.as_int(DataStore.economy.get("refresh_cost", 2), 2)
		if not free:
			if ai_gold < rc:
				return {"accepted": false, "reason_key": "no_gold"}
			ai_gold -= rc
		_refresh_shop()
		return {"accepted": true}
	if at == "buy_exp":
		var ec: int = TypedVariant.as_int(DataStore.economy.get("buy_exp_gold_cost", 4), 4)
		if ai_gold < ec:
			return {"accepted": false, "reason_key": "no_gold"}
		ai_gold -= ec
		_grant_exp(TypedVariant.as_int(DataStore.economy.get("buy_exp_amount", 4), 4))
		return {"accepted": true}
	return {"accepted": false, "reason_key": "not_economy"}


func _try_policy_economy_action() -> bool:
	var filtered: Array = _collect_shop_legal()
	if filtered.is_empty():
		return false
	var obs: PackedFloat32Array = PolicyObs.encode_shop(weight_policy, _policy_obs_ctx())
	var logits: PackedFloat32Array = weight_policy.infer_logits("shop", obs)
	return _dispatch_shop_policy(logits, obs, filtered)


func _dispatch_shop_policy(
	logits: PackedFloat32Array,
	obs: PackedFloat32Array,
	filtered: Array,
	via: String = ECO_MODE_ONNX
) -> bool:
	if filtered.is_empty():
		return false
	if not logits.is_empty() and not _policy_nets_live():
		var slice_ships: Dictionary = TypedVariant.as_dict(weight_policy.current_titan_slice(_ai_titan_id()).get("ship", {}))
		var n_ship: int = mini(6, mini(logits.size(), shop_slots.size()))
		for i: int in range(n_ship):
			var sl: Dictionary = TypedVariant.as_dict(shop_slots[i])
			if TypedVariant.as_bool(sl.get("purchased", false), false):
				continue
			var sid: String = str(TypedVariant.as_int(sl.get("ship_id", 0), 0))
			logits[i] += 2.8 * TypedVariant.as_float(slice_ships.get(sid, 0.5), 0.5)
		var slice_eq: Dictionary = TypedVariant.as_dict(weight_policy.current_titan_slice(_ai_titan_id()).get("equip", {}))
		for ei: int in range(mini(4, equipment_slots.size())):
			var li: int = 6 + ei
			if li >= logits.size():
				break
			var es: Dictionary = TypedVariant.as_dict(equipment_slots[ei])
			if TypedVariant.as_bool(es.get("purchased", false), false):
				continue
			logits[li] += 2.0 * TypedVariant.as_float(slice_eq.get(str(es.get("id", "")), 0.5), 0.5)
	var pick: int = 14
	if not logits.is_empty():
		pick = _shop_argmax_legal(logits, filtered)
	var action: Dictionary = {}
	if pick >= 0 and pick <= 5:
		action = {"action_type": "shop_buy_ship", "seat": -1, "slot_index": pick}
	elif pick >= 6 and pick <= 9:
		action = {"action_type": "shop_buy_equip", "seat": -1, "slot_index": pick - 6}
	elif pick == 10:
		action = {"action_type": "shop_refresh", "seat": -1, "free": false}
	elif pick == 12:
		action = {"action_type": "buy_exp", "seat": -1}
	elif pick == 14:
		return false
	else:
		return false
	var chk: Dictionary = LegalActions.validate_action_against_list(action, filtered)
	if not TypedVariant.as_bool(chk.get("accepted", false), false):
		var fallback_pick: int = _shop_argmax_legal(logits, filtered, pick)
		if fallback_pick == 14:
			return false
		pick = fallback_pick
		if pick >= 0 and pick <= 5:
			action = {"action_type": "shop_buy_ship", "seat": -1, "slot_index": pick}
		elif pick >= 6 and pick <= 9:
			action = {"action_type": "shop_buy_equip", "seat": -1, "slot_index": pick - 6}
		elif pick == 10:
			action = {"action_type": "shop_refresh", "seat": -1, "free": false}
		elif pick == 12:
			action = {"action_type": "buy_exp", "seat": -1}
		else:
			return false
	var at: String = LegalActions.action_type_of(action)
	if at == "shop_buy_ship":
		var si: int = TypedVariant.as_int(action.get("slot_index", -1), -1)
		if si < 0 or si >= shop_slots.size():
			return false
		var slot: Dictionary = TypedVariant.as_dict(shop_slots[si])
		action["ship_id"] = TypedVariant.as_int(slot.get("ship_id", 0), 0)
		action["cost"] = TypedVariant.as_int(DataStore.get_ship(TypedVariant.as_int(action["ship_id"], 0)).get("cost", 0), 0)
		action["team"] = ShipUnit.TEAM_AI
	elif at == "shop_buy_equip":
		var ei: int = TypedVariant.as_int(action.get("slot_index", -1), -1)
		if ei < 0 or ei >= equipment_slots.size():
			return false
		var es: Dictionary = TypedVariant.as_dict(equipment_slots[ei])
		action["item_id"] = str(es.get("id", ""))
		action["cost"] = TypedVariant.as_int(es.get("cost", 0), 0)
		action["team"] = ShipUnit.TEAM_AI
	else:
		action["team"] = ShipUnit.TEAM_AI
	var res: Dictionary = apply_protocol_economy(action)
	if TypedVariant.as_bool(res.get("accepted", false), false):
		var learned: int = pick
		if at == "shop_buy_ship":
			learned = TypedVariant.as_int(action.get("slot_index", pick), pick)
		elif at == "shop_buy_equip":
			learned = 6 + TypedVariant.as_int(action.get("slot_index", 0), 0)
		elif at == "shop_refresh":
			learned = 10
		elif at == "buy_exp":
			learned = 12
		InMatchSlowLearn.note_shop_sample(obs, learned, false)
	SessionDiagnostics.log(
		"ai.decide",
		"net=shop pick=%d at=%s ok=%s via=%s gold=%d ship=%s item=%s" % [
			pick, at, TypedVariant.as_bool(res.get("accepted", false), false), via,
			ai_gold, str(action.get("ship_id", "")), str(action.get("item_id", "")),
		]
	)
	return TypedVariant.as_bool(res.get("accepted", false), false)


func _shop_argmax_legal(logits: PackedFloat32Array, filtered: Array, exclude_i: int = -1) -> int:
	## Farm shop mask: only score legal 0-5/6-9/10/12. Empty army: buy_ship only.
	var empty_army: bool = _count_ai_hangar() + (_board.count_field(ShipUnit.TEAM_AI) if _board else 0) <= 0
	var legal_i: Dictionary = {}
	for la_v: Variant in filtered:
		var la: Dictionary = TypedVariant.as_dict(la_v)
		var at: String = LegalActions.action_type_of(la)
		if empty_army and at != "shop_buy_ship":
			continue
		if at == "shop_buy_ship":
			legal_i[TypedVariant.as_int(la.get("slot_index", -1), -1)] = true
		elif at == "shop_buy_equip":
			legal_i[6 + TypedVariant.as_int(la.get("slot_index", -1), -1)] = true
		elif at == "shop_refresh":
			legal_i[10] = true
		elif at == "buy_exp":
			legal_i[12] = true
	var best_i: int = 14
	var best_v: float = -1.0e30
	for i: int in range(logits.size()):
		if i == 11 or i == 13 or i == 14:
			continue
		if i == exclude_i:
			continue
		if not TypedVariant.as_bool(legal_i.get(i, false), false):
			continue
		var v: float = clampf(logits[i], -32.0, 32.0)
		if v > best_v:
			best_v = v
			best_i = i
	return best_i


func _try_buy_one() -> bool:
	if _uses_onnx_eco():
		return _try_policy_economy_action()
	if _is_first_prepare():
		var candidates: Array[int] = []
		for i: int in range(shop_slots.size()):
			var slot0: Dictionary = TypedVariant.as_dict(shop_slots[i])
			if not TypedVariant.as_bool(slot0.get("purchased", false), false):
				candidates.append(i)
		if candidates.is_empty():
			return false
		return _buy_ai_shop_slot(candidates[randi() % candidates.size()])
	var slot_i: int = -1
	if weight_policy != null and weight_policy.is_ready():
		slot_i = weight_policy.pick_unpurchased_shop_index(shop_slots, _ai_titan_id())
	if slot_i < 0:
		for i: int in range(shop_slots.size()):
			var slot0: Dictionary = TypedVariant.as_dict(shop_slots[i])
			if not TypedVariant.as_bool(slot0.get("purchased", false), false):
				slot_i = i
				break
	if slot_i < 0:
		## refresh or buy exp
		var refresh_cost: int = TypedVariant.as_int(DataStore.economy.get("refresh_cost", 2), 2)
		var exp_cost: int = TypedVariant.as_int(DataStore.economy.get("buy_exp_gold_cost", 4), 4)
		if ai_gold >= refresh_cost and randf() < 0.55:
			ai_gold -= refresh_cost
			_refresh_shop()
			return true
		if ai_gold >= exp_cost:
			ai_gold -= exp_cost
			_grant_exp(TypedVariant.as_int(DataStore.economy.get("buy_exp_amount", 4), 4))
			return true
		return false
	return _buy_ai_shop_slot(slot_i)


func _buy_ai_shop_slot(slot_i: int) -> bool:
	if slot_i < 0 or slot_i >= shop_slots.size() or _board == null:
		return false
	var slot: Dictionary = TypedVariant.as_dict(shop_slots[slot_i])
	if TypedVariant.as_bool(slot.get("purchased", false), false):
		return false
	var sid: int = TypedVariant.as_int(slot.get("ship_id", 0), 0)
	var cost: int = TypedVariant.as_int(DataStore.get_ship(sid).get("cost", 0), 0)
	if ai_gold < cost:
		return false
	var hangar: Vector2i = _board.find_empty_hangar(ShipUnit.TEAM_AI)
	var cap: int = field_cap()
	var on_field: int = _board.count_field(ShipUnit.TEAM_AI)
	if hangar.x >= 0:
		ai_gold -= cost
		shop_slots[slot_i]["purchased"] = true
		AdminBus.request(&"board.deploy", {
			"ship_id": sid, "star": 1, "team": ShipUnit.TEAM_AI,
			"slot_type": "hangar", "x": hangar.x, "z": hangar.y,
		})
		_board.try_upgrades_all()
		return true
	var ship_data: Dictionary = DataStore.get_ship(sid)
	if TypedVariant.as_bool(ship_data.get("requires_cyno_entry", false), false):
		return false
	if on_field < cap:
		## Overflow onto field when hangar full.
		if TypedVariant.as_bool(ship_data.get("deploy_enemy_half_only", false), false):
			var enemy_cell: Vector2i = _pick_ai_field_cell()
			if enemy_cell.x < 0:
				return false
			ai_gold -= cost
			shop_slots[slot_i]["purchased"] = true
			AdminBus.request(&"board.deploy", {
				"ship_id": sid, "star": 1, "team": ShipUnit.TEAM_AI,
				"slot_type": "field", "x": enemy_cell.x, "z": enemy_cell.y,
			})
			## Fix world side after deploy.
			for s: ShipUnit in _board.all_ships():
				if s.team_id == ShipUnit.TEAM_AI and s.ship_id == sid and s.slot_type == "field" and s.grid_x == enemy_cell.x and s.grid_z == enemy_cell.y:
					s.field_side_team = ShipUnit.TEAM_PLAYER
					s.global_position = BoardController.cell_to_world("field", ShipUnit.TEAM_PLAYER, enemy_cell.x, enemy_cell.y)
					break
			_mark_field_cell_used(enemy_cell.x, enemy_cell.y)
			_board.try_upgrades_all()
			_board.refresh_cross_team_cell_offsets()
			return true
		var field: Vector2i = _pick_ai_field_cell()
		if field.x < 0:
			return false
		ai_gold -= cost
		shop_slots[slot_i]["purchased"] = true
		AdminBus.request(&"ai.deploy_ship", {
			"ship_id": sid, "star": 1, "team": ShipUnit.TEAM_AI,
			"x": field.x, "z": field.y,
		})
		_mark_field_cell_used(field.x, field.y)
		_board.try_upgrades_all()
		return true
	return false


func _buy_ai_equip_slot(idx: int) -> bool:
	if idx < 0 or idx >= equipment_slots.size():
		return false
	var slot: Dictionary = TypedVariant.as_dict(equipment_slots[idx])
	if TypedVariant.as_bool(slot.get("purchased", false), false):
		return false
	var item_id: String = str(slot.get("id", "")).strip_edges()
	if item_id == "":
		return false
	var mod: Dictionary = DataStore.get_function_module(item_id)
	if mod.is_empty() or TypedVariant.as_bool(mod.get("implant", false), false):
		return false
	var cost: int = TypedVariant.as_int(mod.get("cost", 10), 10)
	if ai_gold < cost:
		return false
	var bag: int = _find_empty_equipment_inv()
	if bag < 0:
		return false
	ai_gold -= cost
	equipment_slots[idx]["purchased"] = true
	equipment_inventory[bag] = item_id
	return true


func _cell_key(x: int, z: int) -> String:
	return "%d,%d" % [x, z]

func _mark_field_cell_used(x: int, z: int) -> void:
	_used_field_cells[_cell_key(x, z)] = true

func _pick_ai_field_cell() -> Vector2i:
	## Random empty AI-owned field cell; prefer cells not yet used this match.
	var fh: int = TypedVariant.as_int(DataStore.board.get("field_height", 6), 6)
	var unused: Array[Vector2i] = []
	var used: Array[Vector2i] = []
	var total_cells: int = 0
	for z: int in range(fh):
		var cols: int = BoardController.field_cols_at(z)
		total_cells += cols
		for x: int in range(cols):
			if not _board.is_field_cell_free_for(ShipUnit.TEAM_AI, x, z):
				continue
			var k: String = _cell_key(x, z)
			if _used_field_cells.has(k):
				used.append(Vector2i(x, z))
			else:
				unused.append(Vector2i(x, z))
	if unused.is_empty() and not used.is_empty():
		## All empties already visited this match — reset preference so fresh bias restarts.
		if _used_field_cells.size() >= total_cells:
			_used_field_cells.clear()
			return used[randi() % used.size()]
		return used[randi() % used.size()]
	if unused.is_empty():
		return Vector2i(-1, -1)
	return _pick_place_cell(unused, 0)


func _pick_place_cell(candidates: Array[Vector2i], ship_id: int) -> Vector2i:
	if candidates.is_empty():
		return Vector2i(-1, -1)
	if weight_policy == null or not weight_policy.nets_ready():
		return candidates[randi() % candidates.size()]
	var mask: PackedFloat32Array = PackedFloat32Array()
	mask.resize(PolicyObs.MAX_CELLS)
	for c: Vector2i in candidates:
		mask[PolicyObs.flatten_cell(c.x, c.y)] = 1.0
	var obs: PackedFloat32Array = PolicyObs.encode_place(ship_id, 1, _policy_obs_ctx(), mask)
	var logits: PackedFloat32Array = weight_policy.infer_logits("place", obs)
	var best: Vector2i = candidates[0]
	var best_v: float = -1.0e9
	for c2: Vector2i in candidates:
		var idx: int = PolicyObs.flatten_cell(c2.x, c2.y)
		var v: float = logits[idx] if idx < logits.size() else 0.0
		if v > best_v:
			best_v = v
			best = c2
	InMatchSlowLearn.note_place_sample(obs, PolicyObs.flatten_cell(best.x, best.y), false)
	SessionDiagnostics.log(
		"ai.decide",
		"net=place ship=%d cell=%d,%d logit=%.3f" % [ship_id, best.x, best.y, best_v]
	)
	return best


func _policy_obs_ctx() -> Dictionary:
	var field_n: int = _board.count_field(ShipUnit.TEAM_AI) if _board else 0
	var hangar_n: int = 0
	if _board != null:
		for s: ShipUnit in _board.all_ships():
			if s != null and is_instance_valid(s) and s.team_id == ShipUnit.TEAM_AI and s.slot_type == "hangar" and not s.is_destroyed:
				hangar_n += 1
	var stance: PackedFloat32Array = PackedFloat32Array()
	if weight_policy != null:
		stance = weight_policy.stance_mix()
	return {
		"gold": ai_gold,
		"level": ai_level,
		"xp": ai_exp,
		"round": _match.battle_game_stage_count if _match else 1,
		"shop_slots": shop_slots,
		"equipment_slots": equipment_slots,
		"piece_count": field_n + hangar_n,
		"field_count": field_n,
		"hangar_count": hangar_n,
		"bag_count": equipment_inventory.size(),
		"win_streak": win_streak,
		"loss_streak": loss_streak,
		"titan": _ai_titan_id(),
		"stance": stance,
		"buy_exp_cost": TypedVariant.as_int(DataStore.economy.get("buy_exp_gold_cost", 4), 4),
		"xp_demand": float(up_level_demand),
		"security_mode": "nullsec" if _match != null and _match.mode == "nullsec" else "nullsec",
	}

func _reshuffle_ai_field() -> void:
	## Every prepare: move all manned AI field ships to new random cells (prefer unused).
	var ships: Array = []
	for s: ShipUnit in _board.field_ships(ShipUnit.TEAM_AI):
		if s == null or not is_instance_valid(s) or s.is_destroyed or s.is_unmanned:
			continue
		ships.append(s)
	if ships.is_empty():
		return
	ships.shuffle()
	## Free occupancy first so picks don't collide with old seats.
	for s_any: Variant in ships:
		if not (s_any is ShipUnit):
			continue
		var s: ShipUnit = s_any
		_board.release_field_occupancy(s)
	for s_any2: Variant in ships:
		if not (s_any2 is ShipUnit):
			continue
		var ship: ShipUnit = s_any2
		if ship == null or not is_instance_valid(ship):
			continue
		var cell: Vector2i = _pick_ai_field_cell()
		if cell.x < 0:
			## Restore to any free cell via board fallback; should be rare.
			cell = _board.find_empty_field(ShipUnit.TEAM_AI)
		if cell.x < 0:
			continue
		var side: int = ShipUnit.TEAM_AI
		if ship.deploy_enemy_half_only:
			side = ShipUnit.TEAM_PLAYER
		elif ship.field_side_team >= 0:
			side = ship.field_side_team
		_board.move_ship_to_field_side(ship, cell.x, cell.y, side)
		_mark_field_cell_used(cell.x, cell.y)

func _deploy_hangar_to_field() -> void:
	var hangar_ships: Array = []
	for s: ShipUnit in _board.all_ships():
		if s.team_id == ShipUnit.TEAM_AI and s.slot_type == "hangar" and not s.is_destroyed:
			hangar_ships.append(s)
	hangar_ships.sort_custom(func(a: Variant, b: Variant) -> bool:
		if not (a is ShipUnit) or not (b is ShipUnit):
			return false
		var aa: ShipUnit = a
		var bb: ShipUnit = b
		if _policy_nets_live() and aa.is_logistic != bb.is_logistic:
			return not aa.is_logistic
		return aa.star > bb.star
	)
	for s_any: Variant in hangar_ships:
		if not (s_any is ShipUnit):
			continue
		var s: ShipUnit = s_any
		if s.requires_cyno_entry:
			continue
		if _board.count_field(ShipUnit.TEAM_AI) >= field_cap():
			break
		if s.deploy_enemy_half_only:
			var enemy_cell: Vector2i = _pick_ai_field_cell()
			if enemy_cell.x < 0:
				continue
			AdminBus.request(&"board.move", {
				"ship_instance_id": s.get_instance_id(),
				"to_slot_type": "field",
				"to_x": enemy_cell.x,
				"to_z": enemy_cell.y,
				"field_side_team": ShipUnit.TEAM_PLAYER,
			})
			_mark_field_cell_used(enemy_cell.x, enemy_cell.y)
			continue
		var cell: Vector2i = _pick_ai_field_cell()
		if cell.x < 0:
			break
		AdminBus.request(&"board.move", {
			"ship_instance_id": s.get_instance_id(),
			"to_slot_type": "field",
			"to_x": cell.x,
			"to_z": cell.y,
		})
		_mark_field_cell_used(cell.x, cell.y)

func _ensure_one_logistic() -> void:
	var has_logi: bool = false
	for s: ShipUnit in _board.field_ships(ShipUnit.TEAM_AI):
		if s.is_logistic and not s.is_destroyed:
			has_logi = true
			break
	if has_logi:
		return
	for s: ShipUnit in _board.all_ships():
		if s.team_id != ShipUnit.TEAM_AI or s.is_destroyed:
			continue
		if not s.is_logistic:
			continue
		## FAX etc. stay in hangar until cyno jump — never force onto field.
		if s.requires_cyno_entry:
			continue
		if s.slot_type == "field":
			return
		var cell: Vector2i = _pick_ai_field_cell()
		if cell.x < 0:
			return
		if _board.count_field(ShipUnit.TEAM_AI) >= field_cap():
			## Swap weakest non-logi off field if needed — skip for v1 if full.
			return
		AdminBus.request(&"board.move", {
			"ship_instance_id": s.get_instance_id(),
			"to_slot_type": "field",
			"to_x": cell.x,
			"to_z": cell.y,
		})
		_mark_field_cell_used(cell.x, cell.y)
		return

func _sell_hangar_remainder() -> void:
	## AI_PLAYER_HANDBOOK §2.1: sell non-capitals; sell capitals ONLY when
	## capital hangar count > floor(hangar_slots/2), trimming down to that cap.
	if _policy_nets_live() or (_onnx_shop_prepare and _eco_actions > 0):
		return
	var to_sell: Array = []
	var capitals: Array[ShipUnit] = []
	for s: ShipUnit in _board.all_ships():
		if s.team_id == ShipUnit.TEAM_AI and s.slot_type == "hangar" and not s.is_destroyed:
			if s.requires_cyno_entry:
				capitals.append(s)
				continue
			to_sell.append(s)
	var hangar_slots: int = maxi(
		1,
		TypedVariant.as_int(DataStore.board.get("hangar_width", 15), 15)
		* TypedVariant.as_int(DataStore.board.get("hangar_height", 1), 1)
	)
	var keep_capitals: int = floori(float(hangar_slots) * 0.5)
	## 3 capitals on a 15-slot hangar → keep all (3 <= 7). Never wipe the kit.
	if capitals.size() > keep_capitals:
		capitals.sort_custom(func(a: ShipUnit, b: ShipUnit) -> bool:
			if a.star != b.star:
				return a.star < b.star
			if a.get_cost() != b.get_cost():
				return a.get_cost() < b.get_cost()
			return a.get_instance_id() > b.get_instance_id()
		)
		for i: int in range(keep_capitals, capitals.size()):
			to_sell.append(capitals[i])
	var sold_n: int = 0
	var sold_gold: int = 0
	for s_any: Variant in to_sell:
		if not (s_any is ShipUnit):
			continue
		var ship: ShipUnit = s_any
		if ship == null or not is_instance_valid(ship):
			continue
		## Belt-and-suspenders: never sell cyno-gated hulls outside the excess trim above.
		if ship.requires_cyno_entry and capitals.size() <= keep_capitals:
			continue
		var r: Dictionary = AdminBus.request(&"board.sell", {
			"ship_instance_id": ship.get_instance_id(),
			"team": ShipUnit.TEAM_AI,
		})
		if TypedVariant.as_bool(r.get("accepted", false), false):
			var gold: int = TypedVariant.as_int(r.get("gold", ship.get_sell_price()), ship.get_sell_price())
			ai_gold += gold
			sold_n += 1
			sold_gold += gold
	if sold_n > 0:
		var tree: SceneTree = get_tree()
		if tree:
			tree.call_group(
				"match_root",
				"append_battle_log",
				"人机卖了备战席上的舰船，然后获得了%d黄" % sold_gold
			)

func sync_field_for_prepare() -> void:
	## Fill field from hangar (same rules as economy turn). Safe after load/resume
	## when board was overwritten and economy already ran on an empty board.
	_deploy_hangar_to_field()
	if not _uses_onnx_eco():
		_ensure_one_logistic()
	_reshuffle_ai_field()
	_board.recalculate_fetters(ShipUnit.TEAM_AI)

func finalize_prepare() -> void:
	## Deploy first. Six-net ONNX keeps hangar remainder (handbook §0.2 / §2).
	sync_field_for_prepare()
	if not _uses_onnx_eco():
		_random_distribute_equipment()
	if _uses_onnx_eco() or (_onnx_shop_prepare and _eco_actions > 0):
		return
	_sell_hangar_remainder()

func _deploy_legacy_quota() -> void:
	var per: int = maxi(0, TypedVariant.as_int(DataStore.ai.get("deploys_per_round", 1), 1))
	var placed: int = 0
	while placed < per:
		if not _try_deploy_one_random():
			break
		placed += 1
	_board.recalculate_fetters(ShipUnit.TEAM_AI)

func _try_deploy_one_random() -> bool:
	var cap: int = field_cap()
	if _board.count_field(ShipUnit.TEAM_AI) >= cap:
		return false
	var tries: int = TypedVariant.as_int(DataStore.ai.get("deploy_try_limit", 28), 28)
	var tag: String = str(DataStore.ai.get("cruiser_ship_group_tag", "cruiser"))
	var block_until: int = TypedVariant.as_int(DataStore.ai.get("cruiser_block_battle_stages", 3), 3)
	var ids: Array = DataStore.ship_ids()
	if ids.is_empty():
		return false
	for _i: int in range(tries):
		var cell: Vector2i = _pick_ai_field_cell()
		if cell.x < 0:
			return false
		var sid: int = TypedVariant.as_int(ids[randi() % ids.size()], 0)
		var sd: Dictionary = DataStore.get_ship(sid)
		if TypedVariant.as_bool(sd.get("requires_cyno_entry", false), false):
			continue
		if _match.battle_game_stage_count <= block_until and DataStore.ship_has_group(sid, tag):
			continue
		if TypedVariant.as_bool(sd.get("deploy_enemy_half_only", false), false):
			var enemy_cell: Vector2i = _pick_ai_field_cell()
			if enemy_cell.x < 0:
				continue
			AdminBus.request(&"board.deploy", {
				"ship_id": sid, "star": 1, "team": ShipUnit.TEAM_AI,
				"slot_type": "field", "x": enemy_cell.x, "z": enemy_cell.y,
			})
			for s2: ShipUnit in _board.all_ships():
				if s2.team_id == ShipUnit.TEAM_AI and s2.ship_id == sid and s2.slot_type == "field" and s2.grid_x == enemy_cell.x and s2.grid_z == enemy_cell.y:
					s2.field_side_team = ShipUnit.TEAM_PLAYER
					s2.global_position = BoardController.cell_to_world("field", ShipUnit.TEAM_PLAYER, enemy_cell.x, enemy_cell.y)
					break
			_mark_field_cell_used(enemy_cell.x, enemy_cell.y)
			_board.try_upgrades_all()
			_board.refresh_cross_team_cell_offsets()
			return true
		AdminBus.request(&"ai.deploy_ship", {
			"ship_id": sid, "star": 1, "team": ShipUnit.TEAM_AI,
			"x": cell.x, "z": cell.y,
		})
		_mark_field_cell_used(cell.x, cell.y)
		_board.try_upgrades_all()
		return true
	return false

func _on_deploy(payload: Dictionary) -> Dictionary:
	var ship_id: int = TypedVariant.as_int(payload.get("ship_id", 0), 0)
	var x: int = TypedVariant.as_int(payload.get("x", 0), 0)
	var z: int = TypedVariant.as_int(payload.get("z", 0), 0)
	var star: int = TypedVariant.as_int(payload.get("star", 1), 1)
	if TypedVariant.as_bool(DataStore.get_ship(ship_id).get("requires_cyno_entry", false), false):
		return {"accepted": false, "reason_key": "requires_cyno"}
	if _board.count_field(ShipUnit.TEAM_AI) >= field_cap():
		return {"accepted": false, "reason_key": "ai_field_cap"}
	AdminBus.request(&"board.deploy", {
		"ship_id": ship_id, "star": star, "team": ShipUnit.TEAM_AI,
		"slot_type": "field", "x": x, "z": z,
	})
	return {"accepted": true}

func _on_after(channel: StringName, _payload: Dictionary, _result: Dictionary) -> void:
	if endless and String(channel) == "citadel.damage":
		pass


func _count_ai_hangar() -> int:
	var n: int = 0
	if _board == null:
		return 0
	for s: ShipUnit in _board.all_ships():
		if s != null and is_instance_valid(s) and s.team_id == ShipUnit.TEAM_AI and s.slot_type == "hangar" and not s.is_destroyed:
			n += 1
	return n
