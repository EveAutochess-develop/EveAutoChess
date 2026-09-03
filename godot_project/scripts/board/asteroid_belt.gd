extends Node3D
class_name AsteroidBelt
## Central dust-belt decor: EVE TQ ore asteroids under the board midline.
## Each rock has an invisible StaticBody MiningAnchor for future mining FX.
## Layout is computed first; GLB instances spawn in batches (MINING_AND_DUST §1).

const ASTEROID_DIR: String = "res://assets/models/env/asteroids"
const TEX_DIR: String = "res://assets/models/env/asteroids/tex"
## Explicit list — DirAccess + FileAccess.file_exists often miss mounted PCK paths on Android.
const ASTEROID_FILES: Array[String] = [
	"rock_01_l_v1.glb",
	"rock_01_m_v1.glb",
	"rock_01_m_v2.glb",
	"rock_01_m_v3.glb",
	"rock_02_l_v1.glb",
	"rock_02_m_v1.glb",
	"rock_02_m_v2.glb",
	"rock_02_m_v3.glb",
	"rock_02_s_v1.glb",
	"rock_06_v1.glb",
]
## TQ map sets (from res:/dx9/model/celestial/asteroid/rock_XX/rock_XX_{a,n,g}.dds).
const ROCK_SETS: Array[String] = ["rock_01", "rock_02", "rock_06"]
const FALLBACK_ROCKS: Array[String] = [
	"res://assets/models/env/Models_rock_1.glb",
	"res://assets/models/env/Models_rock_2.glb",
	"res://assets/models/env/Models_rock_3.glb",
]

## Public: MiningAnchor nodes (order = asteroid_id 0..n-1).
var mining_anchors: Array[Node3D] = []
var _tex_cache: Dictionary = {}  # path -> Texture2D
## Pending spawn specs after begin_build(); emptied by spawn_batch.
var _queue: Array[Dictionary] = []
var _next_i: int = 0
var _light_at: Vector3 = Vector3.ZERO
var _light_attached: bool = false


## Sync full build (preview tools / legacy callers).
func build() -> void:
	begin_build()
	while spawn_batch(99999):
		pass


