extends Node3D
## Dev probe: does a hull's nose point where the match expects?
## Each cell applies the pack's baked `bow_fit` yaw (falling back to the global
## `ship_model_yaw_deg`), draws a red bar toward ShipUnit forward (local -Z,
## screen up) and green dots on the baked nozzles. Nose on the bar + nozzles at
## the tail = orientation OK.

const CELL: float = 30.0
const COLS: int = 3
const KEYS: Array[String] = [
	"am_chengfazhe",
	"equite",
	"locust",
	"satyr",
	"gram",
	"heavy_repair_amarr",
	"heavy_repair_caldari",
	"heavy_repair_gallente",
	"wrj_a_shiseng",
]


func _ready() -> void:
	var cols: int = COLS
	var rows: int = ceili(float(KEYS.size()) / float(cols))
	var cam: Camera3D = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(rows) * CELL + 6.0
	cam.position = Vector3(float(cols - 1) * CELL * 0.5, 120.0, float(rows - 1) * CELL * 0.5)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(cam)
	cam.make_current()

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.5, 0.62)
	e.ambient_light_energy = 0.45
	env.environment = e
	add_child(env)

	for i: int in KEYS.size():
		var key: String = KEYS[i]
		var path: String = "res://assets/models/ships/%s/model.glb" % key
		if not ResourceLoader.exists(path):
			continue
		var fit: Dictionary = _bow_fit(key)
		var yaw: float = TypedVariant.as_float(fit.get("model_yaw_deg", 180.0), 180.0)
		var holder: Node3D = Node3D.new()
		holder.position = Vector3(float(i % COLS) * CELL, 0.0, float(floori(float(i) / float(COLS))) * CELL)
		add_child(holder)
		_add_forward_marker(holder)
		var pivot: Node3D = Node3D.new()
		holder.add_child(pivot)
		var scene: PackedScene = load(path) as PackedScene
		var inst: Node3D = scene.instantiate() as Node3D
		pivot.add_child(inst)
		_fit(inst, 16.0)
		pivot.rotation_degrees = Vector3(0.0, yaw, 0.0)
		_add_nozzles(holder, pivot, fit)
		var label: Label3D = Label3D.new()
		label.text = "%s yaw%d" % [key, int(yaw)]
		label.font_size = 64
		label.pixel_size = 0.02
		label.position = Vector3(0.0, 0.0, 12.0)
		label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		holder.add_child(label)


func _bow_fit(key: String) -> Dictionary:
	var f: FileAccess = FileAccess.open("res://assets/models/ships/%s/engine_boosters.json" % key, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	var parsed_dict: Dictionary = TypedVariant.as_dict(parsed)
	return TypedVariant.as_dict(parsed_dict.get("bow_fit", null))


func _add_nozzles(holder: Node3D, pivot: Node3D, fit: Dictionary) -> void:
	## Baked norms are 0..1 inside the post-yaw AABB, same contract ShipUnit uses.
	var norms: Array = TypedVariant.as_array(fit.get("nozzles_ship_norm", null))
	if norms.is_empty():
		return
	var aabb: AABB = _aabb_in(holder, pivot)
	for n_any: Variant in norms:
		if not (n_any is Array):
			continue
		var n: Array = n_any
		if n.size() < 3:
			continue
		var mi: MeshInstance3D = MeshInstance3D.new()
		var sph: SphereMesh = SphereMesh.new()
		sph.radius = 0.5
		sph.height = 1.0
		mi.mesh = sph
		mi.position = aabb.position + Vector3(
			TypedVariant.as_float(n[0], 0.0),
			TypedVariant.as_float(n[1], 0.0),
			TypedVariant.as_float(n[2], 0.0),
		) * aabb.size
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.3, 1.0, 0.4)
		mi.material_override = mat
		holder.add_child(mi)


func _add_forward_marker(holder: Node3D) -> void:
	## Red bar along ShipUnit forward (-Z) = where the bow must end up.
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.6, 0.6, 9.0)
	mi.mesh = box
	mi.position = Vector3(0.0, -3.0, -6.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.2)
	mi.material_override = mat
	holder.add_child(mi)


func _fit(root: Node3D, target: float) -> void:
	var aabb: AABB = _aabb(root)
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest > 0.01:
		root.scale = Vector3.ONE * (target / longest)
	root.position = -aabb.get_center() * root.scale.x


func _aabb_in(space: Node3D, root: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in _meshes(root):
		var xf: Transform3D = space.global_transform.affine_inverse() * mi.global_transform
		var a: AABB = xf * mi.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _aabb(node: Node) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in _meshes(node):
		var a: AABB = mi.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for c: Node in node.get_children():
		found.append_array(_meshes(c))
	return found
