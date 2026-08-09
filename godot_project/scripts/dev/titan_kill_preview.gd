extends Node3D
## Titan kill carousel preview — one race at a time.
## Intact: ShipUnit + §0 tq_titan_*.
## Wreck mesh: real extracted per-race TQ wreck mesh (all four races available).
## Hull and wreck both use ShipUnit + the same §0 bundle / ShipLook material channel.
## Kill FX: Echoes ship_death cutout timeline (explosion_005 + fire_01_yd) + TQ death audio.

const RACES: Array[Dictionary] = [
	{
		"id": 911,
		"wreck_id": 921,
		"race": "A",
		"race_id": "amarr",
		"hull": "at1",
		"model_key": "tq_titan_a",
		"wreck_model_key": "tq_titan_wreck_a",
		"model_long_axis": 2200.0,
		"name": "神使级",
		"name_en": "Avatar",
		"label": "神使级 Avatar",
		"color": Color(1.0, 0.82, 0.28),
	},
	{
		"id": 912,
		"wreck_id": 922,
		"race": "C",
		"race_id": "caldari",
		"hull": "ct1",
		"model_key": "tq_titan_c",
		"wreck_model_key": "tq_titan_wreck_c",
		"model_long_axis": 2200.0,
		"name": "勒维亚坦级",
		"name_en": "Leviathan",
		"label": "勒维亚坦级 Leviathan",
		"color": Color(0.35, 0.72, 1.0),
	},
	{
		"id": 913,
		"wreck_id": 923,
		"race": "G",
		"race_id": "gallente",
		"hull": "gt1",
		"model_key": "tq_titan_g",
		"wreck_model_key": "tq_titan_wreck_g",
		"model_long_axis": 2200.0,
		"name": "俄洛巴斯级",
		"name_en": "Erebus",
		"label": "俄洛巴斯级 Erebus",
		"color": Color(0.35, 1.0, 0.55),
	},
	{
		"id": 914,
		"wreck_id": 924,
		"race": "M",
		"race_id": "minmatar",
		"hull": "mt1",
		"model_key": "tq_titan_m",
		"wreck_model_key": "tq_titan_wreck_m",
		"model_long_axis": 2200.0,
		"name": "拉格纳洛克级",
		"name_en": "Ragnarok",
		"label": "拉格纳洛克级 Ragnarok",
		"color": Color(1.0, 0.42, 0.12),
	},
]

## Design §2.6
const INTACT_S: float = 2.0
const EXPLODE_S: float = 2.4
const WRECK_HOLD_S: float = 5.0
const RACE_CYCLE_S: float = INTACT_S + EXPLODE_S + WRECK_HOLD_S

## Display size: match wreck export normalize (longest ≈ 8).
const DISPLAY_LONGEST: float = 8.0

## Bow markers (dev diagnosis): cyan = intact hull, orange = wreck.
const SHOW_BOW_MARKERS: bool = true
const BOW_COLOR_HULL: Color = Color(0.25, 1.0, 1.0, 1.0)
const BOW_COLOR_WRECK: Color = Color(1.0, 0.55, 0.1, 1.0)

const _CAM_MOVE_SPEED: float = 18.0
const _CAM_PITCH_SPEED: float = 48.0
const _CAM_YAW_SPEED: float = 56.0
const _KILL_FX_SCRIPT: GDScript = preload("res://scripts/vfx/echoes_ship_death_fx.gd")

var _entries: Array[Dictionary] = []
var _t: float = 0.0
var _hud: Label = null
var _cam: Camera3D = null
var _cam_base_pos: Vector3 = Vector3(0, 3.2, 16.0)
var _cam_base_pitch_deg: float = -8.0
var _cam_base_yaw_deg: float = 0.0
var _label: Label3D = null


func _ready() -> void:
	_inject_preview_ships()
	_build_env()
	for i: int in RACES.size():
		_entries.append(_spawn_slot(RACES[i]))
	_build_hud()
	_t = 0.0


