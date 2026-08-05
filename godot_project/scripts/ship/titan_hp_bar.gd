extends Node3D
## Titan life = three flat pipes (shield / armor / structure). MULTIPLAYER_PVP §2.4 / §2.4a.
## Board-flat on XZ; RGB × 0.80; fill-only (no track underlay).

const PIPE_COUNT: int = 3
const PIPE_H: float = 0.28
const PIPE_GAP: float = 0.12
const PIPE_THICK: float = 0.06
const HANGAR_CELLS: int = 5
const BRIGHTNESS: float = 0.80
const COL_SHIELD: Color = Color(0.35 * BRIGHTNESS, 0.7 * BRIGHTNESS, 1.0 * BRIGHTNESS, 0.88)
const COL_ARMOR: Color = Color(0.95 * BRIGHTNESS, 0.78 * BRIGHTNESS, 0.3 * BRIGHTNESS, 0.88)
const COL_STRUCT: Color = Color(0.9 * BRIGHTNESS, 0.28 * BRIGHTNESS, 0.24 * BRIGHTNESS, 0.88)

var _fills: Array[MeshInstance3D] = []
var _pipe_z: PackedFloat32Array = PackedFloat32Array()
var _team: int = ShipUnit.TEAM_PLAYER
var _bar_w: float = 7.2
var _laid_out: bool = false


func setup(team: int = ShipUnit.TEAM_PLAYER, _legacy_margin: float = 0.0) -> void:
	_team = team
	top_level = true
	_layout_from_hangar()
	_build()


func _layout_from_hangar() -> void:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board) if DataStore else {}
	var hw: int = maxi(HANGAR_CELLS, TypedVariant.as_int(b.get("hangar_width", 15), 15))
	var mid0: int = int((hw - HANGAR_CELLS) / 2)
	var mid1: int = mid0 + HANGAR_CELLS - 1
	var p0: Vector3 = BoardController.cell_to_world("hangar", _team, mid0, 0)
	var p1: Vector3 = BoardController.cell_to_world("hangar", _team, mid1, 0)
	_bar_w = maxf(absf(p1.x - p0.x), 1.0)
	var center: Vector3 = (p0 + p1) * 0.5
	var out_wu: float = TypedVariant.as_float(
		DataStore.visual.get("titan_hp_bar_hangar_out_wu", 1.35) if DataStore else 1.35,
		1.35
	)
	var y_lift: float = TypedVariant.as_float(
		DataStore.visual.get("titan_hp_bar_board_y", 0.12) if DataStore else 0.12,
		0.12
	)
	var z_sign: float = 1.0 if _team == ShipUnit.TEAM_PLAYER else -1.0
	center.z += z_sign * out_wu
	center.y = y_lift
	global_position = center
	global_rotation = Vector3.ZERO
	_laid_out = true


func _build() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.free()
	_fills.clear()
	_pipe_z = PackedFloat32Array()
	var colors: Array[Color] = [COL_SHIELD, COL_ARMOR, COL_STRUCT]
	var step: float = PIPE_H + PIPE_GAP
	var z_sign: float = 1.0 if _team == ShipUnit.TEAM_PLAYER else -1.0
	var z0: float = -float(PIPE_COUNT - 1) * step * 0.5
	for i: int in range(PIPE_COUNT):
		var z: float = (z0 + float(i) * step) * z_sign
		_pipe_z.append(z)
		var fill: MeshInstance3D = _make_pipe(colors[i])
		fill.position = Vector3(0, 0.01, z)
		add_child(fill)
		_fills.append(fill)


func _make_pipe(col: Color) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(_bar_w, PIPE_THICK, PIPE_H)
	mi.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 8
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func refresh(pipes: TitanHpPipes) -> void:
	if pipes == null:
		return
	if not _laid_out:
		_layout_from_hangar()
	if _fills.size() < PIPE_COUNT:
		_build()
	if _fills.size() < PIPE_COUNT:
		return
	visible = true
	_set_pipe(0, float(pipes.shield), float(pipes.shield_max), COL_SHIELD)
	_set_pipe(1, float(pipes.armor), float(pipes.armor_max), COL_ARMOR)
	_set_pipe(2, float(pipes.structure), float(pipes.structure_max), COL_STRUCT)


func _set_pipe(idx: int, cur: float, mx: float, col: Color) -> void:
	var fill: MeshInstance3D = _fills[idx]
	var z: float = _pipe_z[idx] if idx < _pipe_z.size() else fill.position.z
	var ratio: float = 0.0 if mx <= 0.0 else clampf(cur / mx, 0.0, 1.0)
	fill.scale = Vector3(maxf(ratio, 0.001), 1.0, 1.0)
	fill.position = Vector3(-_bar_w * 0.5 + _bar_w * ratio * 0.5, 0.01, z)
	_set_mat_color(fill, col)


func _set_mat_color(mi: MeshInstance3D, col: Color) -> void:
	if mi == null:
		return
	var mat: Material = mi.material_override
	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).albedo_color = col


func _process(_delta: float) -> void:
	if not _laid_out:
		_layout_from_hangar()
