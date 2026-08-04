extends Node3D
## Titan life = three flat pipes (shield / armor / structure). MULTIPLAYER_PVP §2.4.
## Independent of ship health_bar_style (ring/bars). No capacitor — titans do not enter the field.

const BAR_W: float = 7.2
const BAR_H: float = 0.42
## Edge-to-edge gap between pipes (centers spaced BAR_H + GAP).
const GAP: float = 0.28
const PIPE_COUNT: int = 3
const COL_SHIELD: Color = Color(0.35, 0.7, 1.0, 0.95)
const COL_ARMOR: Color = Color(0.95, 0.78, 0.3, 0.95)
const COL_STRUCT: Color = Color(0.9, 0.28, 0.24, 0.95)
const COL_TRACK: Color = Color(0.05, 0.06, 0.09, 0.7)

var _fills: Array[MeshInstance3D] = []
var _pipe_ys: PackedFloat32Array = PackedFloat32Array()
var _host: Node3D = null
var _base_offset: float = 9.5


func setup(y_offset: float = 9.5) -> void:
	_host = get_parent() as Node3D
	_base_offset = y_offset
	top_level = true
	_build()


func _build() -> void:
	## Free immediately — queue_free left a one-frame gap where refresh saw empty _fills.
	for c: Node in get_children():
		remove_child(c)
		c.free()
	_fills.clear()
	_pipe_ys = PackedFloat32Array()
	var colors: Array[Color] = [COL_SHIELD, COL_ARMOR, COL_STRUCT]
	## Center the stack on the stern anchor so three pipes stay clearly separated.
	var step: float = BAR_H + GAP
	var y0: float = float(PIPE_COUNT - 1) * step * 0.5
	for i: int in range(PIPE_COUNT):
		var y: float = y0 - float(i) * step
		_pipe_ys.append(y)
		var track: MeshInstance3D = _make_box(COL_TRACK)
		track.position = Vector3(0, y, 0)
		add_child(track)
		var fill: MeshInstance3D = _make_box(colors[i])
		fill.position = Vector3(0, y, 0.04)
		add_child(fill)
		_fills.append(fill)


func _make_box(col: Color) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(BAR_W, BAR_H, 0.08)
	mi.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	## look_at billboards can flip the thin box; never cull the face.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 8
	mi.material_override = mat
	return mi


func refresh(pipes: TitanHpPipes) -> void:
	if pipes == null or _fills.size() < PIPE_COUNT:
		return
	visible = true
	_set_pipe(0, float(pipes.shield), float(pipes.shield_max))
	_set_pipe(1, float(pipes.armor), float(pipes.armor_max))
	_set_pipe(2, float(pipes.structure), float(pipes.structure_max))


func _set_pipe(idx: int, cur: float, mx: float) -> void:
	var fill: MeshInstance3D = _fills[idx]
	var y: float = _pipe_ys[idx] if idx < _pipe_ys.size() else fill.position.y
	var ratio: float = 0.0 if mx <= 0.0 else clampf(cur / mx, 0.0, 1.0)
	fill.scale = Vector3(maxf(ratio, 0.001), 1, 1)
	fill.position = Vector3(-BAR_W * 0.5 + BAR_W * ratio * 0.5, y, 0.04)


func _anchor() -> Vector3:
	if _host != null and _host.has_method("stern_top_point"):
		var v: Variant = _host.call("stern_top_point")
		if v is Vector3:
			@warning_ignore("unsafe_cast")
			return v as Vector3
	if _host != null:
		return _host.global_position
	return global_position


func _process(_delta: float) -> void:
	if _host == null or not is_instance_valid(_host):
		_host = get_parent() as Node3D
	if _host == null:
		return
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam == null:
		return
	global_position = _anchor() + Vector3.UP * _base_offset
	if cam.global_position.distance_squared_to(global_position) > 0.0001:
		look_at(cam.global_position, Vector3.UP)
