extends Node
## Tiny session bridge for menu → match mode.

var pending_mode: String = "versus"
var shell_version: String = "1.0.0-shell"
var target_fps: int = 60
var no_model_perf_mode: bool = false
## Player override for camera breathe (options menu). true = on.
var camera_breathe_enabled: bool = true
var resume_save: bool = false
## Empty → last_match.json; otherwise named slot path / id via MatchSave.
var resume_slot_id: String = ""

const SETTINGS_PATH := "user://player_settings.cfg"

func _ready() -> void:
	_load_settings()
	_apply_platform_render_profile()

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	target_fps = int(cf.get_value("graphics", "target_fps", target_fps))
	no_model_perf_mode = bool(cf.get_value("graphics", "no_model_perf_mode", false))
	camera_breathe_enabled = bool(cf.get_value("graphics", "camera_breathe_enabled", true))

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("graphics", "target_fps", target_fps)
	cf.set_value("graphics", "no_model_perf_mode", no_model_perf_mode)
	cf.set_value("graphics", "camera_breathe_enabled", camera_breathe_enabled)
	cf.save(SETTINGS_PATH)

func set_no_model_perf_mode(on: bool) -> void:
	no_model_perf_mode = on
	save_settings()

func set_camera_breathe_enabled(on: bool) -> void:
	camera_breathe_enabled = on
	save_settings()

func _apply_platform_render_profile() -> void:
	## PC: high 3D resolve + MSAA8. Mobile: 1.0 / MSAA off (4× greyscreens phones).
	var mobile := OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"
	var root := get_tree().root
	if root == null:
		return
	if mobile:
		root.scaling_3d_scale = 1.0
		root.msaa_3d = Viewport.MSAA_DISABLED
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		print("[GameSession] mobile render profile: scaling_3d=1.0 msaa=off")
		return
	# Editor preview: lighter 3D resolve so first frame isn't a multi-second GPU hitch.
	var scale := 1.5 if OS.has_feature("editor") else 3.0
	if DataStore and DataStore.visual is Dictionary:
		var key := "editor_scaling_3d" if OS.has_feature("editor") else "desktop_scaling_3d"
		if DataStore.visual.has(key):
			scale = float(DataStore.visual[key])
	scale = clampf(scale, 1.0, 4.0)
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = scale
	root.msaa_3d = Viewport.MSAA_4X if OS.has_feature("editor") else Viewport.MSAA_8X
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	root.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var sz := DisplayServer.window_get_size()
		if sz.x < 1600 or sz.y < 900:
			DisplayServer.window_set_size(Vector2i(1920, 1080))
	print("[GameSession] desktop render profile: scaling_3d=%.1f msaa=%s editor=%s" % [
		scale, "4x" if OS.has_feature("editor") else "8x", OS.has_feature("editor")
	])
