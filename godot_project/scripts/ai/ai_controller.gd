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
var _pity_refresh_count: int = 0
var _pity_seen_tonnage: Dictionary = {}
## Cells AI has already deployed onto this match ("x,z"); prefer fresh cells each place/reshuffle.
var _used_field_cells: Dictionary = {}

func bind(match_ctrl: MatchController, board: BoardController) -> void:
	_match = match_ctrl
	_board = board
	AdminBus.register_handler(&"ai.deploy_ship", _on_deploy)
	AdminBus.after_handoff.connect(_on_after)

func init_economy() -> void:
	## Seat opening only — no shopping. Nullsec builds the rival hulls per PVP round.
	endless = _match.mode == "endless"
	var eco: Dictionary = DataStore.economy
	ai_gold = int(eco.get("base_gold", 5))
	ai_level = 1
	ai_exp = 0
	up_level_demand = int(eco.get("initial_level_exp_demand", 4))
	win_streak = 0
	loss_streak = 0
	_used_field_cells.clear()
	_refresh_shop()

func init_army() -> void:
	init_economy()
	_run_economy_turn()

func rebuild_round_army() -> void:
	## Nullsec PVP draws a different rival every round, so the hulls are rebuilt from
	## scratch — but out of the seat's accumulated level/gold, never a fresh level-1
	## opening (MULTIPLAYER_MATCH_FLOW §5.0: 人机玩家与真人同套).
	_used_field_cells.clear()
	_refresh_shop()
	_run_economy_turn()

func after_round() -> void:
	_grant_exp(int(DataStore.economy.get("base_exp_income", 4)))
	if _match.mode == "nullsec":
		## Hulls bought here would be wiped when the next round's board is authored, so
		## the seat only banks gold/exp and spends it when it is actually the rival.
		return
	_refresh_shop()
	_run_economy_turn()

func population_limit() -> int:
	return mini(ai_level + int(DataStore.board.get("ship_count_buff", 0)), int(DataStore.board.get("max_deployment", 999)))

func field_cap() -> int:
	## min(AI pop, floor(player pop × 2.0))
	var ai_pop := maxi(1, population_limit())
	## Nullsec seats use their own population, same as humans: the asymmetric cap below
	## is 1v1 Versus only (MULTIPLAYER_MATCH_FLOW §5.0).
	if _match and _match.mode == "nullsec":
		return ai_pop
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
	var mining_g: int = _match._mining_gold_for_team(ShipUnit.TEAM_AI) if _match.has_method("_mining_gold_for_team") else 0
	var income: int = base + interest + win_g + streak_g + kill_g + mining_g
	var mul: float = float(DataStore.ai.get("ai_gold_income_buff_mul", 2.0))
	## Buff multiplies combat economy only; mining gold stays raw (parallel channel).
	var combat_part := income - mining_g
	income = int(round(float(combat_part) * mul)) + mining_g
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
	var force_tonnages: Array = []
	var window := maxi(1, int(DataStore.economy.get("shop_tonnage_pity_window", 5)))
	if _pity_refresh_count >= window:
		for key in ShopController._unlocked_tonnage_keys(ai_level):
			if not bool(_pity_seen_tonnage.get(key, false)):
				force_tonnages.append(key)
	var force_i := 0
	for i in range(n):
		var sid := 0
		if force_i < force_tonnages.size():
			## Reuse player shop helper via temporary ShopController statics.
			var pool: Array = []
			var eligible: Array = ShopController._eligible_ship_ids_for_level(ai_level, DataStore.ship_ids())
			var max_same: int = maxi(1, int(DataStore.economy.get("shop_max_same_ship_per_refresh", 2)))
			var want := str(force_tonnages[force_i])
			force_i += 1
			for cand in eligible:
				var cid := int(cand)
				if int(seen_counts.get(cid, 0)) >= max_same:
					continue
				if ShopController.ship_tonnage_key(cid) == want:
					pool.append(cid)
			if not pool.is_empty():
				sid = ShopController._pick_pseudo_random(pool, _recent_shop_hits, _ai_titan_race())
		if sid <= 0:
			sid = _roll_ship_id(seen_counts)
		seen_counts[sid] = int(seen_counts.get(sid, 0)) + 1
		_recent_shop_hits[sid] = int(_recent_shop_hits.get(sid, 0)) + 1
		shop_slots.append({"ship_id": sid, "purchased": false})
	if _pity_refresh_count >= window:
		_pity_refresh_count = 0
		_pity_seen_tonnage.clear()
	for slot in shop_slots:
		var key := ShopController.ship_tonnage_key(int(slot.get("ship_id", 0)))
		if key != "":
			_pity_seen_tonnage[key] = true
	_pity_refresh_count += 1

