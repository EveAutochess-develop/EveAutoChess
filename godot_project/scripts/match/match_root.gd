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
var _long_press_t: float = 0.0
var _long_press_slot: int = -1
var _dragging_sell_ui: bool = false
var _cam_base_pos: Vector3 = Vector3.ZERO
var _cam_base_pitch_deg: float = -55.0
var _cam_base_yaw_deg: float = 0.0
var _citadel_hp_bar: Node3D = null
const _CITADEL_BAR_SCRIPT := preload("res://scripts/ship/citadel_health_bar.gd")
const _CAM_MOVE_SPEED := 8.0
const _CAM_PITCH_SPEED := 35.0
const _CAM_YAW_SPEED := 45.0

func _ready() -> void:
	add_to_group("match_root")
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
	match_ctrl.stage_changed.connect(func(_s): _refresh_hud())
	shop.shop_changed.connect(_refresh_shop_ui)
	var mode := GameSession.pending_mode
	_spawn_map_env(mode)
	match_ctrl.start_match(mode)
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
		mat.energy_multiplier = 1.25
		sky.sky_material = mat
		environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.74, 0.78)
	environment.ambient_light_energy = 1.15
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.15
	environment.tonemap_white = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.12
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.06
	environment.glow_enabled = false
	environment.ssao_enabled = false
	we.environment = environment
	add_child(we)
	_ensure_board_lights()

func _ensure_board_lights() -> void:
	## Off-frustum lights — brighter for readability without crushing hull detail.
	if get_node_or_null("KeyLightOffscreen") == null:
		var key := DirectionalLight3D.new()
		key.name = "KeyLightOffscreen"
		key.light_energy = 1.25
		key.light_color = Color(1.0, 0.98, 0.94)
		key.shadow_enabled = true
		key.shadow_opacity = 0.45
		key.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
		add_child(key)
	if get_node_or_null("RimLightOffscreen") == null:
		var rim := DirectionalLight3D.new()
		rim.name = "RimLightOffscreen"
		rim.light_energy = 0.55
		rim.light_color = Color(0.65, 0.8, 1.0)
		rim.shadow_enabled = false
		rim.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
		add_child(rim)
	if get_node_or_null("FillLight") == null:
		var fill := OmniLight3D.new()
		fill.name = "FillLight"
		fill.light_energy = 0.55
		fill.omni_range = 85.0
		fill.position = Vector3(0, 32, 10)
		add_child(fill)
	if get_node_or_null("FillLightAI") == null:
		var fill_ai := OmniLight3D.new()
		fill_ai.name = "FillLightAI"
		fill_ai.light_energy = 0.42
		fill_ai.light_color = Color(0.88, 0.92, 1.0)
		fill_ai.omni_range = 60.0
		fill_ai.position = Vector3(-16.0, 24.0, -18.0)
		add_child(fill_ai)
	if get_node_or_null("FillLightPlayer") == null:
		var fill_p := OmniLight3D.new()
		fill_p.name = "FillLightPlayer"
		fill_p.light_energy = 0.42
		fill_p.light_color = Color(1.0, 0.96, 0.9)
		fill_p.omni_range = 60.0
		fill_p.position = Vector3(16.0, 24.0, 18.0)
		add_child(fill_p)
	var scene_key := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if scene_key:
		scene_key.light_energy = 1.05
		scene_key.shadow_opacity = 0.4

func _setup_camera() -> void:
	## Default framing; QAWSED translate, RF pitch, TG yaw orbit; breathe on base pose.
	var v := DataStore.visual
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = float(v.get("camera_fov", 47.0))
	var dist := float(v.get("camera_distance", 18.067))
	var height := float(v.get("camera_height", 21.464))
	var cam_x := float(v.get("camera_x", -2.0))
	var unity_pitch := float(v.get("camera_angle_deg", 57.0))
	var unity_yaw := float(v.get("camera_yaw_deg", 180.0))
	_cam_base_pos = Vector3(cam_x, height, dist)
	_cam_base_pitch_deg = -unity_pitch
	_cam_base_yaw_deg = unity_yaw - 180.0
	camera.position = _cam_base_pos
	camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0)

