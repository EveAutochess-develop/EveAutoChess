extends Node3D

const SHIP_UNIT_SCRIPT := preload("res://scripts/ship/ship_unit.gd")

@export var ship_id: int = 10
@export var star: int = 1
@export var team_id: int = ShipUnit.TEAM_PLAYER

# 启动时预设索引（对应 PRESETS 数组下标）。
@export var start_preset_idx: int = 0

# 是否使用上面的导出 ship_id 作为初始船只。
@export var use_export_ship_id: bool = true

const TEST_SHIPS := [10, 8, 6, 41, 53, 51]
const BASE_PRESET := {
	"name": "base",
	"mode": "high_contrast",
	"sky_energy": 0.92,
	"ambient_energy": 0.70,
	"exposure": 0.86,
	"brightness": 0.97,
	"key_energy": 0.82,
	"rim_energy": 0.28,
	"fill_energy": 0.18,
	"scene_key_energy": 0.78,
	"albedo_mul": 0.82,
	"portrait_tint_strength": 0.42,
	"tint_r": 1.0,
	"tint_g": 1.0,
	"tint_b": 1.0,
	"shadow_r": 0.18,
	"shadow_g": 0.16,
	"shadow_b": 0.12,
	"mid_r": 0.66,
	"mid_g": 0.58,
	"mid_b": 0.34,
	"high_r": 0.92,
	"high_g": 0.88,
	"high_b": 0.78,
	"roughness": 0.70,
	"metallic": 0.10,
	"emission": 0.04,
	"normal_scale": 0.92
}
const PRESETS := [
	{
		"name": "unity-standard",
		"mode": "unity_standard",
		"sky_energy": 1.0,
		"ambient_energy": 1.15,
		"ambient_r": 0.212,
		"ambient_g": 0.227,
		"ambient_b": 0.259,
		"exposure": 0.9,
		"brightness": 1.0,
		"contrast": 1.0,
		"saturation": 1.0,
		"key_energy": 1.0,
		"key_color_r": 1.0,
		"key_color_g": 1.0,
		"key_color_b": 1.0,
		"key_pitch_deg": -57.3,
		"key_yaw_deg": 107.7,
		"key_roll_deg": 0.0,
		"rim_energy": 0.0,
		"fill_energy": 0.0,
		"scene_key_energy": 0.0,
		"glow_enabled": true,
		"glow_intensity": 0.55,
		"glow_strength": 0.9,
		"glow_bloom": 0.35,
		"glow_hdr_threshold": 0.45,
		"threshold1": -0.1,
		"threshold2": 0.35,
		"threshold3": 0.68,
		"metallic_threshold": 0.75,
		"color1_r": 0.0, "color1_g": 0.0, "color1_b": 0.0,
		"color2_r": 1.0, "color2_g": 1.0, "color2_b": 1.0,
		"color3_r": 0.1981132, "color3_g": 0.1981132, "color3_b": 0.1981132,
		"color4_r": 1.0, "color4_g": 0.84931314, "color4_b": 0.0,
		"color_light_r": 0.0, "color_light_g": 0.9270375, "color_light_b": 1.0,
		"glow_mul": 1.0,
		"albedo_mul": 1.0,
		"emission": 0.08,
		"normal_scale": 1.0,
		"portrait_tint_strength": 0.0,
	},
	{
		"name": "soft",
		"mode": "high_contrast",
		"sky_energy": 0.86,
		"ambient_energy": 0.62,
		"exposure": 0.80,
		"brightness": 0.95,
		"key_energy": 0.74,
		"rim_energy": 0.20,
		"fill_energy": 0.12,
		"scene_key_energy": 0.72,
		"albedo_mul": 0.76,
		"portrait_tint_strength": 0.52,
		"tint_r": 0.82,
		"tint_g": 0.90,
		"tint_b": 0.86,
		"shadow_r": 0.12,
		"shadow_g": 0.11,
		"shadow_b": 0.09,
		"mid_r": 0.58,
		"mid_g": 0.52,
		"mid_b": 0.36,
		"high_r": 0.84,
		"high_g": 0.82,
		"high_b": 0.74,
		"roughness": 0.82,
		"metallic": 0.03,
		"emission": 0.01,
		"normal_scale": 0.88
	},
	BASE_PRESET,
	{
		"name": "portrait-match",
		"mode": "high_contrast",
		"sky_energy": 0.72,
		"ambient_energy": 0.48,
		"exposure": 0.66,
		"brightness": 0.94,
		"key_energy": 0.62,
		"rim_energy": 0.10,
		"fill_energy": 0.06,
		"scene_key_energy": 0.58,
		"albedo_mul": 0.58,
		"portrait_tint_strength": 0.56,
		"tint_r": 0.94,
		"tint_g": 0.84,
		"tint_b": 0.60,
		"shadow_r": 0.08,
		"shadow_g": 0.07,
		"shadow_b": 0.05,
		"mid_r": 0.55,
		"mid_g": 0.46,
		"mid_b": 0.24,
		"high_r": 0.96,
		"high_g": 0.92,
		"high_b": 0.82,
		"roughness": 0.88,
		"metallic": 0.01,
		"emission": 0.0,
		"normal_scale": 0.78
	}
	,
	{
		"name": "high-contrast",
		"mode": "high_contrast",
		# 环境更暗、关键光更强：先把明暗拉开，后续再用 W/S/E/D/Z/X 微调。
		"sky_energy": 0.78,
		"ambient_energy": 0.30,
		"exposure": 1.00,
		"brightness": 1.00,
		"key_energy": 1.20,
		"rim_energy": 0.52,
		"fill_energy": 0.05,
		"scene_key_energy": 0.80,
		"albedo_mul": 1.04,
		"portrait_tint_strength": 0.92,
		"tint_r": 1.0,
		"tint_g": 1.0,
		"tint_b": 1.0,
		# 颜色更“分层”：暗部更深、亮部更亮。
		"shadow_r": 0.06,
		"shadow_g": 0.05,
		"shadow_b": 0.04,
		"mid_r": 0.58,
		"mid_g": 0.43,
		"mid_b": 0.28,
		"high_r": 0.98,
		"high_g": 0.96,
		"high_b": 0.90,
		# PBR 更利落：降低粗糙度提高高光可见度。
		"roughness": 0.30,
		"metallic": 0.55,
		"emission": 0.01,
		"normal_scale": 1.05,
		"contrast": 1.03,
		"hull_contrast": 1.24
	}
]

