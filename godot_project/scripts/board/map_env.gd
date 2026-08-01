extends Node3D
class_name MapEnv
## Shipped match map only: sky/ground + player/AI 空堡.
## Citadel sits on the player-side of the board (screen-bottom / +Z).
## Invisible FitBox matches mesh AABB; its board-facing top corner pins to the
## rightmost field hex (AI: leftmost). Body extends outward so it does not cover hexes.

const STRUCT_DIR := "res://assets/models/structures"
const CITADEL_TEX := "res://assets/textures/structures_png/citadel_d.png"
const CITADEL_MESH_ASCII := "res://assets/models/structures/citadel.glb"

## Player-side citadel node (for world HP bar). AI citadel is not tracked in v1.
var player_citadel: Node3D
## Nullsec seat titan berth (MULTIPLAYER_PVP §2.4a). Null outside nullsec / no race picked.
var titan_berth: TitanBerth
## PVP rival seat titan on the far side (bow toward local home).
var rival_titan_berth: TitanBerth
var belt: AsteroidBelt

func build(mode: String = "endless") -> Node3D:
	## Nullsec home field shows the seat titan instead of 空堡 (MULTIPLAYER_PVP §2.4a).
	if mode == "nullsec":
		_spawn_asteroid_belt()
		_spawn_titan_berth()
		_spawn_rival_titan_berth()
		return titan_berth
	var size := float(DataStore.visual.get("citadel_target_size", 12.0))
	if UiLayout.is_mobile():
		size = float(DataStore.visual.get("citadel_mobile_target_size", minf(size, 8.0)))
	# Bottom-right of the whole board (hangar tip) — keeps mesh off field hexes.
	var right_cell := _rightmost_hangar_cell()
	player_citadel = _spawn_citadel_under_board("空堡", size, ShipUnit.TEAM_PLAYER, right_cell, true)
	if mode != "endless":
		var left_cell := _leftmost_hangar_cell()
		_spawn_citadel_under_board("空堡", size, ShipUnit.TEAM_AI, left_cell, false)
	_spawn_asteroid_belt()
	return player_citadel

func _spawn_asteroid_belt() -> void:
	belt = AsteroidBelt.new()
	add_child(belt)
	belt.build()
	print("[MapEnv] asteroid belt anchors=%d" % belt.mining_anchors.size())

func _spawn_titan_berth() -> void:
	var race := _local_seat_titan_race()
	if race == "":
		print("[MapEnv] nullsec berth skipped — local seat has no titan race")
		return
	titan_berth = TitanBerth.new()
	add_child(titan_berth)
	if not titan_berth.build(race, belt.bounds_box(), true):
		titan_berth.queue_free()
		titan_berth = null

func _spawn_rival_titan_berth() -> void:
	## Built once for the doomsday target, but only shown on PVP rounds (§2.4a).
	var race := _rival_seat_titan_race()
	if race == "":
		print("[MapEnv] nullsec rival berth skipped — no rival titan race")
		return
	rival_titan_berth = TitanBerth.new()
	add_child(rival_titan_berth)
	if not rival_titan_berth.build(race, belt.bounds_box(), false):
		rival_titan_berth.queue_free()
		rival_titan_berth = null
		return
	rival_titan_berth.visible = false

func _local_seat_titan_race() -> String:
	var payload: Dictionary = GameSession.pending_nullsec if GameSession else {}
	if bool(payload.get("spectator", false)):
		return ""
	var seats: Array = payload.get("seats", []) as Array
	var local_seat := int(payload.get("local_seat", -1))
	for s in seats:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = s
		if int(d.get("seat_id", -1)) == local_seat:
			var race := str(d.get("titan_race", ""))
			if NullsecNetSession.is_player_race(race):
				return race
			return ""
	var fallback := str(payload.get("local_titan_race", ""))
	return fallback if NullsecNetSession.is_player_race(fallback) else ""