func _process(delta: float) -> void:
	_update_camera_free(delta)
	_update_camera_breathe()

func _update_camera_free(delta: float) -> void:
	# QAWSED: world 6-way · RF: pitch · TG: yaw orbit about board origin
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		move.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_E):
		move.y += 1.0
	if move != Vector3.ZERO:
		_cam_base_pos += move.normalized() * _CAM_MOVE_SPEED * delta
	var pitch_delta := 0.0
	if Input.is_physical_key_pressed(KEY_R):
		pitch_delta += _CAM_PITCH_SPEED * delta
	if Input.is_physical_key_pressed(KEY_F):
		pitch_delta -= _CAM_PITCH_SPEED * delta
	if pitch_delta != 0.0:
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg + pitch_delta, -89.0, -5.0)
	var yaw_delta := 0.0
	if Input.is_physical_key_pressed(KEY_T):
		yaw_delta -= _CAM_YAW_SPEED * delta
	if Input.is_physical_key_pressed(KEY_G):
		yaw_delta += _CAM_YAW_SPEED * delta
	if yaw_delta != 0.0:
		var rad := deg_to_rad(yaw_delta)
		var p := _cam_base_pos
		var c := cos(rad)
		var s := sin(rad)
		_cam_base_pos = Vector3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c)
		_cam_base_yaw_deg += yaw_delta
	if move != Vector3.ZERO or pitch_delta != 0.0 or yaw_delta != 0.0:
		camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0)

func _update_camera_breathe() -> void:
	var v := DataStore.visual
	if not bool(v.get("camera_breathe_enabled", true)):
		camera.position = _cam_base_pos
		return
	var period := maxf(0.5, float(v.get("camera_breathe_period_s", 12.0)))
	var amp := float(v.get("camera_breathe_amp", 0.35))
	var th := Time.get_ticks_msec() * 0.001 * TAU / period
	var s := sin(th)
	var c := cos(th)
	# Diagonal figure-8 (lemniscate) with light vertical breathe, rotated 45° on Y.
	var local := Vector3(s, 0.15 * s, s * c) * amp
	var half := 0.70710678
	var offset := Vector3(
		local.x * half - local.z * half,
		local.y,
		local.x * half + local.z * half
	)
	camera.position = _cam_base_pos + offset

func _build_hud() -> void:
	_style_hud_chrome()
	_wire_shop_chrome()
	var pause := hud.get_node_or_null("Root/TopRight/PauseBtn") as Button
	if pause:
		pause.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.process_mode = Node.PROCESS_MODE_ALWAYS

func _style_hud_chrome() -> void:
	var root := hud.get_node_or_null("Root") as Control
	if root == null:
		return
	for lbl_path in ["Hp", "Phase", "Placement/TimerCol/Timer", "Placement/TimerCol/StageHint", "Notice",
			"Shop/ShopCol/MetaRow/LevelExp/LEInner/LELabels/Level",
			"Shop/ShopCol/MetaRow/LevelExp/LEInner/LELabels/Exp",
			"Shop/ShopCol/MetaRow/PopBox/Pop", "Shop/ShopCol/MetaRow/GoldBox/Gold", "TopRight/Version"]:
		var l := root.get_node_or_null(lbl_path) as Label
		if l:
			var fs := 28 if "Timer" in lbl_path else (20 if "Shop/" in lbl_path else 16)
			UiAssets.apply_label_font(l, false, fs)
			l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			l.add_theme_constant_override("outline_size", 4)
	var shop_panel := root.get_node_or_null("Shop") as PanelContainer
	if shop_panel:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.09, 0.11, 0.88)
		sb.border_color = Color(0.35, 0.72, 0.85, 0.55)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(10)
		shop_panel.add_theme_stylebox_override("panel", sb)
	var info := root.get_node_or_null("InfoPanel") as PanelContainer
	if info:
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = Color(0.12, 0.13, 0.15, 0.95)
		sb2.set_corner_radius_all(6)
		sb2.set_content_margin_all(14)
		info.add_theme_stylebox_override("panel", sb2)
	var skip := root.get_node_or_null("Placement/SkipBtn") as Button
	if skip:
		UiAssets.apply_button_font(skip, 16)

