extends Node3D
class_name MatchRoot
## Wires bricks; group name match_root for callbacks.

@onready var world: Node3D = $World
@onready var camera: Camera3D = $Camera3D
@onready var hud: CanvasLayer = $HUD

var match_ctrl: MatchController
var board: BoardController
var shop: ShopController
var combat: CombatResolver
var firing_fx = null
var ai: AiController
var pointer: PointerInput

var _info_ship: ShipUnit = null
var _suppress_headup_for_preview: bool = false
var _long_press_t: float = 0.0
var _long_press_slot: int = -1
var _dragging_sell_ui: bool = false
var _cam_base_pos: Vector3 = Vector3.ZERO
var _cam_default_pitch_deg: float = -55.0
var _cam_base_pitch_deg: float = -55.0
var _cam_base_yaw_deg: float = 0.0
var _cam_frame_offset: Vector3 = Vector3.ZERO
var _cam_frame_target: Vector3 = Vector3.ZERO
var _cam_headup_offset_deg: float = 0.0
var _cam_headup_phase: int = 0
var _cam_headup_t: float = 0.0
## Smooth blend toward a default view (shop / stage); false = settled.
var _cam_view_blend_active: bool = false
var _cam_view_blend_pos: Vector3 = Vector3.ZERO
var _cam_view_blend_pitch_deg: float = 0.0
var _cam_view_blend_yaw_deg: float = 0.0
var _cam_view_blend_fov: float = 50.0
## Camera mode: false = default (framing/breathe/headup); true = free view.
var _camera_free: bool = false
var _cam_look_dragging: bool = false
## Pose snapshot taken when expanding shop; restored when collapsing.
var _cam_pose_before_shop: Dictionary = {}
var _cam_pose_before_shop_valid: bool = false
## Mobile free-view orbit drag.
var _cam_orbit_touch_index: int = -1
var _cam_orbit_dragging: bool = false
## Default cam: hide board slot markers only after settling on first default view.
var _pending_hide_slot_markers: bool = false
var _collapse_left: bool = false
var _collapse_right: bool = false
var _collapse_bottom: bool = false
var _last_match_stage: int = MatchController.Stage.PREPARE
var _battle_log_lines: Array = []
const _BATTLE_LOG_MAX := 40
var _citadel_hp_bar: Node3D = null
const _CITADEL_BAR_SCRIPT := preload("res://scripts/ship/citadel_health_bar.gd")
const _BgMusic := preload("res://scripts/audio/bg_music.gd")
const _CAM_MOVE_SPEED := 8.0
var _exp_hold_active: bool = false
var _exp_hold_t: float = 0.0
var _exp_hold_spent_all: bool = false
const _EXP_HOLD_S := 10.0
const _CAM_PITCH_SPEED := 35.0
const _CAM_YAW_SPEED := 45.0
const _SHOP_META := "Shop/ShopCol/ShopContent/MetaRow"
const _SHOP_LEFT := "Shop/ShopCol/ShopContent/MetaRow/LeftCtrl"
const _SHOP_MID := "Shop/ShopCol/ShopContent/MetaRow/MetaMid"
const _SHOP_INNER := "Shop/ShopCol/ShopContent/ShopInner"
const _SHOP_SLOTS := "Shop/ShopCol/ShopContent/ShopInner/ShopSlots"
const _INFO_PANEL := "RightCol/RightInner/RightContent/InfoPanel"
const _BONUS := "LeftCol/LeftInner/LeftContent/BonusContainer"
const _ROUND := "RoundBar/RoundInner"

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	add_to_group("match_root")
	process_mode = Node.PROCESS_MODE_ALWAYS
	## Pick up balance/visual JSON edits without restarting the editor.
	DataStore.reload_all()
	_BgMusic.instance()
	match_ctrl = MatchController.new()
	board = BoardController.new()
	shop = ShopController.new()
	combat = CombatResolver.new()
	firing_fx = preload("res://scripts/combat/firing_fx.gd").new()
	ai = AiController.new()
	pointer = PointerInput.new()
	add_child(match_ctrl)
	add_child(board)
	add_child(shop)
	add_child(combat)
	add_child(firing_fx)
	add_child(ai)
	add_child(pointer)
	match_ctrl.process_mode = Node.PROCESS_MODE_PAUSABLE
	board.process_mode = Node.PROCESS_MODE_ALWAYS
	shop.process_mode = Node.PROCESS_MODE_PAUSABLE
	combat.process_mode = Node.PROCESS_MODE_PAUSABLE
	firing_fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	ai.process_mode = Node.PROCESS_MODE_PAUSABLE
	pointer.process_mode = Node.PROCESS_MODE_ALWAYS
	board.setup(world)
	_ensure_ground()
	shop.bind(match_ctrl, board)
	firing_fx.setup(world)
	combat.bind(board, firing_fx)
	ai.bind(match_ctrl, board)
	match_ctrl.bind(board, shop, combat, ai)
	_setup_camera()
	_build_hud()
	pointer.setup(self, camera, board)
	pointer.drag_begin.connect(_on_drag_begin)
	pointer.drag_move.connect(_on_drag_move)
	pointer.drag_end.connect(_on_drag_end)
	pointer.tap_ship.connect(_on_tap_ship)
	pointer.hover_ship.connect(_on_hover_ship)
	match_ctrl.hud_refresh.connect(_refresh_hud)
	match_ctrl.notice.connect(show_notice)
	match_ctrl.match_over.connect(_on_match_over)
	match_ctrl.stage_changed.connect(_on_stage_changed_ui)
	shop.shop_changed.connect(_refresh_shop_ui)
	var diag := SessionDiagnostics.instance()
	if diag and diag.has_method("bind_match"):
		diag.bind_match(self)
	var mode := GameSession.pending_mode
	_spawn_map_env(mode)
	var resume_data: Dictionary = {}
	if GameSession.resume_save:
		var slot_id := str(GameSession.resume_slot_id)
		if slot_id != "":
			resume_data = MatchSave.load_slot_dict(slot_id)
		if resume_data.is_empty():
			resume_data = MatchSave.load_dict()
	match_ctrl.start_match(mode)
	if not resume_data.is_empty():
		_apply_match_save_dict(resume_data)
		GameSession.resume_save = false
		GameSession.resume_slot_id = ""
		MatchSave.save_from_match(match_ctrl, board, ai)
	_refresh_hud()
	_refresh_shop_ui()

func _ensure_ground() -> void:
	var g := get_node_or_null("Ground") as MeshInstance3D
	if g == null:
		return
	# Invisible hit plane only — original Endless has no visible floor pad
	if g.mesh == null:
		var plane := PlaneMesh.new()
		plane.size = Vector2(48, 48)
		g.mesh = plane
	g.visible = false
	g.position = Vector3(0, -0.05, 0)

func _spawn_map_env(mode: String) -> void:
	var env := MapEnv.new()
	env.name = "MapEnv"
	world.add_child(env)
	env.build(mode)
	_attach_citadel_hp_bar(env)
	_ensure_sky()

func _attach_citadel_hp_bar(env: MapEnv) -> void:
	if env == null or env.player_citadel == null:
		return
	_citadel_hp_bar = _CITADEL_BAR_SCRIPT.new() as Node3D
	_citadel_hp_bar.name = "CitadelHealthBar"
	env.player_citadel.add_child(_citadel_hp_bar)
	_citadel_hp_bar.call("setup", float(DataStore.visual.get("citadel_health_bar_y", 9.5)))
	_refresh_citadel_bar()

func _refresh_citadel_bar() -> void:
	if _citadel_hp_bar == null or not is_instance_valid(_citadel_hp_bar):
		return
	_citadel_hp_bar.call("refresh", float(match_ctrl.player_hp), float(match_ctrl.player_max_hp))

func _ensure_sky() -> void:
	if get_node_or_null("WorldEnvironment"):
		return
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.1, 0.14)
	var sky_tex := UiAssets.tex("res://assets/skyboxes/amarr.jpeg")
	if sky_tex == null:
		sky_tex = UiAssets.tex("res://assets/skyboxes/gallente.jpeg")
	if sky_tex:
		environment.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		var mat := PanoramaSkyMaterial.new()
		mat.panorama = sky_tex
		mat.energy_multiplier = 1.0
		sky.sky_material = mat
		environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.74, 0.76, 0.80)
	environment.ambient_light_energy = 0.70
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.86
	environment.tonemap_white = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.97
	environment.adjustment_contrast = 1.03
	environment.adjustment_saturation = 1.0
	environment.glow_enabled = false
	environment.ssao_enabled = false
	ShipLook.apply_match_environment(environment)
	we.environment = environment
	add_child(we)
	_ensure_board_lights()

func _ensure_board_lights() -> void:
	## Off-frustum lights — driven by visual.json ship_look (unity-standard default).
	if get_node_or_null("KeyLightOffscreen") == null:
		var key := DirectionalLight3D.new()
		key.name = "KeyLightOffscreen"
		key.light_energy = 1.0
		key.light_color = Color(1.0, 1.0, 1.0)
		key.shadow_enabled = true
		key.shadow_opacity = 0.55
		key.rotation_degrees = Vector3(-57.3, 107.7, 0.0)
		add_child(key)
	if get_node_or_null("RimLightOffscreen") == null:
		var rim := DirectionalLight3D.new()
		rim.name = "RimLightOffscreen"
		rim.light_energy = 0.0
		rim.light_color = Color(0.65, 0.8, 1.0)
		rim.shadow_enabled = false
		rim.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
		add_child(rim)
	if get_node_or_null("FillLight") == null:
		var fill := OmniLight3D.new()
		fill.name = "FillLight"
		fill.light_energy = 0.0
		fill.omni_range = 85.0
		fill.position = Vector3(0, 32, 10)
		add_child(fill)
	if get_node_or_null("FillLightAI") == null:
		var fill_ai := OmniLight3D.new()
		fill_ai.name = "FillLightAI"
		fill_ai.light_energy = 0.0
		fill_ai.light_color = Color(0.88, 0.92, 1.0)
		fill_ai.omni_range = 60.0
		fill_ai.position = Vector3(-16.0, 24.0, -18.0)
		add_child(fill_ai)
	if get_node_or_null("FillLightPlayer") == null:
		var fill_p := OmniLight3D.new()
		fill_p.name = "FillLightPlayer"
		fill_p.light_energy = 0.0
		fill_p.light_color = Color(1.0, 0.96, 0.9)
		fill_p.omni_range = 60.0
		fill_p.position = Vector3(16.0, 24.0, 18.0)
		add_child(fill_p)
	var scene_key := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if scene_key:
		scene_key.light_energy = 0.0
		scene_key.shadow_opacity = 0.4
	ShipLook.apply_match_lights(self)

func _setup_camera() -> void:
	## Two default camera views:
	## - primary: battle / shop collapsed baseline
	## - secondary: prepare + shop expanded
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	var start := _camera_secondary_view() if not _collapse_bottom else _camera_primary_view()
	_cam_base_pos = start.get("pos", Vector3(-2.0, 21.464, 18.067))
	_cam_base_pitch_deg = float(start.get("pitch_deg", -57.0))
	_cam_default_pitch_deg = float(_camera_primary_view().get("pitch_deg", _cam_base_pitch_deg))
	_cam_base_yaw_deg = float(start.get("yaw_deg", 0.0))
	camera.fov = float(start.get("fov", 47.0))
	camera.position = _cam_base_pos
	camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)

func _camera_primary_view() -> Dictionary:
	var v: Dictionary = DataStore.visual
	return {
		"pos": Vector3(
			float(v.get("camera_x", 2.00856733322144)),
			float(v.get("camera_height", 35.0967063903809)),
			float(v.get("camera_distance", 28.4933738708496))
		),
		"pitch_deg": -float(v.get("camera_angle_deg", 55.6669960021973)),
		"yaw_deg": float(v.get("camera_yaw_deg", 180.0)) - 180.0,
		"fov": float(v.get("camera_fov", 50.0))
	}

