extends Node3D
## Dev preview: single「混合长枪」— original crossed-quad fire + prepare scan materials.
## Doc: CAPITAL_AND_CYNO §4.1

const _CAM_MOVE_SPEED: float = 28.0
const _CAM_PITCH_SPEED: float = 55.0
const _CAM_YAW_SPEED: float = 70.0
const _LOOK_SENS: float = 0.22
const _WHEEL_STEP: float = 3.2
const _SPIN_RATE: float = 0.28
const _TIP_CELLS: float = 2.0
## Prepare telegraph default = tactical Ø3 cells.
const _OUTER_DIAM_CELLS: float = 3.0
## Tunable defaults (original TQ stack).
const _DEF_SOFT_D: float = 2.5
const _DEF_CORE_D: float = 1.2
const _DEF_FLOW: float = 3.0
const _DEF_PREP_A: float = 0.0
const _DEF_PREP_D: float = 3.6
const TUNE_COUNT: int = 6
const PREPARE_DIR: String = "res://assets/vfx/lance/prepare"
const PHASE_PREPARE_S: float = 2.8
const PHASE_FIRE_S: float = 3.2
const PHASE_PREPARE: int = 0
const PHASE_FIRE: int = 1

const ICON_A: String = "res://assets/vfx/lance/icon_amarr.png"
const ICON_C: String = "res://assets/vfx/lance/icon_caldari.png"
const ICON_G: String = "res://assets/vfx/lance/icon_gallente.png"
const ICON_M: String = "res://assets/vfx/lance/icon_minmatar.png"
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

const ICON_SHADER: String = "res://shaders/lance_mixed_icon.gdshader"
const BASE_SHADER: String = "res://shaders/lance_mixed_base.gdshader"
const LENS_SHADER: String = "res://shaders/lance_mixed_lens.gdshader"
const SCAN_DIR: String = "res://assets/vfx/lance/prepare/scan"

var _cam: Camera3D
var _hud: Label
var _cam_base_pos: Vector3 = Vector3(0, 18, 42)
var _cam_base_pitch_deg: float = -22.0
var _cam_base_yaw_deg: float = 0.0
var _spin: float = 0.0
var _time_s: float = 0.0
var _scroll_mats: Array = []
var _beam_shaders: Array = []
var _lens_shaders: Array = []
var _icon_mat: ShaderMaterial
var _icon_mesh: MeshInstance3D
var _prepare_root: Node3D
var _fire_root: Node3D
var _scan_rig: Node3D
var _look_dragging: bool = false
var _beam_h: float = 48.0
var _board_diag: float = 48.0
var _board_span_x: float = 36.0
var _board_span_z: float = 33.0
var _cell_wu: float = 3.0
var _outer_d: float = 9.0
var _tip_h: float = 6.0
var _phase: int = PHASE_PREPARE
var _phase_t: float = 0.0
var _phase_paused: bool = false
var _tex_a: Texture2D
var _tex_c: Texture2D
var _tex_g: Texture2D
var _tex_m: Texture2D
var _tex_soft: Texture2D
var _tex_sensor: Texture2D
var _tex_grad: Texture2D
var _tex_base_beam: Texture2D
var _lance_pack: Node3D
## Tunables: 凝实直径 / 淡色直径 / 流动 / 准备直径 / V弧遮罩起始距发出点 / 准备透明度
var _core_d: float = _DEF_CORE_D
var _soft_d: float = _DEF_SOFT_D
var _flow_speed: float = _DEF_FLOW
var _prepare_d: float = 9.0
var _tip_from_muzzle: float = 42.0
var _prepare_alpha: float = _DEF_PREP_A
var _tune_i: int = 0
var _tune_hold_t: float = 0.0
var _tune_names: Array[String] = [
	"凝实光柱直径",
	"淡色光柱直径",
	"流动速度",
	"准备特效直径",
	"V遮罩起始距发出点",
	"准备透明度",
]


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_resolve_board_metrics()
	_load_racial_beam_tex()
	_prepare_d = _OUTER_DIAM_CELLS * _cell_wu
	_tip_from_muzzle = maxf(_beam_h - _tip_h, _beam_h * 0.72)
	_apply_game_tune_sync()
	print(
		"[LanceFxPreview] 混合长枪 diag=%.2f soft=%.2f core=%.2f prepØ=%.2f prepα=%.2f tip=%.2f · AD换项 WS调值"
		% [_beam_h, _soft_d, _core_d, _prepare_d, _prepare_alpha, _tip_from_muzzle]
	)
	_build_env()
	_build_board_reference()
	_build_mixed_lance()
	_build_hud()
	_apply_phase_visibility()


