extends Node3D
## Dev preview: four racial titans fire doomsday at one asteroid in sequence (A→C→G→M).
## Hulls use in-game ShipUnit pipeline (visual.json scale/orient + §0 unity shader).

const PREVIEW_SHIPS: Array = [
	{
		"id": 901,
		"race_code": "A",
		"race": "amarr",
		"name": "圣像级",
		"name_en": "Avatar",
		"model_key": "tq_titan_a",
		"model_long_axis": 2200.0,
		"label": "圣像级 Avatar · 审判之日",
		"color": Color(1.0, 0.82, 0.28, 1.0),
		"style": "beam_lightning",
		"beam": "res://assets/vfx/doomsday/a/beam8.png",
		"detail": "res://assets/vfx/doomsday/a/fx_electro_03b.png",
		"flare": "res://assets/vfx/doomsday/a/whitesharp2_gradient.png",
	},
	{
		"id": 902,
		"race_code": "C",
		"race": "caldari",
		"name": "利维坦级",
		"name_en": "Leviathan",
		"model_key": "tq_titan_c",
		"model_long_axis": 2200.0,
		"label": "利维坦级 Leviathan · 湮没之圣光",
		"color": Color(0.35, 0.72, 1.0, 1.0),
		"style": "particle_smoke",
		"beam": "res://assets/vfx/doomsday/c/thick_streaks.png",
		"detail": "res://assets/vfx/doomsday/c/smoke_atlas_01.png",
		"flare": "res://assets/vfx/doomsday/c/outburst12.png",
	},
	{
		"id": 903,
		"race_code": "G",
		"race": "gallente",
		"name": "厄勒布洛斯级",
		"name_en": "Erebus",
		"model_key": "tq_titan_g",
		"model_long_axis": 2200.0,
		"label": "厄勒布洛斯级 Erebus · 极光之仪",
		"color": Color(0.35, 1.0, 0.55, 1.0),
		"style": "beam_aurora",
		"beam": "res://assets/vfx/doomsday/g/laser.png",
		"detail": "res://assets/vfx/doomsday/g/lightning5x_h_01.png",
		"flare": "res://assets/vfx/doomsday/g/sun2.png",
	},
	{
		"id": 904,
		"race_code": "M",
		"race": "minmatar",
		"name": "诸神黄昏级",
		"name_en": "Ragnarok",
		"model_key": "tq_titan_m",
		"model_long_axis": 2200.0,
		"label": "诸神黄昏级 Ragnarok · 赫姆达洱之咆哮",
		"color": Color(1.0, 0.42, 0.12, 1.0),
		"style": "explosion_smoke",
		"beam": "res://assets/vfx/doomsday/m/whitesharphifi.png",
		"detail": "res://assets/vfx/doomsday/m/smoke_atlas_02.png",
		"flare": "res://assets/vfx/doomsday/m/outburst12.png",
	},
]

const ASTEROID_PATH: String = "res://assets/models/env/asteroids/rock_02_l_v1.glb"
## Sequential fire: one race finishes, then the next (A→C→G→M).
const FIRE_S: float = 1.55
const GAP_S: float = 0.55
const SLOT_S: float = FIRE_S + GAP_S
const SHOT_PATH: String = "H:/game_dev/eveautochess-design/docs/_review/20260731_confirm/doomsday_preview/preview_fire.png"
const SHOT_PATH_B: String = "H:/game_dev/eveautochess-design/docs/_review/20260731_confirm/doomsday_preview/preview_hulls.png"
## Same free-fly keys as match_root: WASD move, QE up/down, RF pitch, TG yaw.
const _CAM_MOVE_SPEED: float = 22.0
const _CAM_PITCH_SPEED: float = 55.0
const _CAM_YAW_SPEED: float = 70.0

var _asteroid: Node3D
var _entries: Array = []
var _hud: Label
var _t: float = 0.0
var _shot_saved: bool = false
var _cam: Camera3D
var _cam_base_pos: Vector3 = Vector3.ZERO
var _cam_base_pitch_deg: float = -90.0
var _cam_base_yaw_deg: float = 0.0
var _cycle_s: float = SLOT_S * 4.0


