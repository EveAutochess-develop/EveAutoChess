extends Node3D
## Extra FX (trail, pulse, green) off when (PlayerSettings.instance() as PlayerSettings).no_model_perf_mode.
## Local narrowers: this script is preloaded by ShipUnit before global class_name may resolve.

static func __as_bool(v: Variant, default_val: bool = false) -> bool:
	match typeof(v):
		TYPE_BOOL:
			@warning_ignore("unsafe_cast")
			return v as bool
		TYPE_INT:
			@warning_ignore("unsafe_cast")
			return (v as int) != 0
		TYPE_FLOAT:
			@warning_ignore("unsafe_cast")
			return (v as float) != 0.0
		TYPE_STRING:
			var s: String = str(v)
			return s == "true" or s == "1"
		_:
			return default_val


static func __as_int(v: Variant, default_val: int = 0) -> int:
	match typeof(v):
		TYPE_INT:
			@warning_ignore("unsafe_cast")
			return v as int
		TYPE_FLOAT:
			@warning_ignore("unsafe_cast")
			return int(v as float)
		TYPE_STRING:
			if str(v).is_valid_int():
				return int(str(v))
			return default_val
		_:
			return default_val


static func __as_float(v: Variant, default_val: float = 0.0) -> float:
	match typeof(v):
		TYPE_FLOAT:
			@warning_ignore("unsafe_cast")
			return v as float
		TYPE_INT:
			@warning_ignore("unsafe_cast")
			return float(v as int)
		TYPE_STRING:
			if str(v).is_valid_float():
				return float(str(v))
			return default_val
		_:
			return default_val


static func __as_dict(v: Variant, default_val: Dictionary = {}) -> Dictionary:
	if typeof(v) == TYPE_DICTIONARY:
		@warning_ignore("unsafe_cast")
		return (v as Dictionary).duplicate(true)
	return default_val.duplicate(true)


static func __mesh(v: Variant) -> MeshInstance3D:
	if v is MeshInstance3D:
		@warning_ignore("unsafe_cast")
		return v as MeshInstance3D
	return null


const BAR_W: float = 1.4
const BAR_H: float = 0.12
const BAR_GAP: float = 0.10
const BAR_COUNT: int = 4
const BADGE_SIZE: float = 0.8
const BADGE_WORLD_SIZE: float = 0.36
const BADGE_PIXEL_SIZE: float = 0.024
const OVERLAY_BG_WORLD_SIZE: float = BADGE_WORLD_SIZE * 1.5
const OVERLAY_TAG_WORLD_SIZE: float = BADGE_WORLD_SIZE * 0.46 * (2.0 / 3.0)
const OVERLAY_TAG_OFFSET: float = BADGE_WORLD_SIZE * 0.5
## HP stack band: wide enough for three distinct concentric half-rings.
## Cap sector uses the same INNER..OUTER so its radial thickness matches the full three-pipe stack.
## Diameter scale 1.5x on the base factors; band (??????) then compressed to 0.75 with INNER fixed.
const RING_DIAMETER_SCALE: float = 1.5
const RING_BAND_SCALE: float = 0.75
const RING_INNER: float = OVERLAY_BG_WORLD_SIZE * 0.78 * RING_DIAMETER_SCALE
const RING_OUTER: float = RING_INNER + OVERLAY_BG_WORLD_SIZE * (1.42 - 0.78) * RING_DIAMETER_SCALE * RING_BAND_SCALE
const RING_HP_GAP_FRAC: float = 0.16
const RING_SEAM: float = deg_to_rad(4.0)
## Ally (TEAM_PLAYER): empty bottom; HP from SW CW 180?; cap on screen-right 90?.
const HP_A0: float = deg_to_rad(-45.0)
const HP_A1: float = deg_to_rad(135.0) - RING_SEAM * 0.5
const CAP_A0: float = deg_to_rad(135.0) + RING_SEAM * 0.5
const CAP_A1: float = deg_to_rad(225.0)
## Enemy (TEAM_AI): empty bottom; cap on screen-left 90?; HP remaining 180?.
const ENEMY_HP_A0: float = deg_to_rad(45.0) + RING_SEAM * 0.5
const ENEMY_HP_A1: float = deg_to_rad(225.0)
const ENEMY_CAP_A0: float = deg_to_rad(-45.0) + RING_SEAM * 0.5
const ENEMY_CAP_A1: float = deg_to_rad(45.0) - RING_SEAM * 0.5
const RING_SEGS_HP: int = 28
const RING_SEGS_CAP: int = 16
const LAYER_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0, 0.95),
	Color(0.95, 0.82, 0.2, 0.95),
	Color(0.9, 0.22, 0.2, 0.95),
	Color(0.2, 0.9, 0.85, 0.25),
]
const BLACK_COLOR: Color = Color(0.02, 0.02, 0.03, 0.92)
const TRAIL_COLOR: Color = Color(0.35, 0.05, 0.06, 0.85)
const GREEN_COLOR: Color = Color(0.15, 0.95, 0.45, 1.0)
const TRAIL_HOLD_S: float = 0.5
const TRAIL_RATIO_PER_S: float = 0.5
const TRAIL_PULSE_AMP: float = 0.10
const GREEN_HOLD_S: float = 0.5
const GREEN_FADE_S: float = 1.0
const FIT_SLOT_COUNT: int = 3
const _FIT_FRAME_FILL: Color = Color(0.12, 0.16, 0.22, 0.28)
const _LAYER_KEYS: Array[String] = ["shield", "armor", "structure", "cap"]

var _ship: Node3D
var _style_bars: bool = false
var _fit_slots: Array = []
var _fit_lance_mats: Array = []
## Wall-clock for mixed-lance fit-icon sweep.
var _sector_fills: Array[MeshInstance3D] = []
var _sector_blacks: Array[MeshInstance3D] = []
var _sector_trails: Array[MeshInstance3D] = []
var _sector_a0: PackedFloat32Array = PackedFloat32Array()
var _sector_a1: PackedFloat32Array = PackedFloat32Array()
var _sector_r0: PackedFloat32Array = PackedFloat32Array()
var _sector_r1: PackedFloat32Array = PackedFloat32Array()
var _bar_fills: Array[MeshInstance3D] = []
var _bar_blacks: Array[MeshInstance3D] = []
var _bar_trails: Array[MeshInstance3D] = []
var _bar_ys: PackedFloat32Array = PackedFloat32Array()
var _fill_ratio: PackedFloat32Array = PackedFloat32Array()
var _trail_ratio: PackedFloat32Array = PackedFloat32Array()
var _trail_hold: PackedFloat32Array = PackedFloat32Array()
var _black_frac: PackedFloat32Array = PackedFloat32Array()
var _prev_cur: PackedFloat32Array = PackedFloat32Array()
var _prev_max: PackedFloat32Array = PackedFloat32Array()
var _layer_inited: bool = false
var _green_batches: Array = [[], [], [], []]
var _tonnage_icon: Sprite3D
var _tonnage_label: Label3D
var _tonnage_plate: MeshInstance3D
var _overlay_bg: Sprite3D
var _overlay_tag: Sprite3D
var _overlay_key: String = ""
## Ring layout baked for enemy (cap left) vs ally (cap right). Rebuilt if team/half changes.
var _ring_enemy_mirrored: bool = false
## Star outline around HP badge/ring (UI_AND_SHELL / plan K).
var _star_border: MeshInstance3D
var _star_border_mat: StandardMaterial3D
var _star_border_star: int = 0
## Main-menu gold palette (menu_parallelogram_button).
const STAR2_SILVER: Color = Color(0.78, 0.82, 0.88, 0.85)
const STAR3_MID_GOLD: Color = Color(0.58, 0.44, 0.16, 0.95)
const STAR3_DARK_GOLD: Color = Color(0.22, 0.14, 0.04, 0.95)
const STAR3_PLATINUM: Color = Color(0.96, 0.94, 0.88, 0.95)
## ≈3px / ≈4px at badge pixel_size scale.
const STAR2_OUTLINE_WU: float = BADGE_PIXEL_SIZE * 3.0
const STAR3_OUTLINE_WU: float = BADGE_PIXEL_SIZE * 4.0
## Was 1.35s; UI_AND_SHELL §2.3 — 1/20 speed for 3★ gold flow.
const STAR3_CYCLE_S: float = 27.0
## Ring star outline skips the same bottom 90° empty as HP/cap (ally −135°→−45°).
const STAR_BORDER_A0: float = deg_to_rad(-45.0)
const STAR_BORDER_A1: float = deg_to_rad(225.0)

