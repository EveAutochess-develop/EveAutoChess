# Engine trail: head pinned to model nozzles; wake stamps in world.
# Two mesh styles (visual.json `booster_trail_mesh_style`, default ribbon):
#   "ribbon" — crossed billboard strips via packed ArrayMesh (match + CG default)
#   "tube"   — hollow SOF outline tubes (SurfaceTool; legacy / opt-in)
class_name EngineBoosterTrail
extends Node3D

const ROOT_NAME: String = "EngineTrails"
const FALLBACK_SIDES: int = 8
const FALLBACK_RADIUS: float = 0.11
const THICKNESS_FRAC: float = 0.16
const DEFAULT_STAMP_INTERVAL_S: float = 1.0
const DEFAULT_UNMANNED_STAMP_INTERVAL_S: float = 0.35
const DEFAULT_MIN_STAMP_WU: float = 0.35
const DEFAULT_MAX_SEGMENTS: int = 6
const DEFAULT_FADE_POWER: float = 2.0
const MIN_SEGMENT_WU: float = 0.12
const STYLE_TUBE: String = "tube"
const STYLE_RIBBON: String = "ribbon"


var _ship: Node3D = null
var _team_player: bool = true
var _locals: Array[Vector3] = []
## Per-nozzle ship-local outline verts (tube) / used to derive radius (ribbon).
var _outlines: Array = []
var _radii: Array[float] = []
var _emitting: bool = false
var _stamp_acc: float = 0.0
## Per-nozzle history: Array of {outer?, center?, radius?, age}
var _histories: Array = []
var _last_stamp_centers: Array[Vector3] = []
var _meshes: Array[MeshInstance3D] = []
var _tint: Color = Color(0.15, 0.55, 1.0, 1.0)
var _world: Node3D = null
## Non-fighter unmanned: one camera-facing strand instead of crossed ribbons.
var _single_strand: bool = false
var _mat: StandardMaterial3D = null
var _is_unmanned: bool = false
var _idle_plume_wu: float = 0.0
var _lifetime_override_s: float = -1.0
var _max_segments_override: int = 0
var _stamp_interval_override_s: float = -1.0
var _astern_local: Vector3 = Vector3(0.0, 0.0, 1.0)
var _rebuild_interval_s: float = 0.0
var _rebuild_acc: float = 0.0
var _mesh_style: String = STYLE_RIBBON
## MATCH_FLOW §2.1: skip trail hot path at ≥sim_high_speed_fx_from so presentation cannot starve sim.
static var high_speed_skip: bool = false
## Per-ship merged visual (global + trail_override). Empty until setup().
var _vis_eff: Dictionary = {}


static func _no_model() -> bool:
	return (PlayerSettings.instance() as PlayerSettings) != null and bool((PlayerSettings.instance() as PlayerSettings).no_model_perf_mode)


static func ensure_on(unit: Node3D, team_player: bool) -> EngineBoosterTrail:
	_purge_legacy(unit)
	if high_speed_skip:
		return null
	if _no_model():
		_strip_on(unit)
		return null
	var trail: EngineBoosterTrail = unit.get_node_or_null(ROOT_NAME) as EngineBoosterTrail
	if trail == null:
		trail = EngineBoosterTrail.new()
		trail.name = ROOT_NAME
		unit.add_child(trail)
	trail.setup(unit, team_player)
	return trail


static func set_emitting_on(unit: Node3D, on: bool) -> void:
	if high_speed_skip or _no_model():
		return
	var trail: EngineBoosterTrail = unit.get_node_or_null(ROOT_NAME) as EngineBoosterTrail
	if trail == null:
		return
	trail.set_emitting(on)


static func set_idle_plume_on(unit: Node3D, wu: float) -> void:
	if _no_model():
		return
	var trail: EngineBoosterTrail = unit.get_node_or_null(ROOT_NAME) as EngineBoosterTrail
	if trail == null:
		return
	trail.set_idle_plume(wu)


static func _strip_on(unit: Node3D) -> void:
	if unit == null:
		return
	var trail: Node = unit.get_node_or_null(ROOT_NAME)
	if trail != null:
		trail.queue_free()


static func _purge_legacy(unit: Node3D) -> void:
	var legacy: Node = unit.get_node_or_null("EngineTrail")
	if legacy:
		legacy.name = "EngineTrail_legacy"
		legacy.queue_free()
	var root: Node = unit.get_node_or_null(ROOT_NAME)
	if root != null and not (root is EngineBoosterTrail):
		root.name = "EngineTrails_legacy"
		root.queue_free()


