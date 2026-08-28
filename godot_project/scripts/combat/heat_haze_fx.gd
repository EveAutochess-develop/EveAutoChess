extends Node3D
class_name HeatHazeFx
## Local heat shimmer volume. Lifetime = this node (parent queues free). No hardcoded seconds.

const SHADER_PATH: String = "res://shaders/heat_haze.gdshader"
const MASK_CONE_SHELL: int = 0
const MASK_RADIAL_POINT: int = 1
# #region agent log
const _DBG_LOG: String = "H:/debug-509535.log"
# #endregion

## Lance cone breath: Prep contracts toward muzzle; Fire expands outward.
const BREATH_OFF: int = 0
const BREATH_CONTRACT: int = 1
const BREATH_EXPAND: int = 2

var _mi: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _mask: int = MASK_CONE_SHELL
var _height: float = 8.0
var _r_muzzle: float = 0.6
var _r_tip: float = 1.1
var _point_radius: float = 2.4
var _point_height: float = 0.35
var _strength: float = 0.003
var _intensity: float = 1.0
var _built: bool = false
var _breath: int = BREATH_OFF
var _breath_t: float = 0.0
# #region agent log
var _dbg_breath_logs: int = 0
# #endregion


# #region agent log
func _dbg(hyp: String, msg: String, data: Dictionary = {}) -> void:
	var f: FileAccess = FileAccess.open(_DBG_LOG, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(_DBG_LOG, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var payload: Dictionary = {
		"sessionId": "509535",
		"runId": "post-fix",
		"hypothesisId": hyp,
		"location": "heat_haze_fx.gd",
		"message": msg,
		"data": data,
		"timestamp": Time.get_ticks_msec(),
	}
	f.store_line(JSON.stringify(payload))
	f.close()
# #endregion


static func fx_allowed() -> bool:
	var ps: PlayerSettings = PlayerSettings.get_or_null()
	if ps == null:
		return true
	if ps.no_model_perf_mode:
		return false
	if ps.weapon_fx_simplified:
		return false
	return true


func configure_cone(height: float, soft_d: float, strength: float = 0.003, intensity: float = 1.0) -> void:
	_mask = MASK_CONE_SHELL
	_height = maxf(0.5, height)
	var soft: float = maxf(0.2, soft_d)
	## Outer shell around soft radius — slightly larger than beam, tip wider.
	var soft_r: float = soft * 0.5
	_r_muzzle = soft_r * 1.08
	_r_tip = maxf(soft_r * 1.35, _r_muzzle * 1.12)
	_strength = clampf(strength, 0.0, 0.012)
	_intensity = clampf(intensity, 0.0, 1.2)
	_ensure_built()
	_apply_mesh_and_params()
	# #region agent log
	_dbg("A", "configure_cone", {
		"soft_d": soft,
		"h": _height,
		"r_muzzle": _r_muzzle,
		"r_tip": _r_tip,
		"strength": _strength,
		"intensity": _intensity,
		"soft_radius": soft_r,
		"cover_alpha": 0.14,
	})
	# #endregion


func configure_point(radius: float, strength: float = 0.0035, intensity: float = 1.0, height: float = 0.35) -> void:
	_mask = MASK_RADIAL_POINT
	_point_radius = maxf(0.3, radius)
	_point_height = maxf(0.05, height)
	_strength = clampf(strength, 0.0, 0.012)
	_intensity = clampf(intensity, 0.0, 1.2)
	_breath = BREATH_OFF
	scale = Vector3.ONE
	_ensure_built()
	_apply_mesh_and_params()
	# #region agent log
	_dbg("A", "configure_point", {
		"radius": _point_radius,
		"strength": _strength,
		"intensity": _intensity,
		"cover_alpha": 0.14,
	})
	# #endregion


## Prep → contract toward dreadnought (muzzle); Fire/End → expand outward.
func set_lance_breath(prepare: bool) -> void:
	var next: int = BREATH_CONTRACT if prepare else BREATH_EXPAND
	if _breath != next:
		_breath = next
		_breath_t = 0.0
		# #region agent log
		_dbg("B", "set_lance_breath", {"prepare": prepare, "breath": _breath})
		# #endregion
	set_process(_breath != BREATH_OFF and _built)


func set_intensity(v: float) -> void:
	_intensity = clampf(v, 0.0, 1.2)
	if _mat != null:
		_mat.set_shader_parameter("intensity", _intensity)


func _process(delta: float) -> void:
	if _breath == BREATH_OFF or not _built:
		return
	_breath_t += delta
	## Mild breath — avoid near-zero scale flicker.
	if _breath == BREATH_CONTRACT:
		var u: float = 0.5 + 0.5 * cos(_breath_t * TAU / 1.8)
		var sy: float = lerpf(0.72, 1.0, u)
		var sxz: float = lerpf(0.82, 1.0, u)
		scale = Vector3(sxz, sy, sxz)
		if _mat != null:
			_mat.set_shader_parameter("noise_speed", Vector2(0.05, -0.14))
	else:
		var u2: float = 0.5 + 0.5 * sin(_breath_t * TAU / 1.6)
		var sy2: float = lerpf(0.88, 1.08, u2)
		var sxz2: float = lerpf(0.92, 1.1, u2)
		scale = Vector3(sxz2, sy2, sxz2)
		if _mat != null:
			_mat.set_shader_parameter("noise_speed", Vector2(0.07, 0.16))
	# #region agent log
	_dbg_breath_logs += 1
	if _dbg_breath_logs <= 8 or (_dbg_breath_logs % 30) == 0:
		_dbg("B", "breath_tick", {
			"breath": _breath,
			"sx": scale.x,
			"sy": scale.y,
			"sz": scale.z,
			"n": _dbg_breath_logs,
		})
	# #endregion


func _ensure_built() -> void:
	if _built:
		return
	if not fx_allowed():
		visible = false
		return
	var sh: Shader = load(SHADER_PATH) as Shader
	if sh == null:
		return
	_mi = MeshInstance3D.new()
	_mi.name = "HeatHazeMesh"
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("noise_tex", _make_noise_tex())
	_mi.material_override = _mat
	_built = true
	set_process(_breath != BREATH_OFF)


func _apply_mesh_and_params() -> void:
	if not _built or _mi == null or _mat == null:
		return
	if _mask == MASK_CONE_SHELL:
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.bottom_radius = _r_muzzle
		cyl.top_radius = _r_tip
		cyl.height = _height
		cyl.radial_segments = 24
		cyl.rings = 4
		_mi.mesh = cyl
		_mi.position = Vector3(0.0, _height * 0.5, 0.0)
		_mat.set_shader_parameter("mask_mode", 0.0)
		_mat.set_shader_parameter("noise_scale", 2.4)
		_mat.set_shader_parameter("noise_speed", Vector2(0.06, 0.12))
		_mat.set_shader_parameter("edge_soft", 0.1)
		_mat.set_shader_parameter("cover_alpha", 0.14)
	else:
		var q: QuadMesh = QuadMesh.new()
		var d: float = _point_radius * 2.0
		q.size = Vector2(d, d)
		_mi.mesh = q
		_mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		_mi.position = Vector3(0.0, _point_height, 0.0)
		_mat.set_shader_parameter("mask_mode", 1.0)
		_mat.set_shader_parameter("noise_scale", 1.6)
		_mat.set_shader_parameter("noise_speed", Vector2(0.08, 0.1))
		_mat.set_shader_parameter("edge_soft", 0.22)
		_mat.set_shader_parameter("cover_alpha", 0.12)
	_mat.set_shader_parameter("strength", _strength)
	_mat.set_shader_parameter("intensity", _intensity)


func _make_noise_tex() -> Texture2D:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var nt: NoiseTexture2D = NoiseTexture2D.new()
	nt.width = 128
	nt.height = 128
	nt.seamless = true
	nt.noise = noise
	return nt
