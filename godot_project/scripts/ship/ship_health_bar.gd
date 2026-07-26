extends Node3D
## Horizontal triple bars: shield (blue) / armor (yellow) / structure (red), top→bottom.
## Placed along camera ↔ board-center view axis at 2× health_bar_y_offset toward the camera.

const BAR_W := 1.4
const BAR_H := 0.1
const BAR_GAP := 0.04
const COLORS := [
	Color(0.25, 0.55, 1.0, 0.95),
	Color(0.95, 0.82, 0.2, 0.95),
	Color(0.9, 0.22, 0.2, 0.95),
]
const BG := Color(0.08, 0.08, 0.1, 0.65)

var _ship: Node3D  # ShipUnit
var _fills: Array[MeshInstance3D] = []
var _bgs: Array[MeshInstance3D] = []

func setup(ship: Node3D) -> void:
	_ship = ship
	_build()
	refresh()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_fills.clear()
	_bgs.clear()
	var total_h := 3.0 * BAR_H + 2.0 * BAR_GAP
	var y0 := total_h * 0.5 - BAR_H * 0.5
	for i in range(3):
		var y := y0 - float(i) * (BAR_H + BAR_GAP)
		var bg := _make_box(BG)
		bg.position = Vector3(0, y, 0)
		add_child(bg)
		_bgs.append(bg)
		var fill := _make_box(COLORS[i])
		fill.position = Vector3(0, y, 0.01)
		add_child(fill)
		_fills.append(fill)

func _make_box(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BAR_W, BAR_H, 0.04)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 10
	mi.material_override = mat
	return mi

func refresh() -> void:
	if _ship == null or _fills.size() < 3:
		return
	_set_fill(0, float(_ship.get("shield_hp")), float(_ship.get("max_shield")))
	_set_fill(1, float(_ship.get("armor_hp")), float(_ship.get("max_armor")))
	_set_fill(2, float(_ship.get("structure_hp")), float(_ship.get("max_structure")))
	visible = not bool(_ship.get("is_destroyed"))

func _set_fill(idx: int, cur: float, mx: float) -> void:
	var ratio := 0.0 if mx <= 0.0 else clampf(cur / mx, 0.0, 1.0)
	var fill := _fills[idx]
	var y := fill.position.y
	fill.scale = Vector3(maxf(ratio, 0.001), 1, 1)
	fill.position = Vector3(-BAR_W * 0.5 + BAR_W * ratio * 0.5, y, 0.01)

func _process(_delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	var board_c := _board_center()
	var axis: Vector3 = cam.global_position - board_c
	if axis.length_squared() < 0.0001:
		axis = Vector3(0, 1, 0)
	else:
		axis = axis.normalized()
	var base := float(DataStore.visual.get("health_bar_y_offset", 2.4))
	var mul := float(DataStore.visual.get("health_bar_view_distance_mul", 2.0))
	global_position = _ship.global_position + axis * (base * mul)
	# Face camera (yaw only).
	var to_cam: Vector3 = cam.global_position - global_position
	to_cam.y = 0.0
	if to_cam.length_squared() > 0.0001:
		look_at(global_position + to_cam.normalized(), Vector3.UP)

func _board_center() -> Vector3:
	var v := DataStore.visual
	return Vector3(
		float(v.get("board_center_x", 0.0)),
		float(v.get("board_center_y", 0.0)),
		float(v.get("board_center_z", 0.0))
	)