## Pull live combat defaults (data/dev/lance_fx_tune.json ← MixedLance content).
func _apply_game_tune_sync() -> void:
	const TUNE_PATH: String = "res://data/dev/lance_fx_tune.json"
	if not FileAccess.file_exists(TUNE_PATH):
		## Fallback: same numbers as MixedLance / function_modules.mixed_lance.
		_soft_d = _DEF_SOFT_D
		_core_d = _DEF_CORE_D
		_flow_speed = _DEF_FLOW
		_prepare_d = 9.0
		_prepare_alpha = _DEF_PREP_A
		_tip_from_muzzle = (42.84 / 48.84) * _beam_h
		return
	var f: FileAccess = FileAccess.open(TUNE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	_core_d = TypedVariant.as_float(d.get("core_d", _core_d), _core_d)
	_soft_d = TypedVariant.as_float(d.get("soft_d", _soft_d), _soft_d)
	_flow_speed = TypedVariant.as_float(d.get("flow_speed", _flow_speed), _flow_speed)
	_prepare_d = TypedVariant.as_float(d.get("prepare_d", _prepare_d), _prepare_d)
	_prepare_alpha = TypedVariant.as_float(d.get("prepare_alpha", _prepare_alpha), _prepare_alpha)
	var tip_frac: float = TypedVariant.as_float(d.get("tip_frac", 42.84 / 48.84), 42.84 / 48.84)
	_tip_from_muzzle = tip_frac * _beam_h
	print("[LanceFxPreview] synced from game tune: %s" % TUNE_PATH)


func _resolve_board_metrics() -> void:
	_cell_wu = CombatFormulas.world_units_per_cell()
	_outer_d = _OUTER_DIAM_CELLS * _cell_wu
	_tip_h = _TIP_CELLS * _cell_wu
	var bb: Vector4 = BoardController.combat_play_bounds_xz(0.0)
	_board_span_x = bb.y - bb.x
	_board_span_z = bb.w - bb.z
	_board_diag = sqrt(_board_span_x * _board_span_x + _board_span_z * _board_span_z)
	_beam_h = _board_diag
	_cam_base_pos = Vector3(0.0, _beam_h * 0.38, _beam_h * 0.95)


func _load_racial_beam_tex() -> void:
	_tex_a = _load_tex_mid_tile("%s/beam4b.png" % str(FX_DIRS[0]))
	_tex_c = _load_tex_mid_tile("%s/beam4b.png" % str(FX_DIRS[1]))
	_tex_g = _load_tex_mid_tile("%s/beam4b.png" % str(FX_DIRS[2]))
	_tex_m = _load_tex_mid_tile("%s/beam4b.png" % str(FX_DIRS[3]))
	_tex_base_beam = _load_tex_mid_tile("%s/lasergradient_01a.png" % str(FX_DIRS[0]))
	if _tex_base_beam == null:
		_tex_base_beam = _tex_a
	_tex_soft = _load_tex("%s/softwhite2_harsh.png" % str(PREPARE_DIR + "/superweaponcylinder"))
	if _tex_soft == null:
		_tex_soft = _load_tex("%s/whitesharphifi.png" % SCAN_DIR)
	_tex_sensor = _load_tex("%s/sensor.png" % SCAN_DIR)
	_tex_grad = _load_tex("%s/gradient_06.png" % SCAN_DIR)
	if _tex_grad == null:
		_tex_grad = _load_tex("%s/gradient_02.png" % SCAN_DIR)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ek: InputEventKey = event
		if ek.pressed and not ek.echo:
			if ek.keycode == KEY_SPACE:
				_phase_paused = not _phase_paused
				get_viewport().set_input_as_handled()
				_refresh_hud()
				return
			if ek.keycode == KEY_1:
				_phase = PHASE_PREPARE
				_phase_t = 0.0
				_apply_phase_visibility()
				get_viewport().set_input_as_handled()
				_refresh_hud()
				return
			if ek.keycode == KEY_2:
				_phase = PHASE_FIRE
				_phase_t = 0.0
				_apply_phase_visibility()
				get_viewport().set_input_as_handled()
				_refresh_hud()
				return
			if ek.keycode == KEY_A:
				_tune_i = (_tune_i - 1 + TUNE_COUNT) % TUNE_COUNT
				get_viewport().set_input_as_handled()
				_refresh_hud()
				return
			if ek.keycode == KEY_D:
				_tune_i = (_tune_i + 1) % TUNE_COUNT
				get_viewport().set_input_as_handled()
				_refresh_hud()
				return
			if ek.keycode == KEY_W or ek.keycode == KEY_S:
				## Continuous nudge handled in _process hold.
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_look_dragging = mb.pressed
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var cam_basis: Basis = Basis.from_euler(
				Vector3(deg_to_rad(_cam_base_pitch_deg), deg_to_rad(_cam_base_yaw_deg), 0.0)
			)
			var forward: Vector3 = -cam_basis.z
			var dolly: float = -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_cam_base_pos += forward * (_WHEEL_STEP * dolly)
			_apply_cam()
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventMouseMotion and _look_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_cam_base_yaw_deg -= mm.relative.x * _LOOK_SENS
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg - mm.relative.y * _LOOK_SENS, -89.0, 89.0)
		_apply_cam()
		get_viewport().set_input_as_handled()