func _ready() -> void:
	_inject_preview_ships()
	_build_env()
	_build_asteroid()
	for i: int in PREVIEW_SHIPS.size():
		var def_v: Variant = PREVIEW_SHIPS[i]
		if not (def_v is Dictionary):
			continue
		var def: Dictionary = def_v
		_entries.append(_spawn_titan(i, def))
	_cycle_s = SLOT_S * float(_entries.size())
	_build_hud()
	_t = 0.0


func _inject_preview_ships() -> void:
	## Runtime-only ship rows so ShipUnit uses visual.json + §0 bundles (not shop content).
	if DataStore == null:
		push_error("DoomsdayPreview: DataStore missing")
		return
	for def_v: Variant in PREVIEW_SHIPS:
		if not (def_v is Dictionary):
			continue
		var def: Dictionary = def_v
		var sid: int = TypedVariant.as_int(def.get("id", 0), 0)
		DataStore.ships[sid] = {
			"id": sid,
			"name": str(def.get("name", "")),
			"name_en": str(def.get("name_en", "")),
			"model_key": str(def.get("model_key", "")),
			"model_long_axis": TypedVariant.as_float(def.get("model_long_axis", 0.0), 0.0),
			"race": str(def.get("race", "")),
			"ship_group": "titan",
			"cost": 0,
			"fetter_ids": [],
			"tags": [str(def.get("race", "")), "titan"],
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


func _fire_envelope(local_t: float) -> float:
	## local_t in [0, FIRE_S): ramp → hold → fade. Else 0.
	if local_t < 0.0 or local_t >= FIRE_S:
		return 0.0
	var amt: float = 0.0
	if local_t < 0.35:
		amt = local_t / 0.35 * 0.35
	else:
		amt = 0.35 + 0.65 * clampf((local_t - 0.35) / 0.25, 0.0, 1.0)
		if local_t > FIRE_S - 0.4:
			amt *= clampf((FIRE_S - local_t) / 0.4, 0.0, 1.0)
	return amt


func _process(delta: float) -> void:
	_update_camera_free(delta)
	_t += delta
	var cycle_pos: float = fmod(_t, _cycle_s)
	var active_idx: int = int(cycle_pos / SLOT_S)
	active_idx = clampi(active_idx, 0, maxi(_entries.size() - 1, 0))
	var local_t: float = cycle_pos - float(active_idx) * SLOT_S
	var peak_amt: float = 0.0
	var active_label: String = ""
	for i: int in _entries.size():
		var amt: float = _fire_envelope(local_t) if i == active_idx else 0.0
		if amt > peak_amt:
			peak_amt = amt
		if i == active_idx and i < PREVIEW_SHIPS.size():
			var ship_v: Variant = PREVIEW_SHIPS[i]
			if ship_v is Dictionary:
				var ship_def: Dictionary = ship_v
				active_label = str(ship_def.get("label", ""))
		var entry_v: Variant = _entries[i]
		if entry_v is Dictionary:
			var entry: Dictionary = entry_v
			_tick_fx(entry, amt, delta)
	if _hud:
		_hud.text = (
			"依次末日  [%d/%d] %s  fire=%.0f%%  | WASD移动 QE升降 RF俯仰 TG偏航 Shift加速"
			% [active_idx + 1, _entries.size(), active_label, peak_amt * 100.0]
		)
	if not _shot_saved and peak_amt > 0.85:
		_shot_saved = true
		call_deferred("_save_preview_shot")


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


func _save_preview_shot() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img:
		img.save_png(SHOT_PATH)
		img.save_png(SHOT_PATH_B)
		print("[DoomsdayPreview] saved ", SHOT_PATH)


func _build_env() -> void:
	## Match ShipLook key light defaults when present.
	var look: Dictionary = {}
	if DataStore and DataStore.visual is Dictionary:
		var sl_v: Variant = DataStore.visual.get("ship_look", {})
		if sl_v is Dictionary:
			look = sl_v
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.light_energy = TypedVariant.as_float(look.get("key_energy", 1.0), 1.0)
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(
		TypedVariant.as_float(look.get("key_pitch_deg", -57.3), -57.3),
		TypedVariant.as_float(look.get("key_yaw_deg", 107.7), 107.7),
		TypedVariant.as_float(look.get("key_roll_deg", 0.0), 0.0)
	)
	if look.has("key_color_r"):
		light.light_color = Color(
			TypedVariant.as_float(look.get("key_color_r", 1.0), 1.0),
			TypedVariant.as_float(look.get("key_color_g", 1.0), 1.0),
			TypedVariant.as_float(look.get("key_color_b", 1.0), 1.0)
		)
	add_child(light)
	var top: DirectionalLight3D = DirectionalLight3D.new()
	top.light_energy = 1.55
	top.shadow_enabled = false
	top.rotation_degrees = Vector3(-90, 0, 0)
	add_child(top)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.light_energy = 4.5
	fill.omni_range = 120.0
	fill.position = Vector3(0, 50, 0)
	add_child(fill)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 38.0
	# Start top-down; free-fly (qawsedrftg) takes over from _process.
	_cam_base_pos = Vector3(0, 42, 0)
	_cam_base_pitch_deg = -88.0
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
	env.ambient_light_energy = maxf(TypedVariant.as_float(look.get("ambient_energy", 1.15), 1.15), 1.8)
	env.glow_enabled = TypedVariant.as_bool(look.get("glow_enabled", true), true)
	env.glow_intensity = TypedVariant.as_float(look.get("glow_intensity", 0.55), 0.55)
	env.glow_bloom = TypedVariant.as_float(look.get("glow_bloom", 0.35), 0.35)
	bg.environment = env
	add_child(bg)


func _build_asteroid() -> void:
	_asteroid = Node3D.new()
	_asteroid.name = "AsteroidTarget"
	_asteroid.position = Vector3(0, 0, -14)
	add_child(_asteroid)
	var packed: Variant = load(ASTEROID_PATH)
	if packed is PackedScene:
		var scene: PackedScene = packed
		var inst: Node3D = scene.instantiate()
		inst.scale = Vector3.ONE * 2.6
		_asteroid.add_child(inst)
	else:
		var mi: MeshInstance3D = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 2.0
		mi.mesh = sphere
		_asteroid.add_child(mi)


func _spawn_titan(idx: int, def: Dictionary) -> Dictionary:
	var unit: ShipUnit = ShipUnit.new()
	unit.name = "Titan_%s" % str(def.get("race_code", ""))
	var x: float = (float(idx) - 1.5) * 10.0
	unit.position = Vector3(x, 0, 8)
	add_child(unit)
	unit.setup(TypedVariant.as_int(def.get("id", 0), 0), 1, ShipUnit.TEAM_PLAYER)
	unit.clear_health_bar()
	# Aim local -Z at asteroid (same as combat face).
	var aim: Vector3 = _asteroid.global_position - unit.global_position
	unit.face_dir_xz(aim)
	# Temporarily allow face even if immobile flags appear.
	unit.immobile_in_combat = false

	var color_v: Variant = def.get("color", null)
	var race_color: Color = color_v if color_v is Color else Color.WHITE
	var label: Label3D = Label3D.new()
	label.text = str(def.get("label", ""))
	label.font_size = 64
	label.modulate = race_color
	label.position = Vector3(0, 0.15, 4.2)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.012
	unit.add_child(label)

	var muzzle: Marker3D = Marker3D.new()
	muzzle.name = "PreviewMuzzle"
	# Prefer ShipUnit turret muzzle if available.
	var tip: Vector3 = Vector3(0, 0.4, -2.8)
	if unit.has_method("get_muzzle_global"):
		# Approximate local from current muzzle once.
		var g: Vector3 = unit.get_muzzle_global()
		tip = unit.to_local(g)
	muzzle.position = tip
	unit.add_child(muzzle)

	var fx: Dictionary = _make_fx(def, muzzle)
	var fx_node_v: Variant = fx.get("node", null)
	if fx_node_v is Node:
		var fx_node: Node = fx_node_v
		unit.add_child(fx_node)
	return {
		"unit": unit,
		"muzzle": muzzle,
		"color": race_color,
		"style": str(def.get("style", "")),
		"hit_flare_enabled": str(def.get("race_code", "")) != "A",
		"mats": fx.get("mats", []),
		"flare": fx.get("flare", null),
		"particles": fx.get("particles", null),
		"beams": fx.get("beams", []),
	}


func _make_fx(def: Dictionary, muzzle: Marker3D) -> Dictionary:
	var holder: Node3D = Node3D.new()
	holder.name = "DoomsdayFx"
	var mats: Array = []
	var beams: Array = []
	var color_v: Variant = def.get("color", null)
	var color: Color = color_v if color_v is Color else Color.WHITE

	var outer: Dictionary = _make_beam_mesh(str(def.get("beam", "")), color, 1.15, 0.55)
	var outer_mi_v: Variant = outer.get("mi", null)
	if outer_mi_v is MeshInstance3D:
		var outer_mi: MeshInstance3D = outer_mi_v
		holder.add_child(outer_mi)
	var outer_mat_v: Variant = outer.get("mat", null)
	if outer_mat_v is StandardMaterial3D:
		mats.append(outer_mat_v)
	if outer_mi_v is MeshInstance3D:
		beams.append(outer_mi_v)
	var inner: Dictionary = _make_beam_mesh(str(def.get("detail", "")), Color.WHITE.lerp(color, 0.35), 0.4, 0.85)
	var inner_mi_v: Variant = inner.get("mi", null)
	if inner_mi_v is MeshInstance3D:
		var inner_mi: MeshInstance3D = inner_mi_v
		holder.add_child(inner_mi)
	var inner_mat_v: Variant = inner.get("mat", null)
	if inner_mat_v is StandardMaterial3D:
		mats.append(inner_mat_v)
	if inner_mi_v is MeshInstance3D:
		beams.append(inner_mi_v)

	var flare: MeshInstance3D = MeshInstance3D.new()
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(2.8, 2.8)
	flare.mesh = q
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var flare_path: String = str(def.get("flare", ""))
	if ResourceLoader.exists(flare_path):
		fmat.albedo_texture = load(flare_path)
	fmat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	fmat.emission_enabled = true
	fmat.emission = color
	fmat.emission_energy_multiplier = 2.2
	flare.material_override = fmat
	holder.add_child(flare)
	mats.append(fmat)

	var particles: GPUParticles3D = null
	var style: String = str(def.get("style", ""))
	if style == "particle_smoke" or style == "explosion_smoke":
		## C/M：只收发散角；保留原始寿命、速度与粒子尺寸，不缩短射流。
		var is_caldari: bool = style == "particle_smoke"
		particles = GPUParticles3D.new()
		particles.amount = 48 if is_caldari else 64
		particles.lifetime = 0.9
		particles.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
		particles.local_coords = true
		var pmat: ParticleProcessMaterial = ParticleProcessMaterial.new()
		pmat.direction = Vector3(0, 0, -1)
		pmat.spread = 2.5 if is_caldari else 4.0
		pmat.initial_velocity_min = 8.0
		pmat.initial_velocity_max = 22.0
		pmat.gravity = Vector3.ZERO
		pmat.damping_min = 0.0
		pmat.damping_max = 0.0
		pmat.scale_min = 0.35
		pmat.scale_max = 1.2
		pmat.color = Color(color.r, color.g, color.b, 0.85)
		particles.process_material = pmat
		var draw: QuadMesh = QuadMesh.new()
		draw.size = Vector2(0.65, 0.65)
		var dmat: StandardMaterial3D = StandardMaterial3D.new()
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		var detail_path: String = str(def.get("detail", ""))
		if ResourceLoader.exists(detail_path):
			dmat.albedo_texture = load(detail_path)
		dmat.albedo_color = Color(color.r, color.g, color.b, 0.7)
		draw.material = dmat
		particles.draw_pass_1 = draw
		particles.emitting = false
		particles.position = muzzle.position
		holder.add_child(particles)

	return {"node": holder, "mats": mats, "flare": flare, "particles": particles, "beams": beams}


func _make_beam_mesh(tex_path: String, color: Color, width: float, alpha: float) -> Dictionary:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE
	mi.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.8
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		mat.uv1_scale = Vector3(1, 4, 1)
	mi.material_override = mat
	mi.set_meta("beam_width", width)
	mi.set_meta("beam_alpha", alpha)
	mi.visible = false
	return {"mi": mi, "mat": mat}


func _tick_fx(e: Dictionary, fire_amt: float, delta: float) -> void:
	var muzzle_v: Variant = e.get("muzzle", null)
	if not (muzzle_v is Marker3D):
		return
	var muzzle: Marker3D = muzzle_v
	var unit_v: Variant = e.get("unit", null)
	if not (unit_v is ShipUnit):
		return
	var unit: ShipUnit = unit_v
	var target: Vector3 = _asteroid.global_position + Vector3(0, 0.6, 0)
	var from: Vector3 = muzzle.global_position
	if unit.has_method("get_muzzle_global"):
		from = unit.get_muzzle_global()
		muzzle.global_position = from
	var mid: Vector3 = (from + target) * 0.5
	var length: float = from.distance_to(target)
	var dir: Vector3 = (target - from).normalized()

	var beams: Array = TypedVariant.as_array(e.get("beams", null))
	for mi_v: Variant in beams:
		if not (mi_v is MeshInstance3D):
			continue
		var mesh_i: MeshInstance3D = mi_v
		var w: float = TypedVariant.as_float(mesh_i.get_meta("beam_width", 0.6), 0.6)
		var a: float = TypedVariant.as_float(mesh_i.get_meta("beam_alpha", 0.7), 0.7)
		mesh_i.visible = fire_amt > 0.02
		if not mesh_i.visible:
			continue
		var right: Vector3 = dir.cross(Vector3.UP)
		if right.length_squared() < 1e-6:
			right = dir.cross(Vector3.RIGHT)
		right = right.normalized()
		var fwd: Vector3 = right.cross(dir).normalized()
		var beam_basis: Basis = Basis(right, dir, fwd)
		mesh_i.global_transform = Transform3D(beam_basis, mid)
		mesh_i.scale = Vector3(w * (0.55 + fire_amt), length, w * (0.55 + fire_amt))
		var mat: StandardMaterial3D = mesh_i.material_override
		var col: Color = mat.albedo_color
		col.a = a * fire_amt
		mat.albedo_color = col
		mat.emission_energy_multiplier = 1.2 + fire_amt * 2.4
		mat.uv1_offset.y = fmod(mat.uv1_offset.y - delta * (1.8 + fire_amt * 2.5), 1.0)

	var flare_v: Variant = e.get("flare", null)
	if not (flare_v is MeshInstance3D):
		return
	var flare: MeshInstance3D = flare_v
	## Amarr whitesharp2_gradient renders as a broken gold square: discard it.
	## C/G/M retain their race hit flare.
	var flare_enabled: bool = TypedVariant.as_bool(e.get("hit_flare_enabled", true), true)
	flare.visible = flare_enabled and fire_amt > 0.02
	flare.global_position = target
	var fmat: StandardMaterial3D = flare.material_override
	var fc: Color = fmat.albedo_color
	fc.a = fire_amt * fire_amt * 0.95 if flare_enabled else 0.0
	fmat.albedo_color = fc
	flare.scale = Vector3.ONE * (1.2 + fire_amt * 3.2)

	var parts_v: Variant = e.get("particles", null)
	if parts_v is GPUParticles3D:
		var parts: GPUParticles3D = parts_v
		parts.emitting = fire_amt > 0.4
		# Emit along beam axis (local -Z = dir) so spread stays in-channel.
		var p_basis: Basis = Basis.looking_at(dir, Vector3.UP)
		parts.global_transform = Transform3D(p_basis, from.lerp(target, 0.12))


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(24, 18)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.modulate = Color(0.85, 0.9, 1.0)
	layer.add_child(_hud)