func setup(unit: Node3D, team_player: bool) -> void:
	_ship = unit
	_team_player = team_player
	_vis_eff = _build_vis_eff(unit)
	_is_unmanned = false
	var kind: String = ""
	if unit != null:
		var um_v: Variant = unit.get("is_unmanned")
		_is_unmanned = TypedVariant.as_bool(um_v, false)
		var kind_v: Variant = unit.get("unmanned_kind")
		kind = str(kind_v)
	var single_on: bool = TypedVariant.as_bool(_vis().get("unmanned_single_strand_trail", true), true)
	_single_strand = _is_unmanned and kind != "fighter" and single_on
	_locals.clear()
	_outlines.clear()
	_radii.clear()
	if _single_strand and unit != null and unit.has_method("rear_center_engine_local"):
		var aft_v: Variant = unit.call("rear_center_engine_local")
		var aft: Vector3 = Vector3.ZERO
		if aft_v is Vector3:
			@warning_ignore("unsafe_cast")
			aft = aft_v as Vector3
		_locals.append(aft)
		var width_mul: float = TypedVariant.as_float(_vis().get("unmanned_single_strand_width_mul", 1.0), 1.0)
		_radii.append(maxf(0.05, width_mul * FALLBACK_RADIUS))
		_outlines.append(PackedVector3Array())
	else:
		_locals = _engine_locals_for(unit)
		_outlines = _engine_outlines_for(unit, _locals)
		_radii = _radii_from_outlines(_locals, _outlines)
		var width_mul_ship: float = TypedVariant.as_float(_vis().get("unmanned_single_strand_width_mul", 1.0), 1.0)
		if absf(width_mul_ship - 1.0) > 0.001:
			for i: int in range(_radii.size()):
				_radii[i] = maxf(0.04, _radii[i] * width_mul_ship)
	_tint = _team_tint(team_player)
	if unit != null:
		_world = unit.get_parent() as Node3D
	_apply_configured_mesh_style()
	_ensure_mesh_slots()
	set_process(true)


func _build_vis_eff(unit: Node3D) -> Dictionary:
	var base: Dictionary = DataStore.visual if DataStore else {}
	var ov: Dictionary = {}
	if unit != null and unit.has_method("resolve_trail_override"):
		var raw: Variant = unit.call("resolve_trail_override")
		ov = TypedVariant.as_dict(raw)
	elif unit != null and DataStore != null:
		var sid: int = TypedVariant.as_int(unit.get("ship_id"), 0)
		if sid > 0:
			ov = TypedVariant.as_dict(DataStore.get_ship(sid).get("trail_override", {}))
	if ov.is_empty():
		return base.duplicate(true)
	return ModTrailResolve.merge_onto_visual(base, ov)


func _apply_configured_mesh_style() -> void:
	## Match CG opening: ribbon is default; visual.json can force tube.
	var raw: String = str(_vis().get("booster_trail_mesh_style", STYLE_RIBBON)).strip_edges().to_lower()
	var next: String = STYLE_RIBBON if raw != STYLE_TUBE else STYLE_TUBE
	if next == _mesh_style:
		return
	_mesh_style = next
	clear_wake()
	for mi: MeshInstance3D in _meshes:
		if is_instance_valid(mi):
			mi.mesh = null


func set_idle_plume(wu: float) -> void:
	_idle_plume_wu = maxf(wu, 0.0)


func set_mesh_style(style: String) -> void:
	## Explicit override (CG director may still call this); otherwise setup() reads visual.json.
	var next: String = STYLE_RIBBON if style == STYLE_RIBBON else STYLE_TUBE
	if next == _mesh_style:
		return
	_mesh_style = next
	clear_wake()
	for mi: MeshInstance3D in _meshes:
		if is_instance_valid(mi):
			mi.mesh = null


func configure_profile(lifetime_s: float, max_segments: int, idle_plume_wu: float, stamp_interval_s: float = -1.0) -> void:
	_lifetime_override_s = lifetime_s if lifetime_s > 0.05 else -1.0
	_max_segments_override = maxi(max_segments, 0)
	_stamp_interval_override_s = stamp_interval_s if stamp_interval_s > 0.05 else -1.0
	set_idle_plume(idle_plume_wu)