func _build_env() -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 35, 0)
	light.light_energy = 1.35
	add_child(light)
	var amb: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.2, 0.24)
	env.ambient_light_energy = 0.45
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.28
	amb.environment = env
	add_child(amb)
	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)
	_apply_cam()


func _build_board_reference() -> void:
	var half_x: float = _board_span_x * 0.5
	var half_z: float = _board_span_z * 0.5
	var pad: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(_board_span_x, 0.06, _board_span_z)
	pad.mesh = box
	var pm: StandardMaterial3D = StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(0.1, 0.12, 0.16, 0.85)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pad.material_override = pm
	pad.position = Vector3(0, -0.03, 0)
	add_child(pad)
	var diag: MeshInstance3D = MeshInstance3D.new()
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(0.22, _board_diag)
	diag.mesh = q
	var dm: StandardMaterial3D = StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(0.95, 0.85, 0.35, 0.9)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	diag.material_override = dm
	diag.position = Vector3(0, 0.04, 0)
	diag.rotation_degrees = Vector3(-90.0, rad_to_deg(atan2(_board_span_x, _board_span_z)), 0.0)
	add_child(diag)
	var corners: Array = [
		Vector3(-half_x, 0.05, -half_z),
		Vector3(half_x, 0.05, -half_z),
		Vector3(half_x, 0.05, half_z),
		Vector3(-half_x, 0.05, half_z),
	]
	for i: int in range(4):
		var a_v: Variant = corners[i]
		var b_v: Variant = corners[(i + 1) % 4]
		if a_v is Vector3 and b_v is Vector3:
			var a: Vector3 = a_v
			var b: Vector3 = b_v
			_add_edge_line(a, b, Color(0.45, 0.55, 0.7, 0.85))
	var note: Label3D = Label3D.new()
	note.text = "混合长枪 · 对角线全长=%.1f wu · 原版交叉柱画法" % _board_diag
	note.font_size = 36
	note.outline_size = 8
	note.position = Vector3(0, 0.25, half_z + 2.8)
	note.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(note)