static func style_is_bars() -> bool:
	var ps: PlayerSettings = PlayerSettings.get_or_null()
	if ps == null:
		return false
	return ps.health_bar_style == "bars"


static func extra_fx_enabled() -> bool:
	var ps: PlayerSettings = PlayerSettings.get_or_null()
	if ps == null:
		return true
	return not ps.no_model_perf_mode


func setup(ship: Node3D) -> void:
	_ship = ship
	top_level = true
	_build()
	refresh()


func _reset_layer_state() -> void:
	_fill_ratio = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	_trail_ratio = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	_trail_hold = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	_black_frac = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	_prev_cur = PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])
	_prev_max = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	_layer_inited = false
	_clear_all_green()


func _clear_all_green() -> void:
	for i: int in range(4):
		_clear_green_layer(i)


func _clear_green_layer(idx: int) -> void:
	if idx < 0 or idx >= _green_batches.size():
		return
	var batches: Array = _green_batches[idx]
	for b: Variant in batches:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var mi: MeshInstance3D = __mesh((b as Dictionary).get("mesh"))
		if mi != null and is_instance_valid(mi):
			mi.queue_free()
	_green_batches[idx] = []


func _build() -> void:
	for c: Node in get_children():
		c.queue_free()
	_sector_fills.clear()
	_sector_blacks.clear()
	_sector_trails.clear()
	_sector_a0.clear()
	_sector_a1.clear()
	_sector_r0.clear()
	_sector_r1.clear()
	_bar_fills.clear()
	_bar_blacks.clear()
	_bar_trails.clear()
	_bar_ys.clear()
	_fit_slots.clear()
	_green_batches = [[], [], [], []]
	_tonnage_icon = null
	_tonnage_label = null
	_tonnage_plate = null
	_overlay_bg = null
	_overlay_tag = null
	_overlay_key = ""
	_star_border = null
	_star_border_mat = null
	_star_border_star = 0
	_reset_layer_state()
	_style_bars = style_is_bars()
	if _style_bars:
		_build_bar_stack()
	else:
		_build_ring_sectors(0.0)
	_build_fit_strip()
	var badge_y: float = _badge_y()
	_tonnage_plate = _make_badge_plate()
	_tonnage_plate.position = Vector3(0, badge_y, -0.02)
	add_child(_tonnage_plate)
	_build_overlays()
	var icon_tex: Texture2D = UiAssets.tonnage_icon(_tonnage_group())
	if icon_tex:
		_tonnage_icon = Sprite3D.new()
		_tonnage_icon.texture = icon_tex
		_tonnage_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tonnage_icon.pixel_size = _badge_pixel_size(icon_tex)
		_tonnage_icon.centered = true
		_tonnage_icon.no_depth_test = true
		_tonnage_icon.render_priority = 20
		_tonnage_icon.position = Vector3(0, badge_y, 0.04)
		add_child(_tonnage_icon)
	else:
		_tonnage_label = Label3D.new()
		_tonnage_label.text = _tonnage_text()
		var f: Font = UiAssets.display_font()
		if f:
			_tonnage_label.font = f
		_tonnage_label.font_size = 216
		_tonnage_label.outline_size = 30
		_tonnage_label.outline_modulate = Color(0, 0, 0, 0.9)
		_tonnage_label.modulate = _tonnage_color()
		_tonnage_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tonnage_label.pixel_size = BADGE_PIXEL_SIZE
		_tonnage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tonnage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_tonnage_label.position = Vector3(0, badge_y, 0.04)
		_tonnage_label.no_depth_test = true
		_tonnage_label.render_priority = 20
		add_child(_tonnage_label)
	_rebuild_star_border()
	## Rebuild (ring mirror / style) used to leave FitSlot icons hidden; _process never re-applied them.
	_refresh_fit_strip()


func _layer_radii(idx: int) -> Vector2:
	## Cap (idx 3): full INNER..OUTER ? same radial thickness as the whole HP three-pipe stack.
	if idx >= 3:
		return Vector2(RING_INNER, RING_OUTER)
	var band: float = RING_OUTER - RING_INNER
	var gap: float = band * RING_HP_GAP_FRAC
	var tw: float = (band - 2.0 * gap) / 3.0
	var r1: float = RING_OUTER - float(idx) * (tw + gap)
	var r0: float = r1 - tw
	return Vector2(r0, r1)


func _build_bar_stack() -> void:
	var fx: bool = extra_fx_enabled()
	var total_h: float = float(BAR_COUNT) * BAR_H + float(BAR_COUNT - 1) * BAR_GAP
	var y0: float = total_h * 0.5 - BAR_H * 0.5
	for i: int in range(BAR_COUNT):
		var y: float = y0 - float(i) * (BAR_H + BAR_GAP)
		_bar_ys.append(y)
		var black: MeshInstance3D = _make_bar_box(BLACK_COLOR, 9)
		black.position = Vector3(0, y, 0.004)
		black.visible = false
		add_child(black)
		_bar_blacks.append(black)
		var trail: MeshInstance3D = _make_bar_box(TRAIL_COLOR, 10)
		trail.position = Vector3(0, y, 0.006)
		trail.visible = false
		add_child(trail)
		_bar_trails.append(trail)
		if not fx or i >= 3:
			trail.visible = false
		var fill: MeshInstance3D = _make_bar_box(LAYER_COLORS[i], 12)
		fill.position = Vector3(0, y, 0.012)
		add_child(fill)
		_bar_fills.append(fill)


func _build_ring_sectors(badge_y: float) -> void:
	## Local XY after look_at(cam): screen-right = ?X, screen-up = +Y
	## Angle 0 = +X = screen-left; increasing = screen-clockwise.
	## Enemy half mirrors cap to the left (UI_AND_SHELL ?2.3.0); badges stay fixed.
	var fx: bool = extra_fx_enabled()
	var enemy: bool = _ring_use_enemy_mirror()
	_ring_enemy_mirrored = enemy
	var hp0: float = ENEMY_HP_A0 if enemy else HP_A0
	var hp1: float = ENEMY_HP_A1 if enemy else HP_A1
	var cap0: float = ENEMY_CAP_A0 if enemy else CAP_A0
	var cap1: float = ENEMY_CAP_A1 if enemy else CAP_A1
	for i: int in range(4):
		var a0: float = cap0 if i == 3 else hp0
		var a1: float = cap1 if i == 3 else hp1
		var rr: Vector2 = _layer_radii(i)
		_sector_a0.append(a0)
		_sector_a1.append(a1)
		_sector_r0.append(rr.x)
		_sector_r1.append(rr.y)
		var segs: int = RING_SEGS_CAP if i == 3 else RING_SEGS_HP
		var black: MeshInstance3D = _make_annulus_sector(rr.x, rr.y, a0, a0, BLACK_COLOR, segs, 9)
		black.position = Vector3(0, badge_y, -0.005)
		black.visible = false
		add_child(black)
		_sector_blacks.append(black)
		var trail: MeshInstance3D = _make_annulus_sector(rr.x, rr.y, a0, a0, TRAIL_COLOR, segs, 10)
		trail.position = Vector3(0, badge_y, -0.004)
		trail.visible = false
		add_child(trail)
		_sector_trails.append(trail)
		if not fx or i >= 3:
			trail.visible = false
		var fill: MeshInstance3D = _make_annulus_sector(rr.x, rr.y, a0, a0, LAYER_COLORS[i], segs, 12)
		fill.position = Vector3(0, badge_y, 0.004)
		add_child(fill)
		_sector_fills.append(fill)


