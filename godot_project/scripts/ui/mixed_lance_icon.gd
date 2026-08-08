extends RefCounted
class_name MixedLanceIcon
## Dynamic mixed-lance icon (CAPITAL_AND_CYNO §4.1) — shared by 2D UI + 3D fit strip.

const MODULE_ID: String = "mixed_lance"
const ICON_A: String = "res://assets/vfx/lance/icon_amarr.png"
const ICON_C: String = "res://assets/vfx/lance/icon_caldari.png"
const ICON_G: String = "res://assets/vfx/lance/icon_gallente.png"
const ICON_M: String = "res://assets/vfx/lance/icon_minmatar.png"
const SHADER_2D: String = "res://shaders/lance_mixed_icon_2d.gdshader"
const SHADER_3D: String = "res://shaders/lance_mixed_icon.gdshader"
const SWEEP_RATE: float = 0.28

static func is_mixed_lance(mod: Dictionary) -> bool:
	return str(mod.get("id", "")).strip_edges() == MODULE_ID or str(mod.get("activate", "")) == "mixed_lance"


static func _load_tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func make_2d_material() -> ShaderMaterial:
	var sh: Shader = load(SHADER_2D) as Shader
	var sm: ShaderMaterial = ShaderMaterial.new()
	sm.shader = sh
	_bind_icons(sm)
	sm.set_shader_parameter("sweep_rad", 0.0)
	return sm


static func make_3d_material(priority: int = 14) -> ShaderMaterial:
	var sh: Shader = load(SHADER_3D) as Shader
	var sm: ShaderMaterial = ShaderMaterial.new()
	sm.shader = sh
	_bind_icons(sm)
	sm.set_shader_parameter("sweep_rad", 0.0)
	sm.render_priority = priority
	return sm


static func _bind_icons(sm: ShaderMaterial) -> void:
	var ia: Texture2D = _load_tex(ICON_A)
	var ic: Texture2D = _load_tex(ICON_C)
	var ig: Texture2D = _load_tex(ICON_G)
	var im: Texture2D = _load_tex(ICON_M)
	if ia != null:
		sm.set_shader_parameter("icon_a", ia)
	if ic != null:
		sm.set_shader_parameter("icon_c", ic)
	if ig != null:
		sm.set_shader_parameter("icon_g", ig)
	if im != null:
		sm.set_shader_parameter("icon_m", im)


static func apply_sweep(sm: ShaderMaterial, time_s: float) -> void:
	if sm == null:
		return
	sm.set_shader_parameter("sweep_rad", time_s * SWEEP_RATE)


## ColorRect that drives sweep_rad every frame (2D bag/shop/detail).
static func make_anim_rect() -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.color = Color.WHITE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.material = make_2d_material()
	rect.set_script(load("res://scripts/ui/mixed_lance_icon_rect.gd") as Script)
	return rect