func _camera_secondary_view() -> Dictionary:
	var v: Dictionary = DataStore.visual
	return {
		"pos": Vector3(
			float(v.get("camera_second_x", 1.82857227325439)),
			float(v.get("camera_second_height", 27.0970573425293)),
			float(v.get("camera_second_distance", 33.6982917785645))
		),
		"pitch_deg": -float(v.get("camera_second_angle_deg", 55.6669960021973)),
		"yaw_deg": float(v.get("camera_second_yaw_deg", float(v.get("camera_yaw_deg", 180.0)))) - 180.0,
		"fov": float(v.get("camera_second_fov", float(v.get("camera_fov", 50.0))))
	}

func _camera_active_view() -> Dictionary:
	if match_ctrl and match_ctrl.stage == MatchController.Stage.BATTLE:
		return _camera_primary_view()
	return _camera_primary_view() if _collapse_bottom else _camera_secondary_view()

func _process(delta: float) -> void:
	if _camera_free:
		_update_camera_free(delta)
	else:
		_update_camera_headup(delta)
		_update_camera_view_blend(delta)
		_update_camera_framing(delta)
	_try_hide_slot_markers_when_view1_settled()
	## Breathe applies in both default and free view (options toggle only).
	_update_camera_breathe()
	_tick_exp_hold(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V and not _gui_wants_text_input() and not UiLayout.is_mobile():
			_toggle_camera_mode()
			get_viewport().set_input_as_handled()
			return
	if not _camera_free:
		return
	if UiLayout.is_mobile():
		_handle_mobile_orbit_input(event)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_cam_look_dragging = mb.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _cam_look_dragging:
		var mm := event as InputEventMouseMotion
		var sens := float(DataStore.visual.get("camera_free_look_sens", 0.18))
		_cam_base_yaw_deg -= mm.relative.x * sens
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg - mm.relative.y * sens, -89.0, 89.0)
		camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
		get_viewport().set_input_as_handled()

func _handle_mobile_orbit_input(event: InputEvent) -> void:
	## Single-finger drag orbits around board center; ignore 2nd finger / ship drags.
	if pointer != null and pointer.has_method("is_pointer_dragging") and pointer.is_pointer_dragging():
		_cam_orbit_dragging = false
		_cam_orbit_touch_index = -1
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.index > 0:
			return
		if st.pressed:
			if _ui_blocks_camera_touch(st.position):
				return
			if _screen_hits_ship(st.position):
				return
			_cam_orbit_touch_index = st.index
			_cam_orbit_dragging = true
			get_viewport().set_input_as_handled()
		elif st.index == _cam_orbit_touch_index:
			_cam_orbit_dragging = false
			_cam_orbit_touch_index = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _cam_orbit_dragging or sd.index != _cam_orbit_touch_index:
			return
		var sens := float(DataStore.visual.get("camera_free_look_sens", 0.18))
		_orbit_camera_around_board(-sd.relative.x * sens, -sd.relative.y * sens)
		get_viewport().set_input_as_handled()

func _ui_blocks_camera_touch(screen: Vector2) -> bool:
	if pointer != null and pointer.has_method("ui_blocks_screen"):
		return bool(pointer.ui_blocks_screen(screen))
	var hover := get_viewport().gui_get_hovered_control() if get_viewport() else null
	return hover != null

func _screen_hits_ship(screen: Vector2) -> bool:
	if board == null or camera == null:
		return false
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	return board.pick_ship_at(origin, dir) != null

func _orbit_camera_around_board(yaw_delta_deg: float, pitch_delta_deg: float) -> void:
	var pivot := Vector3.ZERO
	var offset := _cam_base_pos - pivot
	var dist := maxf(offset.length(), 2.0)
	var yaw := atan2(offset.x, offset.z) + deg_to_rad(yaw_delta_deg)
	var pitch := asin(clampf(offset.y / dist, -0.999, 0.999)) + deg_to_rad(pitch_delta_deg)
	pitch = clampf(pitch, deg_to_rad(-85.0), deg_to_rad(85.0))
	var cp := cos(pitch)
	_cam_base_pos = pivot + Vector3(sin(yaw) * cp, sin(pitch), cos(yaw) * cp) * dist
	camera.position = _cam_base_pos
	camera.look_at(pivot, Vector3.UP)
	_cam_base_pitch_deg = camera.rotation_degrees.x
	_cam_base_yaw_deg = camera.rotation_degrees.y

func _gui_wants_text_input() -> bool:
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	return focus is LineEdit or focus is TextEdit

func _on_camera_mode_pressed() -> void:
	_toggle_camera_mode()

func _toggle_camera_mode() -> void:
	_set_camera_free(not _camera_free)

func _set_camera_free(enabled: bool) -> void:
	_camera_free = enabled
	_cam_look_dragging = false
	_cam_orbit_dragging = false
	_cam_orbit_touch_index = -1
	_cam_view_blend_active = false
	if _camera_free:
		## Adopt current rendered pose as free-view base (drop breathe offset).
		_cam_base_pos = camera.position
		_cam_base_pitch_deg = camera.rotation_degrees.x
		_cam_base_yaw_deg = camera.rotation_degrees.y
		_cam_headup_phase = 0
		_cam_headup_t = 0.0
		_cam_headup_offset_deg = 0.0
		camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
		## Free view: do not delay marker hide for camera settle.
		if _pending_hide_slot_markers:
			_hide_slot_markers_now()
		if UiLayout.is_mobile():
			show_notice("自由视角 · 拖动屏幕绕棋盘旋转 · 点按钮切回")
		else:
			show_notice("自由视角 · WASD移动 QE升降 · 中键环视 · V切回")
	else:
		_snap_camera_to_active_default()
		show_notice("默认视角")
	_refresh_camera_mode_btn()

func _snap_camera_to_active_default() -> void:
	var view: Dictionary
	if match_ctrl and match_ctrl.stage == MatchController.Stage.BATTLE:
		view = _camera_primary_view()
	elif _collapse_bottom:
		view = _camera_primary_view()
	else:
		view = _camera_secondary_view()
	_apply_camera_view_dict(view, true)

func _apply_camera_view_dict(view: Dictionary, smooth: bool = true) -> void:
	## Free view owns its pose; stage / shop / framing must not rewrite it.
	if _camera_free:
		return
	_cam_default_pitch_deg = float(_camera_primary_view().get("pitch_deg", _cam_default_pitch_deg))
	_cam_headup_phase = 0
	_cam_headup_t = 0.0
	_cam_headup_offset_deg = 0.0
	var pos: Vector3 = view.get("pos", _cam_base_pos)
	var pitch := float(view.get("pitch_deg", _cam_base_pitch_deg))
	var yaw := float(view.get("yaw_deg", _cam_base_yaw_deg))
	var fov := float(view.get("fov", camera.fov))
	if not smooth:
		_cam_view_blend_active = false
		_cam_base_pos = pos
		_cam_base_pitch_deg = pitch
		_cam_base_yaw_deg = yaw
		camera.fov = fov
		camera.position = _cam_base_pos
		camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
		return
	_cam_view_blend_active = true
	_cam_view_blend_pos = pos
	_cam_view_blend_pitch_deg = pitch
	_cam_view_blend_yaw_deg = yaw
	_cam_view_blend_fov = fov

func _capture_cam_pose() -> Dictionary:
	return {
		"pos": _cam_base_pos,
		"pitch_deg": _cam_base_pitch_deg,
		"yaw_deg": _cam_base_yaw_deg,
		"fov": camera.fov,
		"free": _camera_free,
	}

func _restore_cam_pose(pose: Dictionary) -> void:
	_cam_view_blend_active = false
	_cam_base_pos = pose.get("pos", _cam_base_pos)
	_cam_base_pitch_deg = float(pose.get("pitch_deg", _cam_base_pitch_deg))
	_cam_base_yaw_deg = float(pose.get("yaw_deg", _cam_base_yaw_deg))
	camera.fov = float(pose.get("fov", camera.fov))
	_cam_headup_phase = 0
	_cam_headup_t = 0.0
	_cam_headup_offset_deg = 0.0
	camera.position = _cam_base_pos
	camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)

func _on_shop_expanded_camera() -> void:
	if _camera_free:
		return
	_cam_pose_before_shop = _capture_cam_pose()
	_cam_pose_before_shop_valid = true
	_apply_camera_view_dict(_camera_secondary_view())

func _on_shop_collapsed_camera() -> void:
	if _camera_free:
		_cam_pose_before_shop_valid = false
		_cam_pose_before_shop.clear()
		return
	_cam_pose_before_shop_valid = false
	_cam_pose_before_shop.clear()
	_apply_camera_view_dict(_camera_primary_view())

func _refresh_camera_mode_btn() -> void:
	var btn := hud.get_node_or_null("Root/TopRight/CamModeBtn") as Button
	if btn == null:
		return
	btn.text = "默认视角" if _camera_free else "自由视角"
	if UiLayout.is_mobile():
		btn.tooltip_text = "当前：%s" % ("自由（触控绕心）" if _camera_free else "默认")
	else:
		btn.tooltip_text = "快捷键 V · 当前：%s" % ("自由" if _camera_free else "默认")

func _update_camera_free(delta: float) -> void:
	if UiLayout.is_mobile():
		## Mobile free view is touch-orbit only; keep pose stable here.
		camera.position = _cam_base_pos
		camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
		return
	## PC free fly: move relative to look; no framing pull-back.
	var v: Dictionary = DataStore.visual
	var speed := float(v.get("camera_free_move_speed", _CAM_MOVE_SPEED))
	var basis := camera.global_transform.basis
	var forward := -basis.z
	var right := basis.x
	var up := Vector3.UP
	var move := Vector3.ZERO
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
	var pitch_delta := 0.0
	if Input.is_physical_key_pressed(KEY_R):
		pitch_delta += _CAM_PITCH_SPEED * delta
	if Input.is_physical_key_pressed(KEY_F):
		pitch_delta -= _CAM_PITCH_SPEED * delta
	if pitch_delta != 0.0:
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg + pitch_delta, -89.0, 89.0)
	var yaw_delta := 0.0
	if Input.is_physical_key_pressed(KEY_T):
		yaw_delta -= _CAM_YAW_SPEED * delta
	if Input.is_physical_key_pressed(KEY_G):
		yaw_delta += _CAM_YAW_SPEED * delta
	if yaw_delta != 0.0:
		_cam_base_yaw_deg += yaw_delta
	camera.position = _cam_base_pos
	camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)

func _camera_pitch_now() -> float:
	return _cam_base_pitch_deg + _cam_headup_offset_deg

func _update_camera_headup(delta: float) -> void:
	if _camera_free:
		_cam_headup_offset_deg = 0.0
		return
	if _cam_headup_phase == 0:
		_cam_headup_offset_deg = 0.0
		return
	var v: Dictionary = DataStore.visual
	var rise_s := maxf(0.01, float(v.get("camera_headup_time_s", 0.18)))
	var recover_s := maxf(0.01, float(v.get("camera_headup_recover_s", 0.32)))
	var target_deg := maxf(0.0, float(v.get("camera_headup_pitch_deg", 6.0)))
	_cam_headup_t += delta
	if _cam_headup_phase == 1:
		var up_k := clampf(_cam_headup_t / rise_s, 0.0, 1.0)
		_cam_headup_offset_deg = lerpf(0.0, target_deg, ease(up_k, -2.0))
		if up_k >= 1.0:
			_cam_base_pitch_deg = clampf(_cam_base_pitch_deg + target_deg, -89.0, -5.0)
			_cam_headup_phase = 0
			_cam_headup_t = 0.0
			_cam_headup_offset_deg = 0.0
	else:
		var down_k := clampf(_cam_headup_t / recover_s, 0.0, 1.0)
		_cam_headup_offset_deg = lerpf(target_deg, 0.0, ease(down_k, 2.0))
		if down_k >= 1.0:
			_cam_headup_phase = 0
			_cam_headup_t = 0.0
			_cam_headup_offset_deg = 0.0

func _trigger_camera_headup(reason: String) -> void:
	if _camera_free:
		return
	var v: Dictionary = DataStore.visual
	if not bool(v.get("camera_headup_enabled", false)):
		return
	if _suppress_headup_for_preview:
		return
	var trigger := str(v.get("camera_headup_trigger", "stage_change"))
	if trigger != "all" and trigger != reason:
		return
	_cam_headup_phase = 1
	_cam_headup_t = 0.0
	_cam_headup_offset_deg = 0.0

