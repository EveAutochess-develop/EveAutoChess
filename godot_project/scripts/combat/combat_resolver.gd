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
## Per-combat fighter damage accounting (for session DPS audit).
var _fighter_dealt_total: float = 0.0
var _fighter_hit_count: int = 0
var _fighter_shot_count: int = 0

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

func start_combat() -> void:
	_active = true
	_combat_sim_time = 0.0
	_retarget_acc = 0.0
	_missile_queue.clear()
	_drone_orbit_phase.clear()
	_fighter_dealt_total = 0.0
	_fighter_hit_count = 0
	_fighter_shot_count = 0
	_clear_debris()
	_spawn_isolation_debris()
	for s in _board.all_ships():
		if s.slot_type == "field" and not s.is_destroyed:
			s.set_combat_tint(true)
			s.reset_combat_runtime()
	_spawn_combat_drones()
	_spawn_capital_auxiliaries()

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
		var trail := s.get_node_or_null("EngineTrail") as CPUParticles3D
		if trail:
			trail.emitting = false
	if _fx and _fx.has_method("clear_all"):
		_fx.clear_all()

func tick(delta: float) -> void:
	if not _active:
		return
	_combat_sim_time += delta
	var now := _combat_sim_time
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
		_update_targeting(s, delta, periodic_retarget)
		var tgt_any = s.combat_target
		if tgt_any == null or not is_instance_valid(tgt_any):
			s.combat_target = null
			continue
		var tgt := tgt_any as ShipUnit
		if tgt == null:
			s.combat_target = null
			continue
		if tgt.is_destroyed:
			s.combat_target = null
			continue
		s.sync_lock(tgt, now)
		s.advance_lock(delta)
		## Covert cyno / pinned: stay put, do not yaw toward targets (no in-place spin).
		if s.has_cyno_module() or s.immobile_in_combat:
			continue
		if s.is_unmanned and s.unmanned_kind.find("sentry") < 0:
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
	var ship_trail: CPUParticles3D = null
	if not s.is_unmanned:
		ship_trail = _ensure_ship_trail(s)
	if step_len > deadband:
		dir /= step_len
		s.face_dir_xz(dir)
		s.global_position += dir * minf(speed * delta, step_len)
		if ship_trail:
			ship_trail.emitting = true
	else:
		var aim: Vector3 = tgt.global_position - s.global_position
		aim.y = 0.0
		s.face_dir_xz(aim)
		if ship_trail:
			ship_trail.emitting = false
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
			if randf() <= p_hit:
				var payload2 := {
					"source_id": s.get_instance_id(),
					"target_id": tgt.get_instance_id(),
					"damage": raw,
				}
				AdminBus.request(&"combat.hit", payload2)
	if _fx and _fx.has_method("play"):
		_fx.play(s, tgt, s.resolve_weapon_fx_kind(), s.attack_duration, fx_travel_s, fx_speed_cells)

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
	var radius := float(DataStore.combat.get("agent_radius", 0.5))
	var min_d := radius * 2.0
	var ships: Array = []
	for s in _board.all_ships():
		if s.slot_type == "field" and not s.is_destroyed:
			ships.append(s)
	for i in range(ships.size()):
		var a: ShipUnit = ships[i]
		for j in range(i + 1, ships.size()):
			var b: ShipUnit = ships[j]
			var delta: Vector3 = a.global_position - b.global_position
			delta.y = 0.0
			var d := delta.length()
			if d >= min_d:
				continue
			var push: Vector3
			if d < 0.001:
				var bias := 1.0 if a.get_instance_id() < b.get_instance_id() else -1.0
				push = Vector3(bias, 0.0, 0.0) * (min_d * 0.5)
			else:
				push = delta.normalized() * ((min_d - d) * 0.5)
			var pin_a := bool(a.immobile_in_combat) or a.has_cyno_module()
			var pin_b := bool(b.immobile_in_combat) or b.has_cyno_module()
			if pin_a and pin_b:
				continue
			elif pin_a:
				b.global_position -= push * 2.0
			elif pin_b:
				a.global_position += push * 2.0
			else:
				a.global_position += push
				b.global_position -= push
			a.global_position = BoardController.clamp_to_combat_play_area(a.global_position)
			b.global_position = BoardController.clamp_to_combat_play_area(b.global_position)
			a.global_position.y = 0.2
			b.global_position.y = 0.2

func _find_target(s: ShipUnit) -> ShipUnit:
	## §6.3 ties: nearest (grid cells) → lowest HP fraction → lowest instance_id.
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
		if o.is_destroyed:
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
	var full := target.apply_heal_racial(race, amounts)
	var healed := float(amounts.get("shield", 0.0)) + float(amounts.get("armor", 0.0)) + float(amounts.get("structure", 0.0))
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
			var drone := _board.spawn_unmanned(drone_id, s.team_id, s.global_position + Vector3(randf_range(-1.2, 1.2), 0.2, randf_range(-1.2, 1.2)), s)
			_ensure_drone_trail(drone)
			_drone_orbit_phase[drone.get_instance_id()] = randf() * TAU


func _drone_spawn_policy_for_ship(s: ShipUnit) -> Dictionary:
	var race := str(s.race).to_lower()
	var ship_data := DataStore.get_ship(s.ship_id)
	var group := str(ship_data.get("ship_group", "")).to_lower()
	var sid := int(s.ship_id)
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
			_drone_orbit_phase[d.get_instance_id()] = ang2


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
			_drone_orbit_phase[f.get_instance_id()] = ang
		active_count += 1

func _clear_drones() -> void:
	var doomed: Array = []
	for s in _board.all_ships():
		if s.is_unmanned:
			doomed.append(s)
	for s in doomed:
		_board.remove_ship_node(s)
	_drone_orbit_phase.clear()

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
		_drone_orbit_phase.erase(s.get_instance_id())
		_board.remove_ship_node(s)

