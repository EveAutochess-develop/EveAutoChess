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
var player_gold_earned: int = 0
var player_hp: int = 1000
var player_max_hp: int = 1000
var ai_hp: int = 1000
var ai_max_hp: int = 1000
var player_level: int = 1
var player_exp: int = 0
var up_level_demand: int = 4
var shop_locked: bool = false
var speed_multiplier: float = 1.0
var _preferred_battle_speed: float = 1.0

var win_streak: int = 0
var loss_streak: int = 0
var kills_this_round_player: int = 0
var kills_this_round_ai: int = 0

## Round outcome frozen the moment combat ends. `reset_ships_after_round()` revives every
## field hull before `stage_changed(PREPARE)` fires, so listeners must never re-count the
## board to decide who won (that read every PVP round as a draw → winner ate a doomsday).
var last_round_result: String = "draw"  ## win | lose | draw, from the player's side
var last_round_player_field: int = 0
var last_round_ai_field: int = 0
var last_round_freighter_alive: bool = false

var _board: BoardController
var _shop: ShopController
var _combat: CombatResolver
var _ai: AiController
var _cyno: CynoController
var _running: bool = false
var _speed_step_index: int = 0
var _sim_accum: float = 0.0
## True when battle opens with either side already empty (symmetric instant wipe; no min_battle wait).
var _battle_opened_empty: bool = false

func bind(board: BoardController, shop: ShopController, combat: CombatResolver, ai: AiController) -> void:
	_board = board
	_shop = shop
	_combat = combat
	_ai = ai
	_cyno = CynoController.new()
	_cyno.bind(board, self, combat)
	AdminBus.after_handoff.connect(_on_admin_after)

func start_match(p_mode: String) -> void:
	mode = p_mode
	var mf: Dictionary = DataStore.match_flow
	var eco: Dictionary = DataStore.economy
	player_gold = int(eco.get("base_gold", 5))
	player_gold_earned = 0
	player_max_hp = int(mf.get("player_max_hp", 1000))
	player_hp = player_max_hp
	ai_max_hp = int(mf.get("ai_max_hp", mf.get("player_max_hp", 1000)))
	ai_hp = ai_max_hp
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
	if mode != "nullsec":
		_ai.init_army()
	_enter_prepare()

func _process(delta: float) -> void:
	if not _running or stage == Stage.GAME_END:
		return
	## 倍速只放大仿真步长；禁止用 Engine.time_scale / 抬 max_fps 冒充加速。
	var sim_delta: float = delta * speed_multiplier
	timer += sim_delta
	var mf: Dictionary = DataStore.match_flow
	if stage == Stage.PREPARE:
		var dur := _prepare_duration_s()
		if timer >= dur:
			_on_prepare_complete()
	elif stage == Stage.BATTLE:
		var fixed := maxf(0.001, float(mf.get("sim_fixed_step_s", 0.05)))
		var max_steps := maxi(1, int(mf.get("sim_max_steps_per_frame", 8)))
		_sim_accum += sim_delta
		var steps := 0
		while _sim_accum >= fixed and steps < max_steps:
			_combat.tick(fixed)
			if _cyno:
				_cyno.tick(_combat.sim_time())
			_sim_accum -= fixed
			steps += 1
		## Leftover accum waits for next render frame — do not burn FPS catching up.
		var bdur := float(mf.get("battle_duration_s", 1800))
		## Opened empty (either side): skip wait — same rule for player and AI. Mid-fight wipe still uses min_battle.
		var min_b := 0.0 if _battle_opened_empty else float(mf.get("min_battle_duration_s", 1.25))
		if timer >= bdur:
			notice.emit("战斗未能在时限内结束")
			_on_combat_complete("timeout")
		elif timer >= min_b and _board.is_one_side_cleared():
			## Cleared field ends the round at once (CAPITAL_AND_CYNO §2): channels never hold it open.
			_on_combat_complete("wipe")
		## Glow countdown uses scaled battle time (same clock as HUD), not render FPS / substep catch-up.
		if _board:
			for s in _board.all_ships():
				if s != null and is_instance_valid(s) and not s.is_destroyed:
					s.tick_combat_glow(sim_delta)
	hud_refresh.emit()

func _init_speed_multiplier() -> void:
	_load_preferred_battle_speed()
	var mf: Dictionary = DataStore.match_flow
	var steps: Array = mf.get("speed_steps", [0.2, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0])
	## Preferred is for Battle; Prepare forces 1× in _enter_prepare.
	speed_multiplier = _preferred_battle_speed
	_speed_step_index = 0
	for i in range(steps.size()):
		if absf(float(steps[i]) - speed_multiplier) < 0.001:
			_speed_step_index = i
			return
	for i in range(steps.size()):
		if float(steps[i]) >= speed_multiplier:
			_speed_step_index = i
			speed_multiplier = float(steps[i])
			_preferred_battle_speed = speed_multiplier
			return
	if steps.size() > 0:
		_speed_step_index = steps.size() - 1
		speed_multiplier = float(steps[_speed_step_index])
		_preferred_battle_speed = speed_multiplier