func configure_nozzles(locals: Array[Vector3], outlines: Array, astern_local: Vector3) -> void:
	if locals.is_empty():
		return
	_locals = locals
	_outlines = outlines
	_radii = _radii_from_outlines(_locals, _outlines)
	if astern_local.length() > 0.001:
		_astern_local = astern_local.normalized()
	_histories.clear()
	_last_stamp_centers.clear()
	_ensure_mesh_slots()


func set_rebuild_interval(seconds: float) -> void:
	_rebuild_interval_s = maxf(seconds, 0.0)


func clear_wake() -> void:
	_histories.clear()
	_last_stamp_centers.clear()
	_stamp_acc = 0.0
	for mi: MeshInstance3D in _meshes:
		if is_instance_valid(mi):
			mi.mesh = null


func wake_sample_count() -> int:
	## Longest per-nozzle history — lets a caller check a plume is grown before a cut.
	var n: int = 0
	for h_v: Variant in _histories:
		if h_v is Array:
			@warning_ignore("unsafe_cast")
			var h: Array = h_v as Array
			n = maxi(n, h.size())
	return n


func set_emitting(on: bool) -> void:
	if on and not _emitting:
		_stamp_acc = _stamp_interval()
	_emitting = on
	if not on:
		_stamp_acc = 0.0


func _vis() -> Dictionary:
	if not _vis_eff.is_empty():
		return _vis_eff
	return DataStore.visual if DataStore else {}


func _stamp_interval() -> float:
	if _stamp_interval_override_s > 0.0:
		return _stamp_interval_override_s
	if _is_unmanned:
		return maxf(0.05, TypedVariant.as_float(_vis().get("booster_trail_unmanned_stamp_interval_s", DEFAULT_UNMANNED_STAMP_INTERVAL_S), DEFAULT_UNMANNED_STAMP_INTERVAL_S))
	return maxf(0.05, TypedVariant.as_float(_vis().get("booster_trail_stamp_interval_s", DEFAULT_STAMP_INTERVAL_S), DEFAULT_STAMP_INTERVAL_S))


func _min_stamp_wu() -> float:
	return maxf(0.05, TypedVariant.as_float(_vis().get("booster_trail_min_stamp_wu", DEFAULT_MIN_STAMP_WU), DEFAULT_MIN_STAMP_WU))


func _max_segments() -> int:
	if _max_segments_override > 0:
		return _max_segments_override
	return maxi(1, TypedVariant.as_int(_vis().get("booster_trail_max_segments", DEFAULT_MAX_SEGMENTS), DEFAULT_MAX_SEGMENTS))


func _fade_power() -> float:
	return maxf(1.0, TypedVariant.as_float(_vis().get("booster_trail_fade_power", DEFAULT_FADE_POWER), DEFAULT_FADE_POWER))


func _lifetime_s() -> float:
	if _lifetime_override_s > 0.05:
		return _lifetime_override_s
	var life: float = TypedVariant.as_float(_vis().get("booster_trail_lifetime_s", 2.0), 2.0)
	if life > 0.05:
		return life
	return _stamp_interval() * float(_max_segments())


func _fade_alpha(age: float) -> float:
	var life: float = _lifetime_s()
	if life <= 0.0001:
		return 0.0
	var t: float = clampf(age / life, 0.0, 1.0)
	return pow(1.0 - t, _fade_power())


func _trail_material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.vertex_color_use_as_albedo = true
		_mat.albedo_color = Color.WHITE
	return _mat


func _process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	if _ship == null or not is_instance_valid(_ship):
		queue_free()
		return
	if _no_model():
		queue_free()
		return
	_tint = _team_tint(_team_player)
	var max_age: float = _lifetime_s()
	for h_v: Variant in _histories:
		if not (h_v is Array):
			continue
		@warning_ignore("unsafe_cast")
		var arr: Array = h_v as Array
		for i: int in range(arr.size() - 1, -1, -1):
			var s: Dictionary = TypedVariant.as_dict(arr[i])
			s["age"] = TypedVariant.as_float(s.get("age", 0.0)) + delta
			arr[i] = s
			if TypedVariant.as_float(s.get("age", 0.0)) >= max_age:
				arr.remove_at(i)
	if _emitting:
		_stamp_acc += delta
		var interval: float = _stamp_interval()
		if _stamp_acc >= interval:
			_stamp_acc = 0.0
			_stamp_rings()
	if _rebuild_interval_s > 0.0:
		_rebuild_acc += delta
		if _rebuild_acc < _rebuild_interval_s:
			SessionDiagnostics.add_usec(&"trail", Time.get_ticks_usec() - t0)
			return
		_rebuild_acc = 0.0
	if _mesh_style == STYLE_RIBBON:
		_rebuild_ribbons()
	else:
		_rebuild_tubes()
	SessionDiagnostics.add_usec(&"trail", Time.get_ticks_usec() - t0)


