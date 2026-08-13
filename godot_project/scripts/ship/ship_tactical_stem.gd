extends Node3D
class_name ShipTacticalStem
## Pseudo-tactical view: vertical stem from model center to board XZ + foot disc (UI_AND_SHELL §2.7).

const STEM_RADIUS: float = 0.006
const STEM_ALPHA: float = 0.35
## Foot disc: alpha 0.20; diameter = hex_edge × (1/3) × (2/3) (UI_AND_SHELL §2.7).
const DISC_ALPHA: float = 0.20
const DISC_DIAMETER_FRAC: float = (1.0 / 3.0) * (2.0 / 3.0)

var _line: MeshInstance3D
var _disc: MeshInstance3D
var _board_y: float = BoardController.DECK_Y

func setup(board_y: float = -1.0) -> void:
	_board_y = BoardController.DECK_Y if board_y < 0.0 else board_y
	_ensure_meshes()

func _hex_edge_length() -> float:
	## Pointy-top regular hex: side length == circumradius.
	return BoardController.field_hex_circumradius()

func _disc_diameter() -> float:
	return maxf(0.05, _hex_edge_length()) * DISC_DIAMETER_FRAC

func _ensure_meshes() -> void:
	var disc_d: float = _disc_diameter()
	if _line == null or not is_instance_valid(_line):
		_line = MeshInstance3D.new()
		_line.name = "TacticalStemLine"
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = STEM_RADIUS
		cyl.bottom_radius = STEM_RADIUS
		cyl.height = 1.0
		cyl.radial_segments = 6
		_line.mesh = cyl
		var mat_l: StandardMaterial3D = StandardMaterial3D.new()
		mat_l.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat_l.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_l.albedo_color = Color(1, 1, 1, STEM_ALPHA)
		mat_l.no_depth_test = true
		mat_l.render_priority = 8
		_line.material_override = mat_l
		add_child(_line)
	if _disc == null or not is_instance_valid(_disc):
		_disc = MeshInstance3D.new()
		_disc.name = "TacticalStemDisc"
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = disc_d * 0.5
		sphere.height = disc_d * 0.08
		sphere.radial_segments = 16
		sphere.rings = 4
		_disc.mesh = sphere
		var mat_d: StandardMaterial3D = StandardMaterial3D.new()
		mat_d.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat_d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_d.albedo_color = Color(1, 1, 1, DISC_ALPHA)
		## Occluded by hulls / battlefield FX (UI_AND_SHELL §2.7).
		mat_d.no_depth_test = false
		mat_d.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat_d.render_priority = 0
		_disc.material_override = mat_d
		add_child(_disc)
	else:
		@warning_ignore("unsafe_cast")
		var sm: SphereMesh = _disc.mesh as SphereMesh
		if sm != null:
			sm.radius = disc_d * 0.5
			sm.height = disc_d * 0.08
		@warning_ignore("unsafe_cast")
		var mat_u: StandardMaterial3D = _disc.material_override as StandardMaterial3D
		if mat_u != null:
			mat_u.albedo_color = Color(1, 1, 1, DISC_ALPHA)

func sync_to_ship(ship: Node3D) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	_ensure_meshes()
	## Anchor = model center projected onto board XZ; direction = world vertical
	## (UI_AND_SHELL §2.7) — never ship-local down (hull rotates / soft-follows).
	var center: Vector3 = ship.global_position
	if ship is ShipUnit:
		@warning_ignore("unsafe_cast")
		center = (ship as ShipUnit).model_center_world()
	elif ship.has_method("model_center_world"):
		center = TypedVariant.as_vector3(ship.call("model_center_world"), center)
	var foot_y: float = _board_y
	var h: float = maxf(0.05, absf(center.y - foot_y))
	## Detach from parent transform so yaw/pitch/roll never tilts the stem.
	top_level = true
	global_transform = Transform3D(Basis.IDENTITY, Vector3(center.x, foot_y, center.z))
	if _line:
		_line.position = Vector3(0, h * 0.5, 0)
		_line.scale = Vector3(1, h, 1)
		_line.rotation = Vector3.ZERO
	if _disc:
		_disc.position = Vector3(0, 0.01, 0)
		_disc.rotation = Vector3.ZERO

func set_visible_stem(v: bool) -> void:
	visible = v