func _ring_use_enemy_mirror() -> bool:
	## bars: no geometric mirror. Ring: same key as 声望 overlay (UI_AND_SHELL §2.3.0 / UI_ICONS §6.1).
	## Mirror when reputation set is enemy (team_id == TEAM_AI) — NOT field_side_team / half-field.
	if _style_bars:
		return false
	if _ship == null or not is_instance_valid(_ship):
		return false
	## Same mapping as `_overlay_set_key` fleet/enemy (ignore unmanned / freighter specials for HP angles).
	const TEAM_AI: int = 1
	return __as_int(_ship.get("team_id"), 0) == TEAM_AI


func _make_annulus_sector(r0: float, r1: float, a0: float, a1: float, col: Color, segs: int, priority: int = 12) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _build_annulus_mesh(r0, r1, a0, a1, segs)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _make_unshaded_alpha_mat(col, priority, BaseMaterial3D.CULL_DISABLED)
	return mi


func _make_unshaded_alpha_mat(col: Color, priority: int, cull: BaseMaterial3D.CullMode = BaseMaterial3D.CULL_DISABLED) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = cull
	mat.albedo_color = col
	mat.render_priority = priority
	## HP overlays face camera; skip depth so thin trail wedges are not z-fought away.
	mat.no_depth_test = true
	return mat


func _build_annulus_mesh(r0: float, r1: float, a0: float, a1: float, segs: int) -> ArrayMesh:
	if absf(a1 - a0) < 0.0001:
		a1 = a0 + 0.0001
	var n: int = maxi(segs, 2)
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for i: int in range(n + 1):
		var t: float = float(i) / float(n)
		var a: float = lerpf(a0, a1, t)
		var ca: float = cos(a)
		var sa: float = sin(a)
		verts.append(Vector3(r0 * ca, r0 * sa, 0.0))
		verts.append(Vector3(r1 * ca, r1 * sa, 0.0))
		norms.append(Vector3(0, 0, 1))
		norms.append(Vector3(0, 0, 1))
	for i: int in range(n):
		var b: int = i * 2
		indices.append(b)
		indices.append(b + 1)
		indices.append(b + 2)
		indices.append(b + 1)
		indices.append(b + 3)
		indices.append(b + 2)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_bar_box(col: Color, priority: int = 10) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(BAR_W, BAR_H, 0.04)
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _make_unshaded_alpha_mat(col, priority, BaseMaterial3D.CULL_DISABLED)
	return mi


func _bars_total_h() -> float:
	return float(BAR_COUNT) * BAR_H + float(BAR_COUNT - 1) * BAR_GAP


func _fit_strip_width() -> float:
	if _style_bars:
		return BAR_W
	return RING_OUTER * 2.0


func _fit_slot_side() -> float:
	return _fit_strip_width() / float(FIT_SLOT_COUNT)


func _fit_strip_y() -> float:
	if _style_bars:
		return -_bars_total_h() * 0.5 - 0.05 - _fit_slot_side() * 0.5
	return -RING_OUTER - 0.06 - _fit_slot_side() * 0.5


func _badge_y() -> float:
	if not _style_bars:
		return 0.0
	var fit_gap: float = 0.0
	if not _fit_slots.is_empty():
		fit_gap = _fit_slot_side() + 0.08
	return -_bars_total_h() * 0.5 - fit_gap - BADGE_SIZE * 0.55 - 0.06


func _build_fit_strip() -> void:
	@warning_ignore("unsafe_cast")
	var su: ShipUnit = _ship as ShipUnit
	if su != null and not FunctionFit.ship_allows_function_fit(DataStore.get_ship(su.ship_id)):
		_fit_slots.clear()
		return
	var side: float = _fit_slot_side()
	var y: float = _fit_strip_y()
	var strip_w: float = _fit_strip_width()
	var x0: float = strip_w * 0.5 - side * 0.5
	for i: int in range(FIT_SLOT_COUNT):
		var slot_root: Node3D = Node3D.new()
		slot_root.name = "FitSlot%d" % i
		slot_root.position = Vector3(x0 - float(i) * side, y, 0.03)
		add_child(slot_root)
		var frame: MeshInstance3D = _make_fit_frame(side)
		frame.visible = false
		slot_root.add_child(frame)
		var icon: MeshInstance3D = _make_fit_icon_mesh(side)
		icon.visible = false
		slot_root.add_child(icon)
		_fit_slots.append({"root": slot_root, "frame": frame, "icon": icon})


func _make_fit_frame(side: float) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(side * 0.96, side * 0.96, 0.025)
	mi.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _FIT_FRAME_FILL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 11
	mi.material_override = mat
	return mi


func _fit_icon_quad_size(side: float, tex: Texture2D = null) -> Vector2:
	## Contain texture aspect inside the square cell (bag/shop KEEP_ASPECT_CENTERED).
	var max_s: float = side * 0.92
	if tex == null:
		return Vector2(max_s, max_s)
	var tw: float = float(tex.get_width())
	var th: float = float(tex.get_height())
	if tw <= 0.5 or th <= 0.5:
		return Vector2(max_s, max_s)
	var aspect: float = tw / th
	if aspect >= 1.0:
		return Vector2(max_s, max_s / aspect)
	return Vector2(max_s * aspect, max_s)


func _make_fit_icon_mesh(side: float) -> MeshInstance3D:
	## QuadMesh (UV 0..1). BoxMesh uses a 3x2 atlas UV and stretches/crops icons.
	var mi: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = _fit_icon_quad_size(side)
	mi.mesh = quad
	mi.position = Vector3(0, 0, 0.02)
	## Parent look_at(cam) aims local -Z at the camera; QuadMesh faces +Z by default.
	mi.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	mi.scale = Vector3.ONE
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _make_fit_tex_mat(14)
	return mi


func _make_fit_tex_mat(priority: int) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.no_depth_test = true
	mat.render_priority = priority
	return mat


func _set_fit_mesh_tex(mi: MeshInstance3D, tex: Texture2D) -> void:
	if mi == null:
		return
	@warning_ignore("unsafe_cast")
	var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
	if mat == null:
		mat = _make_fit_tex_mat(14)
		mi.material_override = mat
	else:
		@warning_ignore("unsafe_cast")
		mat = mat.duplicate() as StandardMaterial3D
		mi.material_override = mat
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE


func _set_fit_lance_icon(mi: MeshInstance3D, side: float) -> void:
	if mi == null:
		return
	_resize_fit_icon_mesh(mi, side)
	var sm: ShaderMaterial = MixedLanceIcon.make_3d_material(14)
	mi.material_override = sm
	_fit_lance_mats.append(sm)
	mi.visible = true


func _resize_fit_icon_mesh(mi: MeshInstance3D, side: float, tex: Texture2D = null) -> void:
	if mi == null:
		return
	mi.scale = Vector3.ONE
	@warning_ignore("unsafe_cast")
	var quad: QuadMesh = mi.mesh as QuadMesh
	if quad == null:
		quad = QuadMesh.new()
		mi.mesh = quad
	quad.size = _fit_icon_quad_size(side, tex)


func _refresh_fit_strip() -> void:
	var side: float = _fit_slot_side()
	_fit_lance_mats.clear()
	for i: int in range(_fit_slots.size()):
		@warning_ignore("unsafe_cast")
		var slot: Dictionary = _fit_slots[i] as Dictionary
		var frame: MeshInstance3D = __mesh(slot.get("frame"))
		var icon: MeshInstance3D = __mesh(slot.get("icon"))
		var mod: Dictionary = {}
		@warning_ignore("unsafe_cast")
		var su: ShipUnit = _ship as ShipUnit
		if su != null:
			var fit: Array = su.get_function_fit()
			if i < fit.size() and typeof(fit[i]) == TYPE_DICTIONARY:
				var entry: Dictionary = __as_dict(fit[i])
				mod = __as_dict(entry.get("def", {}))
				if mod.is_empty():
					var mid: String = str(entry.get("id", ""))
					if mid != "":
						mod = DataStore.get_function_module(mid)
		var filled: bool = not mod.is_empty()
		if frame:
			frame.visible = false
		if icon:
			if filled and MixedLanceIcon.is_mixed_lance(mod):
				_set_fit_lance_icon(icon, side)
			elif filled:
				var tex: Texture2D = UiAssets.function_module_icon(mod)
				if tex:
					_resize_fit_icon_mesh(icon, side, tex)
					_set_fit_mesh_tex(icon, tex)
					icon.visible = true
				else:
					_resize_fit_icon_mesh(icon, side)
					icon.visible = false
			else:
				_resize_fit_icon_mesh(icon, side)
				icon.visible = false


