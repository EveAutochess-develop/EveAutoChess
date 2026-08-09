extends Node3D
class_name BoardController

## Deck plane y used by combat manned hulls (BOARD §2 / COMBAT).
const DECK_Y: float = 0.2

signal board_changed()

var _ships: Array[ShipUnit] = []
var _field_occupied: Dictionary = {}  # "team_x_z" -> ShipUnit
var _hangar_occupied: Dictionary = {}
## team -> titan race key; drives the always-on titan fetter (MULTIPLAYER_PVP §2.3).
var _titan_fetter_race: Dictionary = {}
var _prepare_mode: bool = true
var _drag_ship: ShipUnit = null
var _world_root: Node3D = null
var _markers: Node3D = null
var _field_markers: Node3D = null
var _hangar_markers: Node3D = null
var _boundary_markers: Node3D = null

func setup(world_root: Node3D) -> void:
	_world_root = world_root
	if _markers != null and is_instance_valid(_markers):
		_markers.queue_free()
	if _boundary_markers != null and is_instance_valid(_boundary_markers):
		_boundary_markers.queue_free()
	_markers = Node3D.new()
	_markers.name = "Markers"
	_world_root.add_child(_markers)
	_field_markers = Node3D.new()
	_field_markers.name = "FieldMarkers"
	_markers.add_child(_field_markers)
	_hangar_markers = Node3D.new()
	_hangar_markers.name = "HangarMarkers"
	_markers.add_child(_hangar_markers)
	_boundary_markers = Node3D.new()
	_boundary_markers.name = "BoundaryMarkers"
	_world_root.add_child(_boundary_markers)
	_boundary_markers.visible = false
	_build_slot_markers()
	AdminBus.register_handler(&"board.deploy", _on_deploy)
	AdminBus.register_handler(&"board.move", _on_move)
	AdminBus.register_handler(&"board.sell", _on_sell)

func get_world_root() -> Node3D:
	return _world_root

func reset_match() -> void:
	for s: ShipUnit in _ships:
		if is_instance_valid(s):
			s.queue_free()
	_ships.clear()
	_field_occupied.clear()
	_hangar_occupied.clear()
	_drag_ship = null
	board_changed.emit()

func set_prepare_mode(v: bool) -> void:
	_prepare_mode = v
	## Prepare: show field hexes. Hangar blue frames stay visible in Battle too.
	if v:
		set_field_markers_visible(true)
		set_hangar_markers_visible(true)
	if not v and _drag_ship:
		_cancel_drag()

func set_field_markers_visible(v: bool) -> void:
	if _field_markers:
		_field_markers.visible = v
	if _boundary_markers:
		_boundary_markers.visible = false

func set_hangar_markers_visible(v: bool) -> void:
	if _hangar_markers:
		_hangar_markers.visible = v

func set_slot_markers_visible(v: bool) -> void:
	## Legacy: toggles Field only when hiding (Battle); show restores both.
	set_field_markers_visible(v)
	if v:
		set_hangar_markers_visible(true)

func slot_markers_visible() -> bool:
	return _field_markers != null and _field_markers.visible

func _build_slot_markers() -> void:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var fh: int = TypedVariant.as_int(b.get("field_height", 6), 6)
	var hexa_path: String = "res://assets/models/env/Models_indicator_hexa.glb"
	var square_path: String = "res://assets/models/env/Models_indicator_square.glb"
	var hexa_ps: PackedScene = load(hexa_path) if ResourceLoader.exists(hexa_path) else null
	var square_ps: PackedScene = load(square_path) if ResourceLoader.exists(square_path) else null
	for team: int in [ShipUnit.TEAM_PLAYER, ShipUnit.TEAM_AI]:
		for z: int in range(fh):
			var cols: int = field_cols_at(z)
			for x: int in range(cols):
				var m: Node3D = _make_indicator(hexa_ps, true)
				m.position = cell_to_world("field", team, x, z)
				_field_markers.add_child(m)
				var is_edge: bool = x == 0 or x == cols - 1 or z == 0 or z == fh - 1
				if is_edge and _boundary_markers:
					var bm: Node3D = _make_indicator(hexa_ps, true)
					bm.position = cell_to_world("field", team, x, z)
					_boundary_markers.add_child(bm)
		var hw: int = TypedVariant.as_int(b.get("hangar_width", 15), 15)
		for x: int in range(hw):
			var m2: Node3D = _make_indicator(square_ps, false)
			m2.position = cell_to_world("hangar", team, x, 0)
			_hangar_markers.add_child(m2)
			var is_edge_h: bool = x == 0 or x == hw - 1
			if is_edge_h and _boundary_markers:
				var bm2: Node3D = _make_indicator(square_ps, false)
				bm2.position = cell_to_world("hangar", team, x, 0)
				_boundary_markers.add_child(bm2)

func _make_indicator(packed: PackedScene, is_hexa: bool) -> Node3D:
	## Visual: hollow outline GLB only (filled disks looked wrong).
	## Pick volume is separate solid hex/square math in pick_slot_by_ray (BOARD_AND_INPUT §4).
	var root: Node3D = Node3D.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.95, 0.85, 0.85) if is_hexa else Color(0.35, 0.65, 1.0, 0.88)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Keep board markers always bright regardless of scene lighting.
	mat.disable_ambient_light = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 0.65) if is_hexa else Color(0.25, 0.45, 0.85)
	mat.emission_energy_multiplier = 1.0
	## Depth-test against opaque ships so hulls occlude hex/hangar frames.
	## Do NOT DEPTH_DRAW_ALWAYS / raise render_priority — that draws frames through ships.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 0
	## Slight lift (below) avoids ground z-fight; keep low so ships sit above frames.
	if packed:
		var n: Node3D = packed.instantiate() as Node3D
		if n:
			root.add_child(n)
			var aabb: AABB = _aabb_in_root_space(n)
			var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
			if longest > 0.001:
				n.scale = Vector3.ONE * (1.2 / longest)
			aabb = _aabb_in_root_space(n)
			var s: Vector3 = n.scale
			var center: Vector3 = aabb.get_center()
			n.position.x -= center.x * s.x
			n.position.z -= center.z * s.z
			n.position.y -= aabb.position.y * s.y
			n.position.y += 0.06
			_tint_meshes(n, mat)
			# Do NOT run MobileModelLoad on slot outlines: thin frames lose edges under decimation.
			return root
	# Fallback hollow ring / frame (not solid fill)
	root.add_child(_make_hollow_fallback(mat, is_hexa))
	return root

func _make_hollow_fallback(mat: Material, is_hexa: bool) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	if is_hexa:
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.48
		torus.outer_radius = 0.56
		torus.rings = 6
		torus.ring_segments = 12
		mi.mesh = torus
		mi.rotation_degrees = Vector3(90, 0, 0)
	else:
		mi.mesh = _square_frame_mesh(1.05, 0.08, 0.03)
	mi.material_override = mat
	mi.position.y = 0.06
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi

