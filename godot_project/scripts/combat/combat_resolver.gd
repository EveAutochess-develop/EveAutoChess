extends Node
class_name CombatResolver
## V2 combat: capacitor, EVE turret/missile/lock, racial logistics, movement AI.
## Same path for all ships — no scenarioId branches.

var _board: BoardController
var _active: bool = false
## SEMI_ASYNC §3.1a — guest watch-only: skip local drone/aux spawn; authority rebuilds them.
var authority_only: bool = false
var _retarget_acc: float = 0.0
var _combat_sim_time: float = 0.0
var _fx: Object = null  # FiringFx
var _missile_queue: Array = []  # {pos, source_id, target_id, damage, speed_cells_per_s, source_ship_id?}
var _float_text: FloatTextPool
## Capital attack probes (COMBAT §15.5): iid:reason -> last sim_s; iid -> stats logged.
var _atk_diag_gate_cd: Dictionary = {}
var _atk_diag_stats_done: Dictionary = {}
var _debris: Array = []  # {node: Node3D, cooldown: Dictionary}
var _drone_orbit_phase: Dictionary = {}  # instance_id -> float
## Orbit tangent sign: +1 / -1 (reverse when stuck ~2s).
var _drone_orbit_dir: Dictionary = {}  # instance_id -> float
## Orbit plane tilt degrees [20, 89] vs horizontal; seeded via orbit_tilt.
var _drone_orbit_tilt: Dictionary = {}  # instance_id -> float
## Fixed ascending-node azimuth (radians); plane must not rebuild from live radial.
var _drone_orbit_az: Dictionary = {}  # instance_id -> float
var _drone_orbit_last_pos: Dictionary = {}  # instance_id -> Vector3
var _drone_orbit_stuck_s: Dictionary = {}  # instance_id -> float
## Per-combat fighter damage accounting (for session DPS audit).
var _fighter_dealt_total: float = 0.0
var _fighter_hit_count: int = 0
var _fighter_shot_count: int = 0
## Mining visual FX cooldown remaining per ShipUnit instance_id.
var _mining_fx_cd: Dictionary = {}
## Last MiningAnchor instance_id per firer — consecutive shots prefer a different rock.
var _mining_fx_last_anchor_id: Dictionary = {}
## Excavator wander: instance_id -> MiningAnchor Node3D; retarget cooldown remaining.
var _mining_wander_anchor: Dictionary = {}
var _mining_wander_cd: Dictionary = {}
## HP-stall retarget (COMBAT §14.1): firer id -> watch state.
var _stall_target_id: Dictionary = {}
var _stall_deadline: Dictionary = {}
var _stall_hp0: Dictionary = {}
## Hull morph after unstack: {ship: ShipUnit, from: Vector3, to: Vector3, t: float, dur: float}
var _morph_unstack: Array = []
## Unmanned revive after kill (COMBAT §14C): {mother_id, drone_id, revive_at, star, squadron_id}
var _drone_revive_queue: Array = []
## SEMI_ASYNC §2 — authority RNG (MatchRng) vs presentation (VisualRng).
var match_rng: MatchRng = null
var battle_serial: int = 1
var visual_rng: VisualRng = VisualRng.new()

const DRONE_BW_COST: float = 5.0
const DRONE_CAP: int = 5
const DRONE_REVIVE_DELAY_S: float = 400.0
const RACE_DRONE_LIGHT: Dictionary = {
	"amarr": 1001, "caldari": 1002, "gallente": 1003, "minmatar": 1004,
	## Pirate → empire parent race (SHIPS §1.3).
	"blood": 1001, "sansha": 1001, "mordu": 1002, "serpentis": 1003, "soe": 1003, "angel": 1004,
	"guristas": 1502,
}
const RACE_DRONE_MEDIUM: Dictionary = {
	"amarr": 1005, "caldari": 1006, "gallente": 1007, "minmatar": 1008,
	"blood": 1005, "sansha": 1005, "mordu": 1006, "serpentis": 1007, "soe": 1007, "angel": 1008,
	"guristas": 1506,
}
const RACE_DRONE_HEAVY: Dictionary = {
	"amarr": 1011, "caldari": 1012, "gallente": 1013, "minmatar": 1014,
	"blood": 1011, "sansha": 1011, "mordu": 1012, "serpentis": 1013, "soe": 1013, "angel": 1014,
	"guristas": 1512,
}
const DRONE_COUNT_EXCEPTIONS: Dictionary = {42: 5, 44: 4, 55: 4, 56: 5}

func bind(board: BoardController, fx: Object = null) -> void:
	_board = board
	_fx = fx
	AdminBus.register_handler(&"combat.hit", _on_hit)
	AdminBus.register_handler(&"combat.heal", _on_heal)
	if _float_text == null:
		_float_text = FloatTextPool.new()
		_float_text.name = "FloatTextPool"
		add_child(_float_text)


func bind_match_rng(rng: MatchRng, serial: int = 1) -> void:
	match_rng = rng
	battle_serial = maxi(1, serial)
	if match_rng and not match_rng.has_battle(battle_serial):
		match_rng.begin_battle(battle_serial)


func _function_auth_rng(event_kind: String, from_v: Variant = 0, to_v: Variant = 0) -> Variant:
	match event_kind:
		"shop_fn":
			return _auth_randi_range("function_shop", TypedVariant.as_int(from_v, 0), TypedVariant.as_int(to_v, 0))
		"support_strip":
			return _auth_randf("support_strip")
		_:
			return _auth_randf(str(event_kind))


func _auth_randf(event_kind: String) -> float:
	if match_rng:
		return match_rng.roll(battle_serial, event_kind)
	return randf()


func _auth_randi_range(event_kind: String, from_v: int, to_v: int) -> int:
	if match_rng:
		return match_rng.roll_int(battle_serial, event_kind, from_v, to_v)
	return randi_range(from_v, to_v)


func _auth_randf_range(event_kind: String, from_v: float, to_v: float) -> float:
	var t: float = _auth_randf(event_kind)
	return lerpf(from_v, to_v, t)


func _viz_randf() -> float:
	return visual_rng.randf() if visual_rng else randf()


func _viz_randf_range(from_v: float, to_v: float) -> float:
	return visual_rng.randf_range(from_v, to_v) if visual_rng else randf_range(from_v, to_v)


func _viz_randi_range(from_v: int, to_v: int) -> int:
	return visual_rng.randi_range(from_v, to_v) if visual_rng else randi_range(from_v, to_v)

func start_combat() -> void:
	_active = true
	_combat_sim_time = 0.0
	_retarget_acc = 0.0
	_missile_queue.clear()
	_atk_diag_gate_cd.clear()
	_atk_diag_stats_done.clear()
	_drone_orbit_phase.clear()
	_drone_orbit_dir.clear()
	_drone_orbit_tilt.clear()
	_drone_orbit_az.clear()
	_drone_orbit_last_pos.clear()
	_drone_orbit_stuck_s.clear()
	_fighter_dealt_total = 0.0
	_fighter_hit_count = 0
	_fighter_shot_count = 0
	_mining_fx_cd.clear()
	_mining_fx_last_anchor_id.clear()
	_mining_wander_anchor.clear()
	_mining_wander_cd.clear()
	_drone_revive_queue.clear()
	_morph_unstack.clear()
	_clear_debris()
	_spawn_isolation_debris()
	for s: ShipUnit in _board.all_ships():
		if s.slot_type == "field" and not s.is_destroyed:
			s.set_combat_tint(true)
			s.reset_combat_runtime()
	if not authority_only:
		_spawn_combat_drones()
		_spawn_capital_auxiliaries()
	## Opening pose: both sides on shared cells shift ±X before first tick.
	_board.refresh_cross_team_cell_offsets(true)
	## Capitals: unstack if clipped, then hull_morph (siege / industrial).
	_queue_hull_morphs_with_unstack()
	## Soft-follow mesh after opening teleports so lag starts from the final pose.
	if _board and _board.has_method("arm_visual_follow"):
		_board.arm_visual_follow()
	for s: ShipUnit in _board.all_ships():
		if s != null and is_instance_valid(s) and s.has_method("clear_move_velocity"):
			s.clear_move_velocity()
	SessionDiagnostics.log("combat.start", "")

func sim_time() -> float:
	return _combat_sim_time

func fighter_damage_summary() -> Dictionary:
	var t: float = maxf(_combat_sim_time, 0.001)
	return {
		"dealt": _fighter_dealt_total,
		"hits": _fighter_hit_count,
		"shots": _fighter_shot_count,
		"sim_s": _combat_sim_time,
		"dps": _fighter_dealt_total / t,
	}

func ensure_auxiliaries_for(ship: ShipUnit) -> void:
	if ship == null or ship.is_destroyed or ship.slot_type != "field":
		return
	_spawn_auxiliaries_for_ship(ship)

func stop_combat() -> void:
	_active = false
	_morph_unstack.clear()
	if _board and _board.has_method("disarm_visual_follow"):
		_board.disarm_visual_follow()
	for s: ShipUnit in _board.all_ships():
		if s != null and is_instance_valid(s):
			s.hull_morph_unstacking = false
	SessionDiagnostics.log("combat.end", "sim_s=%.1f" % _combat_sim_time)
	var summary: Dictionary = fighter_damage_summary()
	if TypedVariant.as_int(summary.get("shots", 0), 0) > 0 or TypedVariant.as_float(summary.get("dealt", 0.0), 0.0) > 0.0:
		SessionDiagnostics.log(
			"fighter.dps",
			"dealt=%.1f hits=%d shots=%d sim_s=%.1f dps=%.1f" % [
				TypedVariant.as_float(summary.get("dealt", 0.0), 0.0),
				TypedVariant.as_int(summary.get("hits", 0), 0),
				TypedVariant.as_int(summary.get("shots", 0), 0),
				TypedVariant.as_float(summary.get("sim_s", 0.0), 0.0),
				TypedVariant.as_float(summary.get("dps", 0.0), 0.0),
			]
		)
	_missile_queue.clear()
	_atk_diag_gate_cd.clear()
	_atk_diag_stats_done.clear()
	_drone_revive_queue.clear()
	_clear_drones()
	_clear_debris()
	for s: ShipUnit in _board.all_ships():
		if s != null and is_instance_valid(s):
			s.set_combat_tint(false)
			s.combat_target = null
			if s.has_method("clear_move_velocity"):
				s.clear_move_velocity()
			EngineBoosterTrail.set_emitting_on(s, false)
	if _fx != null and _fx.has_method("clear_all"):
		_fx.call("clear_all")