func _rival_seat_titan_race() -> String:
	var payload: Dictionary = GameSession.pending_nullsec if GameSession else {}
	var seats: Array = payload.get("seats", []) as Array
	var local_seat := int(payload.get("local_seat", -1))
	## Prefer explicit assignment rival; else first other occupied seat with a race.
	var assignments: Dictionary = payload.get("assignments", {}) as Dictionary
	var rival_from_assign := int(assignments.get("rival_seat", assignments.get(str(local_seat), -1)))
	if rival_from_assign >= 0:
		for s in seats:
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = s
			if int(d.get("seat_id", -1)) == rival_from_assign:
				var r := str(d.get("titan_race", ""))
				if NullsecNetSession.is_player_race(r):
					return r
	for s in seats:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var d2: Dictionary = s
		if int(d2.get("seat_id", -1)) == local_seat:
			continue
		var kind := str(d2.get("kind", d2.get("type", "player")))
		if kind == "empty":
			continue
		var race := str(d2.get("titan_race", ""))
		if NullsecNetSession.is_player_race(race):
			return race
	var fb := str(payload.get("rival_titan_race", ""))
	return fb if NullsecNetSession.is_player_race(fb) else ""

func _rightmost_hangar_cell() -> Vector3:
	## Player hangar x=0 is the +X tip (hangar_offset_x < 0).
	return _cell_to_world("hangar", ShipUnit.TEAM_PLAYER, 0, 0)

func _leftmost_hangar_cell() -> Vector3:
	return _cell_to_world("hangar", ShipUnit.TEAM_AI, 0, 0)

func _rightmost_field_cell() -> Vector3:
	return _extreme_field_cell(true)

func _leftmost_field_cell() -> Vector3:
	return _extreme_field_cell(false)

func _extreme_field_cell(want_max_x: bool) -> Vector3:
	var b := DataStore.board
	var fh := int(b.get("field_height", 6))
	var best := Vector3.ZERO
	var best_x := -INF if want_max_x else INF
	var best_z := -INF
	var found := false
	for team in [ShipUnit.TEAM_PLAYER, ShipUnit.TEAM_AI]:
		for z in range(fh):
			var cols := BoardController.field_cols_at(z)
			for x in range(cols):
				var p := _cell_to_world("field", team, x, z)
				var better := false
				if want_max_x:
					if p.x > best_x + 0.001 or (absf(p.x - best_x) <= 0.001 and p.z > best_z):
						better = true
				else:
					if p.x < best_x - 0.001 or (absf(p.x - best_x) <= 0.001 and p.z < best_z):
						better = true
				if better:
					best = p
					best_x = p.x
					best_z = p.z
					found = true
	if not found:
		return Vector3(10.0, 0.05, 6.25)
	print("[MapEnv] edge cell (%s)=%s" % ["rightmost" if want_max_x else "leftmost", best])
	return best

func _cell_to_world(slot_type: String, team: int, x: int, z: int) -> Vector3:
	return BoardController.cell_to_world(slot_type, team, x, z)

func _spawn_citadel_under_board(
		stem: String, target_size: float, team_id: int, anchor_cell: Vector3, player_side: bool
) -> Node3D:
	# Prefer ASCII mesh path — Chinese 空堡.glb often fails to resolve from Android PCK.
	var path := ""
	if ResourceLoader.exists(CITADEL_MESH_ASCII):
		path = CITADEL_MESH_ASCII
	if path == "":
		path = _find_glb(STRUCT_DIR, "citadel")
	if path == "":
		path = _find_glb(STRUCT_DIR, stem)
	if path == "" or not ResourceLoader.exists(path):
		push_warning("MapEnv missing citadel mesh: " + stem)
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var n := packed.instantiate() as Node3D
	if n == null:
		return null
	n.name = "Citadel_%s" % ("P" if team_id == ShipUnit.TEAM_PLAYER else "AI")
	n.set_meta("team_id", team_id)
	add_child(n)
	# Predict seat just outside the edge cell (player: +X/+Z hangar side; AI: −X/−Z).
	var seat_guess := anchor_cell + (
		Vector3(6.0, -5.0, 8.0) if player_side else Vector3(-6.0, -5.0, -8.0)
	)
	n.position = Vector3.ZERO
	n.rotation_degrees = Vector3(0, _yaw_face_point(seat_guess, Vector3.ZERO), 0)
	n.scale = Vector3.ONE
	_normalize_size(n, target_size)
	# Unscaled local AABB; root.scale applied via transform.basis when pinning.
	var aabb := _aabb_unscaled_local(n)
	if aabb.size.length() < 0.0001:
		push_warning("MapEnv citadel AABB empty")
		return n
	_attach_invisible_fit_box(n, aabb)
	var corner := _pick_pin_corner_world_aligned(n, aabb, player_side)
	# basis only — never full transform (stale position would corrupt the pin).
	n.position = anchor_cell - (n.transform.basis * corner)
	var tex_path := CITADEL_TEX
	var mapped: String = str(DataStore.ship_textures.get("citadel_diffuse", ""))
	if mapped != "":
		tex_path = mapped
	_apply_ship_like_hull(n, tex_path, team_id)
	MobileModelLoad.apply_tree(n, target_size)
	_attach_citadel_light(n, player_side)
	n.position.y -= 0.02
	var scaled_size := Vector3(aabb.size.x * n.scale.x, aabb.size.y * n.scale.y, aabb.size.z * n.scale.z)
	print("[MapEnv] citadel under board team=%d pos=%s anchor=%s scaled_size=%s corner=%s" % [
		team_id, n.position, anchor_cell, scaled_size, corner
	])
	return n

