extends Node3D
class_name AsteroidBelt
## Central dust-belt decor: EVE TQ ore asteroids under the board midline.
## Each rock has an invisible StaticBody MiningAnchor for future mining FX.

const ASTEROID_DIR := "res://assets/models/env/asteroids"
const FALLBACK_ROCKS: Array[String] = [
	"res://assets/models/env/Models_rock_1.glb",
	"res://assets/models/env/Models_rock_2.glb",
	"res://assets/models/env/Models_rock_3.glb",
]
const ROCK_TEX: Array[String] = [
	"res://assets/textures/rock 1 diffuse.png",
	"res://assets/textures/rock 2 diffuse.png",
	"res://assets/textures/rock 3 diffuse.png",
]

## Public: MiningAnchor nodes (order = asteroid_id 0..n-1).
var mining_anchors: Array[Node3D] = []


func build() -> void:
	name = "AsteroidBelt"
	mining_anchors.clear()
	var v: Dictionary = DataStore.visual
	var count: int = int(v.get("asteroid_belt_count", 22))
	var belt_seed: int = int(v.get("asteroid_belt_seed", 20260729))
	var y_min: float = float(v.get("asteroid_belt_y_min", -3.8))
	var y_max: float = float(v.get("asteroid_belt_y_max", -1.2))
	var s_min: float = float(v.get("asteroid_belt_scale_min", 0.55))
	var s_max: float = float(v.get("asteroid_belt_scale_max", 1.85))
	var target: float = float(v.get("asteroid_belt_target_size", 2.4))
	var meshes: Array[String] = _collect_mesh_paths()
	if meshes.is_empty():
		push_warning("AsteroidBelt: no asteroid meshes found")
		return
	var box: Dictionary = _midline_under_board_box()
	var x_min: float = float(box.get("x_min", -8.0))
	var x_max: float = float(box.get("x_max", 8.0))
	var z_min: float = float(box.get("z_min", -2.0))
	var z_max: float = float(box.get("z_max", 2.0))
	if x_max <= x_min or z_max <= z_min or y_max <= y_min:
		push_warning("AsteroidBelt: invalid midline box %s" % str(box))
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = belt_seed
	## Uniform scatter inside the isolation strip AABB (strictly under board mid).
	var placed: Array[Vector3] = []
	var min_sep: float = float(v.get("asteroid_belt_min_separation", 1.35))
	var attempts: int = 0
	var max_attempts: int = count * 60
	while placed.size() < count and attempts < max_attempts:
		attempts += 1
		var p := Vector3(
			rng.randf_range(x_min, x_max),
			rng.randf_range(y_min, y_max),
			rng.randf_range(z_min, z_max)
		)
		var ok: bool = true
		for qi in range(placed.size()):
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
		var cols: int = maxi(4, int(ceil(sqrt(float(count)))))
		var row: int = int(floor(float(i) / float(cols)))
		var col: int = i % cols
		var u: float = (float(col) + 0.5 + rng.randf_range(-0.35, 0.35)) / float(cols)
		var w: float = (float(row) + 0.5 + rng.randf_range(-0.35, 0.35)) / float(maxi(1, int(ceil(float(count) / float(cols)))))
		placed.append(Vector3(
			lerpf(x_min, x_max, clampf(u, 0.0, 1.0)),
			rng.randf_range(y_min, y_max),
			lerpf(z_min, z_max, clampf(w, 0.0, 1.0))
		))
	for i in range(count):
		var mesh_path: String = meshes[i % meshes.size()]
		var sc: float = rng.randf_range(s_min, s_max)
		_spawn_one(i, mesh_path, placed[i], target * sc, rng)
	_attach_belt_light(Vector3(
		0.5 * (x_min + x_max),
		0.5 * (y_min + y_max) + 1.2,
		0.5 * (z_min + z_max)
	))


