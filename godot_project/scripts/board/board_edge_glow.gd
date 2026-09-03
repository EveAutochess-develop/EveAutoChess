extends Node3D
class_name BoardEdgeGlow

## Continuous inner-cylinder proximity glow during Battle (BOARD_AND_INPUT §2.2c).

const MAX_SHIPS: int = 48
const TICK_INTERVAL_S: float = 0.05
const CAP_THICKNESS: float = 0.06

const SURFACE_SIDE: int = 0
const SURFACE_TOP: int = 1

var _board: BoardController = null
var _active: bool = false
var _acc: float = 0.0
var _side_mi: MeshInstance3D = null
var _top_mi: MeshInstance3D = null
var _shader: Shader = null


func setup(board: BoardController) -> void:
	_board = board
	if _shader == null:
		_shader = load("res://shaders/board_edge_glow.gdshader") as Shader
	_rebuild_mesh()


func set_active(v: bool) -> void:
	_active = v and _edge_glow_enabled()
	visible = _active


func _edge_glow_enabled() -> bool:
	return TypedVariant.as_bool(DataStore.visual.get("board_edge_glow_enabled", true), true)


func _rebuild_mesh() -> void:
	for child: Node in get_children():
		child.queue_free()
	_side_mi = null
	_top_mi = null
	if _shader == null:
		return
	var r_disk: float = BoardPolarGrid.play_radius()
	var y_band: Vector2 = BoardController.play_volume_y()
	var y_lo: float = y_band.x
	var y_hi: float = y_band.y
	var shell_h: float = maxf(y_hi - y_lo, 0.5)
	var y_mid: float = (y_lo + y_hi) * 0.5

	_side_mi = _make_shell_mesh(
		"SideWall",
		_make_cylinder_tube(r_disk, shell_h),
		Vector3(0.0, y_mid, 0.0),
		SURFACE_SIDE,
		r_disk,
		y_lo,
		y_hi
	)
	_top_mi = _make_shell_mesh(
		"TopCap",
		_make_cap_disk(r_disk),
		Vector3(0.0, y_hi, 0.0),
		SURFACE_TOP,
		r_disk,
		y_lo,
		y_hi
	)


func _make_cylinder_tube(radius: float, height: float) -> CylinderMesh:
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = maxi(48, ceili(BoardPolarGrid.play_diameter() / BoardPolarGrid.cell_step_wu()))
	cyl.cap_top = false
	cyl.cap_bottom = false
	return cyl


func _make_cap_disk(radius: float) -> CylinderMesh:
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = CAP_THICKNESS
	cyl.radial_segments = maxi(48, ceili(BoardPolarGrid.play_diameter() / BoardPolarGrid.cell_step_wu()))
	cyl.cap_top = true
	cyl.cap_bottom = true
	return cyl


func _make_shell_mesh(
	node_name: String,
	mesh: Mesh,
	pos: Vector3,
	surface_kind: int,
	r_disk: float,
	y_lo: float,
	y_hi: float
) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("surface_kind", surface_kind)
	_apply_static_uniforms(mat, r_disk, y_lo, y_hi)
	mi.material_override = mat
	add_child(mi)
	return mi


func _apply_static_uniforms(mat: ShaderMaterial, r_disk: float, y_lo: float, y_hi: float) -> void:
	var vis: Dictionary = DataStore.visual
	mat.set_shader_parameter("play_radius", r_disk)
	mat.set_shader_parameter("y_min", y_lo)
	mat.set_shader_parameter("y_max", y_hi)
	mat.set_shader_parameter(
		"peak_alpha",
		TypedVariant.as_float(vis.get("board_edge_glow_peak_alpha", 0.08), 0.08)
	)
	mat.set_shader_parameter(
		"fade_cells",
		TypedVariant.as_float(vis.get("board_edge_glow_fade_cells", 1.0), 1.0)
	)
	mat.set_shader_parameter(
		"glow_color",
		Color(
			TypedVariant.as_float(vis.get("board_edge_glow_color_r", 0.3), 0.3),
			TypedVariant.as_float(vis.get("board_edge_glow_color_g", 0.85), 0.85),
			TypedVariant.as_float(vis.get("board_edge_glow_color_b", 1.0), 1.0),
			1.0
		)
	)


func _all_shell_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for mi: MeshInstance3D in [_side_mi, _top_mi]:
		if mi != null and is_instance_valid(mi) and mi.material_override is ShaderMaterial:
			out.append(mi.material_override as ShaderMaterial)
	return out


func tick_glow(sim_dt: float) -> void:
	if not _active or _board == null or not _edge_glow_enabled():
		return
	_acc += sim_dt
	if _acc < TICK_INTERVAL_S:
		return
	_acc = 0.0
	var spheres: PackedVector4Array = PackedVector4Array()
	for s: ShipUnit in _board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		if s.slot_type != "field":
			continue
		var center: Vector3 = s.visual_center_world()
		var ship_r: float = s.visual_radius_world()
		if ship_r <= 1e-4:
			continue
		spheres.append(Vector4(center.x, center.y, center.z, ship_r))
		if spheres.size() >= MAX_SHIPS:
			break
	while spheres.size() < MAX_SHIPS:
		spheres.append(Vector4.ZERO)
	var r_disk: float = BoardPolarGrid.play_radius()
	var y_band: Vector2 = BoardController.play_volume_y()
	for mat: ShaderMaterial in _all_shell_materials():
		mat.set_shader_parameter("ship_count", spheres.size())
		mat.set_shader_parameter("ship_spheres", spheres)
		_apply_static_uniforms(mat, r_disk, y_band.x, y_band.y)