func _pick_pin_corner_world_aligned(root: Node3D, aabb: AABB, player_side: bool) -> Vector3:
	## Among 4 top-face corners, pick the one that places AABB center off-board
	## (player: +Z toward hangar; AI: −Z) and outward on X.
	var y := aabb.position.y + aabb.size.y
	var candidates: Array[Vector3] = [
		Vector3(aabb.position.x, y, aabb.position.z),
		Vector3(aabb.position.x + aabb.size.x, y, aabb.position.z),
		Vector3(aabb.position.x, y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x + aabb.size.x, y, aabb.position.z + aabb.size.z),
	]
	var bas := root.transform.basis
	var best_c := candidates[0]
	var best_score := -INF
	for c in candidates:
		var world_c: Vector3 = bas * c
		var trial_pos: Vector3 = -world_c
		var center: Vector3 = trial_pos + (bas * aabb.get_center())
		var score := 0.0
		if player_side:
			# Strongly prefer right of board (+X); only mild hangar-side (+Z) so mesh clears seats.
			score = center.x * 4.0 + center.z * 0.75
		else:
			score = -center.x * 4.0 - center.z * 0.75
		if score > best_score:
			best_score = score
			best_c = c
	return best_c

func _yaw_face_point(from: Vector3, target: Vector3) -> float:
	var flat := Vector3(target.x - from.x, 0.0, target.z - from.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	flat = flat.normalized()
	return rad_to_deg(atan2(-flat.x, -flat.z))

func _aabb_unscaled_local(root: Node3D) -> AABB:
	## Mesh AABB in root local space WITHOUT root.scale (scale applied via basis when pinning).
	var result := AABB()
	var first := true
	for mi in _find_meshes(root):
		if str(mi.name) == "FitBox":
			continue
		var xf := _xform_to_ancestor(root, mi)
		var local_aabb: AABB = mi.get_aabb()
		for i in range(8):
			var p: Vector3 = xf * local_aabb.get_endpoint(i)
			if first:
				result = AABB(p, Vector3.ZERO)
				first = false
			else:
				result = result.expand(p)
	return result

func _attach_invisible_fit_box(root: Node3D, aabb: AABB) -> void:
	var old := root.get_node_or_null("FitBox")
	if old:
		old.queue_free()
	var box := MeshInstance3D.new()
	box.name = "FitBox"
	# Child of scaled root: use unscaled local AABB directly.
	box.mesh = _make_wire_box_mesh(aabb.size)
	box.position = aabb.get_center()
	box.visible = false
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 1.0, 0.85, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material_override = mat
	root.add_child(box)

func _refresh_fit_box(root: Node3D, aabb: AABB) -> void:
	var box := root.get_node_or_null("FitBox") as MeshInstance3D
	if box == null:
		_attach_invisible_fit_box(root, aabb)
		return
	box.mesh = _make_wire_box_mesh(aabb.size)
	box.position = aabb.get_center()

func _make_wire_box_mesh(size: Vector3) -> ArrayMesh:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var corners: Array[Vector3] = [
		Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz),
		Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
	]
	var edges: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]
	var verts := PackedVector3Array()
	for e in edges:
		verts.append(corners[e.x])
		verts.append(corners[e.y])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh

func _xform_to_ancestor(ancestor: Node3D, leaf: Node) -> Transform3D:
	var chain: Array[Node3D] = []
	var walk: Node = leaf
	while walk != null and walk != ancestor:
		if walk is Node3D:
			chain.push_front(walk as Node3D)
		walk = walk.get_parent()
	var xf := Transform3D.IDENTITY
	for n in chain:
		xf = xf * n.transform
	return xf

func _find_glb(dir_path: String, stem: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	var exact := ""
	var fuzzy := ""
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.get_extension().to_lower() == "glb":
			var base := fn.get_basename()
			if base == stem:
				exact = dir_path.path_join(fn)
			elif stem in base and fuzzy == "":
				if base != stem + "2":
					fuzzy = dir_path.path_join(fn)
		fn = dir.get_next()
	if exact != "":
		return exact
	return fuzzy

func _normalize_size(root: Node3D, target: float) -> void:
	## Measure unscaled mesh AABB, then set uniform scale so longest axis = target.
	var result := AABB()
	var first := true
	for mi in _find_meshes(root):
		if str(mi.name) == "FitBox":
			continue
		var xf := _xform_to_ancestor(root, mi)
		var local_aabb: AABB = mi.get_aabb()
		for i in range(8):
			var p: Vector3 = xf * local_aabb.get_endpoint(i)
			if first:
				result = AABB(p, Vector3.ZERO)
				first = false
			else:
				result = result.expand(p)
	var longest := maxf(result.size.x, maxf(result.size.y, result.size.z))
	if longest < 0.0001:
		return
	root.scale = Vector3.ONE * (target / longest)

func _attach_citadel_light(root: Node3D, player_side: bool) -> void:
	## Dedicated citadel key light — independent of board ship fill lights.
	var energy := float(DataStore.visual.get("citadel_light_energy", 3.2))
	if energy <= 0.001:
		return
	var light := OmniLight3D.new()
	light.name = "CitadelLight"
	light.light_energy = energy
	light.omni_range = float(DataStore.visual.get("citadel_light_range", 28.0))
	light.light_color = Color(
		float(DataStore.visual.get("citadel_light_color_r", 1.0)),
		float(DataStore.visual.get("citadel_light_color_g", 0.92)),
		float(DataStore.visual.get("citadel_light_color_b", 0.78))
	)
	light.shadow_enabled = false
	## Local offset above/outward so the hull catches the key without bleaching ships.
	light.position = Vector3(4.0 if player_side else -4.0, 10.0, 3.0 if player_side else -3.0)
	root.add_child(light)

func _apply_ship_like_hull(root: Node, tex_path: String, team_id: int) -> void:
	var tex := UiAssets.tex_ship_bake(tex_path) if tex_path != "" else null
	var ntex: Texture2D = null
	var mobile := UiLayout.is_mobile()
	if not mobile and tex_path != "" and tex_path.ends_with("_d.png"):
		ntex = UiAssets.tex_ship_bake(tex_path.replace("_d.png", "_n.png"))
	# Dimmer than ships — background fortress, not competing with board units.
	var hull := Color(0.42, 0.36, 0.28)
	var team := Color(0.28, 0.34, 0.42) if team_id == ShipUnit.TEAM_PLAYER else Color(0.45, 0.28, 0.26)
	hull = hull.lerp(team, 0.12)
	hull = hull.darkened(float(DataStore.visual.get("citadel_darken", 0.35)))
	for mi in _find_meshes(root):
		if str(mi.name) == "FitBox":
			continue
		var mat := StandardMaterial3D.new()
		mat.shading_mode = (
			BaseMaterial3D.SHADING_MODE_PER_VERTEX if mobile else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mat.texture_repeat = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if tex:
			mat.albedo_texture = tex
			mat.albedo_color = hull
			if not mobile:
				mat.ao_enabled = true
				mat.ao_texture = tex
				mat.ao_light_affect = 0.55
				mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		else:
			mat.albedo_color = hull.darkened(0.1)
		if ntex:
			mat.normal_enabled = true
			mat.normal_texture = ntex
			mat.normal_scale = 0.85
		mat.metallic = 0.12 if mobile else 0.18
		mat.metallic_specular = 0.15 if mobile else 0.22
		mat.roughness = 0.8 if mobile else 0.72
		mi.material_override = mat
		mi.material_overlay = null
		mi.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mobile
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
		if mi.mesh:
			for si in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(si, mat)

func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_meshes(c))
	return out