func _nozzle_local_outline(i: int) -> PackedVector3Array:
	var local_outline: PackedVector3Array = PackedVector3Array()
	if i < _outlines.size() and typeof(_outlines[i]) == TYPE_PACKED_VECTOR3_ARRAY:
		@warning_ignore("unsafe_cast")
		local_outline = _outlines[i] as PackedVector3Array
	if local_outline.is_empty() and i < _locals.size():
		local_outline = _fallback_local_circle(_locals[i], FALLBACK_RADIUS)
	return local_outline


func _live_nozzle_world_outline(i: int) -> PackedVector3Array:
	var local_outline: PackedVector3Array = _nozzle_local_outline(i)
	var world_outer: PackedVector3Array = PackedVector3Array()
	if _ship == null or local_outline.is_empty():
		return world_outer
	for lp: Vector3 in local_outline:
		if _ship.has_method("visual_to_global"):
			var wp_v: Variant = _ship.call("visual_to_global", lp)
			if wp_v is Vector3:
				@warning_ignore("unsafe_cast")
				world_outer.append(wp_v as Vector3)
		else:
			world_outer.append(_ship.to_global(lp))
	return world_outer


func _live_nozzle_center_radius(i: int) -> Dictionary:
	## Ribbon path: only need center + SOF radius, not the full ring verts.
	if _ship == null or i >= _locals.size():
		return {}
	var local_c: Vector3 = _locals[i]
	var world_c: Vector3
	if _ship.has_method("visual_to_global"):
		var wc_v: Variant = _ship.call("visual_to_global", local_c)
		if wc_v is Vector3:
			@warning_ignore("unsafe_cast")
			world_c = wc_v as Vector3
		else:
			world_c = _ship.to_global(local_c)
	else:
		world_c = _ship.to_global(local_c)
	var r: float = FALLBACK_RADIUS
	if i < _radii.size():
		r = maxf(_radii[i], 0.04)
	## Scale radius by the drawn mesh (visual soft-follow / CG long-axis).
	var sc: Vector3 = _ship.global_transform.basis.get_scale()
	r *= maxf(sc.x, maxf(sc.y, sc.z))
	return {"center": world_c, "radius": r}


func _outline_center(outer: PackedVector3Array) -> Vector3:
	if outer.is_empty():
		return Vector3.ZERO
	var c: Vector3 = Vector3.ZERO
	for p: Vector3 in outer:
		c += p
	return c / float(outer.size())


func _stamp_rings() -> void:
	if _ship == null:
		return
	var cap: int = _max_segments()
	var min_wu: float = _min_stamp_wu()
	for i: int in range(_locals.size()):
		while _histories.size() <= i:
			_histories.append([])
		while _last_stamp_centers.size() <= i:
			_last_stamp_centers.append(Vector3(INF, INF, INF))
		var center: Vector3 = Vector3.ZERO
		var sample: Dictionary = {}
		if _mesh_style == STYLE_RIBBON:
			sample = _live_nozzle_center_radius(i)
			if sample.is_empty():
				continue
			var center_v: Variant = sample.get("center")
			if center_v is Vector3:
				@warning_ignore("unsafe_cast")
				center = center_v as Vector3
			else:
				continue
		else:
			var world_outer: PackedVector3Array = _live_nozzle_world_outline(i)
			if world_outer.is_empty():
				continue
			center = _outline_center(world_outer)
			sample = {"outer": world_outer, "age": 0.0}
		var prev: Vector3 = _last_stamp_centers[i]
		if prev.x < 1e20 and center.distance_to(prev) < min_wu:
			continue
		_last_stamp_centers[i] = center
		if not (_histories[i] is Array):
			continue
		@warning_ignore("unsafe_cast")
		var hist: Array = _histories[i] as Array
		if _mesh_style == STYLE_RIBBON:
			hist.push_front({
				"center": center,
				"radius": TypedVariant.as_float(sample.get("radius", FALLBACK_RADIUS), FALLBACK_RADIUS),
				"age": 0.0,
			})
		else:
			hist.push_front(sample)
		while hist.size() > cap:
			hist.pop_back()