func tick(delta: float) -> void:
	if not _active:
		return
	_combat_sim_time += delta
	var now: float = _combat_sim_time
	_tick_morph_unstack(delta)
	_cull_orphan_drones()
	_tick_drone_revives()
	_spawn_capital_auxiliaries()
	var retarget_interval: float = TypedVariant.as_float(DataStore.combat.get("retarget_interval_s", 10.0), 10.0)
	_retarget_acc += delta
	var periodic_retarget: bool = _retarget_acc >= retarget_interval
	if periodic_retarget:
		_retarget_acc = 0.0
	_tick_missiles(delta)
	for s: ShipUnit in _board.all_ships():
		if s.is_destroyed or s.slot_type != "field":
			continue
		s.tick_capacitor(delta)
		s.tick_stat_modifiers(delta)
		s._combat_sim_time = now
		## combat_target is untyped; freed refs must not be cast (throws "Trying to cast a freed object").
		var weapon_tgt: ShipUnit = null
		var ct_any: Variant = s.combat_target
		if ct_any != null and is_instance_valid(ct_any):
			@warning_ignore("unsafe_cast")
			weapon_tgt = ct_any as ShipUnit
		else:
			s.combat_target = null
		FunctionFit.update_function_target(s, _board, weapon_tgt)
		FunctionFit.tick_active_modules(s, _board, delta, now, Callable(self, "_function_auth_rng"))
		s.update_retreat(now)
		_tick_mining_fx(s, delta)
		## Salvage freighter escorts nobody: it parks, never locks and never returns fire
		## (0 damage), but everyone else targets it by the normal rules (FREIGHTER_AND_TITAN §1.2.1).
		if s.is_protect_target:
			s.combat_target = null
			s.clear_move_velocity()
			EngineBoosterTrail.set_emitting_on(s, false)
			continue
		## Excavators: wander central asteroids; no enemy lock / orbit / attack.
		if s.is_unmanned and str(s.unmanned_kind) == "mining_excavator":
			s.combat_target = null
			_wander_mining_drone(s, delta)
			continue
		## Manned mining hulls: logistics-like soft move, keep ore in range (MINING §2.1b).
		if s.is_mining_ship and not s.is_unmanned:
			s.combat_target = null
			if s.has_cyno_module() or s.hull_morph_unstacking:
				continue
			if s.immobile_in_combat:
				EngineBoosterTrail.set_emitting_on(s, false)
				continue
			_move_mining_ship(s, delta, now)
			continue
		_update_targeting(s, delta, periodic_retarget)
		var tgt_any: Variant = s.combat_target
		if tgt_any == null or not is_instance_valid(tgt_any):
			s.combat_target = null
			## Logistics with nothing to repair must still move (soft follow), else looks stuck.
			if s.is_logistic and not s.has_cyno_module() and not s.immobile_in_combat and not s.hull_morph_unstacking:
				_move_logistic_idle(s, delta, now)
			elif not s.has_cyno_module() and not s.immobile_in_combat and not s.hull_morph_unstacking:
				## No order: coast/brake with EVE inertia (COMBAT §3.1 drift).
				_ensure_ship_trail(s)
				_apply_accelerated_displacement(s, Vector3.ZERO, delta)
			continue
		@warning_ignore("unsafe_cast")
		var tgt: ShipUnit = tgt_any as ShipUnit
		if tgt == null:
			s.combat_target = null
			if s.is_logistic and not s.has_cyno_module() and not s.immobile_in_combat and not s.hull_morph_unstacking:
				_move_logistic_idle(s, delta, now)
			elif not s.has_cyno_module() and not s.immobile_in_combat and not s.hull_morph_unstacking:
				_ensure_ship_trail(s)
				_apply_accelerated_displacement(s, Vector3.ZERO, delta)
			continue
		if tgt.is_destroyed:
			s.combat_target = null
			if s.is_logistic and not s.has_cyno_module() and not s.immobile_in_combat and not s.hull_morph_unstacking:
				_move_logistic_idle(s, delta, now)
			elif not s.has_cyno_module() and not s.immobile_in_combat and not s.hull_morph_unstacking:
				_ensure_ship_trail(s)
				_apply_accelerated_displacement(s, Vector3.ZERO, delta)
			continue
		s.sync_lock(tgt, now)
		s.advance_lock(delta)
		## Lead lock on the runner-up, refreshed on the same cadence as the retarget so it
		## gets a full interval to finish; done in time → next switch fires at once (§13.1).
		if periodic_retarget and not s.is_logistic and not s.is_unmanned:
			s.sync_pre_lock(_find_target(s, tgt))
		s.advance_pre_lock(delta)
		## Covert cyno: pinned + no weapons. Other immobile (dread siege / Rorqual industrial):
		## stay put / no yaw, but still lock+fire (morph / unstack are visual / slide only).
		if s.has_cyno_module():
			continue
		if s.hull_morph_unstacking:
			s.clear_move_velocity()
			EngineBoosterTrail.set_emitting_on(s, false)
			## CAPITAL §4: unstack allows brief slide but must not gate lock/fire.
		elif s.immobile_in_combat:
			s.clear_move_velocity()
			EngineBoosterTrail.set_emitting_on(s, false)
		elif s.is_unmanned and s.unmanned_kind.find("sentry") < 0:
			_orbit_drone(s, tgt, delta)
		else:
			_move_ship(s, tgt, delta, now)
		_try_attack(s, tgt, now)
	## Mixed lance: board-wide salvo after all ships ticked (CAPITAL §4.1).
	MixedLance.flush_salvo(_board)
	_tick_debris_contacts(delta)
	_apply_drone_lod()
	_apply_separation()

func _update_targeting(s: ShipUnit, delta: float, periodic_retarget: bool) -> void:
	## Combat drones inherit mother lock when mother still shoots.
	## Carriers (hull DPH=0) let fighters hunt on their own — otherwise damage never lands.
	if s.is_unmanned and str(s.unmanned_kind) == "mining_excavator":
		s.combat_target = null
		return
	## FAX heavy repair drones pick heal targets themselves (prefer mother; CAPITAL §6).
	## Combat drones / fighters inherit mother lock when mother still shoots.
	if s.is_unmanned and s.mother_ship_id != 0 and str(s.unmanned_kind) != "heavy_repair_drone":
		var mother: ShipUnit = instance_from_id(s.mother_ship_id) as ShipUnit
		if mother == null or not is_instance_valid(mother) or mother.is_destroyed:
			return
		var mt: Variant = mother.combat_target
		if mother.has_offensive_damage() and mt != null and is_instance_valid(mt):
			@warning_ignore("unsafe_cast")
			var mt_ship: ShipUnit = mt as ShipUnit
			if not mt_ship.is_destroyed:
				s.combat_target = mt
				return
	var tgt_any: Variant = s.combat_target
	var tgt: ShipUnit = null
	if tgt_any != null and is_instance_valid(tgt_any):
		@warning_ignore("unsafe_cast")
		tgt = tgt_any as ShipUnit
	## HP stall: 30–40s with no layer drop → switch to ally's target at best range.
	if not s.is_logistic and tgt != null and not tgt.is_destroyed:
		if _tick_hp_stall_retarget(s, tgt):
			return
	var need_search: bool = tgt == null or tgt.is_destroyed
	if not need_search and s.is_logistic and not tgt.needs_heal_for_race(s.race):
		need_search = true
	if not need_search and not s.is_logistic and periodic_retarget:
		need_search = true
	if not need_search:
		s.no_target_acc = 0.0
		return
	## Current target died / invalid → switch immediately (do not wait no_target_search_s).
	if tgt != null and (not is_instance_valid(tgt) or tgt.is_destroyed):
		_assign_combat_target(s, _find_target(s))
		s.no_target_acc = 0.0
		return
	var search_s: float = TypedVariant.as_float(DataStore.combat.get("no_target_search_s", 0.5), 0.5)
	if tgt != null and not tgt.is_destroyed:
		_assign_combat_target(s, _find_target(s))
		return
	s.no_target_acc += delta
	if s.no_target_acc >= search_s:
		s.no_target_acc = 0.0
		_assign_combat_target(s, _find_target(s))


func _assign_combat_target(s: ShipUnit, nxt: ShipUnit) -> void:
	s.combat_target = nxt
	_reset_hp_stall_watch(s, nxt)


func _reset_hp_stall_watch(s: ShipUnit, tgt: ShipUnit) -> void:
	if s == null:
		return
	var fid: int = s.get_instance_id()
	if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed or s.is_logistic:
		_stall_target_id.erase(fid)
		_stall_deadline.erase(fid)
		_stall_hp0.erase(fid)
		return
	var span: float = 30.0
	if match_rng != null:
		span = 30.0 + match_rng.roll(battle_serial, "misc_combat") * 10.0
	else:
		span = 30.0 + visual_rng.randf() * 10.0
	_stall_target_id[fid] = tgt.get_instance_id()
	_stall_deadline[fid] = _combat_sim_time + span
	_stall_hp0[fid] = {
		"shield": tgt.shield_hp,
		"armor": tgt.armor_hp,
		"structure": tgt.structure_hp,
	}


func _tick_hp_stall_retarget(s: ShipUnit, tgt: ShipUnit) -> bool:
	var fid: int = s.get_instance_id()
	var tid: int = tgt.get_instance_id()
	if TypedVariant.as_int(_stall_target_id.get(fid, -1), -1) != tid:
		_reset_hp_stall_watch(s, tgt)
		return false
	var snap: Dictionary = TypedVariant.as_dict(_stall_hp0.get(fid, {}))
	if snap.is_empty():
		_reset_hp_stall_watch(s, tgt)
		return false
	## Any layer drop clears the stall clock.
	if (
		tgt.shield_hp < TypedVariant.as_float(snap.get("shield", 0.0)) - 0.01
		or tgt.armor_hp < TypedVariant.as_float(snap.get("armor", 0.0)) - 0.01
		or tgt.structure_hp < TypedVariant.as_float(snap.get("structure", 0.0)) - 0.01
	):
		_reset_hp_stall_watch(s, tgt)
		return false
	if _combat_sim_time < TypedVariant.as_float(_stall_deadline.get(fid, 0.0), 0.0):
		return false
	var alt: ShipUnit = _find_ally_focus_target(s, tgt)
	if alt == null:
		alt = _find_target(s)
	if alt == null or alt == tgt:
		_reset_hp_stall_watch(s, tgt)
		return false
	_assign_combat_target(s, alt)
	s.no_target_acc = 0.0
	return true


func _find_ally_focus_target(s: ShipUnit, exclude: ShipUnit) -> ShipUnit:
	## Prefer enemies currently under fire by allies, scored by closeness to desired ring.
	if s == null or _board == null:
		return null
	var desired: float = _desired_engagement_cells(s, exclude if exclude != null else s)
	var best: ShipUnit = null
	var best_score: float = 1.0e30
	var focused: Dictionary = {}
	for ally_v: Variant in _board.all_ships():
		if not (ally_v is ShipUnit):
			continue
		var ally: ShipUnit = ally_v
		if ally == null or not is_instance_valid(ally) or ally.is_destroyed:
			continue
		if ally.team_id != s.team_id or ally == s:
			continue
		var at: Variant = ally.combat_target
		if at == null or not is_instance_valid(at) or not (at is ShipUnit):
			continue
		@warning_ignore("unsafe_cast")
		var et: ShipUnit = at as ShipUnit
		if et.is_destroyed or et.team_id == s.team_id:
			continue
		if exclude != null and et == exclude:
			continue
		focused[et.get_instance_id()] = et
	for _k: Variant in focused.keys():
		var et2: ShipUnit = focused[_k]
		var d_cells: float = s.grid_dist_to(et2)
		var score: float = absf(d_cells - desired)
		if score < best_score:
			best_score = score
			best = et2
	return best

func _move_ship(s: ShipUnit, tgt: ShipUnit, delta: float, now_s: float) -> void:
	if s.immobile_in_combat or s.has_cyno_module():
		s.clear_move_velocity()
		return
	## Unstack slide is driven by CombatResolver, not engagement move.
	if s.hull_morph_unstacking:
		s.clear_move_velocity()
		return
	var desired_cells: float = _desired_engagement_cells(s, tgt)
	var desired_wu: float = desired_cells * CombatFormulas.world_units_per_cell()
	var deadband: float = TypedVariant.as_float(DataStore.combat.get("range_deadband_cells", 0.25), 0.25)
	deadband *= CombatFormulas.world_units_per_cell()
	var move_goal: Vector3
	if s.is_logistic or s.in_retreat(now_s):
		move_goal = _logistic_position(s, tgt, now_s)
	else:
		move_goal = _combat_position(s, tgt, desired_wu, deadband)
		move_goal = _apply_screen_margin(s, tgt, move_goal)
	var dir: Vector3 = move_goal - s.global_position
	dir = _flatten_move_dir(s, dir)
	var step_len: float = dir.length()
	_ensure_ship_trail(s)
	var desired_dir: Vector3 = Vector3.ZERO
	if step_len > deadband:
		desired_dir = dir / step_len
	## Clamp can pin short-range hulls outside R — close on the target (COMBAT §3).
	if not s.is_logistic and not s.in_retreat(now_s) and _needs_weapon_range_nudge(s, tgt):
		var to_tgt: Vector3 = tgt.global_position - s.global_position
		to_tgt = _flatten_move_dir(s, to_tgt)
		if to_tgt.length_squared() > 0.0001:
			desired_dir = to_tgt.normalized()
	if desired_dir.length_squared() > 0.0001:
		_face_move_dir(s, desired_dir)
	else:
		var aim: Vector3 = tgt.global_position - s.global_position
		aim = _flatten_move_dir(s, aim)
		_face_move_dir(s, aim)
	_apply_accelerated_displacement(s, desired_dir, delta)


func _needs_weapon_range_nudge(s: ShipUnit, tgt: ShipUnit) -> bool:
	if s == null or tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
		return false
	var max_cells: float = s.world_range_cells()
	if max_cells >= 100.0:
		return false
	return s.grid_dist_to(tgt) > max_cells + 0.001


func _apply_accelerated_displacement(s: ShipUnit, desired_dir: Vector3, delta: float) -> void:
	## COMBAT §3.1 — manned: EVE inertia. Unmanned: instant max-speed step (perf).
	if s.is_unmanned:
		_apply_instant_displacement(s, desired_dir, delta)
		return
	var vmax: float = s.combat_move_speed()
	var desired_vel: Vector3 = Vector3.ZERO
	if desired_dir.length_squared() > 0.0001:
		desired_vel = desired_dir.normalized() * vmax
	var disp: Vector3 = s.tick_combat_velocity(desired_vel, delta)
	s.global_position += disp
	_clamp_after_move(s)
	var emit_min: float = TypedVariant.as_float(DataStore.combat.get("move_trail_emit_speed_wu_s", 0.15), 0.15)
	EngineBoosterTrail.set_emitting_on(s, s.combat_speed_now() > emit_min)


