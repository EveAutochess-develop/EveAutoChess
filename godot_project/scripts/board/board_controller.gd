extends Node3D
class_name BoardController

signal board_changed()

var _ships: Array[ShipUnit] = []
var _field_occupied: Dictionary = {}  # "team_x_z" -> ShipUnit
var _hangar_occupied: Dictionary = {}
var _prepare_mode: bool = true
var _drag_ship: ShipUnit = null
var _world_root: Node3D
var _markers: Node3D
var _boundary_markers: Node3D

func setup(world_root: Node3D) -> void:
	_world_root = world_root
	_markers = Node3D.new()
	_markers.name = "Markers"
	_world_root.add_child(_markers)
	_boundary_markers = Node3D.new()
	_boundary_markers.name = "BoundaryMarkers"
	_world_root.add_child(_boundary_markers)
	_boundary_markers.visible = false
	_build_slot_markers()
	AdminBus.register_handler(&"board.deploy", _on_deploy)
	AdminBus.register_handler(&"board.move", _on_move)
	AdminBus.register_handler(&"board.sell", _on_sell)

func reset_match() -> void:
	for s in _ships:
		if is_instance_valid(s):
			s.queue_free()
	_ships.clear()
	_field_occupied.clear()
	_hangar_occupied.clear()
	_drag_ship = null
	board_changed.emit()

func set_prepare_mode(v: bool) -> void:
	_prepare_mode = v
	# Slot grid only in Prepare; boundary only in Battle.
	if _markers:
		_markers.visible = v
	if _boundary_markers:
		_boundary_markers.visible = false
	if not v and _drag_ship:
		_cancel_drag()

func _build_slot_markers() -> void:
	var b := DataStore.board
	var fw := int(b.get("field_width", 11))
	var fh := int(b.get("field_height", 6))
	var hexa_path := "res://assets/models/env/Models_indicator_hexa.glb"
	var square_path := "res://assets/models/env/Models_indicator_square.glb"
	var hexa_ps: PackedScene = load(hexa_path) if ResourceLoader.exists(hexa_path) else null
	var square_ps: PackedScene = load(square_path) if ResourceLoader.exists(square_path) else null
	for team in [ShipUnit.TEAM_PLAYER, ShipUnit.TEAM_AI]:
		for z in range(fh):
			for x in range(fw):
				var m := _make_indicator(hexa_ps, true)
				m.position = cell_to_world("field", team, x, z)
				_markers.add_child(m)
				var is_edge := x == 0 or x == fw - 1 or z == 0 or z == fh - 1
				if is_edge and _boundary_markers:
					var bm := _make_indicator(hexa_ps, true)
					bm.position = cell_to_world("field", team, x, z)
					_boundary_markers.add_child(bm)
		var hw := int(b.get("hangar_width", 14))
		for x in range(hw):
			var m2 := _make_indicator(square_ps, false)
			m2.position = cell_to_world("hangar", team, x, 0)
			_markers.add_child(m2)
			var is_edge_h := x == 0 or x == hw - 1
			if is_edge_h and _boundary_markers:
				var bm2 := _make_indicator(square_ps, false)
				bm2.position = cell_to_world("hangar", team, x, 0)
				_boundary_markers.add_child(bm2)