func _wire_shop_chrome() -> void:
	var root := hud.get_node_or_null("Root")
	if root == null:
		return
	_style_image_button(root.get_node_or_null("Shop/ShopCol/ShopInner/LeftBtns/ExpBtn") as Button,
			UiAssets.shop_exp_path(), "升级", int(DataStore.economy.get("buy_exp_gold_cost", 4)))
	_style_image_button(root.get_node_or_null("Shop/ShopCol/ShopInner/LeftBtns/RefreshBtn") as Button,
			UiAssets.shop_refresh_path(), "刷新", int(DataStore.economy.get("refresh_cost", 2)))
	var lock := root.get_node_or_null("Shop/ShopCol/MetaRow/LockBtn") as Button
	if lock:
		var t := UiAssets.tex(UiAssets.ICON_LOCK)
		if t:
			lock.icon = t
			lock.expand_icon = true
		lock.text = ""
		UiAssets.apply_button_font(lock, 16)
		lock.custom_minimum_size = Vector2(48, 40)
	_ensure_meta_icon(root.get_node_or_null("Shop/ShopCol/MetaRow/GoldBox") as HBoxContainer, "Gold", UiAssets.ICON_MONEY)
	_ensure_meta_icon(root.get_node_or_null("Shop/ShopCol/MetaRow/PopBox") as HBoxContainer, "Pop", UiAssets.ICON_POP)
	var bar := root.get_node_or_null("Shop/ShopCol/MetaRow/LevelExp/LEInner/ExpBar") as ProgressBar
	if bar:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.0, 0.6, 1.0, 1.0)
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.0, 0.4, 0.7, 0.25)
		bar.add_theme_stylebox_override("background", bg)
	var sell := root.get_node_or_null("Shop/ShopCol/ShopInner/SellZone") as PanelContainer
	if sell:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.22, 0.25, 0.92)
		sb.border_color = Color(0.4, 0.75, 0.9, 0.7)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sell.add_theme_stylebox_override("panel", sb)

func _ensure_meta_icon(box: HBoxContainer, for_name: String, tex_path: String) -> void:
	if box == null:
		return
	for c in box.get_children():
		if c is TextureRect and c.has_meta("meta_icon_for") and str(c.get_meta("meta_icon_for")) == for_name:
			return
	var icon := TextureRect.new()
	icon.set_meta("meta_icon_for", for_name)
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var t := UiAssets.tex(tex_path)
	if t:
		icon.texture = t
	box.add_child(icon)
	box.move_child(icon, 0)

func _style_image_button(btn: Button, tex_path: String, title: String, cost: int) -> void:
	if btn == null:
		return
	# Image-only: art fills the control; cost stays in tooltip / accessibility.
	btn.text = ""
	btn.tooltip_text = "%s  %d" % [title, cost]
	var t := UiAssets.tex(tex_path)
	if t:
		btn.icon = t
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.custom_minimum_size = Vector2(0, 72)
	btn.add_theme_constant_override("icon_max_width", 0)

func show_notice(text: String) -> void:
	AdminBus.request(&"ui.notice", {"text": text})
	var lbl := hud.get_node_or_null("Root/Notice") as Label
	if lbl:
		lbl.text = text
		lbl.visible = true
		get_tree().create_timer(2.0).timeout.connect(func(): if lbl: lbl.visible = false)

func on_ship_sold(gold: int) -> void:
	match_ctrl.add_gold(gold)
	show_notice("出售获得 %d PLEX" % gold)
	board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	_refresh_hud()