func _apply_instant_displacement(s: ShipUnit, desired_dir: Vector3, delta: float) -> void:
	s.clear_move_velocity()
	var moving: bool = desired_dir.length_squared() > 0.0001
	if moving:
		var step: float = s.combat_move_speed() * delta
		s.global_position += desired_dir.normalized() * step
	_clamp_after_move(s)
	EngineBoosterTrail.set_emitting_on(s, moving)


## Unmanned: XZ only. Manned Y-unlocked: XZ+Y fence. Other manned: XZ + deck y.
func _clamp_after_move(s: ShipUnit) -> void:
	if s.is_unmanned:
		s.global_position = BoardController.clamp_to_combat_play_area(s.global_position)
		return
	if s.y_axis_unlocked():
		s.global_position = BoardController.clamp_to_play_volume(s.global_position)
		return
	s.global_position = BoardController.clamp_to_combat_play_area(s.global_position)
	s.global_position.y = BoardController.DECK_Y


func _flatten_move_dir(s: ShipUnit, dir: Vector3) -> Vector3:
	if s.y_axis_unlocked():
		return dir
	dir.y = 0.0
	return dir


func _face_move_dir(s: ShipUnit, dir: Vector3) -> void:
	if s.y_axis_unlocked():
		s.face_dir_3d(dir)
	else:
		s.face_dir_xz(dir)


func _desired_engagement_cells(s: ShipUnit, tgt: ShipUnit) -> float:
	## Min engagement distance = 1 cell (no point-blank stack).
	var min_cells: float = TypedVariant.as_float(DataStore.combat.get("min_engagement_cells", 1.0), 1.0)
	var approach: float = TypedVariant.as_float(DataStore.combat.get("approach_factor", 0.9), 0.9)
	var max_cells: float = s.world_range_cells()
	var hold_cap: float = max_cells * approach
	## Missile non-sleeper infinite range: kite away to farthest feasible standoff.
	if max_cells >= 100.0 and s.is_missile_weapon() and not _ship_is_sleeper(s):
		var standoff: float = _missile_standoff_cells(s, tgt, min_cells)
		return maxf(min_cells, standoff)
	## Finite missile (sleepers): hold at approach ring.
	if s.is_missile_weapon():
		return maxf(min_cells, hold_cap)
	## Turrets: ternary D*; flat hit curve → fall back to approach ring (COMBAT §3).
	var raw: float = _ternary_optimal_cells(s, tgt)
	if _turret_hit_curve_is_flat(s, tgt, max_cells):
		raw = hold_cap
	raw = minf(raw, hold_cap)
	return maxf(raw, min_cells)


func _ship_is_sleeper(s: ShipUnit) -> bool:
	if s == null:
		return false
	return ShipUnit._is_sleeper_hull(DataStore.get_ship(s.ship_id))


func _missile_standoff_cells(s: ShipUnit, tgt: ShipUnit, min_cells: float) -> float:
	## Prefer maximum separation while remaining in playable XZ bounds.
	if s == null or tgt == null:
		return min_cells
	var away: Vector3 = s.global_position - tgt.global_position
	away.y = 0.0
	if away.length() < 0.001:
		away = Vector3(0.0, 0.0, 1.0)
	else:
		away = away.normalized()
	var cell_wu: float = TypedVariant.as_float(DataStore.combat.get("world_units_per_cell", 3.0), 3.0)
	var best: float = min_cells
	for i: int in range(8, 0, -1):
		var cells: float = float(i) * 5.0
		var cand: Vector3 = tgt.global_position + away * (cells * cell_wu)
		cand.y = s.global_position.y
		cand = BoardController.clamp_to_combat_play_area(cand)
		var from_tgt: Vector3 = cand - tgt.global_position
		from_tgt.y = 0.0
		var got: float = from_tgt.length() / maxf(cell_wu, 0.001)
		if got >= best:
			best = got
	return maxf(min_cells, best)


func _turret_hit_curve_is_flat(s: ShipUnit, tgt: ShipUnit, max_cells: float) -> bool:
	if max_cells <= 0.001:
		return true
	var p0: float = s.turret_hit_chance_vs(tgt, 0.0)
	var p1: float = s.turret_hit_chance_vs(tgt, max_cells * 0.5)
	var p2: float = s.turret_hit_chance_vs(tgt, max_cells)
	return absf(p0 - p1) < 0.02 and absf(p1 - p2) < 0.02


func _ternary_optimal_cells(s: ShipUnit, tgt: ShipUnit) -> float:
	var lo: float = 0.0
	var hi: float = maxf(s.world_range_cells(), 0.001)
	for _i: int in range(24):
		var m1: float = lo + (hi - lo) / 3.0
		var m2: float = hi - (hi - lo) / 3.0
		if s.turret_hit_chance_vs(tgt, m1) < s.turret_hit_chance_vs(tgt, m2):
			lo = m1
		else:
			hi = m2
	return clampf((lo + hi) * 0.5, 0.0, hi)

func _combat_position(s: ShipUnit, tgt: ShipUnit, desired_wu: float, deadband: float) -> Vector3:
	## Manned ships approach / hold on the fire ring only.
	## Do not lateral-slide around the target; orbit is reserved for unmanned units.
	var away: Vector3 = s.global_position - tgt.global_position
	away.y = 0.0
	var dist_wu: float = away.length()
	if dist_wu < 0.001:
		away = Vector3(0.0, 0.0, 1.0)
	else:
		away = away.normalized()
	if dist_wu > desired_wu + deadband or dist_wu < desired_wu - deadband:
		return tgt.global_position + away * desired_wu
	return s.global_position

func _logistic_position(s: ShipUnit, tgt: ShipUnit, now_s: float) -> Vector3:
	var focus: ShipUnit = tgt
	if s.is_logistic:
		var ally: ShipUnit = _best_heal_ally(s)
		if ally != null:
			focus = ally
		elif focus == null:
			focus = _nearest_ally_any(s)
	if focus == null:
		## No allies left — drift toward enemy centroid so engines stay alive.
		var enemy_c: Variant = _enemy_centroid(s.team_id)
		if enemy_c != null:
			@warning_ignore("unsafe_cast")
			return s.global_position.lerp(enemy_c as Vector3, 0.15)
		return s.global_position
	var repair_wu: float = s.world_range_wu()
	var enemy_centroid: Variant = _enemy_centroid(s.team_id)
	var dir: Vector3
	if enemy_centroid != null:
		@warning_ignore("unsafe_cast")
		dir = focus.global_position - (enemy_centroid as Vector3)
	else:
		dir = focus.global_position - s.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.0, 0.0, 1.0)
	else:
		dir = dir.normalized()
	var anchor: Vector3 = focus.global_position + dir * repair_wu * 0.85
	if s.in_retreat(now_s) and not s.is_logistic:
		var logi_c: Variant = _logistics_centroid(s.team_id)
		if logi_c != null and enemy_centroid != null:
			@warning_ignore("unsafe_cast")
			var back: Vector3 = (logi_c as Vector3) - (enemy_centroid as Vector3)
			back.y = 0.0
			if back.length_squared() > 0.0001:
				@warning_ignore("unsafe_cast")
				anchor = (logi_c as Vector3) + back.normalized() * CombatFormulas.world_units_per_cell()
	return anchor


## Soft station-keeping when no ally needs heal (COMBAT §14.1 / §14.2).
func _move_logistic_idle(s: ShipUnit, delta: float, now_s: float) -> void:
	var focus: ShipUnit = _nearest_ally_any(s)
	var move_goal: Vector3 = _logistic_position(s, focus, now_s)
	var deadband: float = TypedVariant.as_float(DataStore.combat.get("range_deadband_cells", 0.25), 0.25)
	deadband *= CombatFormulas.world_units_per_cell()
	var dir: Vector3 = move_goal - s.global_position
	dir.y = 0.0
	var step_len: float = dir.length()
	_ensure_ship_trail(s)
	var desired_dir: Vector3 = Vector3.ZERO
	if step_len > deadband:
		desired_dir = dir / step_len
		s.face_dir_xz(desired_dir)
		_apply_accelerated_displacement(s, desired_dir, delta)
	else:
		## Slow lateral drift so full-HP idle never looks frozen (still uses inertia).
		var enemy_c: Variant = _enemy_centroid(s.team_id)
		var drift: Vector3 = Vector3(1.0, 0.0, 0.0)
		if enemy_c != null:
			@warning_ignore("unsafe_cast")
			drift = s.global_position - (enemy_c as Vector3)
			drift.y = 0.0
			if drift.length_squared() < 0.0001:
				drift = Vector3(1.0, 0.0, 0.0)
			else:
				drift = drift.normalized().cross(Vector3.UP)
				if drift.length_squared() < 0.0001:
					drift = Vector3(1.0, 0.0, 0.0)
				else:
					drift = drift.normalized()
		var phase: int = float(s.get_instance_id() % 97) * 0.11
		var wobble: float = sin(now_s * 0.55 + phase)
		s.face_dir_xz(drift)
		## Scale desired speed by wobble so inertia still coasts between peaks.
		var vmax: float = s.combat_move_speed() * 0.35 * absf(wobble)
		var desired_vel: Vector3 = Vector3.ZERO
		if absf(wobble) > 0.02:
			desired_vel = drift * vmax * signf(wobble)
		var disp: Vector3 = s.tick_combat_velocity(desired_vel, delta)
		s.global_position += disp
		_clamp_after_move(s)
		var emit_min: float = TypedVariant.as_float(DataStore.combat.get("move_trail_emit_speed_wu_s", 0.15), 0.15)
		EngineBoosterTrail.set_emitting_on(s, s.combat_speed_now() > emit_min)


## Manned mining hulls: logistics-like soft move; keep a MiningAnchor in range (MINING §2.1b).
func _move_mining_ship(s: ShipUnit, delta: float, now_s: float) -> void:
	if s.immobile_in_combat or s.has_cyno_module() or s.hull_morph_unstacking:
		s.clear_move_velocity()
		return
	var belt: AsteroidBelt = _find_asteroid_belt()
	var ore: Node3D = _pick_mining_move_anchor(s, belt)
	var deadband: float = TypedVariant.as_float(DataStore.combat.get("range_deadband_cells", 0.25), 0.25)
	deadband *= CombatFormulas.world_units_per_cell()
	var range_wu: float = maxf(s.world_range_wu(), CombatFormulas.world_units_per_cell())
	_ensure_ship_trail(s)
	if ore == null:
		## No belt — soft drift like logistic idle without focus.
		_move_logistic_idle(s, delta, now_s)
		return
	var ore_xz: Vector3 = Vector3(ore.global_position.x, 0.0, ore.global_position.z)
	var self_xz: Vector3 = Vector3(s.global_position.x, 0.0, s.global_position.z)
	var away: Vector3 = self_xz - ore_xz
	away.y = 0.0
	var dist: float = away.length()
	if dist < 0.001:
		away = Vector3(0.0, 0.0, 1.0)
		dist = 0.0
	else:
		away = away.normalized()
	## Hold inside range (soft ring ~85% like logistics repair station).
	var hold_wu: float = range_wu * 0.85
	var desired_dir: Vector3 = Vector3.ZERO
	if dist > range_wu + deadband:
		var move_goal: Vector3 = ore_xz + away * hold_wu
		move_goal.y = s.global_position.y
		var dir: Vector3 = move_goal - s.global_position
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			desired_dir = dir.normalized()
	elif dist < hold_wu - deadband and dist > 0.05:
		var move_goal2: Vector3 = ore_xz + away * hold_wu
		move_goal2.y = s.global_position.y
		var dir2: Vector3 = move_goal2 - s.global_position
		dir2.y = 0.0
		if dir2.length_squared() > 0.0001:
			desired_dir = dir2.normalized()
	else:
		var tangent: Vector3 = Vector3(-away.z, 0.0, away.x)
		if tangent.length_squared() < 0.0001:
			tangent = Vector3(1.0, 0.0, 0.0)
		else:
			tangent = tangent.normalized()
		var phase: int = float(s.get_instance_id() % 97) * 0.11
		var wobble: float = sin(now_s * 0.55 + phase)
		var face: Vector3 = ore_xz - self_xz
		face.y = 0.0
		s.face_dir_xz(face if face.length_squared() > 0.0001 else tangent)
		var vmax: float = s.combat_move_speed() * 0.35 * absf(wobble)
		var desired_vel: Vector3 = Vector3.ZERO
		if absf(wobble) > 0.02:
			desired_vel = tangent * vmax * signf(wobble)
		var disp: Vector3 = s.tick_combat_velocity(desired_vel, delta)
		s.global_position += disp
		_clamp_after_move(s)
		var emit_min: float = TypedVariant.as_float(DataStore.combat.get("move_trail_emit_speed_wu_s", 0.15), 0.15)
		EngineBoosterTrail.set_emitting_on(s, s.combat_speed_now() > emit_min)
		return
	if desired_dir.length_squared() > 0.0001:
		s.face_dir_xz(desired_dir)
	else:
		var face2: Vector3 = ore_xz - self_xz
		face2.y = 0.0
		s.face_dir_xz(face2)
	_apply_accelerated_displacement(s, desired_dir, delta)


