extends Node
class_name MatchController
## Prepare / Battle stage machine — timings from DataStore.match_flow.

enum Stage { PREPARE, BATTLE, GAME_END }

signal stage_changed(stage: int)
signal hud_refresh()
## Light HUD only (timer/economy labels) — MatchRoot throttles to ≤½ FPS (UI_AND_SHELL).
signal hud_tick()
signal notice(text: String)
signal match_over(summary: String)
## After deferred in-match slow-learn merge (HUD already on Prepare).
signal slow_learn_applied()
## AI Shop loop finished one Prepare slice (handbook §0.2).
signal ai_economy_finished()
## Nullsec R1 Prepare: any successful gold spend (buy/refresh/exp/equip).
signal prepare_spend_occurred()
## Nullsec MP: Prepare timer hit dur but waiting for peers (SEMI_ASYNC §3.0a).
signal prepare_awaiting_peers()

var stage: int = Stage.PREPARE
var timer: float = 0.0
var battle_game_stage_count: int = 0
var round_phase_value: int = 1
var battle_phase_value: int = 0
var mode: String = "versus"  # versus | endless
## Nullsec first Prepare: false until all contestant seats spend once.
var prepare_clock_armed: bool = true
## Nullsec MP: hold Prepare→Battle until host rpc_enter_battle.
var hold_prepare_to_battle: bool = false
var _prepare_hold_reported: bool = false
## SEMI_ASYNC §3.1a — guest watch-only: no local CombatResolver; wait for authority end.
var remote_watch_only: bool = false
## Set by MatchRoot — more reliable than signal alone under RPC flood.
var prepare_hold_callback: Callable = Callable()
## MatchRoot: lock+spawn nullsec PVE creeps with current gold before Battle opens.
var before_battle_callback: Callable = Callable()
## Diag: throttle prepare-freeze heartbeats (logcat).
var _diag_prep_freeze_acc: float = 0.0

var player_gold: int = 0
var player_gold_earned: int = 0
var player_hp: int = 1000
var player_max_hp: int = 1000
var ai_hp: int = 1000
var ai_max_hp: int = 1000
var player_level: int = 1
var player_exp: int = 0
var up_level_demand: int = 4
var speed_multiplier: float = 1.0
## Player equipment bag — up to 12 item ids (EQUIPMENT.md §1 · 3×4).
var equipment_inventory: Array[String] = []
const EQUIPMENT_INVENTORY_SIZE: int = 16
var _preferred_battle_speed: float = 1.0

var win_streak: int = 0
var loss_streak: int = 0
var kills_this_round_player: int = 0
var kills_this_round_ai: int = 0

## Round outcome frozen the moment combat ends. `reset_ships_after_round()` revives every
## field hull before `stage_changed(PREPARE)` fires, so listeners must never re-count the
## board to decide who won (that read every PVP round as a draw → winner ate a doomsday).
var last_round_result: String = "draw"  ## win | lose | draw, from the player's side
## Set when the just-finished round opened with an empty side (phantom wipe).
var last_round_empty_open: bool = false
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
## #region agent log
var _dbg_speed_jank_acc: float = 0.0
## #endregion
var _battle_clock_diag_s: float = 0.0
## True when battle opens with either side already empty (symmetric instant wipe; no min_battle wait).
var _battle_opened_empty: bool = false
## MatchRoot sets true when rival Prepare fleet was synced (empty OK) before Battle — skip 12s phantom hold.
var _empty_open_fleet_trusted: bool = false
var _concede_lock: bool = false
var _slow_learn_needs_followup: bool = false

func bind(board: BoardController, shop: ShopController, combat: CombatResolver, ai: AiController) -> void:
	_board = board
	_shop = shop
	_combat = combat
	_ai = ai
	_cyno = CynoController.new()
	_cyno.bind(board, self, combat)
	AdminBus.after_handoff.connect(_on_admin_after)


func local_ai() -> AiController:
	return _ai

func bind_cyno_rng(rng: MatchRng, serial: int = 1) -> void:
	if _cyno:
		_cyno.bind_match_rng(rng, serial)