func _make_indicator(packed: PackedScene, is_hexa: bool) -> Node3D:
	## Hollow outline GLB only — no solid thickness pad (that looked like filled disks).
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.95, 0.85, 0.85) if is_hexa else Color(0.35, 0.65, 1.0, 0.88)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Keep board markers always bright regardless of scene lighting.
	mat.disable_ambient_light = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 0.65) if is_hexa else Color(0.25, 0.45, 0.85)
	mat.emission_energy_multiplier = 1.0
	# Thin frames: avoid depth flicker against the ground plane.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.render_priority = 1
	if packed:
		var n := packed.instantiate() as Node3D
		if n:
			root.add_child(n)
			var aabb := _aabb_in_root_space(n)
			var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
			if longest > 0.001:
				n.scale = Vector3.ONE * (1.2 / longest)
			aabb = _aabb_in_root_space(n)
			var s: Vector3 = n.scale
			var center := aabb.get_center()
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
	var mi := MeshInstance3D.new()
	if is_hexa:
		var torus := TorusMesh.new()
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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hout := outer * 0.5
	var tin := hout - thickness
	var segs: Array = [
		[Vector3(-hout, 0, -hout), Vector3(hout, 0, -hout), Vector3(hout, 0, -tin), Vector3(-hout, 0, -tin)],
		[Vector3(-hout, 0, tin), Vector3(hout, 0, tin), Vector3(hout, 0, hout), Vector3(-hout, 0, hout)],
		[Vector3(-hout, 0, -tin), Vector3(-tin, 0, -tin), Vector3(-tin, 0, tin), Vector3(-hout, 0, tin)],
		[Vector3(tin, 0, -tin), Vector3(hout, 0, -tin), Vector3(hout, 0, tin), Vector3(tin, 0, tin)],
	]
	for quad in segs:
		var a: Vector3 = quad[0]
		var b: Vector3 = quad[1]
		var c: Vector3 = quad[2]
		var d: Vector3 = quad[3]
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
		var a2 := a + Vector3(0, height, 0)
		var b2 := b + Vector3(0, height, 0)
		var c2 := c + Vector3(0, height, 0)
		var d2 := d + Vector3(0, height, 0)
		st.add_vertex(a2); st.add_vertex(c2); st.add_vertex(b2)
		st.add_vertex(a2); st.add_vertex(d2); st.add_vertex(c2)
	st.generate_normals()
	return st.commit()