const TWEAK_DEFAULTS := {
	"exposure": 0.86,
	"albedo_mul": 0.82,
	"ambient_energy": 0.70,
	"portrait_tint_strength": 0.42,
	"contrast": 1.03,
	"hull_contrast": 1.0,
	"fill_energy": 0.18,
	"key_energy": 0.82,
	"rim_energy": 0.28,
	"roughness": 0.70,
	"metallic": 0.10,
}

var _ship_idx := 0
var _preset_idx := 0
var _ship: ShipUnit
var _cam: Camera3D
var _env: WorldEnvironment
var _key_light: DirectionalLight3D
var _rim_light: DirectionalLight3D
var _fill_light: OmniLight3D
var _scene_key: DirectionalLight3D
var _hud: CanvasLayer
var _title: Label
var _portrait: TextureRect
var _help: Label
var _live_cfg: Dictionary = {}

var _prev_precision_enabled_set: bool = false
var _prev_precision_enabled_value: Variant = null


func _ready() -> void:
	_build_scene()
	_disable_preview_decimation()
	# 初始化：根据导出参数决定起始舰船/预设。
	if use_export_ship_id:
		var idx := TEST_SHIPS.find(ship_id)
		_ship_idx = 0 if idx == -1 else idx
	_preset_idx = start_preset_idx
	if _preset_idx < 0:
		_preset_idx = 0
	elif _preset_idx >= PRESETS.size():
		_preset_idx = PRESETS.size() - 1
	_live_cfg = _current_preset()
	_sync_look_cfg(_live_cfg)
	_spawn_ship()
	_apply_environment_tune(_live_cfg)
	_refresh_hud()


func _disable_preview_decimation() -> void:
	# 预览目标是“上色/光照迭代”，不希望半精度 decimate 造成明显面缺失（看起来像镂空）。
	if typeof(DataStore) == TYPE_NIL or DataStore.visual == null:
		return
	if not (DataStore.visual is Dictionary):
		return
	var vis := DataStore.visual as Dictionary
	if not _prev_precision_enabled_set:
		_prev_precision_enabled_value = vis.get("model_load_precision_enabled", null)
		_prev_precision_enabled_set = true
	vis["model_load_precision_enabled"] = false