func start_match(p_mode: String) -> void:
	mode = p_mode
	var mf: Dictionary = DataStore.match_flow
	var eco: Dictionary = DataStore.economy
	player_gold = TypedVariant.as_int(eco.get("base_gold", 5), 5)
	player_gold_earned = 0
	player_max_hp = TypedVariant.as_int(mf.get("player_max_hp", 1000), 1000)
	player_hp = player_max_hp
	ai_max_hp = TypedVariant.as_int(mf.get("ai_max_hp", mf.get("player_max_hp", 1000)), 1000)
	ai_hp = ai_max_hp
	player_level = 1
	player_exp = 0
	up_level_demand = TypedVariant.as_int(eco.get("initial_level_exp_demand", 4), 4)
	battle_game_stage_count = 0
	round_phase_value = 1
	battle_phase_value = 0
	_init_equipment_inventory()
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
	if stage == Stage.PREPARE:
		InMatchSlowLearn.tick_pending(_ai, InMatchSlowLearn.SLICE_PREPARE_MS)
		var eco_busy: bool = _ai != null and _ai.has_method("is_economy_busy") and _ai.is_economy_busy()
		if InMatchSlowLearn.has_queued() and not eco_busy:
			InMatchSlowLearn.begin_pending(self, _ai, _board)
		if _ai != null and _ai.has_method("tick_economy_turn"):
			if _ai.tick_economy_turn():
				ai_economy_finished.emit()
	var t0: int = Time.get_ticks_usec()
	## 倍速只放大仿真步长；禁止用 Engine.time_scale / 抬 max_fps 冒充加速。
	## MATCH_FLOW §2.1: clamp input delta to break hitch→larger sim_dt spiral.
	var mf_pre: Dictionary = DataStore.match_flow
	var delta_cap: float = maxf(0.016, TypedVariant.as_float(mf_pre.get("sim_input_delta_cap_s", 0.05), 0.05))
	var capped_delta: float = minf(delta, delta_cap)
	var sim_delta: float = capped_delta * speed_multiplier
	## Nullsec R1 Prepare: freeze until spend-gate arms the clock.
	if stage == Stage.PREPARE and not prepare_clock_armed:
		sim_delta = 0.0
		_diag_prep_freeze_acc += delta
		if _diag_prep_freeze_acc >= 2.0:
			_diag_prep_freeze_acc = 0.0
			print("[mp.diag] prepare_freeze mode=%s stage_count=%d timer=%.2f armed=%s" % [
				mode, battle_game_stage_count, timer, prepare_clock_armed
			])
			SessionDiagnostics.log("mp.prep_freeze", "mode=%s count=%d" % [mode, battle_game_stage_count])
	else:
		_diag_prep_freeze_acc = 0.0
	var mf: Dictionary = DataStore.match_flow
	if stage == Stage.PREPARE:
		## Prepare has no combat substep cap — HUD uses full scaled dt.
		timer += sim_delta
		var dur: float = _prepare_duration_s()
		if prepare_clock_armed and timer >= dur:
			if hold_prepare_to_battle:
				timer = dur
				if not _prepare_hold_reported:
					_prepare_hold_reported = true
					print("[mp.diag] prepare_timer_HOLD mode=%s count=%d" % [mode, battle_game_stage_count])
					SessionDiagnostics.log("mp.prep_timer_hold", "count=%d" % battle_game_stage_count)
					## Deferred: avoid re-entrancy during _process; Callable backup if signal missed.
					if prepare_hold_callback.is_valid():
						prepare_hold_callback.call_deferred()
					prepare_awaiting_peers.emit()
			else:
				_on_prepare_complete()
	elif stage == Stage.BATTLE:
		var fixed: float = maxf(0.001, TypedVariant.as_float(mf.get("sim_fixed_step_s", 0.05), 0.05))
		var base_steps: int = maxi(1, TypedVariant.as_int(mf.get("sim_max_steps_per_frame", 8), 8))
		var step_cap: int = maxi(base_steps, TypedVariant.as_int(mf.get("sim_max_steps_per_frame_cap", 48), 48))
		## Drain enough substeps for current speed at low FPS (16x @ 20-30fps needs >8).
		var need_steps: int = maxi(1, ceili(sim_delta / fixed))
		var max_steps: int = clampi(maxi(base_steps, need_steps), 1, step_cap)
		var accum_cap: float = fixed * float(max_steps)
		var budget_ms: int = maxi(4, TypedVariant.as_int(mf.get("sim_frame_budget_ms", 14), 14))
		var budget_usec: int = budget_ms * 1000
		var advanced: float = 0.0
		var fx_from: float = TypedVariant.as_float(mf.get("sim_high_speed_fx_from", 8.0), 8.0)
		var thin_fx: bool = speed_multiplier + 0.001 >= fx_from
		if _combat != null and _combat.has_method("set_high_speed_presentation"):
			_combat.call("set_high_speed_presentation", thin_fx)
		## SEMI_ASYNC §3.1a — watch peers render from authority snaps only.
		if not remote_watch_only:
			_sim_accum += sim_delta
			## MATCH_FLOW §2.1: cap debt to one frame of full drain — never bank minutes of catch-up.
			if _sim_accum > accum_cap:
				_sim_accum = accum_cap
			var steps: int = 0
			var t_budget0: int = Time.get_ticks_usec()
			while _sim_accum >= fixed and steps < max_steps:
				## Prefer frame pacing over unbounded catch-up under load.
				if steps > 0 and (Time.get_ticks_usec() - t_budget0) >= budget_usec:
					break
				var tc: int = Time.get_ticks_usec()
				_combat.tick(fixed)
				SessionDiagnostics.add_usec(&"combat", Time.get_ticks_usec() - tc)
				if _cyno:
					var ty: int = Time.get_ticks_usec()
					_cyno.tick(_combat.sim_time())
					SessionDiagnostics.add_usec(&"cyno", Time.get_ticks_usec() - ty)
				_sim_accum -= fixed
				steps += 1
			advanced = float(steps) * fixed
			if steps > 0:
				SessionDiagnostics.note_sim_steps(steps)
		else:
			_sim_accum = 0.0
			## Same drain ceiling as authority so watch HUD cannot race cyno/combat clocks.
			advanced = minf(sim_delta, accum_cap)
		## HUD / timeout / wipe gates share the drained sim clock (not uncapped sim_dt).
		timer += advanced
		## Leftover within cap waits for next frame; excess already dropped above.
		var bdur: float = TypedVariant.as_float(mf.get("battle_duration_s", 900), 900.0)
		## Opened empty (either side): skip wait — same rule for player and AI. Mid-fight wipe still uses min_battle.
		## Nullsec: only hold briefly when empty-open AND fleet never synced (phantom); synced empty settles now.
		var min_b: float = 0.0 if _battle_opened_empty else TypedVariant.as_float(mf.get("min_battle_duration_s", 1.25), 1.25)
		if _battle_opened_empty and mode == "nullsec" and not _empty_open_fleet_trusted:
			min_b = maxf(min_b, 12.0)
		## Watch-only: never self-end — host rpc_battle_ended drives complete.
		if not remote_watch_only:
			if timer >= bdur:
				notice.emit("战斗未能在时限内结束")
				_on_combat_complete("timeout")
			elif _board.salvage_objective_lost():
				## FREIGHTER §1.5: destroying the salvage target ends Battle immediately.
				_on_combat_complete("salvage_freighter_lost")
			elif timer >= min_b and _board.is_one_side_cleared():
				## Cleared field ends the round at once (CAPITAL_AND_CYNO §2): channels never hold it open.
				_on_combat_complete("wipe")
			elif timer >= min_b and _board.both_sides_no_offense():
				## Neither side can finish the other off (all remaining hulls unarmed) — call it early.
				_on_combat_complete("draw_no_offense")
		## Glow / presentation: skip entirely at high speed so FX does not starve sim budget.
		if _board and advanced > 0.0 and not thin_fx:
			for s: ShipUnit in _board.all_ships():
				if s != null and is_instance_valid(s) and not s.is_destroyed:
					s.tick_combat_glow(advanced)
		_battle_clock_diag_s += advanced
		if _battle_clock_diag_s >= 5.0:
			_battle_clock_diag_s = 0.0
			var sim_t: float = _combat.sim_time() if _combat else 0.0
			SessionDiagnostics.log(
				"battle.clock",
				"sim=%.2f timer=%.2f speed=%.2f advanced=%.3f steps_cap=%d" % [
					sim_t, timer, speed_multiplier, advanced, max_steps,
				]
			)
		# #region agent log
		## H-D/E: high-speed frame cost / step pressure (sample ~1s when ≥2×).
		if speed_multiplier + 0.001 >= 2.0:
			_dbg_speed_jank_acc += delta
			if _dbg_speed_jank_acc >= 1.0:
				_dbg_speed_jank_acc = 0.0
				_dbg_speed_log("D", "match_controller.gd:_process", "high_speed_frame", {
					"speed": speed_multiplier,
					"delta_ms": delta * 1000.0,
					"capped_delta_ms": capped_delta * 1000.0,
					"sim_delta": sim_delta,
					"need_steps": need_steps,
					"max_steps": max_steps,
					"advanced": advanced,
					"accum": _sim_accum,
					"accum_cap": accum_cap,
					"budget_ms": budget_ms,
					"match_ctrl_us": Time.get_ticks_usec() - t0,
					"thin_fx": thin_fx,
					"runId": "post-fix",
				})
		# #endregion
	hud_tick.emit()
	SessionDiagnostics.add_usec(&"match_ctrl", Time.get_ticks_usec() - t0)
	if stage == Stage.BATTLE:
		InMatchSlowLearn.tick_pending(_ai, InMatchSlowLearn.SLICE_BATTLE_MS)

func _init_speed_multiplier() -> void:
	## MATCH_FLOW §2.1: new match always opens at 1× — do not carry cross-match cfg preferred.
	_preferred_battle_speed = 1.0
	speed_multiplier = 1.0
	var steps: Array = TypedVariant.as_array(DataStore.match_flow.get("speed_steps", [0.2, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]))
	_speed_step_index = 0
	for i: int in range(steps.size()):
		if absf(TypedVariant.as_float(steps[i], 0.0) - 1.0) < 0.001:
			_speed_step_index = i
			break
	_save_preferred_battle_speed()
	# #region agent log
	_dbg_speed_log("A", "match_controller.gd:_init_speed", "init_new_match_1x", {
		"speed": speed_multiplier, "preferred": _preferred_battle_speed, "mode": mode, "runId": "post-fix"
	})
	# #endregion

