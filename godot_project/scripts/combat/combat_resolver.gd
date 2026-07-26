extends Node
class_name CombatResolver
## Targeting / range aligned with Unity ShipController:
## R = AttackRange * weaponRangeScale(3); approach stop = 0.9R toward target.
## Unity uses NavMeshAgent (speed 3.5, radius 0.5, HighQuality avoidance).
## Godot: move to approach point + soft separation (no NavMesh).

var _board: BoardController
var _active: bool = false
var _retarget_acc: float = 0.0
var _fx = null  # FiringFx

func bind(board: BoardController, fx = null) -> void:
	_board = board
	_fx = fx
	AdminBus.register_handler(&"combat.hit", _on_hit)
	AdminBus.register_handler(&"combat.heal", _on_heal)

func start_combat() -> void:
	_active = true
	for s in _board.all_ships():
		if s.slot_type == "field" and not s.is_destroyed:
			s.set_combat_tint(true)
			s.combat_target = null

func stop_combat() -> void:
	_active = false
	for s in _board.all_ships():
		s.set_combat_tint(false)
		s.combat_target = null
	if _fx and _fx.has_method("clear_all"):
		_fx.clear_all()

func tick(delta: float) -> void:
	if not _active:
		return
	_retarget_acc += delta
	var retarget := _retarget_acc >= float(DataStore.combat.get("retarget_interval_s", 0.5))
	if retarget:
		_retarget_acc = 0.0
	var now := Time.get_ticks_msec() / 1000.0
	var speed := float(DataStore.combat.get("move_speed", 3.5))
	var approach_f := float(DataStore.combat.get("approach_factor", 0.9))
	for s in _board.all_ships():
		if s.is_destroyed or s.slot_type != "field":
			continue
		if s.combat_target == null or s.combat_target.is_destroyed or retarget:
			s.combat_target = _find_target(s)
		if s.combat_target == null:
			continue
		var tgt: ShipUnit = s.combat_target
		var dist := s.global_position.distance_to(tgt.global_position)
		var R := s.world_range()
		var approach := R * approach_f
		# Unity: destination = target + (self-target).normalized * approach
		if dist > approach:
			var away: Vector3 = s.global_position - tgt.global_position
			away.y = 0.0
			if away.length_squared() < 0.0001:
				away = Vector3(0.0, 0.0, 1.0)
			else:
				away = away.normalized()
			var approach_pt: Vector3 = tgt.global_position + away * approach
			var dir: Vector3 = approach_pt - s.global_position
			dir.y = 0.0
			var step_len := dir.length()
			if step_len > 0.02:
				dir /= step_len
				s.face_dir_xz(dir)
				s.global_position += dir * minf(speed * delta, step_len)
			s.global_position.y = 0.2
		else:
			var aim: Vector3 = tgt.global_position - s.global_position
			aim.y = 0.0
			s.face_dir_xz(aim)
		if dist <= R and now - s.last_attack_time >= s.attack_duration:
			s.last_attack_time = now
			_do_attack(s)
	_apply_separation()

func _apply_separation() -> void:
	## Soft stand-in for Unity NavMeshAgent radius 0.5 avoidance.
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
				push = Vector3(1.0, 0.0, 0.0) * (min_d * 0.5)
			else:
				push = delta.normalized() * ((min_d - d) * 0.5)
			a.global_position += push
			b.global_position -= push
			a.global_position.y = 0.2
			b.global_position.y = 0.2

func _find_target(s: ShipUnit) -> ShipUnit:
	if s.is_logistic:
		var best: ShipUnit = null
		var best_d := 99999.0
		for o in _board.field_ships(s.team_id):
			if o == s:
				continue
			if o.shield_hp >= o.max_shield and o.armor_hp >= o.max_armor:
				continue
			var d := s.global_position.distance_to(o.global_position)
			if d < best_d:
				best_d = d
				best = o
		return best
	else:
		var enemy_team := ShipUnit.TEAM_AI if s.team_id == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
		var best2: ShipUnit = null
		var best_d2 := 99999.0
		for o in _board.field_ships(enemy_team):
			var d2 := s.global_position.distance_to(o.global_position)
			if d2 < best_d2:
				best_d2 = d2
				best2 = o
		return best2

func _do_attack(s: ShipUnit) -> void:
	var raw := s.damage_emp * (1.0 + s.damage_pct_bonus / 100.0)
	if s.is_logistic:
		var heal_amt := raw * float(DataStore.combat.get("logistic_heal_multiplier", 2.0))
		var payload := {"source_id": s.get_instance_id(), "target_id": s.combat_target.get_instance_id(), "heal": heal_amt}
		AdminBus.request(&"combat.heal", payload)
	else:
		var payload2 := {"source_id": s.get_instance_id(), "target_id": s.combat_target.get_instance_id(), "damage_emp": raw}
		AdminBus.request(&"combat.hit", payload2)
	if _fx and _fx.has_method("play") and s.combat_target:
		_fx.play(s, s.combat_target, s.resolve_weapon_fx_kind(), s.attack_duration)

func _on_hit(payload: Dictionary) -> Dictionary:
	var tid := int(payload.get("target_id", 0))
	var raw := float(payload.get("damage_emp", 0.0))
	var target := instance_from_id(tid) as ShipUnit
	if target == null:
		return {"accepted": false}
	var res := target.apply_hit(raw)
	return {"accepted": true, "destroyed": res.get("destroyed", false), "dealt": res.get("dealt", 0.0)}

func _on_heal(payload: Dictionary) -> Dictionary:
	var tid := int(payload.get("target_id", 0))
	var heal := float(payload.get("heal", 0.0))
	var target := instance_from_id(tid) as ShipUnit
	if target == null:
		return {"accepted": false}
	var full := target.apply_heal(heal)
	var src := instance_from_id(int(payload.get("source_id", 0))) as ShipUnit
	if full and src:
		src.combat_target = null
	return {"accepted": true, "full": full}
