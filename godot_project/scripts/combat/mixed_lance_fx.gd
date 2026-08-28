extends Node3D
## Runtime VFX for mixed lance — geometry matches damage cylinder (CAPITAL §4.1).
## Prep = TQ indicator cylinder + scan (preview `_make_prepare_fx`); Fire = crossed beams.

const BASE_SHADER: String = "res://shaders/lance_mixed_base.gdshader"
const LENS_SHADER: String = "res://shaders/lance_mixed_lens.gdshader"
const PREPARE_DIR: String = "res://assets/vfx/lance/prepare"
const SCAN_DIR: String = "res://assets/vfx/lance/prepare/scan"
const FX_DIRS: Array = [
	"res://assets/vfx/lance/damagebeam_a",
	"res://assets/vfx/lance/damagebeam_c",
	"res://assets/vfx/lance/damagebeam_g",
	"res://assets/vfx/lance/damagebeam_m",
]
const TINTS: Array = [
	Color(1.0, 0.82, 0.28, 1.0),
	Color(0.35, 0.72, 1.0, 1.0),
	Color(0.35, 1.0, 0.55, 1.0),
	Color(1.0, 0.42, 0.12, 1.0),
]
const PREPARE_SOFT: String = "res://assets/vfx/lance/prepare/superweaponcylinder/softwhite2_harsh.png"
## Preview-tuned defaults (2026-08-07): soft≡damage Ø, prep shell α=0 (scan only).
const PREPARE_ALPHA: float = 0.0
const FLOW_SPEED: float = 3.0

var _beam_h: float = 48.0
var _soft_d: float = 2.5
var _core_d: float = 1.2
var _prep_d: float = 3.6
var _prep_alpha: float = PREPARE_ALPHA
var _flow_speed: float = FLOW_SPEED
var _tip_frac: float = 0.877
var _pack: Node3D
var _prepare_root: Node3D
var _fire_root: Node3D
var _scan_rig: Node3D
var _haze: HeatHazeFx = null
var _haze_prepare: bool = true
var _haze_soft: float = -1.0
var _haze_h: float = -1.0
var _mats: Array = []
var _scroll_mats: Array = []
var _time_s: float = 0.0
var _built: bool = false


func configure(
	beam_h: float,
	soft_d: float,
	core_d: float,
	prep_d: float,
	tip_frac: float,
	prepare: bool,
	prep_alpha: float = PREPARE_ALPHA,
	flow_speed: float = FLOW_SPEED,
) -> void:
	_beam_h = maxf(1.0, beam_h)
	_soft_d = maxf(0.2, soft_d)
	_core_d = maxf(0.1, core_d)
	_prep_d = maxf(0.5, prep_d)
	_prep_alpha = clampf(prep_alpha, 0.0, 4.0)
	_flow_speed = maxf(0.0, flow_speed)
	_tip_frac = clampf(tip_frac, 0.05, 0.98)
	if not _built:
		_build()
		_built = true
	else:
		## Live retune: push flow into existing beam mats.
		for m_v: Variant in _mats:
			if not (m_v is ShaderMaterial):
				continue
			@warning_ignore("unsafe_cast")
			var sm: ShaderMaterial = m_v as ShaderMaterial
			sm.set_shader_parameter("travel_speed", _flow_speed)
	_sync_haze(prepare)
	_apply_phase(prepare)


func set_pose(origin: Vector3, dir: Vector3, scale_mul: float, prepare: bool) -> void:
	var up: Vector3 = dir.normalized()
	global_position = origin
	var right: Vector3 = up.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var fwd: Vector3 = right.cross(up).normalized()
	global_transform.basis = Basis(right, up, fwd)
	scale = Vector3(scale_mul, scale_mul, scale_mul)
	_sync_haze(prepare)
	_apply_phase(prepare)


func _apply_phase(prepare: bool) -> void:
	if _prepare_root != null:
		_prepare_root.visible = prepare
	if _fire_root != null:
		_fire_root.visible = not prepare


