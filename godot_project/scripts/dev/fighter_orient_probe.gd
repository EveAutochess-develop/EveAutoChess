extends Node3D
## Dev probe: does a hull's nose point where the match expects?
## Each cell applies the pack's baked `bow_fit` yaw (falling back to the global
## `ship_model_yaw_deg`), draws a red bar toward ShipUnit forward (local -Z,
## screen up) and green dots on the baked nozzles. Nose on the bar + nozzles at
## the tail = orientation OK.

const CELL := 30.0
const COLS := 3
const KEYS := [
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
	var cols := COLS
	var rows := int(ceil(float(KEYS.size()) / float(cols)))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(rows) * CELL + 6.0
	cam.position = Vector3(float(cols - 1) * CELL * 0.5, 120.0, float(rows - 1) * CELL * 0.5)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(cam)
	cam.make_current()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.5, 0.62)
	e.ambient_light_energy = 0.45
	env.environment = e
	add_child(env)

	for i in KEYS.size():
		var key := str(KEYS[i])
		var path := "res://assets/models/ships/%s/model.glb" % key
		if not ResourceLoader.exists(path):
			continue
		var fit := _bow_fit(key)
		var yaw := float(fit.get("model_yaw_deg", 180.0))
		var holder := Node3D.new()
		holder.position = Vector3(float(i % COLS) * CELL, 0.0, floorf(float(i) / float(COLS)) * CELL)
		add_child(holder)
		_add_forward_marker(holder)
		var pivot := Node3D.new()
		holder.add_child(pivot)
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		pivot.add_child(inst)
		_fit(inst, 16.0)
		pivot.rotation_degrees = Vector3(0.0, yaw, 0.0)
		_add_nozzles(holder, pivot, fit)
		var label := Label3D.new()
		label.text = "%s yaw%d" % [key, int(yaw)]
		label.font_size = 64
		label.pixel_size = 0.02
		label.position = Vector3(0.0, 0.0, 12.0)
		label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		holder.add_child(label)


func _bow_fit(key: String) -> Dictionary:
	var f := FileAccess.open("res://assets/models/ships/%s/engine_boosters.json" % key, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var fit_v: Variant = (parsed as Dictionary).get("bow_fit", null)
	return fit_v as Dictionary if typeof(fit_v) == TYPE_DICTIONARY else {}


func _add_nozzles(holder: Node3D, pivot: Node3D, fit: Dictionary) -> void:
	## Baked norms are 0..1 inside the post-yaw AABB, same contract ShipUnit uses.
	var norms_v: Variant = fit.get("nozzles_ship_norm", null)
	if typeof(norms_v) != TYPE_ARRAY:
		return
	var aabb := _aabb_in(holder, pivot)
	for n_any in (norms_v as Array):
		var n: Array = n_any
		if n.size() < 3:
			continue
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.5
		sph.height = 1.0
		mi.mesh = sph
		mi.position = aabb.position + Vector3(float(n[0]), float(n[1]), float(n[2])) * aabb.size
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.3, 1.0, 0.4)
		mi.material_override = mat
		holder.add_child(mi)


func _add_forward_marker(holder: Node3D) -> void:
	## Red bar along ShipUnit forward (-Z) = where the bow must end up.
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.6, 9.0)
	mi.mesh = box
	mi.position = Vector3(0.0, -3.0, -6.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.2)
	mi.material_override = mat
	holder.add_child(mi)


func _fit(root: Node3D, target: float) -> void:
	var aabb := _aabb(root)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest > 0.01:
		root.scale = Vector3.ONE * (target / longest)
	root.position = -aabb.get_center() * root.scale.x


func _aabb_in(space: Node3D, root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(root):
		var m: MeshInstance3D = mi
		var xf := space.global_transform.affine_inverse() * m.global_transform
		var a := xf * m.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		var a: AABB = (mi as MeshInstance3D).get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _meshes(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for c in node.get_children():
		found.append_array(_meshes(c))
	return found