## Compute placements + queue GLB jobs; does not instantiate meshes yet.
func begin_build() -> void:
	name = "AsteroidBelt"
	add_to_group("asteroid_belt")
	mining_anchors.clear()
	_queue.clear()
	_next_i = 0
	_light_attached = false
	for c: Node in get_children():
		c.queue_free()
	var v: Dictionary = TypedVariant.as_dict(DataStore.visual)
	var count: int = TypedVariant.as_int(v.get("asteroid_belt_count", 22), 22)
	var belt_seed: int = TypedVariant.as_int(v.get("asteroid_belt_seed", 0), 0)
	var y_min: float = TypedVariant.as_float(v.get("asteroid_belt_y_min", -3.8), -3.8)
	var y_max: float = TypedVariant.as_float(v.get("asteroid_belt_y_max", -1.2), -1.2)
	var s_min: float = TypedVariant.as_float(v.get("asteroid_belt_scale_min", 0.55), 0.55)
	var s_max: float = TypedVariant.as_float(v.get("asteroid_belt_scale_max", 1.85), 1.85)
	var target: float = TypedVariant.as_float(v.get("asteroid_belt_target_size", 2.4), 2.4)
	var meshes: Array[String] = _collect_mesh_paths()
	if meshes.is_empty():
		push_warning("AsteroidBelt: no asteroid meshes found")
		return
	var box: Dictionary = _midline_under_board_box()
	var x_min: float = TypedVariant.as_float(box.get("x_min", -8.0), -8.0)
	var x_max: float = TypedVariant.as_float(box.get("x_max", 8.0), 8.0)
	var z_min: float = TypedVariant.as_float(box.get("z_min", -2.0), -2.0)
	var z_max: float = TypedVariant.as_float(box.get("z_max", 2.0), 2.0)
	if x_max <= x_min or z_max <= z_min or y_max <= y_min:
		push_warning("AsteroidBelt: invalid midline box %s" % str(box))
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	## ≤0 → fresh entropy each MapEnv.build (per match). >0 → reproducible layout.
	if belt_seed <= 0:
		rng.randomize()
	else:
		rng.seed = belt_seed
	print("[AsteroidBelt] seed=%d count=%d meshes=%d" % [rng.seed, count, meshes.size()])
	var placed: Array[Vector3] = []
	var min_sep: float = TypedVariant.as_float(v.get("asteroid_belt_min_separation", 1.35), 1.35)
	var attempts: int = 0
	var max_attempts: int = count * 60
	while placed.size() < count and attempts < max_attempts:
		attempts += 1
		var p: Vector3 = Vector3(
			rng.randf_range(x_min, x_max),
			rng.randf_range(y_min, y_max),
			rng.randf_range(z_min, z_max)
		)
		var ok: bool = true
		for qi: int in range(placed.size()):
			var q: Vector3 = placed[qi]
			var d: float = Vector2(p.x - q.x, p.z - q.z).length()
			if d < min_sep:
				ok = false
				break
		if ok:
			placed.append(p)
	## Fill leftovers on a jittered grid still clamped to the box.
	while placed.size() < count:
		var i: int = placed.size()
		var cols: int = maxi(4, ceili(sqrt(float(count))))
		var row: int = floori(float(i) / float(cols))
		var col: int = i % cols
		var u: float = (float(col) + 0.5 + rng.randf_range(-0.35, 0.35)) / float(cols)
		var w: float = (float(row) + 0.5 + rng.randf_range(-0.35, 0.35)) / float(maxi(1, ceili(float(count) / float(cols))))
		placed.append(Vector3(
			lerpf(x_min, x_max, clampf(u, 0.0, 1.0)),
			rng.randf_range(y_min, y_max),
			lerpf(z_min, z_max, clampf(w, 0.0, 1.0))
		))
	for i: int in range(count):
		var mesh_path: String = meshes[rng.randi() % meshes.size()]
		var sc: float = rng.randf_range(s_min, s_max)
		_queue.append({
			"id": i,
			"mesh_path": mesh_path,
			"pos": placed[i],
			"target_size": target * sc,
			"rot_deg": Vector3(
				rng.randf_range(0.0, 360.0),
				rng.randf_range(0.0, 360.0),
				rng.randf_range(0.0, 360.0)
			),
		})
	_light_at = Vector3(
		0.5 * (x_min + x_max),
		0.5 * (y_min + y_max) + 1.2,
		0.5 * (z_min + z_max)
	)


## Spawn up to `limit` asteroids (default = visual asteroid_belt_spawn_per_frame).
## Returns true if more remain.
func spawn_batch(limit: int = -1) -> bool:
	if _queue.is_empty():
		_ensure_light()
		return false
	var per: int = limit
	if per <= 0:
		per = TypedVariant.as_int(DataStore.visual.get("asteroid_belt_spawn_per_frame", 8), 8)
		per = maxi(1, per)
	var end: int = mini(_next_i + per, _queue.size())
	while _next_i < end:
		var spec: Dictionary = _queue[_next_i]
		_spawn_one_from_spec(spec)
		_next_i += 1
	if _next_i >= _queue.size():
		_ensure_light()
		apply_no_model_visibility()
		return false
	apply_no_model_visibility()
	return true


func load_total() -> int:
	return _queue.size()


func load_done() -> int:
	return _next_i


## UI_AND_SHELL / MINING §1: hide rock meshes + belt light in no-model perf mode.
func apply_no_model_visibility() -> void:
	var nomodel: bool = (PlayerSettings.instance() as PlayerSettings) != null and (PlayerSettings.instance() as PlayerSettings).no_model_perf_mode
	for child: Node in get_children():
		if not (child is Node3D):
			continue
		if not str(child.name).begins_with("Asteroid_"):
			continue
		var mesh_n: Node3D = child.get_node_or_null("Mesh") as Node3D
		if nomodel:
			if mesh_n != null:
				mesh_n.visible = false
		else:
			if mesh_n == null:
				_ensure_asteroid_mesh(child as Node3D)
			else:
				mesh_n.visible = true
	var light: Node3D = get_node_or_null("AsteroidBeltLight") as Node3D
	if light != null:
		light.visible = not nomodel