func _inject_preview_ships() -> void:
	if DataStore == null:
		push_error("TitanKillPreview: DataStore missing")
		return
	for def: Dictionary in RACES:
		var sid: int = TypedVariant.as_int(def.get("id", 0), 0)
		DataStore.ships[sid] = {
			"id": sid,
			"name": str(def.get("name", "")),
			"name_en": str(def.get("name_en", "")),
			"model_key": str(def.get("model_key", "")),
			"model_long_axis": TypedVariant.as_float(def.get("model_long_axis", 0.0), 0.0),
			"race": str(def.get("race_id", "")),
			"ship_group": "titan",
			"cost": 0,
			"fetter_ids": [],
			"tags": [str(def.get("race_id", "")), "titan"],
			"is_logistic": false,
			"weapon_fx": "laser",
			"function_slots": {"slots": []},
			"stars": [
				{
					"attack_range": 8,
					"damage": {"emp": 1.0, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0},
					"repair": {"shield": 0.0, "armor": 0.0, "structure": 0.0},
					"shield": 100.0,
					"armor": 100.0,
					"structure": 100.0,
					"shield_resist": {},
					"armor_resist": {},
					"structure_resist": {},
					"attack_duration": 1.0,
				}
			],
		}
		var wreck_key: String = str(def.get("wreck_model_key", ""))
		var wreck_mesh: String = "res://assets/models/ships/%s/model.glb" % wreck_key
		if ResourceLoader.exists(wreck_mesh):
			var wreck_id: int = TypedVariant.as_int(def.get("wreck_id", 0), 0)
			DataStore.ships[wreck_id] = {
				"id": wreck_id,
				"name": "%s残骸" % str(def.get("name", "")),
				"name_en": "%s Wreck" % str(def.get("name_en", "")),
				"model_key": wreck_key,
				"model_long_axis": TypedVariant.as_float(def.get("model_long_axis", 0.0), 0.0),
				"race": str(def.get("race_id", "")),
				"ship_group": "titan",
				"cost": 0,
				"fetter_ids": [],
				"tags": [str(def.get("race_id", "")), "titan", "wreck"],
				"is_logistic": false,
				"weapon_fx": "",
				"function_slots": {"slots": []},
				"stars": [
					{
						"attack_range": 0,
						"damage": {"emp": 0.0, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0},
						"repair": {"shield": 0.0, "armor": 0.0, "structure": 0.0},
						"shield": 1.0,
						"armor": 1.0,
						"structure": 1.0,
						"shield_resist": {},
						"armor_resist": {},
						"structure_resist": {},
						"attack_duration": 99.0,
					}
				],
			}


func _process(delta: float) -> void:
	_update_camera_free(delta)
	_t += delta
	var total: float = RACE_CYCLE_S * float(RACES.size())
	var abs_t: float = fmod(_t, total)
	var race_i: int = floori(abs_t / RACE_CYCLE_S)
	var phase: float = fmod(abs_t, RACE_CYCLE_S)
	var state: String = "intact"
	var explode_amt: float = 0.0
	if phase < INTACT_S:
		state = "intact"
	elif phase < INTACT_S + EXPLODE_S:
		state = "explode"
		explode_amt = (phase - INTACT_S) / EXPLODE_S
	else:
		state = "wreck"
	for i: int in _entries.size():
		_apply_state(_entries[i], i == race_i, state, explode_amt)
	var def: Dictionary = RACES[race_i]
	if _label:
		var entry: Dictionary = _entries[race_i]
		var miss_v: Variant = entry.get("miss", PackedStringArray())
		var miss: PackedStringArray = miss_v if miss_v is PackedStringArray else PackedStringArray()
		var miss_txt: String = (" · 缺:" + ",".join(miss)) if not miss.is_empty() else ""
		_label.text = "%s%s" % [str(def.get("label", "")), miss_txt]
		_label.modulate = def["color"]
	if _hud:
		_hud.text = (
			"轮播 %d/%d %s  phase=%s  t=%.1f/%.1fs  | §0材质  | 船头标识 青=舰体 橙=残骸  | WASD QE RF TG"
			% [race_i + 1, RACES.size(), str(def.get("label", "")), state, phase, RACE_CYCLE_S]
		)


func _update_camera_free(delta: float) -> void:
	if _cam == null:
		return
	var speed: float = _CAM_MOVE_SPEED
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= 2.5
	var cam_basis: Basis = _cam.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	var right: Vector3 = cam_basis.x
	var up: Vector3 = Vector3.UP
	var move: Vector3 = Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move += forward
	if Input.is_physical_key_pressed(KEY_S):
		move -= forward
	if Input.is_physical_key_pressed(KEY_A):
		move -= right
	if Input.is_physical_key_pressed(KEY_D):
		move += right
	if Input.is_physical_key_pressed(KEY_Q):
		move -= up
	if Input.is_physical_key_pressed(KEY_E):
		move += up
	if move != Vector3.ZERO:
		_cam_base_pos += move.normalized() * speed * delta
	var pitch_delta: float = 0.0
	if Input.is_physical_key_pressed(KEY_R):
		pitch_delta += _CAM_PITCH_SPEED * delta
	if Input.is_physical_key_pressed(KEY_F):
		pitch_delta -= _CAM_PITCH_SPEED * delta
	if pitch_delta != 0.0:
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg + pitch_delta, -89.0, 89.0)
	var yaw_delta: float = 0.0
	if Input.is_physical_key_pressed(KEY_T):
		yaw_delta -= _CAM_YAW_SPEED * delta
	if Input.is_physical_key_pressed(KEY_G):
		yaw_delta += _CAM_YAW_SPEED * delta
	if yaw_delta != 0.0:
		_cam_base_yaw_deg += yaw_delta
	_cam.position = _cam_base_pos
	_cam.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)