func _load_preferred_battle_speed() -> void:
	var mf: Dictionary = DataStore.match_flow
	var fallback: float = TypedVariant.as_float(mf.get("speed_multiplier", 1.0), 1.0)
	_preferred_battle_speed = fallback
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(GameSession.SETTINGS_PATH) != OK:
		return
	_preferred_battle_speed = TypedVariant.as_float(cf.get_value("match", "battle_speed", fallback), fallback)

func _save_preferred_battle_speed() -> void:
	var cf: ConfigFile = ConfigFile.new()
	cf.load(GameSession.SETTINGS_PATH)
	cf.set_value("match", "battle_speed", _preferred_battle_speed)
	cf.save(GameSession.SETTINGS_PATH)

func cycle_speed() -> void:
	if stage == Stage.PREPARE:
		return
	var steps: Array = TypedVariant.as_array(DataStore.match_flow.get("speed_steps", [0.2, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]))
	if steps.is_empty():
		return
	_speed_step_index = (_speed_step_index + 1) % steps.size()
	speed_multiplier = TypedVariant.as_float(steps[_speed_step_index], speed_multiplier)
	_preferred_battle_speed = speed_multiplier
	## Never couple 倍速 to render FPS or Engine.time_scale.
	Engine.time_scale = 1.0
	## MATCH_FLOW §2.1: drop unspent scaled time so the new gear takes effect now.
	_sim_accum = 0.0
	_save_preferred_battle_speed()
	hud_refresh.emit()

func set_battle_speed(speed: float, persist_preferred: bool = true) -> void:
	## persist_preferred=false: auto finish floor (SEMI_ASYNC §4.5) — runtime only.
	if stage == Stage.PREPARE:
		# #region agent log
		_dbg_speed_log("B", "match_controller.gd:set_battle_speed", "blocked_prepare", {
			"asked": speed, "persist": persist_preferred, "cur": speed_multiplier, "preferred": _preferred_battle_speed
		})
		# #endregion
		return
	speed_multiplier = maxf(0.05, speed)
	Engine.time_scale = 1.0
	## MATCH_FLOW §2.1: clear debt on any gear change (net apply / UI / auto floor).
	_sim_accum = 0.0
	if persist_preferred:
		_preferred_battle_speed = speed_multiplier
		_save_preferred_battle_speed()
	# #region agent log
	_dbg_speed_log("C", "match_controller.gd:set_battle_speed", "applied", {
		"speed": speed_multiplier, "persist": persist_preferred, "preferred": _preferred_battle_speed, "stage": stage
	})
	# #endregion
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
	return maxf(0.0, TypedVariant.as_float(DataStore.match_flow.get("battle_duration_s", 900), 900.0) - timer)

func _enter_prepare() -> void:
	stage = Stage.PREPARE
	timer = 0.0
	## Force 1× during prepare; keep preferred battle speed for next Battle.
	speed_multiplier = 1.0
	# #region agent log
	_dbg_speed_log("B", "match_controller.gd:_enter_prepare", "prepare_force_1x", {
		"speed": speed_multiplier, "preferred": _preferred_battle_speed, "mode": mode, "count": battle_game_stage_count
	})
	# #endregion
	## Nullsec first Prepare waits for all contestant seats' first gold spend.
	## Later prepares with MP barrier also start frozen (match_root / net gate).
	prepare_clock_armed = true
	_prepare_hold_reported = false
	if mode == "nullsec" and battle_game_stage_count == 0:
		prepare_clock_armed = false
	print("[mp.diag] enter_prepare mode=%s stage_count=%d armed=%s dur=%.1f hold=%s" % [
		mode, battle_game_stage_count, prepare_clock_armed, _prepare_duration_s(), hold_prepare_to_battle
	])
	SessionDiagnostics.log(
		"mp.enter_prepare",
		"mode=%s count=%d armed=%s hold=%s" % [mode, battle_game_stage_count, prepare_clock_armed, hold_prepare_to_battle]
	)
	var steps: Array = TypedVariant.as_array(DataStore.match_flow.get("speed_steps", [1.0]))
	_speed_step_index = 0
	for i: int in range(steps.size()):
		if absf(TypedVariant.as_float(steps[i], 1.0) - 1.0) < 0.001:
			_speed_step_index = i
			break
	var payload: Dictionary = {"stage": "prepare", "battle_phase": battle_phase_value, "round_phase": round_phase_value}
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
	## Heal empty shop (bad save / mid-refresh persist). Manual refresh only — no round auto-refresh.
	if _shop and _shop.slots.is_empty():
		_shop.refresh_shop(true, false)
	stage_changed.emit(stage)
	hud_refresh.emit()
	## Single rolling snapshot at prepare open (开局前), not mid-buy / mid-drag.
	_autosave_match()
	call_deferred("_deferred_apply_slow_learn")


func _deferred_apply_slow_learn() -> void:
	InMatchSlowLearn.begin_pending(self, _ai, _board)
	if mode != "nullsec" and _ai != null:
		_ai.after_round()
	var follow: bool = _slow_learn_needs_followup
	_slow_learn_needs_followup = false
	_concede_lock = false
	if follow:
		slow_learn_applied.emit()


func _on_prepare_complete() -> void:
	var eco_was_busy: bool = (
		_ai != null and _ai.has_method("is_economy_busy") and _ai.is_economy_busy()
	)
	if _ai and _ai.has_method("force_finish_economy"):
		_ai.force_finish_economy()
	if eco_was_busy:
		ai_economy_finished.emit()
	if mode != "nullsec" and _ai and _ai.has_method("finalize_prepare"):
		_ai.finalize_prepare()
	## Nullsec PVE: re-lock creeps with current gold before combat opens (MATCH_FLOW §5.1.2).
	if before_battle_callback.is_valid():
		before_battle_callback.call()
	var payload: Dictionary = {"stage": "battle", "battle_phase": battle_phase_value, "round_phase": round_phase_value}
	var res: Dictionary = AdminBus.request(&"match.stage_change", payload)
	if not TypedVariant.as_bool(res.get("accepted", true), true):
		return
	stage = Stage.BATTLE
	timer = 0.0
	_sim_accum = 0.0
	## Restore preferred battle speed (clears prepare-only skip turbo).
	var steps: Array = TypedVariant.as_array(DataStore.match_flow.get("speed_steps", [1.0]))
	speed_multiplier = _preferred_battle_speed
	_speed_step_index = 0
	for i: int in range(steps.size()):
		if absf(TypedVariant.as_float(steps[i], speed_multiplier) - speed_multiplier) < 0.001:
			_speed_step_index = i
			break
	# #region agent log
	_dbg_speed_log("A", "match_controller.gd:_on_prepare_complete", "battle_restore_preferred", {
		"speed": speed_multiplier, "preferred": _preferred_battle_speed, "mode": mode, "count": battle_game_stage_count,
		"runId": "post-fix",
	})
	# #endregion
	_board.set_prepare_mode(false)
	_combat.start_combat()
	InMatchSlowLearn.begin_battle(_board)
	if _cyno:
		_cyno.on_battle_start(0.0)
	_battle_opened_empty = _board.is_one_side_cleared()
	if _battle_opened_empty:
		var p: int = _board.count_alive_field(ShipUnit.TEAM_PLAYER)
		var a: int = _board.count_alive_field(ShipUnit.TEAM_AI)
		var p_cyno: int = _count_field_cyno(ShipUnit.TEAM_PLAYER)
		var a_cyno: int = _count_field_cyno(ShipUnit.TEAM_AI)
		## Symmetric notice — either side empty skips the fight wait.
		if p == 0 and a == 0:
			notice.emit("双方场上无舰，本回合跳过")
		elif p == 0:
			notice.emit("场上无己方舰船，本回合跳过")
		else:
			notice.emit("敌方场上无舰，本回合跳过")
		print("[match] battle open with empty side player=%d ai=%d cyno_p=%d cyno_a=%d — skip wipe trusted=%s" % [
			p, a, p_cyno, a_cyno, _empty_open_fleet_trusted
		])
		print("[mp.diag] battle_empty_open player=%d ai=%d cyno_p=%d cyno_a=%d mode=%s trusted=%s" % [
			p, a, p_cyno, a_cyno, mode, _empty_open_fleet_trusted
		])
		SessionDiagnostics.log(
			"mp.battle_empty",
			"p=%d a=%d cyno_p=%d cyno_a=%d trusted=%s" % [p, a, p_cyno, a_cyno, _empty_open_fleet_trusted]
		)
	stage_changed.emit(stage)