func _rebuild_ribbons() -> void:
	_ensure_mesh_slots()
	for i: int in range(_meshes.size()):
		var mi: MeshInstance3D = _meshes[i]
		if i >= _locals.size():
			mi.mesh = null
			continue
		while _histories.size() <= i:
			_histories.append([])
		if not (_histories[i] is Array):
			mi.mesh = null
			continue
		@warning_ignore("unsafe_cast")
		var wake: Array = _histories[i] as Array
		var live: Dictionary = _live_nozzle_center_radius(i)
		var samples: Array = []
		if not live.is_empty() and (_emitting or not wake.is_empty()):
			samples.append({"center": live["center"], "radius": live["radius"], "age": 0.0})
		for w_v: Variant in wake:
			samples.append(w_v)
		if _emitting and _idle_plume_wu > 0.0 and samples.size() < 2 and not live.is_empty():
			samples.append(_idle_plume_ribbon_sample(live))
		if samples.size() < 2:
			mi.mesh = null
			continue
		mi.mesh = _build_crossed_ribbon(samples, _tint, _single_strand)


func _idle_plume_ribbon_sample(live: Dictionary) -> Dictionary:
	var back: Vector3 = (_ship.global_transform.basis * _astern_local).normalized() * _idle_plume_wu
	var center_v: Variant = live.get("center")
	var center: Vector3 = Vector3.ZERO
	if center_v is Vector3:
		@warning_ignore("unsafe_cast")
		center = center_v as Vector3
	return {
		"center": center + back,
		"radius": TypedVariant.as_float(live.get("radius", FALLBACK_RADIUS), FALLBACK_RADIUS) * 0.85,
		"age": _lifetime_s() * 0.85,
	}


func _build_crossed_ribbon(samples: Array, tint: Color, single_strand: bool = false) -> ArrayMesh:
	## Crossed strips by default; single_strand = one camera-facing ribbon (non-fighter unmanned).
	var verts: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var bright: float = clampf(TypedVariant.as_float(_vis().get("booster_trail_brightness", 0.5), 0.5), 0.0, 2.0)
	if _ship != null and str(_ship.get("unmanned_kind")) == "fighter":
		bright *= clampf(TypedVariant.as_float(_vis().get("fighter_trail_brightness_mul", 0.5), 0.5), 0.0, 1.0)
	var width_mul: float = 1.0
	if single_strand:
		width_mul = maxf(0.25, TypedVariant.as_float(_vis().get("unmanned_single_strand_width_mul", 1.0), 1.0))
	var centers: Array[Vector3] = []
	var radii: Array[float] = []
	var colors: Array[Color] = []
	for s_v: Variant in samples:
		var s: Dictionary = TypedVariant.as_dict(s_v)
		var center_v: Variant = s.get("center")
		if center_v is Vector3:
			@warning_ignore("unsafe_cast")
			centers.append(center_v as Vector3)
		radii.append(maxf(TypedVariant.as_float(s.get("radius", FALLBACK_RADIUS), FALLBACK_RADIUS) * width_mul, 0.04))
		var a: float = tint.a * _fade_alpha(TypedVariant.as_float(s.get("age", 0.0))) * bright
		colors.append(Color(tint.r, tint.g, tint.b, a))
	var cam_fwd: Vector3 = Vector3(0.0, 0.0, -1.0)
	if single_strand and _ship != null and is_instance_valid(_ship):
		var vp: Viewport = _ship.get_viewport()
		if vp != null:
			var cam: Camera3D = vp.get_camera_3d()
			if cam != null:
				cam_fwd = -cam.global_transform.basis.z
	for i: int in range(centers.size() - 1):
		var p0: Vector3 = centers[i]
		var p1: Vector3 = centers[i + 1]
		var seg: Vector3 = p1 - p0
		var seg_len: float = seg.length()
		if seg_len < MIN_SEGMENT_WU:
			continue
		var dir: Vector3 = seg / seg_len
		var up: Vector3 = Vector3.UP
		if absf(dir.dot(up)) > 0.92:
			up = Vector3.RIGHT
		var side_a: Vector3
		if single_strand:
			side_a = dir.cross(cam_fwd)
			if side_a.length_squared() < 0.0001:
				side_a = dir.cross(up)
			side_a = side_a.normalized()
		else:
			side_a = dir.cross(up).normalized()
		var r0: float = radii[i]
		var r1: float = radii[i + 1]
		var c0: Color = colors[i]
		var c1: Color = colors[i + 1]
		_push_ribbon_quad(verts, cols, indices, p0, p1, side_a * r0, side_a * r1, c0, c1)
		if not single_strand:
			var side_b: Vector3 = dir.cross(side_a).normalized()
			_push_ribbon_quad(verts, cols, indices, p0, p1, side_b * r0, side_b * r1, c0, c1)
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _push_ribbon_quad(
	verts: PackedVector3Array,
	cols: PackedColorArray,
	indices: PackedInt32Array,
	p0: Vector3,
	p1: Vector3,
	off0: Vector3,
	off1: Vector3,
	c0: Color,
	c1: Color
) -> void:
	var base: int = verts.size()
	verts.append(p0 - off0)
	verts.append(p0 + off0)
	verts.append(p1 + off1)
	verts.append(p1 - off1)
	cols.append(c0)
	cols.append(c0)
	cols.append(c1)
	cols.append(c1)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 3)