func _pick_mining_move_anchor(s: ShipUnit, belt: AsteroidBelt) -> Node3D:
	if belt == null or belt.mining_anchors.is_empty():
		return null
	var range_wu: float = maxf(s.world_range_wu(), CombatFormulas.world_units_per_cell())
	var self_xz: Vector3 = Vector3(s.global_position.x, 0.0, s.global_position.z)
	## Prefer an already-in-range ore (stable station-keeping).
	var best_in: Node3D = null
	var best_in_d: float = 99999.0
	var best_any: Node3D = null
	var best_any_d: float = 99999.0
	for a: Variant in belt.mining_anchors:
		if a == null or not is_instance_valid(a):
			continue
		@warning_ignore("unsafe_cast")
		var n: Node3D = a as Node3D
		if n == null:
			continue
		var d: Variant = self_xz.distance_to(Vector3(n.global_position.x, 0.0, n.global_position.z))
		if d < best_any_d:
			best_any_d = d
			best_any = n
		if d <= range_wu and d < best_in_d:
			best_in_d = d
			best_in = n
	if best_in != null:
		return best_in
	return best_any


func _nearest_ally_any(logi: ShipUnit) -> ShipUnit:
	var best: ShipUnit = null
	var best_d: float = 99999.0
	var best_id: int = 2147483647
	for o: ShipUnit in _board.field_ships(logi.team_id):
		if o == logi or o.is_destroyed:
			continue
		if TypedVariant.as_bool(o.get("is_unmanned")):
			continue
		var d: float = logi.grid_dist_to(o)
		var oid: int = o.get_instance_id()
		if d < best_d - 0.001 or (absf(d - best_d) <= 0.001 and oid < best_id):
			best_d = d
			best_id = oid
			best = o
	return best

func _apply_screen_margin(s: ShipUnit, tgt: ShipUnit, move_goal: Vector3) -> Vector3:
	## Soft screen vs logistics centroid — never push outside weapon range.
	var margin_cells: float = TypedVariant.as_float(DataStore.combat.get("screen_margin", 1.0), 1.0)
	var margin_wu: float = margin_cells * CombatFormulas.world_units_per_cell()
	var logi_c: Variant = _logistics_centroid(s.team_id)
	if logi_c == null:
		return move_goal
	var enemy_pos: Vector3 = tgt.global_position
	var flat_self: Vector3 = Vector3(s.global_position.x, 0.0, s.global_position.z)
	var flat_enemy: Vector3 = Vector3(enemy_pos.x, 0.0, enemy_pos.z)
	@warning_ignore("unsafe_cast")
	var flat_logi: Vector3 = Vector3((logi_c as Vector3).x, 0.0, (logi_c as Vector3).z)
	var d_self: float = flat_self.distance_to(flat_enemy)
	var d_logi: float = flat_logi.distance_to(flat_enemy)
	if d_self >= d_logi + margin_wu:
		return move_goal
	var away: Vector3 = flat_self - flat_enemy
	if away.length_squared() < 0.0001:
		away = Vector3(0.0, 0.0, 1.0)
	else:
		away = away.normalized()
	var needed: float = (d_logi + margin_wu) - d_self
	var candidate: Vector3 = move_goal + away * needed
	var max_range_wu: float = s.world_range_cells() * CombatFormulas.world_units_per_cell()
	var cand_flat: Vector3 = Vector3(candidate.x, 0.0, candidate.z)
	if cand_flat.distance_to(flat_enemy) > max_range_wu:
		## Clamp onto max fire ring so screen_margin cannot starve attacks.
		return flat_enemy + away * max_range_wu
	return candidate

func _logistics_centroid(team: int) -> Variant:
	var sum: Vector3 = Vector3.ZERO
	var n: int = 0
	for o: ShipUnit in _board.field_ships(team):
		if o.is_destroyed or not o.is_logistic:
			continue
		sum += o.global_position
		n += 1
	if n == 0:
		return null
	return sum / float(n)

func _enemy_centroid(team: int) -> Variant:
	var enemy_team: int = ShipUnit.TEAM_AI if team == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
	var sum: Vector3 = Vector3.ZERO
	var n: int = 0
	for o: ShipUnit in _board.field_ships(enemy_team):
		if o.is_destroyed:
			continue
		sum += o.global_position
		n += 1
	if n == 0:
		return null
	return sum / float(n)

func _best_heal_ally(logi: ShipUnit) -> ShipUnit:
	## FAX heavy repair: prefer mother when she needs heal (CAPITAL §6).
	## Movement/orbit follows her even out of range; `_try_attack` still gates 5 cells.
	if str(logi.unmanned_kind) == "heavy_repair_drone" and logi.mother_ship_id != 0:
		var mother: ShipUnit = instance_from_id(logi.mother_ship_id) as ShipUnit
		if (
			mother != null
			and is_instance_valid(mother)
			and not mother.is_destroyed
			and mother.team_id == logi.team_id
			and mother.slot_type == "field"
			and not mother.is_unmanned
			and mother.needs_heal_for_race(logi.race)
		):
			return mother
	var best: ShipUnit = null
	var best_d: float = 99999.0
	var best_id: int = 2147483647
	for o: ShipUnit in _board.field_ships(logi.team_id):
		if o == logi or o.is_destroyed:
			continue
		if TypedVariant.as_bool(o.get("is_unmanned")):
			continue
		if not o.needs_heal_for_race(logi.race):
			continue
		var d: float = logi.grid_dist_to(o)
		var oid: int = o.get_instance_id()
		if d < best_d - 0.001 or (absf(d - best_d) <= 0.001 and oid < best_id):
			best_d = d
			best_id = oid
			best = o
	return best

func _is_atk_diag_subject(s: ShipUnit) -> bool:
	if s == null or not is_instance_valid(s):
		return false
	if s.requires_cyno_entry:
		return true
	return not str(s.capital_role).is_empty()


func _atk_diag_gate(s: ShipUnit, reason: String, extra: String = "") -> void:
	if not _is_atk_diag_subject(s):
		return
	var iid: int = s.get_instance_id()
	var key: String = "%d:%s" % [iid, reason]
	var last: float = TypedVariant.as_float(_atk_diag_gate_cd.get(key, -9999.0), -9999.0)
	if _combat_sim_time - last < 2.0:
		return
	_atk_diag_gate_cd[key] = _combat_sim_time
	var detail: String = "ship=%d reason=%s" % [s.ship_id, reason]
	if extra != "":
		detail += " " + extra
	SessionDiagnostics.log("atk.gate", detail)


func _atk_diag_stats_once(s: ShipUnit) -> void:
	if not _is_atk_diag_subject(s):
		return
	var iid: int = s.get_instance_id()
	if TypedVariant.as_bool(_atk_diag_stats_done.get(iid, false), false):
		return
	_atk_diag_stats_done[iid] = true
	var dph: float = s.damage_emp + s.damage_thermal + s.damage_kinetic + s.damage_explosive
	SessionDiagnostics.log(
		"atk.stats",
		"ship=%d role=%s fx=%s dph=%.1f cycle=%.2f er=%.1f ev=%.1f scan=%.1f cap=%.0f/%.0f" % [
			s.ship_id,
			s.capital_role,
			s.resolve_weapon_fx_kind(),
			dph,
			s.attack_duration,
			s.explosion_radius,
			s.explosion_velocity,
			s.scan_resolution,
			s.cap_current,
			s.cap_capacity,
		]
	)


func _try_attack(s: ShipUnit, tgt: ShipUnit, now: float) -> void:
	_atk_diag_stats_once(s)
	if s.has_cyno_module():
		_atk_diag_gate(s, "cyno")
		return
	## CAPITAL §4.1: suppress only the hull that fitted lance and is in Prep/Fire/End.
	if MixedLance.weapons_suppressed(s):
		_atk_diag_gate(s, "lance")
		return
	if not s.is_logistic and not s.has_offensive_damage():
		_atk_diag_gate(s, "no_dph")
		return
	if now - s.last_attack_time < s.attack_duration:
		## Expected CD — do not log (would flood even throttled on short cycles).
		return
	if not s.attacks_enabled():
		_atk_diag_gate(s, "cap", "frac=%.2f" % s.cap_fraction())
		return
	if not s.is_target_locked():
		_atk_diag_gate(s, "unlock", "lt=%.2f need=%.2f" % [s.lock_timer, s.lock_duration_s])
		return
	var dist_cells: float = s.grid_dist_to(tgt)
	if dist_cells > s.world_range_cells() + 0.001:
		_atk_diag_gate(s, "range", "dist=%.2f max=%.2f" % [dist_cells, s.world_range_cells()])
		return
	s.last_attack_time = now
	s.consume_cap_for_cycle()
	FunctionFit.consume_attack_cap_cost(s)
	_do_attack(s, tgt, dist_cells)

func _do_attack(s: ShipUnit, tgt: ShipUnit, dist_cells: float) -> void:
	var fx_travel_s: float = -1.0
	var fx_speed_cells: float = -1.0
	if s.is_logistic:
		var amounts: Dictionary = s.heal_dict_scaled()
		var payload: Dictionary = {
			"source_id": s.get_instance_id(),
			"target_id": tgt.get_instance_id(),
			"source_race": s.race,
			"heal_shield": amounts.get("shield", 0.0),
			"heal_armor": amounts.get("armor", 0.0),
			"heal_structure": amounts.get("structure", 0.0),
		}
		AdminBus.request(&"combat.heal", payload)
	else:
		var raw: Dictionary = s.damage_dict_scaled()
		var raw_sum: float = s.sum_damage_amount(raw)
		if s.is_missile_weapon():
			var factor: float = s.missile_damage_factor_vs(tgt)
			var scaled: Dictionary = {}
			for k: Variant in raw.keys():
				scaled[k] = TypedVariant.as_float(raw[k], 0.0) * factor
			var spd: float = CombatFormulas.missile_speed_cells_per_s(s)
			fx_speed_cells = spd
			var muzzle: Vector3 = s.get_muzzle_global()
			_missile_queue.append({
				"pos": muzzle,
				"source_id": s.get_instance_id(),
				"target_id": tgt.get_instance_id(),
				"damage": scaled,
				"speed_cells_per_s": spd,
				"source_ship_id": s.ship_id,
				"target_ship_id": tgt.ship_id,
				"raw_sum": raw_sum * factor,
				"diag_capital": _is_atk_diag_subject(s),
			})
			if _is_atk_diag_subject(s):
				SessionDiagnostics.log(
					"atk.fire",
					"ship=%d tgt=%d kind=missile raw=%.0f factor=%.3f dist=%.2f spd=%.2f" % [
						s.ship_id, tgt.ship_id, raw_sum, factor, dist_cells, spd
					]
				)
		else:
			var p_hit: float = s.turret_hit_chance_vs(tgt, dist_cells)
			if FunctionFit.attack_force_hit(s):
				p_hit = 1.0
			var x: float = _auth_randf("turret_hit")
			var quality: float = CombatFormulas.turret_hit_quality(x, p_hit)
			FunctionFit.clear_attack_force_hit(s)
			if quality > 0.0:
				var scaled_t: Dictionary = {}
				for k2: Variant in raw.keys():
					scaled_t[k2] = TypedVariant.as_float(raw[k2], 0.0) * quality
				var payload2: Dictionary = {
					"source_id": s.get_instance_id(),
					"target_id": tgt.get_instance_id(),
					"damage": scaled_t,
				}
				var hit_res: Dictionary = AdminBus.request(&"combat.hit", payload2)
				if _is_atk_diag_subject(s):
					SessionDiagnostics.log(
						"atk.fire",
						"ship=%d tgt=%d kind=%s raw=%.0f qual=%.2f dealt=%.0f dist=%.2f" % [
							s.ship_id,
							tgt.ship_id,
							s.resolve_weapon_fx_kind(),
							raw_sum,
							quality,
							TypedVariant.as_float(hit_res.get("dealt", 0.0), 0.0),
							dist_cells,
						]
					)
			else:
				FunctionFit.on_attack_miss(s)
				if _is_atk_diag_subject(s):
					SessionDiagnostics.log(
						"atk.fire",
						"ship=%d tgt=%d kind=%s raw=%.0f qual=0 miss dist=%.2f" % [
							s.ship_id, tgt.ship_id, s.resolve_weapon_fx_kind(), raw_sum, dist_cells
						]
					)
	if _fx != null and _fx.has_method("play"):
		_fx.call("play", s, tgt, s.resolve_weapon_fx_kind(), s.attack_duration, fx_travel_s, fx_speed_cells)
	if s.has_method("advance_muzzle"):
		s.advance_muzzle()