func _add_edge_line(a: Vector3, b: Vector3, color: Color) -> void:
	var mid: Vector3 = (a + b) * 0.5
	var diff: Vector3 = b - a
	var len_xz: float = Vector2(diff.x, diff.z).length()
	var mi: MeshInstance3D = MeshInstance3D.new()
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(0.08, maxf(len_xz, 0.01))
	mi.mesh = q
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.position = mid
	mi.rotation_degrees = Vector3(-90.0, rad_to_deg(atan2(diff.x, diff.z)), 0.0)
	add_child(mi)


func _build_mixed_lance() -> void:
	var root: Node3D = Node3D.new()
	root.name = "MixedLance"
	add_child(root)
	_attach_mixed_icon(root)
	_lance_pack = Node3D.new()
	_lance_pack.name = "LancePack"
	_lance_pack.position = Vector3(0, _beam_h * 0.5, 0)
	root.add_child(_lance_pack)
	_rebuild_phase_fx()
	var label: Label3D = Label3D.new()
	label.text = "混合长枪\nAD换项 · WS调值\nL=%.1f · 1/2阶段" % _beam_h
	label.font_size = 32
	label.outline_size = 8
	label.position = Vector3(0, _beam_h + 1.6, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)


func _tune_value() -> float:
	match _tune_i:
		0:
			return _core_d
		1:
			return _soft_d
		2:
			return _flow_speed
		3:
			return _prepare_d
		4:
			return _tip_from_muzzle
		_:
			return _prepare_alpha


func _tune_step() -> float:
	match _tune_i:
		0, 1:
			return 0.05
		2:
			return 0.05
		3:
			return 0.15
		4:
			return 0.5
		_:
			return 0.05


func _nudge_tune(dir: float) -> void:
	var step: float = _tune_step() * dir
	match _tune_i:
		0:
			_core_d = clampf(_core_d + step, 0.15, 10.0)
			_rebuild_phase_fx()
		1:
			_soft_d = clampf(_soft_d + step, 0.3, 14.0)
			_rebuild_phase_fx()
		2:
			_flow_speed = clampf(_flow_speed + step, 0.05, 4.0)
			_apply_flow_live()
		3:
			_prepare_d = clampf(_prepare_d + step, 0.8, 24.0)
			_rebuild_phase_fx()
		4:
			_tip_from_muzzle = clampf(_tip_from_muzzle + step, _tip_h * 0.5, _beam_h)
			_rebuild_phase_fx()
		_:
			_prepare_alpha = clampf(_prepare_alpha + step, 0.0, 4.0)
			_rebuild_phase_fx()
	_refresh_hud()


func _apply_flow_live() -> void:
	for sm_v: Variant in _beam_shaders:
		if sm_v is ShaderMaterial:
			var sm: ShaderMaterial = sm_v
			sm.set_shader_parameter("travel_speed", _flow_speed)


func _rebuild_phase_fx() -> void:
	if _lance_pack == null:
		return
	_scroll_mats.clear()
	_beam_shaders.clear()
	_lens_shaders.clear()
	_scan_rig = null
	if _prepare_root != null and is_instance_valid(_prepare_root):
		_lance_pack.remove_child(_prepare_root)
		_prepare_root.free()
	if _fire_root != null and is_instance_valid(_fire_root):
		_lance_pack.remove_child(_fire_root)
		_fire_root.free()
	_prepare_root = _make_prepare_fx()
	_fire_root = _make_fire_fx()
	_lance_pack.add_child(_prepare_root)
	_lance_pack.add_child(_fire_root)
	_apply_phase_visibility()


func _attach_mixed_icon(parent: Node3D) -> void:
	var ia: Texture2D = _load_tex(ICON_A)
	var ic: Texture2D = _load_tex(ICON_C)
	var ig: Texture2D = _load_tex(ICON_G)
	var im: Texture2D = _load_tex(ICON_M)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "MixedIcon"
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(4.2, 4.2)
	mi.mesh = q
	mi.position = Vector3(0, _beam_h + 4.6, 0)
	var sh: Shader = load(ICON_SHADER) as Shader
	_icon_mat = ShaderMaterial.new()
	_icon_mat.shader = sh
	if ia != null:
		_icon_mat.set_shader_parameter("icon_a", ia)
	if ic != null:
		_icon_mat.set_shader_parameter("icon_c", ic)
	if ig != null:
		_icon_mat.set_shader_parameter("icon_g", ig)
	if im != null:
		_icon_mat.set_shader_parameter("icon_m", im)
	_icon_mat.set_shader_parameter("sweep_rad", 0.0)
	mi.material_override = _icon_mat
	parent.add_child(mi)
	_icon_mesh = mi


