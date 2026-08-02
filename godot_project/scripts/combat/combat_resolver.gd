extends Node
class_name CombatResolver
## V2 combat: capacitor, EVE turret/missile/lock, racial logistics, movement AI.
## Same path for all ships — no scenarioId branches.

var _board: BoardController
var _active: bool = false
var _retarget_acc: float = 0.0
var _combat_sim_time: float = 0.0
var _fx = null  # FiringFx
var _missile_queue: Array = []  # {pos, source_id, target_id, damage, speed_cells_per_s}
var _float_text: FloatTextPool
var _debris: Array = []  # {node: Node3D, cooldown: Dictionary}
var _drone_orbit_phase: Dictionary = {}  # instance_id -> float
## Orbit tangent sign: +1 / -1 (reverse when stuck ~2s).
var _drone_orbit_dir: Dictionary = {}  # instance_id -> float
var _drone_orbit_last_xz: Dictionary = {}  # instance_id -> Vector3
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
## Hull morph after unstack: {ship: ShipUnit, from: Vector3, to: Vector3, t: float, dur: float}
var _morph_unstack: Array = []
## SEMI_ASYNC §2 — authority RNG (MatchRng) vs presentation (VisualRng).
var match_rng: MatchRng = null
var battle_serial: int = 1
var visual_rng: VisualRng = VisualRng.new()

const DRONE_BW_COST := 5.0
const DRONE_CAP := 5
const RACE_DRONE_LIGHT := {"amarr": 1001, "caldari": 1002, "gallente": 1003, "minmatar": 1004}
const RACE_DRONE_MEDIUM := {"amarr": 1005, "caldari": 1006, "gallente": 1007, "minmatar": 1008}
const RACE_DRONE_HEAVY := {"amarr": 1011, "caldari": 1012, "gallente": 1013, "minmatar": 1014}
const DRONE_COUNT_EXCEPTIONS := {42: 5, 44: 4, 55: 4, 56: 5}

func bind(board: BoardController, fx = null) -> void:
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


func _auth_randf(event_kind: String) -> float:
	if match_rng:
		return match_rng.roll(battle_serial, event_kind)
	return randf()


func _auth_randi_range(event_kind: String, from_v: int, to_v: int) -> int:
	if match_rng:
		return match_rng.roll_int(battle_serial, event_kind, from_v, to_v)
	return randi_range(from_v, to_v)


func _auth_randf_range(event_kind: String, from_v: float, to_v: float) -> float:
	var t := _auth_randf(event_kind)
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
	_drone_orbit_phase.clear()
	_drone_orbit_dir.clear()
	_drone_orbit_last_xz.clear()
	_drone_orbit_stuck_s.clear()
	_fighter_dealt_total = 0.0
	_fighter_hit_count = 0
	_fighter_shot_count = 0
	_mining_fx_cd.clear()
	_mining_fx_last_anchor_id.clear()
	_mining_wander_anchor.clear()
	_mining_wander_cd.clear()
	_morph_unstack.clear()
	_clear_debris()
	_spawn_isolation_debris()
	for s in _board.all_ships():
		if s.slot_type == "field" and not s.is_destroyed:
			s.set_combat_tint(true)
			s.reset_combat_runtime()
	_spawn_combat_drones()
	_spawn_capital_auxiliaries()
	## Opening pose: both sides on shared cells shift ±X before first tick.
	_board.refresh_cross_team_cell_offsets(true)
	## Capitals: unstack if clipped, then hull_morph (siege / industrial).
	_queue_hull_morphs_with_unstack()
	## Soft-follow mesh after opening teleports so lag starts from the final pose.
	if _board and _board.has_method("arm_visual_follow"):
		_board.arm_visual_follow()

func sim_time() -> float:
	return _combat_sim_time

func fighter_damage_summary() -> Dictionary:
	var t := maxf(_combat_sim_time, 0.001)
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
	for s in _board.all_ships():
		if s != null and is_instance_valid(s):
			s.hull_morph_unstacking = false
	var summary := fighter_damage_summary()
	if float(summary.get("shots", 0)) > 0.0 or float(summary.get("dealt", 0.0)) > 0.0:
		var diag := SessionDiagnostics.instance()
		if diag and diag.has_method("log_event"):
			diag.log_event(
				"fighter.dps",
				"dealt=%.1f hits=%d shots=%d sim_s=%.1f dps=%.1f" % [
					float(summary.get("dealt", 0.0)),
					int(summary.get("hits", 0)),
					int(summary.get("shots", 0)),
					float(summary.get("sim_s", 0.0)),
					float(summary.get("dps", 0.0)),
				]
			)
	_missile_queue.clear()
	_clear_drones()
	_clear_debris()
	for s in _board.all_ships():
		s.set_combat_tint(false)
		s.combat_target = null
		EngineBoosterTrail.set_emitting_on(s, false)
	if _fx and _fx.has_method("clear_all"):
		_fx.clear_all()

func tick(delta: float) -> void:
	if not _active:
		return
	_combat_sim_time += delta
	var now := _combat_sim_time
	_tick_morph_unstack(delta)
	_cull_orphan_drones()
	_spawn_capital_auxiliaries()
	var retarget_interval := float(DataStore.combat.get("retarget_interval_s", 10.0))
	_retarget_acc += delta
	var periodic_retarget := _retarget_acc >= retarget_interval
	if periodic_retarget:
		_retarget_acc = 0.0
	_tick_missiles(delta)
	for s in _board.all_ships():
		if s.is_destroyed or s.slot_type != "field":
			continue
		s.tick_capacitor(delta)
		s.tick_stat_modifiers(delta)
		s.update_retreat(now)
		_tick_mining_fx(s, delta)
		## Salvage freighter escorts nobody: it parks, never locks and never returns fire
		## (0 damage), but everyone else targets it by the normal rules (FREIGHTER_AND_TITAN §1.2.1).
		if s.is_protect_target:
			s.combat_target = null
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
		var tgt_any = s.combat_target
		if tgt_any == null or not is_instance_valid(tgt_any):
			s.combat_target = null
			## Logistics with nothing to repair must still move (soft follow), else looks stuck.
			if s.is_logistic and not s.has_cyno_module() and not s.immobile_in_combat and not s.hull_morph_unstacking:
				_move_logistic_idle(s, delta, now)
			continue
		var tgt := tgt_any as ShipUnit
		if tgt == null:
			s.combat_target = null
			if s.is_logistic and not s.has_cyno_module() and not s.immobile_in_combat and not s.hull_morph_unstacking:
				_move_logistic_idle(s, delta, now)
			continue
		if tgt.is_destroyed:
			s.combat_target = null
			if s.is_logistic and not s.has_cyno_module() and not s.immobile_in_combat and not s.hull_morph_unstacking:
				_move_logistic_idle(s, delta, now)
			continue
		s.sync_lock(tgt, now)
		s.advance_lock(delta)
		## Lead lock on the runner-up, refreshed on the same cadence as the retarget so it
		## gets a full interval to finish; done in time → next switch fires at once (§13.1).
		if periodic_retarget and not s.is_logistic and not s.is_unmanned:
			s.sync_pre_lock(_find_target(s, tgt))
		s.advance_pre_lock(delta)
		## Covert cyno: pinned + no weapons. Other immobile (dread siege / Rorqual industrial):
		## stay put / no yaw, but still lock+fire (morph is visual-only).
		if s.has_cyno_module():
			continue
		if s.hull_morph_unstacking:
			EngineBoosterTrail.set_emitting_on(s, false)
			continue
		if s.immobile_in_combat:
			EngineBoosterTrail.set_emitting_on(s, false)
		elif s.is_unmanned and s.unmanned_kind.find("sentry") < 0:
			_orbit_drone(s, tgt, delta)
		else:
			_move_ship(s, tgt, delta, now)
		_try_attack(s, tgt, now)
	_tick_debris_contacts(delta)
	_apply_drone_lod()
	_apply_separation()