func pick_fit_slot_at_screen(camera: Camera3D, screen: Vector2) -> int:
	if camera == null or _fit_slots.is_empty():
		return -1
	var best_i: int = -1
	var best_d: float = 1.0e9
	for i: int in range(_fit_slots.size()):
		var d: float = fit_slot_screen_distance(camera, screen, i)
		if d < 0.0:
			continue
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func fit_slot_screen_distance(camera: Camera3D, screen: Vector2, slot_index: int) -> float:
	if camera == null or slot_index < 0 or slot_index >= _fit_slots.size():
		return -1.0
	var slot: Dictionary = _fit_slots[slot_index]
	var root: Node3D = slot.get("root")
	if root == null or not is_instance_valid(root):
		var frame: MeshInstance3D = slot.get("frame")
		if frame == null or not is_instance_valid(frame):
			return -1.0
		root = frame
	@warning_ignore("unsafe_cast")
	var su: ShipUnit = _ship as ShipUnit
	if su == null:
		return -1.0
	var fit: Array = su.get_function_fit()
	if slot_index >= fit.size():
		return -1.0
	var world: Vector3 = root.global_position
	if camera.is_position_behind(world):
		return -1.0
	var sp: Vector2 = camera.unproject_position(world)
	var side: float = _fit_slot_side()
	var half: float = side * 0.55 * maxf(scale.x, 0.001)
	var edge: Vector2 = camera.unproject_position(world + camera.global_transform.basis.x * half)
	var r: float = maxf(sp.distance_to(edge), UiLayout.px(16.0))
	var d: float = sp.distance_to(screen)
	if d <= r:
		return d
	return -1.0


func _overlay_set_key() -> String:
	@warning_ignore("unsafe_cast")
	var su: ShipUnit = _ship as ShipUnit
	if su == null or su.is_unmanned:
		return ""
	var profile: String = _tonnage_overlay_profile()
	if profile == "relation":
		if su.is_protect_target or _ship_group_from_data() == "freighter":
			return "relation_friendly"
		return "relation_fleet" if __as_int(su.team_id) == ShipUnit.TEAM_PLAYER else "relation_enemy"
	if su.is_protect_target or _ship_group_from_data() == "freighter":
		return "friendly"
	return "fleet" if __as_int(su.team_id) == ShipUnit.TEAM_PLAYER else "enemy"


func _tonnage_overlay_profile() -> String:
	if _ship == null:
		return ""
	var sd: Dictionary = DataStore.get_ship(__as_int(_ship.get("ship_id")))
	if sd.is_empty():
		return ""
	var vis: Dictionary = TypedVariant.as_dict(sd.get("_visual", {}))
	return str(vis.get("tonnage_overlay_profile", "")).strip_edges()


func _build_overlays() -> void:
	var key: String = _overlay_set_key()
	_overlay_key = key
	if key == "":
		return
	var set_tex: Dictionary = UiAssets.tonnage_overlay_set(key)
	var badge_y: float = _badge_y()
	var bg_tex: Texture2D = set_tex.get("bg")
	if bg_tex:
		_overlay_bg = _make_overlay_sprite(bg_tex, OVERLAY_BG_WORLD_SIZE, 19)
		_overlay_bg.position = Vector3(0, badge_y, 0.02)
		add_child(_overlay_bg)
	var tag_tex: Texture2D = set_tex.get("badge")
	if tag_tex:
		_overlay_tag = _make_overlay_sprite(tag_tex, OVERLAY_TAG_WORLD_SIZE, 21)
		_overlay_tag.position = Vector3(-OVERLAY_TAG_OFFSET, badge_y - OVERLAY_TAG_OFFSET, 0.06)
		add_child(_overlay_tag)


func _sync_overlays() -> void:
	var key: String = _overlay_set_key()
	if key == _overlay_key:
		return
	if _overlay_bg and is_instance_valid(_overlay_bg):
		_overlay_bg.queue_free()
	_overlay_bg = null
	if _overlay_tag and is_instance_valid(_overlay_tag):
		_overlay_tag.queue_free()
	_overlay_tag = null
	_build_overlays()


func _make_overlay_sprite(tex: Texture2D, world_size: float, priority: int) -> Sprite3D:
	var spr: Sprite3D = Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.centered = true
	spr.no_depth_test = true
	spr.double_sided = true
	spr.render_priority = priority
	var longest: float = float(maxi(tex.get_width(), tex.get_height()))
	spr.pixel_size = world_size / maxf(longest, 1.0)
	return spr


func _tonnage_group() -> String:
	if _ship == null:
		return ""
	@warning_ignore("unsafe_cast")
	var su: ShipUnit = _ship as ShipUnit
	if su != null and su.is_unmanned:
		match su.unmanned_kind:
			"fighter":
				return "fighter"
			"heavy_repair_drone":
				return "heavy_repair_drone"
			"combat_drone":
				var sg: String = _ship_group_from_data()
				if sg in ["drone_medium", "drone_heavy", "drone_light"]:
					return sg
				if sg.begins_with("drone_"):
					return sg
				return "drone_light"
			_:
				var g2: String = _ship_group_from_data()
				if g2 != "":
					return g2
				return "drone_light"
	var g: String = _ship_group_from_data()
	return g if g != "" else "frigate"


func _ship_group_from_data() -> String:
	if _ship == null:
		return ""
	@warning_ignore("unsafe_cast")
	var su: ShipUnit = _ship as ShipUnit
	var sid: int = su.ship_id if su != null else __as_int(_ship.get("ship_id"))
	var sd: Dictionary = DataStore.get_ship(sid) if DataStore else {}
	return str(sd.get("ship_group", ""))


func _badge_pixel_size(tex: Texture2D) -> float:
	if tex == null:
		return BADGE_PIXEL_SIZE
	var longest: float = float(maxi(tex.get_width(), tex.get_height()))
	if longest < 1.0:
		return BADGE_PIXEL_SIZE
	return BADGE_WORLD_SIZE / longest


func _tonnage_text() -> String:
	if _ship == null:
		return "?"
	var group: String = _tonnage_group()
	match group:
		"frigate":
			return "?"
		"destroyer":
			return "?"
		"cruiser":
			return "?"
		"battlecruiser":
			return "??"
		"battleship":
			return "?"
		"carrier":
			return "?"
		"dreadnought":
			return "??"
		"force_auxiliary":
			return "??"
		"fighter":
			return "??"
		"drone_light", "drone_medium", "drone_heavy", "heavy_repair_drone", "repair_drone":
			return "??"
		_:
			if __as_bool(_ship.get("is_unmanned")):
				return "??"
			return "?"


func _tonnage_color() -> Color:
	if _ship == null:
		return Color(0.95, 0.95, 1.0)
	var group: String = _tonnage_group()
	match group:
		"frigate":
			return Color(0.75, 0.92, 1.0)
		"destroyer":
			return Color(0.7, 0.98, 0.75)
		"cruiser":
			return Color(1.0, 0.9, 0.5)
		"battlecruiser":
			return Color(1.0, 0.78, 0.4)
		"battleship":
			return Color(1.0, 0.55, 0.5)
		"carrier", "dreadnought", "force_auxiliary":
			return Color(0.85, 0.7, 1.0)
		"fighter", "drone_light", "drone_medium", "drone_heavy", "heavy_repair_drone", "repair_drone":
			return Color(0.85, 0.9, 0.75)
		_:
			if __as_bool(_ship.get("is_unmanned")):
				return Color(0.85, 0.9, 0.75)
			return Color(0.95, 0.95, 1.0)


