extends Node
class_name AiController
## AI is a rule-following player: same economy/shop/hangar with income ×2 buff.

var _board: BoardController
var _match: MatchController
var endless: bool = false

var ai_gold: int = 0
var ai_level: int = 1
var ai_exp: int = 0
var up_level_demand: int = 4
var win_streak: int = 0
var loss_streak: int = 0
var shop_slots: Array = []  # {ship_id, purchased}
var _recent_shop_hits: Dictionary = {}

func bind(match_ctrl: MatchController, board: BoardController) -> void:
	_match = match_ctrl
	_board = board
	AdminBus.register_handler(&"ai.deploy_ship", _on_deploy)
	AdminBus.after_handoff.connect(_on_after)

func init_army() -> void:
	endless = _match.mode == "endless"
	var eco: Dictionary = DataStore.economy
	ai_gold = int(eco.get("base_gold", 5))
	ai_level = 1
	ai_exp = 0
	up_level_demand = int(eco.get("initial_level_exp_demand", 4))
	win_streak = 0
	loss_streak = 0
	_refresh_shop()
	_run_economy_turn()

func after_round() -> void:
	_grant_exp(int(DataStore.economy.get("base_exp_income", 4)))
	_refresh_shop()
	_run_economy_turn()

func population_limit() -> int:
	return mini(ai_level + int(DataStore.board.get("ship_count_buff", 0)), int(DataStore.board.get("max_deployment", 999)))

func field_cap() -> int:
	## min(AI pop, floor(player pop × 2.0))
	var ai_pop := maxi(1, population_limit())
	var player_pop := maxi(1, _match.population_limit())
	var mult := float(DataStore.ai.get("field_cap_vs_player_pop", 2.0))
	var vs_player := maxi(1, int(floor(float(player_pop) * mult)))
	return mini(ai_pop, vs_player)

func update_streaks(won: bool) -> void:
	if won:
		win_streak += 1
		loss_streak = 0
	else:
		loss_streak += 1
		win_streak = 0

func apply_income(won: bool, kills: int) -> void:
	var eco: Dictionary = DataStore.economy
	var interest: int = int(floor(float(ai_gold) / float(eco.get("interest_divisor", 10))))
	var cap: int = int(eco.get("interest_cap", 5))
	if bool(eco.get("interest_capped", true)):
		interest = mini(interest, cap)
	var base: int = _match._base_income_for_round() if _match.has_method("_base_income_for_round") else int(eco.get("base_gold_income", 5))
	var win_g: int = int(eco.get("win_gold", 1)) if won else 0
	var streak: int = win_streak if won else loss_streak
	var streak_g: int = _match._streak_bonus(streak) if _match.has_method("_streak_bonus") else 0
	var kill_g: int = kills * int(eco.get("kill_gold_per_ship", 1))
	var income: int = base + interest + win_g + streak_g + kill_g
	var mul: float = float(DataStore.ai.get("ai_gold_income_buff_mul", 2.0))
	income = int(round(float(income) * mul))
	ai_gold += income

func add_gold(amount: int) -> void:
	ai_gold += amount

func _grant_exp(amount: int) -> void:
	ai_exp += amount
	var eco: Dictionary = DataStore.economy
	var inc: int = int(eco.get("level_exp_demand_increment", 8))
	while ai_exp >= up_level_demand:
		ai_exp -= up_level_demand
		ai_level += 1
		up_level_demand += inc

func _refresh_shop() -> void:
	var n := int(DataStore.economy.get("shop_slot_count", 7))
	ShopController._decay_recent_hits(_recent_shop_hits)
	shop_slots.clear()
	var seen_counts: Dictionary = {}
	for i in range(n):
		var sid := _roll_ship_id(seen_counts)
		seen_counts[sid] = int(seen_counts.get(sid, 0)) + 1
		_recent_shop_hits[sid] = int(_recent_shop_hits.get(sid, 0)) + 1
		shop_slots.append({"ship_id": sid, "purchased": false})

func _roll_ship_id(seen_counts: Dictionary = {}) -> int:
	## Reuse shop odds table at min(ai_level, 5).
	return ShopController.roll_ship_id_for_level(ai_level, _match.battle_game_stage_count, seen_counts, _recent_shop_hits)

func _run_economy_turn() -> void:
	if not bool(DataStore.ai.get("uses_shop_economy", true)):
		_deploy_legacy_quota()
		return
	## Spend loop: hangar buy → overflow field → refresh/exp → stop.
	var guard := 40
	while guard > 0:
		guard -= 1
		if not _try_buy_one():
			break
	_deploy_hangar_to_field()
	_ensure_one_logistic()
	_sell_hangar_remainder()
	_board.recalculate_fetters(ShipUnit.TEAM_AI)