func _update_targeting(s: ShipUnit, delta: float, periodic_retarget: bool) -> void:
	## Combat drones inherit mother lock when mother still shoots.
	## Carriers (hull DPH=0) let fighters hunt on their own — otherwise damage never lands.
	if s.is_unmanned and str(s.unmanned_kind) == "mining_excavator":
		s.combat_target = null
		return
	if s.is_unmanned and s.mother_ship_id != 0:
		var mother: ShipUnit = instance_from_id(s.mother_ship_id) as ShipUnit
		if mother == null or not is_instance_valid(mother) or mother.is_destroyed:
			return
		var mt = mother.combat_target
		if mother.has_offensive_damage() and mt != null and is_instance_valid(mt) and not (mt as ShipUnit).is_destroyed:
			s.combat_target = mt
			return
	var tgt_any = s.combat_target
	var tgt: ShipUnit = null
	if tgt_any != null and is_instance_valid(tgt_any):
		tgt = tgt_any as ShipUnit
	var need_search := tgt == null or tgt.is_destroyed
	if not need_search and s.is_logistic and not tgt.needs_heal_for_race(s.race):
		need_search = true
	if not need_search and not s.is_logistic and periodic_retarget:
		need_search = true
	if not need_search:
		s.no_target_acc = 0.0
		return
	## Current target died / invalid → switch immediately (do not wait no_target_search_s).
	if tgt != null and (not is_instance_valid(tgt) or tgt.is_destroyed):
		s.combat_target = _find_target(s)
		s.no_target_acc = 0.0
		return
	var search_s := float(DataStore.combat.get("no_target_search_s", 0.5))
	if tgt != null and not tgt.is_destroyed:
		s.combat_target = _find_target(s)
		return
	s.no_target_acc += delta
	if s.no_target_acc >= search_s:
		s.no_target_acc = 0.0
		s.combat_target = _find_target(s)

func _move_ship(s: ShipUnit, tgt: ShipUnit, delta: float, now_s: float) -> void:
	if s.immobile_in_combat or s.has_cyno_module():
		return
	## Unstack slide is driven by CombatResolver, not engagement move.
	if s.hull_morph_unstacking:
		return
	var speed := s.combat_move_speed()
	var desired_cells := _desired_engagement_cells(s, tgt)
	var desired_wu := desired_cells * CombatFormulas.world_units_per_cell()
	var deadband := float(DataStore.combat.get("range_deadband_cells", 0.25))
	deadband *= CombatFormulas.world_units_per_cell()
	var move_goal: Vector3
	if s.is_logistic or s.in_retreat(now_s):
		move_goal = _logistic_position(s, tgt, now_s)
	else:
		move_goal = _combat_position(s, tgt, desired_wu, deadband)
		move_goal = _apply_screen_margin(s, tgt, move_goal)
	var dir: Vector3 = move_goal - s.global_position
	dir.y = 0.0
	var step_len := dir.length()
	_ensure_ship_trail(s)
	if step_len > deadband:
		dir /= step_len
		s.face_dir_xz(dir)
		s.global_position += dir * minf(speed * delta, step_len)
		EngineBoosterTrail.set_emitting_on(s, true)
	else:
		var aim: Vector3 = tgt.global_position - s.global_position
		aim.y = 0.0
		s.face_dir_xz(aim)
		EngineBoosterTrail.set_emitting_on(s, false)
	s.global_position = BoardController.clamp_to_combat_play_area(s.global_position)
	s.global_position.y = 0.2

func _desired_engagement_cells(s: ShipUnit, tgt: ShipUnit) -> float:
	## Min engagement distance = 1 cell (no point-blank stack).
	var min_cells := float(DataStore.combat.get("min_engagement_cells", 1.0))
	var raw: float
	if s.is_missile_weapon():
		raw = s.world_range_cells()
	else:
		raw = _ternary_optimal_cells(s, tgt)
	return maxf(raw, min_cells)

func _ternary_optimal_cells(s: ShipUnit, tgt: ShipUnit) -> float:
	var lo := 0.0
	var hi := maxf(s.world_range_cells(), 0.001)
	for _i in range(24):
		var m1 := lo + (hi - lo) / 3.0
		var m2 := hi - (hi - lo) / 3.0
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
	var dist_wu := away.length()
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
			return s.global_position.lerp(enemy_c as Vector3, 0.15)
		return s.global_position
	var repair_wu := s.world_range_wu()
	var enemy_centroid: Variant = _enemy_centroid(s.team_id)
	var dir: Vector3
	if enemy_centroid != null:
		dir = focus.global_position - (enemy_centroid as Vector3)
	else:
		dir = focus.global_position - s.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.0, 0.0, 1.0)
	else:
		dir = dir.normalized()
	var anchor := focus.global_position + dir * repair_wu * 0.85
	if s.in_retreat(now_s) and not s.is_logistic:
		var logi_c: Variant = _logistics_centroid(s.team_id)
		if logi_c != null and enemy_centroid != null:
			var back: Vector3 = (logi_c as Vector3) - (enemy_centroid as Vector3)
			back.y = 0.0
			if back.length_squared() > 0.0001:
				anchor = (logi_c as Vector3) + back.normalized() * CombatFormulas.world_units_per_cell()
	return anchor


## Soft station-keeping when no ally needs heal (COMBAT §14.1 / §14.2).
func _move_logistic_idle(s: ShipUnit, delta: float, now_s: float) -> void:
	var focus := _nearest_ally_any(s)
	var move_goal := _logistic_position(s, focus, now_s)
	var speed := s.combat_move_speed()
	var deadband := float(DataStore.combat.get("range_deadband_cells", 0.25))
	deadband *= CombatFormulas.world_units_per_cell()
	var dir: Vector3 = move_goal - s.global_position
	dir.y = 0.0
	var step_len := dir.length()
	_ensure_ship_trail(s)
	if step_len > deadband:
		dir /= step_len
		s.face_dir_xz(dir)
		s.global_position += dir * minf(speed * delta, step_len)
		EngineBoosterTrail.set_emitting_on(s, true)
	else:
		## Slow lateral drift so full-HP idle never looks frozen.
		var enemy_c: Variant = _enemy_centroid(s.team_id)
		var drift := Vector3(1.0, 0.0, 0.0)
		if enemy_c != null:
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
		## Phase by instance id so multiple logi don't stack.
		var phase := float(s.get_instance_id() % 97) * 0.11
		var wobble := sin(now_s * 0.55 + phase) * CombatFormulas.world_units_per_cell() * 0.35
		s.face_dir_xz(drift)
		s.global_position += drift * (wobble * delta * 0.85)
		EngineBoosterTrail.set_emitting_on(s, absf(wobble) > 0.05)
	s.global_position = BoardController.clamp_to_combat_play_area(s.global_position)
	s.global_position.y = 0.2