func _make_badge_plate() -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(BADGE_SIZE, BADGE_SIZE, 0.03)
	mi.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.06, 0.08, 0.12, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 18
	mi.material_override = mat
	return mi


func _cap_pair() -> Vector2:
	@warning_ignore("unsafe_cast")
	var su: ShipUnit = _ship as ShipUnit
	if su != null:
		return Vector2(float(su.cap_current), float(su.cap_capacity))
	return Vector2(__as_float(_ship.get("cap_current")), __as_float(_ship.get("cap_capacity")))


func _read_layer_cur_max(idx: int) -> Vector2:
	match idx:
		0:
			return Vector2(__as_float(_ship.get("shield_hp")), __as_float(_ship.get("max_shield")))
		1:
			return Vector2(__as_float(_ship.get("armor_hp")), __as_float(_ship.get("max_armor")))
		2:
			return Vector2(__as_float(_ship.get("structure_hp")), __as_float(_ship.get("max_structure")))
		_:
			return _cap_pair()


func _read_black_frac(idx: int) -> float:
	if idx >= 3:
		return 0.0
	@warning_ignore("unsafe_cast")
	var su: ShipUnit = _ship as ShipUnit
	if su == null or not su.has_method("capital_black_frac"):
		return 0.0
	return __as_float(su.call("capital_black_frac", _LAYER_KEYS[idx]))


func refresh() -> void:
	if _ship == null:
		return
	if style_is_bars() != _style_bars:
		_build()
	if not _style_bars and _sector_fills.size() < 4:
		return
	if _style_bars and _bar_fills.size() < BAR_COUNT:
		return
	_sync_layer_values()
	_apply_visuals()
	visible = not __as_bool(_ship.get("is_destroyed"))
	_refresh_fit_strip()
	_sync_overlays()
	if _tonnage_icon:
		var tex: Texture2D = UiAssets.tonnage_icon(_tonnage_group())
		_tonnage_icon.texture = tex
		_tonnage_icon.pixel_size = _badge_pixel_size(tex)
	if _tonnage_label:
		_tonnage_label.text = _tonnage_text()
		_tonnage_label.modulate = _tonnage_color()
	var st: int = _ship_star()
	if st != _star_border_star:
		_rebuild_star_border()
	else:
		_tick_star_border(0.0)


func _ship_star() -> int:
	if _ship == null or not is_instance_valid(_ship):
		return 1
	return clampi(__as_int(_ship.get("star"), 1), 1, 3)


func _rebuild_star_border() -> void:
	if _star_border != null and is_instance_valid(_star_border):
		_star_border.queue_free()
	_star_border = null
	_star_border_mat = null
	_star_border_star = _ship_star()
	if _star_border_star < 2:
		return
	var badge_y: float = _badge_y()
	var thick: float = STAR3_OUTLINE_WU if _star_border_star >= 3 else STAR2_OUTLINE_WU
	if _style_bars:
		var total_h: float = float(BAR_COUNT) * BAR_H + float(BAR_COUNT - 1) * BAR_GAP
		var r0: float = BAR_W * 0.5
		var r1: float = BAR_W * 0.5 + thick
		_star_border = _make_annulus_sector(r0, r1, 0.0, TAU, STAR2_SILVER, 48, 18)
		_star_border.position = Vector3(0, 0, -0.01)
		var sy: float = maxf(total_h / maxf(BAR_W, 0.01), 0.35)
		_star_border.scale = Vector3(1.0, sy, 1.0)
	else:
		var r_mid: float = RING_OUTER + thick * 0.55
		## Keep bottom 90° empty (same gap as HP/cap rings).
		_star_border = _make_annulus_sector(
			r_mid - thick * 0.5, r_mid + thick * 0.5, STAR_BORDER_A0, STAR_BORDER_A1, STAR2_SILVER, 40, 18
		)
		_star_border.position = Vector3(0, badge_y, -0.008)
	_star_border.name = "StarBorder"
	_star_border_mat = _star_border.material_override as StandardMaterial3D
	add_child(_star_border)
	_tick_star_border(0.0)


func _tick_star_border(_delta: float) -> void:
	if _star_border == null or not is_instance_valid(_star_border):
		return
	if _star_border_mat == null:
		_star_border_mat = _star_border.material_override as StandardMaterial3D
	if _star_border_mat == null:
		return
	if _star_border_star == 2:
		var pulse: float = 0.72 + 0.18 * sin(Time.get_ticks_msec() * 0.001 * TAU / 2.4)
		var c: Color = STAR2_SILVER
		c.a = STAR2_SILVER.a * pulse
		_star_border_mat.albedo_color = c
		return
	if _star_border_star >= 3:
		var t: float = fmod(Time.get_ticks_msec() * 0.001, STAR3_CYCLE_S) / STAR3_CYCLE_S
		var c0: Color
		var c1: Color
		var u: float
		if t < 0.333:
			c0 = STAR3_MID_GOLD
			c1 = STAR3_DARK_GOLD
			u = t / 0.333
		elif t < 0.666:
			c0 = STAR3_DARK_GOLD
			c1 = STAR3_PLATINUM
			u = (t - 0.333) / 0.333
		else:
			c0 = STAR3_PLATINUM
			c1 = STAR3_MID_GOLD
			u = (t - 0.666) / 0.334
		_star_border_mat.albedo_color = c0.lerp(c1, clampf(u, 0.0, 1.0))


func _sync_layer_values() -> void:
	var fx: bool = extra_fx_enabled()
	if not fx:
		_clear_all_green()
	for i: int in range(4):
		var cm: Vector2 = _read_layer_cur_max(i)
		var cur: float = cm.x
		var mx: float = maxf(cm.y, 0.0)
		var safe_cur: float = clampf(cur, 0.0, mx if mx > 0.0 else 0.0)
		var new_r: float = 0.0 if mx <= 0.0 else clampf(safe_cur / mx, 0.0, 1.0)
		_black_frac[i] = _read_black_frac(i)
		var old_r: float = _fill_ratio[i]
		var old_cur: float = _prev_cur[i]
		if not _layer_inited or old_cur < 0.0:
			_fill_ratio[i] = new_r
			_trail_ratio[i] = new_r
			_trail_hold[i] = 0.0
			_prev_cur[i] = safe_cur
			_prev_max[i] = mx
			continue
		var dcur: float = safe_cur - old_cur
		## Green push is event-only (notify_layer_gain). Delta only consumes greens on loss.
		if fx and dcur < -0.05:
			_consume_green(i, -dcur)
		elif fx:
			_trim_green_to_cur(i, safe_cur, mx)
		if i < 3 and fx:
			if new_r < old_r - 0.0005:
				var synced: bool = _trail_hold[i] <= 0.0 and absf(_trail_ratio[i] - old_r) <= 0.002
				if synced:
					_trail_hold[i] = TRAIL_HOLD_S
				_trail_ratio[i] = maxf(_trail_ratio[i], old_r)
			elif new_r > old_r + 0.0005:
				_trail_ratio[i] = new_r
				_trail_hold[i] = 0.0
		else:
			_trail_ratio[i] = new_r
			_trail_hold[i] = 0.0
		_fill_ratio[i] = new_r
		_prev_cur[i] = safe_cur
		_prev_max[i] = mx
	_layer_inited = true


func _trim_green_to_cur(idx: int, cur: float, mx: float) -> void:
	## Keep sum(amount) <= cur so overlays never outgrow real HP/cap.
	var over: float = _green_amount_sum(idx) - cur
	if over > 0.05:
		_consume_green(idx, over)
	## Refresh fracs if max changed.
	var use_mx: float = maxf(mx, 0.001)
	var batches: Array = _green_batches[idx]
	for b: Variant in batches:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var d: Dictionary = b
		var amt: float = __as_float(d.get("amount", 0.0))
		d["frac"] = clampf(amt / use_mx, 0.0, 1.0)


