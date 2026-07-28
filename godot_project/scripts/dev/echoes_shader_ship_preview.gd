extends Node3D

const ShipUnit := preload("res://scripts/ship/ship_unit.gd")

@export var ship_id: int = 10
@export var star: int = 1
@export var team_id: int = ShipUnit.TEAM_PLAYER

var _ship: ShipUnit
var _cam: Camera3D


func _ready() -> void:
	_build_env()
	_spawn_ship()


func _build_env() -> void:
	# Camera
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 2.5, 6.8)
	_cam.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	_cam.fov = 45.0
	add_child(_cam)

	# Lights
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	key.light_energy = 1.05
	key.light_color = Color(1.0, 0.98, 0.94)
	key.shadow_enabled = true
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.rotation_degrees = Vector3(-15.0, 145.0, 0.0)
	rim.light_energy = 0.36
	rim.light_color = Color(0.65, 0.8, 1.0)
	add_child(rim)

	var fill := OmniLight3D.new()
	fill.name = "Fill"
	fill.position = Vector3(0.0, 1.5, 3.5)
	fill.omni_range = 20.0
	fill.light_energy = 0.25
	add_child(fill)

	# Background
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.05, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.74, 0.78)
	e.ambient_light_energy = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.95
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.04
	e.adjustment_saturation = 1.0
	e.glow_enabled = false
	e.ssao_enabled = false
	env.environment = e
	add_child(env)


func _spawn_ship() -> void:
	if _ship and is_instance_valid(_ship):
		_ship.queue_free()
	_ship = null

	_ship = ShipUnit.new()
	add_child(_ship)
	_ship.position = Vector3.ZERO
	_ship.setup(ship_id, star, team_id)

	# Hide HUD bars for cleaner screenshots (ShipUnit inserts HealthBar Node3D).
	var hb := _ship.get_node_or_null("HealthBar")
	if hb:
		_hide_node_tree_visible(hb, false)

	await get_tree().process_frame

	# Frame ship in camera space via AABB.
	var meshes := _find_meshes(_ship)
	if meshes.is_empty():
		return

	var aabb := AABB()
	var first := true
	for mi in meshes:
		for v in mi.get_aabb().get_points():
			var p := mi.global_transform * v
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	if first:
		return

	var center := aabb.get_center()
	var size := aabb.size
	_ship.position -= center
	var longest := maxf(size.x, maxf(size.y, size.z))
	_cam.position = Vector3(0.0, 1.8 + longest * 0.25, 5.4 + longest * 0.38)
	_cam.look_at(Vector3(0.0, 0.6 + size.y * 0.2, 0.0), Vector3.UP)


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_find_meshes(c))
	return out


func _hide_node_tree_visible(root: Node, visible: bool) -> void:
	# Node3D has `visible`, Control has `visible` too (CanvasItem).
	if root is Node3D:
		(root as Node3D).visible = visible
	elif root is CanvasItem:
		(root as CanvasItem).visible = visible
	for c in root.get_children():
		_hide_node_tree_visible(c, visible)
