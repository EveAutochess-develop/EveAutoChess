extends Node
class_name MatchController
## Prepare / Battle stage machine — timings from DataStore.match_flow.

enum Stage { PREPARE, BATTLE, GAME_END }

signal stage_changed(stage: int)
signal hud_refresh()
signal notice(text: String)
signal match_over(summary: String)

var stage: int = Stage.PREPARE
var timer: float = 0.0
var battle_game_stage_count: int = 0
var round_phase_value: int = 1
var battle_phase_value: int = 0
var mode: String = "versus"  # versus | endless

var player_gold: int = 0
var player_hp: int = 1000
var player_max_hp: int = 1000
var player_level: int = 1
var player_exp: int = 0
var up_level_demand: int = 4
var shop_locked: bool = false
var speed_multiplier: float = 1.0

var win_streak: int = 0
var loss_streak: int = 0
var kills_this_round_player: int = 0
var kills_this_round_ai: int = 0

var _board: BoardController
var _shop: ShopController
var _combat: CombatResolver
var _ai: AiController
var _running: bool = false
var _speed_step_index: int = 0
var _sim_accum: float = 0.0

func bind(board: BoardController, shop: ShopController, combat: CombatResolver, ai: AiController) -> void:
	_board = board
	_shop = shop
	_combat = combat
	_ai = ai
	AdminBus.after_handoff.connect(_on_admin_after)

func start_match(p_mode: String) -> void:
	mode = p_mode
	var mf: Dictionary = DataStore.match_flow
	var eco: Dictionary = DataStore.economy
	player_gold = int(eco.get("base_gold", 5))
	player_max_hp = int(mf.get("player_max_hp", 1000))
	player_hp = player_max_hp
	player_level = 1
	player_exp = 0
	up_level_demand = int(eco.get("initial_level_exp_demand", 4))
	battle_game_stage_count = 0
	round_phase_value = 1
	battle_phase_value = 0
	shop_locked = false
	win_streak = 0
	loss_streak = 0
	kills_this_round_player = 0
	kills_this_round_ai = 0
	_running = true
	_sim_accum = 0.0
	_init_speed_multiplier()
	_board.reset_match()
	_shop.refresh_shop(true)
	_ai.init_army()
	_enter_prepare()

func _process(delta: float) -> void:
	if not _running or stage == Stage.GAME_END:
		return
	var sim_delta: float = delta * speed_multiplier
	timer += sim_delta
	var mf: Dictionary = DataStore.match_flow
	if stage == Stage.PREPARE:
		var dur := float(mf.get("prepare_duration_s", 16))
		if timer >= dur:
			_on_prepare_complete()
	elif stage == Stage.BATTLE:
		var fixed := maxf(0.001, float(mf.get("sim_fixed_step_s", 0.05)))
		_sim_accum += sim_delta
		while _sim_accum >= fixed:
			_combat.tick(fixed)
			_sim_accum -= fixed
		var bdur := float(mf.get("battle_duration_s", 1800))
		var min_b := float(mf.get("min_battle_duration_s", 1.25))
		if timer >= bdur:
			notice.emit("战斗未能在时限内结束")
			_on_combat_complete("timeout")
		elif timer >= min_b and _board.is_one_side_cleared():
			_on_combat_complete("wipe")
	hud_refresh.emit()

func _init_speed_multiplier() -> void:
	var mf: Dictionary = DataStore.match_flow
	var steps: Array = mf.get("speed_steps", [0.2, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0])
	speed_multiplier = float(mf.get("speed_multiplier", 1.0))
	_speed_step_index = 0
	for i in range(steps.size()):
		if absf(float(steps[i]) - speed_multiplier) < 0.001:
			_speed_step_index = i
			return
	for i in range(steps.size()):
		if float(steps[i]) >= speed_multiplier:
			_speed_step_index = i
			speed_multiplier = float(steps[i])
			return
	if steps.size() > 0:
		_speed_step_index = steps.size() - 1
		speed_multiplier = float(steps[_speed_step_index])

func cycle_speed() -> void:
	if stage == Stage.PREPARE:
		return
	var steps: Array = DataStore.match_flow.get("speed_steps", [0.2, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0])
	if steps.is_empty():
		return
	_speed_step_index = (_speed_step_index + 1) % steps.size()
	speed_multiplier = float(steps[_speed_step_index])
	hud_refresh.emit()

func speed_label() -> String:
	if speed_multiplier >= 1.0 and fmod(speed_multiplier, 1.0) < 0.001:
		return "%dx" % int(speed_multiplier)
	return "%.1fx" % speed_multiplier

func battle_remaining() -> float:
	return maxf(0.0, float(DataStore.match_flow.get("battle_duration_s", 1800)) - timer)

func _enter_prepare() -> void:
	stage = Stage.PREPARE
	timer = 0.0
	## Force 1× during prepare so leftover battle speed cannot shorten the clock.
	speed_multiplier = 1.0
	var steps: Array = DataStore.match_flow.get("speed_steps", [1.0])
	_speed_step_index = 0
	for i in range(steps.size()):
		if absf(float(steps[i]) - 1.0) < 0.001:
			_speed_step_index = i
			break
	var payload := {"stage": "prepare", "battle_phase": battle_phase_value, "round_phase": round_phase_value}
	AdminBus.request(&"match.stage_change", payload)
	_board.set_prepare_mode(true)
	_combat.stop_combat()
	kills_this_round_player = 0
	kills_this_round_ai = 0
	stage_changed.emit(stage)
	hud_refresh.emit()