func _tint_meshes(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.material_override = mat
		# Hard-disable lighting side effects on board visuals.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for c in node.get_children():
		_tint_meshes(c, mat)

func _aabb_in_root_space(root: Node3D) -> AABB:
	## Local-transform AABB (works before root is in the tree — global_transform is identity then).
	var result := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while stack.size() > 0:
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform3D = item[1]
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var local_aabb: AABB = mi.get_aabb()
			for i in range(8):
				var p: Vector3 = xf * local_aabb.get_endpoint(i)
				if first:
					result = AABB(p, Vector3.ZERO)
					first = false
				else:
					result = result.expand(p)
		for c in n.get_children():
			var child_xf := xf
			if c is Node3D and c != root:
				child_xf = xf * (c as Node3D).transform
			elif c is Node3D and n == root:
				child_xf = (c as Node3D).transform
			stack.append([c, child_xf])
	return result

static func field_origin(team: int) -> Vector3:
	## BOARD_AND_INPUT §2.1 — derived from field_width/height; JSON may override x/z keys.
	var b := DataStore.board
	var fw := int(b.get("field_width", 11))
	var fh := int(b.get("field_height", 6))
	var hox := absf(float(b.get("hex_offset_x", -3.0)))
	var hoz := absf(float(b.get("hex_offset_z", -2.5)))
	var gap := float(b.get("center_gap_z", 1.25))
	var ox := (fw - 1) * hox * 0.5
	var oz := (fh - 1) * hoz + gap
	if team == ShipUnit.TEAM_AI:
		if b.has("ai_origin_x"):
			ox = float(b.get("ai_origin_x"))
		else:
			ox = -ox
		if b.has("ai_origin_z"):
			oz = float(b.get("ai_origin_z"))
		else:
			oz = -oz
	else:
		if b.has("player_origin_x"):
			ox = float(b.get("player_origin_x"))
		if b.has("player_origin_z"):
			oz = float(b.get("player_origin_z"))
	return Vector3(ox, 0.0, oz)

static func hangar_origin(team: int) -> Vector3:
	var b := DataStore.board
	var fh := int(b.get("field_height", 6))
	var hw := int(b.get("hangar_width", 14))
	var hoz := absf(float(b.get("hex_offset_z", -2.5)))
	var hgap_x := absf(float(b.get("hangar_offset_x", -2.5)))
	var gap := float(b.get("center_gap_z", 1.25))
	var field_oz := (fh - 1) * hoz + gap
	var ox := (hw - 1) * hgap_x * 0.5
	var oz := field_oz + hoz
	if team == ShipUnit.TEAM_AI:
		if b.has("hangar_origin_x"):
			ox = float(b.get("hangar_origin_x"))
		else:
			ox = -ox
		if b.has("hangar_origin_z"):
			oz = float(b.get("hangar_origin_z"))
		else:
			oz = -oz
	else:
		if b.has("hangar_origin_x"):
			ox = float(b.get("hangar_origin_x"))
		if b.has("hangar_origin_z"):
			oz = float(b.get("hangar_origin_z"))
	return Vector3(ox, 0.0, oz)

static func cell_to_world(slot_type: String, team: int, x: int, z: int) -> Vector3:
	## Unity BoardController: origin + right*offsetX + forward*offsetZ (identity axes).
	var b := DataStore.board
	var ox := float(b.get("hex_offset_x", -3.0))
	var nudge := float(b.get("hex_row_nudge", 1.5))
	var oz := float(b.get("hex_offset_z", -2.5))
	var hox := float(b.get("hangar_offset_x", -2.5))
	var origin := hangar_origin(team) if slot_type == "hangar" else field_origin(team)
	var ox0 := origin.x
	var oy0 := origin.y
	var oz0 := origin.z
	if slot_type == "hangar":
		# AI hangar uses yaw 180 in Unity → negate X step relative to origin
		var step := float(x) * hox
		if team == ShipUnit.TEAM_AI:
			step = -step
		return Vector3(ox0 + step, oy0, oz0)
	var row_offset := z % 2
	var offset_x := float(x) * ox + float(row_offset) * nudge
	var offset_z := float(z) * oz
	if team == ShipUnit.TEAM_AI:
		# Unity fieldZoneTransforms[1] euler Y=180 → negate local XZ
		offset_x = -offset_x
		offset_z = -offset_z
	return Vector3(ox0 + offset_x, oy0 + 0.05, oz0 + offset_z)

## Axis-aligned playable combat rect in XZ (both team fields + margin). Returns [min_x, max_x, min_z, max_z].
static func combat_play_bounds_xz(margin_wu: float = 0.75) -> Vector4:
	var b := DataStore.board
	var fw := int(b.get("field_width", 11))
	var fh := int(b.get("field_height", 6))
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for team in [ShipUnit.TEAM_PLAYER, ShipUnit.TEAM_AI]:
		for z in [0, fh - 1]:
			for x in [0, fw - 1]:
				var p := cell_to_world("field", team, x, z)
				min_x = minf(min_x, p.x)
				max_x = maxf(max_x, p.x)
				min_z = minf(min_z, p.z)
				max_z = maxf(max_z, p.z)
	return Vector4(min_x - margin_wu, max_x + margin_wu, min_z - margin_wu, max_z + margin_wu)

static func clamp_to_combat_play_area(pos: Vector3, margin_wu: float = 0.75) -> Vector3:
	var bb := combat_play_bounds_xz(margin_wu)
	pos.x = clampf(pos.x, bb.x, bb.y)
	pos.z = clampf(pos.z, bb.z, bb.w)
	return pos

static func prepare_slot_bounds_xz(slot_type: String, team: int, margin_wu: float = 0.0) -> Vector4:
	var b := DataStore.board
	var fw := int(b.get("field_width", 11))
	var fh := int(b.get("field_height", 6))
	var hw := int(b.get("hangar_width", 14))
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	if slot_type == "field":
		for z in range(fh):
			for x in range(fw):
				var p := cell_to_world("field", team, x, z)
				min_x = minf(min_x, p.x)
				max_x = maxf(max_x, p.x)
				min_z = minf(min_z, p.z)
				max_z = maxf(max_z, p.z)
	else:
		for x in range(hw):
			var p2 := cell_to_world("hangar", team, x, 0)
			min_x = minf(min_x, p2.x)
			max_x = maxf(max_x, p2.x)
			min_z = minf(min_z, p2.z)
			max_z = maxf(max_z, p2.z)
	return Vector4(min_x - margin_wu, max_x + margin_wu, min_z - margin_wu, max_z + margin_wu)

static func prepare_play_bounds_xz(team: int, margin_wu: float = 0.0) -> Vector4:
	var field_bb := prepare_slot_bounds_xz("field", team, margin_wu)
	var hangar_bb := prepare_slot_bounds_xz("hangar", team, margin_wu)
	return Vector4(
		minf(field_bb.x, hangar_bb.x),
		maxf(field_bb.y, hangar_bb.y),
		minf(field_bb.z, hangar_bb.z),
		maxf(field_bb.w, hangar_bb.w)
	)

static func clamp_to_prepare_slot_area(pos: Vector3, slot_type: String, team: int, margin_wu: float = 0.0) -> Vector3:
	var bb := prepare_slot_bounds_xz(slot_type, team, margin_wu)
	pos.x = clampf(pos.x, bb.x, bb.y)
	pos.z = clampf(pos.z, bb.z, bb.w)
	return pos

static func clamp_to_prepare_play_area(pos: Vector3, team: int, margin_wu: float = 0.0) -> Vector3:
	var bb := prepare_play_bounds_xz(team, margin_wu)
	pos.x = clampf(pos.x, bb.x, bb.y)
	pos.z = clampf(pos.z, bb.z, bb.w)
	return pos

static func _in_bounds(slot_type: String, x: int, z: int = 0) -> bool:
	var b := DataStore.board
	var fw := int(b.get("field_width", 11))
	var fh := int(b.get("field_height", 6))
	var hw := int(b.get("hangar_width", 14))
	if slot_type == "field":
		return x >= 0 and x < fw and z >= 0 and z < fh
	return x >= 0 and x < hw and z == 0

func _key(slot_type: String, team: int, x: int, z: int) -> String:
	return "%s_%d_%d_%d" % [slot_type, team, x, z]

func spawn_ship(ship_id: int, star: int, team: int, slot_type: String, x: int, z: int) -> ShipUnit:
	var ship := ShipUnit.new()
	_world_root.add_child(ship)
	ship.setup(ship_id, star, team)
	ship.slot_type = slot_type
	ship.grid_x = x
	ship.grid_z = z
	ship.global_position = cell_to_world(slot_type, team, x, z)
	_ships.append(ship)
	if not ship.is_unmanned:
		var occ := _hangar_occupied if slot_type == "hangar" else _field_occupied
		occ[_key(slot_type, team, x, z)] = ship
	board_changed.emit()
	return ship

func spawn_unmanned(ship_id: int, team: int, world_pos: Vector3, mother: ShipUnit) -> ShipUnit:
	var ship := ShipUnit.new()
	_world_root.add_child(ship)
	ship.setup(ship_id, 1, team)
	ship.slot_type = "field"
	ship.grid_x = mother.grid_x if mother else 0
	ship.grid_z = mother.grid_z if mother else 0
	ship.is_unmanned = true
	ship.unmanned_kind = str(DataStore.get_ship(ship_id).get("unmanned_kind", "combat_drone"))
	ship.mother_ship_id = mother.get_instance_id() if mother else 0
	ship.clear_health_bar()
	ship.global_position = world_pos
	_ships.append(ship)
	board_changed.emit()
	return ship

func remove_ship_node(ship: ShipUnit) -> void:
	if ship == null:
		return
	if not ship.is_unmanned:
		var occ := _hangar_occupied if ship.slot_type == "hangar" else _field_occupied
		occ.erase(_key(ship.slot_type, ship.team_id, ship.grid_x, ship.grid_z))
	_ships.erase(ship)
	if is_instance_valid(ship):
		ship.queue_free()
	board_changed.emit()

func find_empty_hangar(team: int) -> Vector2i:
	var hw := int(DataStore.board.get("hangar_width", 14))
	for x in range(hw):
		if not _hangar_occupied.has(_key("hangar", team, x, 0)):
			return Vector2i(x, 0)
	return Vector2i(-1, -1)

func find_empty_field(team: int) -> Vector2i:
	var fw := int(DataStore.board.get("field_width", 11))
	var fh := int(DataStore.board.get("field_height", 6))
	var random_deploy := bool(DataStore.ai.get("random_deploy", false))
	if random_deploy:
		var empties: Array[Vector2i] = []
		for z in range(fh):
			for x in range(fw):
				if not _field_occupied.has(_key("field", team, x, z)):
					empties.append(Vector2i(x, z))
		if empties.is_empty():
			return Vector2i(-1, -1)
		return empties[randi() % empties.size()]
	## Front row toward enemy first (z=max), then center-out on X.
	var z_order: Array[int] = []
	for z in range(fh - 1, -1, -1):
		z_order.append(z)
	var cx := fw / 2
	var x_order: Array[int] = []
	for d in range(fw):
		var left := cx - d
		var right := cx + d
		if d == 0:
			if left >= 0 and left < fw:
				x_order.append(left)
		else:
			if left >= 0 and left < fw:
				x_order.append(left)
			if right >= 0 and right < fw and right != left:
				x_order.append(right)
	for z in z_order:
		for x in x_order:
			if not _field_occupied.has(_key("field", team, x, z)):
				return Vector2i(x, z)
	return Vector2i(-1, -1)

func count_field(team: int) -> int:
	var n := 0
	for s in _ships:
		if s.team_id == team and s.slot_type == "field" and not s.is_destroyed and not s.is_unmanned:
			n += 1
	return n

func count_alive_field(team: int) -> int:
	return count_field(team)

func field_ships(team: int) -> Array[ShipUnit]:
	var out: Array[ShipUnit] = []
	for s in _ships:
		if s.team_id == team and s.slot_type == "field" and not s.is_destroyed:
			out.append(s)
	return out

func all_ships() -> Array[ShipUnit]:
	return _ships

func is_one_side_cleared() -> bool:
	return count_alive_field(ShipUnit.TEAM_PLAYER) == 0 or count_alive_field(ShipUnit.TEAM_AI) == 0

func try_upgrades_all() -> void:
	var changed := true
	while changed:
		changed = false
		var groups: Dictionary = {}
		for s in _ships:
			if s.is_destroyed:
				continue
			var k := "%d_%d_%d" % [s.team_id, s.ship_id, s.star]
			if not groups.has(k):
				groups[k] = []
			groups[k].append(s)
		for k in groups.keys():
			var arr: Array = groups[k]
			if arr.size() >= 3:
				var keeper: ShipUnit = arr[2]
				if keeper.star < 3:
					for i in range(2):
						_remove_ship(arr[i])
					keeper.upgrade_level()
					changed = true
					break

func _remove_ship(s: ShipUnit) -> void:
	var occ := _hangar_occupied if s.slot_type == "hangar" else _field_occupied
	occ.erase(_key(s.slot_type, s.team_id, s.grid_x, s.grid_z))
	_ships.erase(s)
	s.queue_free()
	board_changed.emit()

func reset_ships_after_round() -> void:
	for s in _ships:
		if s.slot_type == "field":
			s.reload_stats()
			s.global_position = cell_to_world("field", s.team_id, s.grid_x, s.grid_z)
			s.restore_team_yaw()
			s.set_combat_tint(false)

func _on_deploy(payload: Dictionary) -> Dictionary:
	var ship_id := int(payload.get("ship_id", 0))
	var team := int(payload.get("team", 0))
	var slot_type := str(payload.get("slot_type", "field"))
	var x := int(payload.get("x", 0))
	var z := int(payload.get("z", 0))
	var star := int(payload.get("star", 1))
	if not _in_bounds(slot_type, x, z):
		return {"accepted": false, "reason_key": "out_of_bounds"}
	if slot_type == "field":
		if _field_occupied.has(_key("field", team, x, z)):
			return {"accepted": false, "reason_key": "occupied"}
	else:
		if _hangar_occupied.has(_key("hangar", team, x, z)):
			return {"accepted": false, "reason_key": "occupied"}
	spawn_ship(ship_id, star, team, slot_type, x, z)
	try_upgrades_all()
	return {"accepted": true}

func _on_move(payload: Dictionary) -> Dictionary:
	# payload: from_* to_* ship ref via instance_id
	var sid := int(payload.get("ship_instance_id", 0))
	var ship := instance_from_id(sid) as ShipUnit
	if ship == null:
		return {"accepted": false}
	var to_type := str(payload.get("to_slot_type", ship.slot_type))
	var to_x := int(payload.get("to_x", ship.grid_x))
	var to_z := int(payload.get("to_z", ship.grid_z))
	var to_team := ship.team_id
	if not _in_bounds(to_type, to_x, to_z):
		return {"accepted": false, "reason_key": "out_of_bounds"}
	var occ_from := _hangar_occupied if ship.slot_type == "hangar" else _field_occupied
	var occ_to := _hangar_occupied if to_type == "hangar" else _field_occupied
	var to_key := _key(to_type, to_team, to_x, to_z)
	var other: ShipUnit = occ_to.get(to_key)
	occ_from.erase(_key(ship.slot_type, ship.team_id, ship.grid_x, ship.grid_z))
	if other and other != ship:
		occ_to.erase(to_key)
		other.slot_type = ship.slot_type
		other.grid_x = ship.grid_x
		other.grid_z = ship.grid_z
		other.global_position = cell_to_world(other.slot_type, other.team_id, other.grid_x, other.grid_z)
		var ok := _hangar_occupied if other.slot_type == "hangar" else _field_occupied
		ok[_key(other.slot_type, other.team_id, other.grid_x, other.grid_z)] = other
	ship.slot_type = to_type
	ship.grid_x = to_x
	ship.grid_z = to_z
	ship.global_position = cell_to_world(to_type, to_team, to_x, to_z)
	occ_to[to_key] = ship
	try_upgrades_all()
	board_changed.emit()
	return {"accepted": true}

func _on_sell(payload: Dictionary) -> Dictionary:
	var sid := int(payload.get("ship_instance_id", 0))
	var ship := instance_from_id(sid) as ShipUnit
	if ship == null or ship.team_id != ShipUnit.TEAM_PLAYER:
		return {"accepted": false}
	var gold := ship.get_cost()
	_remove_ship(ship)
	return {"accepted": true, "gold": gold}

func begin_drag(ship: ShipUnit) -> void:
	if not _prepare_mode:
		return
	if ship.team_id != ShipUnit.TEAM_PLAYER and not get_tree().paused:
		return
	_drag_ship = ship

func update_drag(world_pos: Vector3) -> void:
	if _drag_ship:
		var pos := Vector3(world_pos.x, 1.0, world_pos.z)
		pos = clamp_to_prepare_play_area(pos, _drag_ship.team_id, 0.0)
		_drag_ship.global_position = pos

func end_drag(sell_zone: bool, hover_slot: Dictionary) -> void:
	if _drag_ship == null:
		return
	var ship := _drag_ship
	_drag_ship = null
	if sell_zone:
		var r := AdminBus.request(&"board.sell", {"ship_instance_id": ship.get_instance_id()})
		if r.get("accepted", false):
			var g := int(r.get("gold", ship.get_cost()))
			# gold credited by match via signal — emit board_changed; MatchHud listens? Use group
			get_tree().call_group("match_root", "on_ship_sold", g)
		else:
			ship.global_position = cell_to_world(ship.slot_type, ship.team_id, ship.grid_x, ship.grid_z)
		return
	if hover_slot.is_empty():
		ship.global_position = cell_to_world(ship.slot_type, ship.team_id, ship.grid_x, ship.grid_z)
		return
	var to_type := str(hover_slot.get("slot_type", "field"))
	if to_type == "field":
		var match_node := get_tree().get_first_node_in_group("match_root") as MatchRoot
		if match_node:
			var lim := match_node.match_ctrl.population_limit()
			var from_field := ship.slot_type == "field"
			var deployed := count_field(ship.team_id)
			if not from_field and deployed >= lim:
				get_tree().call_group("match_root", "show_notice", "对战区已满")
				ship.global_position = cell_to_world(ship.slot_type, ship.team_id, ship.grid_x, ship.grid_z)
				return
	AdminBus.request(&"board.move", {
		"ship_instance_id": ship.get_instance_id(),
		"to_slot_type": hover_slot.get("slot_type"),
		"to_x": hover_slot.get("x"),
		"to_z": hover_slot.get("z"),
	})

func _cancel_drag() -> void:
	if _drag_ship:
		_drag_ship.global_position = cell_to_world(_drag_ship.slot_type, _drag_ship.team_id, _drag_ship.grid_x, _drag_ship.grid_z)
	_drag_ship = null

func pick_ship_at(origin: Vector3, dir: Vector3) -> ShipUnit:
	## Any team (player + AI) for hover/info; drag still gated in PointerInput / begin_drag.
	var best: ShipUnit = null
	var best_d := 9999.0
	for s in _ships:
		if s.is_destroyed:
			continue
		var to_s := s.global_position - origin
		var t := to_s.dot(dir)
		if t < 0.0:
			continue
		var closest := origin + dir * t
		var d := closest.distance_to(s.global_position)
		# Slightly larger pick for distant AI field ships.
		var hit_r := 1.6 if s.team_id == ShipUnit.TEAM_AI else 1.35
		if d < hit_r and d < best_d:
			best_d = d
			best = s
	return best

func pick_slot_at(world: Vector3, team: int = ShipUnit.TEAM_PLAYER) -> Dictionary:
	var best := {}
	var best_d := 2.5
	var b := DataStore.board
	var fw := int(b.get("field_width", 11))
	var fh := int(b.get("field_height", 6))
	for z in range(fh):
		for x in range(fw):
			var p := cell_to_world("field", team, x, z)
			var d := Vector2(world.x - p.x, world.z - p.z).length()
			if d < best_d:
				best_d = d
				best = {"slot_type": "field", "x": x, "z": z, "team": team}
	var hw := int(b.get("hangar_width", 14))
	for x in range(hw):
		var p2 := cell_to_world("hangar", team, x, 0)
		var d2 := Vector2(world.x - p2.x, world.z - p2.z).length()
		if d2 < best_d:
			best_d = d2
			best = {"slot_type": "hangar", "x": x, "z": 0, "team": team}
	return best

func recalculate_fetters(team: int) -> Array:
	var counts: Dictionary = {}
	for s in field_ships(team):
		var ship := DataStore.get_ship(s.ship_id)
		for fid in ship.get("fetter_ids", []):
			counts[fid] = int(counts.get(fid, 0)) + 1
	var active: Array = []
	for fid in counts.keys():
		var fetter: Dictionary = DataStore.fetters.get(fid, {})
		var effects = fetter.get("effects", [])
		var best = null
		var best_c := -1
		for e in effects:
			var need := int(e.get("champion_count", 0))
			if need <= int(counts[fid]) and need >= best_c:
				best_c = need
				best = e
		if best != null:
			var payload := {"fetter_id": fid, "champion_count": counts[fid], "effect": best}
			var r := AdminBus.request(&"fetter.activate", payload)
			if r.get("accepted", true):
				active.append({"fetter_id": fid, "count": counts[fid], "effect": best})
	var shield_mul := 1.0
	var armor_mul := 1.0
	var repair_mul := 1.0
	var speed_mul := 1.0
	var attack_speed_mul := 1.0
	var armor_hp_pct := 0.0
	var shield_hp_pct := 0.0
	var flat_hp := 0.0
	for a in active:
		var eff: Dictionary = a["effect"]
		var et := str(eff.get("effect_type", ""))
		var vt := str(eff.get("effect_value_type", ""))
		var val := float(eff.get("value", 0.0))
		var target := str(eff.get("effect_target", ""))
		var mul := _fetter_multiplier(vt, val)
		if target == "SelfAll":
			match et:
				"ShieldResist":
					shield_mul *= mul
				"ArmorResist":
					armor_mul *= mul
				"RemoteRepair", "Repair":
					repair_mul *= mul
				"Speed":
					speed_mul *= mul
				"AttackSpeed":
					attack_speed_mul *= mul
				"ArmorHP":
					armor_hp_pct += val if vt == "Percentage" else 0.0
				"ShieldHP":
					shield_hp_pct += val if vt == "Percentage" else 0.0
				"FlatHP":
					flat_hp += val
	for s in field_ships(team):
		s.damage_pct_bonus = 0.0
		var ship := DataStore.get_ship(s.ship_id)
		for a in active:
			if a["fetter_id"] in ship.get("fetter_ids", []):
				var eff: Dictionary = a["effect"]
				if str(eff.get("effect_type", "")) == "Damage" and str(eff.get("effect_value_type", "")) == "Percentage":
					s.damage_pct_bonus += float(eff.get("value", 0.0))
		s.apply_fetter_mods(shield_mul, armor_mul, repair_mul, speed_mul)
		# Recompute cycle from baseline — never stack-divide attack_duration across recalcs.
		var base_cycle := s.base_attack_duration if s.base_attack_duration > 0.0 else s.attack_duration
		if attack_speed_mul != 1.0 and base_cycle > 0.0:
			s.attack_duration = maxf(0.2, base_cycle / attack_speed_mul)
		else:
			s.attack_duration = base_cycle
		if armor_hp_pct > 0.0:
			s.max_armor *= 1.0 + armor_hp_pct / 100.0
			s.armor_hp = minf(s.armor_hp * (1.0 + armor_hp_pct / 100.0), s.max_armor)
		if shield_hp_pct > 0.0:
			s.max_shield *= 1.0 + shield_hp_pct / 100.0
			s.shield_hp = minf(s.shield_hp * (1.0 + shield_hp_pct / 100.0), s.max_shield)
		if flat_hp > 0.0:
			s.max_structure += flat_hp
			s.structure_hp = minf(s.structure_hp + flat_hp, s.max_structure)
	return active

static func _fetter_multiplier(value_type: String, value: float) -> float:
	if value_type == "Multiplier":
		return value
	if value_type == "Percentage":
		return 1.0 + value / 100.0
	return 1.0
