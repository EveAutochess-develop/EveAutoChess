extends Node
## Attack VFX: Unity FiringEffectController laser stretch + EVEmu kind taxonomy
## (effects.Laser / hybrid / projectileFired / missileLaunching).
## Spawns from ShipUnit.get_muzzle_global() (turret hardpoints; cycles multi-gun).
## Beam/projectile endpoints re-sample firer muzzle + target each tick so FX stay tethered.

var _world: Node3D
var _active: Array[Dictionary] = []
var _sfx: WeaponFireSfx

func setup(world_root: Node3D) -> void:
	_world = world_root
	if _sfx == null:
		_sfx = WeaponFireSfx.new()
		_sfx.name = "WeaponFireSfx"
		add_child(_sfx)
		_sfx.setup()

func play(firer: ShipUnit, target: ShipUnit, kind: String, duration: float, projectile_travel_s: float = -1.0, projectile_speed_cells: float = -1.0) -> void:
	if GameSession and bool(GameSession.no_model_perf_mode):
		return
	if firer == null or target == null or _world == null:
		return
	_play_kind(firer, target, null, kind, duration, projectile_travel_s, projectile_speed_cells)


## Visual-only mining beam toward a MiningAnchor (no damage).
func play_to_anchor(firer: ShipUnit, anchor: Node3D, kind: String = "mining", duration: float = 0.85) -> void:
	if GameSession and bool(GameSession.no_model_perf_mode):
		return
	if firer == null or anchor == null or not is_instance_valid(anchor) or _world == null:
		return
	_play_kind(firer, null, anchor, kind, duration, -1.0, -1.0)


## Function-bucket ship-to-ship FX (COMBAT §8.2) — nos/neut/damp/painter/…
func play_function(firer: ShipUnit, target: ShipUnit, kind: String, duration: float = 1.0) -> void:
	if GameSession and bool(GameSession.no_model_perf_mode):
		return
	if firer == null or target == null or _world == null:
		return
	var k: String = str(kind).strip_edges()
	if k == "":
		return
	var dur: float = maxf(0.2, duration)
	## Refresh existing link for the same firer/target/kind so the beam stays for the full active window.
	for e: Dictionary in _active:
		if str(e.get("style", "")) != "beam":
			continue
		if str(e.get("fx_role", "")) != "function":
			continue
		if str(e.get("kind", "")) != k:
			continue
		if e.get("firer") != firer or e.get("target") != target:
			continue
		e["t_left"] = maxf(TypedVariant.as_float(e.get("t_left", 0.0), 0.0), dur)
		return
	var before: int = _active.size()
	_play_kind(firer, target, null, k, dur, -1.0, -1.0)
	if _active.size() > before:
		var entry: Dictionary = _active[_active.size() - 1]
		entry["fx_role"] = "function"
		entry["kind"] = k