func _ensure_asteroid_mesh(root: Node3D) -> void:
	if root == null or root.get_node_or_null("Mesh") != null:
		return
	var mesh_path: String = str(root.get_meta("mesh_path", ""))
	if mesh_path == "" or not ResourceLoader.exists(mesh_path):
		return
	var packed: PackedScene = load(mesh_path) as PackedScene
	if packed == null:
		return
	var n: Node3D = packed.instantiate() as Node3D
	if n == null:
		return
	var id: int = TypedVariant.as_int(root.get_meta("asteroid_id", 0), 0)
	var target_size: float = 2.4
	var anchor: Node = root.get_node_or_null("MiningAnchor")
	if anchor is StaticBody3D:
		var shape_n: CollisionShape3D = anchor.get_node_or_null("Shape") as CollisionShape3D
		if shape_n != null and shape_n.shape is SphereShape3D:
			var sph: SphereShape3D = shape_n.shape as SphereShape3D
			target_size = sph.radius / 0.42
	n.name = "Mesh"
	root.add_child(n)
	_normalize_longest(n, target_size)
	_tint_rock(n, id, mesh_path)
	var do_hp: bool = true
	var keep: float = 0.5
	if DataStore and DataStore.visual is Dictionary:
		do_hp = TypedVariant.as_bool(DataStore.visual.get("asteroid_belt_half_precision_compress", true), true)
		keep = TypedVariant.as_float(DataStore.visual.get("asteroid_belt_mesh_keep_ratio", 0.5), 0.5)
	MobileModelLoad.apply_mesh_keep_ratio(n, keep)
	if do_hp:
		MobileModelLoad.apply_half_precision_compress(n)
	for mi: MeshInstance3D in _find_meshes(n):
		mi.lod_bias = 128.0


func load_fraction() -> float:
	var t: int = load_total()
	if t <= 0:
		return 1.0
	return float(_next_i) / float(t)


func is_load_complete() -> bool:
	return _queue.is_empty() or _next_i >= _queue.size()


func _ensure_light() -> void:
	if _light_attached:
		return
	_light_attached = true
	_attach_belt_light(_light_at)


## Public: belt outer box in local space (X/Z strip + configured under-board Y band).
## Titan berth pins its bow to this box expanded ×1.5 (MULTIPLAYER_PVP §2.4a).
func bounds_box() -> AABB:
	var v: Dictionary = TypedVariant.as_dict(DataStore.visual)
	var box: Dictionary = _midline_under_board_box()
	var x_min: float = TypedVariant.as_float(box.get("x_min", -8.0), -8.0)
	var x_max: float = TypedVariant.as_float(box.get("x_max", 8.0), 8.0)
	var z_min: float = TypedVariant.as_float(box.get("z_min", -2.0), -2.0)
	var z_max: float = TypedVariant.as_float(box.get("z_max", 2.0), 2.0)
	var y_min: float = TypedVariant.as_float(v.get("asteroid_belt_y_min", -3.8), -3.8)
	var y_max: float = TypedVariant.as_float(v.get("asteroid_belt_y_max", -1.2), -1.2)
	return AABB(
		Vector3(x_min, y_min, z_min),
		Vector3(maxf(x_max - x_min, 0.01), maxf(y_max - y_min, 0.01), maxf(z_max - z_min, 0.01))
	)