func _roll_ship_id(seen_counts: Dictionary = {}) -> int:
	## Reuse shop odds table at min(ai_level, 5).
	return ShopController.roll_ship_id_for_level(
		ai_level, _match.battle_game_stage_count, seen_counts, _recent_shop_hits, _ai_titan_race()
	)


## Rival seat titan in nullsec PVP; empty for PVE creeps / versus (no titan shop boost).
func _ai_titan_race() -> String:
	if _board == null:
		return ""
	return _board.titan_fetter_race(ShipUnit.TEAM_AI)

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
	sync_field_for_prepare()
	## Do NOT sell here — keep hangar visible during Prepare for AI purchase readability.

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
	var ship_data: Dictionary = DataStore.get_ship(sid)
	if bool(ship_data.get("requires_cyno_entry", false)):
		return false
	if on_field < cap:
		## Overflow onto field when hangar full.
		if bool(ship_data.get("deploy_enemy_half_only", false)):
			var enemy_cell := _pick_ai_field_cell()
			if enemy_cell.x < 0:
				return false
			ai_gold -= cost
			shop_slots[slot_i]["purchased"] = true
			AdminBus.request(&"board.deploy", {
				"ship_id": sid, "star": 1, "team": ShipUnit.TEAM_AI,
				"slot_type": "field", "x": enemy_cell.x, "z": enemy_cell.y,
			})
			## Fix world side after deploy.
			for s in _board.all_ships():
				if s.team_id == ShipUnit.TEAM_AI and s.ship_id == sid and s.slot_type == "field" and s.grid_x == enemy_cell.x and s.grid_z == enemy_cell.y:
					s.field_side_team = ShipUnit.TEAM_PLAYER
					s.global_position = BoardController.cell_to_world("field", ShipUnit.TEAM_PLAYER, enemy_cell.x, enemy_cell.y)
					break
			_mark_field_cell_used(enemy_cell.x, enemy_cell.y)
			_board.try_upgrades_all()
			_board.refresh_cross_team_cell_offsets()
			return true
		var field := _pick_ai_field_cell()
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

func _cell_key(x: int, z: int) -> String:
	return "%d,%d" % [x, z]

func _mark_field_cell_used(x: int, z: int) -> void:
	_used_field_cells[_cell_key(x, z)] = true

func _pick_ai_field_cell() -> Vector2i:
	## Random empty AI-owned field cell; prefer cells not yet used this match.
	var fh := int(DataStore.board.get("field_height", 6))
	var unused: Array[Vector2i] = []
	var used: Array[Vector2i] = []
	var total_cells := 0
	for z in range(fh):
		var cols: int = BoardController.field_cols_at(z)
		total_cells += cols
		for x in range(cols):
			if not _board.is_field_cell_free_for(ShipUnit.TEAM_AI, x, z):
				continue
			var k := _cell_key(x, z)
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
	return unused[randi() % unused.size()]

func _reshuffle_ai_field() -> void:
	## Every prepare: move all manned AI field ships to new random cells (prefer unused).
	var ships: Array = []
	for s in _board.field_ships(ShipUnit.TEAM_AI):
		if s == null or not is_instance_valid(s) or s.is_destroyed or s.is_unmanned:
			continue
		ships.append(s)
	if ships.is_empty():
		return
	ships.shuffle()
	## Free occupancy first so picks don't collide with old seats.
	for s_any in ships:
		var s: ShipUnit = s_any
		_board.release_field_occupancy(s)
	for s_any2 in ships:
		var ship: ShipUnit = s_any2
		if ship == null or not is_instance_valid(ship):
			continue
		var cell := _pick_ai_field_cell()
		if cell.x < 0:
			## Restore to any free cell via board fallback; should be rare.
			cell = _board.find_empty_field(ShipUnit.TEAM_AI)
		if cell.x < 0:
			continue
		var side := ShipUnit.TEAM_AI
		if ship.deploy_enemy_half_only:
			side = ShipUnit.TEAM_PLAYER
		elif ship.field_side_team >= 0:
			side = ship.field_side_team
		_board.move_ship_to_field_side(ship, cell.x, cell.y, side)
		_mark_field_cell_used(cell.x, cell.y)