func skip_prepare() -> void:
	## Prepare-only turbo: accelerate the prepare timer (does not jump stages).
	## Nullsec multiplayer: no skip (MATCH_FLOW §2.1).
	if mode == "nullsec":
		return
	if stage != Stage.PREPARE or not _running:
		return
	speed_multiplier = TypedVariant.as_float(DataStore.match_flow.get("prepare_skip_speed", 100.0), 100.0)
	hud_refresh.emit()
	notice.emit("备战加速 ×%d" % int(speed_multiplier))

func _abort_cyno_channels() -> void:
	if _cyno != null and _cyno.has_active_channels():
		_cyno.abort_channels()

func _on_combat_complete(reason: String = "wipe") -> void:
	_combat.stop_combat()
	_abort_cyno_channels()
	var was_empty_open: bool = _battle_opened_empty
	_battle_opened_empty = false
	last_round_empty_open = was_empty_open
	var pf: int = _board.count_alive_field(ShipUnit.TEAM_PLAYER) if _board else 0
	var af: int = _board.count_alive_field(ShipUnit.TEAM_AI) if _board else 0
	print("[match] combat complete reason=%s player_field=%d ai_field=%d round=%d-%d" % [
		reason, pf, af, battle_phase_value, round_phase_value,
	])
	print("[mp.diag] combat_complete reason=%s p=%d a=%d opened_empty=%s" % [
		reason, pf, af, was_empty_open
	])
	SessionDiagnostics.log(
		"mp.combat_complete",
		"reason=%s p=%d a=%d empty_open=%s" % [reason, pf, af, was_empty_open]
	)
	battle_game_stage_count += 1
	round_phase_value += 1
	var max_rp: int = TypedVariant.as_int(DataStore.match_flow.get("max_round_phase_value", 5), 5)
	if round_phase_value > max_rp:
		round_phase_value = 1
		battle_phase_value += 1
	_snapshot_round_outcome()
	InMatchSlowLearn.queue_round(self, _board)
	_slow_learn_needs_followup = true
	print("[mp.diag] round_result=%s p_field=%d a_field=%d" % [
		last_round_result, last_round_player_field, last_round_ai_field
	])
	SessionDiagnostics.log(
		"mp.round_result",
		"%s p=%d a=%d" % [last_round_result, last_round_player_field, last_round_ai_field]
	)
	## MATCH_FLOW §4.2: empty-open still settles win/lose + income (only skips battle wait).
	_resolve_citadel_and_income()
	_board.reset_ships_after_round()
	_board.force_full_hp_all_ships()
	_board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	_board.recalculate_fetters(ShipUnit.TEAM_AI)
	## Fetter passives can rescale max — pin full pipes again (MATCH_FLOW Battle→Prepare 满血).
	_board.force_full_hp_all_ships()
	## Star merges wait for Prepare (`try_upgrades_all` is prepare-gated).
	## No automatic shop refresh at round end (ECONOMY_AND_SHOP §3).
	_grant_exp(TypedVariant.as_int(DataStore.economy.get("base_exp_income", 4), 4))
	_empty_open_fleet_trusted = false
	if player_hp <= 0 or (mode != "endless" and ai_hp <= 0):
		_end_match()
		return
	_enter_prepare()


## This-round concede (MULTIPLAYER_PVP §7.0c): settle as local wipe-loss, not full match surrender.
## Nullsec barrier seats must go through host `request_concede_round` → `apply_authority_round_settle`.
func concede_current_round() -> void:
	if not _running or stage == Stage.GAME_END:
		return
	apply_authority_round_settle("lose", "concede")


## Authority round settle for Battle or Prepare (concede sync / watch peer).
func apply_authority_round_settle(mapped_result: String, reason: String = "authority") -> void:
	if not _running or stage == Stage.GAME_END:
		return
	if _concede_lock and reason == "concede":
		return
	if stage == Stage.BATTLE:
		force_authority_combat_complete(mapped_result, reason)
		return
	if stage != Stage.PREPARE:
		return
	_concede_lock = true
	_combat.stop_combat()
	_abort_cyno_channels()
	_battle_opened_empty = false
	last_round_empty_open = false
	print("[mp.diag] combat_complete_authority_prepare reason=%s result=%s" % [reason, mapped_result])
	SessionDiagnostics.log(
		"mp.combat_concede" if reason == "concede" else "mp.combat_complete_auth_prep",
		"prepare result=%s" % mapped_result
	)
	battle_game_stage_count += 1
	round_phase_value += 1
	var max_rp: int = TypedVariant.as_int(DataStore.match_flow.get("max_round_phase_value", 5), 5)
	if round_phase_value > max_rp:
		round_phase_value = 1
		battle_phase_value += 1
	last_round_player_field = 0 if mapped_result == "lose" else (_board.count_alive_field(ShipUnit.TEAM_PLAYER) if _board else 1)
	last_round_ai_field = 0 if mapped_result == "win" else (_board.count_alive_field(ShipUnit.TEAM_AI) if _board else 1)
	if last_round_ai_field <= 0 and mapped_result != "win":
		last_round_ai_field = 1
	last_round_result = mapped_result if mapped_result in ["win", "lose", "draw"] else "draw"
	last_round_freighter_alive = false
	InMatchSlowLearn.queue_round(self, _board)
	_slow_learn_needs_followup = true
	_resolve_citadel_and_income()
	_board.reset_ships_after_round()
	_board.force_full_hp_all_ships()
	_board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	_board.recalculate_fetters(ShipUnit.TEAM_AI)
	_board.force_full_hp_all_ships()
	_grant_exp(TypedVariant.as_int(DataStore.economy.get("base_exp_income", 4), 4))
	_empty_open_fleet_trusted = false
	if player_hp <= 0 or (mode != "endless" and ai_hp <= 0):
		_concede_lock = false
		_end_match()
		return
	_enter_prepare()