## Isolation strip between the two Field nearest rows; X within field span. Under-board Y is caller-side.
func _midline_under_board_box() -> Dictionary:
	if BoardPolarGrid.is_polar():
		var half: float = BoardPolarGrid.isolation_half_width()
		var margin: float = TypedVariant.as_float(DataStore.visual.get("asteroid_belt_margin_xz", 0.85), 0.85)
		var r: float = BoardPolarGrid.play_radius()
		return {
			"x_min": -r + margin,
			"x_max": r - margin,
			"z_min": -half + margin,
			"z_max": half - margin,
		}
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var fh: int = TypedVariant.as_int(b.get("field_height", 6), 6)
	var margin: float = TypedVariant.as_float(DataStore.visual.get("asteroid_belt_margin_xz", 0.85), 0.85)
	## Nearest row to center = last field row (z = fh-1) for both teams.
	var near_z: int = maxi(0, fh - 1)
	var x_lo: float = INF
	var x_hi: float = -INF
	var z_player: float = 0.0
	var z_ai: float = 0.0
	var cols: int = BoardController.field_cols_at(near_z)
	for x: int in range(cols):
		var pp: Vector3 = BoardController.cell_to_world("field", ShipUnit.TEAM_PLAYER, x, near_z)
		var ap: Vector3 = BoardController.cell_to_world("field", ShipUnit.TEAM_AI, x, near_z)
		x_lo = minf(x_lo, minf(pp.x, ap.x))
		x_hi = maxf(x_hi, maxf(pp.x, ap.x))
		z_player = pp.z
		z_ai = ap.z
	var z_lo: float = minf(z_player, z_ai)
	var z_hi: float = maxf(z_player, z_ai)
	## Keep strictly inside the gap (away from both half-field rows).
	z_lo += margin
	z_hi -= margin
	x_lo += margin
	x_hi -= margin
	## Fallback if margin ate the strip (tiny boards).
	if z_hi <= z_lo:
		var mid_z: float = 0.5 * (z_player + z_ai)
		z_lo = mid_z - 0.75
		z_hi = mid_z + 0.75
	if x_hi <= x_lo:
		x_lo = -6.0
		x_hi = 6.0
	return {"x_min": x_lo, "x_max": x_hi, "z_min": z_lo, "z_max": z_hi}


func get_mining_anchor(asteroid_id: int) -> Node3D:
	if asteroid_id < 0 or asteroid_id >= mining_anchors.size():
		return null
	return mining_anchors[asteroid_id]


func _collect_mesh_paths() -> Array[String]:
	var out: Array[String] = []
	## Prefer explicit stems (PCK-safe). Optional DirAccess merge for drop-in rocks.
	for fn: String in ASTEROID_FILES:
		var p: String = ASTEROID_DIR.path_join(fn)
		if ResourceLoader.exists(p):
			out.append(p)
	var dir: DirAccess = DirAccess.open(ASTEROID_DIR)
	if dir:
		dir.list_dir_begin()
		var fn: String = dir.get_next()
		while fn != "":
			if not dir.current_is_dir() and fn.ends_with(".glb") and not fn.begins_with("."):
				var p2: String = ASTEROID_DIR.path_join(fn)
				if ResourceLoader.exists(p2) and not out.has(p2):
					out.append(p2)
			fn = dir.get_next()
		dir.list_dir_end()
	out.sort()
	if out.is_empty():
		for p3: String in FALLBACK_ROCKS:
			if ResourceLoader.exists(p3):
				out.append(p3)
	return out