func _play_kind(
	firer: ShipUnit,
	target: ShipUnit,
	anchor: Node3D,
	kind: String,
	duration: float,
	projectile_travel_s: float,
	projectile_speed_cells: float
) -> void:
	## COMBAT §8.1 — SFX even if weapon_fx kind missing (VFX may no-op).
	if _sfx:
		_sfx.play_for(firer, kind)
	var cfg: Dictionary = DataStore.weapon_fx
	var kinds: Dictionary = TypedVariant.as_dict(cfg.get("kinds", {}))
	var kdef: Dictionary = TypedVariant.as_dict(kinds.get(kind, kinds.get("laser", {})))
	if kdef.is_empty():
		return
	var style: String = str(kdef.get("style", "beam"))
	var col_a: Array = TypedVariant.as_array(kdef.get("color", [1, 1, 0.3, 1]))
	var color: Color = Color(
		TypedVariant.as_float(col_a[0], 1.0),
		TypedVariant.as_float(col_a[1], 1.0),
		TypedVariant.as_float(col_a[2], 0.3),
		TypedVariant.as_float(col_a[3], 1.0) if col_a.size() > 3 else 1.0
	)
	var width: float = TypedVariant.as_float(kdef.get("width", 0.06), 0.06)
	var dur: float = maxf(0.08, duration * TypedVariant.as_float(kdef.get("duration_scale", 1.0), 1.0))
	var rand_r: float = TypedVariant.as_float(cfg.get("rand_pos_range", 0.25), 0.25)
	var jitter_a: Vector3 = Vector3(randf_range(-rand_r, rand_r), randf_range(0.0, rand_r), randf_range(-rand_r, rand_r))
	var jitter_b: Vector3 = Vector3(randf_range(-rand_r, rand_r), randf_range(0.0, rand_r), randf_range(-rand_r, rand_r))
	if style == "projectile" and target != null:
		var spd_cells: float = projectile_speed_cells
		if spd_cells <= 0.0 and kind == "missile":
			spd_cells = CombatFormulas.missile_speed_cells_per_s(firer)
		_spawn_projectile(
			firer,
			target,
			color,
			width,
			TypedVariant.as_float(kdef.get("speed", 30.0), 30.0),
			TypedVariant.as_bool(kdef.get("trail", false), false),
			jitter_a,
			jitter_b,
			projectile_travel_s,
			TypedVariant.as_float(kdef.get("trail_lag", 0.08), 0.08),
			TypedVariant.as_float(kdef.get("trail_length", 0.6), 0.6),
			spd_cells
		)
	else:
		_spawn_beam(firer, target, color, width, dur, jitter_a, jitter_b, anchor)

func _process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	var mul: float = 1.0
	var root: Node = get_tree().get_first_node_in_group("match_root")
	if root:
		var mc_v: Variant = root.get("match_ctrl")
		if mc_v is Node:
			var mc: Node = mc_v
			mul = TypedVariant.as_float(mc.get("speed_multiplier"), 1.0)
	var scaled: float = delta * mul
	var i: int = 0
	while i < _active.size():
		var e: Dictionary = _active[i]
		var alive: bool = true
		if str(e.get("style", "")) == "beam":
			alive = _tick_beam(e, scaled)
		else:
			alive = _tick_projectile(e, scaled)
		if alive:
			i += 1
		else:
			_free_entry(e)
			_active.remove_at(i)
	SessionDiagnostics.add_usec(&"fx", Time.get_ticks_usec() - t0)

func _spawn_beam(firer: ShipUnit, target: ShipUnit, color: Color, width: float, duration: float, ja: Vector3, jb: Vector3, anchor: Node3D = null) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE
	mi.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b) * 1.4
	mat.emission_energy_multiplier = 2.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	## Small hulls (frigate/destroyer): keep beams readable at board camera distance.
	var w: float = maxf(width, 0.06)
	if firer != null and is_instance_valid(firer):
		var sg: String = str(DataStore.get_ship(firer.ship_id).get("ship_group", "")).to_lower()
		if sg in ["frigate", "destroyer", "drone_light", "drone_medium"]:
			w = maxf(w, 0.11)
	mi.material_override = mat
	_world.add_child(mi)
	var entry: Dictionary = {
		"style": "beam",
		"node": mi,
		"firer": firer,
		"target": target,
		"anchor": anchor,
		"t_left": duration,
		"ja": ja,
		"jb": jb,
		"width": w,
	}
	_active.append(entry)
	## Layout immediately — otherwise first frame sits at world origin (looks like FX missing).
	_tick_beam(entry, 0.0)

const MUZZLE_FALLBACK_DIST: float = 6.0

func _muzzle_point(firer: ShipUnit) -> Vector3:
	if firer == null or not is_instance_valid(firer):
		return Vector3(0.0, 0.4, 0.0)
	var from: Vector3 = firer.get_muzzle_global()
	var ship_pos: Vector3 = firer.visual_origin_world() if firer.has_method("visual_origin_world") else firer.global_position
	if from.distance_to(ship_pos) > MUZZLE_FALLBACK_DIST:
		return ship_pos + Vector3(0.0, 0.4, 0.0)
	return from

