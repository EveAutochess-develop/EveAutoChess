# Hull morph: prefer pack AnimationPlayer state machine (StartSiege→SiegeLoop);
# else visual proxy (industrial stands up; siege opens + optional siege_addon).
# Does not gate lock/attack — combat keeps running.
class_name HullMorphFx
extends Node3D

const DEFAULT_START_CLIPS := ["StartSiege", "Normal2Siege", "start_siege", "normal2siege"]
const DEFAULT_LOOP_CLIPS := ["SiegeLoop", "SiegeMode", "InSiegeMode", "siege_loop", "siege_mode"]


var _ship: ShipUnit = null
var _elapsed := 0.0
var _duration := 10.0
var _kind := "siege"
var _done := false
var _base_scale := Vector3.ONE
var _base_model_rot := Vector3.ZERO
var _model: Node3D = null
var _ring: MeshInstance3D = null
var _light: OmniLight3D = null
var _sparks: CPUParticles3D = null
var _anim: AnimationPlayer = null
var _using_anim := false
var _loop_clip := ""
var _addon: Node3D = null
var _addon_base_scale := Vector3.ONE


func play(ship: ShipUnit, kind: String = "siege", duration: float = 10.0) -> void:
	_ship = ship
	_kind = kind if not kind.is_empty() else "siege"
	_duration = maxf(0.5, duration)
	if _ship == null or not is_instance_valid(_ship):
		queue_free()
		return
	_ship.hull_morph_playing = true
	if _ship.has_method("model_root"):
		_model = _ship.model_root()
	if _model:
		_base_scale = _model.scale
		_base_model_rot = _model.rotation
	_resolve_addon()
	_anim = _find_animation_player(_model)
	_using_anim = _try_start_state_machine()
	if not _using_anim:
		_build_proxy_fx()
	set_process(true)


func _process(delta: float) -> void:
	if _done:
		return
	if _ship == null or not is_instance_valid(_ship) or _ship.is_destroyed:
		_finish(false)
		return
	var mul := 1.0
	var root := get_tree().get_first_node_in_group("match_root")
	if root and root.get("match_ctrl"):
		mul = float(root.match_ctrl.speed_multiplier)
	_elapsed += delta * mul
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	if _using_anim:
		_tick_anim(t)
	else:
		_tick_proxy(t, delta, mul)
	if t >= 1.0:
		_finish(true)


func _tick_anim(t: float) -> void:
	if _anim and not _loop_clip.is_empty():
		var cur := String(_anim.current_animation)
		if cur != _loop_clip and not _anim.is_playing():
			_anim.play(_loop_clip)
	global_position = _ship.visual_center_world()
	_ship.apply_hull_morph_emission(lerpf(0.08, 0.35, t), _kind)
	if _addon:
		_addon.visible = true
		var a := lerpf(0.15, 1.0, t)
		_addon.scale = _addon_base_scale * a


func _tick_proxy(t: float, delta: float, mul: float) -> void:
	## Slow open then settle (TQ Normal2Siege / StartSiege feel).
	var open := sin(t * PI)
	var settle := t * t * (3.0 - 2.0 * t)
	if _model:
		if _kind == "industrial":
			## Rorqual "stand up": pitch model toward upright (bow lifts).
			var pitch := lerpf(0.0, -0.55, settle)  ## radians, nose up in Godot if −Z bow
			_model.rotation = Vector3(_base_model_rot.x + pitch, _base_model_rot.y, _base_model_rot.z)
			var stretch := 1.0 + open * 0.06
			_model.scale = Vector3(_base_scale.x * stretch, _base_scale.y * (1.0 + settle * 0.12), _base_scale.z * stretch)
		else:
			var stretch2 := 1.0 + open * 0.12
			var flatten := 1.0 - open * 0.04
			_model.scale = Vector3(_base_scale.x * stretch2, _base_scale.y * flatten, _base_scale.z * stretch2)
	if _addon:
		_addon.visible = true
		var ascl := lerpf(0.05, 1.0, settle)
		_addon.scale = _addon_base_scale * ascl
	global_position = _ship.visual_center_world()
	if _ring:
		_ring.rotation.y += delta * mul * (1.2 + open * 2.0)
		var rs := lerpf(0.55, 1.35, settle) * (1.0 + open * 0.25)
		_ring.scale = Vector3(rs, rs, rs)
		var mat := _ring.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color.a = lerpf(0.15, 0.75, open) * (1.0 - settle * 0.35)
			mat.emission_energy_multiplier = lerpf(1.2, 4.5, open)
	if _light:
		_light.light_energy = lerpf(0.8, 5.5, open) * lerpf(1.0, 0.55, settle)
	if _sparks:
		_sparks.emitting = t < 0.92
	_ship.apply_hull_morph_emission(lerpf(0.06, 0.55, open) * lerpf(1.0, 0.7, settle), _kind)