func _spawn_one_from_spec(spec: Dictionary) -> void:
	var id: int = TypedVariant.as_int(spec.get("id", 0), 0)
	var mesh_path: String = str(spec.get("mesh_path", ""))
	@warning_ignore("unsafe_cast")
	var pos: Vector3 = spec.get("pos", Vector3.ZERO) as Vector3
	var target_size: float = TypedVariant.as_float(spec.get("target_size", 2.4), 2.4)
	@warning_ignore("unsafe_cast")
	var rot_deg: Vector3 = spec.get("rot_deg", Vector3.ZERO) as Vector3
	var root: Node3D = Node3D.new()
	root.name = "Asteroid_%02d" % id
	root.position = pos
	root.rotation_degrees = rot_deg
	root.set_meta("asteroid_id", id)
	root.set_meta("mesh_path", mesh_path)
	add_child(root)
	var skip_mesh: bool = (PlayerSettings.instance() as PlayerSettings) != null and (PlayerSettings.instance() as PlayerSettings).no_model_perf_mode
	var packed: PackedScene = null
	if not skip_mesh and mesh_path != "" and ResourceLoader.exists(mesh_path):
		packed = load(mesh_path) as PackedScene
	if packed:
		var n: Node3D = packed.instantiate() as Node3D
		if n:
			n.name = "Mesh"
			root.add_child(n)
			_normalize_longest(n, target_size)
			_tint_rock(n, id, mesh_path)
			## Half-float attrs + triangle keep (default 0.5 = half faces). Ships stay untouched.
			var do_hp: bool = true
			var keep: float = 0.5
			if DataStore and DataStore.visual is Dictionary:
				do_hp = TypedVariant.as_bool(DataStore.visual.get("asteroid_belt_half_precision_compress", true), true)
				keep = TypedVariant.as_float(DataStore.visual.get("asteroid_belt_mesh_keep_ratio", 0.5), 0.5)
			MobileModelLoad.apply_mesh_keep_ratio(n, keep)
			if do_hp:
				MobileModelLoad.apply_half_precision_compress(n)
			for mi: MeshInstance3D in _find_meshes(n):
				## Prefer full mesh if import LODs exist (board-under rocks vanish with aggressive LOD).
				mi.lod_bias = 128.0
	## Invisible solid locator for mining FX (no gameplay collision).
	var anchor: StaticBody3D = StaticBody3D.new()
	anchor.name = "MiningAnchor"
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	anchor.set_meta("asteroid_id", id)
	anchor.set_meta("mining_anchor", true)
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.name = "Shape"
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = maxf(0.35, target_size * 0.42)
	cs.shape = sphere
	anchor.add_child(cs)
	root.add_child(anchor)
	mining_anchors.append(anchor)


func _normalize_longest(root: Node3D, target: float) -> void:
	var aabb: AABB = _aabb_local(root)
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest < 0.0001:
		return
	root.scale = Vector3.ONE * (target / longest)