func _refresh_hud() -> void:
	var root := hud.get_node_or_null("Root")
	if root == null:
		return
	_set_label(root, "Hp", "HP %d" % match_ctrl.player_hp)
	_refresh_citadel_bar()
	_set_label(root, "Phase", "阶段 %d-%d" % [match_ctrl.battle_phase_value, match_ctrl.round_phase_value])
	_set_label(root, "Shop/ShopCol/MetaRow/GoldBox/Gold", "%d" % match_ctrl.player_gold)
	_set_label(root, "Shop/ShopCol/MetaRow/PopBox/Pop", "%d/%d" % [board.count_field(ShipUnit.TEAM_PLAYER), match_ctrl.population_limit()])
	_set_label(root, "Shop/ShopCol/MetaRow/LevelExp/LEInner/LELabels/Level", "%d级" % match_ctrl.player_level)
	_set_label(root, "Shop/ShopCol/MetaRow/LevelExp/LEInner/LELabels/Exp", "%d / %d" % [match_ctrl.player_exp, match_ctrl.up_level_demand])
	var bar := root.get_node_or_null("Shop/ShopCol/MetaRow/LevelExp/LEInner/ExpBar") as ProgressBar
	if bar:
		bar.max_value = maxf(1.0, float(match_ctrl.up_level_demand))
		bar.value = float(match_ctrl.player_exp)
	var lock := root.get_node_or_null("Shop/ShopCol/MetaRow/LockBtn") as Button
	if lock:
		lock.set_pressed_no_signal(match_ctrl.shop_locked)
	var stage_name := "准备" if match_ctrl.stage == MatchController.Stage.PREPARE else ("战斗" if match_ctrl.stage == MatchController.Stage.BATTLE else "结束")
	var ttext := "倒计时"
	if match_ctrl.stage == MatchController.Stage.PREPARE:
		ttext = "%.0f" % match_ctrl.prepare_remaining()
	elif match_ctrl.stage == MatchController.Stage.BATTLE:
		ttext = "%.0f" % match_ctrl.battle_elapsed()
	_set_label(root, "Placement/TimerCol/Timer", ttext)
	_set_label(root, "Placement/TimerCol/StageHint", stage_name)
	var skip := root.get_node_or_null("Placement/SkipBtn") as Button
	if skip:
		skip.visible = match_ctrl.stage == MatchController.Stage.PREPARE
		skip.disabled = match_ctrl.stage != MatchController.Stage.PREPARE
	_refresh_fetter_ui(root)
	var ver := root.get_node_or_null("TopRight/Version") as Label
	if ver:
		ver.text = "壳 %s | 热更 %s" % [str(ProjectSettings.get_setting("application/config/version", "dev")), DataStore.content_version]

func _refresh_fetter_ui(root: Node) -> void:
	var side := root.get_node_or_null("BonusContainer") as VBoxContainer
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
	var fetters := board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	for a in fetters:
		var fid := str(a.get("fetter_id", ""))
		var fdata: Dictionary = DataStore.fetters.get(fid, {})
		var fname := str(fdata.get("name", fid))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var tex := UiAssets.fetter_icon(fname)
		if tex:
			icon.texture = tex
		row.add_child(icon)
		var lab := Label.new()
		lab.text = "%s %d" % [fname, int(a.get("count", 0))]
		UiAssets.apply_label_font(lab, false, 16)
		lab.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lab.add_theme_constant_override("outline_size", 3)
		row.add_child(lab)
		list.add_child(row)

func _set_label(root: Node, path: String, text: String) -> void:
	var l := root.get_node_or_null(path) as Label
	if l:
		l.text = text

