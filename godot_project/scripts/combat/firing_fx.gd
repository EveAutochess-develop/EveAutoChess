extends Node
## Attack VFX: Unity FiringEffectController laser stretch + EVEmu kind taxonomy
## (effects.Laser / hybrid / projectileFired / missileLaunching).
## Spawns from ShipUnit.get_muzzle_global() (AABB bow tip — GLB has no turret sockets).
## Beam/projectile endpoints re-sample firer muzzle + target each tick so FX stay tethered.

var _world: Node3D
var _active: Array = []  # Dictionary entries

func setup(world_root: Node3D) -> void:
	_world = world_root

func play(firer: ShipUnit, target: ShipUnit, kind: String, duration: float, projectile_travel_s: float = -1.0) -> void:
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
			float(kdef.get("trail_length", 0.6))
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
	if target != null and is_instance_valid(target) and not bool(target.get("is_destroyed")):
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
	trail_length: float = 0.6
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
	_active.append({
		"style": "projectile",
		"node": mi,
		"trail": trail_mi,
		"firer": firer,
		"target": target,
		"ja": ja,
		"jb": jb,
		"from": from,
		"to": to,
		"speed": speed,
		"travel_s": projectile_travel_s,
		"trail_lag": trail_lag,
		"progress": 0.0,
		"dist": maxf(0.01, from.distance_to(to)),
	})

func _tick_beam(e: Dictionary, delta: float) -> bool:
	e["t_left"] = float(e["t_left"]) - delta
	var firer: ShipUnit = e.get("firer")
	var target: ShipUnit = e.get("target")
	var mi: MeshInstance3D = e.get("node")
	if mi == null or not is_instance_valid(mi):
		return false
	if firer == null or not is_instance_valid(firer) or bool(firer.get("is_destroyed")):
		return false
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
	var mi: MeshInstance3D = e.get("node")
	if mi == null or not is_instance_valid(mi):
		return false
	var firer: ShipUnit = e.get("firer")
	var target: ShipUnit = e.get("target")
	var ja: Vector3 = e.get("ja", Vector3.ZERO)
	var jb: Vector3 = e.get("jb", Vector3.ZERO)
	var from: Vector3 = e.get("from", Vector3.ZERO)
	var to: Vector3 = e.get("to", Vector3.ZERO)
	if firer != null and is_instance_valid(firer) and not bool(firer.get("is_destroyed")):
		from = _muzzle_point(firer) + ja
	to = _target_point(target, jb, to)
	e["from"] = from
	e["to"] = to
	var dist: float = maxf(0.01, from.distance_to(to))
	e["dist"] = dist
	var travel_s := float(e.get("travel_s", -1.0))
	if travel_s > 0.0:
		e["progress"] = float(e["progress"]) + delta / travel_s
	else:
		var speed: float = float(e["speed"])
		e["progress"] = float(e["progress"]) + (speed * delta) / dist
	var t: float = clampf(float(e["progress"]), 0.0, 1.0)
	mi.global_position = from.lerp(to, t)
	var trail: MeshInstance3D = e.get("trail")
	if trail != null and is_instance_valid(trail):
		var lag := clampf(float(e.get("trail_lag", 0.08)), 0.02, 0.35)
		var back := from.lerp(to, maxf(0.0, t - lag))
		trail.global_position = (mi.global_position + back) * 0.5
		if mi.global_position.distance_to(back) > 0.01:
			trail.look_at(mi.global_position, Vector3.UP)
			trail.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	return t < 1.0

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
