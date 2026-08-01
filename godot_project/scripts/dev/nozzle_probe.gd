extends Node3D
## Dev probe: are a hull's engine nozzles where the trails should start?
##
## Spawns real ShipUnits (same setup() path the match and the CG use), marks every
## resolved nozzle with a sphere, and saves an orthographic top + side shot per hull.
## Nozzle balls sitting on the stern silhouette = mapping OK; balls off the hull or
## bunched at the bow = engine_boosters.json / orientation mismatch.
##
## Run: Godot --path <project> res://scenes/nozzle_probe.tscn
## Out: projects/eveautochess-opening/_review/nozzle_probe/<id>_<key>_{top,side}.png

const OUT_DIR := "H:/game_dev/cg-director-studio/projects/eveautochess-opening/_review/nozzle_probe"
const SHIP_IDS := [63, 211]

var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_stage()
	await get_tree().process_frame
	for sid in SHIP_IDS:
		await _probe(int(sid))
	print("[NozzleProbe] done -> %s" % OUT_DIR)
	get_tree().quit()


func _build_stage() -> void:
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(_cam)
	_cam.make_current()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.05, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.72)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)


func _probe(sid: int) -> void:
	var ship: Dictionary = DataStore.get_ship(sid)
	if ship.is_empty():
		print("[NozzleProbe] %d: no ship def" % sid)
		return
	var key := str(ship.get("model_key", ""))
	var unit := ShipUnit.new()
	add_child(unit)
	unit.setup(sid, 1, ShipUnit.TEAM_PLAYER)
	unit.clear_health_bar()
	unit.slot_type = ""
	await get_tree().process_frame

	var hull := _mesh_aabb_local(unit)
	var locals: Array[Vector3] = unit.get_engine_locals()
	var report := "[NozzleProbe] %d %s (%s / sof=%s) hull_local pos=%s size=%s n=%d" % [
		sid, str(ship.get("name", "")), key, str(ship.get("sof_hull", "")),
		str(hull.position), str(hull.size), locals.size(),
	]
	print(report)
	## Forward is -Z, stern is +Z: nz near 1 means the nozzle really sits astern.
	for i in locals.size():
		var p: Vector3 = locals[i]
		var n := Vector3(
			(p.x - hull.position.x) / maxf(hull.size.x, 1e-4),
			(p.y - hull.position.y) / maxf(hull.size.y, 1e-4),
			(p.z - hull.position.z) / maxf(hull.size.z, 1e-4)
		)
		print("    nozzle %2d local=(%6.3f,%6.3f,%6.3f) norm=(%5.2f,%5.2f,%5.2f)" % [
			i, p.x, p.y, p.z, n.x, n.y, n.z
		])
		_add_marker(unit, p, maxf(hull.size.x, hull.size.z) * 0.035)
	_add_bow_marker(unit, hull)
	_report_mirror_tests(sid, key, unit, hull, locals)

	var longest := maxf(hull.size.x, maxf(hull.size.y, hull.size.z))
	_cam.size = longest * 1.9
	var dist := longest * 4.0
	var safe_key := key if key != "" else "ship"

	_cam.position = Vector3(0.0, dist, 0.0)
	_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	await _shoot("%s/%d_%s_top.png" % [OUT_DIR, sid, safe_key])

	_cam.position = Vector3(dist, 0.0, 0.0)
	_cam.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	await _shoot("%s/%d_%s_side.png" % [OUT_DIR, sid, safe_key])

	unit.queue_free()
	await get_tree().process_frame


func _report_mirror_tests(sid: int, key: String, unit: Node3D, hull: AABB, locals: Array[Vector3]) -> void:
	## Hulls without a baked bow_fit still go through CgOpeningDirector's guesses: a PI flip
	## for every `tq_` key plus a world-space "is the cloud on the bow?" test. Print what
	## those guesses would decide, so a regression there is visible next to the truth.
	if locals.is_empty():
		return
	if unit.has_method("has_baked_bow_fit") and unit.call("has_baked_bow_fit"):
		print("    MIRROR baked bow_fit -> CG applies no flip and no mirror")
		return
	var mean_local := Vector3.ZERO
	for p in locals:
		mean_local += p
	mean_local /= float(locals.size())
	var bow_yaw := PI if key.begins_with("tq_") else 0.0
	unit.rotation.y = bow_yaw
	var mean_world := Vector3.ZERO
	for p in locals:
		mean_world += unit.to_global(p)
	mean_world /= float(locals.size())
	var world_center := (unit.global_transform * hull).get_center()
	unit.rotation.y = 0.0
	print("    MIRROR bow_yaw=%d° | world: mean_z=%6.3f center_z=%6.3f -> %s | local: mean_z=%6.3f center_z=%6.3f -> %s" % [
		int(rad_to_deg(bow_yaw)),
		mean_world.z, world_center.z, "MIRROR" if mean_world.z < world_center.z else "keep",
		mean_local.z, hull.get_center().z, "MIRROR" if mean_local.z < hull.get_center().z else "keep",
	])


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)


func _add_marker(unit: Node3D, p: Vector3, r: float) -> void:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = r
	sph.height = r * 2.0
	mi.mesh = sph
	mi.position = p
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.25, 1.0, 0.35)
	mat.no_depth_test = true
	mi.material_override = mat
	unit.add_child(mi)


func _add_bow_marker(unit: Node3D, hull: AABB) -> void:
	## ShipUnit convention: forward = -Z, stern = +Z. Red ball caps -Z, blue caps +Z.
	## Nozzles (green) belong on the blue end; a hull whose nose points at blue is
	## modelled back-to-front for this frame.
	var r := maxf(hull.size.x, hull.size.z) * 0.05
	var off := hull.size.z * 0.62
	_add_ball(unit, Vector3(0.0, 0.0, -off), r, Color(1.0, 0.25, 0.2))
	_add_ball(unit, Vector3(0.0, 0.0, off), r, Color(0.3, 0.55, 1.0))


func _add_ball(unit: Node3D, p: Vector3, r: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = r
	sph.height = r * 2.0
	mi.mesh = sph
	mi.position = p
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	mi.material_override = mat
	unit.add_child(mi)


func _mesh_aabb_local(unit: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in _meshes(unit):
		var mi: MeshInstance3D = m
		var xf := unit.global_transform.affine_inverse() * mi.global_transform
		var a := xf * mi.get_aabb()
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
