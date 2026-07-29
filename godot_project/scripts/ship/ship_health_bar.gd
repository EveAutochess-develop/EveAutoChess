extends Node3D
## Horizontal triple bars: shield / armor / structure. Anchored above ship (world-up).
## Tonnage icon sits in the CENTER of the overlay (not a corner badge).
## Badge size is a fixed world footprint — never follows ship long-axis or raw PNG resolution.

const BAR_W := 1.4
const BAR_H := 0.1
const BAR_GAP := 0.04
const BADGE_SIZE := 0.8
## Target on-screen world size for tonnage icons (independent of PNG resolution / ship long-axis).
const BADGE_WORLD_SIZE := 0.72
const BADGE_PIXEL_SIZE := 0.024
const COLORS := [
	Color(0.25, 0.55, 1.0, 0.95),
	Color(0.95, 0.82, 0.2, 0.95),
	Color(0.9, 0.22, 0.2, 0.95),
]
const BG := Color(0.08, 0.08, 0.1, 0.0)

var _ship: Node3D  # ShipUnit
var _fills: Array[MeshInstance3D] = []
var _bgs: Array[MeshInstance3D] = []
var _tonnage_icon: Sprite3D
var _tonnage_label: Label3D
var _tonnage_plate: MeshInstance3D

func setup(ship: Node3D) -> void:
	_ship = ship
	top_level = true
	_build()
	refresh()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_fills.clear()
	_bgs.clear()
	_tonnage_icon = null
	_tonnage_label = null
	_tonnage_plate = null
	var total_h := 3.0 * BAR_H + 2.0 * BAR_GAP
	var y0 := total_h * 0.5 - BAR_H * 0.5
	## Bars first (local origin = overlay center).
	for i in range(3):
		var y := y0 - float(i) * (BAR_H + BAR_GAP)
		var bg := _make_box(BG)
		bg.position = Vector3(0, y, 0)
		add_child(bg)
		_bgs.append(bg)
		var fill := _make_box(COLORS[i])
		fill.position = Vector3(0, y, 0.01)
		add_child(fill)
		_fills.append(fill)
	## Tonnage icon: dead center of overlay (above mid bar stack).
	var badge_y := total_h * 0.5 + BADGE_SIZE * 0.55 + 0.06
	_tonnage_plate = _make_badge_plate()
	_tonnage_plate.position = Vector3(0, badge_y, -0.02)
	add_child(_tonnage_plate)
	var icon_tex := UiAssets.tonnage_icon(_tonnage_group())
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
		return
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

func _tonnage_group() -> String:
	if _ship == null:
		return ""
	var su := _ship as ShipUnit
	if su != null and su.is_unmanned:
		match su.unmanned_kind:
			"fighter":
				return "fighter"
			"heavy_repair_drone":
				return "heavy_repair_drone"
			"combat_drone":
				var sg := _ship_group_from_data()
				if sg in ["drone_medium", "drone_heavy", "drone_light"]:
					return sg
				if sg.begins_with("drone_"):
					return sg
				return "drone_light"
			_:
				var g2 := _ship_group_from_data()
				if g2 != "":
					return g2
				return "drone_light"
	var g := _ship_group_from_data()
	return g if g != "" else "frigate"

func _ship_group_from_data() -> String:
	if _ship == null:
		return ""
	var su := _ship as ShipUnit
	var sid := su.ship_id if su != null else int(_ship.get("ship_id"))
	var sd: Dictionary = DataStore.get_ship(sid) if DataStore else {}
	return str(sd.get("ship_group", ""))

func _badge_pixel_size(tex: Texture2D) -> float:
	## Fixed world footprint — never follow ship long-axis or raw PNG pixel count.
	if tex == null:
		return BADGE_PIXEL_SIZE
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	if longest < 1.0:
		return BADGE_PIXEL_SIZE
	return BADGE_WORLD_SIZE / longest

func _tonnage_text() -> String:
	if _ship == null:
		return "?"
	var group := _tonnage_group()
	match group:
		"frigate":
			return "护"
		"destroyer":
			return "驱"
		"cruiser":
			return "巡"
		"battlecruiser":
			return "战巡"
		"battleship":
			return "战"
		"carrier":
			return "航"
		"dreadnought":
			return "无畏"
		"force_auxiliary":
			return "后勤"
		"fighter":
			return "舰载"
		"drone_light", "drone_medium", "drone_heavy", "heavy_repair_drone", "repair_drone":
			return "无人"
		_:
			if bool(_ship.get("is_unmanned")):
				return "无人"
			return "?"

func _tonnage_color() -> Color:
	if _ship == null:
		return Color(0.95, 0.95, 1.0)
	var group := _tonnage_group()
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
			if bool(_ship.get("is_unmanned")):
				return Color(0.85, 0.9, 0.75)
			return Color(0.95, 0.95, 1.0)

func _make_badge_plate() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BADGE_SIZE, BADGE_SIZE, 0.03)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.06, 0.08, 0.12, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 18
	mi.material_override = mat
	return mi

func _make_box(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BAR_W, BAR_H, 0.04)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 10
	mi.material_override = mat
	return mi

func refresh() -> void:
	if _ship == null or _fills.size() < 3:
		return
	_set_fill(0, float(_ship.get("shield_hp")), float(_ship.get("max_shield")))
	_set_fill(1, float(_ship.get("armor_hp")), float(_ship.get("max_armor")))
	_set_fill(2, float(_ship.get("structure_hp")), float(_ship.get("max_structure")))
	visible = not bool(_ship.get("is_destroyed"))
	if _tonnage_icon:
		var tex := UiAssets.tonnage_icon(_tonnage_group())
		_tonnage_icon.texture = tex
		_tonnage_icon.pixel_size = _badge_pixel_size(tex)
	if _tonnage_label:
		_tonnage_label.text = _tonnage_text()
		_tonnage_label.modulate = _tonnage_color()

func _set_fill(idx: int, cur: float, mx: float) -> void:
	## Clamp both ends so bars never scale past mesh width (avoids visual overflow).
	var safe_max := maxf(mx, 0.0)
	var safe_cur := clampf(cur, 0.0, safe_max if safe_max > 0.0 else 0.0)
	var ratio := 0.0 if safe_max <= 0.0 else clampf(safe_cur / safe_max, 0.0, 1.0)
	var fill := _fills[idx]
	var y := fill.position.y
	fill.scale = Vector3(maxf(ratio, 0.001), 1, 1)
	fill.position = Vector3(-BAR_W * 0.5 + BAR_W * ratio * 0.5, y, 0.01)

func _process(_delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	var center := _ship.global_position
	## Fixed offset — do NOT follow model long-axis / visual_radius (that blew up capital badges + bars).
	var edge_dist := float(DataStore.visual.get("health_bar_y_offset", 1.6))
	if _ship is ShipUnit:
		center = (_ship as ShipUnit).visual_center_world()
	global_position = center + Vector3.UP * edge_dist
	var dist := cam.global_position.distance_to(global_position)
	var ref_d := float(DataStore.visual.get("health_bar_ref_distance", 28.0))
	var sc := clampf(dist / maxf(ref_d, 1.0), 0.7, 1.6)
	scale = Vector3.ONE * sc
	if cam.global_position.distance_squared_to(global_position) > 0.0001:
		look_at(cam.global_position, Vector3.UP)