func _tick_missiles(dt: float) -> void:
	## Independent chase: constant cells/s toward live target (no stretch/shrink with relative motion).
	var wu: float = CombatFormulas.world_units_per_cell()
	var hit_r: float = TypedVariant.as_float(DataStore.combat.get("missile_hit_radius_wu", 0.45), 0.45)
	var i: int = 0
	while i < _missile_queue.size():
		var m: Dictionary = _missile_queue[i]
		var tid: int = TypedVariant.as_int(m.get("target_id", 0), 0)
		var tgt: ShipUnit = instance_from_id(tid) as ShipUnit
		if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
			if TypedVariant.as_bool(m.get("diag_capital", false), false):
				SessionDiagnostics.log(
					"atk.missile_drop",
					"ship=%d tgt=%d reason=tgt_gone" % [
						TypedVariant.as_int(m.get("source_ship_id", 0), 0),
						TypedVariant.as_int(m.get("target_ship_id", 0), 0),
					]
				)
			_missile_queue.remove_at(i)
			continue
		var pos_v: Variant = m.get("pos", tgt.global_position)
		@warning_ignore("unsafe_cast")
		var pos: Vector3 = pos_v as Vector3
		var dest: Vector3 = tgt.global_position + Vector3(0.0, 0.4, 0.0)
		var delta_p: Vector3 = dest - pos
		var dist: float = delta_p.length()
		var speed_wu: float = TypedVariant.as_float(m.get("speed_cells_per_s", 1.5), 1.5) * wu
		var step: float = speed_wu * dt
		if dist <= maxf(hit_r, step) or dist < 0.001:
			var hit_res: Dictionary = AdminBus.request(&"combat.hit", {
				"source_id": TypedVariant.as_int(m.get("source_id", 0), 0),
				"target_id": tid,
				"damage": m.get("damage", {}),
			})
			if TypedVariant.as_bool(m.get("diag_capital", false), false):
				SessionDiagnostics.log(
					"atk.missile_hit",
					"ship=%d tgt=%d dealt=%.0f raw=%.0f" % [
						TypedVariant.as_int(m.get("source_ship_id", 0), 0),
						TypedVariant.as_int(m.get("target_ship_id", 0), 0),
						TypedVariant.as_float(hit_res.get("dealt", 0.0), 0.0),
						TypedVariant.as_float(m.get("raw_sum", 0.0), 0.0),
					]
				)
			_missile_queue.remove_at(i)
			continue
		m["pos"] = pos + delta_p * (step / dist)
		_missile_queue[i] = m
		i += 1

func _apply_separation() -> void:
	## Elastic soft collision spheres sized from on-field model display.
	## Slight overlap allowed; spring push <1 so rear ships can squeeze past allies.
	_board.refresh_cross_team_cell_offsets(false)
	var allow: float = TypedVariant.as_float(DataStore.combat.get("collision_allow_overlap_frac", 0.22), 0.22)
	allow = clampf(allow, 0.0, 0.6)
	var elasticity: float = TypedVariant.as_float(DataStore.combat.get("collision_elasticity", 0.42), 0.42)
	elasticity = clampf(elasticity, 0.05, 1.0)
	var lateral_k: float = TypedVariant.as_float(DataStore.combat.get("collision_same_team_lateral", 0.4), 0.4)
	lateral_k = clampf(lateral_k, 0.0, 1.5)
	var ships: Array[ShipUnit] = []
	for s: ShipUnit in _board.all_ships():
		if s.slot_type == "field" and not s.is_destroyed:
			ships.append(s)
	for i: int in range(ships.size()):
		var a: ShipUnit = ships[i]
		if a.hull_morph_unstacking:
			continue
		var ra: float = a.collision_radius_wu()
		for j: int in range(i + 1, ships.size()):
			var b: ShipUnit = ships[j]
			if b.hull_morph_unstacking:
				continue
			var rb: float = b.collision_radius_wu()
			var sum_r: float = ra + rb
			if sum_r < 0.001:
				continue
			## Only push when deeper than allowed slight clip.
			var soft_min: float = sum_r * (1.0 - allow)
			var delta: Vector3 = a.global_position - b.global_position
			## Vertically clear → skip XZ push (COMBAT §14.2).
			if absf(delta.y) > sum_r:
				continue
			delta.y = 0.0
			var d: float = delta.length()
			if d >= soft_min:
				continue
			var dir: Vector3
			if d < 0.001:
				var bias: float = -1.0 if a.get_instance_id() < b.get_instance_id() else 1.0
				dir = Vector3(bias, 0.0, 0.0)
			else:
				dir = delta.normalized()
			## Same-team: blend side slip so short-range rear ships are not walled in.
			if a.team_id == b.team_id and lateral_k > 0.001:
				var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
				if a.get_instance_id() > b.get_instance_id():
					side = -side
				dir = (dir + side * lateral_k).normalized()
			var penetration: float = soft_min - d
			var push_mag: float = penetration * elasticity * 0.5
			var push: Vector3 = dir * push_mag
			var pin_a: bool = bool(a.immobile_in_combat) or a.has_cyno_module()
			var pin_b: bool = bool(b.immobile_in_combat) or b.has_cyno_module()
			if pin_a and pin_b:
				continue
			elif pin_a:
				b.global_position -= push * 2.0
			elif pin_b:
				a.global_position += push * 2.0
			else:
				## Mass-ish: larger display yields a bit less (rear frigate slides around capital).
				var wa: float = maxf(ra, 0.05)
				var wb: float = maxf(rb, 0.05)
				var inv: float = 1.0 / (wa + wb)
				a.global_position += push * (wb * inv * 2.0)
				b.global_position -= push * (wa * inv * 2.0)
			_clamp_after_move(a)
			_clamp_after_move(b)

func _find_target(s: ShipUnit, exclude: ShipUnit = null) -> ShipUnit:
	## §6.3 ties: nearest (grid cells) → lowest HP fraction → lowest instance_id.
	## `exclude` skips one hull, used to pick the lead-lock runner-up (§13.1).
	if s.is_logistic:
		return _best_heal_ally(s)
	var _sd: Dictionary = DataStore.get_ship(s.ship_id)
	var tier: String = str(_sd.get("weapon_tier", "")).to_lower()
	var fx: String = str(s.resolve_weapon_fx_kind()).to_lower()
	var block_unmanned: bool = tier in ["large", "capital"] and fx in ["laser", "rail", "cannon", "missile"]
	var enemy_team: float = ShipUnit.TEAM_AI if s.team_id == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
	var best2: ShipUnit = null
	var best_d2: float = 99999.0
	var best_hp: float = 99999.0
	var best_id: int = 2147483647
	for o: ShipUnit in _board.field_ships(enemy_team):
		if o.is_destroyed or o == exclude:
			continue
		if block_unmanned and o.is_unmanned:
			continue
		var d2: float = s.grid_dist_to(o)
		var hp_frac: float = o.total_hp_fraction()
		var oid: int = o.get_instance_id()
		var better: bool = false
		if d2 < best_d2 - 0.001:
			better = true
		elif absf(d2 - best_d2) <= 0.001:
			if hp_frac < best_hp - 0.0001:
				better = true
			elif absf(hp_frac - best_hp) <= 0.0001 and oid < best_id:
				better = true
		if better:
			best_d2 = d2
			best_hp = hp_frac
			best_id = oid
			best2 = o
	return best2

func _on_hit(payload: Dictionary) -> Dictionary:
	var tid: int = TypedVariant.as_int(payload.get("target_id", 0), 0)
	var target: ShipUnit = instance_from_id(tid) as ShipUnit
	if target == null:
		return {"accepted": false}
	var dmg: Dictionary = TypedVariant.as_dict(payload.get("damage", {}))
	if dmg.is_empty():
		var raw: float = TypedVariant.as_float(payload.get("damage_emp", 0.0), 0.0)
		dmg = {"emp": raw, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0}
	var src: ShipUnit = instance_from_id(TypedVariant.as_int(payload.get("source_id", 0), 0)) as ShipUnit
	if src != null:
		dmg = FunctionFit.transform_damage_dict(src, target, dmg)
	var res: Dictionary = target.apply_hit_dict(dmg)
	var dealt: float = TypedVariant.as_float(res.get("dealt", 0.0), 0.0)
	if src != null and dealt > 0.0:
		FunctionFit.on_hit_landed(src, target, dealt, Callable(self, "_function_auth_rng"))
		FunctionFit.on_attack_hit(src, target, dealt)
	if src != null and src.unmanned_kind == "fighter":
		_fighter_shot_count += 1
		if dealt > 0.0:
			_fighter_dealt_total += dealt
			_fighter_hit_count += 1
	if dealt > 0.0 and _float_text:
		_float_text.add_damage(target.global_position, dealt, target.get_instance_id())
	var destroyed: bool = TypedVariant.as_bool(res.get("destroyed", false), false)
	## Combat kill only — mother-death orphan cull does not go through apply_hit.
	if destroyed and target.is_unmanned and not authority_only:
		_schedule_drone_revive(target)
	return {"accepted": true, "destroyed": destroyed, "dealt": dealt}

func _on_heal(payload: Dictionary) -> Dictionary:
	var tid: int = TypedVariant.as_int(payload.get("target_id", 0), 0)
	var target: ShipUnit = instance_from_id(tid) as ShipUnit
	if target == null:
		return {"accepted": false}
	if target.is_unmanned:
		return {"accepted": false, "reason_key": "unmanned"}
	var src: ShipUnit = instance_from_id(TypedVariant.as_int(payload.get("source_id", 0), 0)) as ShipUnit
	var race: String = str(payload.get("source_race", src.race if src else "amarr"))
	var amounts: Dictionary = {
		"shield": TypedVariant.as_float(payload.get("heal_shield", payload.get("heal", 0.0)), 0.0),
		"armor": TypedVariant.as_float(payload.get("heal_armor", 0.0), 0.0),
		"structure": TypedVariant.as_float(payload.get("heal_structure", 0.0), 0.0),
	}
	if src != null:
		amounts = FunctionFit.scale_heal_amounts(src, amounts)
	var res: Dictionary = target.apply_heal_racial(race, amounts)
	var healed: float = TypedVariant.as_float(res.get("applied", 0.0), 0.0)
	if src != null and TypedVariant.as_float(amounts.get("armor", 0.0), 0.0) > 0.0:
		FunctionFit.apply_armor_support_on_repair(src, target)
	var full: bool = TypedVariant.as_bool(res.get("full", false), false)
	if healed > 0.0 and _float_text:
		_float_text.add_heal(target.global_position, healed, target.get_instance_id())
	if full and src:
		src.combat_target = null
	return {"accepted": true, "full": full, "applied": healed}

func _spawn_combat_drones() -> void:
	var carriers: Array[ShipUnit] = []
	for s: ShipUnit in _board.all_ships():
		if s.slot_type != "field" or s.is_destroyed or s.is_unmanned:
			continue
		## Capitals use fighter / heavy-repair spawn path instead of race light drones.
		if str(s.capital_role) in ["carrier", "force_auxiliary", "dreadnought"]:
			continue
		var policy: Dictionary = _drone_spawn_policy_for_ship(s)
		if TypedVariant.as_int(policy.get("count", 0), 0) <= 0:
			continue
		carriers.append(s)
	for s: ShipUnit in carriers:
		var policy: Dictionary = _drone_spawn_policy_for_ship(s)
		var n: int = mini(DRONE_CAP, TypedVariant.as_int(policy.get("count", 0), 0))
		if n <= 0:
			continue
		@warning_ignore("unsafe_cast")
		var id_list: Array = policy.get("drone_ids", []) as Array
		var drone_id: int = TypedVariant.as_int(policy.get("drone_id", 0), 0)
		if id_list.is_empty() and drone_id <= 0:
			continue
		for i: int in range(n):
			var spawn_id: int = drone_id
			if id_list.size() > 0:
				spawn_id = TypedVariant.as_int(id_list[i % id_list.size()], 0)
			if spawn_id <= 0:
				continue
			var ang: float = float(i) * TAU / float(maxi(1, n))
			var rad: float = 1.15
			var offset: Vector3 = Vector3(cos(ang) * rad, 0.2, sin(ang) * rad)
			var drone: ShipUnit = _board.spawn_unmanned(spawn_id, s.team_id, s.global_position + offset, s)
			_ensure_drone_trail(drone)
			var did: int = drone.get_instance_id()
			## Even phase + alternate orbit dir — less VisualRng scatter (COMBAT §14C).
			_drone_orbit_phase[did] = ang
			_drone_orbit_dir[did] = 1.0 if (i % 2) == 0 else -1.0
	## Fresh hulls need the team's live SelfAll fetter pass (ArmorHP / Speed / titan …).
	_board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	_board.recalculate_fetters(ShipUnit.TEAM_AI)


