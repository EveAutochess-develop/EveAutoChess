extends Node
## Tiny session bridge for menu → match mode.
## Shell Autoload (PCK cannot replace Autoload class). Keep in sync with eveautochess-dev.
## Local settings memory: user://player_settings.cfg (independent of match saves).

var pending_mode: String = "versus"
## Nullsec lobby → match handoff (assignments / seats / match_seed).
var pending_nullsec: Dictionary = {}
var shell_version: String = "1.0.0-shell"
var target_fps: int = 60
var no_model_perf_mode: bool = false
## Player override for camera breathe (options menu). true = on.
var camera_breathe_enabled: bool = true
## Ship float HP: "ring" (fans around tonnage) | "bars" (4 horizontal incl. cap).
var health_bar_style: String = "ring"
## Developer debug master switch (options → 开发者调试). Default off.
var developer_debug_enabled: bool = false
## Soften player citadel loss when developer debug is on. Default off.
var player_citadel_soften: bool = false
## Player gets AI's gold income ×mul buff (ai_gold_income_buff_mul). Default off.
var player_ai_double_economy: bool = false
## Pause+Prepare: allow dragging enemy ships for layout tweak. Default off.
var enemy_layout_adjust: bool = false
var resume_save: bool = false
## Empty → last_match.json; otherwise named slot path / id via MatchSave.
var resume_slot_id: String = ""
## One-shot payload from 读取存档 (e.g. 旗舰测试 inject). Prefer over re-reading disk.
## Cleared after match applies it. Never used by「继续上次对局」.
var resume_payload: Dictionary = {}
## Options「核实版本是否最新」→ Boot 才走指针仓/HF（默认启动不联网）。
var pending_content_verify: bool = false

## Local-only settings memory (graphics / audio / developer). Not a match save.
const SETTINGS_PATH: String = "user://player_settings.cfg"


func request_verify_content_version() -> void:
	## Shell Boot owns real verify; editor/dev may lack boot.tscn update UI.
	pending_content_verify = true
	var boot: String = "res://scenes/boot.tscn"
	if ResourceLoader.exists(boot):
		var err: Error = get_tree().change_scene_to_file(boot)
		if err != OK:
			push_error("[GameSession] boot scene failed: %s" % err)
			pending_content_verify = false
	else:
		push_warning("[GameSession] no boot.tscn — verify only works in eternal shell")
		pending_content_verify = false

func _ready() -> void:
	_load_settings()
	_apply_platform_render_profile()
	apply_adaptive_fps()

func _load_settings() -> void:
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	target_fps = TypedVariant.as_int(cf.get_value("graphics", "target_fps", target_fps), target_fps)
	no_model_perf_mode = TypedVariant.as_bool(cf.get_value("graphics", "no_model_perf_mode", false), false)
	camera_breathe_enabled = TypedVariant.as_bool(cf.get_value("graphics", "camera_breathe_enabled", true), true)
	health_bar_style = str(cf.get_value("graphics", "health_bar_style", health_bar_style))
	if health_bar_style != "bars":
		health_bar_style = "ring"
	developer_debug_enabled = TypedVariant.as_bool(cf.get_value("developer", "debug_enabled", false), false)
	player_citadel_soften = TypedVariant.as_bool(cf.get_value("developer", "player_citadel_soften", false), false)
	player_ai_double_economy = TypedVariant.as_bool(cf.get_value("developer", "player_ai_double_economy", false), false)
	enemy_layout_adjust = TypedVariant.as_bool(cf.get_value("developer", "enemy_layout_adjust", false), false)

func save_settings() -> void:
	var cf: ConfigFile = ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("graphics", "target_fps", target_fps)
	cf.set_value("graphics", "no_model_perf_mode", no_model_perf_mode)
	cf.set_value("graphics", "camera_breathe_enabled", camera_breathe_enabled)
	cf.set_value("graphics", "health_bar_style", health_bar_style)
	cf.set_value("developer", "debug_enabled", developer_debug_enabled)
	cf.set_value("developer", "player_citadel_soften", player_citadel_soften)
	cf.set_value("developer", "player_ai_double_economy", player_ai_double_economy)
	cf.set_value("developer", "enemy_layout_adjust", enemy_layout_adjust)
	cf.save(SETTINGS_PATH)

func set_no_model_perf_mode(on: bool) -> void:
	no_model_perf_mode = on
	save_settings()
	SessionDiagnostics.log("settings", "nomodel=%d fps_cap=%d" % [1 if on else 0, target_fps])
	var tree: SceneTree = get_tree()
	if tree:
		## UI_AND_SHELL: toggle must refresh existing units + asteroids (on and off).
		tree.call_group("match_root", "apply_no_model_perf_mode_changed")

func set_target_fps(fps: int) -> void:
	target_fps = maxi(0, fps)
	Engine.max_fps = target_fps
	save_settings()
	SessionDiagnostics.log("settings", "fps_cap=%d nomodel=%d" % [target_fps, 1 if no_model_perf_mode else 0])

## UI_AND_SHELL §3.0 — max(floor, refresh×0.75); PC floor 60, mobile floor 30.
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
	SessionDiagnostics.log("settings", "fps_adaptive=%d refresh=%.1f floor=%d" % [target_fps, refresh, floor_fps])
	print("[GameSession] adaptive fps=%d (refresh=%.1f ×0.75, floor=%d)" % [target_fps, refresh, floor_fps])

func set_camera_breathe_enabled(on: bool) -> void:
	camera_breathe_enabled = on
	save_settings()
	SessionDiagnostics.log("settings", "breathe=%d" % (1 if on else 0))

func set_health_bar_style(style: String) -> void:
	health_bar_style = "bars" if str(style) == "bars" else "ring"
	save_settings()

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

## Player failure citadel damage soften (dev debug + option both on).
func player_citadel_soften_active() -> bool:
	return developer_debug_enabled and player_citadel_soften

## Same combat-economy ×mul as AI (mining excluded). Requires developer debug on.
func player_ai_double_economy_active() -> bool:
	return developer_debug_enabled and player_ai_double_economy

## Prepare+paused: drag enemy ships only when developer debug + this flag are on.
func enemy_layout_adjust_active() -> bool:
	return developer_debug_enabled and enemy_layout_adjust

func _apply_platform_render_profile() -> void:
	## PC: 1.5 + MSAA4 (was 3.0 + 8×). Mobile: 1.0 / MSAA off. UI_AND_SHELL §3.0.
	var mobile: bool = OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"
	var root: Window = get_tree().root
	if root == null:
		return
	if mobile:
		root.scaling_3d_scale = 1.0
		root.msaa_3d = Viewport.MSAA_DISABLED
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		print("[GameSession] mobile render profile: scaling_3d=1.0 msaa=off")
		return
	var scale: float = 1.5
	var data_store: Node = get_node_or_null(^"/root/DataStore")
	var visual: Dictionary = TypedVariant.as_dict(data_store.get("visual")) if data_store else {}
	if not visual.is_empty():
		var key: String = "editor_scaling_3d" if OS.has_feature("editor") else "desktop_scaling_3d"
		if visual.has(key):
			scale = TypedVariant.as_float(visual.get(key), 0.0)
	scale = clampf(scale, 1.0, 4.0)
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = scale
	root.msaa_3d = Viewport.MSAA_4X
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	root.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var sz: Vector2i = DisplayServer.window_get_size()
		if sz.x < 1600 or sz.y < 900:
			DisplayServer.window_set_size(Vector2i(1920, 1080))
	print("[GameSession] desktop render profile: scaling_3d=%.1f msaa=4x editor=%s" % [
		scale, OS.has_feature("editor")
	])