func _deploy_hangar_to_field() -> void:
	var hangar_ships: Array = []
	for s in _board.all_ships():
		if s.team_id == ShipUnit.TEAM_AI and s.slot_type == "hangar" and not s.is_destroyed:
			hangar_ships.append(s)
	hangar_ships.sort_custom(func(a, b): return a.star > b.star)
	for s in hangar_ships:
		if s.requires_cyno_entry:
			continue
		if _board.count_field(ShipUnit.TEAM_AI) >= field_cap():
			break
		if s.deploy_enemy_half_only:
			var enemy_cell := _pick_ai_field_cell()
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
		var cell := _pick_ai_field_cell()
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
		## FAX etc. stay in hangar until cyno jump — never force onto field.
		if s.requires_cyno_entry:
			continue
		if s.slot_type == "field":
			return
		var cell := _pick_ai_field_cell()
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
	var to_sell: Array = []
	var capitals: Array[ShipUnit] = []
	for s in _board.all_ships():
		if s.team_id == ShipUnit.TEAM_AI and s.slot_type == "hangar" and not s.is_destroyed:
			if s.requires_cyno_entry:
				capitals.append(s)
				continue
			to_sell.append(s)
	var hangar_slots := maxi(1, int(DataStore.board.get("hangar_width", 15)) * int(DataStore.board.get("hangar_height", 1)))
	var keep_capitals := int(floor(float(hangar_slots) * 0.5))
	## 3 capitals on a 15-slot hangar → keep all (3 <= 7). Never wipe the kit.
	if capitals.size() > keep_capitals:
		capitals.sort_custom(func(a: ShipUnit, b: ShipUnit) -> bool:
			if a.star != b.star:
				return a.star < b.star
			if a.get_cost() != b.get_cost():
				return a.get_cost() < b.get_cost()
			return a.get_instance_id() > b.get_instance_id()
		)
		for i in range(keep_capitals, capitals.size()):
			to_sell.append(capitals[i])
	var sold_n := 0
	var sold_gold := 0
	for s in to_sell:
		var ship := s as ShipUnit
		if ship == null or not is_instance_valid(ship):
			continue
		## Belt-and-suspenders: never sell cyno-gated hulls outside the excess trim above.
		if ship.requires_cyno_entry and capitals.size() <= keep_capitals:
			continue
		var r: Dictionary = AdminBus.request(&"board.sell", {
			"ship_instance_id": ship.get_instance_id(),
			"team": ShipUnit.TEAM_AI,
		})
		if r.get("accepted", false):
			var gold := int(r.get("gold", ship.get_sell_price()))
			ai_gold += gold
			sold_n += 1
			sold_gold += gold
	if sold_n > 0:
		var tree := get_tree()
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
	_ensure_one_logistic()
	_reshuffle_ai_field()
	_board.recalculate_fetters(ShipUnit.TEAM_AI)

func finalize_prepare() -> void:
	## Deploy first, then sell leftover hangar — never sell-before-deploy (leaves empty field).
	sync_field_for_prepare()
	_sell_hangar_remainder()

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
		var cell := _pick_ai_field_cell()
		if cell.x < 0:
			return false
		var sid: int = ids[randi() % ids.size()]
		var sd: Dictionary = DataStore.get_ship(sid)
		if bool(sd.get("requires_cyno_entry", false)):
			continue
		if _match.battle_game_stage_count <= block_until and DataStore.ship_has_group(sid, tag):
			continue
		if bool(sd.get("deploy_enemy_half_only", false)):
			var enemy_cell := _pick_ai_field_cell()
			if enemy_cell.x < 0:
				continue
			AdminBus.request(&"board.deploy", {
				"ship_id": sid, "star": 1, "team": ShipUnit.TEAM_AI,
				"slot_type": "field", "x": enemy_cell.x, "z": enemy_cell.y,
			})
			for s2 in _board.all_ships():
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
	var ship_id := int(payload.get("ship_id", 0))
	var x := int(payload.get("x", 0))
	var z := int(payload.get("z", 0))
	var star := int(payload.get("star", 1))
	if bool(DataStore.get_ship(ship_id).get("requires_cyno_entry", false)):
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
