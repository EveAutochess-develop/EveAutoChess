extends Node
class_name PlayerSettings
## Content-side settings host under /root/PlayerSettings (PCK cannot register Autoloads).
## Authority for graphics / developer / audio prefs → user://player_settings.cfg.

const NODE_NAME: StringName = &"PlayerSettings"
const SETTINGS_PATH: String = "user://player_settings.cfg"
const _SELF: String = "res://scripts/core/player_settings.gd"
const SFX_BUS: StringName = &"SFX"

var target_fps: int = 60
var no_model_perf_mode: bool = false
var weapon_fx_simplified: bool = false
var camera_breathe_enabled: bool = true
var health_bar_style: String = "ring"
var health_bar_visible: bool = true
var developer_debug_enabled: bool = false
var player_citadel_soften: bool = false
var player_ai_double_economy: bool = false
var enemy_layout_adjust: bool = false
var sfx_enabled: bool = true
var sfx_volume_pct: float = 80.0


static func instance() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	@warning_ignore("unsafe_cast")
	var tree: SceneTree = loop as SceneTree
	var existing: Node = tree.root.get_node_or_null(NodePath(String(NODE_NAME)))
	if existing:
		return existing
	var loaded: Variant = load(_SELF)
	if not (loaded is GDScript):
		return null
	@warning_ignore("unsafe_cast")
	var scr: GDScript = loaded as GDScript
	var created: Variant = scr.new()
	if not (created is Node):
		return null
	@warning_ignore("unsafe_cast")
	var n: Node = created as Node
	n.name = String(NODE_NAME)
	tree.root.add_child(n)
	return n


static func get_or_null() -> PlayerSettings:
	var n: Node = instance()
	if n is PlayerSettings:
		return n as PlayerSettings
	return null


func _ready() -> void:
	_load_settings()
	_apply_sfx_bus()


func _load_settings() -> void:
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	target_fps = TypedVariant.as_int(cf.get_value("graphics", "target_fps", target_fps), target_fps)
	no_model_perf_mode = TypedVariant.as_bool(cf.get_value("graphics", "no_model_perf_mode", false), false)
	weapon_fx_simplified = TypedVariant.as_bool(cf.get_value("graphics", "weapon_fx_simplified", false), false)
	camera_breathe_enabled = TypedVariant.as_bool(cf.get_value("graphics", "camera_breathe_enabled", true), true)
	health_bar_visible = TypedVariant.as_bool(cf.get_value("graphics", "health_bar_visible", true), true)
	health_bar_style = str(cf.get_value("graphics", "health_bar_style", health_bar_style))
	if health_bar_style != "bars":
		health_bar_style = "ring"
	developer_debug_enabled = TypedVariant.as_bool(cf.get_value("developer", "debug_enabled", false), false)
	player_citadel_soften = TypedVariant.as_bool(cf.get_value("developer", "player_citadel_soften", false), false)
	player_ai_double_economy = TypedVariant.as_bool(cf.get_value("developer", "player_ai_double_economy", false), false)
	enemy_layout_adjust = TypedVariant.as_bool(cf.get_value("developer", "enemy_layout_adjust", false), false)
	sfx_enabled = TypedVariant.as_bool(cf.get_value("audio", "sfx_enabled", true), true)
	sfx_volume_pct = TypedVariant.as_float(cf.get_value("audio", "sfx_volume", sfx_volume_pct), sfx_volume_pct)


func save_settings() -> void:
	var cf: ConfigFile = ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("graphics", "target_fps", target_fps)
	cf.set_value("graphics", "no_model_perf_mode", no_model_perf_mode)
	cf.set_value("graphics", "weapon_fx_simplified", weapon_fx_simplified)
	cf.set_value("graphics", "camera_breathe_enabled", camera_breathe_enabled)
	cf.set_value("graphics", "health_bar_visible", health_bar_visible)
	cf.set_value("graphics", "health_bar_style", health_bar_style)
	cf.set_value("developer", "debug_enabled", developer_debug_enabled)
	cf.set_value("developer", "player_citadel_soften", player_citadel_soften)
	cf.set_value("developer", "player_ai_double_economy", player_ai_double_economy)
	cf.set_value("developer", "enemy_layout_adjust", enemy_layout_adjust)
	cf.set_value("audio", "sfx_enabled", sfx_enabled)
	cf.set_value("audio", "sfx_volume", sfx_volume_pct)
	cf.save(SETTINGS_PATH)