## Manned mining hulls: logistics-like soft move; keep a MiningAnchor in range (MINING §2.1b).
func _move_mining_ship(s: ShipUnit, delta: float, now_s: float) -> void:
	if s.immobile_in_combat or s.has_cyno_module() or s.hull_morph_unstacking:
		return
	var belt := _find_asteroid_belt()
	var ore := _pick_mining_move_anchor(s, belt)
	var speed := s.combat_move_speed()
	var deadband := float(DataStore.combat.get("range_deadband_cells", 0.25))
	deadband *= CombatFormulas.world_units_per_cell()
	var range_wu := maxf(s.world_range_wu(), CombatFormulas.world_units_per_cell())
	_ensure_ship_trail(s)
	if ore == null:
		## No belt — soft drift like logistic idle without focus.
		_move_logistic_idle(s, delta, now_s)
		return
	var ore_xz := Vector3(ore.global_position.x, 0.0, ore.global_position.z)
	var self_xz := Vector3(s.global_position.x, 0.0, s.global_position.z)
	var away: Vector3 = self_xz - ore_xz
	away.y = 0.0
	var dist := away.length()
	if dist < 0.001:
		away = Vector3(0.0, 0.0, 1.0)
		dist = 0.0
	else:
		away = away.normalized()
	## Hold inside range (soft ring ~85% like logistics repair station).
	var hold_wu := range_wu * 0.85
	if dist > range_wu + deadband:
		## Too far — approach ore until in range.
		var move_goal := ore_xz + away * hold_wu
		move_goal.y = s.global_position.y
		var dir: Vector3 = move_goal - s.global_position
		dir.y = 0.0
		var step_len := dir.length()
		if step_len > 0.001:
			dir /= step_len
			s.face_dir_xz(dir)
			s.global_position += dir * minf(speed * delta, step_len)
			EngineBoosterTrail.set_emitting_on(s, true)
	elif dist < hold_wu - deadband and dist > 0.05:
		## Too close under the belt — soft push out to hold ring (no kite past range).
		var move_goal2 := ore_xz + away * hold_wu
		move_goal2.y = s.global_position.y
		var dir2: Vector3 = move_goal2 - s.global_position
		dir2.y = 0.0
		var step2 := dir2.length()
		if step2 > 0.001:
			dir2 /= step2
			s.face_dir_xz(dir2)
			s.global_position += dir2 * minf(speed * delta * 0.65, step2)
			EngineBoosterTrail.set_emitting_on(s, true)
	else:
		## In range — logistic-style lateral wobble; face ore.
		var tangent := Vector3(-away.z, 0.0, away.x)
		if tangent.length_squared() < 0.0001:
			tangent = Vector3(1.0, 0.0, 0.0)
		else:
			tangent = tangent.normalized()
		var phase := float(s.get_instance_id() % 97) * 0.11
		var wobble := sin(now_s * 0.55 + phase) * CombatFormulas.world_units_per_cell() * 0.35
		var face: Vector3 = ore_xz - self_xz
		face.y = 0.0
		s.face_dir_xz(face if face.length_squared() > 0.0001 else tangent)
		s.global_position += tangent * (wobble * delta * 0.85)
		EngineBoosterTrail.set_emitting_on(s, absf(wobble) > 0.05)
	s.global_position = BoardController.clamp_to_combat_play_area(s.global_position)
	s.global_position.y = 0.2


func _pick_mining_move_anchor(s: ShipUnit, belt: AsteroidBelt) -> Node3D:
	if belt == null or belt.mining_anchors.is_empty():
		return null
	var range_wu := maxf(s.world_range_wu(), CombatFormulas.world_units_per_cell())
	var self_xz := Vector3(s.global_position.x, 0.0, s.global_position.z)
	## Prefer an already-in-range ore (stable station-keeping).
	var best_in: Node3D = null
	var best_in_d := 99999.0
	var best_any: Node3D = null
	var best_any_d := 99999.0
	for a in belt.mining_anchors:
		if a == null or not is_instance_valid(a):
			continue
		var n := a as Node3D
		if n == null:
			continue
		var d := self_xz.distance_to(Vector3(n.global_position.x, 0.0, n.global_position.z))
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
	var best_d := 99999.0
	var best_id := 2147483647
	for o in _board.field_ships(logi.team_id):
		if o == logi or o.is_destroyed:
			continue
		if bool(o.get("is_unmanned")):
			continue
		var d := logi.grid_dist_to(o)
		var oid := o.get_instance_id()
		if d < best_d - 0.001 or (absf(d - best_d) <= 0.001 and oid < best_id):
			best_d = d
			best_id = oid
			best = o
	return best

func _apply_screen_margin(s: ShipUnit, tgt: ShipUnit, move_goal: Vector3) -> Vector3:
	## Soft screen vs logistics centroid — never push outside weapon range.
	var margin_cells := float(DataStore.combat.get("screen_margin", 1.0))
	var margin_wu := margin_cells * CombatFormulas.world_units_per_cell()
	var logi_c: Variant = _logistics_centroid(s.team_id)
	if logi_c == null:
		return move_goal
	var enemy_pos := tgt.global_position
	var flat_self := Vector3(s.global_position.x, 0.0, s.global_position.z)
	var flat_enemy := Vector3(enemy_pos.x, 0.0, enemy_pos.z)
	var flat_logi := Vector3((logi_c as Vector3).x, 0.0, (logi_c as Vector3).z)
	var d_self := flat_self.distance_to(flat_enemy)
	var d_logi := flat_logi.distance_to(flat_enemy)
	if d_self >= d_logi + margin_wu:
		return move_goal
	var away: Vector3 = flat_self - flat_enemy
	if away.length_squared() < 0.0001:
		away = Vector3(0.0, 0.0, 1.0)
	else:
		away = away.normalized()
	var needed := (d_logi + margin_wu) - d_self
	var candidate := move_goal + away * needed
	var max_range_wu := s.world_range_cells() * CombatFormulas.world_units_per_cell()
	var cand_flat := Vector3(candidate.x, 0.0, candidate.z)
	if cand_flat.distance_to(flat_enemy) > max_range_wu:
		## Clamp onto max fire ring so screen_margin cannot starve attacks.
		return flat_enemy + away * max_range_wu
	return candidate

func _logistics_centroid(team: int) -> Variant:
	var sum := Vector3.ZERO
	var n := 0
	for o in _board.field_ships(team):
		if o.is_destroyed or not o.is_logistic:
			continue
		sum += o.global_position
		n += 1
	if n == 0:
		return null
	return sum / float(n)