## SEMI_ASYNC §3.1a — watch peer: end Battle from host result (seat-perspective already mapped).
func force_authority_combat_complete(mapped_result: String, reason: String = "authority") -> void:
	if stage != Stage.BATTLE:
		return
	if _concede_lock and reason == "concede":
		return
	if reason == "concede":
		_concede_lock = true
	_combat.stop_combat()
	_abort_cyno_channels()
	var was_empty_open: bool = _battle_opened_empty
	_battle_opened_empty = false
	last_round_empty_open = was_empty_open
	print("[mp.diag] combat_complete_authority reason=%s result=%s" % [reason, mapped_result])
	SessionDiagnostics.log("mp.combat_complete_auth", "reason=%s result=%s" % [reason, mapped_result])
	battle_game_stage_count += 1
	round_phase_value += 1
	var max_rp: int = TypedVariant.as_int(DataStore.match_flow.get("max_round_phase_value", 5), 5)
	if round_phase_value > max_rp:
		round_phase_value = 1
		battle_phase_value += 1
	last_round_player_field = _board.count_alive_field(ShipUnit.TEAM_PLAYER) if _board else 0
	last_round_ai_field = _board.count_alive_field(ShipUnit.TEAM_AI) if _board else 0
	last_round_result = mapped_result if mapped_result in ["win", "lose", "draw"] else "draw"
	last_round_freighter_alive = false
	if _board:
		for s: ShipUnit in _board.all_ships():
			if s == null or not is_instance_valid(s) or not s.is_protect_target:
				continue
			if not s.is_destroyed and float(s.structure_hp) > 0.01:
				last_round_freighter_alive = true
				break
	InMatchSlowLearn.queue_round(self, _board)
	_slow_learn_needs_followup = true
	## MATCH_FLOW §4.2: empty-open still settles (authority result already mapped).
	_resolve_citadel_and_income()
	_board.reset_ships_after_round()
	_board.force_full_hp_all_ships()
	_board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	_board.recalculate_fetters(ShipUnit.TEAM_AI)
	_board.force_full_hp_all_ships()
	_grant_exp(TypedVariant.as_int(DataStore.economy.get("base_exp_income", 4), 4))
	_empty_open_fleet_trusted = false
	if player_hp <= 0 or (mode != "endless" and ai_hp <= 0):
		_concede_lock = false
		_end_match()
		return
	_enter_prepare()


func is_battle_opened_empty() -> bool:
	return _battle_opened_empty


func _count_field_cyno(team: int) -> int:
	if _board == null:
		return 0
	var n: int = 0
	for s: ShipUnit in _board.all_ships():
		if s == null or not is_instance_valid(s):
			continue
		if s.team_id != team or s.slot_type != "field" or s.is_destroyed or s.is_unmanned:
			continue
		if s.has_cyno_module():
			n += 1
	return n


func clear_battle_opened_empty() -> void:
	_battle_opened_empty = false


## MatchRoot: rival Prepare fleet (incl. empty) was synced — skip 12s phantom hold.
func mark_empty_open_fleet_trusted(trusted: bool = true) -> void:
	_empty_open_fleet_trusted = trusted


## After late rival fleet lands during an empty-open hold, resume real combat.
func resume_combat_after_empty_fleet() -> void:
	if stage != Stage.BATTLE or not _running:
		return
	_battle_opened_empty = false
	timer = 0.0
	_sim_accum = 0.0
	if _combat:
		_combat.start_combat()
		InMatchSlowLearn.begin_battle(_board)
	if _cyno:
		_cyno.on_battle_start(0.0)
	print("[mp.diag] resume_combat_after_empty_fleet")
	SessionDiagnostics.log("mp.resume_after_empty", "ok")
	notice.emit("对手舰队已同步 · 开战")
	hud_refresh.emit()

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
		for s: ShipUnit in _board.all_ships():
			if s == null or not is_instance_valid(s) or not s.is_protect_target:
				continue
			if not s.is_destroyed and float(s.structure_hp) > 0.01:
				last_round_freighter_alive = true
				break

func _match_round_number() -> int:
	## 1-based round index used by early income / citadel bands.
	return maxi(1, battle_game_stage_count)

func _citadel_base_damage() -> int:
	var round_n: int = _match_round_number()
	var bands: Array = TypedVariant.as_array(DataStore.match_flow.get("citadel_base_damage_by_round_band", []))
	for b_v: Variant in bands:
		if typeof(b_v) != TYPE_DICTIONARY:
			continue
		var b: Dictionary = b_v
		if round_n <= TypedVariant.as_int(b.get("max_round", 999), 999):
			return TypedVariant.as_int(b.get("base", 0), 0)
	return 0

func _citadel_ship_damage_sum(team: int) -> int:
	## Placeholder: cost × star for each alive field ship (unmanned excluded).
	var total: int = 0
	for s: ShipUnit in _board.field_ships(team):
		if s.is_destroyed or s.is_unmanned:
			continue
		var cost: int = TypedVariant.as_int(DataStore.get_ship(s.ship_id).get("cost", 1), 1)
		total += maxi(1, cost * s.star)
	return total

func _resolve_citadel_and_income() -> void:
	## §11.1: total = round base + Σ surviving piece damage
	## Nullsec / lowsec MP: lives are titan pipes — skip citadel damage + 主堡播报 (MULTIPLAYER_PVP §2.4).
	var skip_citadel: bool = mode == "nullsec"
	var base: int = _citadel_base_damage()
	var p_alive: int = _board.count_alive_field(ShipUnit.TEAM_PLAYER)
	var ai_alive: int = _board.count_alive_field(ShipUnit.TEAM_AI)
	var p_dmg: int = 0
	if p_alive > 0:
		p_dmg = base + _citadel_ship_damage_sum(ShipUnit.TEAM_PLAYER)
	var a_dmg: int = 0
	if ai_alive > 0:
		a_dmg = base + _citadel_ship_damage_sum(ShipUnit.TEAM_AI)
	var player_won: bool = p_alive > 0 and ai_alive == 0
	var ai_won: bool = ai_alive > 0 and p_alive == 0
	if not skip_citadel:
		if a_dmg > 0 and ai_alive > 0:
			var cit: Dictionary = {"source_team": ShipUnit.TEAM_AI, "target_team": ShipUnit.TEAM_PLAYER, "damage": a_dmg, "alive_ships": ai_alive}
			var r: Dictionary = AdminBus.request(&"citadel.damage", cit)
			if TypedVariant.as_bool(r.get("accepted", true), true):
				var p2: Dictionary = TypedVariant.as_dict(r.get("payload", cit))
				_take_player_damage(TypedVariant.as_int(p2.get("damage", a_dmg), a_dmg))
		if mode != "endless" and p_dmg > 0 and p_alive > 0:
			var cit_ai: Dictionary = {"source_team": ShipUnit.TEAM_PLAYER, "target_team": ShipUnit.TEAM_AI, "damage": p_dmg, "alive_ships": p_alive}
			var r_ai: Dictionary = AdminBus.request(&"citadel.damage", cit_ai)
			if TypedVariant.as_bool(r_ai.get("accepted", true), true):
				var a2: Dictionary = TypedVariant.as_dict(r_ai.get("payload", cit_ai))
				_take_ai_damage(TypedVariant.as_int(a2.get("damage", p_dmg), p_dmg))
	_update_streaks(player_won)
	if _ai and _ai.has_method("update_streaks"):
		_ai.update_streaks(ai_won)
	## Snapshot both incomes before granting so loss_comp interest is pre-payout.
	var p_parts: Dictionary = _compute_round_income_parts(ShipUnit.TEAM_PLAYER, player_won)
	var a_parts: Dictionary = _compute_round_income_parts(ShipUnit.TEAM_AI, ai_won)
	_grant_income_from_parts(ShipUnit.TEAM_PLAYER, player_won, ai_won, p_parts, a_parts)
	if _ai != null:
		_grant_income_from_parts(ShipUnit.TEAM_AI, ai_won, player_won, a_parts, p_parts)

