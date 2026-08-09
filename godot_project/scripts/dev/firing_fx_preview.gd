extends Node3D
## Dev gallery: list every `weapon_fx.json` kind side-by-side via real FiringFx.
## Camera / board pad / HUD pattern reused from lance_fx_preview.gd (COMBAT §8).

const FiringFxScript = preload("res://scripts/combat/firing_fx.gd")
const _CAM_MOVE_SPEED: float = 28.0
const _LOOK_SENS: float = 0.22
const _WHEEL_STEP: float = 3.2
const _REFIRE_S: float = 1.35
const _BEAM_DUR_S: float = 1.15
const _FUNC_DUR_S: float = 2.4
const _COL_GAP: float = 7.2
const _SHOT_LEN: float = 16.0
const _CANNON_TUNE_PATH: String = "res://data/dev/cannon_fx_tune.json"
const _CANNON_BOOST_STEP: float = 0.25
const _CANNON_BOOST_MIN: float = 0.5
const _CANNON_BOOST_MAX: float = 300.0

## Attack kinds use FiringFx.play; function kinds use play_function; mining → play_to_anchor.
const FUNCTION_KINDS: Dictionary = {
	"nos": true,
	"neut": true,
	"remote_cap": true,
	"sensor_damp": true,
	"tracking_disrupt": true,
	"guidance_disrupt": true,
	"target_painter": true,
}

## Gallery firer hulls (small/readable) with turret_anchors sidecar when present.
const KIND_SHIP_ID: Dictionary = {
	"laser": 1,
	"rail": 11,
	"cannon": 21,
	"missile": 16,
	"heal": 12,
	"mining": 135,
	"nos": 1,
	"neut": 1,
	"remote_cap": 12,
	"sensor_damp": 11,
	"tracking_disrupt": 1,
	"guidance_disrupt": 16,
	"target_painter": 11,
}
const TARGET_SHIP_ID: int = 21

var _cam: Camera3D
var _hud: Label
var _cannon_btn: Button
var _firing_fx: FiringFxScript
var _world: Node3D
var _kinds: Array[String] = []
var _firers: Array[ShipUnit] = []
var _targets: Array[ShipUnit] = []
var _anchors: Array[Node3D] = []
var _labels: Array[Label3D] = []
var _selected: int = 0
var _refire_t: float = 0.0
var _paused: bool = false
var _cam_base_pos: Vector3 = Vector3(0, 16, 36)
var _cam_base_pitch_deg: float = -28.0
var _cam_base_yaw_deg: float = 0.0
var _look_dragging: bool = false
var _board_span_x: float = 36.0
var _board_span_z: float = 33.0
## Dedicated cannon brightness arm: W/S nudge emission_boost (COMBAT §8 preview).
var _cannon_tune_armed: bool = false
var cannon_emission_boost: float = 5.0
var _cannon_hold_t: float = 0.0


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	if DataStore != null and DataStore.has_method("reload_all"):
		DataStore.reload_all()
	_collect_kinds()
	_load_cannon_boost()
	_resolve_board_metrics()
	_build_env()
	_build_board_reference()
	_world = Node3D.new()
	_world.name = "FxWorld"
	add_child(_world)
	_firing_fx = FiringFxScript.new()
	_firing_fx.name = "FiringFx"
	add_child(_firing_fx)
	_firing_fx.force_full_fx = true
	_firing_fx.setup(_world)
	_build_gallery()
	_build_hud()
	_fire_all()
	print("[FiringFxPreview] kinds=%d · B/按钮武装加农亮度 · W/S调值 · ←/→选中 · Esc退出" % _kinds.size())


func _resolve_board_metrics() -> void:
	var bb: Vector4 = BoardController.combat_play_bounds_xz(0.0)
	_board_span_x = bb.y - bb.x
	_board_span_z = bb.w - bb.z
	var width: float = maxf(float(_kinds.size()) * _COL_GAP, _board_span_x)
	_cam_base_pos = Vector3(0.0, 18.0, maxf(width * 0.55, 28.0))