func _make_base_mat(core_boost: float, alpha: float, emission: float, uv_tile: float, mask_soft: float) -> ShaderMaterial:
	var sh: Shader = load(BASE_SHADER) as Shader
	var sm: ShaderMaterial = ShaderMaterial.new()
	sm.shader = sh
	if _tex_base_beam != null:
		sm.set_shader_parameter("tex_beam", _tex_base_beam)
	var ta_v: Variant = TINTS[0]
	var tc_v: Variant = TINTS[1]
	var tg_v: Variant = TINTS[2]
	var tm_v: Variant = TINTS[3]
	if ta_v is Color:
		sm.set_shader_parameter("tint_a", ta_v)
	if tc_v is Color:
		sm.set_shader_parameter("tint_c", tc_v)
	if tg_v is Color:
		sm.set_shader_parameter("tint_g", tg_v)
	if tm_v is Color:
		sm.set_shader_parameter("tint_m", tm_v)
	sm.set_shader_parameter("time_s", 0.0)
	sm.set_shader_parameter("travel_speed", _flow_speed)
	sm.set_shader_parameter("uv_tile_y", uv_tile)
	sm.set_shader_parameter("uv_scroll", 0.0)
	sm.set_shader_parameter("alpha_mul", alpha)
	sm.set_shader_parameter("emission_mul", emission)
	sm.set_shader_parameter("core_boost", core_boost)
	## V-arc clips both ends; join opens to full layer UV.
	var mask_start: float = clampf(_tip_from_muzzle / maxf(_beam_h, 0.001), 0.05, 0.98)
	sm.set_shader_parameter("mask_enable", 1.0)
	sm.set_shader_parameter("mask_start", mask_start)
	sm.set_shader_parameter("muzzle_end", clampf(1.0 - mask_start, 0.02, 0.45))
	sm.set_shader_parameter("mask_arc", 1.35)
	sm.set_shader_parameter("mask_tip_frac", 0.03)
	sm.set_shader_parameter("mask_soft", mask_soft)
	_beam_shaders.append(sm)
	return sm


func _make_lens_mat(tint: Color, tex: Texture2D) -> ShaderMaterial:
	var sh: Shader = load(LENS_SHADER) as Shader
	var sm: ShaderMaterial = ShaderMaterial.new()
	sm.shader = sh
	if tex != null:
		sm.set_shader_parameter("tex_beam", tex)
	if _tex_soft != null:
		sm.set_shader_parameter("tex_soft", _tex_soft)
	sm.set_shader_parameter("tint", tint)
	sm.set_shader_parameter("time_s", 0.0)
	sm.set_shader_parameter("uv_scroll", 0.0)
	sm.set_shader_parameter("soft_power", 1.7)
	sm.set_shader_parameter("alpha_mul", 0.8)
	sm.set_shader_parameter("emission_mul", 2.6)
	_lens_shaders.append(sm)
	return sm


func _add_crossed_quads(parent: Node3D, width: float, height: float, mat: Material, y_center: float) -> void:
	for k: int in range(2):
		var mi: MeshInstance3D = MeshInstance3D.new()
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(width, height)
		mi.mesh = q
		mi.material_override = mat
		mi.position = Vector3(0, y_center, 0)
		mi.rotation_degrees = Vector3(0, float(k) * 90.0, 0)
		parent.add_child(mi)