func _refresh_shop_ui() -> void:
	var box := hud.get_node_or_null("Root/Shop/ShopCol/ShopInner/ShopSlots") as VBoxContainer
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	for i in range(shop.slots.size()):
		var slot: Dictionary = shop.slots[i]
		var sid := int(slot.get("ship_id", 0))
		var ship := DataStore.get_ship(sid)
		var purchased := bool(slot.get("purchased", false))
		var ship_name := str(ship.get("name", "?"))
		var cost := int(ship.get("cost", 0))
		var card := _make_shop_card(ship_name, ship, purchased, cost, i)
		box.add_child(card)
	if not _dragging_sell_ui:
		_set_sell_mode(false)

func _make_shop_card(ship_name: String, ship: Dictionary, purchased: bool, cost: int, idx: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 118)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var outer := StyleBoxFlat.new()
	outer.bg_color = Color(0.26, 0.29, 0.3, 0.98)
	outer.border_color = Color(0.31, 0.42, 0.47, 0.95)
	outer.set_border_width_all(2)
	outer.set_corner_radius_all(3)
	outer.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", outer)
	var body := PanelContainer.new()
	var face := StyleBoxFlat.new()
	face.bg_color = Color(0.31, 0.42, 0.47, 0.85)
	face.set_content_margin_all(6)
	body.add_theme_stylebox_override("panel", face)
	card.add_child(body)
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 6)
	body.add_child(root_v)
	if purchased:
		var done := Label.new()
		done.text = "已购"
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		done.size_flags_vertical = Control.SIZE_EXPAND_FILL
		UiAssets.apply_label_font(done, false, 24)
		root_v.add_child(done)
		return card
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root_v.add_child(top)
	var fetter_col := VBoxContainer.new()
	fetter_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fetter_col.add_theme_constant_override("separation", 4)
	top.add_child(fetter_col)
	var fids: Array = ship.get("fetter_ids", [])
	for fid in fids:
		var fdata: Dictionary = DataStore.fetters.get(str(fid), {})
		var fname := str(fdata.get("name", fid))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var fic := TextureRect.new()
		fic.custom_minimum_size = Vector2(22, 22)
		fic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var ft := UiAssets.fetter_icon(fname)
		if ft:
			fic.texture = ft
		row.add_child(fic)
		var fl := Label.new()
		fl.text = fname
		UiAssets.apply_label_font(fl, false, 15)
		fl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
		row.add_child(fl)
		fetter_col.add_child(row)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(76, 76)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := UiAssets.champion_icon(ship_name)
	if tex:
		portrait.texture = tex
	top.add_child(portrait)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	root_v.add_child(bottom)
	var name_l := Label.new()
	name_l.text = ship_name
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(name_l, false, 17)
	name_l.add_theme_color_override("font_color", Color(1, 1, 1))
	bottom.add_child(name_l)
	var money := TextureRect.new()
	money.custom_minimum_size = Vector2(20, 20)
	money.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	money.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var mt := UiAssets.tex(UiAssets.ICON_MONEY)
	if mt:
		money.texture = mt
	bottom.add_child(money)
	var cost_l := Label.new()
	cost_l.text = str(cost)
	UiAssets.apply_label_font(cost_l, false, 18)
	cost_l.add_theme_color_override("font_color", Color(1, 1, 1))
	bottom.add_child(cost_l)
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.pressed.connect(func(): shop.try_buy(idx); _refresh_shop_ui(); _refresh_hud())
	hit.mouse_entered.connect(func(): _show_ship_info_id(int(ship.get("id", 0))))
	hit.gui_input.connect(func(ev): _shop_gui_input(ev, idx))
	card.add_child(hit)
	return card

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
	var slots := hud.get_node_or_null("Root/Shop/ShopCol/ShopInner/ShopSlots") as Control
	var sell := hud.get_node_or_null("Root/Shop/ShopCol/ShopInner/SellZone") as PanelContainer
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
		price = int(DataStore.get_ship(ship.ship_id).get("cost", 0))
	_set_sell_mode(true, price)

func _on_drag_move(world_pos: Vector3) -> void:
	board.update_drag(world_pos)

func _on_drag_end(sell: bool, slot: Dictionary) -> void:
	board.end_drag(sell, slot)
	board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
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