func _load_preferred_battle_speed() -> void:
	var mf: Dictionary = DataStore.match_flow
	var fallback := float(mf.get("speed_multiplier", 1.0))
	_preferred_battle_speed = fallback
	var cf := ConfigFile.new()
	if cf.load(GameSession.SETTINGS_PATH) != OK:
		return
	_preferred_battle_speed = float(cf.get_value("match", "battle_speed", fallback))

func _save_preferred_battle_speed() -> void:
	var cf := ConfigFile.new()
	cf.load(GameSession.SETTINGS_PATH)
	cf.set_value("match", "battle_speed", _preferred_battle_speed)
	cf.save(GameSession.SETTINGS_PATH)

func cycle_speed() -> void:
	if stage == Stage.PREPARE:
		return
	var steps: Array = DataStore.match_flow.get("speed_steps", [0.2, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0])
	if steps.is_empty():
		return
	_speed_step_index = (_speed_step_index + 1) % steps.size()
	speed_multiplier = float(steps[_speed_step_index])
	_preferred_battle_speed = speed_multiplier
	## Never couple 倍速 to render FPS or Engine.time_scale.
	Engine.time_scale = 1.0
	_save_preferred_battle_speed()
	hud_refresh.emit()

func set_battle_speed(speed: float) -> void:
	if stage == Stage.PREPARE:
		return
	speed_multiplier = maxf(0.05, speed)
	_preferred_battle_speed = speed_multiplier
	Engine.time_scale = 1.0
	_save_preferred_battle_speed()
	hud_refresh.emit()

func force_draw_battle() -> void:
	## Wall-clock timeout draw for remaining nullsec battles.
	if stage != Stage.BATTLE or not _running:
		return
	notice.emit("平局（墙钟时限）")
	_on_combat_complete("draw_timeout")

func speed_label() -> String:
	if speed_multiplier >= 1.0 and fmod(speed_multiplier, 1.0) < 0.001:
		return "%dx" % int(speed_multiplier)
	return "%.1fx" % speed_multiplier

func battle_remaining() -> float:
	return maxf(0.0, float(DataStore.match_flow.get("battle_duration_s", 1800)) - timer)

func _enter_prepare() -> void:
	stage = Stage.PREPARE
	timer = 0.0
	## Force 1× during prepare; keep preferred battle speed for next Battle.
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
	## First prepare pass: any pending 3-of-a-kind from last round / hangar merges now.
	_board.try_upgrades_all()
	_combat.stop_combat()
	kills_this_round_player = 0
	kills_this_round_ai = 0
	if _cyno:
		_cyno.on_prepare_start()
	## Cyno-gated hulls return to hangar for next induction (MATCH_FLOW §5.0b).
	if _board and _board.has_method("recall_cyno_entry_ships_to_hangar"):
		_board.recall_cyno_entry_ships_to_hangar()
	## Heal empty shop (bad save / mid-refresh persist).
	if _shop and _shop.slots.is_empty() and not shop_locked:
		_shop.refresh_shop(true, false)
	stage_changed.emit(stage)
	hud_refresh.emit()
	## Single rolling snapshot at prepare open (开局前), not mid-buy / mid-drag.
	_autosave_match()

func _on_prepare_complete() -> void:
	if mode != "nullsec" and _ai and _ai.has_method("finalize_prepare"):
		_ai.finalize_prepare()
	var payload := {"stage": "battle", "battle_phase": battle_phase_value, "round_phase": round_phase_value}
	var res := AdminBus.request(&"match.stage_change", payload)
	if not res.get("accepted", true):
		return
	stage = Stage.BATTLE
	timer = 0.0
	_sim_accum = 0.0
	## Restore preferred battle speed (clears prepare-only skip turbo).
	var steps: Array = DataStore.match_flow.get("speed_steps", [1.0])
	speed_multiplier = _preferred_battle_speed
	_speed_step_index = 0
	for i in range(steps.size()):
		if absf(float(steps[i]) - speed_multiplier) < 0.001:
			_speed_step_index = i
			break
	_board.set_prepare_mode(false)
	_combat.start_combat()
	if _cyno:
		_cyno.on_battle_start(0.0)
	_battle_opened_empty = _board.is_one_side_cleared()
	if _battle_opened_empty:
		var p := _board.count_alive_field(ShipUnit.TEAM_PLAYER)
		var a := _board.count_alive_field(ShipUnit.TEAM_AI)
		## Symmetric notice — either side empty skips the fight wait.
		if p == 0 and a == 0:
			notice.emit("双方场上无舰，本回合跳过")
		elif p == 0:
			notice.emit("场上无己方舰船，本回合跳过")
		else:
			notice.emit("敌方场上无舰，本回合跳过")
		print("[match] battle open with empty side player=%d ai=%d — skip wipe" % [p, a])
	stage_changed.emit(stage)

