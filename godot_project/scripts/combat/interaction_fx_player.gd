extends Node
## Data-driven burst / interaction FX from mod recipe JSON (COMBAT §8.4).
## No mod scripts — recipes are PNG + JSON only.
## Intentionally no class_name (avoid parse-order cycle with ShipUnit).

const WORLD_SCALE: float = 0.35
const MAX_ACTIVE: int = 48

var _world: Node3D
var _active: Array[Dictionary] = []


func setup(world_root: Node3D) -> void:
	_world = world_root


func clear_all() -> void:
	for e: Dictionary in _active:
		var host: Node3D = _entry_host(e)
		if host != null and is_instance_valid(host):
			host.queue_free()
	_active.clear()


func play_burst(
	trigger: String,
	firer: Node3D,
	target: Node3D,
	fx_def: Dictionary,
	duration_s: float = -1.0
) -> void:
	if _world == null or fx_def.is_empty():
		return
	if _use_skip_fx():
		return
	var style: String = str(fx_def.get("style", ""))
	if style == "weapon_fx_delegate":
		_play_channel_delegate(trigger, firer, target, fx_def, duration_s)
		return
	var recipe: Dictionary = _load_recipe(fx_def)
	if recipe.is_empty():
		return
	var anchor: Vector3 = _resolve_anchor(
		str(fx_def.get("anchor", recipe.get("anchor", "target_center"))),
		firer,
		target
	)
	var max_layers: int = mini(TypedVariant.as_int(fx_def.get("max_layers", 4), 4), 4)
	var layers: Array = TypedVariant.as_array(recipe.get("layers", []))
	if layers.is_empty():
		return
	var host: Node3D = Node3D.new()
	host.name = "InteractionFx_%s" % trigger
	host.global_position = anchor
	_world.add_child(host)
	var scale_mul: float = maxf(0.05, TypedVariant.as_float(fx_def.get("scale", 1.0), 1.0))
	var emit_boost: float = maxf(0.1, TypedVariant.as_float(fx_def.get("emit_boost", 1.0), 1.0))
	var dur: float = duration_s
	if dur <= 0.0:
		dur = _recipe_duration(recipe, fx_def)
	var layer_count: int = mini(layers.size(), max_layers)
	for i: int in range(layer_count):
		if typeof(layers[i]) != TYPE_DICTIONARY:
			continue
		var layer: Dictionary = TypedVariant.as_dict(layers[i])
		if style == "ring_billboard":
			_spawn_ring_layer(host, layer, fx_def, i, scale_mul, emit_boost)
		else:
			_spawn_particle_layer(host, layer, fx_def, i, scale_mul, emit_boost)
	_active.append({"host": host, "t_left": dur})
	while _active.size() > MAX_ACTIVE:
		var old: Dictionary = _active.pop_front()
		var h: Node3D = _entry_host(old)
		if h != null and is_instance_valid(h):
			h.queue_free()


func _process(delta: float) -> void:
	var i: int = _active.size() - 1
	while i >= 0:
		var e: Dictionary = _active[i]
		var t_left: float = TypedVariant.as_float(e.get("t_left", 0.0), 0.0) - delta
		if t_left <= 0.0:
			var host: Node3D = _entry_host(e)
			if host != null and is_instance_valid(host):
				host.queue_free()
			_active.remove_at(i)
		else:
			e["t_left"] = t_left
			_active[i] = e
		i -= 1


func _entry_host(e: Dictionary) -> Node3D:
	var raw: Variant = e.get("host")
	if raw == null or not (raw is Node3D):
		return null
	@warning_ignore("unsafe_cast")
	return raw as Node3D


func _use_skip_fx() -> bool:
	var ps: Variant = PlayerSettings.get_or_null()
	if ps == null or not (ps is Object):
		return false
	@warning_ignore("unsafe_cast")
	var ps_obj: Object = ps as Object
	if TypedVariant.as_bool(ps_obj.get("no_model_perf_mode"), false):
		return true
	if TypedVariant.as_bool(ps_obj.get("weapon_fx_simplified"), false):
		return true
	return false