func _collect_kinds() -> void:
	_kinds.clear()
	var cfg: Dictionary = DataStore.weapon_fx if DataStore != null else {}
	var kinds_d: Dictionary = TypedVariant.as_dict(cfg.get("kinds", {}))
	var keys: Array = kinds_d.keys()
	keys.sort()
	## Stable gallery order: attack → mining/heal → function (COMBAT §8 / §8.2).
	var prefer: Array[String] = [
		"laser", "rail", "cannon", "missile", "heal", "mining",
		"nos", "neut", "remote_cap", "sensor_damp",
		"tracking_disrupt", "guidance_disrupt", "target_painter",
	]
	var seen: Dictionary = {}
	for k: String in prefer:
		if kinds_d.has(k):
			_kinds.append(k)
			seen[k] = true
	for k_v: Variant in keys:
		var k2: String = str(k_v)
		if TypedVariant.as_bool(seen.get(k2, false), false):
			continue
		_kinds.append(k2)
	if _kinds.is_empty():
		_kinds = ["laser", "rail", "cannon", "missile", "heal", "mining"]


func _build_gallery() -> void:
	var n: int = _kinds.size()
	var origin_x: float = -0.5 * float(n - 1) * _COL_GAP
	var last_role: String = ""
	for i: int in range(n):
		var kind: String = _kinds[i]
		var x: float = origin_x + float(i) * _COL_GAP
		var role: String = _role_for(kind)
		if role != last_role:
			var banner: Label3D = Label3D.new()
			banner.text = "【%s】" % role
			banner.font_size = 36
			banner.outline_size = 10
			banner.modulate = Color(0.75, 0.9, 1.0)
			banner.position = Vector3(x, 4.2, 0.0)
			banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_world.add_child(banner)
			last_role = role
		var firer: ShipUnit = _make_dummy_ship(
			"Firer_%s" % kind,
			Vector3(x, 0.6, _SHOT_LEN * 0.5),
			_ship_id_for_kind(kind),
			ShipUnit.TEAM_PLAYER
		)
		var target: ShipUnit = _make_dummy_ship(
			"Target_%s" % kind,
			Vector3(x, 0.6, -_SHOT_LEN * 0.5),
			TARGET_SHIP_ID,
			ShipUnit.TEAM_AI
		)
		_firers.append(firer)
		_targets.append(target)
		_mark_muzzles(firer)
		var anchor: Node3D = Node3D.new()
		anchor.name = "Anchor_%s" % kind
		anchor.position = Vector3(x, 0.8, -_SHOT_LEN * 0.5)
		_world.add_child(anchor)
		_anchors.append(anchor)
		var pad_f: MeshInstance3D = _make_pad(Color(0.35, 0.75, 1.0, 0.55))
		pad_f.position = firer.global_position + Vector3(0, -0.55, 0)
		_world.add_child(pad_f)
		var pad_t: MeshInstance3D = _make_pad(Color(1.0, 0.45, 0.35, 0.55))
		pad_t.position = target.global_position + Vector3(0, -0.55, 0)
		_world.add_child(pad_t)
		var lab: Label3D = Label3D.new()
		lab.text = _label_for(kind, i)
		lab.font_size = 28
		lab.outline_size = 8
		lab.position = Vector3(x, 3.1, 0.0)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_world.add_child(lab)
		_labels.append(lab)
	_refresh_selection_labels()


func _role_for(kind: String) -> String:
	if FUNCTION_KINDS.has(kind):
		return "装备"
	if kind == "heal":
		return "维修"
	if kind == "mining":
		return "采矿"
	return "开火"


func _label_for(kind: String, index: int) -> String:
	var cfg: Dictionary = TypedVariant.as_dict(
		TypedVariant.as_dict(DataStore.weapon_fx.get("kinds", {})).get(kind, {})
	)
	var style: String = str(cfg.get("style", "?"))
	var look: String = str(cfg.get("look", "solid"))
	return "%d  %s\n%s · %s/%s" % [index + 1, kind, _role_for(kind), style, look]


func _ship_id_for_kind(kind: String) -> int:
	return TypedVariant.as_int(KIND_SHIP_ID.get(kind, 1), 1)


func _make_dummy_ship(p_name: String, pos: Vector3, ship_id: int, team: int) -> ShipUnit:
	var s: ShipUnit = ShipUnit.new()
	s.name = p_name
	s.position = pos
	_world.add_child(s)
	## After enter tree so model / turret_anchors resolve in world space.
	s.setup(ship_id, 1, team)
	s.global_position = pos
	return s