func _drone_spawn_policy_for_ship(s: ShipUnit) -> Dictionary:
	var race: String = str(s.race).to_lower()
	var ship_data: Dictionary = DataStore.get_ship(s.ship_id)
	var group: String = str(ship_data.get("ship_group", "")).to_lower()
	var sid: int = int(s.ship_id)
	## Explicit multi-id list (Guristas C×2, Nestor logistics 1421–1424).
	@warning_ignore("unsafe_cast")
	var unit_ids: Array = ship_data.get("drone_unit_ids", []) as Array
	if unit_ids.size() > 0:
		var ids_out: Array = []
		for u: Variant in unit_ids:
			var uid: int = TypedVariant.as_int(u, 0)
			if uid > 0:
				ids_out.append(uid)
		if ids_out.size() > 0:
			return {"count": ids_out.size(), "drone_ids": ids_out, "drone_id": TypedVariant.as_int(ids_out[0], 0)}
	## Rorqual / industrial: explicit mining Excavator template (not race light drones).
	var mining_drone_id: int = TypedVariant.as_int(ship_data.get("mining_drone_id", 0), 0)
	if mining_drone_id > 0:
		var mcount: int = TypedVariant.as_int(ship_data.get("drone_bay_slots", ship_data.get("drone_count_cap", 0)), 0)
		if mcount <= 0:
			mcount = TypedVariant.as_int(ship_data.get("mining_drone_count", 4), 4)
		return {"count": mcount, "drone_id": mining_drone_id}
	## COMBAT §14C: logistic cruiser / BC never launch combat drones (FAX still uses auxiliaries).
	## Nestor battleship with drone_unit_ids already returned above.
	if TypedVariant.as_bool(s.is_logistic, false) and group in ["cruiser", "battlecruiser"]:
		return {"count": 0, "drone_id": 0}
	if DRONE_COUNT_EXCEPTIONS.has(sid):
		var cnt: int = TypedVariant.as_int(DRONE_COUNT_EXCEPTIONS[sid], 0)
		if group == "battlecruiser":
			return {"count": cnt, "drone_id": TypedVariant.as_int(RACE_DRONE_MEDIUM.get(race, 1005), 1005)}
		if group == "battleship":
			return {"count": cnt, "drone_id": TypedVariant.as_int(RACE_DRONE_HEAVY.get(race, 1011), 1011)}
	if group == "battlecruiser":
		return {"count": 1, "drone_id": TypedVariant.as_int(RACE_DRONE_MEDIUM.get(race, 1005), 1005)}
	if group == "battleship":
		## Logistic battleship without explicit drone_unit_ids: no combat heavies.
		if TypedVariant.as_bool(s.is_logistic, false):
			return {"count": 0, "drone_id": 0}
		return {"count": 2, "drone_id": TypedVariant.as_int(RACE_DRONE_HEAVY.get(race, 1011), 1011)}
	## Mining barges: G medium 1007; Orca (industrial_command): G heavy 1013 (MINING §2).
	var slots: int = TypedVariant.as_int(s.get("drone_bay_slots"), 0)
	if slots <= 0:
		slots = TypedVariant.as_int(ship_data.get("drone_bay_slots", ship_data.get("drone_count_cap", 0)), 0)
	## Explicit bay=0 must stay 0 — do not invent from leftover SDE bandwidth.
	if slots <= 0 and not ship_data.has("drone_bay_slots") and s.drone_bandwidth > 0.0:
		slots = floori(s.drone_bandwidth / DRONE_BW_COST)
	if slots <= 0:
		return {"count": 0, "drone_id": 0}
	if group == "mining_barge":
		return {"count": slots, "drone_id": 1007}
	if group == "industrial_command":
		return {"count": slots, "drone_id": 1013}
	## Faction / empire cruiser with explicit bay: prefer medium when race map has pirate entry
	## and ship marked faction_ship; else light (empire Dominix etc.).
	if group == "cruiser":
		if TypedVariant.as_bool(ship_data.get("faction_ship", false), false):
			return {"count": slots, "drone_id": TypedVariant.as_int(RACE_DRONE_MEDIUM.get(race, 1005), 1005)}
	## Guristas race fallback → doubled C drones.
	if race == "guristas":
		if group == "cruiser":
			return {"count": slots, "drone_id": 1506}
		if group == "battleship":
			return {"count": slots, "drone_id": 1512}
		return {"count": slots, "drone_id": 1502}
	return {"count": slots, "drone_id": TypedVariant.as_int(RACE_DRONE_LIGHT.get(race, 1001), 1001)}


func _spawn_capital_auxiliaries() -> void:
	for s: ShipUnit in _board.all_ships():
		if s.slot_type != "field" or s.is_destroyed or s.is_unmanned:
			continue
		_spawn_auxiliaries_for_ship(s)


func _count_children_of(mother: ShipUnit) -> int:
	var n: int = 0
	var mid: int = mother.get_instance_id()
	for s: ShipUnit in _board.all_ships():
		if s.is_unmanned and not s.is_destroyed and s.mother_ship_id == mid:
			n += 1
	return n


func _spawn_auxiliaries_for_ship(s: ShipUnit) -> void:
	var data: Dictionary = DataStore.get_ship(s.ship_id)
	var fighter_ids: Array = _carrier_fighter_unit_ids(data)
	if s.capital_role == "carrier" or fighter_ids.size() > 0:
		_ensure_carrier_fighter_squadrons(s, data)
		return
	if s.capital_role == "force_auxiliary" or TypedVariant.as_int(data.get("heavy_repair_drone_id", 0), 0) > 0:
		var drone_id: int = TypedVariant.as_int(data.get("heavy_repair_drone_id", 0), 0)
		if drone_id <= 0:
			return
		var need2: int = TypedVariant.as_int(data.get("heavy_repair_drone_count", 4), 4)
		var have2: int = _count_children_of(s)
		for j: int in range(have2, need2):
			var ang2: float = float(j) * TAU / float(maxi(1, need2))
			var offset2: Vector3 = Vector3(cos(ang2) * 1.6, 0.25, sin(ang2) * 1.6)
			## Repair drones always ★1 heal (reload_stats ignores star for repair).
			var d: ShipUnit = _board.spawn_unmanned(drone_id, s.team_id, s.global_position + offset2, s, 1)
			_ensure_drone_trail(d)
			var did2: int = d.get_instance_id()
			_drone_orbit_phase[did2] = ang2
			_drone_orbit_dir[did2] = 1.0 if _auth_randf("orbit_dir") < 0.5 else -1.0
		_board.recalculate_fetters(s.team_id)


func _carrier_fighter_unit_ids(data: Dictionary) -> Array:
	@warning_ignore("unsafe_cast")
	var arr: Array = data.get("fighter_unit_ids", []) as Array
	var out: Array = []
	for v: Variant in arr:
		var fid: int = TypedVariant.as_int(v, 0)
		if fid > 0:
			out.append(fid)
	if out.size() > 0:
		return out
	var one: int = TypedVariant.as_int(data.get("fighter_unit_id", 0), 0)
	if one > 0:
		out.append(one)
	return out


func _ensure_carrier_fighter_squadrons(s: ShipUnit, data: Dictionary) -> void:
	## Max `fighter_squadrons` active at once; lifetime pool `fighter_squadron_pool`.
	## When a whole squadron is wiped, launch another while pool remains.
	## Multi-type: `fighter_unit_ids[]` — each active slot uses ids[slot % len] (Delirium 4 races).
	var fighter_ids: Array = _carrier_fighter_unit_ids(data)
	if fighter_ids.is_empty():
		return
	var active_max: int = TypedVariant.as_int(data.get("fighter_squadrons", 3), 3)
	if fighter_ids.size() > 1:
		active_max = maxi(active_max, fighter_ids.size())
	var tubes: int = TypedVariant.as_int(data.get("fighter_tubes_per_squadron", 3), 3)
	var pool_cap: int = TypedVariant.as_int(data.get("fighter_squadron_pool", 10), 10)
	active_max = maxi(1, active_max)
	tubes = maxi(1, tubes)
	pool_cap = maxi(active_max, pool_cap)
	if s.fighter_squadron_pool_left < 0:
		s.fighter_squadron_pool_left = pool_cap
	var mid: int = s.get_instance_id()
	var living_by_sq: Dictionary = {}
	for u: ShipUnit in _board.all_ships():
		if not u.is_unmanned or u.is_destroyed:
			continue
		if u.mother_ship_id != mid or u.unmanned_kind != "fighter":
			continue
		var sq: int = int(u.fighter_squadron_id)
		living_by_sq[sq] = TypedVariant.as_int(living_by_sq.get(sq, 0), 0) + 1
	var active_count: int = 0
	for sq2: Variant in living_by_sq.keys():
		if TypedVariant.as_int(living_by_sq[sq2], 0) > 0:
			active_count += 1
	while active_count < active_max and s.fighter_squadron_pool_left > 0:
		var sq_id: int = s.fighter_next_squadron_id
		s.fighter_next_squadron_id += 1
		s.fighter_squadron_pool_left -= 1
		var fighter_id: int = TypedVariant.as_int(fighter_ids[active_count % fighter_ids.size()], 0)
		for i: int in range(tubes):
			var ang: float = float(active_count * tubes + i) * TAU / float(active_max * tubes)
			var offset: Vector3 = Vector3(cos(ang) * 1.4, 0.25, sin(ang) * 1.4)
			var f: ShipUnit = _board.spawn_unmanned(
				fighter_id, s.team_id, s.global_position + offset, s, s.star, sq_id
			)
			_ensure_drone_trail(f)
			var fid: int = f.get_instance_id()
			_drone_orbit_phase[fid] = ang
			_drone_orbit_dir[fid] = 1.0 if _auth_randf("orbit_dir") < 0.5 else -1.0
		active_count += 1
	_board.recalculate_fetters(s.team_id)


func _clear_drones() -> void:
	var doomed: Array[ShipUnit] = []
	for ship: ShipUnit in _board.all_ships():
		if ship.is_unmanned:
			doomed.append(ship)
	for ship2: ShipUnit in doomed:
		_board.remove_ship_node(ship2)
	_drone_orbit_phase.clear()
	_drone_orbit_dir.clear()
	_drone_orbit_tilt.clear()
	_drone_orbit_az.clear()
	_drone_orbit_last_pos.clear()
	_drone_orbit_stuck_s.clear()
	_mining_wander_anchor.clear()
	_mining_wander_cd.clear()
	_mining_fx_cd.clear()
	_mining_fx_last_anchor_id.clear()
	_drone_revive_queue.clear()


func _schedule_drone_revive(drone: ShipUnit) -> void:
	if drone == null or not drone.is_unmanned:
		return
	var mid: int = int(drone.mother_ship_id)
	if mid == 0:
		return
	var mother: ShipUnit = instance_from_id(mid) as ShipUnit
	if mother == null or not is_instance_valid(mother) or mother.is_destroyed:
		return
	_drone_revive_queue.append({
		"mother_id": mid,
		"drone_id": int(drone.ship_id),
		"revive_at": _combat_sim_time + DRONE_REVIVE_DELAY_S,
		"star": maxi(int(drone.star), 1),
		"squadron_id": int(drone.fighter_squadron_id),
	})


func _tick_drone_revives() -> void:
	if authority_only or _drone_revive_queue.is_empty():
		return
	var left: Array = []
	for entry_v: Variant in _drone_revive_queue:
		var entry: Dictionary = TypedVariant.as_dict(entry_v)
		var mid: int = TypedVariant.as_int(entry.get("mother_id", 0), 0)
		var mother: ShipUnit = instance_from_id(mid) as ShipUnit
		if mother == null or not is_instance_valid(mother) or mother.is_destroyed or mother.slot_type != "field":
			continue
		var due: float = TypedVariant.as_float(entry.get("revive_at", 0.0), 0.0)
		if _combat_sim_time < due:
			left.append(entry)
			continue
		var drone_id: int = TypedVariant.as_int(entry.get("drone_id", 0), 0)
		if drone_id <= 0:
			continue
		var star: int = TypedVariant.as_int(entry.get("star", mother.star), mother.star)
		var sq: int = TypedVariant.as_int(entry.get("squadron_id", -1), -1)
		var have: int = _count_children_of(mother)
		var ang: float = float(have) * TAU / float(maxi(have + 1, 1))
		var offset: Vector3 = Vector3(cos(ang) * 1.15, 0.2, sin(ang) * 1.15)
		var drone: ShipUnit = _board.spawn_unmanned(
			drone_id, mother.team_id, mother.global_position + offset, mother, star, sq
		)
		_ensure_drone_trail(drone)
		var did: int = drone.get_instance_id()
		_drone_orbit_phase[did] = ang
		_drone_orbit_dir[did] = 1.0 if (have % 2) == 0 else -1.0
		_board.recalculate_fetters(mother.team_id)
	_drone_revive_queue = left