func _rebuild_tubes() -> void:
	_ensure_mesh_slots()
	for i: int in range(_meshes.size()):
		var mi: MeshInstance3D = _meshes[i]
		if i >= _locals.size():
			mi.mesh = null
			continue
		while _histories.size() <= i:
			_histories.append([])
		if not (_histories[i] is Array):
			mi.mesh = null
			continue
		@warning_ignore("unsafe_cast")
		var wake: Array = _histories[i] as Array
		var live_outer: PackedVector3Array = _live_nozzle_world_outline(i)
		var samples: Array = []
		if not live_outer.is_empty() and (_emitting or not wake.is_empty()):
			samples.append({"outer": live_outer, "age": 0.0})
		for w_v: Variant in wake:
			samples.append(w_v)
		if _emitting and _idle_plume_wu > 0.0 and samples.size() < 2 and not live_outer.is_empty():
			samples.append(_idle_plume_sample(live_outer))
		if samples.size() < 2:
			if samples.size() == 1:
				var sample_v: Variant = samples[0]
				if sample_v is Dictionary:
					@warning_ignore("unsafe_cast")
					mi.mesh = _build_ring_outline(sample_v as Dictionary, _tint)
				else:
					mi.mesh = null
			else:
				mi.mesh = null
			continue
		mi.mesh = _build_hollow_tube(samples, _tint)


func _idle_plume_sample(live_outer: PackedVector3Array) -> Dictionary:
	var back: Vector3 = (_ship.global_transform.basis * _astern_local).normalized() * _idle_plume_wu
	var tail: PackedVector3Array = PackedVector3Array()
	for p: Vector3 in live_outer:
		tail.append(p + back)
	return {"outer": tail, "age": _lifetime_s() * 0.85}


func _ensure_mesh_slots() -> void:
	while _meshes.size() < _locals.size():
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "TrailTube_%d" % _meshes.size()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		mi.global_transform = Transform3D.IDENTITY
		mi.material_override = _trail_material()
		if _world:
			_world.add_child(mi)
		else:
			add_child(mi)
		_meshes.append(mi)
	while _meshes.size() > _locals.size():
		var old: MeshInstance3D = _meshes.pop_back()
		if is_instance_valid(old):
			old.queue_free()
	while _histories.size() < _locals.size():
		_histories.append([])
	while _last_stamp_centers.size() < _locals.size():
		_last_stamp_centers.append(Vector3(INF, INF, INF))


func _sample_color(sample: Dictionary, tint: Color) -> Color:
	var bright: float = clampf(TypedVariant.as_float(_vis().get("booster_trail_brightness", 0.5), 0.5), 0.0, 2.0)
	if _ship != null and str(_ship.get("unmanned_kind")) == "fighter":
		bright *= clampf(TypedVariant.as_float(_vis().get("fighter_trail_brightness_mul", 0.5), 0.5), 0.0, 1.0)
	var a: float = tint.a * _fade_alpha(TypedVariant.as_float(sample.get("age", 0.0))) * bright
	return Color(tint.r, tint.g, tint.b, a)