func _update_camera_view_blend(delta: float) -> void:
	if not _cam_view_blend_active or _camera_free:
		return
	## Battle framing owns continuous lock; drop event blend.
	if match_ctrl != null and match_ctrl.stage == MatchController.Stage.BATTLE:
		_cam_view_blend_active = false
		return
	var framing: Dictionary = DataStore.visual.get("camera_framing", {})
	var spd := float(framing.get("lerp_speed", 4.0))
	var k := clampf(spd * delta, 0.0, 1.0)
	_cam_base_pos = _cam_base_pos.lerp(_cam_view_blend_pos, k)
	_cam_base_pitch_deg = lerpf(_cam_base_pitch_deg, _cam_view_blend_pitch_deg, k)
	_cam_base_yaw_deg = lerpf(_cam_base_yaw_deg, _cam_view_blend_yaw_deg, k)
	camera.fov = lerpf(camera.fov, _cam_view_blend_fov, k)
	var pos_done := _cam_base_pos.distance_to(_cam_view_blend_pos) < 0.03
	var ang_done := absf(_cam_base_pitch_deg - _cam_view_blend_pitch_deg) < 0.08 \
		and absf(_cam_base_yaw_deg - _cam_view_blend_yaw_deg) < 0.08
	var fov_done := absf(camera.fov - _cam_view_blend_fov) < 0.05
	if pos_done and ang_done and fov_done:
		_cam_base_pos = _cam_view_blend_pos
		_cam_base_pitch_deg = _cam_view_blend_pitch_deg
		_cam_base_yaw_deg = _cam_view_blend_yaw_deg
		camera.fov = _cam_view_blend_fov
		_cam_view_blend_active = false

func _update_camera_framing(delta: float) -> void:
	if _camera_free:
		return
	## Prepare: shop open/close events own the pose. Only Battle continuously locks view 1.
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.BATTLE:
		return
	_cam_view_blend_active = false
	var framing: Dictionary = DataStore.visual.get("camera_framing", {})
	var spd := float(framing.get("lerp_speed", 4.0))
	var view := _camera_primary_view()
	var k := clampf(spd * delta, 0.0, 1.0)
	_cam_base_pos = _cam_base_pos.lerp(view.get("pos", _cam_base_pos), k)
	_cam_base_pitch_deg = lerpf(_cam_base_pitch_deg, float(view.get("pitch_deg", _cam_base_pitch_deg)), k)
	_cam_base_yaw_deg = lerpf(_cam_base_yaw_deg, float(view.get("yaw_deg", _cam_base_yaw_deg)), k)
	camera.fov = lerpf(camera.fov, float(view.get("fov", camera.fov)), k)
	_cam_default_pitch_deg = float(view.get("pitch_deg", _cam_default_pitch_deg))
	_cam_frame_target = Vector3.ZERO
	_cam_frame_offset = Vector3.ZERO
	camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)

func _camera_near_primary_view() -> bool:
	var view := _camera_primary_view()
	var pos: Vector3 = view.get("pos", _cam_base_pos)
	if _cam_base_pos.distance_to(pos) > 0.08:
		return false
	if absf(_cam_base_pitch_deg - float(view.get("pitch_deg", _cam_base_pitch_deg))) > 0.15:
		return false
	if absf(_cam_base_yaw_deg - float(view.get("yaw_deg", _cam_base_yaw_deg))) > 0.15:
		return false
	if absf(camera.fov - float(view.get("fov", camera.fov))) > 0.1:
		return false
	return true

func _hide_slot_markers_now() -> void:
	_pending_hide_slot_markers = false
	## Battle: hide Field hexes only; Hangar blue frames stay.
	if board and board.has_method("set_field_markers_visible"):
		board.set_field_markers_visible(false)
	elif board and board.has_method("set_slot_markers_visible"):
		board.set_slot_markers_visible(false)

func _show_slot_markers_now() -> void:
	_pending_hide_slot_markers = false
	if board and board.has_method("set_field_markers_visible"):
		board.set_field_markers_visible(true)
		if board.has_method("set_hangar_markers_visible"):
			board.set_hangar_markers_visible(true)
	elif board and board.has_method("set_slot_markers_visible"):
		board.set_slot_markers_visible(true)

func _try_hide_slot_markers_when_view1_settled() -> void:
	if not _pending_hide_slot_markers:
		return
	if _camera_free:
		_hide_slot_markers_now()
		return
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.BATTLE:
		_pending_hide_slot_markers = false
		return
	if _camera_near_primary_view():
		_hide_slot_markers_now()

func _update_camera_breathe() -> void:
	var v: Dictionary = DataStore.visual
	## Free view: offset from pilot base only (no framing). Default: base + frame.
	var base := _cam_base_pos if _camera_free else (_cam_base_pos + _cam_frame_offset)
	var amp := float(v.get("camera_breathe_amp", 0.35))
	## Player setting overrides content; options menu is the only off switch.
	var breathe_on := true
	if GameSession != null:
		breathe_on = GameSession.camera_breathe_enabled
	elif not bool(v.get("camera_breathe_enabled", true)):
		breathe_on = false
	if not breathe_on:
		camera.position = base
		camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)
		return
	var period := maxf(0.5, float(v.get("camera_breathe_period_s", 12.0)))
	var th := Time.get_ticks_msec() * 0.001 * TAU / period
	var s := sin(th)
	var c := cos(th)
	# Diagonal figure-8 on XZ only (no Y) so pitch feel stays stable.
	var local := Vector3(s, 0.0, s * c) * amp
	var half := 0.70710678
	var offset := Vector3(
		local.x * half - local.z * half,
		0.0,
		local.x * half + local.z * half
	)
	camera.position = base + offset
	camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)
func _build_hud() -> void:
	_ensure_reserve_grid()
	_apply_adaptive_hud_layout()
	_style_hud_chrome()
	_wire_shop_chrome()
	_apply_shop_interactable()
	var root := hud.get_node_or_null("Root") as Control
	if root and not root.resized.is_connected(_on_hud_resized):
		root.resized.connect(_on_hud_resized)
	var pause := hud.get_node_or_null("Root/TopRight/PauseBtn") as Button
	if pause:
		pause.process_mode = Node.PROCESS_MODE_ALWAYS
	var cam_btn := hud.get_node_or_null("Root/TopRight/CamModeBtn") as Button
	if cam_btn:
		cam_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_camera_mode_btn()

func _on_hud_resized() -> void:
	_apply_adaptive_hud_layout()
	_style_hud_chrome()
	_wire_shop_chrome()
	_apply_shop_interactable()

func _ensure_reserve_grid() -> void:
	var grid := hud.get_node_or_null("Root/LeftCol/LeftInner/LeftContent/ReserveGrid") as GridContainer
	if grid == null or grid.get_child_count() > 0:
		return
	for i in range(8):
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(18, 18)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.15, 0.45, 0.22, 0.55)
		sb.set_corner_radius_all(2)
		cell.add_theme_stylebox_override("panel", sb)
		grid.add_child(cell)

func _apply_adaptive_hud_layout() -> void:
	var root := hud.get_node_or_null("Root") as Control
	if root == null:
		return
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top_h := UiLayout.top_bar_height_frac()
	var left_w: float = UiLayout.collapse_strip_frac() if _collapse_left else UiLayout.left_col_width_frac()
	var right_w: float = UiLayout.collapse_strip_frac() if _collapse_right else UiLayout.right_col_width_frac()
	var bottom_h: float = UiLayout.collapse_strip_frac() if _collapse_bottom else UiLayout.bottom_shop_height_frac()
	var round_bar := root.get_node_or_null("RoundBar") as Control
	if round_bar:
		UiLayout.set_rect_frac(round_bar, 0.22, 0.008, 0.78, top_h)
	var top_r := root.get_node_or_null("TopRight") as Control
	if top_r:
		UiLayout.set_rect_frac(top_r, 0.78, 0.008, 0.992, top_h)
	var left_col := root.get_node_or_null("LeftCol") as Control
	if left_col:
		UiLayout.set_rect_frac(left_col, 0.006, top_h + 0.01, 0.006 + left_w, 1.0 - bottom_h - 0.02)
	var right_col := root.get_node_or_null("RightCol") as Control
	if right_col:
		UiLayout.set_rect_frac(right_col, 1.0 - 0.006 - right_w, top_h + 0.01, 0.994, 1.0 - bottom_h - 0.02)
	var shop_panel := root.get_node_or_null("Shop") as Control
	if shop_panel:
		UiLayout.set_bottom_strip(shop_panel, bottom_h, 0.01, 0.01, 0.008)
	var left_content := root.get_node_or_null("LeftCol/LeftInner/LeftContent") as Control
	if left_content:
		left_content.visible = not _collapse_left
	var right_content := root.get_node_or_null("RightCol/RightInner/RightContent") as Control
	if right_content:
		right_content.visible = not _collapse_right
	var shop_content := root.get_node_or_null("Shop/ShopCol/ShopContent") as Control
	if shop_content:
		shop_content.visible = not _collapse_bottom
	var cl := root.get_node_or_null("LeftCol/LeftInner/CollapseLeftBtn") as Button
	if cl:
		cl.text = "▶" if _collapse_left else "◀"
	var cr := root.get_node_or_null("RightCol/RightInner/CollapseRightBtn") as Button
	if cr:
		cr.text = "◀" if _collapse_right else "▶"
	var cb := root.get_node_or_null("Shop/ShopCol/CollapseBottomBtn") as Button
	if cb:
		cb.text = "▲" if _collapse_bottom else "▼"
	var notice := root.get_node_or_null("Notice") as Control
	if notice:
		UiLayout.set_rect_frac(notice, 0.28, 0.4, 0.72, 0.5)
		notice.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _style_hud_chrome() -> void:
	var root := hud.get_node_or_null("Root") as Control
	if root == null:
		return
	for lbl_path in [
			"%s/Hp" % _ROUND, "%s/Phase" % _ROUND,
			"%s/Placement/TimerCol/Timer" % _ROUND, "%s/Placement/TimerCol/StageHint" % _ROUND,
			"Notice",
			"%s/LevelExp/LEInner/LELabels/Level" % _SHOP_LEFT,
			"%s/LevelExp/LEInner/LELabels/Exp" % _SHOP_LEFT,
			"%s/StatsRow/PopBox/Pop" % _SHOP_MID, "%s/StatsRow/GoldBox/Gold" % _SHOP_MID,
			"TopRight/Version",
			"RightCol/RightInner/RightContent/BattleLog/BattleLogInner/BattleLogTitle"]:
		var l := root.get_node_or_null(lbl_path) as Label
		if l:
			var design := 22 if "Timer" in lbl_path else (
				32 if "Gold" in lbl_path else (
				26 if "Pop" in lbl_path else (
				22 if "Level" in lbl_path else 15)))
			UiAssets.apply_label_font(l, "Gold" in lbl_path or "Level" in lbl_path, UiLayout.font_size(design, root))
			l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2) if "Gold" in lbl_path else Color(0.95, 0.95, 0.9))
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			l.add_theme_constant_override("outline_size", UiLayout.margin_px(3, root))
	for panel_path in ["RoundBar", "LeftCol", "RightCol", "Shop"]:
		var panel := root.get_node_or_null(panel_path) as PanelContainer
		if panel:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.07, 0.09, 0.11, 0.88)
			sb.border_color = Color(0.35, 0.72, 0.85, 0.55)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(4)
			sb.set_content_margin_all(UiLayout.margin_px(6, root))
			panel.add_theme_stylebox_override("panel", sb)
			panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var info := root.get_node_or_null(_INFO_PANEL) as PanelContainer
	if info:
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = Color(0.10, 0.12, 0.15, 0.0)
		sb2.border_color = Color(0.35, 0.72, 0.85, 0.38)
		sb2.set_border_width_all(1)
		sb2.set_corner_radius_all(6)
		sb2.set_content_margin_all(UiLayout.margin_px(8, root))
		info.add_theme_stylebox_override("panel", sb2)
	var blog := root.get_node_or_null("RightCol/RightInner/RightContent/BattleLog") as PanelContainer
	if blog:
		var sb3 := StyleBoxFlat.new()
		sb3.bg_color = Color(0.08, 0.12, 0.16, 0.9)
		sb3.set_corner_radius_all(4)
		sb3.set_content_margin_all(UiLayout.margin_px(6, root))
		blog.add_theme_stylebox_override("panel", sb3)
	var skip := root.get_node_or_null("%s/Placement/SkipBtn" % _ROUND) as Button
	if skip:
		UiAssets.apply_button_font(skip, UiLayout.font_size(14, root))
		skip.custom_minimum_size = Vector2(UiLayout.px(72, root), UiLayout.px(36, root))
	for btn_name in ["TopRight/PauseBtn", "TopRight/ExitBtn", "TopRight/SpeedBtn",
			"LeftCol/LeftInner/CollapseLeftBtn", "RightCol/RightInner/CollapseRightBtn",
			"Shop/ShopCol/CollapseBottomBtn"]:
		var b := root.get_node_or_null(btn_name) as Button
		if b:
			UiAssets.apply_button_font(b, UiLayout.font_size(13, root))
			b.custom_minimum_size = Vector2(UiLayout.px(56, root), UiLayout.px(28, root))
	_ensure_speed_button(root)