func _aabb_local(root: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	var nodes: Array[Node] = [root]
	var xforms: Array[Transform3D] = [Transform3D.IDENTITY]
	while not nodes.is_empty():
		@warning_ignore("unsafe_cast")
		var n: Node = nodes.pop_back() as Node
		@warning_ignore("unsafe_cast")
		var xf: Transform3D = xforms.pop_back() as Transform3D
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.mesh != null:
				var local_aabb: AABB = mi.get_aabb()
				for i: int in range(8):
					var p: Vector3 = xf * local_aabb.get_endpoint(i)
					if first:
						result = AABB(p, Vector3.ZERO)
						first = false
					else:
						result = result.expand(p)
		for c: Node in n.get_children():
			var child: Node = c as Node
			var child_xf: Transform3D = xf
			if child is Node3D and child != root:
				child_xf = xf * (child as Node3D).transform
			elif child is Node3D and n == root:
				child_xf = (child as Node3D).transform
			nodes.append(child)
			xforms.append(child_xf)
	return result


func _attach_belt_light(at: Vector3) -> void:
	var v: Dictionary = TypedVariant.as_dict(DataStore.visual)
	var energy: float = TypedVariant.as_float(v.get("asteroid_belt_light_energy", 1.6), 1.6)
	if energy <= 0.001:
		return
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "AsteroidBeltLight"
	light.light_energy = energy
	light.omni_range = TypedVariant.as_float(v.get("asteroid_belt_light_range", 14.0), 14.0)
	light.light_color = Color(
		TypedVariant.as_float(v.get("asteroid_belt_light_color_r", 0.95), 0.95),
		TypedVariant.as_float(v.get("asteroid_belt_light_color_g", 0.88), 0.88),
		TypedVariant.as_float(v.get("asteroid_belt_light_color_b", 0.78), 0.78)
	)
	light.shadow_enabled = false
	light.position = at
	add_child(light)


## Re-apply albedo/emission/light from current `DataStore.visual` without rebuild.
func refresh_look() -> void:
	var id: int = 0
	for child: Node in get_children():
		if child is Node3D and str(child.name).begins_with("Asteroid_"):
			var mesh_root: Node = child.get_node_or_null("Mesh")
			var mesh_path: String = str(child.get_meta("mesh_path", ""))
			if mesh_root:
				_tint_rock(mesh_root, id, mesh_path)
			id += 1
	var light: OmniLight3D = get_node_or_null("AsteroidBeltLight") as OmniLight3D
	if light == null:
		return
	var v: Dictionary = TypedVariant.as_dict(DataStore.visual) if DataStore.visual is Dictionary else {}
	light.light_energy = TypedVariant.as_float(v.get("asteroid_belt_light_energy", 1.6), 1.6)
	light.omni_range = TypedVariant.as_float(v.get("asteroid_belt_light_range", 14.0), 14.0)
	light.light_color = Color(
		TypedVariant.as_float(v.get("asteroid_belt_light_color_r", 0.95), 0.95),
		TypedVariant.as_float(v.get("asteroid_belt_light_color_g", 0.88), 0.88),
		TypedVariant.as_float(v.get("asteroid_belt_light_color_b", 0.78), 0.78)
	)


func _rock_set_for(mesh_path: String, id: int) -> String:
	var stem: String = mesh_path.get_file().get_basename().to_lower()
	for rs: String in ROCK_SETS:
		if stem.begins_with(rs):
			return rs
	return ROCK_SETS[id % ROCK_SETS.size()]


func _load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		@warning_ignore("unsafe_cast")
		return _tex_cache[path] as Texture2D
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_tex_cache[path] = tex
	return tex


func _tint_rock(root: Node, id: int, mesh_path: String = "") -> void:
	## TQ albedo/normal sampled with mesh UVs (reimported GR2→GLB with TEXCOORD_0).
	## Do not use triplanar on UV atlases — atlas packing black → solid black patches.
	var v: Dictionary = TypedVariant.as_dict(DataStore.visual)
	var bright: float = TypedVariant.as_float(v.get("asteroid_belt_albedo_boost", 1.0), 1.0)
	var emit_e: float = TypedVariant.as_float(v.get("asteroid_belt_emission_energy", 0.0), 0.0)
	var rock_set: String = _rock_set_for(mesh_path, id)
	var albedo: Texture2D = _load_tex("%s/%s_albedo.png" % [TEX_DIR, rock_set])
	var normal: Texture2D = _load_tex("%s/%s_normal.png" % [TEX_DIR, rock_set])
	var rough_tex: Texture2D = _load_tex("%s/%s_rough.png" % [TEX_DIR, rock_set])
	for mi: MeshInstance3D in _find_meshes(root):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.metallic = 0.0
		mat.roughness = 0.92
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		## Warm rock multiply (TQ *_a is grayscale intensity).
		mat.albedo_color = Color(0.72 * bright, 0.66 * bright, 0.58 * bright)
		if albedo:
			mat.albedo_texture = albedo
			mat.uv1_triplanar = false
			mat.uv1_scale = Vector3.ONE
		if normal:
			mat.normal_enabled = true
			mat.normal_texture = normal
			mat.normal_scale = 0.7
		if rough_tex:
			mat.roughness_texture = rough_tex
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		## Glow map is nearly empty on these rocks; keep emission off by default.
		if emit_e > 0.001:
			mat.emission_enabled = true
			mat.emission = Color(0.35, 0.30, 0.26)
			mat.emission_energy_multiplier = emit_e
		else:
			mat.emission_enabled = false
		mi.material_override = mat


func _find_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		@warning_ignore("unsafe_cast")
		var n: Node = stack.pop_back() as Node
		if n is MeshInstance3D:
			out.append(n as MeshInstance3D)
		for c: Node in n.get_children():
			stack.append(c as Node)
	return out