func notify_layer_gain(layer: String, amount: float) -> void:
	## Only explicit restore deltas (heal / discrete cap inject). Never frame-diff cur.
	if not extra_fx_enabled():
		return
	var idx: int = _layer_key_to_idx(layer)
	if idx < 0:
		return
	var cm: Vector2 = _read_layer_cur_max(idx)
	var mx: float = maxf(cm.y, 0.0)
	if mx <= 0.0:
		return
	## Ignore jitter; require a real restore slice.
	var min_amt: float = maxf(0.5, mx * 0.0005)
	var amt: float = amount
	if amt <= min_amt:
		return
	## Clamp to what can exist on the bar after this restore (cur already includes amt).
	var cur: float = clampf(cm.x, 0.0, mx)
	var already: float = _green_amount_sum(idx)
	var room: float = maxf(0.0, cur - already)
	amt = minf(amt, room)
	if amt <= min_amt:
		return
	## Never let a single batch claim more than this restore (guard against bad callers).
	amt = minf(amt, mx)
	var frac: float = clampf(amt / mx, 0.0, 1.0)
	if frac <= 0.0005:
		return
	_push_green(idx, amt, frac)


func _green_amount_sum(idx: int) -> float:
	if idx < 0 or idx >= _green_batches.size():
		return 0.0
	var total: float = 0.0
	for b: Variant in _green_batches[idx]:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		total += __as_float((b as Dictionary).get("amount", 0.0))
	return total


func _layer_key_to_idx(layer: String) -> int:
	match str(layer).strip_edges().to_lower():
		"shield":
			return 0
		"armor":
			return 1
		"structure", "hull":
			return 2
		"cap", "capacitor", "cap_current":
			return 3
		_:
			return -1


func _push_green(idx: int, amount: float, frac: float) -> void:
	if amount <= 0.0 or frac <= 0.0:
		return
	var mi: MeshInstance3D
	if _style_bars:
		mi = _make_bar_box(GREEN_COLOR, 16)
		mi.position = Vector3(0, _bar_ys[idx] if idx < _bar_ys.size() else 0.0, 0.018)
	else:
		if idx < 0 or idx >= _sector_r0.size() or idx >= _sector_r1.size():
			return
		var segs: int = RING_SEGS_CAP if idx == 3 else RING_SEGS_HP
		mi = _make_annulus_sector(_sector_r0[idx], _sector_r1[idx], 0.0, 0.0001, GREEN_COLOR, segs, 16)
		mi.position = Vector3(0.0, 0.0, 0.012)
	mi.visible = false
	add_child(mi)
	@warning_ignore("unsafe_cast")
	(_green_batches[idx] as Array).append({
		"amount": amount,
		"frac": frac,
		"age": 0.0,
		"mesh": mi,
	})


func _consume_green(idx: int, loss: float) -> void:
	## Tip (newest) first ? matches depleting-end damage and newest-at-tip draw order.
	var remain: float = loss
	var batches: Array = _green_batches[idx]
	var kept_rev: Array = []
	var mx: float = maxf(_prev_max[idx], 0.001)
	for i: int in range(batches.size() - 1, -1, -1):
		var b: Variant = batches[i]
		if typeof(b) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var d: Dictionary = b
		if remain <= 0.0:
			kept_rev.append(d)
			continue
		var amt: float = __as_float(d.get("amount", 0.0))
		if amt <= remain + 0.001:
			remain -= amt
			@warning_ignore("unsafe_cast")
			var mi: MeshInstance3D = __mesh(d.get("mesh"))
			if mi != null and is_instance_valid(mi):
				mi.queue_free()
		else:
			var left: float = amt - remain
			d["amount"] = left
			d["frac"] = clampf(left / mx, 0.0, 1.0)
			remain = 0.0
			kept_rev.append(d)
	kept_rev.reverse()
	_green_batches[idx] = kept_rev


func _green_alpha(age: float) -> float:
	if age <= GREEN_HOLD_S:
		return 1.0
	var t: float = (age - GREEN_HOLD_S) / GREEN_FADE_S
	return clampf(1.0 - t, 0.0, 1.0)


func _tick_fx(delta: float) -> void:
	var fx: bool = extra_fx_enabled()
	if not fx:
		for i: int in range(3):
			_trail_ratio[i] = _fill_ratio[i]
			_trail_hold[i] = 0.0
		_clear_all_green()
		return
	for i: int in range(3):
		if _trail_ratio[i] > _fill_ratio[i] + 0.0005:
			if _trail_hold[i] > 0.0:
				_trail_hold[i] = maxf(0.0, _trail_hold[i] - delta)
			else:
				_trail_ratio[i] = maxf(_fill_ratio[i], _trail_ratio[i] - TRAIL_RATIO_PER_S * delta)
		else:
			_trail_ratio[i] = _fill_ratio[i]
			_trail_hold[i] = 0.0
	for i: int in range(4):
		var batches: Array = _green_batches[i]
		var kept: Array = []
		for b: Variant in batches:
			if typeof(b) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var d: Dictionary = b
			var amt: float = __as_float(d.get("amount", 0.0))
			if amt <= 0.001:
				@warning_ignore("unsafe_cast")
				var mi_dead: MeshInstance3D = __mesh(d.get("mesh"))
				if mi_dead != null and is_instance_valid(mi_dead):
					mi_dead.queue_free()
				continue
			d["age"] = __as_float(d.get("age", 0.0)) + delta
			if __as_float(d.get("age", 0.0)) >= GREEN_HOLD_S + GREEN_FADE_S:
				@warning_ignore("unsafe_cast")
				var mi_done: MeshInstance3D = __mesh(d.get("mesh"))
				if mi_done != null and is_instance_valid(mi_done):
					mi_done.queue_free()
				continue
			kept.append(d)
		_green_batches[i] = kept


func _usable_a0(idx: int) -> float:
	var a0: float = _sector_a0[idx]
	var a1: float = _sector_a1[idx]
	return lerpf(a0, a1, clampf(_black_frac[idx], 0.0, 1.0))


func _hp_fill_angles(a0_eff: float, a1: float, ratio: float) -> Vector2:
	var r: float = clampf(ratio, 0.0, 1.0)
	if r <= 0.001:
		return Vector2(a1, a1)
	return Vector2(lerpf(a1, a0_eff, r), a1)


func _cap_fill_angles(a0: float, a1: float, ratio: float) -> Vector2:
	var r: float = clampf(ratio, 0.0, 1.0)
	if r <= 0.001:
		return Vector2(a0, a0)
	return Vector2(a0, lerpf(a0, a1, r))


func _apply_visuals() -> void:
	## Team / half can change after setup (??, fleet mirror); rebuild ring angles.
	if not _style_bars and _ring_use_enemy_mirror() != _ring_enemy_mirrored:
		_build()
		return
	if not health_bars_shown():
		_hide_hp_geometry()
		return
	var fx: bool = extra_fx_enabled()
	var pulse: float = 1.0
	if fx:
		var period: float = 12.0
		if DataStore:
			period = maxf(0.5, __as_float(DataStore.visual.get("camera_breathe_period_s", 24.0), 24.0))
		var th: float = Time.get_ticks_msec() * 0.001 * TAU / period
		pulse = 1.0 + TRAIL_PULSE_AMP * sin(th)
	if _style_bars:
		_apply_bar_visuals(fx, pulse)
	else:
		_apply_ring_visuals(fx, pulse)


static func health_bars_shown() -> bool:
	var ps: PlayerSettings = PlayerSettings.get_or_null()
	if ps == null:
		return true
	return ps.health_bar_visible


func _hide_hp_geometry() -> void:
	## Keep tonnage / overlays / fit; only hide HP+cap fills and FX meshes.
	for mi: MeshInstance3D in _sector_fills:
		if mi:
			mi.visible = false
	for mi2: MeshInstance3D in _sector_blacks:
		if mi2:
			mi2.visible = false
	for mi3: MeshInstance3D in _sector_trails:
		if mi3:
			mi3.visible = false
	for mi4: MeshInstance3D in _bar_fills:
		if mi4:
			mi4.visible = false
	for mi5: MeshInstance3D in _bar_blacks:
		if mi5:
			mi5.visible = false
	for mi6: MeshInstance3D in _bar_trails:
		if mi6:
			mi6.visible = false
	for i: int in range(_green_batches.size()):
		var batches: Array = _green_batches[i]
		for b: Variant in batches:
			if typeof(b) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var gmi: MeshInstance3D = __mesh((b as Dictionary).get("mesh"))
			if gmi != null and is_instance_valid(gmi):
				gmi.visible = false