func _cull_orphan_drones() -> void:
	## Mother destroyed / missing → recycle combat drones immediately (no 400s revive).
	var doomed: Array[ShipUnit] = []
	for s: ShipUnit in _board.all_ships():
		if not s.is_unmanned or s.is_destroyed:
			continue
		if s.mother_ship_id == 0:
			continue
		var mother: ShipUnit = instance_from_id(s.mother_ship_id) as ShipUnit
		if mother == null or not is_instance_valid(mother) or mother.is_destroyed:
			doomed.append(s)
	## Drop pending revives whose mother is already gone.
	if not _drone_revive_queue.is_empty():
		var kept: Array = []
		for entry_v: Variant in _drone_revive_queue:
			var entry: Dictionary = TypedVariant.as_dict(entry_v)
			var mid2: int = TypedVariant.as_int(entry.get("mother_id", 0), 0)
			var mom2: ShipUnit = instance_from_id(mid2) as ShipUnit
			if mom2 == null or not is_instance_valid(mom2) or mom2.is_destroyed:
				continue
			kept.append(entry)
		_drone_revive_queue = kept
	for s: ShipUnit in doomed:
		@warning_ignore("unsafe_cast")
		var ship: ShipUnit = s as ShipUnit
		if ship == null:
			continue
		var iid: int = ship.get_instance_id()
		_drone_orbit_phase.erase(iid)
		_drone_orbit_dir.erase(iid)
		_drone_orbit_tilt.erase(iid)
		_drone_orbit_az.erase(iid)
		_drone_orbit_last_pos.erase(iid)
		_drone_orbit_stuck_s.erase(iid)
		_mining_wander_anchor.erase(iid)
		_mining_wander_cd.erase(iid)
		_mining_fx_cd.erase(iid)
		_mining_fx_last_anchor_id.erase(iid)
		_board.remove_ship_node(ship)

func _orbit_drone(s: ShipUnit, tgt: ShipUnit, delta: float) -> void:
	if tgt == null or not is_instance_valid(tgt):
		return
	## Fighters: orbit at star.optimal cells (EVE squadron orbit ≈ 10 km → 5 cells).
	## Other combat drones stay visually tight (cap 1.6 wu) — high tracking still hits.
	var radius: float
	if s.unmanned_kind == "fighter":
		var orbit_cells: float = maxf(s.optimal_cells, 2.0)
		radius = orbit_cells * CombatFormulas.world_units_per_cell()
	else:
		radius = maxf(0.9, minf(s.world_range_wu() * 0.8, 1.6))
	_orbit_around_3d(s, tgt.global_position, delta, radius, true)


func _wander_mining_drone(s: ShipUnit, delta: float) -> void:
	## Excavators orbit a random central MiningAnchor; periodically re-pick (MINING §2.1).
	var id: int = s.get_instance_id()
	var belt: AsteroidBelt = _find_asteroid_belt()
	if belt == null or belt.mining_anchors.is_empty():
		EngineBoosterTrail.set_emitting_on(s, false)
		return
	var cd: float = TypedVariant.as_float(_mining_wander_cd.get(id, 0.0), 0.0) - delta
	var anchor_v: Variant = _mining_wander_anchor.get(id)
	var anchor: Node3D = null
	if anchor_v is Node3D:
		@warning_ignore("unsafe_cast")
		anchor = anchor_v as Node3D
	var need_pick: bool = anchor == null or not is_instance_valid(anchor) or cd <= 0.0
	if need_pick:
		var pick_i: int = _auth_randi_range("mining_pick", 0, belt.mining_anchors.size() - 1)
		var pick_v: Variant = belt.mining_anchors[pick_i]
		if pick_v is Node3D:
			@warning_ignore("unsafe_cast")
			anchor = pick_v as Node3D
		_mining_wander_anchor[id] = anchor
		var cd_min: float = TypedVariant.as_float(DataStore.visual.get("mining_drone_wander_cd_min_s", 4.0), 4.0)
		var cd_max: float = TypedVariant.as_float(DataStore.visual.get("mining_drone_wander_cd_max_s", 12.0), 12.0)
		_mining_wander_cd[id] = _auth_randf_range("mining_wander", maxf(1.0, cd_min), maxf(cd_min + 0.1, cd_max))
	else:
		_mining_wander_cd[id] = cd
	if anchor == null or not is_instance_valid(anchor):
		EngineBoosterTrail.set_emitting_on(s, false)
		return
	var radius: float = TypedVariant.as_float(DataStore.visual.get("mining_drone_orbit_radius_wu", 1.35), 1.35)
	radius = maxf(0.75, radius)
	_orbit_around_3d(s, anchor.global_position, delta, radius, true)
	EngineBoosterTrail.set_emitting_on(s, true)


func _orbit_plane_basis(tilt_deg: float, az: float) -> Array:
	## Fixed plane: inclination θ vs horizontal; lean(az) is ascending-node direction.
	## n = up·cos(θ)+lean·sin(θ); θ=0 → horizontal circle; θ→90° → near-vertical.
	var tilt: float = deg_to_rad(clampf(tilt_deg, 0.0, 89.5))
	var lean: Vector3 = Vector3(cos(az), 0.0, sin(az))
	var plane_n: Vector3 = (Vector3.UP * cos(tilt) + lean * sin(tilt)).normalized()
	if plane_n.length_squared() < 0.0001:
		plane_n = Vector3.UP
	var e1: Vector3 = plane_n.cross(Vector3.UP)
	if e1.length_squared() < 1e-8:
		## Near-horizontal plane: use lean as in-plane axis.
		e1 = lean.cross(plane_n)
		if e1.length_squared() < 1e-8:
			e1 = Vector3.RIGHT
	e1 = e1.normalized()
	var e2: Vector3 = plane_n.cross(e1)
	if e2.length_squared() < 1e-8:
		e2 = Vector3.FORWARD
	else:
		e2 = e2.normalized()
	return [e1, e2]


func _orbit_around_3d(s: ShipUnit, center: Vector3, delta: float, radius: float, face_center: bool) -> void:
	var id: int = s.get_instance_id()
	var phase: float = TypedVariant.as_float(_drone_orbit_phase.get(id, 0.0), 0.0)
	var orbit_dir: float = TypedVariant.as_float(_drone_orbit_dir.get(id, 0.0), 0.0)
	if absf(orbit_dir) < 0.5:
		orbit_dir = 1.0 if _auth_randf("orbit_dir") < 0.5 else -1.0
		_drone_orbit_dir[id] = orbit_dir
	var tilt_deg: float = TypedVariant.as_float(_drone_orbit_tilt.get(id, -1.0), -1.0)
	if tilt_deg < 0.0:
		tilt_deg = _auth_randf_range("orbit_tilt", 20.0, 89.0)
		_drone_orbit_tilt[id] = tilt_deg
	if not _drone_orbit_az.has(id):
		_drone_orbit_az[id] = _auth_randf("orbit_az") * TAU
	var az: float = TypedVariant.as_float(_drone_orbit_az[id], 0.0)
	var basis: Array = _orbit_plane_basis(tilt_deg, az)
	var e1: Vector3 = basis[0]
	var e2: Vector3 = basis[1]
	var self_pos: Vector3 = s.global_position
	## Net world motion since last orbit tick (includes post-separation pushback).
	var stuck_eps: float = TypedVariant.as_float(DataStore.combat.get("unmanned_orbit_stuck_eps_wu", 0.06), 0.06)
	var stuck_limit: float = TypedVariant.as_float(DataStore.combat.get("unmanned_orbit_stuck_reverse_s", 2.0), 2.0)
	var stuck_s: float = TypedVariant.as_float(_drone_orbit_stuck_s.get(id, 0.0), 0.0)
	if _drone_orbit_last_pos.has(id):
		@warning_ignore("unsafe_cast")
		var last_pos: Vector3 = _drone_orbit_last_pos[id]
		if self_pos.distance_to(last_pos) < stuck_eps:
			stuck_s += delta
		else:
			stuck_s = 0.0
		if stuck_s >= stuck_limit:
			orbit_dir = -orbit_dir
			_drone_orbit_dir[id] = orbit_dir
			stuck_s = 0.0
	_drone_orbit_stuck_s[id] = stuck_s
	_drone_orbit_last_pos[id] = self_pos
	## Offset projected into the fixed orbit plane (not live XZ radial).
	var offset: Vector3 = self_pos - center
	var in_plane: Vector3 = e1 * offset.dot(e1) + e2 * offset.dot(e2)
	var planar_r: float = in_plane.length()
	var nearest_phase: float = phase
	if planar_r > 0.05:
		nearest_phase = atan2(in_plane.dot(e2), in_plane.dot(e1))
	var on_circle: Vector3 = center + (e1 * cos(nearest_phase) + e2 * sin(nearest_phase)) * radius
	var dist_circle: float = self_pos.distance_to(on_circle)
	var enter_band: float = radius * 0.35
	var desired_dir: Vector3 = Vector3.ZERO
	if dist_circle > enter_band:
		## Approach nearest point on the tilted circle — never dive through the pole/overhead.
		desired_dir = (on_circle - self_pos).normalized()
		_drone_orbit_phase[id] = nearest_phase
	else:
		## Advance along the fixed circle; re-sync angle from projection so pushback cannot polar-stall.
		phase = nearest_phase + delta * 0.9 * orbit_dir
		_drone_orbit_phase[id] = phase
		on_circle = center + (e1 * cos(phase) + e2 * sin(phase)) * radius
		var tangent: Vector3 = (-e1 * sin(phase) + e2 * cos(phase)) * orbit_dir
		if tangent.length_squared() > 0.0001:
			tangent = tangent.normalized()
		var pull: Vector3 = on_circle - self_pos
		desired_dir = tangent + pull * 1.6
		if desired_dir.length_squared() > 0.0001:
			desired_dir = desired_dir.normalized()
		elif tangent.length_squared() > 0.0001:
			desired_dir = tangent
		else:
			desired_dir = Vector3.ZERO
	if desired_dir.length_squared() > 0.0001:
		s.face_dir_3d(desired_dir)
	_apply_accelerated_displacement(s, desired_dir, delta)
	if face_center:
		var aim: Vector3 = center - s.global_position
		if aim.length_squared() > 0.0001:
			s.face_dir_3d(aim)
	## Displacement already set emit (instant step for unmanned). Do NOT re-gate on
	## combat_speed_now — unmanned clear velocity, so that check permanently kills trails.
	_attach_trail_once(s)


func _tick_mining_fx(s: ShipUnit, delta: float) -> void:
	if s == null or s.is_destroyed or s.slot_type != "field":
		return
	var wfx: String = ""
	if s.has_method("resolve_weapon_fx_kind"):
		wfx = str(s.resolve_weapon_fx_kind())
	var is_excavator: bool = str(s.unmanned_kind) == "mining_excavator"
	if wfx != "mining" and not is_excavator:
		return
	var sid: int = s.get_instance_id()
	var left: float = TypedVariant.as_float(_mining_fx_cd.get(sid, 0.0), 0.0)
	left -= delta
	if left > 0.0:
		_mining_fx_cd[sid] = left
		return
	var belt: AsteroidBelt = _find_asteroid_belt()
	if belt == null or belt.mining_anchors.is_empty():
		_mining_fx_cd[sid] = 1.0
		return
	## Every shot: fresh uniform random MiningAnchor (MINING §2.3). Never reuse wander lock.
	var anchor: Node3D = _pick_random_mining_anchor(belt, sid)
	if anchor == null or not is_instance_valid(anchor):
		_mining_fx_cd[sid] = 1.0
		return
	_mining_fx_last_anchor_id[sid] = anchor.get_instance_id()
	if _fx != null and _fx.has_method("play_to_anchor"):
		_fx.call("play_to_anchor", s, anchor, "mining", 0.9)
	if s.has_method("advance_muzzle"):
		s.advance_muzzle()
	var cd_max: float = TypedVariant.as_float(DataStore.visual.get("mining_fx_cd_max_s", 10.0), 10.0)
	_mining_fx_cd[sid] = _viz_randf_range(0.05, maxf(0.1, cd_max))


func _pick_random_mining_anchor(belt: AsteroidBelt, firer_id: int) -> Node3D:
	var anchors: Array = belt.mining_anchors
	var n: int = anchors.size()
	if n <= 0:
		return null
	var idx: int = _auth_randi_range("mining_pick", 0, n - 1)
	var pick: Node3D = _anchor_at(anchors, idx)
	if n == 1:
		return pick
	## Prefer a different rock than the previous shot so consecutive beams visibly retarget.
	var last_id: int = TypedVariant.as_int(_mining_fx_last_anchor_id.get(firer_id, 0), 0)
	if pick == null or (last_id != 0 and pick.get_instance_id() == last_id):
		idx = (idx + 1 + _auth_randi_range("mining_pick", 0, n - 2)) % n
		pick = _anchor_at(anchors, idx)
	return pick