func _on_prepare_complete() -> void:
	var payload := {"stage": "battle", "battle_phase": battle_phase_value, "round_phase": round_phase_value}
	var res := AdminBus.request(&"match.stage_change", payload)
	if not res.get("accepted", true):
		return
	stage = Stage.BATTLE
	timer = 0.0
	_sim_accum = 0.0
	_board.set_prepare_mode(false)
	_combat.start_combat()
	if _board.is_one_side_cleared():
		var p := _board.count_alive_field(ShipUnit.TEAM_PLAYER)
		var a := _board.count_alive_field(ShipUnit.TEAM_AI)
		if p == 0:
			notice.emit("场上无己方舰船，本回合将快速结算")
		elif a == 0:
			notice.emit("敌方场上无舰，本回合将快速结算")
		print("[match] battle open with empty side player=%d ai=%d — wipe after min_battle" % [p, a])
	stage_changed.emit(stage)

func _on_combat_complete(reason: String = "wipe") -> void:
	_combat.stop_combat()
	print("[match] combat complete reason=%s player_field=%d ai_field=%d round=%d-%d" % [
		reason,
		_board.count_alive_field(ShipUnit.TEAM_PLAYER),
		_board.count_alive_field(ShipUnit.TEAM_AI),
		battle_phase_value,
		round_phase_value,
	])
	battle_game_stage_count += 1
	round_phase_value += 1
	var max_rp := int(DataStore.match_flow.get("max_round_phase_value", 5))
	if round_phase_value > max_rp:
		round_phase_value = 1
		battle_phase_value += 1
	_resolve_citadel_and_income()
	_board.reset_ships_after_round()
	_board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	_board.recalculate_fetters(ShipUnit.TEAM_AI)
	_board.try_upgrades_all()
	if not shop_locked:
		_shop.refresh_shop(true)
	_grant_exp(int(DataStore.economy.get("base_exp_income", 4)))
	_ai.after_round()
	if player_hp <= 0:
		_end_match()
		return
	_enter_prepare()

func _match_round_number() -> int:
	## 1-based round index used by early income / citadel bands.
	return maxi(1, battle_game_stage_count)

func _citadel_base_damage() -> int:
	var round_n := _match_round_number()
	var bands: Array = DataStore.match_flow.get("citadel_base_damage_by_round_band", [])
	for b in bands:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		if round_n <= int(b.get("max_round", 999)):
			return int(b.get("base", 0))
	return 0

func _citadel_ship_damage_sum(team: int) -> int:
	## Placeholder: cost × star for each alive field ship (unmanned excluded).
	var total := 0
	for s in _board.field_ships(team):
		if s.is_destroyed or s.is_unmanned:
			continue
		var cost := int(DataStore.get_ship(s.ship_id).get("cost", 1))
		total += maxi(1, cost * s.star)
	return total

func _resolve_citadel_and_income() -> void:
	## §11.1: total = round base + Σ surviving piece damage
	var base := _citadel_base_damage()
	var p_alive := _board.count_alive_field(ShipUnit.TEAM_PLAYER)
	var ai_alive := _board.count_alive_field(ShipUnit.TEAM_AI)
	var p_dmg := 0
	if p_alive > 0:
		p_dmg = base + _citadel_ship_damage_sum(ShipUnit.TEAM_PLAYER)
	var a_dmg := 0
	if ai_alive > 0:
		a_dmg = base + _citadel_ship_damage_sum(ShipUnit.TEAM_AI)
	var player_won := p_alive > 0 and ai_alive == 0
	var ai_won := ai_alive > 0 and p_alive == 0
	if a_dmg > 0 and ai_alive > 0:
		var cit := {"source_team": ShipUnit.TEAM_AI, "target_team": ShipUnit.TEAM_PLAYER, "damage": a_dmg, "alive_ships": ai_alive}
		var r := AdminBus.request(&"citadel.damage", cit)
		if r.get("accepted", true):
			var p2: Dictionary = r.get("payload", cit)
			_take_player_damage(int(p2.get("damage", a_dmg)))
	if mode != "endless" and p_dmg > 0 and p_alive > 0:
		AdminBus.request(&"citadel.damage", {"source_team": ShipUnit.TEAM_PLAYER, "target_team": ShipUnit.TEAM_AI, "damage": p_dmg, "alive_ships": p_alive})
	_update_streaks(player_won)
	if _ai and _ai.has_method("update_streaks"):
		_ai.update_streaks(ai_won)
	_apply_income(ShipUnit.TEAM_PLAYER, player_won, kills_this_round_player)
	if _ai and _ai.has_method("apply_income"):
		_ai.apply_income(ai_won, kills_this_round_ai)

func _update_streaks(player_won: bool) -> void:
	if player_won:
		win_streak += 1
		loss_streak = 0
	else:
		loss_streak += 1
		win_streak = 0