func _add_witch_lenses(parent: Node3D, shaft_h: float, shaft_y: float) -> void:
	var lens_h: float = shaft_h * 0.16
	var lens_w: float = _soft_d * 0.85
	var radial: float = _soft_d * 0.28
	var races: Array[int] = [0, 1, 2, 3]
	var y01s: Array[float] = [0.18, 0.42, 0.66, 0.88]
	var yaws: Array[float] = [20.0, 110.0, 200.0, 290.0]
	var tex_by_race: Array = [_tex_a, _tex_c, _tex_g, _tex_m]
	for i: int in range(4):
		var race: int = races[i]
		var y01: float = y01s[i]
		var yaw: float = yaws[i]
		var y: float = shaft_y - shaft_h * 0.5 + y01 * shaft_h
		var rad: float = deg_to_rad(yaw)
		var ox: float = cos(rad) * radial
		var oz: float = sin(rad) * radial
		var tint_v: Variant = TINTS[race]
		var tint: Color = Color.WHITE
		if tint_v is Color:
			tint = tint_v
		var tex_v: Variant = tex_by_race[race]
		var tex: Texture2D = _tex_base_beam
		if tex_v is Texture2D:
			tex = tex_v
		var mat: ShaderMaterial = _make_lens_mat(tint, tex)
		var mi: MeshInstance3D = MeshInstance3D.new()
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(lens_w, lens_h)
		mi.mesh = q
		mi.material_override = mat
		mi.position = Vector3(ox, y, oz)
		mi.rotation_degrees = Vector3(0, -yaw + 90.0, 0)
		parent.add_child(mi)
		var mi2: MeshInstance3D = MeshInstance3D.new()
		var q2: QuadMesh = QuadMesh.new()
		q2.size = Vector2(lens_w * 0.85, lens_h)
		mi2.mesh = q2
		mi2.material_override = mat
		mi2.position = Vector3(ox, y, oz)
		mi2.rotation_degrees = Vector3(0, -yaw, 0)
		parent.add_child(mi2)


func _make_prepare_fx() -> Node3D:
	## Keep prepare TQ materials; diameter/alpha from tunables.
	var holder: Node3D = Node3D.new()
	holder.name = "PrepareFx"
	var caustic: Texture2D = _load_tex("%s/modular_indicatorbeamactivation_st_t1a/caustic_14.png" % PREPARE_DIR)
	if caustic == null:
		caustic = _load_tex("%s/caustic_14.png" % SCAN_DIR)
	var prep_r: float = _prepare_d * 0.5
	var a_mul: float = _prepare_alpha
	var cyl: MeshInstance3D = MeshInstance3D.new()
	var cyl_mesh: CylinderMesh = CylinderMesh.new()
	cyl_mesh.top_radius = prep_r
	cyl_mesh.bottom_radius = prep_r
	cyl_mesh.height = _beam_h
	cyl_mesh.radial_segments = 28
	cyl.mesh = cyl_mesh
	var cyl_mat: StandardMaterial3D = StandardMaterial3D.new()
	cyl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cyl_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	cyl_mat.no_depth_test = true
	cyl_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.012 * a_mul)
	if _tex_soft != null:
		cyl_mat.albedo_texture = _tex_soft
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
	holder.add_child(_scan_rig)
	var band_w: float = _cell_wu * 0.2
	var band_tex: Texture2D = _tex_sensor if _tex_sensor != null else _tex_grad
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
		if _tex_grad != null:
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
			gmat.albedo_texture = _tex_grad
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