func _set_mat_color(mi: MeshInstance3D, col: Color) -> void:
	if mi == null or mi.material_override == null:
		return
	@warning_ignore("unsafe_cast")
	var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = col


func _place_bar_segment(mi: MeshInstance3D, y: float, x0: float, width: float, z: float) -> void:
	if mi == null:
		return
	if width <= 0.001:
		mi.visible = false
		return
	mi.visible = true
	mi.scale = Vector3(maxf(width / BAR_W, 0.001), 1, 1)
	mi.position = Vector3(x0 + width * 0.5, y, z)


func _apply_bar_visuals(fx: bool, pulse: float) -> void:
	for i: int in range(4):
		var y: float = _bar_ys[i]
		var bf: float = clampf(_black_frac[i], 0.0, 1.0)
		var black_w: float = BAR_W * bf
		var usable_w: float = BAR_W - black_w
		var x_left: float = -BAR_W * 0.5
		_place_bar_segment(_bar_blacks[i], y, x_left, black_w, 0.004)
		var x_u0: float = x_left + black_w
		var fr: float = _fill_ratio[i]
		var trail_r: float = _trail_ratio[i] if (fx and i < 3) else fr
		## Keep fill on the right of usable (deplete from left / after black).
		var fill_w: float = usable_w * fr
		var fill_x0: float = x_u0 + usable_w - fill_w
		## Full trail underlay (same shape as trail_r), under fill; gap is the visible lag.
		if fx and i < 3 and trail_r > fr + 0.001 and usable_w > 0.001:
			var trail_w: float = usable_w * trail_r
			var trail_x0: float = x_u0 + usable_w - trail_w
			var tc: Color = TRAIL_COLOR
			tc.r = clampf(tc.r * pulse, 0.0, 1.0)
			tc.g = clampf(tc.g * pulse, 0.0, 1.0)
			tc.b = clampf(tc.b * pulse, 0.0, 1.0)
			_set_mat_color(_bar_trails[i], tc)
			_place_bar_segment(_bar_trails[i], y, trail_x0, trail_w, 0.006)
		elif i < _bar_trails.size() and _bar_trails[i]:
			_bar_trails[i].visible = false
		_place_bar_segment(_bar_fills[i], y, fill_x0, fill_w, 0.012)
		_apply_bar_greens(i, x_u0, usable_w, fill_x0, fill_w, y, fx)


func _apply_bar_greens(idx: int, _x_u0: float, usable_w: float, fill_x0: float, fill_w: float, y: float, fx: bool) -> void:
	var batches: Array = _green_batches[idx]
	if not fx or batches.is_empty() or usable_w <= 0.001 or fill_w <= 0.001:
		for b: Variant in batches:
			if typeof(b) == TYPE_DICTIONARY:
				@warning_ignore("unsafe_cast")
				var mi0: MeshInstance3D = __mesh((b as Dictionary).get("mesh"))
				if mi0:
					mi0.visible = false
		return
	## Newest at depleting end; length = usable_w * frac (heal/max only ? never budget=cur).
	var remain_frac: float = clampf(_fill_ratio[idx], 0.0, 1.0)
	var cursor: float = fill_x0
	for i: int in range(batches.size() - 1, -1, -1):
		var b: Variant = batches[i]
		if typeof(b) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var d: Dictionary = b
		@warning_ignore("unsafe_cast")
		var mi: MeshInstance3D = __mesh(d.get("mesh"))
		if mi == null or not is_instance_valid(mi):
			continue
		if remain_frac <= 0.0005 or cursor >= fill_x0 + fill_w - 0.001:
			mi.visible = false
			continue
		var frac: float = __as_float(d.get("frac", -1.0))
		if frac < 0.0:
			var mx: float = maxf(_prev_max[idx], 0.001)
			frac = clampf(__as_float(d.get("amount", 0.0)) / mx, 0.0, 1.0)
		frac = minf(frac, remain_frac)
		remain_frac -= frac
		var w: float = usable_w * frac
		w = minf(w, fill_x0 + fill_w - cursor)
		if w <= 0.001:
			mi.visible = false
			continue
		var a: float = _green_alpha(__as_float(d.get("age", 0.0)))
		var col: Color = GREEN_COLOR
		col.a = a
		_set_mat_color(mi, col)
		_place_bar_segment(mi, y, cursor, w, 0.018)
		cursor += w


func _apply_ring_visuals(fx: bool, pulse: float) -> void:
	for i: int in range(4):
		var a0: float = _sector_a0[i]
		var a1: float = _sector_a1[i]
		var r0: float = _sector_r0[i]
		var r1: float = _sector_r1[i]
		var segs: int = RING_SEGS_CAP if i == 3 else RING_SEGS_HP
		var bf: float = clampf(_black_frac[i], 0.0, 1.0)
		var a0_eff: float = lerpf(a0, a1, bf)
		if i < 3 and bf > 0.001:
			_sector_blacks[i].visible = true
			_sector_blacks[i].mesh = _build_annulus_mesh(r0, r1, a0, a0_eff, segs)
		else:
			_sector_blacks[i].visible = false
		var fr: float = _fill_ratio[i]
		var trail_r: float = _trail_ratio[i] if (fx and i < 3) else fr
		var fill_ang: Vector2
		var trail_ang: Vector2
		if i == 3:
			fill_ang = _cap_fill_angles(a0, a1, fr)
			trail_ang = fill_ang
		else:
			fill_ang = _hp_fill_angles(a0_eff, a1, fr)
			trail_ang = _hp_fill_angles(a0_eff, a1, trail_r)
		## Full trail underlay matching trail_r (under fill). Visible lag = trail beyond fill tip.
		if fx and i < 3 and trail_r > fr + 0.001:
			var tc: Color = TRAIL_COLOR
			tc.r = clampf(tc.r * pulse, 0.0, 1.0)
			tc.g = clampf(tc.g * pulse, 0.0, 1.0)
			tc.b = clampf(tc.b * pulse, 0.0, 1.0)
			_set_mat_color(_sector_trails[i], tc)
			_sector_trails[i].visible = true
			_sector_trails[i].mesh = _build_annulus_mesh(r0, r1, trail_ang.x, trail_ang.y, segs)
		else:
			_sector_trails[i].visible = false
		if fr <= 0.001:
			_sector_fills[i].visible = false
		else:
			_sector_fills[i].visible = true
			_sector_fills[i].mesh = _build_annulus_mesh(r0, r1, fill_ang.x, fill_ang.y, segs)
		_apply_ring_greens(i, a0_eff, a1, fill_ang, fx)


