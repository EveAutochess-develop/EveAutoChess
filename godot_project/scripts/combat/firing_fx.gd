extends Node
## Attack VFX: Unity FiringEffectController laser stretch + EVEmu kind taxonomy
## (effects.Laser / hybrid / projectileFired / missileLaunching).
## Spawns from ShipUnit.get_muzzle_global() (AABB bow tip — GLB has no turret sockets).
## Beam/projectile endpoints re-sample firer muzzle + target each tick so FX stay tethered.

var _world: Node3D
var _active: Array = []  # Dictionary entries

func setup(world_root: Node3D) -> void:
	_world = world_root

func play(firer: ShipUnit, target: ShipUnit, kind: String, duration: float, projectile_travel_s: float = -1.0, projectile_speed_cells: float = -1.0) -> void:
	if firer == null or target == null or _world == null:
		return
	var cfg: Dictionary = DataStore.weapon_fx
	var kinds: Dictionary = cfg.get("kinds", {})
	var kdef: Dictionary = kinds.get(kind, kinds.get("laser", {}))
	if kdef.is_empty():
		return
	var style := str(kdef.get("style", "beam"))
	var col_a: Array = kdef.get("color", [1, 1, 0.3, 1])
	var color := Color(float(col_a[0]), float(col_a[1]), float(col_a[2]), float(col_a[3]) if col_a.size() > 3 else 1.0)
	var width := float(kdef.get("width", 0.06))
	var dur := maxf(0.08, duration * float(kdef.get("duration_scale", 1.0)))
	var rand_r := float(cfg.get("rand_pos_range", 0.25))
	var jitter_a := Vector3(randf_range(-rand_r, rand_r), randf_range(0.0, rand_r), randf_range(-rand_r, rand_r))
	var jitter_b := Vector3(randf_range(-rand_r, rand_r), randf_range(0.0, rand_r), randf_range(-rand_r, rand_r))
	if style == "projectile":
		var spd_cells := projectile_speed_cells
		if spd_cells <= 0.0 and kind == "missile":
			spd_cells = CombatFormulas.missile_speed_cells_per_s(firer)
		_spawn_projectile(
			firer,
			target,
			color,
			width,
			float(kdef.get("speed", 30.0)),
			bool(kdef.get("trail", false)),
			jitter_a,
			jitter_b,
			projectile_travel_s,
			float(kdef.get("trail_lag", 0.08)),
			float(kdef.get("trail_length", 0.6)),
			spd_cells
		)
	else:
		_spawn_beam(firer, target, color, width, dur, jitter_a, jitter_b)

func _process(delta: float) -> void:
	var mul := 1.0
	var root := get_tree().get_first_node_in_group("match_root")
	if root and root.has_method("get") and root.get("match_ctrl"):
		var mc = root.match_ctrl
		if mc:
			mul = float(mc.speed_multiplier)
	var scaled := delta * mul
	var i := 0
	while i < _active.size():
		var e: Dictionary = _active[i]
		var alive := true
		if str(e.get("style", "")) == "beam":
			alive = _tick_beam(e, scaled)
		else:
			alive = _tick_projectile(e, scaled)
		if alive:
			i += 1
		else:
			_free_entry(e)
			_active.remove_at(i)

func _spawn_beam(firer: ShipUnit, target: ShipUnit, color: Color, width: float, duration: float, ja: Vector3, jb: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b) * 1.4
	mat.emission_energy_multiplier = 2.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	_world.add_child(mi)
	_active.append({
		"style": "beam",
		"node": mi,
		"firer": firer,
		"target": target,
		"t_left": duration,
		"ja": ja,
		"jb": jb,
		"width": width,
	})

const MUZZLE_FALLBACK_DIST := 6.0

func _muzzle_point(firer: ShipUnit) -> Vector3:
	if firer == null or not is_instance_valid(firer):
		return Vector3(0.0, 0.4, 0.0)
	var from: Vector3 = firer.get_muzzle_global()
	var ship_pos: Vector3 = firer.global_position
	if from.distance_to(ship_pos) > MUZZLE_FALLBACK_DIST:
		return ship_pos + Vector3(0.0, 0.4, 0.0)
	return from

func _target_point(target: ShipUnit, jb: Vector3, fallback: Vector3) -> Vector3:
	if target != null and is_instance_valid(target) and not target.is_destroyed:
		return target.global_position + Vector3(0, 0.4, 0) + jb
	return fallback

func _spawn_projectile(
	firer: ShipUnit,
	target: ShipUnit,
	color: Color,
	width: float,
	speed: float,
	trail: bool,
	ja: Vector3,
	jb: Vector3,
	projectile_travel_s: float = -1.0,
	trail_lag: float = 0.08,
	trail_length: float = 0.6,
	speed_cells_per_s: float = -1.0
) -> void:
	var from := _muzzle_point(firer) + ja
	var to := _target_point(target, jb, from + Vector3(0, 0, 1))
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = width * 0.5
	sphere.height = width
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 2.5
	mi.material_override = mat
	_world.add_child(mi)
	mi.global_position = from
	var trail_mi: MeshInstance3D = null
	if trail:
		trail_mi = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = width * 0.15
		cyl.bottom_radius = width * 0.35
		cyl.height = maxf(0.2, trail_length)
		trail_mi.mesh = cyl
		var tmat := StandardMaterial3D.new()
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.albedo_color = Color(color.r, color.g, color.b, 0.45)
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		trail_mi.material_override = tmat
		_world.add_child(trail_mi)
	var chase := speed_cells_per_s > 0.0
	_active.append({
		"style": "projectile",
		"node": mi,
		"trail": trail_mi,
		## Detached chase missiles do not re-tether to firer muzzle.
		"firer": null if chase else firer,
		"target": target,
		"ja": ja,
		"jb": jb,
		"from": from,
		"to": to,
		"pos": from,
		"speed": speed,
		"speed_cells_per_s": speed_cells_per_s,
		"travel_s": -1.0 if chase else projectile_travel_s,
		"trail_lag": trail_lag,
		"progress": 0.0,
		"dist": maxf(0.01, from.distance_to(to)),
	})