func _process(delta: float) -> void:
	_time_s += delta
	for m_v: Variant in _mats:
		if m_v is ShaderMaterial:
			var sm: ShaderMaterial = m_v
			sm.set_shader_parameter("time_s", _time_s)
			## Outward: scroll toward tip (CAPITAL §4.1).
			sm.set_shader_parameter("uv_scroll", _time_s * _flow_speed * 0.82)
	for entry_v: Variant in _scroll_mats:
		if entry_v is Dictionary:
			var entry: Dictionary = entry_v
			var mat_v: Variant = entry.get("mat", null)
			if mat_v is StandardMaterial3D:
				var mat: StandardMaterial3D = mat_v
				var rate: float = TypedVariant.as_float(entry.get("rate", 0.5), 0.5)
				mat.uv1_offset = Vector3(0.0, -_time_s * rate, 0.0)
	if _scan_rig != null and is_instance_valid(_scan_rig) and _prepare_root != null and _prepare_root.visible:
		_scan_rig.rotation_degrees = Vector3(0.0, _time_s * 55.0, 0.0)


func _build() -> void:
	_pack = Node3D.new()
	_pack.name = "LancePack"
	add_child(_pack)
	_prepare_root = _make_prepare_fx()
	_fire_root = Node3D.new()
	_fire_root.name = "Fire"
	_pack.add_child(_prepare_root)
	_pack.add_child(_fire_root)
	## Local: beam along +Y from 0 to beam_h (emit at 0).
	_add_crossed(_fire_root, _soft_d, _beam_h, _make_base_mat(0.55, 0.95, 1.8, true), _beam_h * 0.5)
	_add_crossed(_fire_root, _core_d, _beam_h, _make_base_mat(1.4, 1.0, 3.2, true), _beam_h * 0.5)
	_add_lenses(_fire_root)
	_ensure_haze()
	_sync_haze(true)
	_apply_phase(true)


func _ensure_haze() -> void:
	if _haze != null and is_instance_valid(_haze):
		return
	if not HeatHazeFx.fx_allowed():
		return
	_haze = HeatHazeFx.new()
	_haze.name = "LanceHeatHaze"
	_pack.add_child(_haze)


func _sync_haze(prepare: bool) -> void:
	_ensure_haze()
	if _haze == null or not is_instance_valid(_haze):
		return
	## Prep uses telegraph diameter; Fire/End use soft (damage) diameter.
	var soft_for_haze: float = _prep_d if prepare else _soft_d
	var need_mesh: bool = (
		absf(soft_for_haze - _haze_soft) > 0.001
		or absf(_beam_h - _haze_h) > 0.001
	)
	if need_mesh:
		_haze.configure_cone(_beam_h, soft_for_haze, 0.003, 0.85)
		_haze_soft = soft_for_haze
		_haze_h = _beam_h
	if prepare != _haze_prepare or need_mesh:
		## Prep → contract toward muzzle (dread); Fire → expand outward.
		_haze.set_lance_breath(prepare)
		_haze_prepare = prepare
	_haze.visible = true