func _fill_info_panel(ship_name: String, star: int, shield_txt: String, armor_txt: String, structure_txt: String, dmg: Dictionary, atk_range, fetter_ids: Array) -> void:
	var p := hud.get_node_or_null("Root/InfoPanel") as PanelContainer
	if p == null:
		return
	var icon := p.get_node_or_null("InfoBody/InfoTop/InfoIcon") as TextureRect
	var title := p.get_node_or_null("InfoBody/InfoTop/InfoTitleCol/InfoTitle") as Label
	var fetter_box := p.get_node_or_null("InfoBody/InfoFetters") as VBoxContainer
	var sh := p.get_node_or_null("InfoBody/InfoShield") as Label
	var ar := p.get_node_or_null("InfoBody/InfoArmor") as Label
	var st := p.get_node_or_null("InfoBody/InfoStructure") as Label
	var dm := p.get_node_or_null("InfoBody/InfoDmg") as Label
	var rg := p.get_node_or_null("InfoBody/InfoRange") as Label
	if icon:
		icon.texture = UiAssets.champion_icon(ship_name)
	if title:
		title.text = "%s  ★%d" % [ship_name, star]
		UiAssets.apply_label_font(title, true, 22)
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
			var ft := UiAssets.fetter_icon(fname)
			if ft:
				fic.texture = ft
			row.add_child(fic)
			var fl := Label.new()
			fl.text = fname
			UiAssets.apply_label_font(fl, false, 15)
			row.add_child(fl)
			fetter_box.add_child(row)
	if sh:
		sh.text = "护盾  %s" % shield_txt
		UiAssets.apply_label_font(sh, false, 16)
	if ar:
		ar.text = "装甲  %s" % armor_txt
		UiAssets.apply_label_font(ar, false, 16)
	if st:
		st.text = "结构  %s" % structure_txt
		UiAssets.apply_label_font(st, false, 16)
	if dm:
		dm.text = "电磁 %s  热能 %s\n动能 %s  爆炸 %s" % [
			str(dmg.get("emp", 0)), str(dmg.get("thermal", 0)),
			str(dmg.get("kinetic", 0)), str(dmg.get("explosive", 0))
		]
		UiAssets.apply_label_font(dm, false, 15)
	if rg:
		rg.text = "射程  %s" % str(atk_range)
		UiAssets.apply_label_font(rg, false, 16)
	p.visible = true

func _show_ship_info(ship: ShipUnit) -> void:
	_info_ship = ship
	if ship == null:
		return
	var data := DataStore.get_ship(ship.ship_id)
	_fill_info_panel(
		str(data.get("name", "?")),
		ship.star,
		"%.0f/%.0f" % [ship.shield_hp, ship.max_shield],
		"%.0f/%.0f" % [ship.armor_hp, ship.max_armor],
		"%.0f/%.0f" % [ship.structure_hp, ship.max_structure],
		{"emp": ship.damage_emp, "thermal": 0, "kinetic": 0, "explosive": 0},
		ship.attack_range,
		data.get("fetter_ids", [])
	)

func _show_ship_info_id(ship_id: int) -> void:
	var st := DataStore.get_star(ship_id, 1)
	var data := DataStore.get_ship(ship_id)
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
		data.get("fetter_ids", [])
	)

func _hide_ship_info() -> void:
	var p := hud.get_node_or_null("Root/InfoPanel") as PanelContainer
	if p:
		p.visible = false

func _on_match_over(summary: String) -> void:
	show_notice(summary)
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
	match_ctrl.buy_exp()
	_refresh_hud()

func _on_skip_pressed() -> void:
	match_ctrl.skip_prepare()
	_refresh_hud()

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_pause_pressed() -> void:
	get_tree().paused = not get_tree().paused
	var btn := hud.get_node_or_null("Root/TopRight/PauseBtn") as Button
	if btn:
		btn.text = "继续" if get_tree().paused else "暂停"
	show_notice("已暂停" if get_tree().paused else "继续")
