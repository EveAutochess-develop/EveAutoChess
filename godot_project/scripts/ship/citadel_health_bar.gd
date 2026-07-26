extends Node3D
## Single structure HP bar for player citadel (binds MatchController.player_hp).
## Same view-axis placement as ship bars (camera ↔ board center, 2× offset).

const BAR_W := 5.6
const BAR_H := 0.32
const COLOR := Color(0.9, 0.22, 0.2, 0.95)
const BG := Color(0.08, 0.08, 0.1, 0.75)

var _fill: MeshInstance3D
var _y_fill: float = 0.0
var _host: Node3D = null
var _base_offset: float = 9.5

func setup(y_offset: float = 9.5) -> void:
	_host = get_parent() as Node3D
	_base_offset = y_offset
	_build()
	refresh(1.0, 1.0)

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var bg := _make_box(BG)
	bg.position = Vector3(0, 0, 0)
	add_child(bg)
	_fill = _make_box(COLOR)
	_y_fill = 0.0
	_fill.position = Vector3(0, 0, 0.04)
	add_child(_fill)

func _make_box(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BAR_W, BAR_H, 0.08)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 8
	mi.material_override = mat
	return mi

func refresh(cur: float, mx: float) -> void:
	if _fill == null:
		return
	var ratio := 0.0 if mx <= 0.0 else clampf(cur / mx, 0.0, 1.0)
	_fill.scale = Vector3(maxf(ratio, 0.001), 1, 1)
	_fill.position = Vector3(-BAR_W * 0.5 + BAR_W * ratio * 0.5, _y_fill, 0.04)

func _process(_delta: float) -> void:
	if _host == null or not is_instance_valid(_host):
		_host = get_parent() as Node3D
	if _host == null:
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	var board_c := Vector3(
		float(DataStore.visual.get("board_center_x", 0.0)),
		float(DataStore.visual.get("board_center_y", 0.0)),
		float(DataStore.visual.get("board_center_z", 0.0))
	)
	var axis: Vector3 = cam.global_position - board_c
	if axis.length_squared() < 0.0001:
		axis = Vector3(0, 1, 0)
	else:
		axis = axis.normalized()
	var mul := float(DataStore.visual.get("health_bar_view_distance_mul", 2.0))
	global_position = _host.global_position + axis * (_base_offset * mul)
	var to_cam: Vector3 = cam.global_position - global_position
	to_cam.y = 0.0
	if to_cam.length_squared() > 0.0001:
		look_at(global_position + to_cam.normalized(), Vector3.UP)