func _exit_tree() -> void:
	# 尽量不污染全局：恢复 decimation 开关（预览离开时）。
	if not _prev_precision_enabled_set:
		return
	if typeof(DataStore) == TYPE_NIL or DataStore.visual == null:
		return
	if not (DataStore.visual is Dictionary):
		return
	var vis := DataStore.visual as Dictionary
	if _prev_precision_enabled_value == null:
		vis.erase("model_load_precision_enabled")
	else:
		vis["model_load_precision_enabled"] = _prev_precision_enabled_value


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	match event.keycode:
		KEY_LEFT:
			_ship_idx = posmod(_ship_idx - 1, TEST_SHIPS.size())
			_spawn_ship()
		KEY_RIGHT:
			_ship_idx = posmod(_ship_idx + 1, TEST_SHIPS.size())
			_spawn_ship()
		KEY_UP:
			_preset_idx = posmod(_preset_idx + 1, PRESETS.size())
			_live_cfg = _current_preset()
			_apply_preset()
		KEY_DOWN:
			_preset_idx = posmod(_preset_idx - 1, PRESETS.size())
			_live_cfg = _current_preset()
			_apply_preset()
		KEY_Q:
			_tweak("exposure", -0.08)
		KEY_A:
			_tweak("exposure", 0.08)
		KEY_W:
			_tweak("albedo_mul", -0.08)
		KEY_S:
			_tweak("albedo_mul", 0.08)
		KEY_E:
			_tweak("ambient_energy", -0.10)
		KEY_D:
			_tweak("ambient_energy", 0.10)
		KEY_Z:
			_tweak("portrait_tint_strength", -0.10)
		KEY_X:
			_tweak("portrait_tint_strength", 0.10)
		KEY_C:
			_tweak("contrast", -0.05)
		KEY_V:
			_tweak("contrast", 0.05)
		KEY_B:
			_tweak("hull_contrast", -0.08)
		KEY_F:
			_tweak("fill_energy", 0.10)
		KEY_G:
			_tweak("fill_energy", -0.10)
		KEY_T:
			_tweak("key_energy", 0.10)
		KEY_Y:
			_tweak("key_energy", -0.10)
		KEY_U:
			_tweak("rim_energy", 0.10)
		KEY_I:
			_tweak("rim_energy", -0.10)
		KEY_J:
			_tweak("roughness", 0.10)
		KEY_K:
			_tweak("roughness", -0.10)
		KEY_N:
			_tweak("hull_contrast", 0.08)
		KEY_M:
			_tweak("metallic", -0.10)
		KEY_R:
			_preset_idx = 0
			_live_cfg = _current_preset()
			_apply_preset()
		KEY_P:
			print("[ShipColorViewer] ship=%s preset=%s cfg=%s" % [
				str(_current_ship_id()), str(_live_cfg.get("name", "?")), JSON.stringify(_live_cfg)
			])


func _build_scene() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16.0, 16.0)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.08, 0.09, 0.11)
	ground_mat.roughness = 0.95
	ground.material_override = ground_mat
	add_child(ground)

	_scene_key = DirectionalLight3D.new()
	_scene_key.name = "SceneKey"
	_scene_key.rotation_degrees = Vector3(-55.0, -10.0, 0.0)
	add_child(_scene_key)

	_key_light = DirectionalLight3D.new()
	_key_light.name = "KeyLight"
	_key_light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	_key_light.light_color = Color(1.0, 0.98, 0.94)
	_key_light.shadow_enabled = true
	add_child(_key_light)

	_rim_light = DirectionalLight3D.new()
	_rim_light.name = "RimLight"
	_rim_light.rotation_degrees = Vector3(-15.0, 145.0, 0.0)
	_rim_light.light_color = Color(0.65, 0.8, 1.0)
	add_child(_rim_light)

	_fill_light = OmniLight3D.new()
	_fill_light.name = "FillLight"
	_fill_light.position = Vector3(0.0, 5.5, 6.0)
	_fill_light.omni_range = 22.0
	add_child(_fill_light)

	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 2.4, 7.0)
	_cam.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	_cam.fov = 26.0
	add_child(_cam)

	_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.76, 0.80)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.03
	env.adjustment_saturation = 1.0
	_env.environment = env
	add_child(_env)

	_hud = CanvasLayer.new()
	add_child(_hud)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(root)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 16
	panel.offset_top = 16
	panel.offset_right = 340
	panel.offset_bottom = 330
	root.add_child(panel)

	var vb := VBoxContainer.new()
	panel.add_child(vb)

	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(_title, true, 18)
	vb.add_child(_title)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(256, 210)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.visible = false
	vb.add_child(_portrait)

	_help = Label.new()
	_help.text = "Left/Right 切舰  Up/Down 切预设\nQ/A 曝光  W/S 贴图乘子  E/D 环境光  Z/X 染色强度\nC/V -Contrast/+Contrast  B/N -HullContrast/+HullContrast\nF/G +Fill/-Fill  T/Y +Key/-Key  U/I +Rim/-Rim\nJ/K +Rough/-Rough  M -Metal  R 重置  P 打印当前参数"
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(_help, false, 14)
	vb.add_child(_help)