func _update_streaks(player_won: bool) -> void:
	if player_won:
		win_streak += 1
		loss_streak = 0
	else:
		loss_streak += 1
		win_streak = 0

func _streak_bonus(streak: int) -> int:
	var table: Dictionary = TypedVariant.as_dict(DataStore.economy.get("streak_gold", {"3": 1, "5": 2, "7": 3}))
	var best: int = 0
	for k_v: Variant in table.keys():
		var need: int = TypedVariant.as_int(k_v, 0)
		if streak >= need:
			best = maxi(best, TypedVariant.as_int(table[k_v], 0))
	return best

func _loss_comp_rate(streak: int) -> float:
	var eco: Dictionary = DataStore.economy
	var start_r: float = TypedVariant.as_float(eco.get("loss_comp_rate_start", 0.10), 0.10)
	var step_r: float = TypedVariant.as_float(eco.get("loss_comp_rate_step", 0.20), 0.20)
	var cap_r: float = TypedVariant.as_float(eco.get("loss_comp_rate_cap", 0.70), 0.70)
	var s: int = maxi(1, streak)
	return minf(cap_r, start_r + step_r * float(s - 1))

func field_ships_cost_sum(team: int) -> int:
	## Public: nullsec PVE creep budget V_field (MATCH_FLOW §5.1.2).
	return _field_ships_cost_sum(team)


func _field_ships_cost_sum(team: int) -> int:
	if _board == null:
		return 0
	var total: int = 0
	for s: ShipUnit in _board.field_ships(team):
		if s == null or not is_instance_valid(s) or s.is_destroyed or s.is_unmanned:
			continue
		var sd: Dictionary = DataStore.get_ship(s.ship_id)
		total += maxi(0, TypedVariant.as_int(sd.get("cost", 0), 0))
	return total

func _compute_round_income_parts(team: int, won: bool) -> Dictionary:
	## Pre-loss-comp income breakdown (base+interest+win+streak+mining).
	var eco: Dictionary = DataStore.economy
	var gold_ref: int = player_gold if team == ShipUnit.TEAM_PLAYER else (int(_ai.ai_gold) if _ai else 0)
	var interest: int = floori(float(gold_ref) / TypedVariant.as_float(eco.get("interest_divisor", 10), 10.0))
	var cap: int = TypedVariant.as_int(eco.get("interest_cap", 5), 5)
	if TypedVariant.as_bool(eco.get("interest_capped", true), true):
		interest = mini(interest, cap)
	var base: int = _base_income_for_round()
	var win_g: int = TypedVariant.as_int(eco.get("win_gold", 1), 1) if won else 0
	var streak_g: int = 0
	if won:
		var streak: int = win_streak if team == ShipUnit.TEAM_PLAYER else (_ai.win_streak if _ai else 0)
		streak_g = _streak_bonus(streak)
	var mine_lines: Array = _mining_gold_lines_for_team(team)
	var mining_g: int = 0
	for line_v: Variant in mine_lines:
		mining_g += TypedVariant.as_int(TypedVariant.as_dict(line_v).get("amount", 0), 0)
	var income: int = base + interest + win_g + streak_g + mining_g
	if team == ShipUnit.TEAM_PLAYER and GameSession and (PlayerSettings.instance() as PlayerSettings).player_ai_double_economy_active():
		var mul: float = TypedVariant.as_float(DataStore.ai.get("ai_gold_income_buff_mul", 2.0), 2.0)
		var combat_part: int = income - mining_g
		income = roundi(float(combat_part) * mul) + mining_g
	elif team == ShipUnit.TEAM_AI and _ai != null:
		var mul_ai: float = TypedVariant.as_float(DataStore.ai.get("ai_gold_income_buff_mul", 2.0), 2.0)
		var combat_ai: int = income - mining_g
		income = roundi(float(combat_ai) * mul_ai) + mining_g
	return {
		"base": base,
		"interest": interest,
		"win": win_g,
		"streak": streak_g,
		"mining": mining_g,
		"mining_lines": mine_lines,
		"income": income,
	}

func _base_income_for_round() -> int:
	var eco: Dictionary = DataStore.economy
	var by_r: Array = TypedVariant.as_array(eco.get("base_gold_income_by_round", [2, 3, 4]))
	var r: int = _match_round_number()
	if r <= by_r.size():
		return TypedVariant.as_int(by_r[r - 1], 0)
	return TypedVariant.as_int(eco.get("base_gold_income", 5), 5)

func _apply_income(team: int, won: bool, _kills: int) -> void:
	## Legacy entry: compute+grant for one team (tests / callers without opponent snap).
	var parts: Dictionary = _compute_round_income_parts(team, won)
	var opp: int = ShipUnit.TEAM_AI if team == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
	var opp_won: bool = not won ## approximate; prefer _grant via stop_combat path
	var opp_parts: Dictionary = _compute_round_income_parts(opp, opp_won)
	_grant_income_from_parts(team, won, opp_won, parts, opp_parts)

func _grant_income_from_parts(
	team: int,
	won: bool,
	opponent_won: bool,
	parts: Dictionary,
	winner_or_opp_parts: Dictionary
) -> void:
	var base: int = TypedVariant.as_int(parts.get("base", 0), 0)
	var interest: int = TypedVariant.as_int(parts.get("interest", 0), 0)
	var win_g: int = TypedVariant.as_int(parts.get("win", 0), 0)
	var streak_g: int = TypedVariant.as_int(parts.get("streak", 0), 0)
	var kill_g: int = 0
	var mining_g: int = TypedVariant.as_int(parts.get("mining", 0), 0)
	var income: int = TypedVariant.as_int(parts.get("income", 0), 0)
	var loss_comp: int = 0
	if not won and opponent_won:
		var opp_team: int = ShipUnit.TEAM_AI if team == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
		var winner_income: int = TypedVariant.as_int(winner_or_opp_parts.get("income", 0), 0)
		var winner_field: int = _field_ships_cost_sum(opp_team)
		var ls: int = loss_streak if team == ShipUnit.TEAM_PLAYER else (_ai.loss_streak if _ai else 1)
		var rate: float = _loss_comp_rate(ls)
		loss_comp = int(ceili(float(winner_income + winner_field) * rate))
		income += loss_comp
		## Dual cap vs winner income: max(pct, flat) then min — ECONOMY §2.
		var core: int = base + interest + mining_g
		var tp: Dictionary = DataStore.titan_pvp if DataStore != null else {}
		var cap_mul: float = TypedVariant.as_float(tp.get("loss_comp_vs_winner_cap", 0.75), 0.75)
		var less_n: int = TypedVariant.as_int(tp.get("loss_comp_vs_winner_less", 60), 60)
		var cap_pct: int = floori(float(winner_income) * cap_mul)
		var cap_flat: int = maxi(0, winner_income - less_n)
		var cap: int = maxi(cap_pct, cap_flat)
		income = mini(income, cap)
		loss_comp = maxi(0, income - core)
	var payload: Dictionary = {
		"team": team,
		"base": base,
		"interest": interest,
		"win": win_g,
		"streak": streak_g,
		"kills": kill_g,
		"mining": mining_g,
		"loss_comp": loss_comp,
		"income": income,
	}
	var r: Dictionary = AdminBus.request(&"economy.income", payload)
	var p2: Dictionary = TypedVariant.as_dict(r.get("payload", payload))
	var final_income: int = TypedVariant.as_int(p2.get("income", income), income)
	if team == ShipUnit.TEAM_PLAYER:
		var mine_lines: Array = TypedVariant.as_array(parts.get("mining_lines", []))
		if mine_lines.is_empty() and mining_g > 0:
			mine_lines = _mining_gold_lines_for_team(team)
		add_gold(final_income, mining_g, mine_lines)
		if loss_comp > 0:
			notice.emit("你收入了%d黄币（含连输补偿%d）" % [final_income, loss_comp])
		elif mining_g > 0:
			notice.emit("你收入了%d黄币（含采矿%d）" % [final_income, mining_g])
		else:
			notice.emit("你收入了%d黄币" % final_income)
	elif _ai and _ai.has_method("add_gold"):
		_ai.add_gold(final_income)


