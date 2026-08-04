extends Node3D
## Single structure HP bar for player citadel. Anchored above citadel (world-up).

const BAR_W: float = 5.6
const BAR_H: float = 0.32
const COLOR: Color = Color(0.9, 0.22, 0.2, 0.95)
const BG: Color = Color(0.08, 0.08, 0.1, 0.0)

var _fill: MeshInstance3D
var _y_fill: float = 0.0
var _host: Node3D = null
var _base_offset: float = 9.5

func setup(y_offset: float = 9.5) -> void:
	_host = get_parent() as Node3D
	_base_offset = y_offset
	top_level = true
	_build()
	refresh(1.0, 1.0)

func _build() -> void:
	for c: Node in get_children():
		c.queue_free()
	var bg: MeshInstance3D = _make_box(BG)
	bg.position = Vector3(0, 0, 0)
	add_child(bg)
	_fill = _make_box(COLOR)
	_y_fill = 0.0
	_fill.position = Vector3(0, 0, 0.04)
	add_child(_fill)

func _make_box(col: Color) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(BAR_W, BAR_H, 0.08)
	mi.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 8
	mi.material_override = mat
	return mi

func refresh(cur: float, mx: float) -> void:
	if _fill == null:
		return
	var ratio: float = 0.0 if mx <= 0.0 else clampf(cur / mx, 0.0, 1.0)
	_fill.scale = Vector3(maxf(ratio, 0.001), 1, 1)
	_fill.position = Vector3(-BAR_W * 0.5 + BAR_W * ratio * 0.5, _y_fill, 0.04)

func _process(_delta: float) -> void:
	if _host == null or not is_instance_valid(_host):
		_host = get_parent() as Node3D
	if _host == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	global_position = _host.global_position + Vector3.UP * _base_offset
	if cam.global_position.distance_squared_to(global_position) > 0.0001:
		look_at(cam.global_position, Vector3.UP)