func _spawn_ship() -> void:
	if _ship and is_instance_valid(_ship):
		_ship.queue_free()
		_ship = null
	_ship = SHIP_UNIT_SCRIPT.new()
	add_child(_ship)
	_ship.position = Vector3(0.0, 0.0, 0.0)
	_ship.setup(_current_ship_id(), star, team_id)
	_ship.slot_type = "hangar"
	_ship.rotation_degrees = Vector3(0.0, 205.0, 0.0)
	var hb := _ship.get_node_or_null("HealthBar")
	if hb:
		_hide_node_tree_visible(hb, false)
	_refresh_hud()
	await get_tree().process_frame
	_frame_ship()
	if ShipLook.is_unity_standard():
		_apply_unity_material_tune(_live_cfg if not _live_cfg.is_empty() else _current_preset())
	else:
		_apply_material_tune()


func _frame_ship() -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	var meshes := _find_meshes(_ship)
	if meshes.is_empty():
		return
	var aabb := AABB()
	var first := true
	for mi in meshes:
		var local_aabb := mi.get_aabb()
		for i in range(8):
			var p := _ship.global_transform.affine_inverse() * mi.global_transform * local_aabb.get_endpoint(i)
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	if first:
		return
	var center := aabb.get_center()
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	_ship.position = Vector3(-center.x, -aabb.position.y, -center.z)
	_cam.position = Vector3(0.0, maxf(1.4, longest * 0.34), maxf(4.6, longest * 1.45))
	_cam.look_at(Vector3(0.0, aabb.size.y * 0.42, 0.0), Vector3.UP)
	_fill_light.position = Vector3(0.0, maxf(3.0, longest * 0.8), maxf(4.0, longest * 0.9))


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_find_meshes(c))
	return out


func _hide_node_tree_visible(root: Node, visible_flag: bool) -> void:
	if root is Node3D:
		(root as Node3D).visible = visible_flag
	elif root is CanvasItem:
		(root as CanvasItem).visible = visible_flag
	for c in root.get_children():
		_hide_node_tree_visible(c, visible_flag)


func _current_ship_id() -> int:
	return int(TEST_SHIPS[_ship_idx])


func _current_preset() -> Dictionary:
	return (PRESETS[_preset_idx] as Dictionary).duplicate(true)


func _apply_preset() -> void:
	var cfg := _live_cfg if not _live_cfg.is_empty() else _current_preset()
	_sync_look_cfg(cfg)
	_apply_environment_tune(cfg)
	# Re-tint via spawn so unity_standard shader is picked at _tint_model time.
	_spawn_ship()
	_refresh_hud()


func _sync_look_cfg(cfg: Dictionary) -> void:
	if typeof(DataStore) == TYPE_NIL or not (DataStore.visual is Dictionary):
		return
	var vis := DataStore.visual as Dictionary
	var look: Dictionary = {}
	if vis.get("ship_look") is Dictionary:
		look = (vis["ship_look"] as Dictionary).duplicate(true)
	for k in cfg.keys():
		look[k] = cfg[k]
	if not look.has("mode"):
		var n := str(look.get("name", "")).to_lower()
		look["mode"] = "unity_standard" if n == "unity-standard" or n == "unity_standard" else "high_contrast"
	vis["ship_look"] = look
	ShipLook.clear_caches()