func _enemy_centroid(team: int) -> Variant:
	var enemy_team := ShipUnit.TEAM_AI if team == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
	var sum := Vector3.ZERO
	var n := 0
	for o in _board.field_ships(enemy_team):
		if o.is_destroyed:
			continue
		sum += o.global_position
		n += 1
	if n == 0:
		return null
	return sum / float(n)

func _best_heal_ally(logi: ShipUnit) -> ShipUnit:
	var best: ShipUnit = null
	var best_d := 99999.0
	var best_id := 2147483647
	for o in _board.field_ships(logi.team_id):
		if o == logi or o.is_destroyed:
			continue
		if bool(o.get("is_unmanned")):
			continue
		if not o.needs_heal_for_race(logi.race):
			continue
		var d := logi.grid_dist_to(o)
		var oid := o.get_instance_id()
		if d < best_d - 0.001 or (absf(d - best_d) <= 0.001 and oid < best_id):
			best_d = d
			best_id = oid
			best = o
	return best

func _try_attack(s: ShipUnit, tgt: ShipUnit, now: float) -> void:
	if s.has_cyno_module():
		return
	if not s.is_logistic and not s.has_offensive_damage():
		return
	if now - s.last_attack_time < s.attack_duration:
		return
	if not s.attacks_enabled():
		return
	if not s.is_target_locked():
		return
	var dist_cells := s.grid_dist_to(tgt)
	if dist_cells > s.world_range_cells() + 0.001:
		return
	s.last_attack_time = now
	s.consume_cap_for_cycle()
	_do_attack(s, tgt, dist_cells)

func _do_attack(s: ShipUnit, tgt: ShipUnit, dist_cells: float) -> void:
	var fx_travel_s := -1.0
	var fx_speed_cells := -1.0
	if s.is_logistic:
		var amounts := s.heal_dict_scaled()
		var payload := {
			"source_id": s.get_instance_id(),
			"target_id": tgt.get_instance_id(),
			"source_race": s.race,
			"heal_shield": amounts.get("shield", 0.0),
			"heal_armor": amounts.get("armor", 0.0),
			"heal_structure": amounts.get("structure", 0.0),
		}
		AdminBus.request(&"combat.heal", payload)
	else:
		var raw := s.damage_dict_scaled()
		if s.is_missile_weapon():
			var factor := s.missile_damage_factor_vs(tgt)
			var scaled := {}
			for k in raw.keys():
				scaled[k] = float(raw[k]) * factor
			var spd := CombatFormulas.missile_speed_cells_per_s(s)
			fx_speed_cells = spd
			var muzzle := s.get_muzzle_global()
			_missile_queue.append({
				"pos": muzzle,
				"source_id": s.get_instance_id(),
				"target_id": tgt.get_instance_id(),
				"damage": scaled,
				"speed_cells_per_s": spd,
			})
		else:
			var p_hit := s.turret_hit_chance_vs(tgt, dist_cells)
			if _auth_randf("turret_hit") <= p_hit:
				var payload2 := {
					"source_id": s.get_instance_id(),
					"target_id": tgt.get_instance_id(),
					"damage": raw,
				}
				AdminBus.request(&"combat.hit", payload2)
	if _fx and _fx.has_method("play"):
		_fx.play(s, tgt, s.resolve_weapon_fx_kind(), s.attack_duration, fx_travel_s, fx_speed_cells)
	if s.has_method("advance_muzzle"):
		s.advance_muzzle()

func _tick_missiles(dt: float) -> void:
	## Independent chase: constant cells/s toward live target (no stretch/shrink with relative motion).
	var wu := CombatFormulas.world_units_per_cell()
	var hit_r := float(DataStore.combat.get("missile_hit_radius_wu", 0.45))
	var i := 0
	while i < _missile_queue.size():
		var m: Dictionary = _missile_queue[i]
		var tid := int(m.get("target_id", 0))
		var tgt := instance_from_id(tid) as ShipUnit
		if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
			_missile_queue.remove_at(i)
			continue
		var pos: Vector3 = m.get("pos", tgt.global_position)
		var dest := tgt.global_position + Vector3(0.0, 0.4, 0.0)
		var delta_p := dest - pos
		var dist := delta_p.length()
		var speed_wu := float(m.get("speed_cells_per_s", 1.5)) * wu
		var step := speed_wu * dt
		if dist <= maxf(hit_r, step) or dist < 0.001:
			AdminBus.request(&"combat.hit", {
				"source_id": int(m.get("source_id", 0)),
				"target_id": tid,
				"damage": m.get("damage", {}),
			})
			_missile_queue.remove_at(i)
			continue
		m["pos"] = pos + delta_p * (step / dist)
		_missile_queue[i] = m
		i += 1

func _apply_separation() -> void:
	## Elastic soft collision spheres sized from on-field model display.
	## Slight overlap allowed; spring push <1 so rear ships can squeeze past allies.
	_board.refresh_cross_team_cell_offsets(false)
	var allow := float(DataStore.combat.get("collision_allow_overlap_frac", 0.22))
	allow = clampf(allow, 0.0, 0.6)
	var elasticity := float(DataStore.combat.get("collision_elasticity", 0.42))
	elasticity = clampf(elasticity, 0.05, 1.0)
	var lateral_k := float(DataStore.combat.get("collision_same_team_lateral", 0.4))
	lateral_k = clampf(lateral_k, 0.0, 1.5)
	var ships: Array = []
	for s in _board.all_ships():
		if s.slot_type == "field" and not s.is_destroyed:
			ships.append(s)
	for i in range(ships.size()):
		var a: ShipUnit = ships[i]
		if a.hull_morph_unstacking:
			continue
		var ra := a.collision_radius_wu()
		for j in range(i + 1, ships.size()):
			var b: ShipUnit = ships[j]
			if b.hull_morph_unstacking:
				continue
			var rb := b.collision_radius_wu()
			var sum_r := ra + rb
			if sum_r < 0.001:
				continue
			## Only push when deeper than allowed slight clip.
			var soft_min := sum_r * (1.0 - allow)
			var delta: Vector3 = a.global_position - b.global_position
			delta.y = 0.0
			var d := delta.length()
			if d >= soft_min:
				continue
			var dir: Vector3
			if d < 0.001:
				var bias := -1.0 if a.get_instance_id() < b.get_instance_id() else 1.0
				dir = Vector3(bias, 0.0, 0.0)
			else:
				dir = delta.normalized()
			## Same-team: blend side slip so short-range rear ships are not walled in.
			if a.team_id == b.team_id and lateral_k > 0.001:
				var side := Vector3(-dir.z, 0.0, dir.x)
				if a.get_instance_id() > b.get_instance_id():
					side = -side
				dir = (dir + side * lateral_k).normalized()
			var penetration := soft_min - d
			var push_mag := penetration * elasticity * 0.5
			var push: Vector3 = dir * push_mag
			var pin_a := bool(a.immobile_in_combat) or a.has_cyno_module()
			var pin_b := bool(b.immobile_in_combat) or b.has_cyno_module()
			if pin_a and pin_b:
				continue
			elif pin_a:
				b.global_position -= push * 2.0
			elif pin_b:
				a.global_position += push * 2.0
			else:
				## Mass-ish: larger display yields a bit less (rear frigate slides around capital).
				var wa := maxf(ra, 0.05)
				var wb := maxf(rb, 0.05)
				var inv := 1.0 / (wa + wb)
				a.global_position += push * (wb * inv * 2.0)
				b.global_position -= push * (wa * inv * 2.0)
			a.global_position = BoardController.clamp_to_combat_play_area(a.global_position)
			b.global_position = BoardController.clamp_to_combat_play_area(b.global_position)
			a.global_position.y = 0.2
			b.global_position.y = 0.2