func _target_point(target: ShipUnit, jb: Vector3, fallback: Vector3) -> Vector3:
	if target != null and is_instance_valid(target) and not target.is_destroyed:
		## Aim at the drawn hull so beams/missiles meet the soft-followed mesh.
		var center: Vector3 = target.visual_center_world() if target.has_method("visual_center_world") else target.global_position
		return center + Vector3(0, 0.4, 0) + jb
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
	var from: Vector3 = _muzzle_point(firer) + ja
	var to: Vector3 = _target_point(target, jb, from + Vector3(0, 0, 1))
	var mi: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = width * 0.5
	sphere.height = width
	mi.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
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
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = width * 0.15
		cyl.bottom_radius = width * 0.35
		cyl.height = maxf(0.2, trail_length)
		trail_mi.mesh = cyl
		var tmat: StandardMaterial3D = StandardMaterial3D.new()
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.albedo_color = Color(color.r, color.g, color.b, 0.45)
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		trail_mi.material_override = tmat
		_world.add_child(trail_mi)
	var chase: bool = speed_cells_per_s > 0.0
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

func _dict_vec3(v: Variant, default_val: Vector3 = Vector3.ZERO) -> Vector3:
	if v is Vector3:
		return v
	return default_val

func _tick_beam(e: Dictionary, delta: float) -> bool:
	e["t_left"] = TypedVariant.as_float(e.get("t_left", 0.0), 0.0) - delta
	var mi_v: Variant = e.get("node")
	if mi_v == null or not is_instance_valid(mi_v):
		return false
	if not mi_v is MeshInstance3D:
		return false
	var mi: MeshInstance3D = mi_v
	var firer: ShipUnit = _alive_ship_ref(e, "firer")
	if firer == null:
		return false
	var target: ShipUnit = _alive_ship_ref(e, "target")
	var ja: Vector3 = _dict_vec3(e.get("ja", Vector3.ZERO))
	var jb: Vector3 = _dict_vec3(e.get("jb", Vector3.ZERO))
	var from: Vector3 = _muzzle_point(firer) + ja
	var to: Vector3
	var anchor_v: Variant = e.get("anchor")
	if anchor_v != null and is_instance_valid(anchor_v) and anchor_v is Node3D:
		var anchor: Node3D = anchor_v
		to = anchor.global_position + jb
	else:
		to = _target_point(target, jb, from + Vector3(0, 0, 1))
	var diff: Vector3 = to - from
	var length: float = diff.length()
	if length < 0.05:
		return TypedVariant.as_float(e.get("t_left", 0.0), 0.0) > 0.0
	var mid: Vector3 = from + diff * 0.5
	mi.global_position = mid
	mi.look_at(to, Vector3.UP)
	var w: float = TypedVariant.as_float(e.get("width", 0.06), 0.06)
	mi.scale = Vector3(w, w, length)
	# blink like LaserBlinking
	var pulse: float = 0.65 + 0.35 * absf(sin(Time.get_ticks_msec() * 0.02))
	var mat_v: Variant = mi.material_override
	if mat_v is StandardMaterial3D:
		var beam_mat: StandardMaterial3D = mat_v
		beam_mat.albedo_color.a = pulse
	return TypedVariant.as_float(e.get("t_left", 0.0), 0.0) > 0.0