func _make_prepare_fx() -> Node3D:
	## Match lance_fx_preview._make_prepare_fx (alphas × prepare_alpha; no depth vs hulls).
	var holder: Node3D = Node3D.new()
	holder.name = "Prepare"
	var prep_r: float = _prep_d * 0.5
	var a_mul: float = _prep_alpha
	var caustic: Texture2D = _load_tex("%s/modular_indicatorbeamactivation_st_t1a/caustic_14.png" % PREPARE_DIR)
	if caustic == null:
		caustic = _load_tex("%s/caustic_14.png" % SCAN_DIR)
	var soft_tex: Texture2D = _load_tex(PREPARE_SOFT)
	if soft_tex == null:
		soft_tex = _load_tex("%s/whitesharphifi.png" % SCAN_DIR)
	var cyl: MeshInstance3D = MeshInstance3D.new()
	var cyl_mesh: CylinderMesh = CylinderMesh.new()
	cyl_mesh.top_radius = prep_r
	cyl_mesh.bottom_radius = prep_r
	cyl_mesh.height = _beam_h
	cyl_mesh.radial_segments = 28
	cyl.mesh = cyl_mesh
	cyl.position = Vector3(0, _beam_h * 0.5, 0)
	var cyl_mat: StandardMaterial3D = StandardMaterial3D.new()
	cyl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cyl_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	cyl_mat.no_depth_test = true
	cyl_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.012 * a_mul)
	if soft_tex != null:
		cyl_mat.albedo_texture = soft_tex
	cyl_mat.emission_enabled = true
	cyl_mat.emission = Color(0.95, 0.95, 0.96)
	cyl_mat.emission_energy_multiplier = 0.04 * a_mul
	cyl.material_override = cyl_mat
	holder.add_child(cyl)
	if caustic != null:
		var caust_mi: MeshInstance3D = MeshInstance3D.new()
		var caust_mesh: CylinderMesh = CylinderMesh.new()
		caust_mesh.top_radius = prep_r * 0.98
		caust_mesh.bottom_radius = prep_r * 0.98
		caust_mesh.height = _beam_h
		caust_mesh.radial_segments = 32
		caust_mi.mesh = caust_mesh
		caust_mi.position = Vector3(0, _beam_h * 0.5, 0)
		var act: StandardMaterial3D = StandardMaterial3D.new()
		act.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		act.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		act.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		act.cull_mode = BaseMaterial3D.CULL_DISABLED
		act.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		act.no_depth_test = true
		act.albedo_texture = caustic
		act.albedo_color = Color(0.95, 0.95, 0.96, 0.045 * a_mul)
		act.emission_enabled = true
		act.emission = Color(0.92, 0.92, 0.94)
		act.emission_energy_multiplier = 0.18 * a_mul
		act.uv1_scale = Vector3(2.0, maxf(_beam_h / 5.0, 4.0), 1.0)
		caust_mi.material_override = act
		holder.add_child(caust_mi)
		_scroll_mats.append({"mat": act, "rate": 0.7})
	_scan_rig = Node3D.new()
	_scan_rig.name = "TwinScanRig"
	_scan_rig.position = Vector3(0, _beam_h * 0.5, 0)
	holder.add_child(_scan_rig)
	## Align preview: `lance_fx_preview.gd` → `band_w = _cell_wu * 0.2`
	var band_w: float = CombatFormulas.world_units_per_cell() * 0.2
	var band_tex: Texture2D = _load_tex("%s/sensor.png" % SCAN_DIR)
	var grad_tex: Texture2D = _load_tex("%s/gradient_06.png" % SCAN_DIR)
	if band_tex == null:
		band_tex = grad_tex
	for i: int in range(2):
		var band: MeshInstance3D = MeshInstance3D.new()
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(band_w, _beam_h)
		band.mesh = q
		var bmat: StandardMaterial3D = StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		bmat.no_depth_test = true
		bmat.albedo_color = Color(0.85, 0.95, 1.0, 0.95)
		bmat.emission_enabled = true
		bmat.emission = Color(0.7, 0.9, 1.0)
		bmat.emission_energy_multiplier = 3.0
		if band_tex != null:
			bmat.albedo_texture = band_tex
			bmat.uv1_scale = Vector3(1.0, maxf(_beam_h / 8.0, 3.0), 1.0)
		band.material_override = bmat
		var side: float = 1.0 if i == 0 else -1.0
		band.position = Vector3(side * prep_r * 0.96, 0, 0)
		band.rotation_degrees = Vector3(0, 90.0, 0)
		_scan_rig.add_child(band)
		_scroll_mats.append({"mat": bmat, "rate": 0.9})
		if grad_tex != null:
			var band2: MeshInstance3D = MeshInstance3D.new()
			var q2: QuadMesh = QuadMesh.new()
			q2.size = Vector2(band_w * 0.65, _beam_h)
			band2.mesh = q2
			var gmat: StandardMaterial3D = StandardMaterial3D.new()
			gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
			gmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			gmat.no_depth_test = true
			gmat.albedo_texture = grad_tex
			gmat.albedo_color = Color(0.95, 0.98, 1.0, 0.72)
			gmat.emission_enabled = true
			gmat.emission = Color(0.85, 0.95, 1.0)
			gmat.emission_energy_multiplier = 1.9
			gmat.uv1_scale = Vector3(1.0, maxf(_beam_h / 6.0, 2.5), 1.0)
			band2.material_override = gmat
			band2.position = Vector3(side * prep_r * 0.96, 0, 0.02)
			band2.rotation_degrees = Vector3(0, 90.0, 0)
			_scan_rig.add_child(band2)
			_scroll_mats.append({"mat": gmat, "rate": -0.55})
	return holder


