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

var _board: BoardController
var _shop: ShopController
var _combat: CombatResolver
var _ai: AiController
var _running: bool = false

func bind(board: BoardController, shop: ShopController, combat: CombatResolver, ai: AiController) -> void:
	_board = board
	_shop = shop
	_combat = combat
	_ai = ai

func start_match(p_mode: String) -> void:
	mode = p_mode
	var mf := DataStore.match_flow
	var eco := DataStore.economy
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
	_running = true
	_board.reset_match()
	_shop.refresh_shop(true)
	_ai.init_army()
	_enter_prepare()

func _process(delta: float) -> void:
	if not _running or stage == Stage.GAME_END:
		return
	timer += delta
	var mf := DataStore.match_flow
	if stage == Stage.PREPARE:
		var dur := float(mf.get("prepare_duration_s", 16))
		if timer >= dur:
			_on_prepare_complete()
	elif stage == Stage.BATTLE:
		_combat.tick(delta)
		var bdur := float(mf.get("battle_duration_s", 60))
		var min_b := float(mf.get("min_battle_duration_s", 1.25))
		if timer >= bdur:
			notice.emit("战斗未能在时限内结束")
			_on_combat_complete("timeout")
		elif timer >= min_b and _board.is_one_side_cleared():
			_on_combat_complete("wipe")
	hud_refresh.emit()

func _enter_prepare() -> void:
	stage = Stage.PREPARE
	timer = 0.0
	var payload := {"stage": "prepare", "battle_phase": battle_phase_value, "round_phase": round_phase_value}
	AdminBus.request(&"match.stage_change", payload)
	_board.set_prepare_mode(true)
	_combat.stop_combat()
	stage_changed.emit(stage)
	hud_refresh.emit()

func _on_prepare_complete() -> void:
	var payload := {"stage": "battle", "battle_phase": battle_phase_value, "round_phase": round_phase_value}
	var res := AdminBus.request(&"match.stage_change", payload)
	if not res.get("accepted", true):
		return
	stage = Stage.BATTLE
	timer = 0.0
	_board.set_prepare_mode(false)
	_combat.start_combat()
	# Unity: 若一方场上无舰则快速结束本回合。延迟 min_battle 再结，避免准备→结算闪帧。
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
	_board.try_upgrades_all()
	if not shop_locked:
		_shop.refresh_shop(true)
	_grant_exp(int(DataStore.economy.get("base_exp_income", 4)))
	_ai.after_round()
	if player_hp <= 0:
		_end_match()
		return
	_enter_prepare()

func _resolve_citadel_and_income() -> void:
	var constant := int(DataStore.match_flow.get("citadel_damage_constant", 18))
	# Player damage to AI
	var p_alive := _board.count_alive_field(ShipUnit.TEAM_PLAYER)
	var p_dmg := 0
	if p_alive > 0:
		p_dmg = (p_alive + constant) * (1 + battle_phase_value)
	var ai_alive := _board.count_alive_field(ShipUnit.TEAM_AI)
	var a_dmg := 0
	if ai_alive > 0:
		a_dmg = (ai_alive + constant) * (1 + battle_phase_value)
	# Apply to player from AI
	if a_dmg > 0:
		var cit := {"source_team": ShipUnit.TEAM_AI, "target_team": ShipUnit.TEAM_PLAYER, "damage": a_dmg, "alive_ships": ai_alive}
		var r := AdminBus.request(&"citadel.damage", cit)
		if r.get("accepted", true):
			var p2: Dictionary = r.get("payload", cit)
			_take_player_damage(int(p2.get("damage", a_dmg)))
	# Endless AI ignores damage; versus tracks conceptually only (no AI HP UI required for v1)
	if mode != "endless" and p_dmg > 0:
		AdminBus.request(&"citadel.damage", {"source_team": ShipUnit.TEAM_PLAYER, "target_team": ShipUnit.TEAM_AI, "damage": p_dmg, "alive_ships": p_alive})
	_apply_income()

func _take_player_damage(amount: int) -> void:
	player_hp = maxi(0, player_hp - amount)
	notice.emit("主堡受到 %d 伤害" % amount)

func _apply_income() -> void:
	var eco := DataStore.economy
	var interest := int(floor(float(player_gold) / float(eco.get("interest_divisor", 10))))
	var income := int(eco.get("base_gold_income", 5)) + interest
	var payload := {"team": ShipUnit.TEAM_PLAYER, "base": int(eco.get("base_gold_income", 5)), "interest": interest, "income": income}
	var r := AdminBus.request(&"economy.income", payload)
	var p2: Dictionary = r.get("payload", payload)
	var final_income := int(p2.get("income", income))
	player_gold += final_income
	notice.emit("你收入了%dPLEX" % final_income)

func _grant_exp(amount: int) -> void:
	player_exp += amount
	var eco := DataStore.economy
	var inc := int(eco.get("level_exp_demand_increment", 8))
	while player_exp >= up_level_demand:
		player_exp -= up_level_demand
		player_level += 1
		up_level_demand += inc
	hud_refresh.emit()

func buy_exp() -> void:
	var eco := DataStore.economy
	var cost := int(eco.get("buy_exp_gold_cost", 4))
	var amt := int(eco.get("buy_exp_amount", 4))
	var payload := {"gold_cost": cost, "exp_amount": amt, "team": ShipUnit.TEAM_PLAYER}
	var r := AdminBus.request(&"shop.buy_exp", payload)
	if not r.get("accepted", true):
		return
	cost = int(payload.get("gold_cost", cost))
	amt = int(payload.get("exp_amount", amt))
	if player_gold < cost:
		notice.emit("PLEX不足")
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
	## Instantly end prepare and start this round's battle (same path as timer expiry).
	if stage != Stage.PREPARE or not _running:
		return
	_on_prepare_complete()

func _end_match() -> void:
	stage = Stage.GAME_END
	_running = false
	var summary := "最终等级为 %d" % player_level
	match_over.emit(summary)
	stage_changed.emit(stage)