func _find_target(s: ShipUnit, exclude: ShipUnit = null) -> ShipUnit:
	## §6.3 ties: nearest (grid cells) → lowest HP fraction → lowest instance_id.
	## `exclude` skips one hull, used to pick the lead-lock runner-up (§13.1).
	if s.is_logistic:
		return _best_heal_ally(s)
	var _sd := DataStore.get_ship(s.ship_id)
	var tier := str(_sd.get("weapon_tier", "")).to_lower()
	var fx := str(s.resolve_weapon_fx_kind()).to_lower()
	var block_unmanned := tier in ["large", "capital"] and fx in ["laser", "rail", "cannon", "missile"]
	var enemy_team := ShipUnit.TEAM_AI if s.team_id == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
	var best2: ShipUnit = null
	var best_d2 := 99999.0
	var best_hp := 99999.0
	var best_id := 2147483647
	for o in _board.field_ships(enemy_team):
		if o.is_destroyed or o == exclude:
			continue
		if block_unmanned and o.is_unmanned:
			continue
		var d2 := s.grid_dist_to(o)
		var hp_frac := o.total_hp_fraction()
		var oid := o.get_instance_id()
		var better := false
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
	var tid := int(payload.get("target_id", 0))
	var target := instance_from_id(tid) as ShipUnit
	if target == null:
		return {"accepted": false}
	var dmg: Dictionary = payload.get("damage", {})
	if dmg.is_empty():
		var raw := float(payload.get("damage_emp", 0.0))
		dmg = {"emp": raw, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0}
	var res := target.apply_hit_dict(dmg)
	var dealt := float(res.get("dealt", 0.0))
	var src := instance_from_id(int(payload.get("source_id", 0))) as ShipUnit
	if src != null and src.unmanned_kind == "fighter":
		_fighter_shot_count += 1
		if dealt > 0.0:
			_fighter_dealt_total += dealt
			_fighter_hit_count += 1
	if dealt > 0.0 and _float_text:
		_float_text.spawn(target.global_position, "-%d" % int(round(dealt)), Color(1.0, 0.45, 0.35))
	return {"accepted": true, "destroyed": res.get("destroyed", false), "dealt": dealt}

func _on_heal(payload: Dictionary) -> Dictionary:
	var tid := int(payload.get("target_id", 0))
	var target := instance_from_id(tid) as ShipUnit
	if target == null:
		return {"accepted": false}
	if target.is_unmanned:
		return {"accepted": false, "reason_key": "unmanned"}
	var src := instance_from_id(int(payload.get("source_id", 0))) as ShipUnit
	var race := str(payload.get("source_race", src.race if src else "amarr"))
	var amounts := {
		"shield": float(payload.get("heal_shield", payload.get("heal", 0.0))),
		"armor": float(payload.get("heal_armor", 0.0)),
		"structure": float(payload.get("heal_structure", 0.0)),
	}
	var res := target.apply_heal_racial(race, amounts)
	var healed := float(res.get("applied", 0.0))
	var full := bool(res.get("full", false))
	if healed > 0.0 and _float_text:
		_float_text.spawn(target.global_position, "+%d" % int(round(healed)), Color(0.35, 0.95, 0.55))
	if full and src:
		src.combat_target = null
	return {"accepted": true, "full": full}

func _spawn_combat_drones() -> void:
	var carriers: Array = []
	for s in _board.all_ships():
		if s.slot_type != "field" or s.is_destroyed or s.is_unmanned:
			continue
		## Capitals use fighter / heavy-repair spawn path instead of race light drones.
		if str(s.capital_role) in ["carrier", "force_auxiliary", "dreadnought"]:
			continue
		var policy := _drone_spawn_policy_for_ship(s)
		if int(policy.get("count", 0)) <= 0:
			continue
		carriers.append(s)
	for s in carriers:
		var policy := _drone_spawn_policy_for_ship(s)
		var n := mini(DRONE_CAP, int(policy.get("count", 0)))
		if n <= 0:
			continue
		var drone_id := int(policy.get("drone_id", 0))
		if drone_id <= 0:
			continue
		for i in range(n):
			var drone := _board.spawn_unmanned(drone_id, s.team_id, s.global_position + Vector3(_viz_randf_range(-1.2, 1.2), 0.2, _viz_randf_range(-1.2, 1.2)), s)
			_ensure_drone_trail(drone)
			var did := drone.get_instance_id()
			_drone_orbit_phase[did] = _viz_randf() * TAU
			_drone_orbit_dir[did] = 1.0 if _auth_randf("orbit_dir") < 0.5 else -1.0
	## Fresh hulls need the team's live SelfAll fetter pass (ArmorHP / Speed / titan …).
	_board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	_board.recalculate_fetters(ShipUnit.TEAM_AI)


func _drone_spawn_policy_for_ship(s: ShipUnit) -> Dictionary:
	var race := str(s.race).to_lower()
	var ship_data := DataStore.get_ship(s.ship_id)
	var group := str(ship_data.get("ship_group", "")).to_lower()
	var sid := int(s.ship_id)
	## Rorqual / industrial: explicit mining Excavator template (not race light drones).
	var mining_drone_id := int(ship_data.get("mining_drone_id", 0))
	if mining_drone_id > 0:
		var mcount := int(ship_data.get("drone_bay_slots", ship_data.get("drone_count_cap", 0)))
		if mcount <= 0:
			mcount = int(ship_data.get("mining_drone_count", 4))
		return {"count": mcount, "drone_id": mining_drone_id}
	if DRONE_COUNT_EXCEPTIONS.has(sid):
		var cnt := int(DRONE_COUNT_EXCEPTIONS[sid])
		if group == "battlecruiser":
			return {"count": cnt, "drone_id": int(RACE_DRONE_MEDIUM.get(race, 1005))}
		if group == "battleship":
			return {"count": cnt, "drone_id": int(RACE_DRONE_HEAVY.get(race, 1011))}
	if group == "battlecruiser":
		return {"count": 1, "drone_id": int(RACE_DRONE_MEDIUM.get(race, 1005))}
	if group == "battleship":
		return {"count": 2, "drone_id": int(RACE_DRONE_HEAVY.get(race, 1011))}
	var slots := int(s.get("drone_bay_slots"))
	if slots <= 0 and s.drone_bandwidth > 0.0:
		slots = int(floor(s.drone_bandwidth / DRONE_BW_COST))
	if slots <= 0:
		return {"count": 0, "drone_id": 0}
	return {"count": slots, "drone_id": int(RACE_DRONE_LIGHT.get(race, 1001))}