func _ensure_speed_button(root: Node) -> void:
	var top_r := root.get_node_or_null("TopRight") as HBoxContainer
	if top_r == null:
		return
	var btn := top_r.get_node_or_null("SpeedBtn") as Button
	if btn == null:
		btn = Button.new()
		btn.name = "SpeedBtn"
		var pause := top_r.get_node_or_null("PauseBtn")
		if pause:
			top_r.add_child(btn)
			top_r.move_child(btn, pause.get_index())
		else:
			top_r.add_child(btn)
		btn.pressed.connect(_on_speed_pressed)
	btn.visible = match_ctrl.stage == MatchController.Stage.BATTLE
	btn.text = match_ctrl.speed_label()
	btn.tooltip_text = "战斗倍速（点按循环）"

func _wire_shop_chrome() -> void:
	var root := hud.get_node_or_null("Root")
	if root == null:
		return
	# 按钮素材为横图（约 198×69）；宽度保持原设计，高度按比例，禁止再塞进正方形造成下方空白
	var btn_w := UiLayout.px(144 if UiLayout.is_mobile() else 162, root)
	_style_image_button(root.get_node_or_null("%s/LeftBtns/ExpBtn" % _SHOP_LEFT) as Button,
			UiAssets.shop_exp_path(), "购买经验", int(DataStore.economy.get("buy_exp_gold_cost", 4)), btn_w)
	_wire_exp_hold(root.get_node_or_null("%s/LeftBtns/ExpBtn" % _SHOP_LEFT) as Button)
	_style_image_button(root.get_node_or_null("%s/LeftBtns/RefreshBtn" % _SHOP_LEFT) as Button,
			UiAssets.shop_refresh_path(), "刷新商店", int(DataStore.economy.get("refresh_cost", 2)), btn_w)
	var lock := root.get_node_or_null("%s/StatsRow/LockBtn" % _SHOP_MID) as Button
	if lock:
		var t := UiAssets.tex(UiAssets.ICON_LOCK)
		if t:
			lock.icon = t
			lock.expand_icon = true
		lock.text = ""
		UiAssets.apply_button_font(lock, UiLayout.font_size(14, root))
		lock.custom_minimum_size = Vector2(UiLayout.px(52, root), UiLayout.px(44, root))
	_ensure_meta_icon(root.get_node_or_null("%s/StatsRow/GoldBox" % _SHOP_MID) as HBoxContainer, "Gold", UiAssets.ICON_MONEY, 36)
	_ensure_meta_icon(root.get_node_or_null("%s/StatsRow/PopBox" % _SHOP_MID) as HBoxContainer, "Pop", UiAssets.ICON_POP, 36)
	var btn_h := btn_w * (69.0 / 198.0)  # 与素材比例一致
	var le := root.get_node_or_null("%s/LevelExp" % _SHOP_LEFT) as PanelContainer
	if le:
		# 等级框贴合内容，高度不超过按钮行
		var le_h := minf(UiLayout.px(64 if UiLayout.is_mobile() else 68, root), ceilf(btn_h) + float(UiLayout.margin_px(8, root)))
		le.custom_minimum_size = Vector2(UiLayout.px(208, root), le_h)
		le.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var le_inner := le.get_node_or_null("LEInner") as VBoxContainer
		if le_inner:
			le_inner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			le_inner.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
		var le_sb := StyleBoxFlat.new()
		le_sb.bg_color = Color(0.05, 0.08, 0.1, 0.75)
		le_sb.border_color = Color(0.25, 0.55, 0.7, 0.55)
		le_sb.set_border_width_all(1)
		le_sb.set_corner_radius_all(4)
		le_sb.content_margin_left = UiLayout.margin_px(8, root)
		le_sb.content_margin_right = UiLayout.margin_px(8, root)
		le_sb.content_margin_top = UiLayout.margin_px(4, root)
		le_sb.content_margin_bottom = UiLayout.margin_px(4, root)
		le.add_theme_stylebox_override("panel", le_sb)
	var left_ctrl := root.get_node_or_null(_SHOP_LEFT) as Control
	if left_ctrl:
		# 宽度保留；高度跟内容走，禁止再锁 162 把 MetaRow 撑出空白带
		left_ctrl.custom_minimum_size = Vector2(UiLayout.px(560, root), 0)
		left_ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if left_ctrl is BoxContainer:
			(left_ctrl as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	var left_btns := root.get_node_or_null("%s/LeftBtns" % _SHOP_LEFT) as Control
	if left_btns:
		left_btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var seg_row := root.get_node_or_null("%s/LevelExp/LEInner/ExpSegRow" % _SHOP_LEFT) as HBoxContainer
	if seg_row:
		seg_row.custom_minimum_size = Vector2(0, UiLayout.px(18, root))
		seg_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seg_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var meta_row := root.get_node_or_null(_SHOP_META) as HBoxContainer
	if meta_row:
		meta_row.alignment = BoxContainer.ALIGNMENT_CENTER
		meta_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		meta_row.add_theme_constant_override("separation", UiLayout.margin_px(10, root))
	var shop_content := root.get_node_or_null("Shop/ShopCol/ShopContent") as VBoxContainer
	if shop_content:
		shop_content.add_theme_constant_override("separation", UiLayout.margin_px(4, root))
	var stats := root.get_node_or_null("%s/StatsRow" % _SHOP_MID) as HBoxContainer
	if stats:
		stats.alignment = BoxContainer.ALIGNMENT_CENTER
		stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sell := root.get_node_or_null("%s/SellZone" % _SHOP_INNER) as PanelContainer
	if sell:
		sell.custom_minimum_size = Vector2(UiLayout.px(120, root), 0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.22, 0.25, 0.92)
		sb.border_color = Color(0.4, 0.75, 0.9, 0.7)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sell.add_theme_stylebox_override("panel", sb)

func _ensure_meta_icon(box: HBoxContainer, for_name: String, tex_path: String, design_px: int = 20) -> void:
	if box == null:
		return
	for c in box.get_children():
		if c is TextureRect and c.has_meta("meta_icon_for") and str(c.get_meta("meta_icon_for")) == for_name:
			var existing_icon_sz := UiLayout.px(float(design_px), box)
			(c as TextureRect).custom_minimum_size = Vector2(existing_icon_sz, existing_icon_sz)
			return
	var icon := TextureRect.new()
	icon.set_meta("meta_icon_for", for_name)
	var new_icon_sz := UiLayout.px(float(design_px), box)
	icon.custom_minimum_size = Vector2(new_icon_sz, new_icon_sz)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var t := UiAssets.tex(tex_path)
	if t:
		icon.texture = t
	box.add_child(icon)
	box.move_child(icon, 0)

func _refresh_exp_segments(root: Node) -> void:
	var row := root.get_node_or_null("%s/LevelExp/LEInner/ExpSegRow" % _SHOP_LEFT) as HBoxContainer
	if row == null:
		return
	for c in row.get_children():
		row.remove_child(c)
		c.free()
	var demand := maxi(1, match_ctrl.up_level_demand)
	var exp_now := clampi(match_ctrl.player_exp, 0, demand)
	var seg_h := UiLayout.px(18, row)
	var slots := demand if demand <= 10 else 10
	var filled := exp_now if demand <= 10 else int(round(float(exp_now) / float(demand) * float(slots)))
	row.add_theme_constant_override("separation", UiLayout.margin_px(4, row))
	row.custom_minimum_size = Vector2(0, seg_h)
	for i in range(slots):
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.custom_minimum_size = Vector2(UiLayout.px(10, row), seg_h)
		var sb := StyleBoxFlat.new()
		if i < filled:
			sb.bg_color = Color(0.0, 0.78, 1.0, 1.0)
			sb.border_color = Color(0.55, 0.92, 1.0, 0.95)
		else:
			sb.bg_color = Color(0.04, 0.16, 0.24, 0.92)
			sb.border_color = Color(0.22, 0.48, 0.62, 0.9)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.set_content_margin_all(0)
		cell.add_theme_stylebox_override("panel", sb)
		row.add_child(cell)
	var legacy := root.get_node_or_null("%s/LevelExp/LEInner/ExpBar" % _SHOP_LEFT) as ProgressBar
	if legacy:
		legacy.visible = false

func _style_image_button(btn: Button, tex_path: String, title: String, cost: int, width_px: float = -1.0) -> void:
	if btn == null:
		return
	# Image-only: art fills the control; cost stays in tooltip / accessibility.
	btn.text = ""
	btn.tooltip_text = "%s  %d" % [title, cost]
	var w := width_px if width_px > 0.0 else UiLayout.px(72 if UiLayout.is_mobile() else 88, btn)
	var h := w
	var t := UiAssets.tex(tex_path)
	if t and t.get_width() > 0 and t.get_height() > 0:
		# 横图按比例定高，避免正方形 min_size 在图标下方留出大块空白
		h = w * (float(t.get_height()) / float(t.get_width()))
	btn.custom_minimum_size = Vector2(w, h)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if t:
		btn.icon = t
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	# Allow large icons to fill the button face.
	btn.add_theme_constant_override("icon_max_width", int(w))
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("disabled", empty)

func show_notice(text: String) -> void:
	AdminBus.request(&"ui.notice", {"text": text})
	_append_battle_log(text)
	var lbl := hud.get_node_or_null("Root/Notice") as Label
	if lbl:
		lbl.text = text
		lbl.visible = true
		get_tree().create_timer(2.0).timeout.connect(func(): if lbl: lbl.visible = false)

func append_battle_log(text: String) -> void:
	## Battle-log only (no floating notice) — used by AI sell / combat breadcrumbs.
	_append_battle_log(text)

func on_ship_sold(gold: int) -> void:
	match_ctrl.add_gold(gold)
	show_notice("出售获得 %d PLEX" % gold)
	board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	_refresh_hud()

func _refresh_hud() -> void:
	var root := hud.get_node_or_null("Root")
	if root == null:
		return
	_set_label(root, "%s/Hp" % _ROUND, _player_hp_label_text())
	_refresh_citadel_bar()
	_set_label(root, "%s/Phase" % _ROUND, "阶段 %d-%d" % [match_ctrl.battle_phase_value, match_ctrl.round_phase_value])
	_set_label(root, "%s/StatsRow/GoldBox/Gold" % _SHOP_MID, "%d" % match_ctrl.player_gold)
	_set_label(root, "%s/StatsRow/PopBox/Pop" % _SHOP_MID, "%d/%d" % [board.count_field(ShipUnit.TEAM_PLAYER), match_ctrl.population_limit()])
	_set_label(root, "%s/LevelExp/LEInner/LELabels/Level" % _SHOP_LEFT, "%d级" % match_ctrl.player_level)
	_set_label(root, "%s/LevelExp/LEInner/LELabels/Exp" % _SHOP_LEFT, "%d / %d" % [match_ctrl.player_exp, match_ctrl.up_level_demand])
	_refresh_exp_segments(root)
	var lock := root.get_node_or_null("%s/StatsRow/LockBtn" % _SHOP_MID) as Button
	if lock:
		lock.set_pressed_no_signal(match_ctrl.shop_locked)
	var stage_name := "准备" if match_ctrl.stage == MatchController.Stage.PREPARE else ("战斗" if match_ctrl.stage == MatchController.Stage.BATTLE else "结束")
	var ttext := "倒计时"
	if match_ctrl.stage == MatchController.Stage.PREPARE:
		ttext = "%.0f" % match_ctrl.prepare_remaining()
	elif match_ctrl.stage == MatchController.Stage.BATTLE:
		ttext = "%.0f" % match_ctrl.battle_remaining()
	_set_label(root, "%s/Placement/TimerCol/Timer" % _ROUND, ttext)
	_set_label(root, "%s/Placement/TimerCol/StageHint" % _ROUND, stage_name)
	var speed_btn := root.get_node_or_null("TopRight/SpeedBtn") as Button
	if speed_btn:
		speed_btn.visible = match_ctrl.stage == MatchController.Stage.BATTLE
		speed_btn.text = match_ctrl.speed_label()
	var skip := root.get_node_or_null("%s/Placement/SkipBtn" % _ROUND) as Button
	if skip:
		skip.visible = match_ctrl.stage == MatchController.Stage.PREPARE
		skip.disabled = match_ctrl.stage != MatchController.Stage.PREPARE
	_apply_shop_interactable()
	_refresh_fetter_ui(root)
	var ver := root.get_node_or_null("TopRight/Version") as Label
	if ver:
		ver.text = "壳 %s | 热更 %s" % [str(ProjectSettings.get_setting("application/config/version", "dev")), DataStore.content_version]

func _apply_shop_interactable() -> void:
	## Shop stays interactive in Prepare and Battle (no grey-lock).
	var root := hud.get_node_or_null("Root")
	if root == null:
		return
	for path in [
			"%s/LeftBtns/ExpBtn" % _SHOP_LEFT,
			"%s/LeftBtns/RefreshBtn" % _SHOP_LEFT,
			"%s/StatsRow/LockBtn" % _SHOP_MID]:
		var b := root.get_node_or_null(path) as Button
		if b:
			b.disabled = false
			b.modulate = Color(1, 1, 1, 1)
	var slots := root.get_node_or_null(_SHOP_SLOTS) as Control
	if slots:
		slots.modulate = Color(1, 1, 1, 1)
		for c in slots.get_children():
			_set_shop_card_interactable(c, true)

func _set_shop_card_interactable(card: Node, enabled: bool) -> void:
	if card == null:
		return
	for child in card.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = not enabled
			(child as BaseButton).mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		_set_shop_card_interactable(child, enabled)
func _refresh_fetter_ui(root: Node) -> void:
	var side := root.get_node_or_null(_BONUS) as VBoxContainer
	if side == null:
		return
	var list := side.get_node_or_null("FetterList") as VBoxContainer
	if list == null:
		var old := side.get_node_or_null("Fetters") as Label
		if old:
			old.visible = false
		list = VBoxContainer.new()
		list.name = "FetterList"
		list.add_theme_constant_override("separation", 6)
		side.add_child(list)
	for c in list.get_children():
		c.queue_free()
	var fetters: Array = board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	for a in fetters:
		var fid := str(a.get("fetter_id", ""))
		var fdata: Dictionary = DataStore.fetters.get(fid, {})
		var fname := str(fdata.get("name", fid))
		var count := int(a.get("count", 0))
		var eff: Dictionary = a.get("effect", {})
		var need := int(eff.get("champion_count", 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(UiLayout.px(26, list), UiLayout.px(26, list))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var tex := UiAssets.fetter_icon(fid, fname)
		if tex:
			icon.texture = tex
		row.add_child(icon)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 1)
		var lab := Label.new()
		lab.text = "%s %d/%d" % [fname, count, need] if need > 0 else "%s %d" % [fname, count]
		UiAssets.apply_label_font(lab, false, UiLayout.font_size(15, list))
		lab.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lab.add_theme_constant_override("outline_size", 3)
		col.add_child(lab)
		var eff_txt := UiAssets.fetter_effect_text(eff)
		if eff_txt != "":
			var elab := Label.new()
			elab.text = eff_txt
			elab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			UiAssets.apply_label_font(elab, false, UiLayout.font_size(12, list))
			elab.add_theme_color_override("font_color", Color(0.55, 0.92, 0.72))
			elab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
			elab.add_theme_constant_override("outline_size", 2)
			col.add_child(elab)
		row.add_child(col)
		list.add_child(row)

func _set_label(root: Node, path: String, text: String) -> void:
	var l := root.get_node_or_null(path) as Label
	if l:
		l.text = text

func _refresh_shop_ui() -> void:
	var box := hud.get_node_or_null("Root/%s" % _SHOP_SLOTS) as HBoxContainer
	if box == null:
		return
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for c in box.get_children():
		c.queue_free()
	var slot_count := maxi(1, shop.slots.size())
	var card_size := _shop_card_size(slot_count, box)
	for i in range(shop.slots.size()):
		var slot: Dictionary = shop.slots[i]
		var sid := int(slot.get("ship_id", 0))
		var ship: Dictionary = DataStore.get_ship(sid)
		var purchased := bool(slot.get("purchased", false))
		var ship_name := str(ship.get("name", "?"))
		var cost := int(ship.get("cost", 0))
		var card := _make_shop_card(ship_name, ship, purchased, cost, i, card_size)
		box.add_child(card)
	if not _dragging_sell_ui:
		_set_sell_mode(false)
	_apply_shop_interactable()

func _shop_card_size(slot_count: int, box: Control) -> Vector2:
	var avail_w := box.size.x
	var avail_h := box.size.y
	if avail_w < 8.0 or avail_h < 8.0:
		var shop_panel := hud.get_node_or_null("Root/Shop") as Control
		if shop_panel:
			avail_w = shop_panel.size.x * 0.88
			avail_h = shop_panel.size.y * 0.62
	if avail_w < 8.0:
		avail_w = UiLayout.px(1100.0, box)
	if avail_h < 8.0:
		avail_h = UiLayout.px(160.0, box)
	var sep := float(UiLayout.margin_px(6, box))
	var total_sep := sep * float(maxi(0, slot_count - 1))
	var w := (avail_w - total_sep) / float(slot_count)
	var min_w := UiLayout.px(88.0 if UiLayout.is_mobile() else 100.0, box)
	var max_w := UiLayout.px(180.0 if UiLayout.is_mobile() else 210.0, box)
	var min_h := UiLayout.px(120.0 if UiLayout.is_mobile() else 140.0, box)
	var max_h := UiLayout.px(180.0 if UiLayout.is_mobile() else 210.0, box)
	return Vector2(clampf(w, min_w, max_w), clampf(avail_h, min_h, max_h))

func _make_shop_card(ship_name: String, ship: Dictionary, purchased: bool, cost: int, idx: int, card_size: Vector2 = Vector2.ZERO) -> Control:
	var card := PanelContainer.new()
	var sz := card_size if card_size.x > 0.0 else Vector2(UiLayout.px(140, card), UiLayout.px(170, card))
	card.custom_minimum_size = sz
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var outer := StyleBoxFlat.new()
	outer.bg_color = Color(0.14, 0.16, 0.18, 0.98)
	outer.border_color = Color(0.4, 0.65, 0.78, 0.95)
	outer.set_border_width_all(2)
	outer.set_corner_radius_all(5)
	outer.set_content_margin_all(0)
	card.add_theme_stylebox_override("panel", outer)
	var stack := Control.new()
	stack.custom_minimum_size = sz
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(stack)
	if purchased:
		var done := Label.new()
		done.text = "已购"
		done.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UiAssets.apply_label_font(done, false, UiLayout.font_size(20, card))
		done.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
		stack.add_child(done)
		return card
	# Large centered portrait (leave room below for fetter strip + name)
	var psz := minf(sz.x * 0.88, sz.y * 0.58)
	psz = maxf(psz, UiLayout.px(72 if UiLayout.is_mobile() else 90, card))
	var tex := UiAssets.champion_icon(ship_name, int(ship.get("id", 0)))
	var art: Control
	if tex:
		var art_rect := TextureRect.new()
		art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art_rect.texture = tex
		art = art_rect
	else:
		var ph := ColorRect.new()
		ph.color = Color(0.12, 0.16, 0.24, 1.0)
		art = ph
	art.custom_minimum_size = Vector2(psz, psz)
	art.set_anchors_preset(Control.PRESET_CENTER_TOP)
	art.anchor_left = 0.5
	art.anchor_right = 0.5
	art.offset_left = -psz * 0.5
	art.offset_right = psz * 0.5
	art.offset_top = UiLayout.px(28, card)
	art.offset_bottom = art.offset_top + psz
	stack.add_child(art)
	# 本舰可达成羁绊 · 立绘下方简展
	var fids: Array = ship.get("fetter_ids", [])
	var badge_icon := UiLayout.px(18 if UiLayout.is_mobile() else 22, card)
	var fetter_box := HBoxContainer.new()
	fetter_box.add_theme_constant_override("separation", UiLayout.margin_px(3, card))
	fetter_box.alignment = BoxContainer.ALIGNMENT_CENTER
	fetter_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	fetter_box.anchor_left = 0.0
	fetter_box.anchor_right = 1.0
	fetter_box.offset_left = UiLayout.px(4, card)
	fetter_box.offset_right = -UiLayout.px(4, card)
	fetter_box.offset_top = art.offset_bottom + UiLayout.px(2, card)
	fetter_box.offset_bottom = fetter_box.offset_top + badge_icon + 2.0
	for fid in fids:
		var fdata: Dictionary = DataStore.fetters.get(str(fid), {})
		var fname := str(fdata.get("name", fid))
		var fic := TextureRect.new()
		fic.custom_minimum_size = Vector2(badge_icon, badge_icon)
		fic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fic.tooltip_text = fname
		var ft := UiAssets.fetter_icon(str(fid), fname)
		if ft:
			fic.texture = ft
		else:
			# 无图时用色块占位，避免空白缺口
			var ph2 := ColorRect.new()
			ph2.custom_minimum_size = Vector2(badge_icon, badge_icon)
			ph2.color = Color(0.35, 0.4, 0.48, 0.9)
			ph2.tooltip_text = fname
			fetter_box.add_child(ph2)
			continue
		fetter_box.add_child(fic)
	stack.add_child(fetter_box)
	# Name under fetter strip
	var name_l := Label.new()
	name_l.text = ship_name
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_l.offset_top = -UiLayout.px(28, card)
	name_l.offset_bottom = -UiLayout.px(4, card)
	name_l.offset_left = UiLayout.px(4, card)
	name_l.offset_right = -UiLayout.px(4, card)
	UiAssets.apply_label_font(name_l, false, UiLayout.font_size(14, card))
	name_l.add_theme_color_override("font_color", Color(1, 1, 1))
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_l.add_theme_constant_override("outline_size", 3)
	stack.add_child(name_l)
	# ★ 角标 · 左上
	var star_badge := _make_corner_badge("★1", Color(0.12, 0.1, 0.05, 0.92), Color(1.0, 0.88, 0.35), card)
	star_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	star_badge.offset_left = UiLayout.px(4, card)
	star_badge.offset_top = UiLayout.px(4, card)
	star_badge.offset_right = star_badge.offset_left + UiLayout.px(42, card)
	star_badge.offset_bottom = star_badge.offset_top + UiLayout.px(24, card)
	stack.add_child(star_badge)
	# 价格角标 · 右下
	var cost_badge := PanelContainer.new()
	var cost_sb := StyleBoxFlat.new()
	cost_sb.bg_color = Color(0.05, 0.08, 0.1, 0.92)
	cost_sb.border_color = Color(0.85, 0.7, 0.25, 0.9)
	cost_sb.set_border_width_all(1)
	cost_sb.set_corner_radius_all(4)
	cost_sb.set_content_margin_all(UiLayout.margin_px(4, card))
	cost_badge.add_theme_stylebox_override("panel", cost_sb)
	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", UiLayout.margin_px(3, card))
	cost_badge.add_child(cost_row)
	var money := TextureRect.new()
	money.custom_minimum_size = Vector2(UiLayout.px(16, card), UiLayout.px(16, card))
	money.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	money.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var mt := UiAssets.tex(UiAssets.ICON_MONEY)
	if mt:
		money.texture = mt
	cost_row.add_child(money)
	var cost_l := Label.new()
	cost_l.text = str(cost)
	UiAssets.apply_label_font(cost_l, false, UiLayout.font_size(15, card))
	cost_l.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	cost_row.add_child(cost_l)
	cost_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cost_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cost_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cost_badge.offset_right = -UiLayout.px(4, card)
	cost_badge.offset_bottom = -UiLayout.px(30, card)
	cost_badge.offset_left = cost_badge.offset_right - UiLayout.px(56, card)
	cost_badge.offset_top = cost_badge.offset_bottom - UiLayout.px(26, card)
	stack.add_child(cost_badge)
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.pressed.connect(func():
		shop.try_buy(idx)
		_refresh_shop_ui()
		_refresh_hud()
	)
	hit.mouse_entered.connect(func(): _show_ship_info_id(int(ship.get("id", 0))))
	hit.gui_input.connect(func(ev): _shop_gui_input(ev, idx))
	stack.add_child(hit)
	return card

func _make_corner_badge(text: String, bg: Color, fg: Color, from: Node) -> PanelContainer:
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(UiLayout.margin_px(4, from))
	badge.add_theme_stylebox_override("panel", sb)
	var lab := Label.new()
	lab.text = text
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiAssets.apply_label_font(lab, false, UiLayout.font_size(13, from))
	lab.add_theme_color_override("font_color", fg)
	badge.add_child(lab)
	return badge

func _shop_card_height(slot_count: int, box: Control) -> float:
	return _shop_card_size(slot_count, box).y

func _shop_gui_input(ev: InputEvent, idx: int) -> void:
	if ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_long_press_slot = idx
			_long_press_t = Time.get_ticks_msec() / 1000.0
		else:
			if _long_press_slot == idx:
				var held := Time.get_ticks_msec() / 1000.0 - _long_press_t
				if held >= 0.35:
					_show_ship_info_id(int(shop.slots[idx].get("ship_id", 0)))
			_long_press_slot = -1

func _set_sell_mode(active: bool, price: int = 0) -> void:
	var slots := hud.get_node_or_null("Root/%s" % _SHOP_SLOTS) as Control
	var sell := hud.get_node_or_null("Root/%s/SellZone" % _SHOP_INNER) as PanelContainer
	if slots:
		slots.visible = not active
	if sell:
		sell.visible = active
		var lab := sell.get_node_or_null("SellLabel") as Label
		if lab:
			lab.text = "售价  %d" % price if active else "售价"
			UiAssets.apply_label_font(lab, false, 22)

func _on_drag_begin(ship: ShipUnit) -> void:
	board.begin_drag(ship)
	_dragging_sell_ui = true
	var price := 0
	if ship:
		price = ship.get_sell_price()
	_set_sell_mode(true, price)

func _on_drag_move(world_pos: Vector3) -> void:
	board.update_drag(world_pos)

func _on_drag_end(sell: bool, slot: Dictionary) -> void:
	board.end_drag(sell, slot)
	var team := int(slot.get("team", ShipUnit.TEAM_PLAYER))
	board.recalculate_fetters(team)
	_dragging_sell_ui = false
	_set_sell_mode(false)
	_refresh_shop_ui()
	_refresh_hud()

func _on_tap_ship(ship: ShipUnit) -> void:
	_show_ship_info(ship)

func _on_hover_ship(ship: ShipUnit) -> void:
	if ship:
		_show_ship_info(ship)
	else:
		_hide_ship_info()

func _on_long_press_shop(idx: int) -> void:
	if idx >= 0 and idx < shop.slots.size():
		_show_ship_info_id(int(shop.slots[idx].get("ship_id", 0)))

func _weapon_kind_label(kind: String) -> String:
	match kind:
		"rail":
			return "磁轨"
		"cannon":
			return "火炮"
		"missile":
			return "导弹"
		"heal":
			return "维修"
		_:
			return "激光"

func _weapon_size_label(ship_data: Dictionary) -> String:
	var tier := str(ship_data.get("weapon_tier", ""))
	if tier == "large":
		return "大"
	if tier == "small":
		return "小"
	if tier == "medium":
		return "中"
	var ship_group := str(ship_data.get("ship_group", ""))
	match ship_group:
		"frigate", "destroyer":
			return "小"
		"cruiser", "battlecruiser":
			return "中"
		"battleship":
			return "大"
		_:
			return ""

func _weapon_module_type_id(ship_data: Dictionary) -> int:
	var fx: String = str(ship_data.get("weapon_fx", "laser"))
	var source_weapon := int(ship_data.get("source_module_type_id", 0))
	if fx == "heal":
		## Medium/large remote repair reuse small-tier icons (art parity).
		return _repair_icon_type_id(int(ship_data.get("source_repair_module_type_id", 0)))
	var group := str(ship_data.get("ship_group", "frigate"))
	var tier := str(ship_data.get("weapon_tier", ""))
	var large := tier == "large" or group == "battleship"
	var medium := tier == "medium" or (tier == "" and (group == "cruiser" or group == "battlecruiser"))
	## Prefer Echoes-tier icons: medium missile must not share large missile art.
	if fx == "missile" and medium and (source_weapon == 501 or source_weapon == 499 or source_weapon == 0):
		return 120300101
	if source_weapon > 0:
		return source_weapon
	match fx:
		"laser":
			if large:
				return 462
			if medium:
				return 456
			return 453
		"rail":
			if large:
				return 574
			if medium:
				return 570
			return 561
		"cannon":
			if large:
				return 498
			if medium:
				return 491
			return 485
		"missile":
			if large:
				return 501
			if medium:
				return 120300101
			return 499
		_:
			return int(ship_data.get("source_module_type_id", 0))

func _repair_icon_type_id(repair_module_id: int) -> int:
	## Armor RR / shield RB / hull RR: always show small-tier icon art.
	match repair_module_id:
		11355, 11357, 11359:
			return 11355
		3586, 3596, 3606:
			return 3586
		27932, 27930, 27904:
			return 11355  ## no dedicated hull icon pack — reuse armor RR small
		_:
			return repair_module_id if repair_module_id > 0 else 11355

func _weapon_damage_text(dmg: Dictionary) -> String:
	var emp := float(dmg.get("emp", 0.0))
	var thermal := float(dmg.get("thermal", 0.0))
	var kinetic := float(dmg.get("kinetic", 0.0))
	var explosive := float(dmg.get("explosive", 0.0))
	var total := emp + thermal + kinetic + explosive
	## Hide per-channel breakdown (capital/cyno UI lock).
	return "总伤 %d" % int(round(total))

func _weapon_or_repair_text(ship_data: Dictionary, star_data: Dictionary, dmg: Dictionary) -> String:
	if str(ship_data.get("weapon_fx", "")) != "heal":
		return _weapon_damage_text(dmg)
	var repair: Dictionary = star_data.get("repair", {})
	var lines: Array[String] = []
	var shield := float(repair.get("shield", 0.0))
	var armor := float(repair.get("armor", 0.0))
	var structure := float(repair.get("structure", 0.0))
	if shield > 0.0:
		lines.append("护盾修理 %d" % int(round(shield)))
	if armor > 0.0:
		lines.append("装甲修理 %d" % int(round(armor)))
	if structure > 0.0:
		lines.append("结构修理 %d" % int(round(structure)))
	if lines.is_empty():
		lines.append("修理 0")
	return "\n".join(lines)

const _RACE_DRONE_LIGHT := {"amarr": 1001, "caldari": 1002, "gallente": 1003, "minmatar": 1004}
const _RACE_DRONE_MEDIUM := {"amarr": 1005, "caldari": 1006, "gallente": 1007, "minmatar": 1008}
const _RACE_DRONE_HEAVY := {"amarr": 1011, "caldari": 1012, "gallente": 1013, "minmatar": 1014}
const _DRONE_COUNT_EXCEPTIONS := {42: 5, 44: 4, 55: 4, 56: 5}

func _drone_tier_for_carrier(ship_data: Dictionary) -> String:
	var group := str(ship_data.get("ship_group", "frigate"))
	if group == "battlecruiser":
		return "medium"
	if group == "battleship":
		return "heavy"
	if group == "cruiser":
		return "medium"
	return "light"

func _race_drone_id(ship_data: Dictionary) -> int:
	var race := str(ship_data.get("race", "amarr")).to_lower()
	match _drone_tier_for_carrier(ship_data):
		"heavy":
			return int(_RACE_DRONE_HEAVY.get(race, 1011))
		"medium":
			return int(_RACE_DRONE_MEDIUM.get(race, 1005))
		_:
			return int(_RACE_DRONE_LIGHT.get(race, 1001))

func _ship_drone_bay_slots(ship_data: Dictionary) -> int:
	var sid := int(ship_data.get("id", 0))
	if _DRONE_COUNT_EXCEPTIONS.has(sid):
		return int(_DRONE_COUNT_EXCEPTIONS[sid])
	var group := str(ship_data.get("ship_group", ""))
	if group == "battleship":
		return 2
	if group == "battlecruiser":
		return 1
	var slots := int(ship_data.get("drone_bay_slots", ship_data.get("drone_count_cap", 0)))
	if slots <= 0:
		var bw := float(ship_data.get("drone_bandwidth", 0.0))
		if bw > 0.0:
			slots = int(floor(bw / 5.0))
	return slots

func _attack_cycle_s(ship_data: Dictionary, runtime_cycle: float = -1.0) -> float:
	## Same source as ShipUnit.setup: JSON cycle (or combat fallback), then attack_cycle_cap_s.
	var cap_s := float(DataStore.combat.get("attack_cycle_cap_s", 6.0))
	var role := str(ship_data.get("capital_role", ""))
	var skip_cap := role != "" or bool(ship_data.get("requires_cyno_entry", false))
	if runtime_cycle > 0.0:
		return runtime_cycle if skip_cap else minf(runtime_cycle, cap_s)
	var cycle := float(ship_data.get("attack_cycle_s", 0.0))
	if cycle <= 0.0:
		var logistic := str(ship_data.get("weapon_fx", "")) == "heal" or bool(ship_data.get("is_logistic", false))
		cycle = float(DataStore.combat.get("logistic_attack_duration_s" if logistic else "attack_duration_s", 1.0))
	return cycle if skip_cap else minf(cycle, cap_s)

func _weapon_stats_text(ship_data: Dictionary, star_data: Dictionary, atk_range, runtime_cycle: float = -1.0) -> String:
	var shown_range := float(atk_range)
	var tracking := float(star_data.get("tracking", 0.0))
	var cycle := _attack_cycle_s(ship_data, runtime_cycle)
	return "射程 %s\n跟踪 %.2f\nCD %.2fs" % [str(int(round(shown_range))), tracking, cycle]

func _drone_stats_text(drone_data: Dictionary, drone_star: Dictionary) -> String:
	var cycle := _attack_cycle_s(drone_data)
	var speed := float(drone_data.get("speed", 0.0))
	if bool(drone_data.get("is_logistic", false)) or str(drone_data.get("weapon_fx", "")) == "heal":
		var repair: Dictionary = drone_star.get("repair", {})
		var parts: Array[String] = []
		for k in ["shield", "armor", "structure"]:
			var v := float(repair.get(k, 0.0))
			if v > 0.0:
				var label := "盾" if k == "shield" else ("甲" if k == "armor" else "结")
				parts.append("%s%d" % [label, int(round(v))])
		var heal_txt := " ".join(parts) if not parts.is_empty() else "修 0"
		return "%s\nCD %.2fs\n速度 %s" % [heal_txt, cycle, str(int(round(speed)))]
	var dmg: Dictionary = drone_star.get("damage", {})
	return "%s\nCD %.2fs\n速度 %s" % [_weapon_damage_text(dmg), cycle, str(int(round(speed)))]

func _ensure_info_stat_square(parent: Control, square_name: String, min_size: Vector2) -> Dictionary:
	var square := parent.get_node_or_null(square_name) as PanelContainer
	if square == null:
		square = PanelContainer.new()
		square.name = square_name
		square.custom_minimum_size = min_size
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_content_margin_all(0)
		square.add_theme_stylebox_override("panel", sb)
		parent.add_child(square)
	var row := square.get_node_or_null("%sRow" % square_name) as HBoxContainer
	if row == null:
		row = HBoxContainer.new()
		row.name = "%sRow" % square_name
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.add_theme_constant_override("separation", 10)
		UiAssets.full_rect(row)
		square.add_child(row)
	var icon := row.get_node_or_null("%sIcon" % square_name) as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = "%sIcon" % square_name
		icon.custom_minimum_size = Vector2(56, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	var lbl := row.get_node_or_null("%sText" % square_name) as Label
	if lbl == null:
		lbl = Label.new()
		lbl.name = "%sText" % square_name
		lbl.custom_minimum_size = Vector2(150, 72)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(lbl)
	return {"square": square, "icon": icon, "label": lbl}

func _ensure_info_weapon_column(info_top: HBoxContainer) -> Dictionary:
	var col := info_top.get_node_or_null("InfoWeaponColumn") as VBoxContainer
	if col == null:
		col = VBoxContainer.new()
		col.name = "InfoWeaponColumn"
		col.add_theme_constant_override("separation", 6)
		info_top.add_child(col)
	# Migrate legacy weapon square if it was parented directly under InfoTop.
	var legacy := info_top.get_node_or_null("InfoWeaponSquare") as PanelContainer
	if legacy and legacy.get_parent() == info_top:
		info_top.remove_child(legacy)
		legacy.queue_free()
	var weapon := _ensure_info_stat_square(col, "InfoWeaponSquare", Vector2(228, 176))
	var drone := _ensure_info_stat_square(col, "InfoDroneSquare", Vector2(228, 120))
	return {"weapon": weapon, "drone": drone}

func _style_info_stat_label(lbl: Label) -> void:
	UiAssets.apply_label_font(lbl, true, 13)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 2)

func _ensure_info_weapon_square(info_top: HBoxContainer) -> Dictionary:
	return _ensure_info_weapon_column(info_top).get("weapon", {})

func _ensure_info_extra(body: VBoxContainer) -> Label:
	var lbl := body.get_node_or_null("InfoExtra") as Label
	if lbl == null:
		lbl = Label.new()
		lbl.name = "InfoExtra"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(lbl)
	return lbl

func _resist_pct(value) -> int:
	return int(round(float(value) * 100.0))

func _resist_text(resist: Dictionary) -> String:
	return "电%s%% 热%s%% 动%s%% 爆%s%%" % [
		_resist_pct(resist.get("emp", 0.0)),
		_resist_pct(resist.get("thermal", 0.0)),
		_resist_pct(resist.get("kinetic", 0.0)),
		_resist_pct(resist.get("explosive", 0.0))
	]

func _hp_line(layer_name: String, hp_text: String, _resist: Dictionary) -> String:
	## Resists hidden in ship detail panel (capital update lock).
	return "%s  %s" % [layer_name, hp_text]

func _base_stats_text(ship_data: Dictionary) -> String:
	var long_axis := float(ship_data.get("model_long_axis", 0.0))
	var long_axis_txt := "%.0f" % long_axis if long_axis > 0.0 else "—"
	return "信源半径 %s   速度 %s   长轴 %s\n感应强度 %s   电容量 %s   电容回复 %ss" % [
		str(ship_data.get("signature_radius", 0)),
		str(ship_data.get("speed", 0)),
		long_axis_txt,
		str(ship_data.get("sensor_strength", 0)),
		str(ship_data.get("capacitor_capacity", 0)),
		str(ship_data.get("capacitor_recharge_s", 0))
	]

func _fill_info_panel(ship_name: String, star: int, shield_txt: String, armor_txt: String, structure_txt: String, dmg: Dictionary, atk_range, fetter_ids: Array, ship_data: Dictionary, star_data: Dictionary, ship_id: int = 0, runtime_cycle: float = -1.0) -> void:
	var p := hud.get_node_or_null("Root/%s" % _INFO_PANEL) as PanelContainer
	if p == null:
		return
	var icon := p.get_node_or_null("InfoBody/InfoTop/InfoIcon") as TextureRect
	var title := p.get_node_or_null("InfoBody/InfoTop/InfoTitleCol/InfoTitle") as Label
	var title_col := p.get_node_or_null("InfoBody/InfoTop/InfoTitleCol") as VBoxContainer
	var info_top := p.get_node_or_null("InfoBody/InfoTop") as HBoxContainer
	var weapon_col: Dictionary = {}
	if info_top:
		weapon_col = _ensure_info_weapon_column(info_top)
	var weapon_square: Dictionary = weapon_col.get("weapon", {})
	var drone_square: Dictionary = weapon_col.get("drone", {})
	if title_col:
		var old_badge := title_col.get_node_or_null("InfoWeaponRow")
		if old_badge:
			old_badge.queue_free()
	var fetter_box := p.get_node_or_null("InfoBody/InfoFetters") as VBoxContainer
	var sh := p.get_node_or_null("InfoBody/InfoShield") as Label
	var ar := p.get_node_or_null("InfoBody/InfoArmor") as Label
	var st := p.get_node_or_null("InfoBody/InfoStructure") as Label
	var dm := p.get_node_or_null("InfoBody/InfoDmg") as Label
	var rg := p.get_node_or_null("InfoBody/InfoRange") as Label
	var body := p.get_node_or_null("InfoBody") as VBoxContainer
	var extra: Label = null
	if body:
		extra = _ensure_info_extra(body)
	if icon:
		icon.texture = UiAssets.champion_icon(ship_name, ship_id)
	if title:
		title.text = "%s  ★%d" % [ship_name, star]
		UiAssets.apply_label_font(title, true, 22)
	if not weapon_square.is_empty():
		var weapon_icon := weapon_square.get("icon") as TextureRect
		var weapon_label := weapon_square.get("label") as Label
		var weapon_panel := weapon_square.get("square") as PanelContainer
		var fs: Dictionary = ship_data.get("function_slots", {}) if typeof(ship_data.get("function_slots", {})) == TYPE_DICTIONARY else {}
		var fslots: Array = fs.get("slots", []) if typeof(fs) == TYPE_DICTIONARY else []
		var cyno_mod: Dictionary = {}
		for m in fslots:
			if typeof(m) == TYPE_DICTIONARY and str((m as Dictionary).get("kind", "")) == "cyno":
				cyno_mod = m
				break
		var dmg_total := float(dmg.get("emp", 0)) + float(dmg.get("thermal", 0)) + float(dmg.get("kinetic", 0)) + float(dmg.get("explosive", 0))
		var show_cyno := not cyno_mod.is_empty() or str(ship_data.get("capital_role", "")) == "covert_cyno"
		if (not show_cyno) and dmg_total <= 0.001:
			# No primary weapon damage: hide weapon slot (carriers/FAX etc. keep drone/fighter slot only).
			if weapon_panel:
				weapon_panel.visible = false
			if weapon_icon:
				weapon_icon.texture = null
			if weapon_label:
				weapon_label.text = ""
		elif show_cyno and dmg_total <= 0.001:
			## Empty weapon → equip (cyno) fills weapon square (上移盖空武器框).
			if weapon_panel:
				weapon_panel.visible = true
			if weapon_icon:
				var cyno_icon_id := int(cyno_mod.get("icon_item_id", ship_data.get("source_module_type_id", 11114010000)))
				weapon_icon.texture = UiAssets.item_icon(cyno_icon_id)
			if weapon_label:
				var dur := float(cyno_mod.get("duration_s", 90.0))
				weapon_label.text = "%s\n读条 %.0fs" % [str(cyno_mod.get("name", "诱导")), dur]
				_style_info_stat_label(weapon_label)
		else:
			if weapon_panel:
				weapon_panel.visible = true
			if weapon_icon:
				weapon_icon.texture = UiAssets.item_icon(_weapon_module_type_id(ship_data))
			if weapon_label:
				weapon_label.text = "%s\n%s" % [
					_weapon_or_repair_text(ship_data, star_data, dmg),
					_weapon_stats_text(ship_data, star_data, atk_range, runtime_cycle)
				]
				_style_info_stat_label(weapon_label)
	if not drone_square.is_empty():
		var drone_panel := drone_square.get("square") as PanelContainer
		var drone_icon := drone_square.get("icon") as TextureRect
		var drone_label := drone_square.get("label") as Label
		var fighter_id := int(ship_data.get("fighter_unit_id", 0))
		var repair_id := int(ship_data.get("heavy_repair_drone_id", 0))
		var bay_slots := _ship_drone_bay_slots(ship_data)
		if fighter_id > 0:
			var squads := int(ship_data.get("fighter_squadrons", 3))
			var tubes := int(ship_data.get("fighter_tubes_per_squadron", 3))
			var n_fighters := squads * tubes
			var fighter_data: Dictionary = DataStore.get_ship(fighter_id)
			var fighter_star: Dictionary = DataStore.get_star(fighter_id, 1)
			if drone_panel:
				drone_panel.visible = true
			if drone_icon:
				drone_icon.texture = UiAssets.champion_icon(str(fighter_data.get("name", "")), fighter_id)
			if drone_label:
				drone_label.text = "%s ×%d\n%s" % [
					str(fighter_data.get("name", "舰载机")),
					n_fighters,
					_drone_stats_text(fighter_data, fighter_star)
				]
				_style_info_stat_label(drone_label)
		elif repair_id > 0:
			var n_rep := int(ship_data.get("heavy_repair_drone_count", 4))
			var rep_data: Dictionary = DataStore.get_ship(repair_id)
			var rep_star: Dictionary = DataStore.get_star(repair_id, 1)
			if drone_panel:
				drone_panel.visible = true
			if drone_icon:
				drone_icon.texture = UiAssets.drone_portrait(repair_id)
				if drone_icon.texture == null:
					var rep_path := str(rep_data.get("portrait", ""))
					if rep_path != "":
						drone_icon.texture = UiAssets.tex(rep_path)
			if drone_label:
				drone_label.text = "%s ×%d\n%s" % [
					str(rep_data.get("name", "维修无人机")),
					n_rep,
					_drone_stats_text(rep_data, rep_star)
				]
				_style_info_stat_label(drone_label)
		else:
			if drone_panel:
				drone_panel.visible = bay_slots > 0
			if bay_slots > 0:
				var drone_id := _race_drone_id(ship_data)
				var drone_data: Dictionary = DataStore.get_ship(drone_id)
				var drone_star: Dictionary = DataStore.get_star(drone_id, 1)
				if drone_icon:
					drone_icon.texture = UiAssets.drone_portrait(drone_id)
				if drone_label:
					var drone_name := str(drone_data.get("name", "无人机"))
					drone_label.text = "%s ×%d\n%s" % [
						drone_name,
						bay_slots,
						_drone_stats_text(drone_data, drone_star)
					]
					_style_info_stat_label(drone_label)
	if fetter_box:
		for c in fetter_box.get_children():
			c.queue_free()
		for fid in fetter_ids:
			var fdata: Dictionary = DataStore.fetters.get(str(fid), {})
			var fname := str(fdata.get("name", fid))
			var row := HBoxContainer.new()
			var fic := TextureRect.new()
			fic.custom_minimum_size = Vector2(22, 22)
			fic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var ft := UiAssets.fetter_icon(str(fid), fname)
			if ft:
				fic.texture = ft
			row.add_child(fic)
			var fl := Label.new()
			fl.text = fname
			UiAssets.apply_label_font(fl, false, 15)
			row.add_child(fl)
			fetter_box.add_child(row)
	if sh:
		sh.text = _hp_line("护盾", shield_txt, star_data.get("shield_resist", {}))
		UiAssets.apply_label_font(sh, false, 16)
	if ar:
		ar.text = _hp_line("装甲", armor_txt, star_data.get("armor_resist", {}))
		UiAssets.apply_label_font(ar, false, 16)
	if st:
		st.text = _hp_line("结构", structure_txt, star_data.get("structure_resist", {}))
		UiAssets.apply_label_font(st, false, 16)
	if dm:
		dm.visible = false
	if rg:
		rg.visible = false
	if extra:
		extra.text = _base_stats_text(ship_data)
		UiAssets.apply_label_font(extra, false, 15)
	p.visible = true
	# Expand right column when showing ship info.
	if _collapse_right:
		_collapse_right = false
		_apply_adaptive_hud_layout()

func _show_ship_info(ship: ShipUnit) -> void:
	_info_ship = ship
	_suppress_headup_for_preview = ship == null or ship.slot_type != "field"
	if ship == null:
		return
	var data: Dictionary = DataStore.get_ship(ship.ship_id)
	var st: Dictionary = DataStore.get_star(ship.ship_id, ship.star)
	_fill_info_panel(
		str(data.get("name", "?")),
		ship.star,
		"%.0f/%.0f" % [ship.shield_hp, ship.max_shield],
		"%.0f/%.0f" % [ship.armor_hp, ship.max_armor],
		"%.0f/%.0f" % [ship.structure_hp, ship.max_structure],
		{"emp": ship.damage_emp, "thermal": ship.damage_thermal, "kinetic": ship.damage_kinetic, "explosive": ship.damage_explosive},
		ship.attack_range,
		data.get("fetter_ids", []),
		data,
		st,
		ship.ship_id,
		ship.attack_duration
	)

func _show_ship_info_id(ship_id: int) -> void:
	_info_ship = null
	_suppress_headup_for_preview = true
	var st: Dictionary = DataStore.get_star(ship_id, 1)
	var data: Dictionary = DataStore.get_ship(ship_id)
	var dmg: Dictionary = st.get("damage", {})
	var armor := float(st.get("armor_hp", 0))
	var structure := float(st.get("structure_hp", maxf(50.0, roundf(armor * 0.5))))
	_fill_info_panel(
		str(data.get("name", "?")),
		1,
		str(st.get("shield_hp", 0)),
		str(st.get("armor_hp", 0)),
		str(int(structure)),
		dmg,
		st.get("attack_range", 0),
		data.get("fetter_ids", []),
		data,
		st,
		ship_id
	)

func _hide_ship_info() -> void:
	_info_ship = null
	_suppress_headup_for_preview = false
	var p := hud.get_node_or_null("Root/%s" % _INFO_PANEL) as PanelContainer
	if p:
		p.visible = false

func _on_match_over(summary: String) -> void:
	show_notice(summary)
	_append_battle_log(summary)
	_cam_headup_phase = 0
	_cam_headup_t = 0.0
	_cam_headup_offset_deg = 0.0
	_cam_base_pitch_deg = _cam_default_pitch_deg
	var delay := float(DataStore.match_flow.get("death_return_delay_s", 3))
	await get_tree().create_timer(delay).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_refresh_pressed() -> void:
	shop.manual_refresh()
	_refresh_shop_ui()
	_refresh_hud()

func _on_lock_pressed() -> void:
	match_ctrl.shop_locked = not match_ctrl.shop_locked
	show_notice("商店锁定" if match_ctrl.shop_locked else "商店解锁")

func _on_lock_toggled(pressed: bool) -> void:
	match_ctrl.shop_locked = pressed
	show_notice("商店锁定" if pressed else "商店解锁")

func _on_exp_pressed() -> void:
	## Scene may still fire pressed; prefer button_down/up hold path.
	pass

func _wire_exp_hold(btn: Button) -> void:
	if btn == null:
		return
	if btn.pressed.is_connected(_on_exp_pressed):
		btn.pressed.disconnect(_on_exp_pressed)
	if not btn.button_down.is_connected(_on_exp_button_down):
		btn.button_down.connect(_on_exp_button_down)
	if not btn.button_up.is_connected(_on_exp_button_up):
		btn.button_up.connect(_on_exp_button_up)

func _on_exp_button_down() -> void:
	_exp_hold_active = true
	_exp_hold_t = 0.0
	_exp_hold_spent_all = false

func _on_exp_button_up() -> void:
	if _exp_hold_active and not _exp_hold_spent_all and _exp_hold_t < _EXP_HOLD_S:
		match_ctrl.buy_exp()
		_refresh_hud()
	_exp_hold_active = false
	_exp_hold_t = 0.0

func _tick_exp_hold(delta: float) -> void:
	if not _exp_hold_active or _exp_hold_spent_all:
		return
	_exp_hold_t += delta
	if _exp_hold_t < _EXP_HOLD_S:
		return
	_exp_hold_spent_all = true
	var cost := int(DataStore.economy.get("buy_exp_gold_cost", 4))
	var n := 0
	while match_ctrl.player_gold >= cost and n < 200:
		var before := match_ctrl.player_gold
		match_ctrl.buy_exp()
		if match_ctrl.player_gold >= before:
			break
		n += 1
	_refresh_hud()
	show_notice("已花光黄币升级" if n > 0 else "黄币不足")

func _player_hp_label_text() -> String:
	var t := "我 %d  ·  敌 %d" % [match_ctrl.player_hp, match_ctrl.ai_hp]
	if bool(DataStore.match_flow.get("citadel_test_mode", false)):
		t += "  测试期间输一局只扣一点血"
	return t

func _apply_match_save() -> void:
	_apply_match_save_dict(MatchSave.load_dict())

func _apply_match_save_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	var p: Dictionary = d.get("player", {})
	match_ctrl.player_gold = int(p.get("gold", match_ctrl.player_gold))
	match_ctrl.player_hp = int(p.get("hp", match_ctrl.player_hp))
	match_ctrl.player_max_hp = int(p.get("max_hp", match_ctrl.player_max_hp))
	match_ctrl.player_level = int(p.get("level", match_ctrl.player_level))
	match_ctrl.player_exp = int(p.get("exp", match_ctrl.player_exp))
	match_ctrl.up_level_demand = int(p.get("up_level_demand", match_ctrl.up_level_demand))
	match_ctrl.win_streak = int(p.get("win_streak", 0))
	match_ctrl.loss_streak = int(p.get("loss_streak", 0))
	match_ctrl.shop_locked = bool(p.get("shop_locked", false))
	match_ctrl.battle_game_stage_count = int(d.get("battle_game_stage_count", 0))
	match_ctrl.round_phase_value = int(d.get("round_phase_value", 1))
	match_ctrl.battle_phase_value = int(d.get("battle_phase_value", 0))
	if shop and p.has("shop_slots"):
		shop.slots = (p.get("shop_slots", []) as Array).duplicate(true)
		shop.shop_changed.emit()
	var a: Dictionary = d.get("ai", {})
	match_ctrl.ai_hp = int(a.get("hp", match_ctrl.ai_hp))
	match_ctrl.ai_max_hp = int(a.get("max_hp", match_ctrl.ai_max_hp))
	if ai:
		ai.ai_gold = int(a.get("gold", ai.ai_gold))
		ai.ai_level = int(a.get("level", ai.ai_level))
		ai.ai_exp = int(a.get("exp", ai.ai_exp))
		ai.up_level_demand = int(a.get("up_level_demand", ai.up_level_demand))
		ai.win_streak = int(a.get("win_streak", 0))
		ai.loss_streak = int(a.get("loss_streak", 0))
		ai.shop_slots = a.get("shop_slots", ai.shop_slots)
	board.reset_match()
	_redeploy_saved_ships(d.get("ships", []))
	## start_match already ran AI economy on an empty board; after redeploy, fill field again.
	if ai and ai.has_method("sync_field_for_prepare"):
		ai.sync_field_for_prepare()
	show_notice("已继续上次对局")

func _redeploy_saved_ships(ships: Array) -> void:
	for entry in ships:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sid := int(entry.get("ship_id", 0))
		if sid <= 0:
			continue
		if DataStore.get_ship(sid).is_empty():
			continue
		AdminBus.request(&"board.deploy", {
			"ship_id": sid,
			"star": int(entry.get("star", 1)),
			"team": int(entry.get("team", ShipUnit.TEAM_PLAYER)),
			"slot_type": str(entry.get("slot_type", "hangar")),
			"x": int(entry.get("x", 0)),
			"z": int(entry.get("z", 0)),
		})
		if int(entry.get("field_side_team", -1)) >= 0:
			for s2 in board.all_ships():
				if s2.ship_id == sid and s2.grid_x == int(entry.get("x", 0)) and s2.grid_z == int(entry.get("z", 0)) and s2.slot_type == str(entry.get("slot_type", "hangar")):
					s2.field_side_team = int(entry.get("field_side_team"))
					break
	board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	board.recalculate_fetters(ShipUnit.TEAM_AI)
	_refresh_hud()
	_refresh_shop_ui()

func _on_skip_pressed() -> void:
	match_ctrl.skip_prepare()
	_refresh_hud()

func _on_speed_pressed() -> void:
	match_ctrl.cycle_speed()
	_refresh_hud()
	show_notice("倍速 %s" % match_ctrl.speed_label())

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_pause_pressed() -> void:
	get_tree().paused = not get_tree().paused
	var btn := hud.get_node_or_null("Root/TopRight/PauseBtn") as Button
	if btn:
		btn.text = "继续" if get_tree().paused else "暂停"
	show_notice("已暂停" if get_tree().paused else "继续")

func _on_collapse_left() -> void:
	_collapse_left = not _collapse_left
	_apply_adaptive_hud_layout()

func _on_collapse_right() -> void:
	_collapse_right = not _collapse_right
	_apply_adaptive_hud_layout()

func _on_collapse_bottom() -> void:
	var was_collapsed := _collapse_bottom
	_collapse_bottom = not _collapse_bottom
	_apply_adaptive_hud_layout()
	## Free view: HUD only — never move the camera for shop or stage chrome.
	if _camera_free:
		return
	## Shop expand → view 2. Shop collapse → first default (default mode).
	## Battle: bottom toggle does not move the camera.
	if match_ctrl != null and match_ctrl.stage == MatchController.Stage.BATTLE:
		return
	if was_collapsed and not _collapse_bottom:
		_on_shop_expanded_camera()
	elif not was_collapsed and _collapse_bottom:
		_on_shop_collapsed_camera()

func _on_stage_changed_ui(stage: int) -> void:
	var stage_label := "准备" if stage == MatchController.Stage.PREPARE else ("战斗" if stage == MatchController.Stage.BATTLE else "结束")
	_append_battle_log("进入%s阶段" % stage_label)
	## Battle start: auto-collapse side + bottom chrome; toggles remain available.
	if stage == MatchController.Stage.BATTLE:
		_collapse_left = true
		_collapse_bottom = true
		_cam_pose_before_shop_valid = false
		_cam_pose_before_shop.clear()
		_apply_adaptive_hud_layout()
		## Free view keeps current pose across combat enter.
		if not _camera_free:
			_apply_camera_view_dict(_camera_primary_view())
			## Keep slot grid until camera settles on first default view.
			_show_slot_markers_now()
			_pending_hide_slot_markers = true
		else:
			_hide_slot_markers_now()
	# 回合结束：战斗 -> 准备；展开左栏+底栏一次；default 切视角 2；free 不动镜头。
	if _last_match_stage == MatchController.Stage.BATTLE and stage == MatchController.Stage.PREPARE:
		_collapse_left = false
		_collapse_bottom = false
		_apply_adaptive_hud_layout()
		_show_slot_markers_now()
		if not _camera_free:
			_cam_headup_phase = 0
			_cam_headup_t = 0.0
			_cam_headup_offset_deg = 0.0
			_cam_default_pitch_deg = float(_camera_primary_view().get("pitch_deg", _cam_default_pitch_deg))
			_cam_pose_before_shop = _capture_cam_pose()
			_cam_pose_before_shop_valid = true
			_apply_camera_view_dict(_camera_secondary_view())
	elif not _camera_free:
		_trigger_camera_headup("stage_change")
	_last_match_stage = stage
	_refresh_hud()
	var diag := SessionDiagnostics.instance()
	if diag and diag.has_method("log_event"):
		diag.log_event("stage", stage_label)

func _append_battle_log(text: String) -> void:
	var line := str(text).strip_edges()
	if line.is_empty():
		return
	_battle_log_lines.append(line)
	while _battle_log_lines.size() > _BATTLE_LOG_MAX:
		_battle_log_lines.pop_front()
	_refresh_battle_log_list()

func _refresh_battle_log_list() -> void:
	var list := hud.get_node_or_null("Root/RightCol/RightInner/RightContent/BattleLog/BattleLogInner/BattleLogScroll/BattleLogList") as VBoxContainer
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	for entry in _battle_log_lines:
		var lab := Label.new()
		lab.text = str(entry)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiAssets.apply_label_font(lab, false, UiLayout.font_size(11, list))
		lab.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		list.add_child(lab)
	call_deferred("_scroll_battle_log_to_end")

func _scroll_battle_log_to_end() -> void:
	var scroll := hud.get_node_or_null("Root/RightCol/RightInner/RightContent/BattleLog/BattleLogInner/BattleLogScroll") as ScrollContainer
	if scroll == null:
		return
	var bar := scroll.get_v_scroll_bar()
	if bar:
		scroll.scroll_vertical = int(bar.max_value)