func _square_frame_mesh(outer: float, thickness: float, height: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hout: float = outer * 0.5
	var tin: float = hout - thickness
	var segs: Array = [
		[Vector3(-hout, 0, -hout), Vector3(hout, 0, -hout), Vector3(hout, 0, -tin), Vector3(-hout, 0, -tin)],
		[Vector3(-hout, 0, tin), Vector3(hout, 0, tin), Vector3(hout, 0, hout), Vector3(-hout, 0, hout)],
		[Vector3(-hout, 0, -tin), Vector3(-tin, 0, -tin), Vector3(-tin, 0, tin), Vector3(-hout, 0, tin)],
		[Vector3(tin, 0, -tin), Vector3(hout, 0, -tin), Vector3(hout, 0, tin), Vector3(tin, 0, tin)],
	]
	for quad: Array in segs:
		var a: Vector3 = quad[0]
		var b: Vector3 = quad[1]
		var c: Vector3 = quad[2]
		var d: Vector3 = quad[3]
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
		var a2: Vector3 = a + Vector3(0, height, 0)
		var b2: Vector3 = b + Vector3(0, height, 0)
		var c2: Vector3 = c + Vector3(0, height, 0)
		var d2: Vector3 = d + Vector3(0, height, 0)
		st.add_vertex(a2); st.add_vertex(c2); st.add_vertex(b2)
		st.add_vertex(a2); st.add_vertex(d2); st.add_vertex(c2)
	st.generate_normals()
	return st.commit()

func _tint_meshes(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.material_override = mat
		# Hard-disable lighting side effects on board visuals.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for c: Node in node.get_children():
		_tint_meshes(c, mat)

func _aabb_in_root_space(root: Node3D) -> AABB:
	## Local-transform AABB (works before root is in the tree — global_transform is identity then).
	var result: AABB = AABB()
	var first: bool = true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while stack.size() > 0:
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform3D = item[1]
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			var local_aabb: AABB = mi.get_aabb()
			for i: int in range(8):
				var p: Vector3 = xf * local_aabb.get_endpoint(i)
				if first:
					result = AABB(p, Vector3.ZERO)
					first = false
				else:
					result = result.expand(p)
		for c: Node in n.get_children():
			var child_xf: Transform3D = xf
			if c is Node3D and c != root:
				child_xf = xf * (c as Node3D).transform
			elif c is Node3D and n == root:
				child_xf = (c as Node3D).transform
			stack.append([c, child_xf])
	return result

static func field_cols_at(z: int) -> int:
	## Even rows: field_width. Odd rows: +field_odd_row_extra (default 1) so L/R zigzag phase matches.
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var fw: int = TypedVariant.as_int(b.get("field_width", 12), 12)
	var extra: int = TypedVariant.as_int(b.get("field_odd_row_extra", 1), 1)
	if z % 2 == 1:
		return fw + extra
	return fw

static func field_origin(team: int) -> Vector3:
	## Rows self-center on world X=0; origin only carries half-field Z (and overrides).
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var fh: int = TypedVariant.as_int(b.get("field_height", 6), 6)
	var hoz: float = absf(TypedVariant.as_float(b.get("hex_offset_z", -2.5), -2.5))
	var gap: float = TypedVariant.as_float(b.get("center_gap_z", 1.25), 1.25)
	var ox: float = 0.0
	var oz: float = (fh - 1) * hoz + gap
	if team == ShipUnit.TEAM_AI:
		if b.has("ai_origin_x"):
			ox = TypedVariant.as_float(b.get("ai_origin_x", 0.0), 0.0)
		if b.has("ai_origin_z"):
			oz = TypedVariant.as_float(b.get("ai_origin_z", 0.0), 0.0)
		else:
			oz = -oz
	else:
		if b.has("player_origin_x"):
			ox = TypedVariant.as_float(b.get("player_origin_x", 0.0), 0.0)
		if b.has("player_origin_z"):
			oz = TypedVariant.as_float(b.get("player_origin_z", 0.0), 0.0)
	return Vector3(ox, 0.0, oz)

static func field_span_x() -> float:
	## Widest row (odd row with +1) — player/AI share the same X silhouette.
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var fw: int = TypedVariant.as_int(b.get("field_width", 12), 12)
	var extra: int = TypedVariant.as_int(b.get("field_odd_row_extra", 1), 1)
	var hox: float = absf(TypedVariant.as_float(b.get("hex_offset_x", -3.0), -3.0))
	var widest: int = fw + maxi(0, extra)
	return float(widest - 1) * hox

static func hangar_step_x() -> float:
	## Default: span matches Field silhouette so Hangar edges align with hex outer tips.
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	if b.has("hangar_offset_x"):
		return TypedVariant.as_float(b.get("hangar_offset_x", 0.0), 0.0)
	var hw: int = maxi(2, TypedVariant.as_int(b.get("hangar_width", 15), 15))
	return -field_span_x() / float(hw - 1)

static func hangar_origin(team: int) -> Vector3:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var fo: Vector3 = field_origin(team)
	var hoz: float = absf(TypedVariant.as_float(b.get("hex_offset_z", -2.5), -2.5))
	var half: float = field_span_x() * 0.5
	## Hangar x=0 at Field outer +X (player) / −X (AI) so L/R edges match both half-fields.
	var ox: float = half if team == ShipUnit.TEAM_PLAYER else -half
	ox += fo.x
	var oz: float = fo.z + (hoz if team == ShipUnit.TEAM_PLAYER else -hoz)
	if team == ShipUnit.TEAM_PLAYER:
		if b.has("hangar_origin_x"):
			ox = TypedVariant.as_float(b.get("hangar_origin_x", 0.0), 0.0)
		if b.has("hangar_origin_z"):
			oz = TypedVariant.as_float(b.get("hangar_origin_z", 0.0), 0.0)
	else:
		if b.has("ai_hangar_origin_x"):
			ox = TypedVariant.as_float(b.get("ai_hangar_origin_x", 0.0), 0.0)
		elif b.has("hangar_origin_x"):
			ox = -TypedVariant.as_float(b.get("hangar_origin_x", 0.0), 0.0)
		if b.has("ai_hangar_origin_z"):
			oz = TypedVariant.as_float(b.get("ai_hangar_origin_z", 0.0), 0.0)
		elif b.has("hangar_origin_z"):
			oz = -TypedVariant.as_float(b.get("hangar_origin_z", 0.0), 0.0)
	return Vector3(ox, 0.0, oz)

static func cell_to_world(slot_type: String, team: int, x: int, z: int) -> Vector3:
	## Unity BoardController: origin + right*offsetX + forward*offsetZ (identity axes).
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var ox: float = TypedVariant.as_float(b.get("hex_offset_x", -3.0), -3.0)
	var oz: float = TypedVariant.as_float(b.get("hex_offset_z", -2.5), -2.5)
	var hox_step: float = hangar_step_x()
	var origin: Vector3 = hangar_origin(team) if slot_type == "hangar" else field_origin(team)
	var ox0: float = origin.x
	var oy0: float = origin.y
	var oz0: float = origin.z
	if slot_type == "hangar":
		var step: float = float(x) * hox_step
		if team == ShipUnit.TEAM_AI:
			step = -step
		return Vector3(ox0 + step, oy0, oz0)
	## Each row self-centers on X=0; odd rows have +1 cell → both edges share the same zigzag phase.
	var cols: int = field_cols_at(z)
	var row_left: float = float(cols - 1) * absf(ox) * 0.5
	var offset_x: float = row_left + float(x) * ox
	var offset_z: float = float(z) * oz
	if team == ShipUnit.TEAM_AI:
		offset_x = -offset_x
		offset_z = -offset_z
	return Vector3(ox0 + offset_x, oy0 + 0.05, oz0 + offset_z)

## Axis-aligned playable combat rect in XZ (both team fields + margin). Returns [min_x, max_x, min_z, max_z].
static func combat_play_bounds_xz(margin_wu: float = 0.75) -> Vector4:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var fh: int = TypedVariant.as_int(b.get("field_height", 6), 6)
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for team: int in [ShipUnit.TEAM_PLAYER, ShipUnit.TEAM_AI]:
		for z: int in [0, fh - 1]:
			var cols: int = field_cols_at(z)
			for x: int in [0, cols - 1]:
				var p: Vector3 = cell_to_world("field", team, x, z)
				min_x = minf(min_x, p.x)
				max_x = maxf(max_x, p.x)
				min_z = minf(min_z, p.z)
				max_z = maxf(max_z, p.z)
	return Vector4(min_x - margin_wu, max_x + margin_wu, min_z - margin_wu, max_z + margin_wu)

static func clamp_to_combat_play_area(pos: Vector3, margin_wu: float = 0.75) -> Vector3:
	var bb: Vector4 = combat_play_bounds_xz(margin_wu)
	pos.x = clampf(pos.x, bb.x, bb.y)
	pos.z = clampf(pos.z, bb.z, bb.w)
	return pos


## Vertical play band [y_min, y_max] from hangar cell width × floor/ceiling cells.
static func play_volume_y() -> Vector2:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var step: float = absf(hangar_step_x())
	var floor_cells: float = TypedVariant.as_float(b.get("play_floor_cells", 1), 1.0)
	var ceil_cells: float = TypedVariant.as_float(b.get("play_ceiling_cells", 4), 4.0)
	return Vector2(DECK_Y - floor_cells * step, DECK_Y + ceil_cells * step)


## Manned only: XZ combat bounds + Y fence. Unmanned keep clamp_to_combat_play_area.
static func clamp_to_play_volume(pos: Vector3, margin_wu: float = 0.75) -> Vector3:
	pos = clamp_to_combat_play_area(pos, margin_wu)
	var yy: Vector2 = play_volume_y()
	pos.y = clampf(pos.y, yy.x, yy.y)
	return pos

static func prepare_slot_bounds_xz(slot_type: String, team: int, margin_wu: float = 0.0) -> Vector4:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var fh: int = TypedVariant.as_int(b.get("field_height", 6), 6)
	var hw: int = TypedVariant.as_int(b.get("hangar_width", 15), 15)
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	if slot_type == "field":
		for z: int in range(fh):
			var cols: int = field_cols_at(z)
			for x: int in range(cols):
				var p: Vector3 = cell_to_world("field", team, x, z)
				min_x = minf(min_x, p.x)
				max_x = maxf(max_x, p.x)
				min_z = minf(min_z, p.z)
				max_z = maxf(max_z, p.z)
	else:
		for x: int in range(hw):
			var p2: Vector3 = cell_to_world("hangar", team, x, 0)
			min_x = minf(min_x, p2.x)
			max_x = maxf(max_x, p2.x)
			min_z = minf(min_z, p2.z)
			max_z = maxf(max_z, p2.z)
	return Vector4(min_x - margin_wu, max_x + margin_wu, min_z - margin_wu, max_z + margin_wu)

static func prepare_play_bounds_xz(team: int, margin_wu: float = 0.0) -> Vector4:
	var field_bb: Vector4 = prepare_slot_bounds_xz("field", team, margin_wu)
	var hangar_bb: Vector4 = prepare_slot_bounds_xz("hangar", team, margin_wu)
	return Vector4(
		minf(field_bb.x, hangar_bb.x),
		maxf(field_bb.y, hangar_bb.y),
		minf(field_bb.z, hangar_bb.z),
		maxf(field_bb.w, hangar_bb.w)
	)

static func clamp_to_prepare_slot_area(pos: Vector3, slot_type: String, team: int, margin_wu: float = 0.0) -> Vector3:
	var bb: Vector4 = prepare_slot_bounds_xz(slot_type, team, margin_wu)
	pos.x = clampf(pos.x, bb.x, bb.y)
	pos.z = clampf(pos.z, bb.z, bb.w)
	return pos

static func clamp_to_prepare_play_area(pos: Vector3, team: int, margin_wu: float = 0.0) -> Vector3:
	var bb: Vector4 = prepare_play_bounds_xz(team, margin_wu)
	pos.x = clampf(pos.x, bb.x, bb.y)
	pos.z = clampf(pos.z, bb.z, bb.w)
	return pos

static func _in_bounds(slot_type: String, x: int, z: int = 0) -> bool:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var fh: int = TypedVariant.as_int(b.get("field_height", 6), 6)
	var hw: int = TypedVariant.as_int(b.get("hangar_width", 15), 15)
	if slot_type == "field":
		if z < 0 or z >= fh or x < 0:
			return false
		return x < field_cols_at(z)
	return x >= 0 and x < hw and z == 0

func _key(slot_type: String, team: int, x: int, z: int) -> String:
	return "%s_%d_%d_%d" % [slot_type, team, x, z]

func spawn_ship(ship_id: int, star: int, team: int, slot_type: String, x: int, z: int) -> ShipUnit:
	var ship: ShipUnit = ShipUnit.new()
	_world_root.add_child(ship)
	ship.setup(ship_id, star, team)
	ship.slot_type = slot_type
	ship.grid_x = x
	ship.grid_z = z
	ship.global_position = cell_to_world(slot_type, team, x, z)
	_ships.append(ship)
	if not ship.is_unmanned:
		var occ: Dictionary = _hangar_occupied if slot_type == "hangar" else _field_occupied
		occ[_key(slot_type, team, x, z)] = ship
	if _visual_follow_armed:
		ship.arm_visual_follow()
	board_changed.emit()
	return ship

func spawn_unmanned(ship_id: int, team: int, world_pos: Vector3, mother: ShipUnit, star: int = -1, squadron_id: int = -1) -> ShipUnit:
	var ship: ShipUnit = ShipUnit.new()
	_world_root.add_child(ship)
	var use_star: int = star if star > 0 else (mother.star if mother else 1)
	ship.setup(ship_id, use_star, team)
	ship.slot_type = "field"
	ship.grid_x = mother.grid_x if mother else 0
	ship.grid_z = mother.grid_z if mother else 0
	ship.is_unmanned = true
	ship.unmanned_kind = str(DataStore.get_ship(ship_id).get("unmanned_kind", "combat_drone"))
	ship.mother_ship_id = mother.get_instance_id() if mother else 0
	ship.fighter_squadron_id = squadron_id
	ship.clear_health_bar()
	ship.global_position = world_pos
	_ships.append(ship)
	if _visual_follow_armed:
		ship.arm_visual_follow()
	board_changed.emit()
	return ship

func remove_ship_node(ship: ShipUnit) -> void:
	if ship == null:
		return
	if not ship.is_unmanned:
		var occ: Dictionary = _hangar_occupied if ship.slot_type == "hangar" else _field_occupied
		## Prefer exact key; also scrub any occupancy entry still pointing at this instance.
		occ.erase(_key(ship.slot_type, ship.team_id, ship.grid_x, ship.grid_z))
		var stale: Array = []
		for k: Variant in occ.keys():
			if occ[k] == ship:
				stale.append(k)
		for k2: Variant in stale:
			occ.erase(k2)
	_ships.erase(ship)
	if is_instance_valid(ship):
		ship.visible = false
		ship.queue_free()
	refresh_cross_team_cell_offsets()
	board_changed.emit()


## Free hangar/field cell without freeing the node (scout depart / FX).
func release_ship_occupancy(ship: ShipUnit) -> void:
	if ship == null or ship.is_unmanned:
		return
	if ship.slot_type != "hangar" and ship.slot_type != "field":
		return
	var occ: Dictionary = _hangar_occupied if ship.slot_type == "hangar" else _field_occupied
	occ.erase(_key(ship.slot_type, ship.team_id, ship.grid_x, ship.grid_z))
	var stale: Array = []
	for k: Variant in occ.keys():
		if occ[k] == ship:
			stale.append(k)
	for k2: Variant in stale:
		occ.erase(k2)
	board_changed.emit()

func is_field_cell_free_for(team: int, x: int, z: int) -> bool:
	if not _in_bounds("field", x, z):
		return false
	return not _field_occupied.has(_key("field", team, x, z))


## Dev tool: swap player↔AI ownership; grid indices stay put (board halves are already 180°-mirrored).
func swap_sides_center_symmetric() -> Dictionary:
	if not _prepare_mode:
		return {"ok": false, "reason": "prepare_only"}
	if _drag_ship:
		_cancel_drag()
	var targets: Array = []
	for s: ShipUnit in _ships:
		if s == null or not is_instance_valid(s) or s.is_destroyed or s.is_unmanned:
			continue
		targets.append(s)
	## Drop occupancy first so remaps cannot collide mid-pass.
	for s2: Variant in targets:
		@warning_ignore("unsafe_cast")
		var ship2: ShipUnit = s2 as ShipUnit
		var occ: Dictionary = _hangar_occupied if ship2.slot_type == "hangar" else _field_occupied
		occ.erase(_key(ship2.slot_type, ship2.team_id, ship2.grid_x, ship2.grid_z))
	for s3: Variant in targets:
		@warning_ignore("unsafe_cast")
		var ship3: ShipUnit = s3 as ShipUnit
		var old_team: int = ship3.team_id
		var new_team: int = ShipUnit.TEAM_AI if old_team == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
		ship3.team_id = new_team
		if ship3.slot_type == "field":
			var old_side: int = ship3.field_side_team if ship3.field_side_team >= 0 else old_team
			ship3.field_side_team = (
				ShipUnit.TEAM_AI if old_side == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
			)
		else:
			ship3.field_side_team = new_team
		ship3.restore_team_yaw()
		var place_side: int = ship3.field_side_team if ship3.slot_type == "field" else new_team
		ship3.global_position = cell_to_world(
			ship3.slot_type, place_side, ship3.grid_x, ship3.grid_z
		)
		var occ2: Dictionary = _hangar_occupied if ship3.slot_type == "hangar" else _field_occupied
		occ2[_key(ship3.slot_type, new_team, ship3.grid_x, ship3.grid_z)] = ship3
		if ship3.has_method("rebuild_health_bar"):
			ship3.rebuild_health_bar()
	refresh_cross_team_cell_offsets(true)
	recalculate_fetters(ShipUnit.TEAM_PLAYER)
	recalculate_fetters(ShipUnit.TEAM_AI)
	board_changed.emit()
	return {"ok": true, "count": targets.size()}


func move_ship_to_field_side(ship: ShipUnit, x: int, z: int, side_team: int) -> void:
	## Place hangar/field ship onto field at (x,z) using side_team world coords (cyno warp).
	if ship == null:
		return
	var occ_from: Dictionary = _hangar_occupied if ship.slot_type == "hangar" else _field_occupied
	occ_from.erase(_key(ship.slot_type, ship.team_id, ship.grid_x, ship.grid_z))
	ship.slot_type = "field"
	ship.grid_x = x
	ship.grid_z = z
	ship.field_side_team = side_team
	ship.global_position = cell_to_world("field", side_team, x, z)
	_field_occupied[_key("field", ship.team_id, x, z)] = ship
	refresh_cross_team_cell_offsets()
	board_changed.emit()


func release_field_occupancy(ship: ShipUnit) -> void:
	## Free the ship's current field/hangar occupancy key without freeing the node (AI reshuffle).
	if ship == null or not is_instance_valid(ship):
		return
	var occ: Dictionary = _hangar_occupied if ship.slot_type == "hangar" else _field_occupied
	occ.erase(_key(ship.slot_type, ship.team_id, ship.grid_x, ship.grid_z))


func ship_world_side(ship: ShipUnit) -> int:
	if ship == null:
		return ShipUnit.TEAM_PLAYER
	if ship.field_side_team >= 0:
		return ship.field_side_team
	return ship.team_id


## Cross-team same world cell (e.g. cyno on enemy half): shift player −X / AI +X to avoid clip.
## `force_all`: snap every ship in the cell (combat open / prepare). Else only pinned/cyno.
func refresh_cross_team_cell_offsets(force_all: bool = false) -> void:
	_purge_freed_ships()
	var lateral: float = TypedVariant.as_float(DataStore.combat.get("cell_overlap_lateral_wu", 0.55), 0.55) if DataStore else 0.55
	lateral = maxf(0.0, lateral)
	## key "side_x_z" -> Array[ShipUnit]
	var groups: Dictionary = {}
	for s_any: Variant in (_ships as Array):
		if s_any == null or not is_instance_valid(s_any):
			continue
		var s: ShipUnit = s_any
		if s.is_destroyed:
			continue
		if s.slot_type != "field" or s.is_unmanned:
			continue
		var side: int = ship_world_side(s)
		var k: String = "%d_%d_%d" % [side, s.grid_x, s.grid_z]
		if not groups.has(k):
			groups[k] = []
		@warning_ignore("unsafe_cast")
		var bucket: Array = groups[k] as Array
		bucket.append(s)
	for k2: Variant in groups.keys():
		var members: Array = groups[k2]
		var teams: Dictionary = {}
		for m: Variant in members:
			if m == null or not is_instance_valid(m):
				continue
			var sh: ShipUnit = m
			teams[sh.team_id] = true
		var overlap: bool = teams.size() >= 2 and members.size() >= 2
		for m2: Variant in members:
			if m2 == null or not is_instance_valid(m2):
				continue
			var ship: ShipUnit = m2
			var pinned: bool = (
				ship.immobile_in_combat
				or ship.has_cyno_module()
				or bool(ship.allow_enemy_cell_overlap)
			)
			var snap: bool = force_all or _prepare_mode or pinned
			if not snap:
				continue
			var side2: int = ship_world_side(ship)
			var base: Vector3 = cell_to_world("field", side2, ship.grid_x, ship.grid_z)
			if overlap and lateral > 0.0:
				var sign_x: float = -1.0 if ship.team_id == ShipUnit.TEAM_PLAYER else 1.0
				base.x += sign_x * lateral
			ship.global_position = base
			ship.global_position.y = 0.2


func find_empty_hangar(team: int) -> Vector2i:
	## Center-out on X (middle first, then left/right), same pattern as find_empty_field.
	var hw: int = TypedVariant.as_int(DataStore.board.get("hangar_width", 15), 15)
	var cx: int = hw >> 1
	var x_order: Array[int] = []
	for d: int in range(hw):
		var left: int = cx - d
		var right: int = cx + d
		if d == 0:
			if left >= 0 and left < hw:
				x_order.append(left)
		else:
			if left >= 0 and left < hw:
				x_order.append(left)
			if right >= 0 and right < hw and right != left:
				x_order.append(right)
	for x: int in x_order:
		if not _hangar_occupied.has(_key("hangar", team, x, 0)):
			return Vector2i(x, 0)
	return Vector2i(-1, -1)

func find_empty_field(team: int) -> Vector2i:
	var fh: int = TypedVariant.as_int(DataStore.board.get("field_height", 6), 6)
	var random_deploy: bool = TypedVariant.as_bool(DataStore.ai.get("random_deploy", false), false)
	if random_deploy:
		var empties: Array[Vector2i] = []
		for z: int in range(fh):
			var cols: int = field_cols_at(z)
			for x: int in range(cols):
				if not _field_occupied.has(_key("field", team, x, z)):
					empties.append(Vector2i(x, z))
		if empties.is_empty():
			return Vector2i(-1, -1)
		return empties[randi() % empties.size()]
	## Front row toward enemy first (z=max), then center-out on X (per-row width).
	var z_order: Array[int] = []
	for z: int in range(fh - 1, -1, -1):
		z_order.append(z)
	for z: int in z_order:
		var cols: int = field_cols_at(z)
		var cx: int = cols >> 1
		var x_order: Array[int] = []
		for d: int in range(cols):
			var left: int = cx - d
			var right: int = cx + d
			if d == 0:
				if left >= 0 and left < cols:
					x_order.append(left)
			else:
				if left >= 0 and left < cols:
					x_order.append(left)
				if right >= 0 and right < cols and right != left:
					x_order.append(right)
		for x: int in x_order:
			if not _field_occupied.has(_key("field", team, x, z)):
				return Vector2i(x, z)
	return Vector2i(-1, -1)

func count_field(team: int) -> int:
	var n: int = 0
	for s: ShipUnit in _ships:
		## The salvage freighter is not a combatant: counting it would keep the half it
		## sits on from ever reading as cleared (FREIGHTER_AND_TITAN §1.2.1).
		if s.is_protect_target:
			continue
		if s.team_id == team and s.slot_type == "field" and not s.is_destroyed and not s.is_unmanned:
			n += 1
	return n

func count_alive_field(team: int) -> int:
	return count_field(team)

func field_ships(team: int) -> Array[ShipUnit]:
	var out: Array[ShipUnit] = []
	for s: ShipUnit in _ships:
		if s.team_id == team and s.slot_type == "field" and not s.is_destroyed:
			out.append(s)
	return out

func all_ships() -> Array[ShipUnit]:
	return _ships


## False for hulls that only exist as scenery — berth titans, wrecks, CG props.
## They are pickable (detail panel / observe cam) but own no slot to move between.
func is_board_piece(ship: ShipUnit) -> bool:
	return ship != null and is_instance_valid(ship) and _ships.has(ship)


## Soft-follow the mesh toward logic pose (COMBAT §3.2). Combat still reads the root.
var _visual_follow_armed: bool = false

func arm_visual_follow() -> void:
	_visual_follow_armed = true
	for s: ShipUnit in _ships:
		if is_instance_valid(s):
			s.arm_visual_follow()


func disarm_visual_follow() -> void:
	_visual_follow_armed = false
	for s: ShipUnit in _ships:
		if is_instance_valid(s):
			s.disarm_visual_follow()

func is_one_side_cleared() -> bool:
	return count_alive_field(ShipUnit.TEAM_PLAYER) == 0 or count_alive_field(ShipUnit.TEAM_AI) == 0

## True when neither side can ever finish the other off: both still have ≥1 alive
## manned field ship, but none of those ships carry offensive damage (e.g. all pure
## logistics/utility). Freighters and unmanned hulls are excluded like `count_alive_field`.
## Covert cyno counts as combat presence (CAPITAL_AND_CYNO §2 清场计数 / MATCH_FLOW §4.2):
## do not draw_no_offense while a cyno is on field — channel must run until kill/complete.
func both_sides_no_offense() -> bool:
	var player_alive: int = 0
	var ai_alive: int = 0
	var player_has_presence: bool = false
	var ai_has_presence: bool = false
	for s: ShipUnit in _ships:
		if s == null or not is_instance_valid(s):
			continue
		if s.is_protect_target or s.is_unmanned:
			continue
		if s.slot_type != "field" or s.is_destroyed:
			continue
		var presence: bool = s.has_offensive_damage() or s.has_cyno_module()
		if s.team_id == ShipUnit.TEAM_PLAYER:
			player_alive += 1
			if presence:
				player_has_presence = true
		elif s.team_id == ShipUnit.TEAM_AI:
			ai_alive += 1
			if presence:
				ai_has_presence = true
	return player_alive >= 1 and ai_alive >= 1 and not player_has_presence and not ai_has_presence

func try_upgrades_all() -> void:
	## 3-of-a-kind star merges only in Prepare (ECONOMY_AND_SHOP §5) — never mid-battle.
	if not _prepare_mode:
		return
	var changed: bool = true
	while changed:
		changed = false
		## Each pass may queue_free materials; scrub before typed ShipUnit reads.
		_purge_freed_ships()
		var groups: Dictionary = {}
		for s_any: Variant in (_ships as Array):
			if s_any == null or not is_instance_valid(s_any):
				continue
			var s: ShipUnit = s_any
			if s.is_destroyed:
				continue
			var k: String = "%d_%d_%d" % [s.team_id, s.ship_id, s.star]
			if not groups.has(k):
				groups[k] = []
			@warning_ignore("unsafe_cast")
			var grp: Array = groups[k] as Array
			grp.append(s)
		for k: Variant in groups.keys():
			var arr: Array = groups[k]
			if arr.size() < 3:
				continue
			if not is_instance_valid(arr[2]):
				continue
			var keeper: ShipUnit = arr[2]
			if keeper.star >= 3:
				continue
			## Unequip → item ids only (no ShipUnit across call_group / free). EQUIPMENT §2.
			var team: int = keeper.team_id
			var returned_ids: Array = []
			for i: int in range(mini(3, arr.size())):
				if not is_instance_valid(arr[i]):
					continue
				var hull: ShipUnit = arr[i]
				returned_ids.append_array(_drain_function_fit_ids(hull))
			for i: int in range(2):
				if is_instance_valid(arr[i]):
					@warning_ignore("unsafe_cast")
					_remove_ship(arr[i] as ShipUnit)
			if is_instance_valid(keeper):
				keeper.upgrade_level()
			var tree: SceneTree = get_tree()
			if tree and not returned_ids.is_empty():
				tree.call_group("match_root", "on_star_merge_stash_equipment", team, returned_ids)
			changed = true
			break


## Strip all function-fit modules from a hull; returns module ids (may be empty).
func _drain_function_fit_ids(ship: ShipUnit) -> Array:
	var out: Array = []
	if ship == null or not is_instance_valid(ship):
		return out
	while true:
		var fit: Array = ship.get_function_fit()
		if fit.is_empty():
			break
		var mid: String = ship.unequip_function_at(fit.size() - 1)
		if mid == "":
			break
		out.append(mid)
	return out

func _remove_ship(s: ShipUnit) -> void:
	## Same teardown as an explicit removal: exact key + scrub of any occupancy entry
	## still pointing at this hull, so a star merge cannot leave a freed reference behind.
	remove_ship_node(s)


## A freed hull (star merge, sell, kill) can still sit in the roster or the occupancy
## maps. Reading one back into a typed `ShipUnit` slot raises "Trying to assign invalid
## previously freed instance", so scrub before any pass that does such an assignment.
func _purge_freed_ships() -> void:
	## Index via untyped Array — typed Array[ShipUnit] throws on freed elements before
	## is_instance_valid can run.
	var raw: Array = _ships
	var i: int = raw.size() - 1
	while i >= 0:
		var entry: Variant = raw[i]
		if entry == null or not is_instance_valid(entry):
			_ships.remove_at(i)
		i -= 1
	for occ_any: Dictionary in [_field_occupied, _hangar_occupied]:
		var occ: Dictionary = occ_any
		var stale: Array = []
		for k: Variant in occ.keys():
			var v: Variant = occ[k]
			if v == null or not is_instance_valid(v):
				stale.append(k)
		for k2: Variant in stale:
			occ.erase(k2)
	if _drag_ship != null and not is_instance_valid(_drag_ship):
		_drag_ship = null

func reset_ships_after_round() -> void:
	## MATCH_FLOW: heal every hull (field + hangar), not only field.
	for s: ShipUnit in _ships:
		if s == null or not is_instance_valid(s):
			continue
		s.reload_stats()
		if s.slot_type == "field":
			var side: int = ship_world_side(s)
			s.global_position = cell_to_world("field", side, s.grid_x, s.grid_z)
			s.restore_team_yaw()
			s.set_combat_tint(false)
	refresh_cross_team_cell_offsets()


## Explicit full pipes after Battle (covers hangar + post-fetter max rescale).
func force_full_hp_all_ships() -> void:
	for s: ShipUnit in _ships:
		if s == null or not is_instance_valid(s):
			continue
		s.is_destroyed = false
		s.visible = true
		s.shield_hp = s.max_shield
		s.armor_hp = s.max_armor
		s.structure_hp = s.max_structure


## After battle / before prepare autosave: send cyno-gated hulls back to hangar
## so the next round needs induction again and resume never starts with them on field.
## Hangar full → auto-sell (CAPITAL_AND_CYNO §6.1 / MATCH_FLOW §5.0b).
func recall_cyno_entry_ships_to_hangar() -> int:
	var moved: int = 0
	var sold: int = 0
	var snapshot: Array = _ships.duplicate()
	for s_any: Variant in snapshot:
		@warning_ignore("unsafe_cast")
		var s: ShipUnit = s_any as ShipUnit
		if s == null or not is_instance_valid(s) or s.is_destroyed or s.is_unmanned:
			continue
		if not s.requires_cyno_entry:
			continue
		if s.slot_type != "field":
			continue
		var hang: Vector2i = find_empty_hangar(s.team_id)
		if hang.x < 0:
			var gold: int = s.get_sell_price()
			var sold_id: int = s.ship_id
			var sold_team: int = s.team_id
			SessionDiagnostics.log(
				"capital.recall_autosell",
				"ship=%d team=%d gold=%d" % [sold_id, sold_team, gold]
			)
			_remove_ship(s)
			sold += 1
			var tree: SceneTree = get_tree()
			if tree:
				tree.call_group("match_root", "on_capital_hangar_full_autosell", gold, sold_team)
			continue
		var occ_from: Dictionary = _field_occupied
		occ_from.erase(_key("field", s.team_id, s.grid_x, s.grid_z))
		s.slot_type = "hangar"
		s.grid_x = hang.x
		s.grid_z = hang.y
		s.field_side_team = s.team_id
		s.global_position = cell_to_world("hangar", s.team_id, hang.x, hang.y)
		s.restore_team_yaw()
		_hangar_occupied[_key("hangar", s.team_id, hang.x, hang.y)] = s
		moved += 1
	if moved > 0 or sold > 0:
		refresh_cross_team_cell_offsets()
		board_changed.emit()
	return moved


func _on_deploy(payload: Dictionary) -> Dictionary:
	var ship_id: int = TypedVariant.as_int(payload.get("ship_id", 0), 0)
	var team: int = TypedVariant.as_int(payload.get("team", 0), 0)
	var slot_type: String = str(payload.get("slot_type", "field"))
	var x: int = TypedVariant.as_int(payload.get("x", 0), 0)
	var z: int = TypedVariant.as_int(payload.get("z", 0), 0)
	var star: int = TypedVariant.as_int(payload.get("star", 1), 1)
	var sd: Dictionary = DataStore.get_ship(ship_id)
	if slot_type == "field" and TypedVariant.as_bool(sd.get("requires_cyno_entry", false), false):
		SessionDiagnostics.log("deploy.fail", "reason=requires_cyno ship=%d" % ship_id)
		return {"accepted": false, "reason_key": "requires_cyno"}
	if not _in_bounds(slot_type, x, z):
		SessionDiagnostics.log("deploy.fail", "reason=out_of_bounds ship=%d" % ship_id)
		return {"accepted": false, "reason_key": "out_of_bounds"}
	if slot_type == "field":
		if _field_occupied.has(_key("field", team, x, z)):
			SessionDiagnostics.log("deploy.fail", "reason=occupied ship=%d" % ship_id)
			return {"accepted": false, "reason_key": "occupied"}
	else:
		if _hangar_occupied.has(_key("hangar", team, x, z)):
			SessionDiagnostics.log("deploy.fail", "reason=occupied ship=%d" % ship_id)
			return {"accepted": false, "reason_key": "occupied"}
	var ship: ShipUnit = spawn_ship(ship_id, star, team, slot_type, x, z)
	if slot_type == "field" and TypedVariant.as_bool(sd.get("deploy_enemy_half_only", false), false):
		var side: int = ShipUnit.TEAM_AI if team == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
		ship.field_side_team = side
		ship.global_position = cell_to_world("field", side, x, z)
	## Bulk redeploy / save restore must not merge stars mid-stream (MATCH_FLOW §5.0b).
	if not TypedVariant.as_bool(payload.get("skip_upgrade", false), false):
		try_upgrades_all()
	refresh_cross_team_cell_offsets()
	return {"accepted": true}

func _on_move(payload: Dictionary) -> Dictionary:
	# payload: from_* to_* ship ref via instance_id
	_purge_freed_ships()
	var sid: int = TypedVariant.as_int(payload.get("ship_instance_id", 0), 0)
	@warning_ignore("unsafe_cast")
	var ship: ShipUnit = instance_from_id(sid) as ShipUnit
	if ship == null or not is_instance_valid(ship):
		return {"accepted": false}
	if ship.requires_cyno_entry and str(payload.get("to_slot_type", ship.slot_type)) == "field":
		SessionDiagnostics.log("deploy.fail", "reason=requires_cyno move")
		return {"accepted": false, "reason_key": "requires_cyno"}
	var to_type: String = str(payload.get("to_slot_type", ship.slot_type))
	var to_x: int = TypedVariant.as_int(payload.get("to_x", ship.grid_x), ship.grid_x)
	var to_z: int = TypedVariant.as_int(payload.get("to_z", ship.grid_z), ship.grid_z)
	var to_team: int = ship.team_id
	if not _in_bounds(to_type, to_x, to_z):
		SessionDiagnostics.log("deploy.fail", "reason=out_of_bounds move")
		return {"accepted": false, "reason_key": "out_of_bounds"}
	var side_team: int = to_team
	if to_type == "field" and ship.deploy_enemy_half_only:
		side_team = ShipUnit.TEAM_AI if to_team == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
	elif to_type == "field" and payload.has("field_side_team"):
		side_team = TypedVariant.as_int(payload.get("field_side_team", to_team), to_team)
	var from_type: String = ship.slot_type
	var from_x: int = ship.grid_x
	var from_z: int = ship.grid_z
	var from_side: int = ship.field_side_team if ship.field_side_team >= 0 else ship.team_id
	var occ_from: Dictionary = _hangar_occupied if from_type == "hangar" else _field_occupied
	var occ_to: Dictionary = _hangar_occupied if to_type == "hangar" else _field_occupied
	var to_key: String = _key(to_type, to_team, to_x, to_z)
	var other_any: Variant = occ_to.get(to_key)
	if other_any != null and not is_instance_valid(other_any):
		occ_to.erase(to_key)
		other_any = null
	@warning_ignore("unsafe_cast")
	var other: ShipUnit = other_any as ShipUnit
	if other and other != ship:
		## Only own-team board pieces swap; enemy / freighter / scenery refuse as occupied.
		if other.team_id != ship.team_id or other.is_protect_target or not is_board_piece(other):
			SessionDiagnostics.log("deploy.fail", "reason=occupied swap")
			return {"accepted": false, "reason_key": "occupied"}
		## Swap must not sneak a cyno-gated hull onto Field.
		if other.requires_cyno_entry and from_type == "field":
			SessionDiagnostics.log("deploy.fail", "reason=requires_cyno swap")
			return {"accepted": false, "reason_key": "requires_cyno"}
		## Non-cyno hull must not land on enemy half via swap (BOARD_AND_INPUT §4).
		## Covert cyno may sit on either half (`allow_enemy_cell_overlap`).
		if from_type == "field" and not other.allow_enemy_cell_overlap and not other.deploy_enemy_half_only:
			if from_side != other.team_id:
				SessionDiagnostics.log("deploy.fail", "reason=enemy_half_forbidden swap")
				return {"accepted": false, "reason_key": "enemy_half_forbidden"}
	## Non-cyno ship may not move/swap onto the enemy half (cyno may via allow_enemy_cell_overlap).
	if to_type == "field" and side_team != to_team:
		if not ship.deploy_enemy_half_only and not ship.allow_enemy_cell_overlap:
			SessionDiagnostics.log("deploy.fail", "reason=enemy_half_forbidden move")
			return {"accepted": false, "reason_key": "enemy_half_forbidden"}
	## Legacy deploy_enemy_half_only: if still true on a hull, refuse own half.
	if to_type == "field" and ship.deploy_enemy_half_only:
		var enemy_side: int = ShipUnit.TEAM_AI if to_team == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
		if side_team != enemy_side:
			SessionDiagnostics.log("deploy.fail", "reason=enemy_half_only move")
			return {"accepted": false, "reason_key": "enemy_half_only"}
	occ_from.erase(_key(from_type, ship.team_id, from_x, from_z))
	if other and other != ship:
		occ_to.erase(to_key)
		other.slot_type = from_type
		other.grid_x = from_x
		other.grid_z = from_z
		if from_type == "hangar":
			other.field_side_team = other.team_id
			other.global_position = cell_to_world("hangar", other.team_id, from_x, from_z)
		else:
			other.field_side_team = from_side
			other.global_position = cell_to_world("field", from_side, from_x, from_z)
		var ok: Dictionary = _hangar_occupied if other.slot_type == "hangar" else _field_occupied
		ok[_key(other.slot_type, other.team_id, other.grid_x, other.grid_z)] = other
	ship.slot_type = to_type
	ship.grid_x = to_x
	ship.grid_z = to_z
	if to_type == "hangar":
		ship.field_side_team = to_team
		side_team = to_team
	else:
		ship.field_side_team = side_team
	ship.global_position = cell_to_world(to_type, side_team, to_x, to_z)
	occ_to[to_key] = ship
	try_upgrades_all()
	refresh_cross_team_cell_offsets()
	board_changed.emit()
	return {"accepted": true}


func _occupant_at(slot_type: String, team: int, x: int, z: int) -> ShipUnit:
	var occ: Dictionary = _hangar_occupied if slot_type == "hangar" else _field_occupied
	@warning_ignore("unsafe_cast")
	return occ.get(_key(slot_type, team, x, z)) as ShipUnit

func _on_sell(payload: Dictionary) -> Dictionary:
	var sid: int = TypedVariant.as_int(payload.get("ship_instance_id", 0), 0)
	@warning_ignore("unsafe_cast")
	var ship: ShipUnit = instance_from_id(sid) as ShipUnit
	if ship == null or not is_instance_valid(ship):
		return {"accepted": false}
	## Player + AI share sell path (AI hangar clear at end of economy turn).
	if payload.has("team") and TypedVariant.as_int(payload.get("team", 0), 0) != ship.team_id:
		return {"accepted": false}
	if ship.is_protect_target:
		return {"accepted": false, "reason": "protect_target"}
	var gold: int = ship.get_sell_price()
	var sold_id: int = ship.ship_id
	var sold_team: int = ship.team_id
	_remove_ship(ship)
	if sold_team == ShipUnit.TEAM_PLAYER:
		SessionDiagnostics.log("shop.sell", "ok ship=%d gold=%d" % [sold_id, gold])
	return {"accepted": true, "gold": gold}

func begin_drag(ship: ShipUnit) -> void:
	if ship == null:
		return
	## Battle: hangar↔hangar only; Field drag stays Prepare-only (BOARD_AND_INPUT §4).
	if not _prepare_mode and ship.slot_type != "hangar":
		return
	## Salvage freighter rides on the player team but is scenario furniture: never draggable.
	if ship.is_protect_target:
		return
	## Berth titans are set dressing on the player team too (FREIGHTER_AND_TITAN §2.1).
	if not is_board_piece(ship):
		return
	if ship.team_id != ShipUnit.TEAM_PLAYER:
		if not get_tree().paused or not GameSession.enemy_layout_adjust_active():
			return
	_drag_ship = ship

func update_drag(world_pos: Vector3) -> void:
	if _drag_ship:
		var pos: Vector3 = Vector3(world_pos.x, 1.0, world_pos.z)
		var clamp_team: int = _drag_ship.team_id
		if _drag_ship.deploy_enemy_half_only:
			clamp_team = ShipUnit.TEAM_AI if _drag_ship.team_id == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
		pos = clamp_to_prepare_play_area(pos, clamp_team, 0.0)
		_drag_ship.global_position = pos

func end_drag(sell_zone: bool, hover_slot: Dictionary) -> void:
	_purge_freed_ships()
	if _drag_ship == null:
		return
	var ship: ShipUnit = _drag_ship
	_drag_ship = null
	var snap_side: int = ship_world_side(ship)
	if sell_zone:
		var r: Dictionary = AdminBus.request(&"board.sell", {"ship_instance_id": ship.get_instance_id()})
		if TypedVariant.as_bool(r.get("accepted", false), false):
			var g: int = TypedVariant.as_int(r.get("gold", ship.get_sell_price()), 0)
			# gold credited by match via signal — emit board_changed; MatchHud listens? Use group
			get_tree().call_group("match_root", "on_ship_sold", g)
		else:
			ship.global_position = cell_to_world(ship.slot_type, snap_side if ship.slot_type == "field" else ship.team_id, ship.grid_x, ship.grid_z)
		return
	if hover_slot.is_empty():
		ship.global_position = cell_to_world(ship.slot_type, snap_side if ship.slot_type == "field" else ship.team_id, ship.grid_x, ship.grid_z)
		return
	var to_type: String = str(hover_slot.get("slot_type", "field"))
	var hover_team: int = TypedVariant.as_int(hover_slot.get("team", ship.team_id), ship.team_id)
	## Battle: hangar only — bounce any Field drop.
	if not _prepare_mode and to_type != "hangar":
		get_tree().call_group("match_root", "show_notice", "战斗中仅可调整候席")
		ship.global_position = cell_to_world(ship.slot_type, snap_side if ship.slot_type == "field" else ship.team_id, ship.grid_x, ship.grid_z)
		return
	## Capitals: any drop onto a field cell bounces back to hangar + notice.
	if ship.requires_cyno_entry and to_type == "field":
		get_tree().call_group("match_root", "show_notice", "旗舰必须通过诱导跳跃进场")
		ship.global_position = cell_to_world(ship.slot_type, snap_side if ship.slot_type == "field" else ship.team_id, ship.grid_x, ship.grid_z)
		return
	if ship.deploy_enemy_half_only and to_type == "field":
		var enemy: int = ShipUnit.TEAM_AI if ship.team_id == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
		if hover_team != enemy:
			get_tree().call_group("match_root", "show_notice", "只能部署在敌方半场")
			ship.global_position = cell_to_world(ship.slot_type, snap_side if ship.slot_type == "field" else ship.team_id, ship.grid_x, ship.grid_z)
			return
	elif to_type == "field" and hover_team != ship.team_id:
		## Own half only unless covert cyno (allow_enemy_cell_overlap) or legacy enemy-half-only.
		if not ship.allow_enemy_cell_overlap and not ship.deploy_enemy_half_only:
			get_tree().call_group("match_root", "show_notice", "不可部署到敌方半场")
			ship.global_position = cell_to_world(ship.slot_type, snap_side if ship.slot_type == "field" else ship.team_id, ship.grid_x, ship.grid_z)
			return
	if to_type == "field":
		var match_node: MatchRoot = get_tree().get_first_node_in_group("match_root") as MatchRoot
		if match_node:
			var lim: int = match_node.match_ctrl.population_limit()
			var from_field: bool = ship.slot_type == "field"
			var deployed: int = count_field(ship.team_id)
			## Hangar→field onto an ally is a swap: field count stays flat, so skip the cap.
			var swap_ally: ShipUnit = _occupant_at("field", ship.team_id, TypedVariant.as_int(hover_slot.get("x", -1), -1), TypedVariant.as_int(hover_slot.get("z", -1), -1))
			var is_swap: bool = (
				swap_ally != null
				and swap_ally != ship
				and swap_ally.team_id == ship.team_id
				and not swap_ally.is_protect_target
			)
			if not from_field and not is_swap and deployed >= lim:
				get_tree().call_group("match_root", "show_notice", "对战区已满")
				ship.global_position = cell_to_world(ship.slot_type, snap_side if ship.slot_type == "field" else ship.team_id, ship.grid_x, ship.grid_z)
				return
	var move_r: Dictionary = AdminBus.request(&"board.move", {
		"ship_instance_id": ship.get_instance_id(),
		"to_slot_type": hover_slot.get("slot_type"),
		"to_x": hover_slot.get("x"),
		"to_z": hover_slot.get("z"),
		"field_side_team": hover_team if to_type == "field" else ship.team_id,
	})
	if not TypedVariant.as_bool(move_r.get("accepted", false), false):
		if str(move_r.get("reason_key", "")) == "requires_cyno":
			get_tree().call_group("match_root", "show_notice", "旗舰必须通过诱导跳跃进场")
		elif str(move_r.get("reason_key", "")) == "enemy_half_only":
			get_tree().call_group("match_root", "show_notice", "只能部署在敌方半场")
		elif str(move_r.get("reason_key", "")) == "enemy_half_forbidden":
			get_tree().call_group("match_root", "show_notice", "不可部署到敌方半场")
		ship.global_position = cell_to_world(ship.slot_type, snap_side if ship.slot_type == "field" else ship.team_id, ship.grid_x, ship.grid_z)

func _cancel_drag() -> void:
	if _drag_ship:
		var side: int = ship_world_side(_drag_ship) if _drag_ship.slot_type == "field" else _drag_ship.team_id
		_drag_ship.global_position = cell_to_world(_drag_ship.slot_type, side, _drag_ship.grid_x, _drag_ship.grid_z)
	_drag_ship = null

func pick_ship_at(origin: Vector3, dir: Vector3, exclude: ShipUnit = null) -> ShipUnit:
	## Model AABB raycast (BOARD_AND_INPUT §4). No soft sphere around logic centre.
	## Any team (player + AI) for hover/info; drag still gated in PointerInput / begin_drag.
	_purge_freed_ships()
	var best: ShipUnit = null
	var best_t: float = INF
	var nd: Vector3 = dir.normalized()
	if nd.length_squared() < 1e-12:
		return null
	for s: ShipUnit in _ships:
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		if exclude != null and s == exclude:
			continue
		var t: float = s.ray_hit_model_distance(origin, nd)
		if t < 0.0:
			continue
		if t < best_t:
			best_t = t
			best = s
	return best

## Circumradius for pointy-top field hexes that tessellate with board spacing.
static func field_hex_circumradius() -> float:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var hox: float = absf(TypedVariant.as_float(b.get("hex_offset_x", -3.0), -3.0))
	var hoz: float = absf(TypedVariant.as_float(b.get("hex_offset_z", -2.5), -2.5))
	## Pointy-top: same-row spacing = sqrt(3)*R; vertical neighbor spacing = 1.5*R.
	var r_x: float = hox / sqrt(3.0)
	var r_z: float = hoz / 1.5
	return minf(r_x, r_z) * 0.98


## Solid filled pointy-top hex in XZ (not a hollow ring; BOARD_AND_INPUT §4).
static func point_in_field_hex_xz(world: Vector3, cell_center: Vector3, radius: float = -1.0) -> bool:
	var R: float = radius if radius > 0.0 else field_hex_circumradius()
	if R <= 1e-6:
		return false
	var dx: float = absf(world.x - cell_center.x)
	var dz: float = absf(world.z - cell_center.z)
	if dz > R:
		return false
	if dx > R * sqrt(3.0) * 0.5:
		return false
	return dz <= R - dx / sqrt(3.0)


static func point_in_hangar_square_xz(world: Vector3, cell_center: Vector3) -> bool:
	var half: float = absf(hangar_step_x()) * 0.5
	if half <= 1e-6:
		half = 0.6
	return absf(world.x - cell_center.x) <= half and absf(world.z - cell_center.z) <= half


## Camera ray → solid cell under cursor (BOARD_AND_INPUT §4). Empty = miss.
func pick_slot_by_ray(origin: Vector3, dir: Vector3, team: int = ShipUnit.TEAM_PLAYER, field_side: int = -1) -> Dictionary:
	var nd: Vector3 = dir.normalized()
	if nd.length_squared() < 1e-12:
		return {}
	var best: Dictionary = {}
	var best_t: float = INF
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var fh: int = TypedVariant.as_int(b.get("field_height", 6), 6)
	var side: int = field_side if field_side >= 0 else team
	var hex_r: float = field_hex_circumradius()
	for z: int in range(fh):
		var cols: int = field_cols_at(z)
		for x: int in range(cols):
			var c: Vector3 = cell_to_world("field", side, x, z)
			if absf(nd.y) < 1e-8:
				continue
			var t: float = (c.y - origin.y) / nd.y
			if t < 0.0 or t >= best_t:
				continue
			var hit: Vector3 = origin + nd * t
			if not point_in_field_hex_xz(hit, c, hex_r):
				continue
			best_t = t
			best = {"slot_type": "field", "x": x, "z": z, "team": side}
	var hw: int = TypedVariant.as_int(b.get("hangar_width", 15), 15)
	for x: int in range(hw):
		var c2: Vector3 = cell_to_world("hangar", team, x, 0)
		if absf(nd.y) < 1e-8:
			continue
		var t2: float = (c2.y - origin.y) / nd.y
		if t2 < 0.0 or t2 >= best_t:
			continue
		var hit2: Vector3 = origin + nd * t2
		if not point_in_hangar_square_xz(hit2, c2):
			continue
		best_t = t2
		best = {"slot_type": "hangar", "x": x, "z": 0, "team": team}
	return best


func pick_slot_at(world: Vector3, team: int = ShipUnit.TEAM_PLAYER, field_side: int = -1) -> Dictionary:
	## Solid footprint containment (same shapes as pick_slot_by_ray). No soft sphere.
	var best: Dictionary = {}
	var best_d: float = INF
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var fh: int = TypedVariant.as_int(b.get("field_height", 6), 6)
	var side: int = field_side if field_side >= 0 else team
	var hex_r: float = field_hex_circumradius()
	for z: int in range(fh):
		var cols: int = field_cols_at(z)
		for x: int in range(cols):
			var p: Vector3 = cell_to_world("field", side, x, z)
			if not point_in_field_hex_xz(world, p, hex_r):
				continue
			var d: float = Vector2(world.x - p.x, world.z - p.z).length()
			if d < best_d:
				best_d = d
				best = {"slot_type": "field", "x": x, "z": z, "team": side}
	var hw: int = TypedVariant.as_int(b.get("hangar_width", 15), 15)
	for x: int in range(hw):
		var p2: Vector3 = cell_to_world("hangar", team, x, 0)
		if not point_in_hangar_square_xz(world, p2):
			continue
		var d2: float = Vector2(world.x - p2.x, world.z - p2.z).length()
		if d2 < best_d:
			best_d = d2
			best = {"slot_type": "hangar", "x": x, "z": 0, "team": team}
	return best

func recalculate_fetters(team: int) -> Array:
	var counts: Dictionary = {}
	for s: ShipUnit in field_ships(team):
		## Salvage freighter rides on the player team but is not a roster piece.
		if s.is_protect_target:
			continue
		var ship: Dictionary = DataStore.get_ship(s.ship_id)
		for fid: Variant in TypedVariant.as_array(ship.get("fetter_ids", [])):
			counts[fid] = TypedVariant.as_int(counts.get(fid, 0), 0) + 1
	var active: Array = []
	for fid: Variant in counts.keys():
		var fetter: Dictionary = DataStore.fetters.get(fid, {})
		var effects: Array = TypedVariant.as_array(fetter.get("effects", []))
		var best: Variant = null
		var best_c: int = -1
		for e: Dictionary in effects:
			var need: int = TypedVariant.as_int(e.get("champion_count", 0), 0)
			if need <= TypedVariant.as_int(counts[fid], 0) and need >= best_c:
				best_c = need
				best = e
		if best != null:
			var payload: Dictionary = {"fetter_id": fid, "champion_count": counts[fid], "effect": best}
			var r: Dictionary = AdminBus.request(&"fetter.activate", payload)
			if TypedVariant.as_bool(r.get("accepted", true), true):
				active.append({"fetter_id": fid, "count": counts[fid], "effect": best})
	_append_titan_fetter(team, active)
	var shield_mul: float = 1.0
	var armor_mul: float = 1.0
	var repair_mul_all: float = 1.0
	var speed_mul: float = 1.0
	var attack_speed_mul: float = 1.0
	var armor_hp_pct_all: float = 0.0
	var shield_hp_pct_all: float = 0.0
	var flat_hp_all: float = 0.0
	## SelfFetter repair extras keyed by fetter_id → multiplier product.
	var repair_mul_by_fetter: Dictionary = {}
	for a: Dictionary in active:
		var eff: Dictionary = a["effect"]
		var et: String = str(eff.get("effect_type", ""))
		var vt: String = str(eff.get("effect_value_type", ""))
		var val: float = TypedVariant.as_float(eff.get("value", 0.0), 0.0)
		var target: String = str(eff.get("effect_target", "SelfAll"))
		var mul: float = _fetter_multiplier(vt, val)
		var self_fetter: bool = target == "SelfFetter" and not TypedVariant.as_bool(a.get("meta", false), false)
		match et:
			"ShieldResist":
				if not self_fetter:
					shield_mul *= mul
			"ArmorResist":
				if not self_fetter:
					armor_mul *= mul
			"RemoteRepair", "Repair", "ArmorHeal", "ShieldHeal":
				## ArmorHeal/ShieldHeal are logistic-heal aliases (FETTERS · logistic.json).
				if self_fetter:
					var fid: String = str(a["fetter_id"])
					repair_mul_by_fetter[fid] = TypedVariant.as_float(repair_mul_by_fetter.get(fid, 1.0), 1.0) * mul
				else:
					repair_mul_all *= mul
			"Speed":
				if not self_fetter:
					speed_mul *= mul
			"AttackSpeed":
				if not self_fetter:
					attack_speed_mul *= mul
			"ArmorHP":
				if not self_fetter and vt == "Percentage":
					armor_hp_pct_all += val
			"ShieldHP":
				if not self_fetter and vt == "Percentage":
					shield_hp_pct_all += val
			"FlatHP":
				if not self_fetter:
					flat_hp_all += val
	for s: ShipUnit in field_ships(team):
		if s == null or not is_instance_valid(s):
			continue
		s.damage_pct_bonus = 0.0
		var ship: Dictionary = DataStore.get_ship(s.ship_id)
		@warning_ignore("unsafe_cast")
		var fids: Array = ship.get("fetter_ids", []) as Array
		var ship_repair: float = repair_mul_all
		for a: Dictionary in active:
			## Titan meta fetter buffs every own hull; race fetters only their own members.
			var is_meta: bool = TypedVariant.as_bool(a.get("meta", false), false)
			var on_ship: bool = is_meta or (a["fetter_id"] in fids)
			if not on_ship:
				continue
			var eff: Dictionary = a["effect"]
			var et: String = str(eff.get("effect_type", ""))
			var vt: String = str(eff.get("effect_value_type", ""))
			var target: String = str(eff.get("effect_target", "SelfAll"))
			if et == "Damage" and vt == "Percentage":
				## SelfFetter Damage only hits members; SelfAll / meta hits everyone already gated by on_ship.
				if target == "SelfFetter" or target == "SelfAll" or is_meta:
					s.damage_pct_bonus += TypedVariant.as_float(eff.get("value", 0.0), 0.0)
		for fid2: Variant in repair_mul_by_fetter.keys():
			if fid2 in fids:
				ship_repair *= TypedVariant.as_float(repair_mul_by_fetter[fid2], 1.0)
		s.apply_fetter_mods(shield_mul, armor_mul, ship_repair, speed_mul)
		# Recompute cycle from baseline — never stack-divide attack_duration across recalcs.
		var base_cycle: float = s.base_attack_duration if s.base_attack_duration > 0.0 else s.attack_duration
		if attack_speed_mul != 1.0 and base_cycle > 0.0:
			s.attack_duration = maxf(0.2, base_cycle / attack_speed_mul)
		else:
			s.attack_duration = base_cycle
		## HP bonuses always from base max — prevents compounding to astronomical values.
		var sh_ratio: float = 1.0 if s.base_max_shield <= 0.0 else clampf(s.shield_hp / maxf(s.max_shield, 0.001), 0.0, 1.0)
		var ar_ratio: float = 1.0 if s.base_max_armor <= 0.0 else clampf(s.armor_hp / maxf(s.max_armor, 0.001), 0.0, 1.0)
		var st_ratio: float = 1.0 if s.base_max_structure <= 0.0 else clampf(s.structure_hp / maxf(s.max_structure, 0.001), 0.0, 1.0)
		s.max_shield = s.base_max_shield * (1.0 + shield_hp_pct_all / 100.0)
		s.max_armor = s.base_max_armor * (1.0 + armor_hp_pct_all / 100.0)
		s.max_structure = s.base_max_structure + flat_hp_all
		s.shield_hp = minf(s.max_shield, s.max_shield * sh_ratio)
		s.armor_hp = minf(s.max_armor, s.max_armor * ar_ratio)
		s.structure_hp = minf(s.max_structure, s.max_structure * st_ratio)
	return active


## Titan buff is delivered as a fetter (MULTIPLAYER_PVP §2.3 / FETTERS §4.2): always-on,
## independent of Field counts, and it buffs every hull on that side.
func set_titan_fetter_race(team: int, race: String) -> void:
	var r: String = race.to_lower()
	if r == "" or not DataStore.fetters.has("titan_%s" % r):
		_titan_fetter_race.erase(team)
	else:
		_titan_fetter_race[team] = r
	recalculate_fetters(team)


func titan_fetter_race(team: int) -> String:
	return str(_titan_fetter_race.get(team, ""))


func _append_titan_fetter(team: int, active: Array) -> void:
	var race: String = str(_titan_fetter_race.get(team, ""))
	if race == "":
		return
	var fid: String = "titan_%s" % race
	var fetter: Dictionary = DataStore.fetters.get(fid, {})
	var effects: Array = TypedVariant.as_array(fetter.get("effects", []))
	if effects.is_empty():
		return
	var payload: Dictionary = {"fetter_id": fid, "champion_count": 0, "effect": effects[0]}
	var r: Dictionary = AdminBus.request(&"fetter.activate", payload)
	if TypedVariant.as_bool(r.get("accepted", true), true):
		active.append({"fetter_id": fid, "count": 0, "effect": effects[0], "meta": true})


static func _fetter_multiplier(value_type: String, value: float) -> float:
	if value_type == "Multiplier":
		return value
	if value_type == "Percentage":
		return 1.0 + value / 100.0
	return 1.0