func skip_prepare() -> void:
	## Prepare-only turbo: accelerate the prepare timer (does not jump stages).
	if stage != Stage.PREPARE or not _running:
		return
	speed_multiplier = float(DataStore.match_flow.get("prepare_skip_speed", 100.0))
	hud_refresh.emit()
	notice.emit("备战加速 ×%d" % int(speed_multiplier))

func _abort_cyno_channels() -> void:
	if _cyno != null and _cyno.has_active_channels():
		_cyno.abort_channels()

func _on_combat_complete(reason: String = "wipe") -> void:
	_combat.stop_combat()
	_abort_cyno_channels()
	_battle_opened_empty = false
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
	_snapshot_round_outcome()
	_resolve_citadel_and_income()
	_board.reset_ships_after_round()
	_board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	_board.recalculate_fetters(ShipUnit.TEAM_AI)
	## Star merges wait for Prepare (`try_upgrades_all` is prepare-gated).
	if not shop_locked:
		_shop.refresh_shop(true)
	_grant_exp(int(DataStore.economy.get("base_exp_income", 4)))
	_ai.after_round()
	if player_hp <= 0 or (mode != "endless" and ai_hp <= 0):
		_end_match()
		return
	_enter_prepare()

## Freeze who was standing at the final combat tick, before hulls are reloaded.
func _snapshot_round_outcome() -> void:
	last_round_player_field = _board.count_alive_field(ShipUnit.TEAM_PLAYER) if _board else 0
	last_round_ai_field = _board.count_alive_field(ShipUnit.TEAM_AI) if _board else 0
	if last_round_player_field > 0 and last_round_ai_field <= 0:
		last_round_result = "win"
	elif last_round_ai_field > 0 and last_round_player_field <= 0:
		last_round_result = "lose"
	else:
		last_round_result = "draw"
	last_round_freighter_alive = false
	if _board:
		for s in _board.all_ships():
			if s == null or not is_instance_valid(s) or not s.is_protect_target:
				continue
			if not s.is_destroyed and float(s.structure_hp) > 0.01:
				last_round_freighter_alive = true
				break

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
		var cit_ai := {"source_team": ShipUnit.TEAM_PLAYER, "target_team": ShipUnit.TEAM_AI, "damage": p_dmg, "alive_ships": p_alive}
		var r_ai := AdminBus.request(&"citadel.damage", cit_ai)
		if r_ai.get("accepted", true):
			var a2: Dictionary = r_ai.get("payload", cit_ai)
			_take_ai_damage(int(a2.get("damage", p_dmg)))
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
	var mining_g: int = _mining_gold_for_team(team)
	var income: int = base + interest + win_g + streak_g + kill_g + mining_g
	## Dev: same AI income ×mul on combat part only (mining stays raw).
	if team == ShipUnit.TEAM_PLAYER and GameSession and GameSession.player_ai_double_economy_active():
		var mul: float = float(DataStore.ai.get("ai_gold_income_buff_mul", 2.0))
		var combat_part := income - mining_g
		income = int(round(float(combat_part) * mul)) + mining_g
	var payload := {
		"team": team,
		"base": base,
		"interest": interest,
		"win": win_g,
		"streak": streak_g,
		"kills": kill_g,
		"mining": mining_g,
		"income": income,
	}
	var r := AdminBus.request(&"economy.income", payload)
	var p2: Dictionary = r.get("payload", payload)
	var final_income := int(p2.get("income", income))
	if team == ShipUnit.TEAM_PLAYER:
		player_gold += final_income
		player_gold_earned += maxi(0, final_income)
		if mining_g > 0:
			notice.emit("你收入了%d黄币（含采矿%d）" % [final_income, mining_g])
		else:
			notice.emit("你收入了%d黄币" % final_income)
	elif _ai and _ai.has_method("add_gold"):
		_ai.add_gold(final_income)