func _build_ring_outline(sample: Dictionary, tint: Color) -> ArrayMesh:
	var col: Color = _sample_color(sample, tint)
	var outer_v: Variant = sample.get("outer", PackedVector3Array())
	var outer: PackedVector3Array = PackedVector3Array()
	if outer_v is PackedVector3Array:
		@warning_ignore("unsafe_cast")
		outer = outer_v as PackedVector3Array
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_poly_border(st, outer, col)
	st.generate_normals()
	return st.commit()


func _build_hollow_tube(samples: Array, tint: Color) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var cols: Array[Color] = []
	var centers: Array[Vector3] = []
	for s_v: Variant in samples:
		var s: Dictionary = TypedVariant.as_dict(s_v)
		cols.append(_sample_color(s, tint))
		var outer_v: Variant = s.get("outer", PackedVector3Array())
		var outer: PackedVector3Array = PackedVector3Array()
		if outer_v is PackedVector3Array:
			@warning_ignore("unsafe_cast")
			outer = outer_v as PackedVector3Array
		var inner: PackedVector3Array = _inset_poly(outer, THICKNESS_FRAC)
		rings.append({"outer": outer, "inner": inner})
		centers.append(_outline_center(outer))
	for i: int in range(rings.size() - 1):
		if centers[i].distance_to(centers[i + 1]) < MIN_SEGMENT_WU:
			continue
		var a: Dictionary = TypedVariant.as_dict(rings[i])
		var b: Dictionary = TypedVariant.as_dict(rings[i + 1])
		var ca: Color = cols[i]
		var cb: Color = cols[i + 1]
		var ao_v: Variant = a.get("outer")
		var bo_v: Variant = b.get("outer")
		var ai_v: Variant = a.get("inner")
		var bi_v: Variant = b.get("inner")
		if not (ao_v is PackedVector3Array and bo_v is PackedVector3Array and ai_v is PackedVector3Array and bi_v is PackedVector3Array):
			continue
		@warning_ignore("unsafe_cast")
		var ao: PackedVector3Array = ao_v as PackedVector3Array
		@warning_ignore("unsafe_cast")
		var bo: PackedVector3Array = bo_v as PackedVector3Array
		@warning_ignore("unsafe_cast")
		var ai: PackedVector3Array = ai_v as PackedVector3Array
		@warning_ignore("unsafe_cast")
		var bi: PackedVector3Array = bi_v as PackedVector3Array
		var n: int = mini(ao.size(), bo.size())
		if n < 3:
			continue
		if ao.size() != bo.size():
			ao = _resample_closed(ao, n)
			bo = _resample_closed(bo, n)
			ai = _resample_closed(ai, n)
			bi = _resample_closed(bi, n)
		for k: int in range(n):
			var k2: int = (k + 1) % n
			_quad(st, ao[k], ao[k2], bo[k2], bo[k], ca, ca, cb, cb)
			_quad(st, ai[k2], ai[k], bi[k], bi[k2], ca, ca, cb, cb)
	for i: int in range(rings.size()):
		var ring_entry: Dictionary = TypedVariant.as_dict(rings[i])
		var outer_v: Variant = ring_entry.get("outer")
		if outer_v is PackedVector3Array:
			@warning_ignore("unsafe_cast")
			_add_poly_border(st, outer_v as PackedVector3Array, cols[i])
	st.generate_normals()
	return st.commit()


func _add_poly_border(st: SurfaceTool, outer: PackedVector3Array, col: Color) -> void:
	if outer.size() < 3:
		return
	var inner: PackedVector3Array = _inset_poly(outer, THICKNESS_FRAC)
	var n: int = outer.size()
	for k: int in range(n):
		var k2: int = (k + 1) % n
		_quad(st, outer[k], outer[k2], inner[k2], inner[k], col, col, col, col)


func _inset_poly(outer: PackedVector3Array, frac: float) -> PackedVector3Array:
	var n: int = outer.size()
	if n < 3:
		return outer
	var c: Vector3 = Vector3.ZERO
	for p: Vector3 in outer:
		c += p
	c /= float(n)
	var inner: PackedVector3Array = PackedVector3Array()
	var t: float = clampf(1.0 - frac, 0.05, 0.95)
	for p: Vector3 in outer:
		inner.append(c.lerp(p, t))
	return inner