func _make_fire_fx() -> Node3D:
	## Full-length beam; tip = V-arc MASK clipping the shaft (no separate tip mesh).
	## Emit=顶(+Y), 末尾=底(-Y). _tip_from_muzzle = 发出点→遮罩起始距（与凝实直径解绑）.
	var holder: Node3D = Node3D.new()
	holder.name = "FireFx"
	var shaft_h: float = _beam_h
	var shaft_y: float = 0.0
	var fringe_w: float = _soft_d * (1.55 / 2.4)
	var bolt_w: float = _core_d * (0.95 / 1.15)
	var hot_w: float = _core_d * (0.18 / 1.15)
	## Soft layers: soft V edge; core/hot: hard V cut.
	var soft_m: ShaderMaterial = _make_base_mat(0.0, 0.72, 1.9, maxf(_beam_h / 7.0, 5.0), 0.28)
	_add_crossed_quads(holder, _soft_d, shaft_h, soft_m, shaft_y)
	var fringe_m: ShaderMaterial = _make_base_mat(0.15, 0.55, 1.6, maxf(_beam_h / 6.5, 5.2), 0.22)
	_add_crossed_quads(holder, fringe_w, shaft_h, fringe_m, shaft_y)
	var core_m: ShaderMaterial = _make_base_mat(0.85, 0.95, 2.5, maxf(_beam_h / 6.0, 5.5), 0.0)
	if _tex_a != null:
		core_m.set_shader_parameter("tex_beam", _tex_a)
	_add_crossed_quads(holder, _core_d, shaft_h, core_m, shaft_y)
	var bolt_m: ShaderMaterial = _make_base_mat(0.7, 0.9, 2.3, maxf(_beam_h / 5.8, 5.8), 0.0)
	if _tex_a != null:
		bolt_m.set_shader_parameter("tex_beam", _tex_a)
	_add_crossed_quads(holder, bolt_w, shaft_h, bolt_m, shaft_y)
	var hot_m: ShaderMaterial = _make_base_mat(1.0, 0.98, 2.9, maxf(_beam_h / 5.5, 6.0), 0.0)
	if _tex_a != null:
		hot_m.set_shader_parameter("tex_beam", _tex_a)
	_add_crossed_quads(holder, hot_w, shaft_h, hot_m, shaft_y)
	_add_witch_lenses(holder, shaft_h, shaft_y)
	return holder


func _load_image(res_path: String) -> Image:
	if res_path == "":
		return null
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		push_warning("[LanceFxPreview] missing tex %s" % abs_path)
		return null
	var img: Image = Image.new()
	if img.load(abs_path) != OK:
		return null
	return img


func _load_tex(res_path: String) -> Texture2D:
	var img: Image = _load_image(res_path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


func _load_tex_mid_tile(res_path: String) -> Texture2D:
	var img: Image = _load_image(res_path)
	if img == null:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	if h < 8:
		return ImageTexture.create_from_image(img)
	var y0: int = int(float(h) * 0.28)
	var y1: int = int(float(h) * 0.72)
	return ImageTexture.create_from_image(img.get_region(Rect2i(0, y0, w, maxi(y1 - y0, 4))))


func _apply_phase_visibility() -> void:
	if _prepare_root != null:
		_prepare_root.visible = _phase == PHASE_PREPARE
	if _fire_root != null:
		_fire_root.visible = _phase == PHASE_FIRE


func _refresh_hud() -> void:
	if _hud == null:
		return
	var phase_name: String = "准备" if _phase == PHASE_PREPARE else "开火"
	var pause_s: String = "暂停" if _phase_paused else "循环"
	var tune_name: String = _tune_names[_tune_i]
	var tune_val: float = _tune_value()
	_hud.text = (
		"混合长枪 · [%s/%s] · AD换项 WS调值 · 相机↑↓←→ QE\n选中: %s = %.3f\n凝实=%.2f 淡色=%.2f 流动=%.2f 准备Ø=%.2f 锥距=%.1f 准备α=%.2f"
		% [phase_name, pause_s, tune_name, tune_val, _core_d, _soft_d, _flow_speed, _prepare_d, _tip_from_muzzle, _prepare_alpha]
	)


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 16)
	layer.add_child(_hud)
	_refresh_hud()