func _mining_gold_for_team(team: int) -> int:
	## MINING_AND_DUST §3–4: Field survivors; ★k × base; Porpoise command +20% on other sources (floor).
	if _board == null:
		return 0
	var has_command := false
	for s in _board.field_ships(team):
		if s == null or s.is_destroyed or s.is_unmanned:
			continue
		var sd0: Dictionary = DataStore.get_ship(s.ship_id)
		if "mining_command" in sd0.get("fetter_ids", []) or int(s.ship_id) == 136:
			has_command = true
			break
	var total := 0
	for s in _board.field_ships(team):
		if s == null or s.is_destroyed:
			continue
		var sd: Dictionary = DataStore.get_ship(s.ship_id)
		var base_g := int(sd.get("mining_gold_per_round", 0))
		if base_g <= 0:
			continue
		## Excavators only pay while mother still alive (orphan cull runs in stop_combat).
		if s.is_unmanned and str(s.unmanned_kind) == "mining_excavator":
			var mother := instance_from_id(s.mother_ship_id) as ShipUnit
			if mother == null or not is_instance_valid(mother) or mother.is_destroyed:
				continue
		var star_mul := maxi(int(s.star), 1)
		var starred := base_g * star_mul
		var is_porpoise: bool = false
		if not s.is_unmanned:
			var fids = sd.get("fetter_ids", [])
			is_porpoise = int(s.ship_id) == 136 or ("mining_command" in fids)
		if has_command and not is_porpoise:
			total += int(floor(float(starred) * 1.2))
		else:
			total += starred
	return total

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
	var dmg := amount
	## Soften only when Settings → 开发者调试 → 我方扣血软化 is on (default off).
	if GameSession and GameSession.player_citadel_soften_active():
		var mf: Dictionary = DataStore.match_flow
		dmg = int(mf.get("citadel_test_loss_damage", 1))
	player_hp = maxi(0, player_hp - dmg)
	notice.emit("主堡受到 %d 伤害" % dmg)

func _take_ai_damage(amount: int) -> void:
	## Developer soften never applies to AI; full formula always.
	var dmg := maxi(0, amount)
	ai_hp = maxi(0, ai_hp - dmg)
	notice.emit("对手主堡受到 %d 伤害" % dmg)

func _grant_exp(amount: int) -> void:
	player_exp += amount
	var eco: Dictionary = DataStore.economy
	var inc: int = int(eco.get("level_exp_demand_increment", 8))
	while player_exp >= up_level_demand:
		player_exp -= up_level_demand
		player_level += 1
		up_level_demand += inc
	hud_refresh.emit()


## Demand for next level after reaching `level` (1-based).
static func exp_demand_for_level(level: int) -> int:
	var eco: Dictionary = DataStore.economy
	var initial := int(eco.get("initial_level_exp_demand", 4))
	var inc := int(eco.get("level_exp_demand_increment", 8))
	return initial + maxi(0, level - 1) * inc


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
	request_autosave()

func try_spend(amount: int) -> bool:
	if player_gold < amount:
		return false
	player_gold -= amount
	hud_refresh.emit()
	return true

func add_gold(amount: int) -> void:
	player_gold += amount
	if amount > 0:
		player_gold_earned += amount
	hud_refresh.emit()

func population_limit() -> int:
	return mini(player_level + int(DataStore.board.get("ship_count_buff", 0)), int(DataStore.board.get("max_deployment", 999)))

func prepare_remaining() -> float:
	return maxf(0.0, _prepare_duration_s() - timer)

func _prepare_duration_s() -> float:
	var base := float(DataStore.match_flow.get("prepare_duration_s", 16))
	## New match first prepare only (`battle_game_stage_count` still 0 until after first battle).
	if battle_game_stage_count == 0:
		base += float(DataStore.match_flow.get("prepare_first_round_bonus_s", 10))
	return base

func battle_elapsed() -> float:
	return timer

func _end_match() -> void:
	stage = Stage.GAME_END
	_running = false
	if mode != "nullsec":
		## A nullsec match never owned last_match, so it must not clear it either.
		MatchSave.clear()
	var summary: String
	if player_hp <= 0 and (mode == "endless" or ai_hp > 0):
		summary = "主堡失守 · 最终等级 %d" % player_level
	elif mode != "endless" and ai_hp <= 0:
		summary = "击破对手主堡 · 最终等级 %d" % player_level
	else:
		summary = "最终等级为 %d" % player_level
	match_over.emit(summary)
	stage_changed.emit(stage)

func _autosave_match() -> void:
	if stage != Stage.PREPARE:
		return
	if mode == "nullsec":
		## Multiplayer rounds are unresumable offline, and writing here would also
		## bury the single-player last_match (MATCH_FLOW §5.0b 负安多人局不入存档).
		return
	if GameSession and bool(GameSession.get("resume_save")):
		## Resume path loads into memory then applies; skip overwriting the slot mid-start.
		return
	if _board and _board.has_method("recall_cyno_entry_ships_to_hangar"):
		_board.recall_cyno_entry_ships_to_hangar()
	MatchSave.save_from_match(self, _board, _ai)


## Rolling last_match only at prepare open. Mid-prepare buy/drag must not rewrite roster.
## Return-to-menu / explicit named save still call save_from_match (or force_autosave).
func request_autosave() -> void:
	pass


func force_autosave() -> void:
	_autosave_match()