func _spawn_capital_auxiliaries() -> void:
	for s in _board.all_ships():
		if s.slot_type != "field" or s.is_destroyed or s.is_unmanned:
			continue
		_spawn_auxiliaries_for_ship(s)


func _count_children_of(mother: ShipUnit) -> int:
	var n := 0
	var mid := mother.get_instance_id()
	for s in _board.all_ships():
		if s.is_unmanned and not s.is_destroyed and s.mother_ship_id == mid:
			n += 1
	return n


func _spawn_auxiliaries_for_ship(s: ShipUnit) -> void:
	var data: Dictionary = DataStore.get_ship(s.ship_id)
	if s.capital_role == "carrier" or int(data.get("fighter_unit_id", 0)) > 0:
		_ensure_carrier_fighter_squadrons(s, data)
		return
	if s.capital_role == "force_auxiliary" or int(data.get("heavy_repair_drone_id", 0)) > 0:
		var drone_id := int(data.get("heavy_repair_drone_id", 0))
		if drone_id <= 0:
			return
		var need2 := int(data.get("heavy_repair_drone_count", 4))
		var have2 := _count_children_of(s)
		for j in range(have2, need2):
			var ang2 := float(j) * TAU / float(maxi(1, need2))
			var offset2 := Vector3(cos(ang2) * 1.6, 0.25, sin(ang2) * 1.6)
			## Repair drones always ★1 heal (reload_stats ignores star for repair).
			var d := _board.spawn_unmanned(drone_id, s.team_id, s.global_position + offset2, s, 1)
			_ensure_drone_trail(d)
			var did2 := d.get_instance_id()
			_drone_orbit_phase[did2] = ang2
			_drone_orbit_dir[did2] = 1.0 if _auth_randf("orbit_dir") < 0.5 else -1.0
		_board.recalculate_fetters(s.team_id)


func _ensure_carrier_fighter_squadrons(s: ShipUnit, data: Dictionary) -> void:
	## Max `fighter_squadrons` active at once; lifetime pool `fighter_squadron_pool`.
	## When a whole squadron is wiped, launch another while pool remains.
	var fighter_id := int(data.get("fighter_unit_id", 0))
	if fighter_id <= 0:
		return
	var active_max := int(data.get("fighter_squadrons", 3))
	var tubes := int(data.get("fighter_tubes_per_squadron", 3))
	var pool_cap := int(data.get("fighter_squadron_pool", 10))
	active_max = maxi(1, active_max)
	tubes = maxi(1, tubes)
	pool_cap = maxi(active_max, pool_cap)
	if s.fighter_squadron_pool_left < 0:
		s.fighter_squadron_pool_left = pool_cap
	var mid := s.get_instance_id()
	var living_by_sq: Dictionary = {}
	for u in _board.all_ships():
		if not u.is_unmanned or u.is_destroyed:
			continue
		if u.mother_ship_id != mid or u.unmanned_kind != "fighter":
			continue
		var sq := int(u.fighter_squadron_id)
		living_by_sq[sq] = int(living_by_sq.get(sq, 0)) + 1
	var active_count := 0
	for sq2 in living_by_sq.keys():
		if int(living_by_sq[sq2]) > 0:
			active_count += 1
	while active_count < active_max and s.fighter_squadron_pool_left > 0:
		var sq_id := s.fighter_next_squadron_id
		s.fighter_next_squadron_id += 1
		s.fighter_squadron_pool_left -= 1
		for i in range(tubes):
			var ang := float(active_count * tubes + i) * TAU / float(active_max * tubes)
			var offset := Vector3(cos(ang) * 1.4, 0.25, sin(ang) * 1.4)
			var f := _board.spawn_unmanned(
				fighter_id, s.team_id, s.global_position + offset, s, s.star, sq_id
			)
			_ensure_drone_trail(f)
			var fid := f.get_instance_id()
			_drone_orbit_phase[fid] = ang
			_drone_orbit_dir[fid] = 1.0 if _auth_randf("orbit_dir") < 0.5 else -1.0
		active_count += 1
	_board.recalculate_fetters(s.team_id)


func _clear_drones() -> void:
	var doomed: Array = []
	for ship in _board.all_ships():
		if ship.is_unmanned:
			doomed.append(ship)
	for ship2 in doomed:
		_board.remove_ship_node(ship2)
	_drone_orbit_phase.clear()
	_drone_orbit_dir.clear()
	_drone_orbit_last_xz.clear()
	_drone_orbit_stuck_s.clear()
	_mining_wander_anchor.clear()
	_mining_wander_cd.clear()
	_mining_fx_cd.clear()
	_mining_fx_last_anchor_id.clear()

func _cull_orphan_drones() -> void:
	## Mother destroyed / missing → recycle combat drones immediately.
	var doomed: Array = []
	for s in _board.all_ships():
		if not s.is_unmanned or s.is_destroyed:
			continue
		if s.mother_ship_id == 0:
			continue
		var mother := instance_from_id(s.mother_ship_id) as ShipUnit
		if mother == null or not is_instance_valid(mother) or mother.is_destroyed:
			doomed.append(s)
	for s in doomed:
		var ship := s as ShipUnit
		if ship == null:
			continue
		var iid: int = ship.get_instance_id()
		_drone_orbit_phase.erase(iid)
		_drone_orbit_dir.erase(iid)
		_drone_orbit_last_xz.erase(iid)
		_drone_orbit_stuck_s.erase(iid)
		_mining_wander_anchor.erase(iid)
		_mining_wander_cd.erase(iid)
		_mining_fx_cd.erase(iid)
		_mining_fx_last_anchor_id.erase(iid)
		_board.remove_ship_node(ship)

func _orbit_drone(s: ShipUnit, tgt: ShipUnit, delta: float) -> void:
	## Fighters: orbit at star.optimal cells (EVE squadron orbit ≈ 10 km → 5 cells).
	## Other combat drones stay visually tight (cap 1.6 wu) — high tracking still hits.
	var radius: float
	if s.unmanned_kind == "fighter":
		var orbit_cells := maxf(s.optimal_cells, 2.0)
		radius = orbit_cells * CombatFormulas.world_units_per_cell()
	else:
		radius = maxf(0.9, minf(s.world_range_wu() * 0.8, 1.6))
	_orbit_around_xz(s, tgt.global_position, delta, radius, true)