func _mining_gold_for_team(team: int) -> int:
	var n: int = 0
	for line_v: Variant in _mining_gold_lines_for_team(team):
		n += TypedVariant.as_int(TypedVariant.as_dict(line_v).get("amount", 0), 0)
	return n


func mining_command_state(team: int) -> Dictionary:
	## MINING §3 / FETTERS §2: Field Porpoise ≥1 → other sources ×(1.2 + extra porpoise pp).
	var porpoise_n: int = 0
	if _board != null:
		for s0: ShipUnit in _board.field_ships(team):
			if s0 == null or not is_instance_valid(s0) or s0.is_destroyed or s0.is_unmanned:
				continue
			if _is_mining_command_hull(s0.ship_id):
				porpoise_n += 1
	var has_command: bool = porpoise_n > 0
	var cmd_mul: float = 1.0
	if has_command:
		var mc: Dictionary = DataStore.fetters.get("mining_command", {})
		var effects: Array = TypedVariant.as_array(mc.get("effects", []))
		var base_need: int = BoardController._fetter_base_need(effects)
		if base_need <= 0:
			base_need = 1
		var base_pct: float = 20.0
		for e_v: Variant in effects:
			if typeof(e_v) != TYPE_DICTIONARY:
				continue
			var e: Dictionary = TypedVariant.as_dict(e_v)
			if str(e.get("effect_type", "")) == "MiningGoldBonus":
				base_pct = TypedVariant.as_float(e.get("value", 20.0), 20.0)
				break
		var step: int = maxi(0, porpoise_n - base_need)
		cmd_mul = 1.0 + (base_pct + float(step)) / 100.0
	return {"has_command": has_command, "mul": cmd_mul, "porpoise_n": porpoise_n}


func _is_mining_command_hull(ship_id: int) -> bool:
	if ship_id == 136:
		return true
	var sd: Dictionary = DataStore.get_ship(ship_id)
	return "mining_command" in TypedVariant.as_array(sd.get("fetter_ids", []))


func mining_gold_amount_for_ship(ship: ShipUnit, state: Dictionary = {}) -> int:
	## Same integer as settlement / gold float (MINING §3–4). Porpoise itself does not eat command.
	if ship == null or not is_instance_valid(ship) or ship.is_destroyed:
		return 0
	var sd: Dictionary = DataStore.get_ship(ship.ship_id)
	var base_g: int = TypedVariant.as_int(sd.get("mining_gold_per_round", 0), 0)
	if base_g <= 0:
		return 0
	if ship.is_unmanned and str(ship.unmanned_kind) == "mining_excavator":
		@warning_ignore("unsafe_cast")
		var mother: ShipUnit = instance_from_id(ship.mother_ship_id) as ShipUnit
		if mother == null or not is_instance_valid(mother) or mother.is_destroyed:
			return 0
	var starred: int = base_g * maxi(int(ship.star), 1)
	var st: Dictionary = state
	if st.is_empty():
		st = mining_command_state(ship.team_id)
	var is_porpoise: bool = (not ship.is_unmanned) and _is_mining_command_hull(ship.ship_id)
	if TypedVariant.as_bool(st.get("has_command", false), false) and not is_porpoise:
		return floori(float(starred) * TypedVariant.as_float(st.get("mul", 1.2), 1.2))
	return starred


func mining_gold_amount_for_base(team: int, ship_id: int, starred_base: int, unmanned: bool = false) -> int:
	## HUD preview when we only have table ids (Rorqual excavator square).
	var st: Dictionary = mining_command_state(team)
	var is_porpoise: bool = (not unmanned) and _is_mining_command_hull(ship_id)
	if TypedVariant.as_bool(st.get("has_command", false), false) and not is_porpoise:
		return floori(float(starred_base) * TypedVariant.as_float(st.get("mul", 1.2), 1.2))
	return starred_base


func _mining_gold_lines_for_team(team: int) -> Array:
	var lines: Array = []
	if _board == null:
		return lines
	var st: Dictionary = mining_command_state(team)
	for s: ShipUnit in _board.field_ships(team):
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		var amt: int = mining_gold_amount_for_ship(s, st)
		if amt <= 0:
			continue
		var sd: Dictionary = DataStore.get_ship(s.ship_id)
		lines.append({
			"ship_id": s.ship_id,
			"name": str(sd.get("name", s.ship_id)),
			"amount": amt,
			"unmanned": s.is_unmanned,
		})
	return lines

func _on_admin_after(channel: StringName, payload: Dictionary, result: Dictionary) -> void:
	if String(channel) != "combat.hit":
		return
	if not TypedVariant.as_bool(result.get("destroyed", false), false):
		return
	@warning_ignore("unsafe_cast")
	var src: ShipUnit = instance_from_id(TypedVariant.as_int(payload.get("source_id", 0), 0)) as ShipUnit
	@warning_ignore("unsafe_cast")
	var tgt: ShipUnit = instance_from_id(TypedVariant.as_int(payload.get("target_id", 0), 0)) as ShipUnit
	if tgt == null or tgt.is_unmanned:
		return
	if src == null:
		return
	if src.team_id == ShipUnit.TEAM_PLAYER:
		kills_this_round_player += 1
		## Kill gold pays out the instant the kill lands (feel-good realtime pop);
		## `_apply_income` forces kill_g=0 at round-end so this is never re-paid.
		var kill_gold: int = TypedVariant.as_int(DataStore.economy.get("kill_gold_per_ship", 1), 1)
		if kill_gold > 0:
			add_gold(kill_gold)
			notice.emit("击毁获得 %d 黄币" % kill_gold)
	elif src.team_id == ShipUnit.TEAM_AI:
		kills_this_round_ai += 1

func _take_player_damage(amount: int) -> void:
	## Nullsec lives use titan pipes — never emit 主堡 battle-log lines.
	if mode == "nullsec":
		return
	var dmg: int = amount
	## Soften only when Settings → 开发者调试 → 我方扣血软化 is on (default off).
	if GameSession and (PlayerSettings.instance() as PlayerSettings).player_citadel_soften_active():
		var mf: Dictionary = DataStore.match_flow
		dmg = TypedVariant.as_int(mf.get("citadel_test_loss_damage", 1), 1)
	player_hp = maxi(0, player_hp - dmg)
	notice.emit("主堡受到 %d 伤害" % dmg)

func _take_ai_damage(amount: int) -> void:
	if mode == "nullsec":
		return
	## Developer soften never applies to AI; full formula always.
	var dmg: int = maxi(0, amount)
	ai_hp = maxi(0, ai_hp - dmg)
	notice.emit("对手主堡受到 %d 伤害" % dmg)