func _build_env() -> void:
	var look: Dictionary = {}
	if DataStore and DataStore.visual is Dictionary:
		var sl_v: Variant = DataStore.visual.get("ship_look", {})
		if sl_v is Dictionary:
			look = sl_v

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.light_energy = maxf(TypedVariant.as_float(look.get("key_energy", 1.0), 1.0), 1.35)
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(
		TypedVariant.as_float(look.get("key_pitch_deg", -42.0), -42.0),
		TypedVariant.as_float(look.get("key_yaw_deg", 35.0), 35.0),
		0.0
	)
	add_child(light)

	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.light_energy = 1.1
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.rotation_degrees = Vector3(-18, -140, 0)
	add_child(rim)

	var fill: OmniLight3D = OmniLight3D.new()
	fill.light_energy = 3.2
	fill.omni_range = 90.0
	fill.position = Vector3(0, 8, 10)
	add_child(fill)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 42.0
	_cam_base_pos = Vector3(0, 3.2, 16.0)
	_cam_base_pitch_deg = -8.0
	_cam_base_yaw_deg = 0.0
	_cam.position = _cam_base_pos
	_cam.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
	add_child(_cam)

	var bg: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(
		TypedVariant.as_float(look.get("ambient_r", 0.212), 0.212),
		TypedVariant.as_float(look.get("ambient_g", 0.227), 0.227),
		TypedVariant.as_float(look.get("ambient_b", 0.259), 0.259)
	)
	env.ambient_light_energy = maxf(TypedVariant.as_float(look.get("ambient_energy", 1.15), 1.15), 1.9)
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.3
	bg.environment = env
	add_child(bg)

	var park_label: Label3D = Label3D.new()
	park_label.text = "停泊带 · 原玩家空堡位"
	park_label.font_size = 28
	park_label.position = Vector3(0, -0.15, 5.0)
	park_label.modulate = Color(0.65, 0.7, 0.8)
	add_child(park_label)

	_label = Label3D.new()
	_label.font_size = 36
	_label.position = Vector3(0, 5.2, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)


func _spawn_slot(def: Dictionary) -> Dictionary:
	## All races share origin; carousel toggles visibility.
	var root: Node3D = Node3D.new()
	root.name = "KillSlot_%s" % str(def.get("race", ""))
	root.position = Vector3.ZERO
	root.visible = false
	add_child(root)

	var intact_holder: Node3D = Node3D.new()
	intact_holder.name = "Intact"
	root.add_child(intact_holder)
	var unit: ShipUnit = ShipUnit.new()
	intact_holder.add_child(unit)
	unit.setup(TypedVariant.as_int(def.get("id", 0), 0), 1, ShipUnit.TEAM_PLAYER)
	if unit.has_method("clear_health_bar"):
		unit.clear_health_bar()
	## Normalize intact to DISPLAY_LONGEST using *world* AABB (includes ShipUnit scale).
	call_deferred("_normalize_node_to_display", intact_holder, BOW_COLOR_HULL)

	var wreck: Node3D = Node3D.new()
	wreck.name = "Wreck"
	wreck.visible = false
	root.add_child(wreck)
	var wreck_key: String = str(def.get("wreck_model_key", ""))
	var wreck_mesh: String = "res://assets/models/ships/%s/model.glb" % wreck_key
	if ResourceLoader.exists(wreck_mesh):
		var wreck_unit: ShipUnit = ShipUnit.new()
		wreck.add_child(wreck_unit)
		wreck_unit.setup(TypedVariant.as_int(def.get("wreck_id", 0), 0), 1, ShipUnit.TEAM_PLAYER)
		if wreck_unit.has_method("clear_health_bar"):
			wreck_unit.clear_health_bar()
		call_deferred("_normalize_node_to_display", wreck, BOW_COLOR_WRECK)

	var kill_fx_inst_v: Variant = _KILL_FX_SCRIPT.new()
	var kill_fx: Node3D = Node3D.new()
	if kill_fx_inst_v is Node3D:
		kill_fx = kill_fx_inst_v
	kill_fx.name = "KillFx"
	kill_fx.position = Vector3(0, 1.2, 0)
	root.add_child(kill_fx)

	var miss: PackedStringArray = PackedStringArray()
	if not ResourceLoader.exists("res://assets/models/ships/%s/model.glb" % str(def.get("model_key", ""))):
		miss.append("hull")
	if wreck.get_child_count() == 0:
		miss.append("wreck_mesh")
	if not ResourceLoader.exists("res://assets/vfx/ship_death_echoes/tex/explosion_005.png"):
		miss.append("kill_fx_tex")

	return {
		"root": root,
		"intact": intact_holder,
		"wreck": wreck,
		"has_wreck": wreck.get_child_count() > 0,
		"unit": unit,
		"kill_fx": kill_fx,
		"miss": miss,
		"def": def,
	}