func _apply_ring_greens(idx: int, a0_eff: float, a1: float, fill_ang: Vector2, fx: bool) -> void:
	var batches: Array = _green_batches[idx]
	var r0: float = _sector_r0[idx]
	var r1: float = _sector_r1[idx]
	var segs: int = RING_SEGS_CAP if idx == 3 else RING_SEGS_HP
	if not fx or batches.is_empty() or _fill_ratio[idx] <= 0.001:
		for b: Variant in batches:
			if typeof(b) == TYPE_DICTIONARY:
				@warning_ignore("unsafe_cast")
				var mi0: MeshInstance3D = __mesh((b as Dictionary).get("mesh"))
				if mi0:
					mi0.visible = false
		return
	var span: float = a1 - a0_eff
	var remain_frac: float = clampf(_fill_ratio[idx], 0.0, 1.0)
	if idx == 3:
		## Cap: newest at tip fa1; length = cap_span * frac.
		var cursor: float = fill_ang.y
		var cap_span: float = a1 - a0_eff
		if absf(cap_span) < 0.0001:
			cap_span = _sector_a1[idx] - _sector_a0[idx]
		for i: int in range(batches.size() - 1, -1, -1):
			var b: Variant = batches[i]
			if typeof(b) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var d: Dictionary = b
			@warning_ignore("unsafe_cast")
			var mi: MeshInstance3D = __mesh(d.get("mesh"))
			if mi == null or not is_instance_valid(mi):
				continue
			if remain_frac <= 0.0005 or cursor <= fill_ang.x + 0.0005:
				mi.visible = false
				continue
			var frac: float = __as_float(d.get("frac", -1.0))
			if frac < 0.0:
				frac = clampf(__as_float(d.get("amount", 0.0)) / maxf(_prev_max[idx], 0.001), 0.0, 1.0)
			frac = minf(frac, remain_frac)
			remain_frac -= frac
			var gspan: float = cap_span * frac
			gspan = minf(gspan, cursor - fill_ang.x)
			var ga0: float = cursor - gspan
			var col: Color = GREEN_COLOR
			col.a = _green_alpha(__as_float(d.get("age", 0.0))) * 0.25
			_set_mat_color(mi, col)
			if gspan > 0.0005:
				mi.visible = true
				mi.mesh = _build_annulus_mesh(r0, r1, ga0, cursor, segs)
			else:
				mi.visible = false
			cursor = ga0
	else:
		## HP: newest at tip fa0; length = span * frac (heal/max only).
		var cursor2: float = fill_ang.x
		for j: int in range(batches.size() - 1, -1, -1):
			var b2: Variant = batches[j]
			if typeof(b2) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var d2: Dictionary = b2
			@warning_ignore("unsafe_cast")
			var mi2: MeshInstance3D = __mesh(d2.get("mesh"))
			if mi2 == null or not is_instance_valid(mi2):
				continue
			if remain_frac <= 0.0005 or cursor2 >= fill_ang.y - 0.0005:
				mi2.visible = false
				continue
			var frac2: float = __as_float(d2.get("frac", -1.0))
			if frac2 < 0.0:
				frac2 = clampf(__as_float(d2.get("amount", 0.0)) / maxf(_prev_max[idx], 0.001), 0.0, 1.0)
			frac2 = minf(frac2, remain_frac)
			remain_frac -= frac2
			var gspan2: float = span * frac2
			gspan2 = minf(gspan2, fill_ang.y - cursor2)
			var ga1: float = cursor2 + gspan2
			var col2: Color = GREEN_COLOR
			col2.a = _green_alpha(__as_float(d2.get("age", 0.0)))
			_set_mat_color(mi2, col2)
			if gspan2 > 0.0005:
				mi2.visible = true
				mi2.mesh = _build_annulus_mesh(r0, r1, cursor2, ga1, segs)
			else:
				mi2.visible = false
			cursor2 = ga1


func _process(delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	if not _fit_lance_mats.is_empty():
		var t: float = Time.get_ticks_msec() * 0.001
		for m_v: Variant in _fit_lance_mats:
			if typeof(m_v) == TYPE_OBJECT and m_v is ShaderMaterial:
				var sm: ShaderMaterial = m_v
				sm.set_shader_parameter("sweep_rad", t * 0.28)
	_sync_layer_values()
	_tick_fx(delta)
	_apply_visuals()
	_tick_star_border(delta)
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	var center: Vector3 = _ship.global_position
	var edge_dist: float = __as_float(DataStore.visual.get("health_bar_y_offset", 1.85))
	var radius_wu: float = 1.0
	if _ship is ShipUnit:
		@warning_ignore("unsafe_cast")
		var su: ShipUnit = _ship as ShipUnit
		center = su.visual_center_world()
		radius_wu = maxf(su.visual_radius_world(), 0.5)
	var cam_pull: float = __as_float(DataStore.visual.get("health_bar_cam_pull_wu", 0.55))
	cam_pull += radius_wu * __as_float(DataStore.visual.get("health_bar_cam_pull_radius_mul", 0.12))
	var toward_cam: Vector3 = cam.global_position - center
	if toward_cam.length_squared() > 0.0001:
		toward_cam = toward_cam.normalized()
	else:
		toward_cam = Vector3.FORWARD
	global_position = center + Vector3.UP * edge_dist + toward_cam * cam_pull
	var dist: float = cam.global_position.distance_to(global_position)
	var ref_d: float = __as_float(DataStore.visual.get("health_bar_ref_distance", 28.0))
	var sc: float = clampf(dist / maxf(ref_d, 1.0), 0.7, 1.6)
	scale = Vector3.ONE * sc
	if cam.global_position.distance_squared_to(global_position) > 0.0001:
		look_at(cam.global_position, Vector3.UP)

func flash_lock_brackets(duration_s: float = 0.45) -> void:
	## Procedural open square around tonnage overlay BG: mid-half of each edge missing; red→yellow→red.
	var size_wu: float = OVERLAY_BG_WORLD_SIZE * 1.02
	var badge_y: float = 0.0
	if _overlay_bg != null and is_instance_valid(_overlay_bg):
		badge_y = _overlay_bg.position.y
		size_wu = OVERLAY_BG_WORLD_SIZE * 1.02
	elif _tonnage_icon != null and is_instance_valid(_tonnage_icon):
		badge_y = _tonnage_icon.position.y
	var root: Node3D = get_node_or_null("LockFlashRoot") as Node3D
	if root != null:
		root.queue_free()
	root = Node3D.new()
	root.name = "LockFlashRoot"
	root.position = Vector3(0, badge_y, 0.06)
	add_child(root)
	var half: float = size_wu * 0.5
	var corner: float = size_wu * 0.25 ## each end segment = 1/4 edge
	var mats: Array[StandardMaterial3D] = []
	var ends: Array[Vector3] = [
		Vector3(-half, half, 0), Vector3(-half + corner, half, 0),
		Vector3(half - corner, half, 0), Vector3(half, half, 0),
		Vector3(-half, -half, 0), Vector3(-half + corner, -half, 0),
		Vector3(half - corner, -half, 0), Vector3(half, -half, 0),
		Vector3(-half, half, 0), Vector3(-half, half - corner, 0),
		Vector3(-half, -half + corner, 0), Vector3(-half, -half, 0),
		Vector3(half, half, 0), Vector3(half, half - corner, 0),
		Vector3(half, -half + corner, 0), Vector3(half, -half, 0),
	]
	var si: int = 0
	while si + 1 < ends.size():
		var a: Vector3 = ends[si]
		var b: Vector3 = ends[si + 1]
		si += 2
		var mi: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		var mid: Vector3 = (a + b) * 0.5
		var length: float = a.distance_to(b)
		var along_x: bool = absf(a.y - b.y) < 0.0001
		if along_x:
			box.size = Vector3(maxf(length, 0.001), 0.02, 0.02)
		else:
			box.size = Vector3(0.02, maxf(length, 0.001), 0.02)
		mi.mesh = box
		mi.position = mid
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.15, 0.12, 1.0)
		mat.no_depth_test = true
		mat.render_priority = 30
		mi.material_override = mat
		root.add_child(mi)
		mats.append(mat)
	var tw: Tween = create_tween()
	tw.set_parallel(false)
	var half_t: float = maxf(0.05, duration_s * 0.5)
	tw.tween_method(func(t: float) -> void:
		var c: Color = Color(1.0, 0.15, 0.12, 1.0).lerp(Color(1.0, 0.92, 0.15, 1.0), t)
		for mat_m: StandardMaterial3D in mats:
			mat_m.albedo_color = c
	, 0.0, 1.0, half_t)
	tw.tween_method(func(t: float) -> void:
		var c: Color = Color(1.0, 0.92, 0.15, 1.0).lerp(Color(1.0, 0.15, 0.12, 1.0), t)
		for mat_m2: StandardMaterial3D in mats:
			mat_m2.albedo_color = c
	, 0.0, 1.0, half_t)
	tw.tween_callback(func() -> void:
		if is_instance_valid(root):
			root.queue_free()
	)