func _wander_mining_drone(s: ShipUnit, delta: float) -> void:
	## Excavators orbit a random central MiningAnchor; periodically re-pick (MINING §2.1).
	var id := s.get_instance_id()
	var belt := _find_asteroid_belt()
	if belt == null or belt.mining_anchors.is_empty():
		EngineBoosterTrail.set_emitting_on(s, false)
		return
	var cd := float(_mining_wander_cd.get(id, 0.0)) - delta
	var anchor: Node3D = _mining_wander_anchor.get(id) as Node3D
	var need_pick := anchor == null or not is_instance_valid(anchor) or cd <= 0.0
	if need_pick:
		var pick_i := _auth_randi_range("mining_pick", 0, belt.mining_anchors.size() - 1)
		anchor = belt.mining_anchors[pick_i] as Node3D
		_mining_wander_anchor[id] = anchor
		var cd_min := float(DataStore.visual.get("mining_drone_wander_cd_min_s", 4.0))
		var cd_max := float(DataStore.visual.get("mining_drone_wander_cd_max_s", 12.0))
		_mining_wander_cd[id] = _auth_randf_range("mining_wander", maxf(1.0, cd_min), maxf(cd_min + 0.1, cd_max))
	else:
		_mining_wander_cd[id] = cd
	if anchor == null or not is_instance_valid(anchor):
		EngineBoosterTrail.set_emitting_on(s, false)
		return
	var radius := float(DataStore.visual.get("mining_drone_orbit_radius_wu", 1.35))
	radius = maxf(0.75, radius)
	_orbit_around_xz(s, anchor.global_position, delta, radius, true)
	EngineBoosterTrail.set_emitting_on(s, true)


func _orbit_around_xz(s: ShipUnit, center: Vector3, delta: float, radius: float, face_center: bool) -> void:
	var id := s.get_instance_id()
	var phase := float(_drone_orbit_phase.get(id, 0.0))
	var orbit_dir := float(_drone_orbit_dir.get(id, 0.0))
	if absf(orbit_dir) < 0.5:
		orbit_dir = 1.0 if _auth_randf("orbit_dir") < 0.5 else -1.0
		_drone_orbit_dir[id] = orbit_dir
	var flat_self := Vector3(s.global_position.x, 0.0, s.global_position.z)
	## Net world motion since last orbit tick (includes post-separation pushback).
	var stuck_eps := float(DataStore.combat.get("unmanned_orbit_stuck_eps_wu", 0.06))
	var stuck_limit := float(DataStore.combat.get("unmanned_orbit_stuck_reverse_s", 2.0))
	var stuck_s := float(_drone_orbit_stuck_s.get(id, 0.0))
	if _drone_orbit_last_xz.has(id):
		var last_xz: Vector3 = _drone_orbit_last_xz[id]
		if flat_self.distance_to(last_xz) < stuck_eps:
			stuck_s += delta
		else:
			stuck_s = 0.0
		if stuck_s >= stuck_limit:
			orbit_dir = -orbit_dir
			_drone_orbit_dir[id] = orbit_dir
			stuck_s = 0.0
	_drone_orbit_stuck_s[id] = stuck_s
	_drone_orbit_last_xz[id] = flat_self
	var flat_center := Vector3(center.x, 0.0, center.z)
	var to_center := flat_center - flat_self
	var dist := to_center.length()
	var enter_band := radius * 0.35
	var step := s.combat_move_speed() * delta
	var move: Vector3
	if dist > radius + enter_band:
		move = to_center.normalized()
	else:
		phase += delta * 0.9 * orbit_dir
		_drone_orbit_phase[id] = phase
		var away: Vector3 = flat_self - flat_center
		if away.length_squared() < 0.0001:
			away = Vector3(cos(phase), 0.0, sin(phase))
		else:
			away = away.normalized()
		## CCW when orbit_dir > 0; CW when < 0.
		var tangent := Vector3(-away.z, 0.0, away.x) * orbit_dir
		var radial_error := dist - radius
		move = tangent + away * clampf(-radial_error * 1.4, -0.65, 0.65)
		move = move.normalized()
	var moving := move.length_squared() > 0.0001
	if moving:
		s.face_dir_xz(move)
		s.global_position += move * step
	s.global_position = BoardController.clamp_to_combat_play_area(s.global_position)
	s.global_position.y = 0.35
	if face_center:
		var aim: Vector3 = flat_center - Vector3(s.global_position.x, 0.0, s.global_position.z)
		if aim.length_squared() > 0.0001:
			s.face_dir_xz(aim)
	## Orbit path must keep trails on (mining already did; combat drones/fighters used to miss this).
	_attach_trail_once(s)
	EngineBoosterTrail.set_emitting_on(s, moving)


func _tick_mining_fx(s: ShipUnit, delta: float) -> void:
	if s == null or s.is_destroyed or s.slot_type != "field":
		return
	var wfx := ""
	if s.has_method("resolve_weapon_fx_kind"):
		wfx = str(s.resolve_weapon_fx_kind())
	var is_excavator := str(s.unmanned_kind) == "mining_excavator"
	if wfx != "mining" and not is_excavator:
		return
	var sid := s.get_instance_id()
	var left := float(_mining_fx_cd.get(sid, 0.0))
	left -= delta
	if left > 0.0:
		_mining_fx_cd[sid] = left
		return
	var belt := _find_asteroid_belt()
	if belt == null or belt.mining_anchors.is_empty():
		_mining_fx_cd[sid] = 1.0
		return
	## Every shot: fresh uniform random MiningAnchor (MINING §2.3). Never reuse wander lock.
	var anchor := _pick_random_mining_anchor(belt, sid)
	if anchor == null or not is_instance_valid(anchor):
		_mining_fx_cd[sid] = 1.0
		return
	_mining_fx_last_anchor_id[sid] = anchor.get_instance_id()
	if _fx and _fx.has_method("play_to_anchor"):
		_fx.play_to_anchor(s, anchor, "mining", 0.9)
	if s.has_method("advance_muzzle"):
		s.advance_muzzle()
	var cd_max := float(DataStore.visual.get("mining_fx_cd_max_s", 10.0))
	_mining_fx_cd[sid] = _viz_randf_range(0.05, maxf(0.1, cd_max))


func _pick_random_mining_anchor(belt: AsteroidBelt, firer_id: int) -> Node3D:
	var anchors: Array = belt.mining_anchors
	var n := anchors.size()
	if n <= 0:
		return null
	var idx := _auth_randi_range("mining_pick", 0, n - 1)
	var pick := _anchor_at(anchors, idx)
	if n == 1:
		return pick
	## Prefer a different rock than the previous shot so consecutive beams visibly retarget.
	var last_id := int(_mining_fx_last_anchor_id.get(firer_id, 0))
	if pick == null or (last_id != 0 and pick.get_instance_id() == last_id):
		idx = (idx + 1 + _auth_randi_range("mining_pick", 0, n - 2)) % n
		pick = _anchor_at(anchors, idx)
	return pick


## Belt rocks can be freed mid-battle; a stale slot must not be cast blindly.
func _anchor_at(anchors: Array, idx: int) -> Node3D:
	var v: Variant = anchors[idx]
	if typeof(v) != TYPE_OBJECT or not is_instance_valid(v):
		return null
	return v as Node3D