func _apply_unity_material_tune(cfg: Dictionary = {}) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	if cfg.is_empty():
		cfg = _live_cfg if not _live_cfg.is_empty() else _current_preset()
	_sync_look_cfg(cfg)
	for mi in _find_meshes(_ship):
		if mi.material_override is ShaderMaterial:
			var smat := mi.material_override as ShaderMaterial
			ShipLook.apply_to_unity_shader_material(smat)
		elif mi.material_override is StandardMaterial3D:
			var mat := mi.material_override as StandardMaterial3D
			ShipLook.apply_to_standard_material(mat, _current_ship_id(), mat.albedo_texture, "")


func _apply_environment_tune(cfg: Dictionary = {}) -> void:
	if cfg.is_empty():
		cfg = _live_cfg if not _live_cfg.is_empty() else _current_preset()
	_sync_look_cfg(cfg)
	var env := _env.environment
	ShipLook.apply_match_environment(env)
	if str(cfg.get("mode", "")).to_lower() == "unity_standard" or str(cfg.get("name", "")).to_lower() == "unity-standard":
		_key_light.light_energy = float(cfg.get("key_energy", 1.0))
		_key_light.light_color = Color(
			float(cfg.get("key_color_r", 1.0)),
			float(cfg.get("key_color_g", 1.0)),
			float(cfg.get("key_color_b", 1.0))
		)
		_key_light.rotation_degrees = Vector3(
			float(cfg.get("key_pitch_deg", -57.3)),
			float(cfg.get("key_yaw_deg", 107.7)),
			float(cfg.get("key_roll_deg", 0.0))
		)
		_rim_light.light_energy = float(cfg.get("rim_energy", 0.0))
		_fill_light.light_energy = float(cfg.get("fill_energy", 0.0))
		_scene_key.light_energy = float(cfg.get("scene_key_energy", 0.0))
		return
	env.ambient_light_energy = float(cfg.get("ambient_energy", 0.7))
	env.tonemap_exposure = float(cfg.get("exposure", 0.86))
	env.adjustment_brightness = float(cfg.get("brightness", 0.97))
	env.adjustment_contrast = float(cfg.get("contrast", 1.03))
	_scene_key.light_energy = float(cfg.get("scene_key_energy", 0.78))
	_key_light.light_energy = float(cfg.get("key_energy", 0.82))
	_rim_light.light_energy = float(cfg.get("rim_energy", 0.28))
	_fill_light.light_energy = float(cfg.get("fill_energy", 0.18))


func _tweak(key: String, delta: float) -> void:
	if _live_cfg.is_empty():
		_live_cfg = _current_preset()
	var base_val := float(_live_cfg.get(key, TWEAK_DEFAULTS.get(key, 0.0)))
	_live_cfg[key] = base_val + delta
	_sync_look_cfg(_live_cfg)
	_apply_environment_tune(_live_cfg)
	if ShipLook.is_unity_standard():
		_apply_unity_material_tune(_live_cfg)
	else:
		_apply_material_tune(_live_cfg)
	_refresh_hud()