func _diag(tag: String, msg: String) -> void:
	SessionDiagnostics.log(tag, msg)


func set_no_model_perf_mode(on: bool) -> void:
	no_model_perf_mode = on
	save_settings()
	_diag("settings", "nomodel=%d fps_cap=%d" % [1 if on else 0, target_fps])
	var tree: SceneTree = get_tree()
	if tree:
		tree.call_group("match_root", "apply_no_model_perf_mode_changed")


func set_weapon_fx_simplified(on: bool) -> void:
	weapon_fx_simplified = on
	save_settings()
	_diag("settings", "weapon_fx_simplified=%d" % (1 if on else 0))


func set_target_fps(fps: int) -> void:
	target_fps = maxi(0, fps)
	Engine.max_fps = target_fps
	save_settings()
	_diag("settings", "fps_cap=%d nomodel=%d" % [target_fps, 1 if no_model_perf_mode else 0])


func apply_adaptive_fps() -> void:
	var mobile: bool = OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"
	var floor_fps: int = 30 if mobile else 60
	var refresh: float = DisplayServer.screen_get_refresh_rate()
	if refresh < 1.0:
		refresh = 60.0
	var adaptive: int = int(roundf(refresh * 0.75))
	target_fps = maxi(floor_fps, adaptive)
	Engine.max_fps = target_fps
	save_settings()
	_diag("settings", "fps_adaptive=%d refresh=%.1f floor=%d" % [target_fps, refresh, floor_fps])
	print("[PlayerSettings] adaptive fps=%d (refresh=%.1f ×0.75, floor=%d)" % [target_fps, refresh, floor_fps])


func set_camera_breathe_enabled(on: bool) -> void:
	camera_breathe_enabled = on
	save_settings()
	_diag("settings", "breathe=%d" % (1 if on else 0))


func set_health_bar_style(style: String) -> void:
	health_bar_style = "bars" if str(style) == "bars" else "ring"
	save_settings()
	var tree: SceneTree = get_tree()
	if tree:
		tree.call_group("match_root", "rebuild_all_ship_health_bars")


func set_health_bar_visible(on: bool) -> void:
	health_bar_visible = on
	save_settings()
	_diag("settings", "health_bar_visible=%d" % (1 if on else 0))
	var tree: SceneTree = get_tree()
	if tree:
		tree.call_group("match_root", "refresh_all_ship_health_bars")


func set_developer_debug_enabled(on: bool) -> void:
	developer_debug_enabled = on
	save_settings()


func set_player_citadel_soften(on: bool) -> void:
	player_citadel_soften = on
	save_settings()


func set_player_ai_double_economy(on: bool) -> void:
	player_ai_double_economy = on
	save_settings()


func set_enemy_layout_adjust(on: bool) -> void:
	enemy_layout_adjust = on
	save_settings()


func set_sfx_enabled(on: bool) -> void:
	sfx_enabled = on
	_apply_sfx_bus()
	save_settings()


func set_sfx_volume_pct(pct: float) -> void:
	sfx_volume_pct = clampf(pct, 0.0, 100.0)
	_apply_sfx_bus()
	save_settings()


func _apply_sfx_bus() -> void:
	SfxBus.ensure()
	var idx: int = AudioServer.get_bus_index(String(SFX_BUS))
	if idx < 0:
		return
	if not sfx_enabled or sfx_volume_pct <= 0.01:
		AudioServer.set_bus_mute(idx, true)
		return
	AudioServer.set_bus_mute(idx, false)
	AudioServer.set_bus_volume_db(idx, linear_to_db(sfx_volume_pct / 100.0))


func player_citadel_soften_active() -> bool:
	return developer_debug_enabled and player_citadel_soften


func player_ai_double_economy_active() -> bool:
	return developer_debug_enabled and player_ai_double_economy


func enemy_layout_adjust_active() -> bool:
	return developer_debug_enabled and enemy_layout_adjust