func _process(delta: float) -> void:
	_time_s += delta
	_spin += delta * _SPIN_RATE
	if _icon_mat != null:
		_icon_mat.set_shader_parameter("sweep_rad", _time_s * 0.7)
	for sm_v: Variant in _beam_shaders:
		if sm_v is ShaderMaterial:
			var sm: ShaderMaterial = sm_v
			sm.set_shader_parameter("time_s", _time_s)
			sm.set_shader_parameter("travel_speed", _flow_speed)
			## Outward from emit (无畏) toward tip — CAPITAL §4.1.
			sm.set_shader_parameter("uv_scroll", _time_s * _flow_speed * 0.82)
			sm.set_shader_parameter("muzzle_end", clampf(1.0 - clampf(_tip_from_muzzle / maxf(_beam_h, 0.001), 0.05, 0.98), 0.02, 0.45))
	for entry_v: Variant in _scroll_mats:
		if entry_v is Dictionary:
			var entry: Dictionary = entry_v
			var mat_v: Variant = entry.get("mat", null)
			if mat_v is StandardMaterial3D:
				var mat: StandardMaterial3D = mat_v
				var rate: float = 0.5
				var rate_v: Variant = entry.get("rate", 0.5)
				if rate_v is float:
					rate = rate_v
				elif rate_v is int:
					var ri: int = rate_v
					rate = float(ri)
				mat.uv1_offset = Vector3(0.0, -_spin * rate, 0.0)
	for lens_v: Variant in _lens_shaders:
		if lens_v is ShaderMaterial:
			var lens_sm: ShaderMaterial = lens_v
			lens_sm.set_shader_parameter("time_s", _time_s)
			lens_sm.set_shader_parameter("uv_scroll", -_time_s * 0.35)
	if _scan_rig != null and is_instance_valid(_scan_rig) and _phase == PHASE_PREPARE:
		_scan_rig.rotation_degrees = Vector3(0.0, _time_s * 55.0, 0.0)
	if not _phase_paused:
		_phase_t += delta
		var dur: float = PHASE_PREPARE_S if _phase == PHASE_PREPARE else PHASE_FIRE_S
		if _phase_t >= dur:
			_phase_t = 0.0
			_phase = PHASE_FIRE if _phase == PHASE_PREPARE else PHASE_PREPARE
			_apply_phase_visibility()
			_refresh_hud()
	## Hold W/S to keep nudging selected tune.
	var ws: float = 0.0
	if Input.is_key_pressed(KEY_W):
		ws += 1.0
	if Input.is_key_pressed(KEY_S):
		ws -= 1.0
	if ws != 0.0:
		if _tune_hold_t <= 0.0:
			_nudge_tune(ws)
			_tune_hold_t = 0.001
		else:
			_tune_hold_t += delta
			if _tune_hold_t >= 0.11:
				_tune_hold_t = 0.001
				_nudge_tune(ws)
	else:
		_tune_hold_t = 0.0
	if _icon_mesh != null and _cam != null and is_instance_valid(_icon_mesh):
		_icon_mesh.look_at(_cam.global_position, Vector3.UP)
		_icon_mesh.rotate_object_local(Vector3.UP, PI)
	_fly_cam(delta)


func _fly_cam(delta: float) -> void:
	if _cam == null:
		return
	var boost: float = 2.6 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	var move: Vector3 = Vector3.ZERO
	## WASD reserved for tune; camera uses arrows + QE.
	if Input.is_key_pressed(KEY_UP):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		move.z += 1.0
	if Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_Q):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		move.y += 1.0
	if Input.is_key_pressed(KEY_R):
		_cam_base_pitch_deg -= _CAM_PITCH_SPEED * delta
	if Input.is_key_pressed(KEY_F):
		_cam_base_pitch_deg += _CAM_PITCH_SPEED * delta
	if Input.is_key_pressed(KEY_T):
		_cam_base_yaw_deg -= _CAM_YAW_SPEED * delta
	if Input.is_key_pressed(KEY_G):
		_cam_base_yaw_deg += _CAM_YAW_SPEED * delta
	_cam_base_pitch_deg = clampf(_cam_base_pitch_deg, -89.0, 89.0)
	if move != Vector3.ZERO:
		var cam_basis: Basis = Basis.from_euler(
			Vector3(deg_to_rad(_cam_base_pitch_deg), deg_to_rad(_cam_base_yaw_deg), 0.0)
		)
		_cam_base_pos += cam_basis * move.normalized() * (_CAM_MOVE_SPEED * boost * delta)
	_apply_cam()


func _apply_cam() -> void:
	if _cam == null:
		return
	_cam.position = _cam_base_pos
	_cam.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