func _apply_material_tune(cfg: Dictionary = {}) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	if cfg.is_empty():
		cfg = _live_cfg if not _live_cfg.is_empty() else _current_preset()
	_sync_look_cfg(cfg)
	if ShipLook.is_unity_standard():
		_apply_unity_material_tune(cfg)
		return
	var albedo_mul := float(cfg.get("albedo_mul", 0.82))
	var portrait_tint_strength := float(cfg.get("portrait_tint_strength", 0.42))
	var manual_tint := Color(
		float(cfg.get("tint_r", 1.0)),
		float(cfg.get("tint_g", 1.0)),
		float(cfg.get("tint_b", 1.0)),
		1.0
	)
	var roughness := float(cfg.get("roughness", 0.70))
	var metallic := float(cfg.get("metallic", 0.10))
	var emission := float(cfg.get("emission", 0.04))
	var normal_scale := float(cfg.get("normal_scale", 0.92))
	var hull_contrast := float(cfg.get("hull_contrast", 1.0))
	var tint := manual_tint.lerp(_portrait_tint(), portrait_tint_strength)
	var shadow_col := Color(float(cfg.get("shadow_r", 0.18)), float(cfg.get("shadow_g", 0.16)), float(cfg.get("shadow_b", 0.12)), 1.0)
	var mid_col := Color(float(cfg.get("mid_r", 0.66)), float(cfg.get("mid_g", 0.58)), float(cfg.get("mid_b", 0.34)), 1.0)
	var high_col := Color(float(cfg.get("high_r", 0.92)), float(cfg.get("high_g", 0.88)), float(cfg.get("high_b", 0.78)), 1.0)
	var portrait_palette := _portrait_palette()
	shadow_col = shadow_col.lerp(portrait_palette["shadow"], 0.55)
	mid_col = mid_col.lerp(portrait_palette["mid"], 0.55)
	high_col = high_col.lerp(portrait_palette["high"], 0.55)
	# 同一舰的材质通常共享同一 albedo_tex，避免重复重采样。
	var remapped_ad_tex: Texture2D = null
	var last_ad_tex: Texture2D = null
	for mi in _find_meshes(_ship):
		if mi.material_override is StandardMaterial3D:
			var mat := mi.material_override as StandardMaterial3D
			if mat == null:
				continue
			# 预览必须实体化：避免 alpha/剔除导致“镂空”观感。
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			if mat.albedo_texture:
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				mat.albedo_texture = _remap_texture_tones(mat.albedo_texture, shadow_col, mid_col, high_col, tint, albedo_mul, hull_contrast)
				mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
				mat.roughness = roughness
				mat.metallic = metallic
				mat.metallic_specular = 0.03
				mat.ao_enabled = false
				mat.emission_enabled = emission > 0.0
				mat.emission = Color(1, 1, 1) * emission
				mat.emission_energy_multiplier = 1.0
				if mat.normal_enabled:
					mat.normal_scale = normal_scale
			else:
				mat.albedo_color = Color(0.55, 0.60, 0.66)
				mat.roughness = 0.85
		elif mi.material_override is ShaderMaterial:
			var smat := mi.material_override as ShaderMaterial
			if smat == null:
				continue
			# 让 shader 内的 hull/team tint 不重复染色；颜色差异主要来自 remap + lum masks。
			smat.set_shader_parameter("hull_tint", Color.WHITE)
			smat.set_shader_parameter("team_tint", Color.WHITE)
			smat.set_shader_parameter("team_mix", 0.0)
			smat.set_shader_parameter("normal_scale", normal_scale)
			# 利用 PBR 响应强弱（粗糙度/金属度/轻微发光）突出明暗层次。
			smat.set_shader_parameter("pmwo_metallic", metallic)
			smat.set_shader_parameter("pmwo_roughness", roughness)
			smat.set_shader_parameter("combat_emission_strength", emission)

			var ad_any: Variant = smat.get_shader_parameter("albedo_tex")
			if ad_any is Texture2D:
				var ad_tex := ad_any as Texture2D
				if last_ad_tex == null or ad_tex != last_ad_tex:
					remapped_ad_tex = _remap_texture_tones(ad_tex, shadow_col, mid_col, high_col, tint, albedo_mul, hull_contrast)
					last_ad_tex = ad_tex
				smat.set_shader_parameter("albedo_tex", remapped_ad_tex)


func _refresh_hud() -> void:
	var ship := DataStore.get_ship(_current_ship_id())
	var ship_name := str(ship.get("name", "?"))
	var key := str(ship.get("model_key", ""))
	var cfg := _live_cfg if not _live_cfg.is_empty() else _current_preset()
	_title.text = "%s  (%s)\n预设=%s exp=%.2f amb=%.2f ctr=%.2f hullCtr=%.2f fill=%.2f key=%.2f rim=%.2f\nmul=%.2f tint=%.2f rgb=%.2f/%.2f/%.2f rough=%.2f metal=%.2f" % [
		ship_name,
		key,
		str(cfg.get("name", "?")),
		float(cfg.get("exposure", 0.0)),
		float(cfg.get("ambient_energy", 0.0)),
		float(cfg.get("contrast", 1.03)),
		float(cfg.get("hull_contrast", 1.0)),
		float(cfg.get("fill_energy", 0.0)),
		float(cfg.get("key_energy", 0.0)),
		float(cfg.get("rim_energy", 0.0)),
		float(cfg.get("albedo_mul", 0.0)),
		float(cfg.get("portrait_tint_strength", 0.0)),
		float(cfg.get("tint_r", 0.0)),
		float(cfg.get("tint_g", 0.0)),
		float(cfg.get("tint_b", 0.0)),
		float(cfg.get("roughness", 0.0)),
		float(cfg.get("metallic", 0.0))
	]
	_portrait.texture = UiAssets.champion_icon(ship_name, _current_ship_id())