func _streak_bonus(streak: int) -> int:
	var table: Dictionary = DataStore.economy.get("streak_gold", {"3": 1, "5": 2, "7": 3})
	var best := 0
	for k in table.keys():
		var need := int(k)
		if streak >= need:
			best = maxi(best, int(table[k]))
	return best

func _base_income_for_round() -> int:
	var eco: Dictionary = DataStore.economy
	var by_r: Array = eco.get("base_gold_income_by_round", [2, 3, 4])
	var r := _match_round_number()
	if r <= by_r.size():
		return int(by_r[r - 1])
	return int(eco.get("base_gold_income", 5))

func _apply_income(team: int, won: bool, kills: int) -> void:
	var eco: Dictionary = DataStore.economy
	var gold_ref: int = player_gold if team == ShipUnit.TEAM_PLAYER else (int(_ai.ai_gold) if _ai else 0)
	var interest: int = int(floor(float(gold_ref) / float(eco.get("interest_divisor", 10))))
	var cap: int = int(eco.get("interest_cap", 5))
	if bool(eco.get("interest_capped", true)):
		interest = mini(interest, cap)
	var base: int = _base_income_for_round()
	var win_g: int = int(eco.get("win_gold", 1)) if won else 0
	var streak: int = win_streak if team == ShipUnit.TEAM_PLAYER else (_ai.win_streak if _ai else 0)
	if not won:
		streak = loss_streak if team == ShipUnit.TEAM_PLAYER else (_ai.loss_streak if _ai else 0)
	var streak_g: int = _streak_bonus(streak)
	var kill_g: int = kills * int(eco.get("kill_gold_per_ship", 1))
	var income: int = base + interest + win_g + streak_g + kill_g
	var payload := {
		"team": team,
		"base": base,
		"interest": interest,
		"win": win_g,
		"streak": streak_g,
		"kills": kill_g,
		"income": income,
	}
	var r := AdminBus.request(&"economy.income", payload)
	var p2: Dictionary = r.get("payload", payload)
	var final_income := int(p2.get("income", income))
	if team == ShipUnit.TEAM_PLAYER:
		player_gold += final_income
		notice.emit("你收入了%d黄币" % final_income)
	elif _ai and _ai.has_method("add_gold"):
		_ai.add_gold(final_income)

func _on_admin_after(channel: StringName, payload: Dictionary, result: Dictionary) -> void:
	if String(channel) != "combat.hit":
		return
	if not bool(result.get("destroyed", false)):
		return
	var src: ShipUnit = instance_from_id(int(payload.get("source_id", 0))) as ShipUnit
	var tgt: ShipUnit = instance_from_id(int(payload.get("target_id", 0))) as ShipUnit
	if tgt == null or tgt.is_unmanned:
		return
	if src == null:
		return
	if src.team_id == ShipUnit.TEAM_PLAYER:
		kills_this_round_player += 1
	elif src.team_id == ShipUnit.TEAM_AI:
		kills_this_round_ai += 1

func _take_player_damage(amount: int) -> void:
	player_hp = maxi(0, player_hp - amount)
	notice.emit("主堡受到 %d 伤害" % amount)

func _grant_exp(amount: int) -> void:
	player_exp += amount
	var eco: Dictionary = DataStore.economy
	var inc: int = int(eco.get("level_exp_demand_increment", 8))
	while player_exp >= up_level_demand:
		player_exp -= up_level_demand
		player_level += 1
		up_level_demand += inc
	hud_refresh.emit()

func buy_exp() -> void:
	var eco: Dictionary = DataStore.economy
	var cost: int = int(eco.get("buy_exp_gold_cost", 4))
	var amt: int = int(eco.get("buy_exp_amount", 4))
	var payload := {"gold_cost": cost, "exp_amount": amt, "team": ShipUnit.TEAM_PLAYER}
	var r := AdminBus.request(&"shop.buy_exp", payload)
	if not r.get("accepted", true):
		return
	cost = int(payload.get("gold_cost", cost))
	amt = int(payload.get("exp_amount", amt))
	if player_gold < cost:
		notice.emit("黄币不足")
		return
	player_gold -= cost
	_grant_exp(amt)

func try_spend(amount: int) -> bool:
	if player_gold < amount:
		return false
	player_gold -= amount
	hud_refresh.emit()
	return true

func add_gold(amount: int) -> void:
	player_gold += amount
	hud_refresh.emit()

func population_limit() -> int:
	return mini(player_level + int(DataStore.board.get("ship_count_buff", 0)), int(DataStore.board.get("max_deployment", 999)))

func prepare_remaining() -> float:
	return maxf(0.0, float(DataStore.match_flow.get("prepare_duration_s", 16)) - timer)

func battle_elapsed() -> float:
	return timer

func skip_prepare() -> void:
	if stage != Stage.PREPARE or not _running:
		return
	_on_prepare_complete()

func _end_match() -> void:
	stage = Stage.GAME_END
	_running = false
	var summary := "最终等级为 %d" % player_level
	match_over.emit(summary)
	stage_changed.emit(stage)