## Belt rocks can be freed mid-battle; a stale slot must not be cast blindly.
func _anchor_at(anchors: Array, idx: int) -> Node3D:
	var v: Variant = anchors[idx]
	if typeof(v) != TYPE_OBJECT or not is_instance_valid(v):
		return null
	@warning_ignore("unsafe_cast")
	return v as Node3D


func _find_asteroid_belt() -> AsteroidBelt:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var nodes: Array = tree.get_nodes_in_group("asteroid_belt")
	for n: Node in nodes:
		if n is AsteroidBelt:
			return n as AsteroidBelt
	# Fallback: search under board parent MapEnv
	if _board:
		var p: Node = _board.get_parent()
		if p:
			var found: Node = p.find_child("AsteroidBelt", true, false)
			if found is AsteroidBelt:
				return found as AsteroidBelt
	return null


## Public: cyno jump / late spawn — unstack near neighbors then unfold.
func schedule_capital_hull_morph(ship: ShipUnit) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	if str(ship.hull_morph).is_empty():
		return
	_enqueue_morph_ships([ship])


func _queue_hull_morphs_with_unstack() -> void:
	var list: Array[ShipUnit] = []
	for s: ShipUnit in _board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		if s.slot_type != "field" or s.is_unmanned:
			continue
		if str(s.hull_morph).is_empty() or s.hull_morphed or s.hull_morph_playing:
			continue
		if not s.can_begin_hull_morph():
			continue
		list.append(s)
	_enqueue_morph_ships(list)


func _enqueue_morph_ships(ships: Array) -> void:
	if ships.is_empty():
		return
	var min_d: float = TypedVariant.as_float(DataStore.combat.get("hull_morph_unstack_min_dist_wu", 1.4), 1.4)
	var push_wu: float = TypedVariant.as_float(DataStore.combat.get("hull_morph_unstack_wu", 0.85), 0.85)
	var dur: float = TypedVariant.as_float(DataStore.combat.get("hull_morph_unstack_s", 0.8), 0.8)
	dur = maxf(0.05, dur)
	## Accumulate lateral push per ship from all close neighbors (any field ship).
	var targets: Dictionary = {}  # instance_id -> Vector3 goal
	for s: Variant in ships:
		@warning_ignore("unsafe_cast")
		var ship: ShipUnit = s as ShipUnit
		if ship == null:
			continue
		targets[ship.get_instance_id()] = ship.global_position
	for i: int in range(ships.size()):
		@warning_ignore("unsafe_cast")
		var a: ShipUnit = ships[i] as ShipUnit
		if a == null:
			continue
		for j: int in range(i + 1, ships.size()):
			@warning_ignore("unsafe_cast")
			var b: ShipUnit = ships[j] as ShipUnit
			if b == null:
				continue
			var delta: Vector3 = a.global_position - b.global_position
			delta.y = 0.0
			var d: float = delta.length()
			if d >= min_d:
				continue
			var dir: Vector3
			if d < 0.001:
				## Stable left/right by instance id.
				var bias: float = -1.0 if a.get_instance_id() < b.get_instance_id() else 1.0
				dir = Vector3(bias, 0.0, 0.0)
			else:
				dir = delta.normalized()
			var half: float = push_wu * 0.5
			## Extra separation when almost overlapping.
			if d < min_d * 0.5:
				half = push_wu
			var aid: int = a.get_instance_id()
			var bid: int = b.get_instance_id()
			@warning_ignore("unsafe_cast")
			targets[aid] = (targets[aid] as Vector3) + dir * half
			@warning_ignore("unsafe_cast")
			targets[bid] = (targets[bid] as Vector3) - dir * half
	## Also push away from non-morph field ships that are clipping.
	var morph_ids: Dictionary = {}
	for s0: Variant in ships:
		@warning_ignore("unsafe_cast")
		var sh0: ShipUnit = s0 as ShipUnit
		if sh0:
			morph_ids[sh0.get_instance_id()] = true
	for s2: Variant in ships:
		@warning_ignore("unsafe_cast")
		var ship2: ShipUnit = s2 as ShipUnit
		if ship2 == null:
			continue
		for o: ShipUnit in _board.all_ships():
			if o == null or o == ship2 or o.is_destroyed or o.slot_type != "field":
				continue
			if morph_ids.has(o.get_instance_id()):
				continue
			var dlt: Vector3 = ship2.global_position - o.global_position
			dlt.y = 0.0
			var od: float = dlt.length()
			if od >= min_d:
				continue
			if od < 0.001:
				dlt = Vector3(-1.0 if ship2.get_instance_id() < o.get_instance_id() else 1.0, 0.0, 0.0)
			var push_dir: Vector3 = dlt.normalized()
			var iid2: int = ship2.get_instance_id()
			@warning_ignore("unsafe_cast")
			targets[iid2] = (targets[iid2] as Vector3) + push_dir * (push_wu * 0.5)
	for s3: Variant in ships:
		@warning_ignore("unsafe_cast")
		var ship3: ShipUnit = s3 as ShipUnit
		if ship3 == null:
			continue
		var from_p: Vector3 = ship3.global_position
		var to_p_v: Variant = targets.get(ship3.get_instance_id(), from_p)
		@warning_ignore("unsafe_cast")
		var to_p: Vector3 = to_p_v as Vector3
		to_p.y = 0.2
		to_p = BoardController.clamp_to_combat_play_area(to_p)
		var need_move: bool = from_p.distance_to(to_p) > 0.05
		ship3.hull_morph_unstacking = need_move
		_morph_unstack.append({
			"ship": ship3,
			"from": from_p,
			"to": to_p,
			"t": 0.0,
			"dur": dur if need_move else 0.05,
		})


func _tick_morph_unstack(delta: float) -> void:
	if _morph_unstack.is_empty():
		return
	var mul: float = 1.0
	var root: Node = get_tree().get_first_node_in_group("match_root") if get_tree() else null
	if root != null:
		var mc_v: Variant = root.get("match_ctrl")
		if mc_v is Object:
			@warning_ignore("unsafe_cast")
			mul = TypedVariant.as_float((mc_v as Object).get("speed_multiplier"), 1.0)
	var left: Array = []
	for entry: Variant in _morph_unstack:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var entry_d: Dictionary = entry as Dictionary
		@warning_ignore("unsafe_cast")
		var ship: ShipUnit = entry_d.get("ship") as ShipUnit
		if ship == null or not is_instance_valid(ship) or ship.is_destroyed:
			continue
		var dur: float = maxf(0.05, TypedVariant.as_float(entry_d.get("dur", 0.8), 0.8))
		var t: float = TypedVariant.as_float(entry_d.get("t", 0.0), 0.0) + delta * mul
		entry_d["t"] = t
		var u: float = clampf(t / dur, 0.0, 1.0)
		## Smoothstep slide.
		var smooth: float = u * u * (3.0 - 2.0 * u)
		var from_v: Variant = entry_d.get("from", ship.global_position)
		var to_v: Variant = entry_d.get("to", ship.global_position)
		@warning_ignore("unsafe_cast")
		var from_p: Vector3 = from_v as Vector3
		@warning_ignore("unsafe_cast")
		var to_p: Vector3 = to_v as Vector3
		ship.global_position = from_p.lerp(to_p, smooth)
		_clamp_after_move(ship)
		EngineBoosterTrail.set_emitting_on(ship, u < 0.98 and from_p.distance_to(to_p) > 0.05)
		if u < 1.0:
			left.append(entry_d)
			continue
		ship.hull_morph_unstacking = false
		EngineBoosterTrail.set_emitting_on(ship, false)
		ship.begin_hull_morph_if_needed()
	_morph_unstack = left


func _ensure_drone_trail(drone: ShipUnit) -> void:
	EngineBoosterTrail.ensure_on(drone, drone.team_id == ShipUnit.TEAM_PLAYER)
	EngineBoosterTrail.set_emitting_on(drone, true)

func _ensure_ship_trail(ship: ShipUnit) -> void:
	EngineBoosterTrail.ensure_on(ship, ship.team_id == ShipUnit.TEAM_PLAYER)

## Per-frame guard: re-running `ensure_on` every tick re-resolves nozzles for nothing.
func _attach_trail_once(ship: ShipUnit) -> void:
	if ship.get_node_or_null(EngineBoosterTrail.ROOT_NAME) == null:
		EngineBoosterTrail.ensure_on(ship, ship.team_id == ShipUnit.TEAM_PLAYER)

func _apply_drone_lod() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	## Default match camera already sits ~45 wu out, so the old 30/100 cut every drone trail.
	## Thresholds must clear the standard rig and only bite on zoom-out (COMBAT §14C).
	var trail_wu: float = TypedVariant.as_float(DataStore.visual.get("unmanned_trail_lod_wu", 90.0), 90.0)
	var hide_wu: float = TypedVariant.as_float(DataStore.visual.get("unmanned_hide_lod_wu", 200.0), 200.0)
	for s: ShipUnit in _board.all_ships():
		if not s.is_unmanned:
			continue
		var d: float = cam.global_position.distance_to(s.global_position)
		## Far: hide trail. Near: do not force-on here — orbit / mining / move paths own emit.
		if d > trail_wu:
			EngineBoosterTrail.set_emitting_on(s, false)
		s.visible = d <= hide_wu and not s.is_destroyed

func _spawn_isolation_debris() -> void:
	var cmin: int = TypedVariant.as_int(DataStore.combat.get("isolation_debris_count_min", 3), 3)
	var cmax: int = TypedVariant.as_int(DataStore.combat.get("isolation_debris_count_max", 5), 5)
	var n: int = clampi(cmin + _auth_randi_range("isolation_debris", 0, maxi(0, cmax - cmin)), cmin, cmax)
	var half: float = TypedVariant.as_float(DataStore.combat.get("isolation_half_width_wu", 2.5), 2.5)
	for i: int in range(n):
		var mi: MeshInstance3D = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = _viz_randf_range(0.35, 0.7)
		sphere.height = sphere.radius * 2.0
		mi.mesh = sphere
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		## Unshaded so fill lights don't wash debris into white spheres.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.18, 0.16, 0.14, 1.0)
		mat.roughness = 0.95
		mi.material_override = mat
		mi.position = Vector3(_viz_randf_range(-10.0, 10.0), sphere.radius, _viz_randf_range(-half * 0.8, half * 0.8))
		var parent: Node = _board.get_parent()
		if parent:
			parent.add_child(mi)
		else:
			_board.add_child(mi)
		_debris.append({"node": mi, "hit_cd": {}})

func _clear_debris() -> void:
	for d_v: Variant in _debris:
		var d_entry: Dictionary = TypedVariant.as_dict(d_v)
		var n_v: Variant = d_entry.get("node")
		if n_v is Node and is_instance_valid(n_v):
			@warning_ignore("unsafe_cast")
			(n_v as Node).queue_free()
	_debris.clear()

func _tick_debris_contacts(delta: float) -> void:
	var dmg_lo: float = TypedVariant.as_float(DataStore.combat.get("isolation_debris_damage_min", 5), 5)
	var dmg_hi: float = TypedVariant.as_float(DataStore.combat.get("isolation_debris_damage_max", 10), 10)
	for d_v: Variant in _debris:
		var d_entry: Dictionary = TypedVariant.as_dict(d_v)
		var node_v: Variant = d_entry.get("node")
		if node_v == null or not is_instance_valid(node_v) or not (node_v is Node3D):
			continue
		@warning_ignore("unsafe_cast")
		var node: Node3D = node_v as Node3D
		var cds: Dictionary = TypedVariant.as_dict(d_entry.get("hit_cd", {}))
		for s: ShipUnit in _board.all_ships():
			if s.slot_type != "field" or s.is_destroyed:
				continue
			var sid: int = s.get_instance_id()
			cds[sid] = maxf(0.0, TypedVariant.as_float(cds.get(sid, 0.0), 0.0) - delta)
			if cds[sid] > 0.0:
				continue
			if s.global_position.distance_to(node.global_position) > 1.4:
				continue
			var dealt: float = _auth_randf_range("isolation_debris_dmg", dmg_lo, dmg_hi)
			s.apply_hit_dict({"emp": 0.0, "thermal": 0.0, "kinetic": 0.0, "explosive": dealt})
			cds[sid] = 1.25
			if _float_text:
				_float_text.add_damage(s.global_position, dealt, s.get_instance_id())
		d_entry["hit_cd"] = cds