func _orbit_drone(s: ShipUnit, tgt: ShipUnit, delta: float) -> void:
	var id := s.get_instance_id()
	var phase := float(_drone_orbit_phase.get(id, 0.0))
	var center := tgt.global_position
	var flat_self := Vector3(s.global_position.x, 0.0, s.global_position.z)
	var flat_center := Vector3(center.x, 0.0, center.z)
	var to_center := flat_center - flat_self
	var dist := to_center.length()
	## Fighters: orbit at star.optimal cells (EVE squadron orbit ≈ 10 km → 5 cells).
	## Other drones stay visually tight (cap 1.6 wu) — high tracking still hits.
	var radius: float
	if s.unmanned_kind == "fighter":
		var orbit_cells := maxf(s.optimal_cells, 2.0)
		radius = orbit_cells * CombatFormulas.world_units_per_cell()
	else:
		radius = maxf(0.9, minf(s.world_range_wu() * 0.8, 1.6))
	var enter_band := radius * 0.35
	var step := s.combat_move_speed() * delta
	var move: Vector3
	if dist > radius + enter_band:
		move = to_center.normalized()
	else:
		phase += delta * 0.9
		_drone_orbit_phase[id] = phase
		var away: Vector3 = flat_self - flat_center
		if away.length_squared() < 0.0001:
			away = Vector3(cos(phase), 0.0, sin(phase))
		else:
			away = away.normalized()
		var tangent := Vector3(-away.z, 0.0, away.x)
		var radial_error := dist - radius
		move = tangent + away * clampf(-radial_error * 1.4, -0.65, 0.65)
		move = move.normalized()
	if move.length_squared() > 0.0001:
		s.face_dir_xz(move)
		s.global_position += move * step
	s.global_position = BoardController.clamp_to_combat_play_area(s.global_position)
	s.global_position.y = 0.35
	var aim: Vector3 = tgt.global_position - s.global_position
	aim.y = 0.0
	if aim.length_squared() > 0.0001:
		s.face_dir_xz(aim)

func _ensure_drone_trail(drone: ShipUnit) -> void:
	if drone.has_node("EngineTrail"):
		return
	var particles := CPUParticles3D.new()
	particles.name = "EngineTrail"
	particles.amount = 24
	particles.lifetime = 0.45
	particles.emitting = true
	particles.direction = Vector3(0, 0, 1)
	particles.spread = 12.0
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 1.2
	particles.gravity = Vector3.ZERO
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.7, 1.0) if drone.team_id == ShipUnit.TEAM_PLAYER else Color(1.0, 0.35, 0.3)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 1.2
	particles.mesh = SphereMesh.new()
	(particles.mesh as SphereMesh).radius = 0.05
	(particles.mesh as SphereMesh).height = 0.1
	particles.material_override = mat
	drone.add_child(particles)

func _ensure_ship_trail(ship: ShipUnit) -> CPUParticles3D:
	var existing := ship.get_node_or_null("EngineTrail") as CPUParticles3D
	if existing:
		return existing
	var particles := CPUParticles3D.new()
	particles.name = "EngineTrail"
	particles.local_coords = true
	particles.amount = 26
	particles.lifetime = 0.5
	particles.emitting = false
	particles.direction = Vector3(0, 0, 1)
	particles.spread = 9.0
	particles.initial_velocity_min = 0.55
	particles.initial_velocity_max = 1.25
	particles.gravity = Vector3.ZERO
	var local_muzzle := ship.to_local(ship.get_muzzle_global())
	particles.position = Vector3(-local_muzzle.x, maxf(0.1, local_muzzle.y * 0.4), -local_muzzle.z * 0.82)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.7, 1.0) if ship.team_id == ShipUnit.TEAM_PLAYER else Color(1.0, 0.35, 0.3)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 1.15
	particles.mesh = SphereMesh.new()
	(particles.mesh as SphereMesh).radius = 0.06
	(particles.mesh as SphereMesh).height = 0.12
	particles.material_override = mat
	ship.add_child(particles)
	return particles

func _apply_drone_lod() -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	for s in _board.all_ships():
		if not s.is_unmanned:
			continue
		var d := cam.global_position.distance_to(s.global_position)
		var trail := s.get_node_or_null("EngineTrail") as CPUParticles3D
		if trail:
			trail.emitting = d <= 30.0
		s.visible = d <= 100.0 and not s.is_destroyed

func _spawn_isolation_debris() -> void:
	var cmin := int(DataStore.combat.get("isolation_debris_count_min", 3))
	var cmax := int(DataStore.combat.get("isolation_debris_count_max", 5))
	var n := clampi(cmin + randi() % maxi(1, cmax - cmin + 1), cmin, cmax)
	var half := float(DataStore.combat.get("isolation_half_width_wu", 2.5))
	for i in range(n):
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = randf_range(0.35, 0.7)
		sphere.height = sphere.radius * 2.0
		mi.mesh = sphere
		var mat := StandardMaterial3D.new()
		## Unshaded so fill lights don't wash debris into white spheres.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.18, 0.16, 0.14, 1.0)
		mat.roughness = 0.95
		mi.material_override = mat
		mi.position = Vector3(randf_range(-10.0, 10.0), sphere.radius, randf_range(-half * 0.8, half * 0.8))
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
			var dealt := randf_range(dmg_lo, dmg_hi)
			s.apply_hit_dict({"emp": 0.0, "thermal": 0.0, "kinetic": 0.0, "explosive": dealt})
			cds[sid] = 1.25
			if _float_text:
				_float_text.spawn(s.global_position, "-%d" % int(dealt), Color(0.8, 0.7, 0.4))
		d["hit_cd"] = cds