func _tick_projectile(e: Dictionary, delta: float) -> bool:
	var mi_v: Variant = e.get("node")
	if mi_v == null or not is_instance_valid(mi_v):
		return false
	if not mi_v is MeshInstance3D:
		return false
	var mi: MeshInstance3D = mi_v
	var target: ShipUnit = _alive_ship_ref(e, "target")
	var jb: Vector3 = _dict_vec3(e.get("jb", Vector3.ZERO))
	var speed_cells: float = TypedVariant.as_float(e.get("speed_cells_per_s", -1.0), -1.0)
	## Independent chase: fixed cells/s toward live target (or last known point).
	if speed_cells > 0.0:
		var pos: Vector3 = _dict_vec3(e.get("pos", mi.global_position), mi.global_position)
		var to: Vector3 = _target_point(target, jb, _dict_vec3(e.get("to", pos), pos))
		e["to"] = to
		var delta_p: Vector3 = to - pos
		var dist: float = delta_p.length()
		var wu: float = CombatFormulas.world_units_per_cell()
		var step: float = speed_cells * wu * delta
		var hit_r: float = TypedVariant.as_float(DataStore.combat.get("missile_hit_radius_wu", 0.45), 0.45)
		if dist <= maxf(hit_r, step) or dist < 0.001:
			mi.global_position = to
			e["pos"] = to
			return false
		var nxt: Vector3 = pos + delta_p * (step / dist)
		e["pos"] = nxt
		mi.global_position = nxt
		var trail_v: Variant = e.get("trail")
		if trail_v != null and is_instance_valid(trail_v) and trail_v is Node3D:
			var trail: Node3D = trail_v
			var _lag: float = clampf(TypedVariant.as_float(e.get("trail_lag", 0.08), 0.08), 0.02, 0.35)
			var back: Vector3 = pos
			trail.global_position = (nxt + back) * 0.5
			if nxt.distance_to(back) > 0.01:
				trail.look_at(nxt, Vector3.UP)
				trail.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		return true
	var firer: ShipUnit = _alive_ship_ref(e, "firer")
	var ja: Vector3 = _dict_vec3(e.get("ja", Vector3.ZERO))
	var from: Vector3 = _dict_vec3(e.get("from", Vector3.ZERO))
	var to2: Vector3 = _dict_vec3(e.get("to", Vector3.ZERO))
	if firer != null:
		from = _muzzle_point(firer) + ja
	to2 = _target_point(target, jb, to2)
	e["from"] = from
	e["to"] = to2
	var dist2: float = maxf(0.01, from.distance_to(to2))
	e["dist"] = dist2
	var travel_s: float = TypedVariant.as_float(e.get("travel_s", -1.0), -1.0)
	if travel_s > 0.0:
		e["progress"] = TypedVariant.as_float(e.get("progress", 0.0), 0.0) + delta / travel_s
	else:
		var speed: float = TypedVariant.as_float(e.get("speed", 0.0), 0.0)
		e["progress"] = TypedVariant.as_float(e.get("progress", 0.0), 0.0) + (speed * delta) / dist2
	var t: float = clampf(TypedVariant.as_float(e.get("progress", 0.0), 0.0), 0.0, 1.0)
	mi.global_position = from.lerp(to2, t)
	var trail2_v: Variant = e.get("trail")
	if trail2_v != null and is_instance_valid(trail2_v) and trail2_v is Node3D:
		var trail2: Node3D = trail2_v
		var lag2: float = clampf(TypedVariant.as_float(e.get("trail_lag", 0.08), 0.08), 0.02, 0.35)
		var back2: Vector3 = from.lerp(to2, maxf(0.0, t - lag2))
		trail2.global_position = (mi.global_position + back2) * 0.5
		if mi.global_position.distance_to(back2) > 0.01:
			trail2.look_at(mi.global_position, Vector3.UP)
			trail2.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	return t < 1.0

## Avoid typed assign from Dictionary when the Object was freed (crashes GDScript).
func _alive_ship_ref(e: Dictionary, key: String) -> ShipUnit:
	var raw: Variant = e.get(key)
	if raw == null or not is_instance_valid(raw):
		e[key] = null
		return null
	if not raw is ShipUnit:
		e[key] = null
		return null
	var ship: ShipUnit = raw
	if bool(ship.is_destroyed):
		return null
	return ship

func _free_entry(e: Dictionary) -> void:
	var n_v: Variant = e.get("node")
	if n_v != null and is_instance_valid(n_v) and n_v is Node:
		var n: Node = n_v
		n.queue_free()
	var trail_v: Variant = e.get("trail")
	if trail_v != null and is_instance_valid(trail_v) and trail_v is Node:
		var trail: Node = trail_v
		trail.queue_free()

func clear_all() -> void:
	for e: Dictionary in _active:
		_free_entry(e)
	_active.clear()