func _grant_exp(amount: int) -> void:
	var eco: Dictionary = DataStore.economy
	var cap: int = TypedVariant.as_int(eco.get("player_level_cap", 20), 20)
	if player_level >= cap:
		hud_refresh.emit()
		return
	player_exp += amount
	var inc: int = TypedVariant.as_int(eco.get("level_exp_demand_increment", 8), 8)
	while player_exp >= up_level_demand and player_level < cap:
		player_exp -= up_level_demand
		player_level += 1
		up_level_demand += inc
	if player_level >= cap:
		player_exp = 0
	hud_refresh.emit()


## Demand for next level after reaching `level` (1-based).
static func exp_demand_for_level(level: int) -> int:
	var eco: Dictionary = DataStore.economy
	var initial: int = TypedVariant.as_int(eco.get("initial_level_exp_demand", 4), 4)
	var inc: int = TypedVariant.as_int(eco.get("level_exp_demand_increment", 8), 8)
	return initial + maxi(0, level - 1) * inc


func buy_exp() -> void:
	var eco: Dictionary = DataStore.economy
	var cap: int = TypedVariant.as_int(eco.get("player_level_cap", 20), 20)
	if player_level >= cap:
		notice.emit("已达等级上限")
		return
	var cost: int = TypedVariant.as_int(eco.get("buy_exp_gold_cost", 4), 4)
	var amt: int = TypedVariant.as_int(eco.get("buy_exp_amount", 4), 4)
	var payload: Dictionary = {"gold_cost": cost, "exp_amount": amt, "team": ShipUnit.TEAM_PLAYER}
	var r: Dictionary = AdminBus.request(&"shop.buy_exp", payload)
	if not TypedVariant.as_bool(r.get("accepted", true), true):
		return
	cost = TypedVariant.as_int(payload.get("gold_cost", cost), cost)
	amt = TypedVariant.as_int(payload.get("exp_amount", amt), amt)
	if player_gold < cost:
		notice.emit("黄币不足")
		return
	player_gold -= cost
	_grant_exp(amt)
	prepare_spend_occurred.emit()
	InMatchSlowLearn.note_revealed({"kind": "buy_exp", "cost": cost})
	request_autosave()

func try_spend(amount: int) -> bool:
	if player_gold < amount:
		return false
	player_gold -= amount
	prepare_spend_occurred.emit()
	## ECONOMY: gold-only. Full adaptive HUD on spend was the refresh hitch.
	return true

func arm_prepare_clock() -> void:
	if prepare_clock_armed:
		return
	prepare_clock_armed = true
	timer = 0.0
	_prepare_hold_reported = false
	print("[mp.diag] prepare_clock_ARMED mode=%s stage_count=%d" % [mode, battle_game_stage_count])
	SessionDiagnostics.log("mp.clock_armed", "count=%d" % battle_game_stage_count)
	hud_refresh.emit()


func disarm_prepare_clock() -> void:
	prepare_clock_armed = false
	_prepare_hold_reported = false
	print("[mp.diag] prepare_clock_DISARM mode=%s count=%d" % [mode, battle_game_stage_count])


func commit_prepare_complete() -> void:
	## Host barrier released — enter Battle even if hold_prepare_to_battle.
	if stage != Stage.PREPARE or not _running:
		return
	print("[mp.diag] commit_prepare_complete count=%d" % battle_game_stage_count)
	SessionDiagnostics.log("mp.commit_prepare", "count=%d" % battle_game_stage_count)
	_prepare_hold_reported = false
	_on_prepare_complete()


func is_prepare_peer_hold() -> bool:
	return hold_prepare_to_battle and _prepare_hold_reported

func add_gold(amount: int, mining_part: int = 0, mining_lines: Array = []) -> void:
	player_gold += amount
	if amount > 0:
		player_gold_earned += amount
		var tree: SceneTree = get_tree()
		if tree:
			tree.call_group("match_root", "on_gold_income_float", amount, mining_part, mining_lines)
	hud_refresh.emit()

func population_limit() -> int:
	var board_cfg: Dictionary = TypedVariant.as_dict(DataStore.board)
	return mini(
		player_level + TypedVariant.as_int(board_cfg.get("ship_count_buff", 0), 0),
		TypedVariant.as_int(board_cfg.get("max_deployment", 999), 999),
	)

func prepare_remaining() -> float:
	if not prepare_clock_armed:
		return _prepare_duration_s()
	return maxf(0.0, _prepare_duration_s() - timer)

func _prepare_duration_s() -> float:
	## MATCH_FLOW: flat prepare_duration_s; first-round bonus retired (bonus key kept at 0 for legacy packs).
	return TypedVariant.as_float(DataStore.match_flow.get("prepare_duration_s", 16), 16.0)

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
	if GameSession and TypedVariant.as_bool(GameSession.get("resume_save"), false):
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


func _init_equipment_inventory() -> void:
	equipment_inventory.clear()
	for _i: int in range(EQUIPMENT_INVENTORY_SIZE):
		equipment_inventory.append("")


func ensure_equipment_inventory_size() -> void:
	while equipment_inventory.size() < EQUIPMENT_INVENTORY_SIZE:
		equipment_inventory.append("")
	if equipment_inventory.size() > EQUIPMENT_INVENTORY_SIZE:
		equipment_inventory.resize(EQUIPMENT_INVENTORY_SIZE)


func find_empty_equipment_inventory_slot() -> int:
	ensure_equipment_inventory_size()
	for i: int in range(EQUIPMENT_INVENTORY_SIZE):
		if str(equipment_inventory[i]).strip_edges() == "":
			return i
	return -1


func add_equipment_to_inventory(item_id: String) -> bool:
	var slot: int = find_empty_equipment_inventory_slot()
	if slot < 0:
		return false
	equipment_inventory[slot] = str(item_id)
	return true


func remove_equipment_from_inventory(slot_index: int) -> String:
	ensure_equipment_inventory_size()
	if slot_index < 0 or slot_index >= EQUIPMENT_INVENTORY_SIZE:
		return ""
	var prev: String = str(equipment_inventory[slot_index])
	equipment_inventory[slot_index] = ""
	return prev


func move_equipment_inventory(from_idx: int, to_idx: int) -> void:
	ensure_equipment_inventory_size()
	if from_idx < 0 or from_idx >= EQUIPMENT_INVENTORY_SIZE:
		return
	if to_idx < 0 or to_idx >= EQUIPMENT_INVENTORY_SIZE:
		return
	if from_idx == to_idx:
		return
	var item: String = str(equipment_inventory[from_idx])
	var dst: String = str(equipment_inventory[to_idx])
	equipment_inventory[from_idx] = dst
	equipment_inventory[to_idx] = item


# #region agent log
func _dbg_speed_log(hypothesis_id: String, location: String, message: String, data: Dictionary = {}) -> void:
	SessionDiagnostics.log("dbg.speed.%s" % hypothesis_id, "%s %s %s" % [location, message, JSON.stringify(data)])
	var path: String = "H:/debug-0c9657.log"
	if OS.has_feature("mobile") or OS.get_name() == "Android":
		path = ProjectSettings.globalize_path("user://debug/debug-0c9657.log")
	var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"sessionId": "0c9657",
		"runId": str(data.get("runId", "pre-fix")),
		"hypothesisId": hypothesis_id,
		"location": location,
		"message": message,
		"data": data,
		"timestamp": int(Time.get_unix_time_from_system() * 1000.0),
	}))
	f.close()
# #endregion
