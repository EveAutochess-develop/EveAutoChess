extends Node3D
## Three-pipe titan HP bar above the berth (MULTIPLAYER_PVP §2.4 shield/armor/structure).
## Billboards toward the active camera like the citadel bar it replaces in nullsec.

const BAR_W := 7.2
const BAR_H := 0.34
const GAP := 0.12
const COL_SHIELD := Color(0.35, 0.7, 1.0, 0.95)
const COL_ARMOR := Color(0.95, 0.78, 0.3, 0.95)
const COL_STRUCT := Color(0.9, 0.28, 0.24, 0.95)
const COL_TRACK := Color(0.05, 0.06, 0.09, 0.7)

var _fills: Array[MeshInstance3D] = []
var _host: Node3D = null
var _base_offset: float = 9.5

func setup(y_offset: float = 9.5) -> void:
	_host = get_parent() as Node3D
	_base_offset = y_offset
	top_level = true
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_fills.clear()
	var colors: Array[Color] = [COL_SHIELD, COL_ARMOR, COL_STRUCT]
	for i in range(colors.size()):
		var y := float(colors.size() - 1 - i) * (BAR_H + GAP)
		var track := _make_box(COL_TRACK)
		track.position = Vector3(0, y, 0)
		add_child(track)
		var fill := _make_box(colors[i])
		fill.position = Vector3(0, y, 0.04)
		add_child(fill)
		_fills.append(fill)

func _make_box(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BAR_W, BAR_H, 0.08)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	## Match field ship bars: look_at billboards can flip the thin box; never cull the face.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 8
	mi.material_override = mat
	return mi

func refresh(pipes: TitanHpPipes) -> void:
	if pipes == null or _fills.size() < 3:
		return
	visible = true
	_set_pipe(0, float(pipes.shield), float(pipes.shield_max))
	_set_pipe(1, float(pipes.armor), float(pipes.armor_max))
	_set_pipe(2, float(pipes.structure), float(pipes.structure_max))

func _set_pipe(idx: int, cur: float, mx: float) -> void:
	var fill := _fills[idx]
	var y := fill.position.y
	var ratio := 0.0 if mx <= 0.0 else clampf(cur / mx, 0.0, 1.0)
	fill.scale = Vector3(maxf(ratio, 0.001), 1, 1)
	fill.position = Vector3(-BAR_W * 0.5 + BAR_W * ratio * 0.5, y, 0.04)

## Berth hosts anchor the pipes over the stern; anything else keeps origin+offset.
func _anchor() -> Vector3:
	if _host.has_method("stern_top_point"):
		return _host.call("stern_top_point")
	return _host.global_position


func _process(_delta: float) -> void:
	if _host == null or not is_instance_valid(_host):
		_host = get_parent() as Node3D
	if _host == null:
		return
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null:
		return
	global_position = _anchor() + Vector3.UP * _base_offset
	if cam.global_position.distance_squared_to(global_position) > 0.0001:
		look_at(cam.global_position, Vector3.UP)