func _find_asteroid_belt() -> AsteroidBelt:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("asteroid_belt")
	for n in nodes:
		if n is AsteroidBelt:
			return n as AsteroidBelt
	# Fallback: search under board parent MapEnv
	if _board:
		var p: Node = _board.get_parent()
		if p:
			var found := p.find_child("AsteroidBelt", true, false)
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
	var list: Array = []
	for s in _board.all_ships():
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
	var min_d := float(DataStore.combat.get("hull_morph_unstack_min_dist_wu", 1.4))
	var push_wu := float(DataStore.combat.get("hull_morph_unstack_wu", 0.85))
	var dur := float(DataStore.combat.get("hull_morph_unstack_s", 0.8))
	dur = maxf(0.05, dur)
	## Accumulate lateral push per ship from all close neighbors (any field ship).
	var targets: Dictionary = {}  # instance_id -> Vector3 goal
	for s in ships:
		var ship: ShipUnit = s as ShipUnit
		if ship == null:
			continue
		targets[ship.get_instance_id()] = ship.global_position
	for i in range(ships.size()):
		var a: ShipUnit = ships[i] as ShipUnit
		if a == null:
			continue
		for j in range(i + 1, ships.size()):
			var b: ShipUnit = ships[j] as ShipUnit
			if b == null:
				continue
			var delta: Vector3 = a.global_position - b.global_position
			delta.y = 0.0
			var d := delta.length()
			if d >= min_d:
				continue
			var dir: Vector3
			if d < 0.001:
				## Stable left/right by instance id.
				var bias := -1.0 if a.get_instance_id() < b.get_instance_id() else 1.0
				dir = Vector3(bias, 0.0, 0.0)
			else:
				dir = delta.normalized()
			var half := push_wu * 0.5
			## Extra separation when almost overlapping.
			if d < min_d * 0.5:
				half = push_wu
			var aid := a.get_instance_id()
			var bid := b.get_instance_id()
			targets[aid] = (targets[aid] as Vector3) + dir * half
			targets[bid] = (targets[bid] as Vector3) - dir * half
	## Also push away from non-morph field ships that are clipping.
	var morph_ids: Dictionary = {}
	for s0 in ships:
		var sh0: ShipUnit = s0 as ShipUnit
		if sh0:
			morph_ids[sh0.get_instance_id()] = true
	for s2 in ships:
		var ship2: ShipUnit = s2 as ShipUnit
		if ship2 == null:
			continue
		for o in _board.all_ships():
			if o == null or o == ship2 or o.is_destroyed or o.slot_type != "field":
				continue
			if morph_ids.has(o.get_instance_id()):
				continue
			var dlt: Vector3 = ship2.global_position - o.global_position
			dlt.y = 0.0
			var od := dlt.length()
			if od >= min_d:
				continue
			if od < 0.001:
				dlt = Vector3(-1.0 if ship2.get_instance_id() < o.get_instance_id() else 1.0, 0.0, 0.0)
			var push_dir := dlt.normalized()
			var iid2 := ship2.get_instance_id()
			targets[iid2] = (targets[iid2] as Vector3) + push_dir * (push_wu * 0.5)
	for s3 in ships:
		var ship3: ShipUnit = s3 as ShipUnit
		if ship3 == null:
			continue
		var from_p := ship3.global_position
		var to_p: Vector3 = targets.get(ship3.get_instance_id(), from_p)
		to_p.y = 0.2
		to_p = BoardController.clamp_to_combat_play_area(to_p)
		var need_move := from_p.distance_to(to_p) > 0.05
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
	var mul := 1.0
	var root := get_tree().get_first_node_in_group("match_root") if get_tree() else null
	if root and root.get("match_ctrl"):
		mul = float(root.match_ctrl.speed_multiplier)
	var left: Array = []
	for entry in _morph_unstack:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var ship: ShipUnit = entry.get("ship") as ShipUnit
		if ship == null or not is_instance_valid(ship) or ship.is_destroyed:
			continue
		var dur := maxf(0.05, float(entry.get("dur", 0.8)))
		var t := float(entry.get("t", 0.0)) + delta * mul
		entry["t"] = t
		var u := clampf(t / dur, 0.0, 1.0)
		## Smoothstep slide.
		var s := u * u * (3.0 - 2.0 * u)
		var from_p: Vector3 = entry.get("from", ship.global_position)
		var to_p: Vector3 = entry.get("to", ship.global_position)
		ship.global_position = from_p.lerp(to_p, s)
		ship.global_position.y = 0.2
		EngineBoosterTrail.set_emitting_on(ship, u < 0.98 and from_p.distance_to(to_p) > 0.05)
		if u < 1.0:
			left.append(entry)
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
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	## Default match camera already sits ~45 wu out, so the old 30/100 cut every drone trail.
	## Thresholds must clear the standard rig and only bite on zoom-out (COMBAT §14C).
	var trail_wu := float(DataStore.visual.get("unmanned_trail_lod_wu", 90.0))
	var hide_wu := float(DataStore.visual.get("unmanned_hide_lod_wu", 200.0))
	for s in _board.all_ships():
		if not s.is_unmanned:
			continue
		var d := cam.global_position.distance_to(s.global_position)
		## Far: hide trail. Near: do not force-on here — orbit / mining / move paths own emit.
		if d > trail_wu:
			EngineBoosterTrail.set_emitting_on(s, false)
		s.visible = d <= hide_wu and not s.is_destroyed

func _spawn_isolation_debris() -> void:
	var cmin := int(DataStore.combat.get("isolation_debris_count_min", 3))
	var cmax := int(DataStore.combat.get("isolation_debris_count_max", 5))
	var n := clampi(cmin + _auth_randi_range("isolation_debris", 0, maxi(0, cmax - cmin)), cmin, cmax)
	var half := float(DataStore.combat.get("isolation_half_width_wu", 2.5))
	for i in range(n):
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = _viz_randf_range(0.35, 0.7)
		sphere.height = sphere.radius * 2.0
		mi.mesh = sphere
		var mat := StandardMaterial3D.new()
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
	for d in _debris:
		var n: Node = d.get("node")
		if n and is_instance_valid(n):
			n.queue_free()
	_debris.clear()

func _tick_debris_contacts(delta: float) -> void:
	var dmg_lo := float(DataStore.combat.get("isolation_debris_damage_min", 5))
	var dmg_hi := float(DataStore.combat.get("isolation_debris_damage_max", 10))
	for d in _debris:
		var node: Node3D = d.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var cds: Dictionary = d.get("hit_cd", {})
		for s in _board.all_ships():
			if s.slot_type != "field" or s.is_destroyed:
				continue
			var sid := s.get_instance_id()
			cds[sid] = maxf(0.0, float(cds.get(sid, 0.0)) - delta)
			if cds[sid] > 0.0:
				continue
			if s.global_position.distance_to(node.global_position) > 1.4:
				continue
			var dealt := _auth_randf_range("isolation_debris_dmg", dmg_lo, dmg_hi)
			s.apply_hit_dict({"emp": 0.0, "thermal": 0.0, "kinetic": 0.0, "explosive": dealt})
			cds[sid] = 1.25
			if _float_text:
				_float_text.spawn(s.global_position, "-%d" % int(dealt), Color(0.8, 0.7, 0.4))
		d["hit_cd"] = cds