func _tick_beam(e: Dictionary, delta: float) -> bool:
	e["t_left"] = float(e["t_left"]) - delta
	var mi = e.get("node")
	if mi == null or not is_instance_valid(mi):
		return false
	var firer := _alive_ship_ref(e, "firer")
	if firer == null:
		return false
	var target := _alive_ship_ref(e, "target")
	var ja: Vector3 = e.get("ja", Vector3.ZERO)
	var jb: Vector3 = e.get("jb", Vector3.ZERO)
	var from: Vector3 = _muzzle_point(firer) + ja
	var to: Vector3 = _target_point(target, jb, from + Vector3(0, 0, 1))
	var diff: Vector3 = to - from
	var length := diff.length()
	if length < 0.05:
		return float(e["t_left"]) > 0.0
	var mid := from + diff * 0.5
	mi.global_position = mid
	mi.look_at(to, Vector3.UP)
	var w := float(e.get("width", 0.06))
	mi.scale = Vector3(w, w, length)
	# blink like LaserBlinking
	var pulse := 0.65 + 0.35 * absf(sin(Time.get_ticks_msec() * 0.02))
	if mi.material_override is StandardMaterial3D:
		(mi.material_override as StandardMaterial3D).albedo_color.a = pulse
	return float(e["t_left"]) > 0.0

func _tick_projectile(e: Dictionary, delta: float) -> bool:
	var mi = e.get("node")
	if mi == null or not is_instance_valid(mi):
		return false
	var target := _alive_ship_ref(e, "target")
	var jb: Vector3 = e.get("jb", Vector3.ZERO)
	var speed_cells := float(e.get("speed_cells_per_s", -1.0))
	## Independent chase: fixed cells/s toward live target (or last known point).
	if speed_cells > 0.0:
		var pos: Vector3 = e.get("pos", mi.global_position)
		var to := _target_point(target, jb, e.get("to", pos))
		e["to"] = to
		var delta_p := to - pos
		var dist := delta_p.length()
		var wu := CombatFormulas.world_units_per_cell()
		var step := speed_cells * wu * delta
		var hit_r := float(DataStore.combat.get("missile_hit_radius_wu", 0.45))
		if dist <= maxf(hit_r, step) or dist < 0.001:
			mi.global_position = to
			e["pos"] = to
			return false
		var nxt := pos + delta_p * (step / dist)
		e["pos"] = nxt
		mi.global_position = nxt
		var trail = e.get("trail")
		if trail != null and is_instance_valid(trail):
			var lag := clampf(float(e.get("trail_lag", 0.08)), 0.02, 0.35)
			var back := pos
			trail.global_position = (nxt + back) * 0.5
			if nxt.distance_to(back) > 0.01:
				trail.look_at(nxt, Vector3.UP)
				trail.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		return true
	var firer := _alive_ship_ref(e, "firer")
	var ja: Vector3 = e.get("ja", Vector3.ZERO)
	var from: Vector3 = e.get("from", Vector3.ZERO)
	var to2: Vector3 = e.get("to", Vector3.ZERO)
	if firer != null:
		from = _muzzle_point(firer) + ja
	to2 = _target_point(target, jb, to2)
	e["from"] = from
	e["to"] = to2
	var dist2: float = maxf(0.01, from.distance_to(to2))
	e["dist"] = dist2
	var travel_s := float(e.get("travel_s", -1.0))
	if travel_s > 0.0:
		e["progress"] = float(e["progress"]) + delta / travel_s
	else:
		var speed: float = float(e["speed"])
		e["progress"] = float(e["progress"]) + (speed * delta) / dist2
	var t: float = clampf(float(e["progress"]), 0.0, 1.0)
	mi.global_position = from.lerp(to2, t)
	var trail2 = e.get("trail")
	if trail2 != null and is_instance_valid(trail2):
		var lag2 := clampf(float(e.get("trail_lag", 0.08)), 0.02, 0.35)
		var back2 := from.lerp(to2, maxf(0.0, t - lag2))
		trail2.global_position = (mi.global_position + back2) * 0.5
		if mi.global_position.distance_to(back2) > 0.01:
			trail2.look_at(mi.global_position, Vector3.UP)
			trail2.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	return t < 1.0

## Avoid typed assign from Dictionary when the Object was freed (crashes GDScript).
func _alive_ship_ref(e: Dictionary, key: String) -> ShipUnit:
	var raw = e.get(key)
	if raw == null or not is_instance_valid(raw):
		e[key] = null
		return null
	var ship := raw as ShipUnit
	if ship == null:
		e[key] = null
		return null
	if bool(ship.is_destroyed):
		return null
	return ship

func _free_entry(e: Dictionary) -> void:
	var n = e.get("node")
	if n != null and is_instance_valid(n):
		n.queue_free()
	var trail = e.get("trail")
	if trail != null and is_instance_valid(trail):
		trail.queue_free()

func clear_all() -> void:
	for e in _active:
		_free_entry(e)
	_active.clear()