func _load_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is Texture2D:
			return res
	## Fallback: raw image load (same path as lance_fx_preview).
	var abs_path: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	var img: Image = Image.new()
	if img.load(abs_path) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _make_base_mat(core_boost: float, alpha: float, emission: float, mask: bool) -> ShaderMaterial:
	var sh: Shader = load(BASE_SHADER) as Shader
	var sm: ShaderMaterial = ShaderMaterial.new()
	sm.shader = sh
	var tex: Texture2D = load("%s/lasergradient_01a.png" % str(FX_DIRS[0])) as Texture2D
	if tex != null:
		sm.set_shader_parameter("tex_beam", tex)
	sm.set_shader_parameter("tint_a", TINTS[0])
	sm.set_shader_parameter("tint_c", TINTS[1])
	sm.set_shader_parameter("tint_g", TINTS[2])
	sm.set_shader_parameter("tint_m", TINTS[3])
	sm.set_shader_parameter("travel_speed", _flow_speed)
	sm.set_shader_parameter("uv_tile_y", 2.4)
	sm.set_shader_parameter("uv_scroll", 0.0)
	sm.set_shader_parameter("alpha_mul", alpha)
	sm.set_shader_parameter("emission_mul", emission)
	sm.set_shader_parameter("core_boost", core_boost)
	sm.set_shader_parameter("mask_enable", 1.0 if mask else 0.0)
	sm.set_shader_parameter("mask_start", _tip_frac)
	## Symmetric muzzle cone length (emit end).
	sm.set_shader_parameter("muzzle_end", clampf(1.0 - _tip_frac, 0.02, 0.45))
	sm.set_shader_parameter("mask_arc", 1.35)
	sm.set_shader_parameter("mask_tip_frac", 0.03)
	sm.set_shader_parameter("mask_soft", 0.08)
	_mats.append(sm)
	return sm


func _add_crossed(parent: Node3D, width: float, height: float, mat: Material, y_center: float) -> void:
	for k: int in range(2):
		var mi: MeshInstance3D = MeshInstance3D.new()
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(width, height)
		mi.mesh = q
		mi.material_override = mat
		mi.position = Vector3(0, y_center, 0)
		mi.rotation_degrees = Vector3(0, float(k) * 90.0, 0)
		parent.add_child(mi)


func _add_lenses(parent: Node3D) -> void:
	var soft: Texture2D = load(PREPARE_SOFT) as Texture2D
	var lens_h: float = _beam_h * 0.16
	var lens_w: float = _soft_d * 0.85
	var radial: float = _soft_d * 0.28
	var y01s: Array[float] = [0.18, 0.42, 0.66, 0.88]
	var yaws: Array[float] = [20.0, 110.0, 200.0, 290.0]
	for i: int in range(4):
		var sh: Shader = load(LENS_SHADER) as Shader
		var sm: ShaderMaterial = ShaderMaterial.new()
		sm.shader = sh
		var tex: Texture2D = load("%s/beam4b.png" % str(FX_DIRS[i])) as Texture2D
		if tex != null:
			sm.set_shader_parameter("tex_beam", tex)
		if soft != null:
			sm.set_shader_parameter("tex_soft", soft)
		sm.set_shader_parameter("tint", TINTS[i])
		sm.set_shader_parameter("soft_power", 1.7)
		sm.set_shader_parameter("alpha_mul", 0.8)
		sm.set_shader_parameter("emission_mul", 2.6)
		_mats.append(sm)
		var rad: float = deg_to_rad(yaws[i])
		var mi: MeshInstance3D = MeshInstance3D.new()
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(lens_w, lens_h)
		mi.mesh = q
		mi.material_override = sm
		mi.position = Vector3(cos(rad) * radial, y01s[i] * _beam_h, sin(rad) * radial)
		mi.rotation_degrees = Vector3(0, yaws[i], 0)
		parent.add_child(mi)