func _resample_closed(poly: PackedVector3Array, n: int) -> PackedVector3Array:
	if poly.size() == n or poly.is_empty() or n < 3:
		return poly
	var out: PackedVector3Array = PackedVector3Array()
	for k: int in range(n):
		var t: float = float(k) / float(n) * float(poly.size())
		var i0: int = floori(t) % poly.size()
		var i1: int = (i0 + 1) % poly.size()
		var f: float = t - float(floori(t))
		out.append(poly[i0].lerp(poly[i1], f))
	return out


func _fallback_local_circle(center: Vector3, radius: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for k: int in range(FALLBACK_SIDES):
		var ang: float = TAU * float(k) / float(FALLBACK_SIDES)
		out.append(center + Vector3(cos(ang) * radius, sin(ang) * radius, 0.0))
	return out


func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	st.set_color(c0)
	st.add_vertex(p0)
	st.set_color(c1)
	st.add_vertex(p1)
	st.set_color(c2)
	st.add_vertex(p2)
	st.set_color(c0)
	st.add_vertex(p0)
	st.set_color(c2)
	st.add_vertex(p2)
	st.set_color(c3)
	st.add_vertex(p3)


func _team_tint(team_player: bool) -> Color:
	var vis: Dictionary = _vis()
	if team_player:
		return Color(
			TypedVariant.as_float(vis.get("booster_tint_player_r", 0.15), 0.15),
			TypedVariant.as_float(vis.get("booster_tint_player_g", 0.55), 0.55),
			TypedVariant.as_float(vis.get("booster_tint_player_b", 1.0), 1.0),
			TypedVariant.as_float(vis.get("booster_tint_player_a", 1.0), 1.0)
		)
	return Color(
		TypedVariant.as_float(vis.get("booster_tint_enemy_r", 1.0), 1.0),
		TypedVariant.as_float(vis.get("booster_tint_enemy_g", 0.12), 0.12),
		TypedVariant.as_float(vis.get("booster_tint_enemy_b", 0.08), 0.08),
		TypedVariant.as_float(vis.get("booster_tint_enemy_a", 1.0), 1.0)
	)


static func _radii_from_outlines(locals: Array[Vector3], outlines: Array) -> Array[float]:
	var out: Array[float] = []
	for i: int in locals.size():
		var r: float = FALLBACK_RADIUS
		if i < outlines.size() and typeof(outlines[i]) == TYPE_PACKED_VECTOR3_ARRAY:
			var ring: PackedVector3Array = outlines[i]
			var c: Vector3 = locals[i]
			for p: Vector3 in ring:
				r = maxf(r, p.distance_to(c))
		out.append(r)
	return out


static func _engine_locals_for(unit: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if unit.has_method("get_engine_locals"):
		var got: Variant = unit.call("get_engine_locals")
		if typeof(got) == TYPE_ARRAY:
			for p: Variant in got:
				if typeof(p) == TYPE_VECTOR3:
					@warning_ignore("unsafe_cast")
					out.append(p as Vector3)
	if out.is_empty() and unit.has_method("get_engine_local"):
		var local_v: Variant = unit.call("get_engine_local")
		if local_v is Vector3:
			@warning_ignore("unsafe_cast")
			out.append(local_v as Vector3)
	if out.is_empty():
		out.append(Vector3(0.0, 0.12, 0.55))
	return out


static func _engine_outlines_for(unit: Node3D, locals: Array[Vector3]) -> Array:
	var out: Array = []
	if unit.has_method("get_engine_outlines"):
		var got: Variant = unit.call("get_engine_outlines")
		if typeof(got) == TYPE_ARRAY:
			for item: Variant in got:
				if typeof(item) == TYPE_PACKED_VECTOR3_ARRAY:
					out.append(item)
	while out.size() < locals.size():
		var c: Vector3 = locals[out.size()]
		var ring: PackedVector3Array = PackedVector3Array()
		for k: int in range(FALLBACK_SIDES):
			var ang: float = TAU * float(k) / float(FALLBACK_SIDES)
			ring.append(c + Vector3(cos(ang) * FALLBACK_RADIUS, sin(ang) * FALLBACK_RADIUS, 0.0))
		out.append(ring)
	return out


func _exit_tree() -> void:
	for mi: MeshInstance3D in _meshes:
		if is_instance_valid(mi):
			mi.queue_free()
	_meshes.clear()