func _mark_muzzles(firer: ShipUnit) -> void:
	if firer == null or not firer.has_method("get_muzzle_locals"):
		return
	var locals: Array = firer.get_muzzle_locals()
	for i: int in range(mini(locals.size(), 8)):
		var p_v: Variant = locals[i]
		if typeof(p_v) != TYPE_VECTOR3:
			continue
		var mi: MeshInstance3D = MeshInstance3D.new()
		var sph: SphereMesh = SphereMesh.new()
		sph.radius = 0.08
		sph.height = 0.16
		mi.mesh = sph
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.85, 0.2, 0.95)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.8, 0.15)
		mat.emission_energy_multiplier = 2.5
		mi.material_override = mat
		firer.add_child(mi)
		@warning_ignore("unsafe_cast")
		mi.position = p_v as Vector3


func _make_pad(color: Color) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.2, 0.08, 1.2)
	mi.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	return mi


func _fire_all() -> void:
	if _firing_fx == null:
		return
	_firing_fx.clear_all()
	for i: int in range(_kinds.size()):
		_fire_index(i)


func _fire_index(i: int) -> void:
	if i < 0 or i >= _kinds.size():
		return
	var kind: String = _kinds[i]
	var firer: ShipUnit = _firers[i]
	var target: ShipUnit = _targets[i]
	if firer == null or not is_instance_valid(firer):
		return
	if kind == "mining":
		var anchor: Node3D = _anchors[i]
		_firing_fx.play_to_anchor(firer, anchor, "mining", _BEAM_DUR_S)
		if firer.has_method("advance_muzzle"):
			firer.advance_muzzle()
		return
	if FUNCTION_KINDS.has(kind):
		if target != null and is_instance_valid(target):
			_firing_fx.play_function(firer, target, kind, _FUNC_DUR_S)
		if firer.has_method("advance_muzzle"):
			firer.advance_muzzle()
		return
	if target != null and is_instance_valid(target):
		_firing_fx.play(firer, target, kind, _BEAM_DUR_S)
		if firer.has_method("advance_muzzle"):
			firer.advance_muzzle()


func _process(delta: float) -> void:
	_drive_camera(delta)
	_tick_cannon_tune(delta)
	if _paused:
		return
	_refire_t += delta
	if _refire_t >= _REFIRE_S:
		_refire_t = 0.0
		_fire_all()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ek: InputEventKey = event
		if ek.pressed and not ek.echo:
			if ek.keycode == KEY_ESCAPE:
				get_tree().quit()
				return
			if ek.keycode == KEY_B:
				_toggle_cannon_tune()
				get_viewport().set_input_as_handled()
				return
			if ek.keycode == KEY_W or ek.keycode == KEY_S:
				if _cannon_tune_armed:
					## Continuous nudge in _process while held.
					get_viewport().set_input_as_handled()
					return
			if ek.keycode == KEY_SPACE:
				_paused = not _paused
				_refresh_hud()
				get_viewport().set_input_as_handled()
				return
			if ek.keycode == KEY_R:
				_refire_t = 0.0
				_fire_all()
				_refresh_hud()
				get_viewport().set_input_as_handled()
				return
			if ek.keycode == KEY_LEFT or ek.keycode == KEY_A:
				_selected = (_selected - 1 + _kinds.size()) % maxi(_kinds.size(), 1)
				_refresh_selection_labels()
				_refresh_hud()
				get_viewport().set_input_as_handled()
				return
			if ek.keycode == KEY_RIGHT or ek.keycode == KEY_D:
				_selected = (_selected + 1) % maxi(_kinds.size(), 1)
				_refresh_selection_labels()
				_refresh_hud()
				get_viewport().set_input_as_handled()
				return
			if ek.keycode == KEY_ENTER or ek.keycode == KEY_F:
				_fire_index(_selected)
				get_viewport().set_input_as_handled()
				return
			## Digits 1–9 jump to slot.
			if ek.keycode >= KEY_1 and ek.keycode <= KEY_9:
				var idx: int = int(ek.keycode - KEY_1)
				if idx < _kinds.size():
					_selected = idx
					_fire_index(_selected)
					_refresh_selection_labels()
					_refresh_hud()
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