func _try_buy_one() -> bool:
	var slot_i := -1
	for i in range(shop_slots.size()):
		if not shop_slots[i].get("purchased", false):
			slot_i = i
			break
	if slot_i < 0:
		## refresh or buy exp
		var refresh_cost := int(DataStore.economy.get("refresh_cost", 2))
		var exp_cost := int(DataStore.economy.get("buy_exp_gold_cost", 4))
		if ai_gold >= refresh_cost and randf() < 0.55:
			ai_gold -= refresh_cost
			_refresh_shop()
			return true
		if ai_gold >= exp_cost:
			ai_gold -= exp_cost
			_grant_exp(int(DataStore.economy.get("buy_exp_amount", 4)))
			return true
		return false
	var sid := int(shop_slots[slot_i].get("ship_id", 0))
	var cost := int(DataStore.get_ship(sid).get("cost", 0))
	if ai_gold < cost:
		return false
	var hangar := _board.find_empty_hangar(ShipUnit.TEAM_AI)
	var field := _board.find_empty_field(ShipUnit.TEAM_AI)
	var cap := field_cap()
	var on_field := _board.count_field(ShipUnit.TEAM_AI)
	if hangar.x >= 0:
		ai_gold -= cost
		shop_slots[slot_i]["purchased"] = true
		AdminBus.request(&"board.deploy", {
			"ship_id": sid, "star": 1, "team": ShipUnit.TEAM_AI,
			"slot_type": "hangar", "x": hangar.x, "z": hangar.y,
		})
		_board.try_upgrades_all()
		return true
	if field.x >= 0 and on_field < cap:
		## Overflow onto field when hangar full.
		ai_gold -= cost
		shop_slots[slot_i]["purchased"] = true
		AdminBus.request(&"ai.deploy_ship", {
			"ship_id": sid, "star": 1, "team": ShipUnit.TEAM_AI,
			"x": field.x, "z": field.y,
		})
		_board.try_upgrades_all()
		return true
	return false

func _deploy_hangar_to_field() -> void:
	var hangar_ships: Array = []
	for s in _board.all_ships():
		if s.team_id == ShipUnit.TEAM_AI and s.slot_type == "hangar" and not s.is_destroyed:
			hangar_ships.append(s)
	hangar_ships.sort_custom(func(a, b): return a.star > b.star)
	for s in hangar_ships:
		if _board.count_field(ShipUnit.TEAM_AI) >= field_cap():
			break
		var cell := _board.find_empty_field(ShipUnit.TEAM_AI)
		if cell.x < 0:
			break
		AdminBus.request(&"board.move", {
			"ship_instance_id": s.get_instance_id(),
			"to_slot_type": "field",
			"to_x": cell.x,
			"to_z": cell.y,
		})

func _ensure_one_logistic() -> void:
	var has_logi := false
	for s in _board.field_ships(ShipUnit.TEAM_AI):
		if s.is_logistic and not s.is_destroyed:
			has_logi = true
			break
	if has_logi:
		return
	for s in _board.all_ships():
		if s.team_id != ShipUnit.TEAM_AI or s.is_destroyed:
			continue
		if not s.is_logistic:
			continue
		if s.slot_type == "field":
			return
		var cell := _board.find_empty_field(ShipUnit.TEAM_AI)
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
		return

func _sell_hangar_remainder() -> void:
	var to_sell: Array = []
	for s in _board.all_ships():
		if s.team_id == ShipUnit.TEAM_AI and s.slot_type == "hangar" and not s.is_destroyed:
			to_sell.append(s)
	for s in to_sell:
		var ship := s as ShipUnit
		if ship == null:
			continue
		var price: int = ship.get_cost()
		ai_gold += price
		AdminBus.request(&"board.sell", {"ship_instance_id": ship.get_instance_id(), "team": ShipUnit.TEAM_AI})

func _deploy_legacy_quota() -> void:
	var per := maxi(0, int(DataStore.ai.get("deploys_per_round", 1)))
	var placed := 0
	while placed < per:
		if not _try_deploy_one_random():
			break
		placed += 1
	_board.recalculate_fetters(ShipUnit.TEAM_AI)

func _try_deploy_one_random() -> bool:
	var cap := field_cap()
	if _board.count_field(ShipUnit.TEAM_AI) >= cap:
		return false
	var tries := int(DataStore.ai.get("deploy_try_limit", 28))
	var tag := str(DataStore.ai.get("cruiser_ship_group_tag", "cruiser"))
	var block_until := int(DataStore.ai.get("cruiser_block_battle_stages", 3))
	var ids: Array = DataStore.ship_ids()
	if ids.is_empty():
		return false
	for _i in range(tries):
		var cell := _board.find_empty_field(ShipUnit.TEAM_AI)
		if cell.x < 0:
			return false
		var sid: int = ids[randi() % ids.size()]
		if _match.battle_game_stage_count <= block_until and DataStore.ship_has_group(sid, tag):
			continue
		AdminBus.request(&"ai.deploy_ship", {
			"ship_id": sid, "star": 1, "team": ShipUnit.TEAM_AI,
			"x": cell.x, "z": cell.y,
		})
		_board.try_upgrades_all()
		return true
	return false

func _on_deploy(payload: Dictionary) -> Dictionary:
	var ship_id := int(payload.get("ship_id", 0))
	var x := int(payload.get("x", 0))
	var z := int(payload.get("z", 0))
	var star := int(payload.get("star", 1))
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