func _normalize_node_to_display(node: Node3D, bow_color: Color = Color.TRANSPARENT) -> void:
	if node == null or not is_instance_valid(node):
		return
	await get_tree().process_frame
	var longest: float = _approx_longest_world(node)
	if longest < 0.05:
		return
	var mul: float = DISPLAY_LONGEST / longest
	## Clamp so we never explode size if AABB was wrong.
	mul = clampf(mul, 0.05, 4.0)
	node.scale = node.scale * mul
	if SHOW_BOW_MARKERS and bow_color.a > 0.0:
		_add_bow_marker(node, bow_color)


func _add_bow_marker(node: Node3D, color: Color) -> void:
	## Floating arrow at the model's own +X end (the bow as the export pipeline
	## declared it), so hull vs wreck marks reveal which mesh is mirrored.
	var box: AABB = _local_mesh_aabb(node)
	if box.size.x < 0.001:
		return
	var length: float = box.size.x * 0.16
	var half_h: float = length * 0.55
	var verts: PackedVector3Array = PackedVector3Array([
		Vector3(length, 0.0, 0.0),
		Vector3(0.0, half_h, 0.0),
		Vector3(0.0, -half_h, 0.0),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.albedo_color = color
	mat.render_priority = 3

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "BowMarker"
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(
		box.position.x + box.size.x + length * 0.6,
		box.position.y + box.size.y * 0.5,
		box.position.z + box.size.z * 0.5
	)
	node.add_child(mi)


func _local_mesh_aabb(node: Node3D) -> AABB:
	var inv: Transform3D = node.global_transform.affine_inverse()
	var box: AABB = AABB()
	var seeded: bool = false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.mesh == null:
				continue
			var xf: Transform3D = inv * mi.global_transform
			var local: AABB = mi.mesh.get_aabb()
			for i: int in 8:
				var p: Vector3 = xf * local.get_endpoint(i)
				if not seeded:
					box = AABB(p, Vector3.ZERO)
					seeded = true
				else:
					box = box.expand(p)
	return box


func _approx_longest_world(node: Node3D) -> float:
	var best: float = 0.0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.mesh == null:
				continue
			var local: AABB = mi.mesh.get_aabb()
			var corners: Array[Vector3] = [
				local.position,
				local.position + Vector3(local.size.x, 0, 0),
				local.position + Vector3(0, local.size.y, 0),
				local.position + Vector3(0, 0, local.size.z),
				local.position + local.size,
			]
			var mn: Vector3 = Vector3(INF, INF, INF)
			var mx: Vector3 = Vector3(-INF, -INF, -INF)
			for p: Vector3 in corners:
				var w: Vector3 = mi.global_transform * p
				mn = mn.min(w)
				mx = mx.max(w)
			var size: Vector3 = mx - mn
			best = maxf(best, maxf(size.x, maxf(size.y, size.z)))
	return best


func _apply_state(e: Dictionary, active: bool, state: String, explode_amt: float) -> void:
	var root: Node3D = e["root"]
	root.visible = active
	var kill_fx_v: Variant = e.get("kill_fx", null)
	if kill_fx_v != null and kill_fx_v is Node:
		var kill_fx: Node = kill_fx_v
		if kill_fx.has_method("apply_phase"):
			kill_fx.call("apply_phase", state if active else "off", explode_amt, active)
	if not active:
		return
	var intact: Node3D = e["intact"]
	var wreck: Node3D = e["wreck"]
	var has_wreck: bool = TypedVariant.as_bool(e.get("has_wreck", false), false)
	match state:
		"intact":
			intact.visible = true
			wreck.visible = false
		"explode":
			intact.visible = explode_amt < 0.55
			wreck.visible = has_wreck and explode_amt >= 0.55
		"wreck":
			intact.visible = false
			wreck.visible = has_wreck


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(24, 18)
	_hud.add_theme_font_size_override("font_size", 17)
	_hud.modulate = Color(0.92, 0.88, 0.72)
	layer.add_child(_hud)