## Isolation strip between the two Field nearest rows; X within field span. Under-board Y is caller-side.
func _midline_under_board_box() -> Dictionary:
	var b: Dictionary = DataStore.board
	var fh: int = int(b.get("field_height", 6))
	var margin: float = float(DataStore.visual.get("asteroid_belt_margin_xz", 0.85))
	## Nearest row to center = last field row (z = fh-1) for both teams.
	var near_z: int = maxi(0, fh - 1)
	var x_lo: float = INF
	var x_hi: float = -INF
	var z_player: float = 0.0
	var z_ai: float = 0.0
	var cols: int = BoardController.field_cols_at(near_z)
	for x in range(cols):
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
	var dir := DirAccess.open(ASTEROID_DIR)
	if dir:
		dir.list_dir_begin()
		var fn: String = dir.get_next()
		while fn != "":
			if not dir.current_is_dir() and fn.ends_with(".glb") and not fn.begins_with("."):
				var p: String = ASTEROID_DIR.path_join(fn)
				if FileAccess.file_exists(p):
					out.append(p)
			fn = dir.get_next()
		dir.list_dir_end()
	out.sort()
	if out.is_empty():
		for p in FALLBACK_ROCKS:
			if FileAccess.file_exists(p):
				out.append(p)
	return out


func _spawn_one(id: int, mesh_path: String, pos: Vector3, target_size: float, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.name = "Asteroid_%02d" % id
	root.position = pos
	root.rotation_degrees = Vector3(
		rng.randf_range(0.0, 360.0),
		rng.randf_range(0.0, 360.0),
		rng.randf_range(0.0, 360.0)
	)
	root.set_meta("asteroid_id", id)
	root.set_meta("mesh_path", mesh_path)
	add_child(root)
	var packed: PackedScene = load(mesh_path) as PackedScene
	if packed:
		var n: Node3D = packed.instantiate() as Node3D
		if n:
			n.name = "Mesh"
			root.add_child(n)
			_normalize_longest(n, target_size)
			_tint_rock(n, id)
	## Invisible solid locator for mining FX (no gameplay collision).
	var anchor := StaticBody3D.new()
	anchor.name = "MiningAnchor"
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	anchor.set_meta("asteroid_id", id)
	anchor.set_meta("mining_anchor", true)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var sphere := SphereShape3D.new()
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
	var result := AABB()
	var first: bool = true
	var nodes: Array[Node] = [root]
	var xforms: Array[Transform3D] = [Transform3D.IDENTITY]
	while not nodes.is_empty():
		var n: Node = nodes.pop_back() as Node
		var xf: Transform3D = xforms.pop_back() as Transform3D
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.mesh != null:
				var local_aabb: AABB = mi.get_aabb()
				for i in range(8):
					var p: Vector3 = xf * local_aabb.get_endpoint(i)
					if first:
						result = AABB(p, Vector3.ZERO)
						first = false
					else:
						result = result.expand(p)
		for c in n.get_children():
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
	var v: Dictionary = DataStore.visual
	var energy: float = float(v.get("asteroid_belt_light_energy", 1.8))
	if energy <= 0.001:
		return
	var light := OmniLight3D.new()
	light.name = "AsteroidBeltLight"
	light.light_energy = energy
	light.omni_range = float(v.get("asteroid_belt_light_range", 16.0))
	light.light_color = Color(
		float(v.get("asteroid_belt_light_color_r", 0.95)),
		float(v.get("asteroid_belt_light_color_g", 0.88)),
		float(v.get("asteroid_belt_light_color_b", 0.78))
	)
	light.shadow_enabled = false
	light.position = at
	add_child(light)


func _tint_rock(root: Node, id: int) -> void:
	var v: Dictionary = DataStore.visual
	var tex_path: String = ROCK_TEX[id % ROCK_TEX.size()]
	var tex: Texture2D = null
	if ResourceLoader.exists(tex_path):
		tex = load(tex_path) as Texture2D
	var bright: float = float(v.get("asteroid_belt_albedo_boost", 1.05))
	var hue: Color = Color(0.55, 0.52, 0.48).lerp(Color(0.42, 0.45, 0.5), float(id % 5) / 5.0)
	hue = Color(
		clampf(hue.r * bright, 0.0, 1.0),
		clampf(hue.g * bright, 0.0, 1.0),
		clampf(hue.b * bright, 0.0, 1.0)
	)
	var emit_e: float = float(v.get("asteroid_belt_emission_energy", 0.08))
	for mi in _find_meshes(root):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.88
		mat.metallic = 0.02
		if tex:
			mat.albedo_texture = tex
			mat.albedo_color = hue
		else:
			mat.albedo_color = hue.darkened(0.05)
		if emit_e > 0.001:
			mat.emission_enabled = true
			mat.emission = hue
			mat.emission_energy_multiplier = emit_e
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _find_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back() as Node
		if n is MeshInstance3D:
			out.append(n as MeshInstance3D)
		for c in n.get_children():
			stack.append(c as Node)
	return out