func _finish(completed: bool) -> void:
	_done = true
	set_process(false)
	if _ship != null and is_instance_valid(_ship):
		_ship.hull_morph_playing = false
		if completed:
			_ship.hull_morphed = true
			if _using_anim and _anim and not _loop_clip.is_empty():
				_anim.play(_loop_clip)
			elif _model and _kind == "industrial":
				## Hold stood-up pose after industrial morph.
				_model.rotation = Vector3(_base_model_rot.x - 0.55, _base_model_rot.y, _base_model_rot.z)
				_model.scale = Vector3(_base_scale.x, _base_scale.y * 1.12, _base_scale.z)
			elif _model:
				_model.scale = _base_scale
			if _addon:
				_addon.visible = true
				_addon.scale = _addon_base_scale
		## Never leave morph emission stuck as a white/orange film.
		_ship.apply_hull_morph_emission(0.0, _kind)
		_ship.restore_emission_after_hull_morph()
	queue_free()


func _try_start_state_machine() -> bool:
	if _anim == null:
		return false
	var cfg := _load_hull_morph_cfg()
	var starts: Array = cfg.get("start_clips", DEFAULT_START_CLIPS)
	var loops: Array = cfg.get("loop_clips", DEFAULT_LOOP_CLIPS)
	var start_name := _first_existing_clip(starts)
	_loop_clip = _first_existing_clip(loops)
	if start_name.is_empty() and _loop_clip.is_empty():
		return false
	if not start_name.is_empty():
		_anim.play(start_name)
		if not _loop_clip.is_empty() and _anim.has_animation(start_name):
			## Queue loop after start when AnimationPlayer supports it.
			if _anim.has_method("queue"):
				_anim.queue(_loop_clip)
	elif not _loop_clip.is_empty():
		_anim.play(_loop_clip)
	return true


func _first_existing_clip(names: Array) -> String:
	if _anim == null:
		return ""
	for n in names:
		var s := str(n)
		if s.is_empty():
			continue
		if _anim.has_animation(s):
			return s
		## Godot 4 libraries: animation names may be library/clip.
		for lib_name in _anim.get_animation_library_list():
			var lib: AnimationLibrary = _anim.get_animation_library(lib_name)
			if lib and lib.has_animation(s):
				return "%s/%s" % [lib_name, s] if not str(lib_name).is_empty() else s
	return ""


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	if root is AnimationPlayer:
		return root as AnimationPlayer
	var direct := root.find_child("AnimationPlayer", true, false)
	if direct is AnimationPlayer:
		return direct as AnimationPlayer
	return null


func _resolve_addon() -> void:
	if _model == null:
		return
	_addon = _model.get_node_or_null("SiegeAddon") as Node3D
	if _addon == null:
		_addon = _model.find_child("SiegeAddon", true, false) as Node3D
	if _addon == null:
		return
	_addon_base_scale = _addon.scale
	_addon.visible = false
	_addon.scale = _addon_base_scale * 0.05


func _load_hull_morph_cfg() -> Dictionary:
	if _ship == null or DataStore == null:
		return {}
	var key := str(DataStore.get_ship(_ship.ship_id).get("model_key", ""))
	if key.is_empty():
		return {}
	var path := "res://assets/models/ships/%s/hull_morph.json" % key
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _build_proxy_fx() -> void:
	var col := Color(1.0, 0.45, 0.18, 0.7) if _kind != "industrial" else Color(0.35, 0.95, 0.55, 0.7)
	top_level = true
	if _ship:
		global_position = _ship.visual_center_world()

	_light = OmniLight3D.new()
	_light.name = "MorphLight"
	_light.light_color = Color(col.r, col.g, col.b)
	_light.light_energy = 1.0
	_light.omni_range = 8.0
	_light.shadow_enabled = false
	add_child(_light)

	_ring = MeshInstance3D.new()
	_ring.name = "MorphRing"
	var tor := TorusMesh.new()
	tor.inner_radius = 0.65
	tor.outer_radius = 1.45
	tor.rings = 14
	tor.ring_segments = 28
	_ring.mesh = tor
	_ring.position = Vector3(0, 0.15, 0)
	_ring.material_override = _mat(col, 2.5)
	add_child(_ring)

	_sparks = CPUParticles3D.new()
	_sparks.name = "MorphSparks"
	_sparks.amount = 36
	_sparks.lifetime = 0.9
	_sparks.emitting = true
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 1.1
	_sparks.direction = Vector3(0, 1, 0)
	_sparks.spread = 55.0
	_sparks.initial_velocity_min = 0.4
	_sparks.initial_velocity_max = 2.2
	_sparks.gravity = Vector3(0, -0.4, 0)
	_sparks.scale_amount_min = 0.15
	_sparks.scale_amount_max = 0.45
	_sparks.material_override = _mat(Color(col.r, col.g, col.b, 0.95), 2.2, true)
	add_child(_sparks)


func _mat(color: Color, emission_e: float, billboard: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = emission_e
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return mat