func _refresh_selection_labels() -> void:
	for i: int in range(_labels.size()):
		var lab: Label3D = _labels[i]
		if lab == null or not is_instance_valid(lab):
			continue
		var kind: String = _kinds[i] if i < _kinds.size() else "?"
		var mark: String = "▶ " if i == _selected else ""
		lab.text = "%s%s" % [mark, _label_for(kind, i)]
		lab.modulate = Color(1.2, 1.15, 0.7) if i == _selected else Color.WHITE


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	_cannon_btn = Button.new()
	_cannon_btn.text = "加农亮度"
	_cannon_btn.tooltip_text = "武装后用 W/S 调 cannon emission_boost"
	_cannon_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_cannon_btn.offset_left = -168.0
	_cannon_btn.offset_top = 12.0
	_cannon_btn.offset_right = -12.0
	_cannon_btn.offset_bottom = 48.0
	_cannon_btn.pressed.connect(_toggle_cannon_tune)
	layer.add_child(_cannon_btn)
	_hud = Label.new()
	_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud.offset_left = 12
	_hud.offset_top = 10
	_hud.offset_right = 920
	_hud.offset_bottom = 300
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)
	_refresh_hud()


func _refresh_hud() -> void:
	if _hud == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("开火 / 维修 / 装备特效 · TQ 贴图照搬 · FiringFxPreview")
	lines.append("炮台 laser/rail/cannon：近远贴图交替（pulse↔beam / blast↔rail / auto↔artil）")
	lines.append("←/→选中 · Enter/F单播 · R重播 · Space暂停 · Esc退出")
	lines.append(
		"加农亮度：按钮或 B 武装 · W/S 调 emission_boost=%.2f · 武装=%s" % [
			cannon_emission_boost,
			"开" if _cannon_tune_armed else "关",
		]
	)
	lines.append("暂停=%s · 选中=%d/%d · %s" % [
		"是" if _paused else "否",
		_selected + 1,
		_kinds.size(),
		_kinds[_selected] if _selected < _kinds.size() else "?",
	])
	lines.append("--- kinds (%d) ---" % _kinds.size())
	for i: int in range(_kinds.size()):
		var kind: String = _kinds[i]
		var cfg: Dictionary = TypedVariant.as_dict(
			TypedVariant.as_dict(DataStore.weapon_fx.get("kinds", {})).get(kind, {})
		)
		var mark: String = ">" if i == _selected else " "
		var nf: String = ""
		if TypedVariant.as_bool(cfg.get("alternate_near_far", false), false):
			nf = "近%s↔远%s" % [str(cfg.get("role_near", "?")), str(cfg.get("role_far", "?"))]
		var boost_s: String = ""
		if kind == "cannon":
			boost_s = "emit=%.2f" % TypedVariant.as_float(cfg.get("emission_boost", cannon_emission_boost), cannon_emission_boost)
		lines.append(
			"%s %2d  %-18s  %-6s  look=%-12s  %s  %s  %s" % [
				mark,
				i + 1,
				kind,
				_role_for(kind),
				str(cfg.get("look", "solid")),
				nf,
				boost_s,
				str(cfg.get("evemu_effect", "")),
			]
		)
	_hud.text = "\n".join(lines)
	if _cannon_btn != null:
		_cannon_btn.text = "加农亮度 · %.2f%s" % [
			cannon_emission_boost,
			" ●" if _cannon_tune_armed else "",
		]
		_cannon_btn.modulate = Color(1.0, 0.85, 0.45) if _cannon_tune_armed else Color.WHITE


func _load_cannon_boost() -> void:
	## Tune file wins — never let weapon_fx.json defaults clobber a player-tuned value.
	var base: float = 5.0
	var from_tune: bool = false
	if FileAccess.file_exists(_CANNON_TUNE_PATH):
		var raw: String = FileAccess.get_file_as_string(_CANNON_TUNE_PATH)
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			@warning_ignore("unsafe_cast")
			var tune: Dictionary = parsed as Dictionary
			if tune.has("emission_boost"):
				base = TypedVariant.as_float(tune.get("emission_boost", base), base)
				from_tune = true
	if not from_tune and DataStore != null:
		var kinds: Dictionary = TypedVariant.as_dict(DataStore.weapon_fx.get("kinds", {}))
		var cannon: Dictionary = TypedVariant.as_dict(kinds.get("cannon", {}))
		base = TypedVariant.as_float(cannon.get("emission_boost", base), base)
	set_cannon_emission_boost(base)