func _portrait_tint() -> Color:
	if _portrait.texture == null:
		return Color(0.82, 0.88, 0.92, 1.0)
	var img := _portrait.texture.get_image()
	if img == null or img.is_empty():
		return Color(0.82, 0.88, 0.92, 1.0)
	img.decompress()
	var acc := Vector3.ZERO
	var weight_sum := 0.0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a < 0.1:
				continue
			if c.s < 0.18 or c.v < 0.14 or c.v > 0.92:
				continue
			var w := c.s * (1.0 - absf(c.v - 0.55))
			acc += Vector3(c.r, c.g, c.b) * w
			weight_sum += w
	if weight_sum <= 0.0001:
		return Color(0.82, 0.88, 0.92, 1.0)
	var rgb := acc / weight_sum
	var mx := maxf(rgb.x, maxf(rgb.y, rgb.z))
	if mx > 0.0001:
		rgb /= mx
	return Color(
		clampf(rgb.x, 0.0, 1.0),
		clampf(rgb.y, 0.0, 1.0),
		clampf(rgb.z, 0.0, 1.0),
		1.0
	)


func _portrait_palette() -> Dictionary:
	var fallback := {
		"shadow": Color(0.12, 0.09, 0.05, 1.0),
		"mid": Color(0.52, 0.44, 0.30, 1.0),
		"high": Color(0.88, 0.82, 0.67, 1.0),
	}
	if _portrait.texture == null:
		return fallback
	var img := _portrait.texture.get_image()
	if img == null or img.is_empty():
		return fallback
	img.decompress()
	var buckets := {
		"shadow": {"acc": Vector3.ZERO, "w": 0.0, "lo": 0.0, "hi": 0.18},
		"mid": {"acc": Vector3.ZERO, "w": 0.0, "lo": 0.18, "hi": 0.65},
		"high": {"acc": Vector3.ZERO, "w": 0.0, "lo": 0.65, "hi": 1.01},
	}
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a < 0.2:
				continue
			var lum := (c.r + c.g + c.b) / 3.0
			var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			for key in buckets.keys():
				var b: Dictionary = buckets[key]
				if lum >= float(b["lo"]) and lum < float(b["hi"]):
					var w := maxf(sat, 0.03)
					b["acc"] = (b["acc"] as Vector3) + Vector3(c.r, c.g, c.b) * w
					b["w"] = float(b["w"]) + w
					buckets[key] = b
					break
	var out := {}
	for key in ["shadow", "mid", "high"]:
		var b: Dictionary = buckets[key]
		if float(b["w"]) <= 0.0001:
			out[key] = fallback[key]
		else:
			var rgb := (b["acc"] as Vector3) / float(b["w"])
			out[key] = Color(rgb.x, rgb.y, rgb.z, 1.0)
	return out


func _remap_texture_tones(
	tex: Texture2D,
	shadow_col: Color,
	mid_col: Color,
	high_col: Color,
	tint: Color,
	mul: float,
	hull_contrast: float = 1.0
) -> Texture2D:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex
	img.decompress()
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			var lum := (c.r + c.g + c.b) / 3.0
			var mapped: Color
			if lum < 0.22:
				var t0 := clampf(lum / 0.22, 0.0, 1.0)
				mapped = shadow_col.lerp(mid_col, t0)
			elif lum < 0.72:
				var t1 := clampf((lum - 0.22) / 0.50, 0.0, 1.0)
				mapped = mid_col.lerp(high_col, t1 * 0.25)
			else:
				var t2 := clampf((lum - 0.72) / 0.28, 0.0, 1.0)
				mapped = mid_col.lerp(high_col, 0.25 + t2 * 0.75)
			var detail_boost := 0.42 + lum * 0.92
			mapped = Color(
				mapped.r * tint.r * mul * detail_boost,
				mapped.g * tint.g * mul * detail_boost,
				mapped.b * tint.b * mul * detail_boost,
				1.0
			)
			# 舰船本体颜色对比度：围绕 0.5 灰做拉伸/压缩，不影响环境整体对比度。
			mapped.r = clampf(0.5 + (mapped.r - 0.5) * hull_contrast, 0.0, 1.0)
			mapped.g = clampf(0.5 + (mapped.g - 0.5) * hull_contrast, 0.0, 1.0)
			mapped.b = clampf(0.5 + (mapped.b - 0.5) * hull_contrast, 0.0, 1.0)
			out.set_pixel(x, y, mapped)
	return ImageTexture.create_from_image(out)