func _load_recipe(fx_def: Dictionary) -> Dictionary:
	var abs_path: String = str(fx_def.get("recipe_abs", "")).strip_edges()
	if abs_path == "":
		abs_path = str(fx_def.get("recipe", "")).strip_edges()
	if abs_path == "" or not FileAccess.file_exists(abs_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(abs_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return TypedVariant.as_dict(parsed)


func _recipe_duration(recipe: Dictionary, fx_def: Dictionary) -> float:
	var best: float = 0.35
	for layer_v: Variant in TypedVariant.as_array(recipe.get("layers", [])):
		if typeof(layer_v) != TYPE_DICTIONARY:
			continue
		var layer: Dictionary = TypedVariant.as_dict(layer_v)
		best = maxf(best, TypedVariant.as_float(layer.get("duration", 0.0), 0.0))
		best = maxf(best, TypedVariant.as_float(layer.get("lifetime", 0.0), 0.0))
	return best * maxf(0.1, TypedVariant.as_float(fx_def.get("duration_scale", 1.0), 1.0))


func _call_vec3(node: Object, method: StringName) -> Vector3:
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	if not node.has_method(method):
		return Vector3.ZERO
	var v: Variant = node.call(method)
	if v is Vector3:
		@warning_ignore("unsafe_cast")
		return v as Vector3
	return Vector3.ZERO


func _resolve_anchor(anchor: String, firer: Node3D, target: Node3D) -> Vector3:
	match anchor:
		"firer_muzzle":
			if firer != null and is_instance_valid(firer):
				if firer.has_method("get_muzzle_global"):
					return _call_vec3(firer, &"get_muzzle_global")
				return firer.global_position + Vector3(0, 0.4, 0)
		"target_shield":
			if target != null and is_instance_valid(target) and target.has_method("get_shield_hit_global"):
				return _call_vec3(target, &"get_shield_hit_global")
		"world_hit":
			pass
		"target_center":
			pass
	if target != null and is_instance_valid(target):
		if target.has_method("visual_center_global"):
			return _call_vec3(target, &"visual_center_global")
		return target.global_position
	if firer != null and is_instance_valid(firer):
		return firer.global_position
	return Vector3.ZERO


func _spawn_particle_layer(
	host: Node3D,
	layer: Dictionary,
	fx_def: Dictionary,
	index: int,
	scale_mul: float,
	emit_boost: float
) -> void:
	var gp: GPUParticles3D = GPUParticles3D.new()
	gp.name = "Layer_%d" % index
	var pos_a: Array = TypedVariant.as_array(layer.get("pos", []))
	var px: float = TypedVariant.as_float(pos_a[0], 0.0) if pos_a.size() > 0 else 0.0
	var py: float = TypedVariant.as_float(pos_a[1], 0.0) if pos_a.size() > 1 else 0.0
	var pz: float = TypedVariant.as_float(pos_a[2], 0.0) if pos_a.size() > 2 else 0.0
	gp.position = Vector3(px, py, pz) * WORLD_SCALE * scale_mul
	var max_p: int = clampi(
		int(TypedVariant.as_float(layer.get("max_particles", 32), 32.0) * emit_boost),
		4,
		128
	)
	gp.amount = max_p
	gp.lifetime = clampf(TypedVariant.as_float(layer.get("lifetime", 1.0), 1.0), 0.1, 4.0)
	gp.one_shot = not TypedVariant.as_bool(layer.get("looping", false), false)
	gp.explosiveness = 0.85 if gp.one_shot else 0.08
	gp.preprocess = 0.15 if gp.one_shot else 0.35
	gp.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = clampf(
		TypedVariant.as_float(layer.get("shape_radius", 0.1), 0.1) * WORLD_SCALE * scale_mul,
		0.05,
		2.5
	)
	var speed: float = TypedVariant.as_float(layer.get("speed", 0.0), 0.0) * WORLD_SCALE
	mat.initial_velocity_min = maxf(0.0, speed * 0.35)
	mat.initial_velocity_max = maxf(0.5, speed * 1.1 + 0.8)
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 55.0
	mat.gravity = Vector3(0, -TypedVariant.as_float(layer.get("gravity", 0.0), 0.0) * 2.5, 0)
	var sz: float = clampf(TypedVariant.as_float(layer.get("size", 1.0), 1.0) * scale_mul, 0.05, 3.0)
	mat.scale_min = sz * 0.55
	mat.scale_max = sz * 1.15
	var col: Color = _layer_color(layer, fx_def)
	var grad: Gradient = Gradient.new()
	if TypedVariant.as_bool(layer.get("color_over_lifetime", false), false):
		grad.colors = PackedColorArray([
			Color(col.r, col.g, col.b, 0.0),
			col,
			Color(col.r, col.g, col.b, 0.0)
		])
		grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	else:
		grad.colors = PackedColorArray([col, Color(col.r, col.g, col.b, 0.0)])
		grad.offsets = PackedFloat32Array([0.0, 1.0])
	var grad_tex: GradientTexture1D = GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex
	gp.process_material = mat

	var rate: float = TypedVariant.as_float(layer.get("rate", 0.0), 0.0)
	if rate > 0.01:
		gp.amount = clampi(int(rate * gp.lifetime * emit_boost), 8, 128)
	var bursts: Array = TypedVariant.as_array(layer.get("bursts", []))
	if not bursts.is_empty() and rate < 0.01:
		var burst0: Dictionary = TypedVariant.as_dict(bursts[0])
		gp.amount = clampi(int(TypedVariant.as_float(burst0.get("count", 12), 12.0) * emit_boost), 6, 128)
		gp.one_shot = true
		gp.explosiveness = 0.92

	host.add_child(gp)
	gp.emitting = true


func _spawn_ring_layer(
	host: Node3D,
	layer: Dictionary,
	fx_def: Dictionary,
	index: int,
	scale_mul: float,
	_emit_boost: float
) -> void:
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = "Ring_%d" % index
	var torus: TorusMesh = TorusMesh.new()
	var sz: float = clampf(
		TypedVariant.as_float(layer.get("size", 1.0), 1.0) * scale_mul * WORLD_SCALE,
		0.2,
		3.0
	)
	torus.inner_radius = sz * 0.72
	torus.outer_radius = sz
	mesh_inst.mesh = torus
	var col: Color = _layer_color(layer, fx_def)
	var smat: StandardMaterial3D = StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = col
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tex_path: String = str(fx_def.get("tex_ring", ""))
	if tex_path == "":
		tex_path = _resolve_layer_tex(layer, fx_def)
	if tex_path != "":
		var tex: Texture2D = _load_tex(tex_path)
		if tex != null:
			smat.albedo_texture = tex
	mesh_inst.material_override = smat
	host.add_child(mesh_inst)


func _layer_color(layer: Dictionary, fx_def: Dictionary) -> Color:
	var col_a: Array = TypedVariant.as_array(layer.get("color", []))
	var base: Color = Color(
		TypedVariant.as_float(col_a[0], 1.0) if col_a.size() > 0 else 1.0,
		TypedVariant.as_float(col_a[1], 1.0) if col_a.size() > 1 else 1.0,
		TypedVariant.as_float(col_a[2], 1.0) if col_a.size() > 2 else 1.0,
		TypedVariant.as_float(col_a[3], 1.0) if col_a.size() > 3 else 1.0
	)
	var ov_a: Array = TypedVariant.as_array(fx_def.get("color", []))
	if ov_a.size() >= 3:
		var alpha: float = TypedVariant.as_float(ov_a[3], base.a) if ov_a.size() > 3 else base.a
		base = Color(
			TypedVariant.as_float(ov_a[0], 1.0),
			TypedVariant.as_float(ov_a[1], 1.0),
			TypedVariant.as_float(ov_a[2], 1.0),
			alpha
		)
	return base


func _resolve_layer_tex(layer: Dictionary, fx_def: Dictionary) -> String:
	var rel: String = str(layer.get("tex_rel", "")).strip_edges()
	if rel == "":
		return str(fx_def.get("tex_sprite", "")).strip_edges()
	if rel.begins_with("res://") or rel.find(":") >= 0:
		return rel
	var recipe_abs: String = str(fx_def.get("recipe_abs", "")).strip_edges()
	if recipe_abs != "":
		return recipe_abs.get_base_dir().path_join(rel.get_file() if rel.find("/") < 0 else rel)
	return rel


func _load_tex(path: String) -> Texture2D:
	if path.strip_edges() == "":
		return null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			@warning_ignore("unsafe_cast")
			return res as Texture2D
	if FileAccess.file_exists(path):
		var img: Image = Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


func _play_channel_delegate(
	_trigger: String,
	firer: Node3D,
	target: Node3D,
	fx_def: Dictionary,
	duration_s: float
) -> void:
	if firer == null or target == null:
		return
	var root: Node = get_tree().get_first_node_in_group("match_root") if get_tree() else null
	if root == null or not root.get("firing_fx"):
		return
	var fx: Variant = root.get("firing_fx")
	if fx == null or not (fx is Object):
		return
	var kind: String = str(fx_def.get("weapon_fx_kind", "laser"))
	var dur: float = duration_s if duration_s > 0.0 else 1.2
	@warning_ignore("unsafe_cast")
	var fx_obj: Object = fx as Object
	if target.has_method("resolve_weapon_fx_kind") and fx_obj.has_method("play_function"):
		fx_obj.call("play_function", firer, target, kind, dur, {})
	elif fx_obj.has_method("play_to_anchor"):
		fx_obj.call("play_to_anchor", firer, target, kind, dur)