func _toggle_cannon_tune() -> void:
	_cannon_tune_armed = not _cannon_tune_armed
	if _cannon_tune_armed:
		for i: int in range(_kinds.size()):
			if _kinds[i] == "cannon":
				_selected = i
				break
		_refresh_selection_labels()
		_fire_index(_selected)
	_cannon_hold_t = 0.0
	_refresh_hud()
	print("[FiringFxPreview] cannon tune armed=%s boost=%.2f" % [_cannon_tune_armed, cannon_emission_boost])


func set_cannon_emission_boost(v: float) -> void:
	cannon_emission_boost = clampf(v, _CANNON_BOOST_MIN, _CANNON_BOOST_MAX)
	if DataStore != null:
		var kinds: Dictionary = TypedVariant.as_dict(DataStore.weapon_fx.get("kinds", {}))
		var cannon: Dictionary = TypedVariant.as_dict(kinds.get("cannon", {}))
		cannon["emission_boost"] = cannon_emission_boost
		kinds["cannon"] = cannon
		DataStore.weapon_fx["kinds"] = kinds
	_persist_cannon_tune()
	_refresh_hud()


func _persist_cannon_tune() -> void:
	var abs_path: String = ProjectSettings.globalize_path(_CANNON_TUNE_PATH)
	var dir_path: String = abs_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var f: FileAccess = FileAccess.open(_CANNON_TUNE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"emission_boost": cannon_emission_boost,
		"_comment": "FiringFxPreview cannon brightness; W/S while armed (B / 加农亮度按钮)",
	}, "\t"))
	f.close()


func _tick_cannon_tune(delta: float) -> void:
	if not _cannon_tune_armed:
		_cannon_hold_t = 0.0
		return
	var dir: float = 0.0
	if Input.is_physical_key_pressed(KEY_W):
		dir += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		dir -= 1.0
	if dir == 0.0:
		_cannon_hold_t = 0.0
		return
	## Lance-style: one step on press, then repeat while held.
	if _cannon_hold_t <= 0.0:
		_nudge_cannon_boost(dir)
		_cannon_hold_t = 0.001
	else:
		_cannon_hold_t += delta
		if _cannon_hold_t >= 0.11:
			_cannon_hold_t = 0.001
			_nudge_cannon_boost(dir)


func _nudge_cannon_boost(dir: float) -> void:
	set_cannon_emission_boost(cannon_emission_boost + _CANNON_BOOST_STEP * dir)
	_fire_index(_selected)
	print("[FiringFxPreview] cannon emission_boost=%.2f" % cannon_emission_boost)


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
	env.glow_intensity = 0.65
	env.glow_bloom = 0.22
	amb.environment = env
	add_child(amb)
	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)
	_apply_cam()


func _build_board_reference() -> void:
	var half_x: float = maxf(_board_span_x, float(_kinds.size()) * _COL_GAP) * 0.5
	var half_z: float = maxf(_board_span_z, _SHOT_LEN + 4.0) * 0.5
	var pad: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(half_x * 2.0, 0.06, half_z * 2.0)
	pad.mesh = box
	var pm: StandardMaterial3D = StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(0.1, 0.12, 0.16, 0.85)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pad.material_override = pm
	pad.position = Vector3(0, -0.03, 0)
	add_child(pad)
	var note: Label3D = Label3D.new()
	note.text = "开火/维修/装备 kinds 全量 · 蓝垫=开火舰 · 红垫=目标 · 黄点=SOF炮口"
	note.font_size = 32
	note.outline_size = 8
	note.position = Vector3(0, 0.25, half_z + 2.2)
	note.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(note)


func _drive_camera(delta: float) -> void:
	var move: Vector3 = Vector3.ZERO
	## W/S reserved for cannon emission_boost when tune armed.
	if Input.is_key_pressed(KEY_UP):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		move.z += 1.0
	if Input.is_key_pressed(KEY_Q):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		move.y += 1.0
	if move != Vector3.ZERO:
		var cam_basis: Basis = Basis.from_euler(
			Vector3(deg_to_rad(_cam_base_pitch_deg), deg_to_rad(_cam_base_yaw_deg), 0.0)
		)
		_cam_base_pos += cam_basis * move.normalized() * _CAM_MOVE_SPEED * delta
		_apply_cam()


func _apply_cam() -> void:
	if _cam == null:
		return
	_cam.position = _cam_base_pos
	_cam.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
