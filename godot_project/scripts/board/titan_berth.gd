extends Node3D
class_name TitanBerth
## Nullsec seat titan parked under the board (MULTIPLAYER_PVP §2.4a).
## Hangar-span width, bow toward opposing half, bow tangent to dust-belt ×1.5,
## hull top clamped below deck plane. Decorative ShipUnit (not on board).

const RACE_SHIP_ID: Dictionary = {
	"caldari": 202,
	"gallente": 203,
	"minmatar": 204,
	"amarr": 201,
	## 唯一势力泰坦：征服者级 205（model_key=tsl_zhengfuzhe；禁止映射神使/其它帝国泰坦壳）。
	"angel": 205,
}
## TQ titan meshes point their bow at +长轴 end; flip so the bow faces the enemy half.
const BOW_FLIP: float = PI
## Pull the stern anchor slightly inboard so bar/badge don't float off the hull.
const STERN_INSET_FRAC: float = 0.08
## Same tonnage sizing ladder as ship hulls (UI_ICONS §6.1): icon+bg 1/2, corner badge 1/3.
const _ShipHealthBar: GDScript = preload("res://scripts/ship/ship_health_bar.gd")
const TONNAGE_WORLD_SIZE: float = _ShipHealthBar.BADGE_WORLD_SIZE
const OVERLAY_BG_WORLD_SIZE: float = _ShipHealthBar.OVERLAY_BG_WORLD_SIZE
const OVERLAY_TAG_WORLD_SIZE: float = _ShipHealthBar.OVERLAY_TAG_WORLD_SIZE
const OVERLAY_TAG_OFFSET: float = _ShipHealthBar.OVERLAY_TAG_OFFSET

## Race of the parked titan ("" = seat picked none → nothing spawned).
var race: String = ""
var ship_id: int = 0
## Decorative ShipUnit hull — never registered on the board, never targeted.
var unit: ShipUnit = null
## World-space bow-pin box used for the last solve (debug/verify).
var pin_box: AABB = AABB()
## true = local home berth (bow −Z); false = rival berth on far side (bow +Z).
var home_side: bool = true

var _belt_box: AABB = AABB()
## Stern-top anchor in berth-local space (solved once per pin).
var _stern_local: Vector3 = Vector3.ZERO
var _tonnage_overlay_root: Node3D = null
var _tonnage_bg: Sprite3D = null
var _tonnage_badge: Sprite3D = null
var _tonnage_tag: Sprite3D = null
var _engine_trail: EngineBoosterTrail = null


static func ship_id_for(p_race: String) -> int:
	var sid: int = ModManager.titan_ship_id_for(p_race)
	if sid > 0:
		return sid
	return TypedVariant.as_int(RACE_SHIP_ID.get(p_race.to_lower(), 0), 0)


func build(p_race: String, belt_box: AABB, p_home_side: bool = true) -> bool:
	name = "TitanBerth" if p_home_side else "TitanBerthRival"
	_belt_box = belt_box
	home_side = p_home_side
	return set_race(p_race)


## Prepare-time titan swap: same berth, re-solved scale/pin.
func set_race(p_race: String) -> bool:
	race = p_race.to_lower()
	ship_id = ship_id_for(race)
	if unit and is_instance_valid(unit):
		unit.queue_free()
	unit = null
	_clear_tonnage_badge()
	if ship_id <= 0:
		return false
	unit = ShipUnit.new()
	unit.name = "TitanHull"
	add_child(unit)
	unit.setup(ship_id, 1, ShipUnit.TEAM_PLAYER if home_side else ShipUnit.TEAM_AI)
	unit.clear_health_bar()
	## Berth is decor: no board slot, no combat, no drones.
	unit.slot_type = ""
	unit.immobile_in_combat = false
	## Bow toward opposing half (home −Z / rival +Z); no per-ship yaw jitter.
	var applied_bow_flip: bool = _orient_bow_at_opposing_half()
	_fit_scale()
	_pin_bow_to_belt()
	## BOW_FLIP puts SOF +Z “aft” nozzles on the visual bow — remirror so trails stay stern.
	## Hulls with baked bow_fit already coherent: never flip and never remirror on top.
	if applied_bow_flip and unit.has_method("compensate_bow_flip_for_engines"):
		unit.compensate_bow_flip_for_engines()
	_attach_tonnage_badge()
	_attach_key_light()
	_engine_trail = EngineBoosterTrail.ensure_on(unit, home_side)
	## Trails only while the hull is sliding in (§2.5). Parked / teleport / doomsday = off.
	if _engine_trail:
		EngineBoosterTrail.set_idle_plume_on(unit, 0.0)
		EngineBoosterTrail.set_emitting_on(unit, false)
	set_meta("titan_ship_id", ship_id)
	set_meta("titan_race", race)
	set_meta("titan_home_side", home_side)
	return true


## Top of the hull in world space.
func hull_top_y() -> float:
	if unit == null or not is_instance_valid(unit):
		return global_position.y
	var box: AABB = _world_aabb(unit)
	return box.position.y + box.size.y


## Stern-top anchor in world space — HP pipes / tonnage badge ride above this,
## so they never sit over the bow that points into the battlefield.
## Cached in local space: the bar polls this per frame, and the intro slides the berth.
func stern_top_point() -> Vector3:
	if unit == null or not is_instance_valid(unit):
		return global_position
	return to_global(_stern_local)


func _solve_stern_local() -> void:
	if unit == null or not is_instance_valid(unit):
		_stern_local = Vector3.ZERO
		return
	var hull: AABB = _world_aabb(unit)
	var inset: float = hull.size.z * STERN_INSET_FRAC
	var z: float = (hull.position.z + hull.size.z - inset) if home_side else (hull.position.z + inset)
	_stern_local = to_local(Vector3(hull.get_center().x, hull.position.y + hull.size.y, z))


## Fire / doomsday origin roughly at hull center.
func fire_point() -> Vector3:
	if unit == null or not is_instance_valid(unit):
		return global_position
	return _world_aabb(unit).get_center()


## Rough pick for hover / tap (closest-point vs inflated AABB).
func pick_hits_ray(origin: Vector3, dir: Vector3) -> bool:
	if not visible or unit == null or not is_instance_valid(unit):
		return false
	var box: AABB = _world_aabb(unit)
	if box.size.length() < 0.01:
		return false
	box = box.grow(1.2)
	var nd: Vector3 = dir.normalized()
	var center: Vector3 = box.get_center()
	var t: float = (center - origin).dot(nd)
	if t < 0.0:
		return false
	var closest: Vector3 = origin + nd * t
	var d: Vector3 = closest - center
	var half: Vector3 = box.size * 0.5
	return absf(d.x) <= half.x and absf(d.y) <= half.y and absf(d.z) <= half.z


func place_tonnage_badge() -> void:
	_place_tonnage_badge()


func set_engine_trail_emitting(on: bool) -> void:
	## Decorative hull: only the intro slide turns trails on; teleports never do.
	if unit == null or not is_instance_valid(unit):
		return
	if _engine_trail == null or not is_instance_valid(_engine_trail):
		_engine_trail = EngineBoosterTrail.ensure_on(unit, home_side)
	if _engine_trail == null:
		return
	EngineBoosterTrail.set_emitting_on(unit, on)


func _orient_bow_at_opposing_half() -> bool:
	## TQ titan GLBs are authored length-on-X (measured: 14k–18k on X vs 2k–6.4k on Z),
	## so the hull must end up length-on-Z before we pick which end faces the enemy.
	## ShipUnit auto-orient normally does this; berth re-checks in case content flips
	## `ship_model_auto_orient` or the def flag, otherwise the titan parks sideways.
	## Returns true when BOW_FLIP was applied (caller must remirror engine nozzles).
	if unit == null or not is_instance_valid(unit):
		return false
	## Empire TQ hulls need BOW_FLIP. Packs with baked bow_fit (Vanquisher) are already
	## nozzle-coherent — stacking flip reverses bow/stern and puts trails on the bow.
	var use_bow_flip: bool = not unit.has_baked_bow_fit()
	var flip: float = BOW_FLIP if use_bow_flip else 0.0
	## Base yaw puts the modelled bow at the enemy half; BOW_FLIP swaps ends when needed.
	var yaw: float = flip if home_side else flip + PI
	unit.rotation.y = yaw
	var box: AABB = _world_aabb(unit)
	if box.size.x > box.size.z:
		unit.rotation.y = yaw + PI * 0.5
	return use_bow_flip


func _target_width() -> float:
	## Hangar silhouette ≡ field_span_x (BoardController hangar_step default).
	var span: float = BoardController.field_span_x()
	var v: Dictionary = TypedVariant.as_dict(DataStore.visual)
	var k: float = TypedVariant.as_float(v.get("titan_berth_width_scale", 1.0), 1.0)
	return maxf(span * k, 1.0)


func _max_length_z() -> float:
	## Keep the hull from stretching across the whole scene once width-matched.
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var fh: int = TypedVariant.as_int(b.get("field_height", 6), 6)
	var hoz: float = absf(TypedVariant.as_float(b.get("hex_offset_z", -2.5), -2.5))
	var default_max: float = maxf(float(fh) * hoz * 1.6, 8.0)
	var v: Dictionary = TypedVariant.as_dict(DataStore.visual)
	return maxf(TypedVariant.as_float(v.get("titan_berth_max_length_z", default_max), default_max), 1.0)


func _fit_scale() -> void:
	## Hangar-span width (MULTIPLAYER_PVP §2.4a), capped by the length budget.
	var box: AABB = _world_aabb(unit)
	if box.size.x < 0.0001 or box.size.z < 0.0001:
		return
	var k_width: float = _target_width() / box.size.x
	var k_len: float = _max_length_z() / box.size.z
	unit.scale = unit.scale * minf(k_width, k_len)


func _pin_bow_to_belt() -> void:
	var v: Dictionary = TypedVariant.as_dict(DataStore.visual)
	var expand: float = TypedVariant.as_float(v.get("titan_berth_belt_expand", 1.5), 1.5)
	var center: Vector3 = _belt_box.get_center()
	var half: Vector3 = _belt_box.size * 0.5 * expand
	pin_box = AABB(center - half, half * 2.0)
	position = Vector3.ZERO
	var hull: AABB = _world_aabb(unit)
	var hull_center: Vector3 = hull.get_center()
	## Prefer belt-band Y, then clamp so hull top stays under the deck.
	var y: float = TypedVariant.as_float(v.get("titan_berth_y", center.y), center.y)
	## Home: bow (−Z face) tangent to player-side (+Z) wall of expanded box.
	## Rival: bow (+Z face) tangent to AI-side (−Z) wall.
	var bow_z: float
	var z_offset: float
	if home_side:
		bow_z = pin_box.position.z + pin_box.size.z
		z_offset = bow_z - hull.position.z
	else:
		bow_z = pin_box.position.z
		z_offset = bow_z - (hull.position.z + hull.size.z)
	position = Vector3(
		center.x - hull_center.x,
		y - hull_center.y,
		z_offset
	)
	_sink_below_deck()
	_solve_stern_local()
	print("[TitanBerth] race=%s home=%s pos=%s hull=%s pin=%s" % [race, home_side, position, hull.size, pin_box])


func _sink_below_deck() -> void:
	## Hard constraint: hull AABB top ≤ deck_y − clearance (MULTIPLAYER_PVP §2.4a).
	if unit == null or not is_instance_valid(unit):
		return
	var v: Dictionary = TypedVariant.as_dict(DataStore.visual)
	var clearance: float = TypedVariant.as_float(v.get("titan_berth_deck_clearance", 0.35), 0.35)
	var deck_y: float = TypedVariant.as_float(v.get("board_center_y", 0.0), 0.0)
	var hull: AABB = _world_aabb(unit)
	var top: float = hull.position.y + hull.size.y
	var max_top: float = deck_y - clearance
	if top > max_top:
		position.y -= (top - max_top)


func _attach_tonnage_badge() -> void:
	_clear_tonnage_badge()
	var tex: Texture2D = UiAssets.tonnage_icon("titan")
	if tex == null:
		return
	_tonnage_overlay_root = Node3D.new()
	_tonnage_overlay_root.name = "TonnageOverlay"
	add_child(_tonnage_overlay_root)
	_tonnage_overlay_root.top_level = true

	var set_key: String = "fleet" if home_side else "enemy"
	var set_tex: Dictionary = UiAssets.tonnage_overlay_set(set_key)
	var bg_v: Variant = set_tex.get("bg")
	var bg_tex: Texture2D = null
	if bg_v is Texture2D:
		@warning_ignore("unsafe_cast")
		bg_tex = bg_v as Texture2D
	if bg_tex:
		_tonnage_bg = _make_tonnage_sprite(bg_tex, OVERLAY_BG_WORLD_SIZE, 19, "TonnageBackground")
		_tonnage_bg.position = Vector3(0, 0, 0.02)
		_tonnage_overlay_root.add_child(_tonnage_bg)

	_tonnage_badge = _make_tonnage_sprite(tex, TONNAGE_WORLD_SIZE, 20, "TonnageBadge")
	_tonnage_badge.position = Vector3(0, 0, 0.04)
	_tonnage_overlay_root.add_child(_tonnage_badge)

	var tag_v: Variant = set_tex.get("badge")
	var tag_tex: Texture2D = null
	if tag_v is Texture2D:
		@warning_ignore("unsafe_cast")
		tag_tex = tag_v as Texture2D
	if tag_tex:
		_tonnage_tag = _make_tonnage_sprite(tag_tex, OVERLAY_TAG_WORLD_SIZE, 21, "TonnageCornerBadge")
		## Overlay root faces the camera; local -X/-Y is screen right/bottom.
		_tonnage_tag.position = Vector3(-OVERLAY_TAG_OFFSET, -OVERLAY_TAG_OFFSET, 0.06)
		_tonnage_overlay_root.add_child(_tonnage_tag)
	_place_tonnage_badge()


func _make_tonnage_sprite(tex: Texture2D, world_size: float, priority: int, node_name: String) -> Sprite3D:
	var spr: Sprite3D = Sprite3D.new()
	spr.name = node_name
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var longest: float = float(maxi(tex.get_width(), tex.get_height()))
	spr.pixel_size = world_size / maxf(longest, 1.0)
	spr.centered = true
	spr.shaded = false
	spr.double_sided = true
	spr.no_depth_test = true
	spr.render_priority = priority
	return spr


func _place_tonnage_badge() -> void:
	if _tonnage_overlay_root == null or not is_instance_valid(_tonnage_overlay_root):
		return
	var v: Dictionary = TypedVariant.as_dict(DataStore.visual)
	var margin: float = TypedVariant.as_float(v.get("titan_badge_stern_margin", 4.0), 4.0)
	_tonnage_overlay_root.global_position = stern_top_point() + Vector3.UP * margin
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam and cam.global_position.distance_squared_to(_tonnage_overlay_root.global_position) > 0.0001:
		_tonnage_overlay_root.look_at(cam.global_position, Vector3.UP)


func _process(_delta: float) -> void:
	## Intro slides and free-camera turns both keep all three layers locked together.
	_place_tonnage_badge()


func _clear_tonnage_badge() -> void:
	if _tonnage_overlay_root and is_instance_valid(_tonnage_overlay_root):
		_tonnage_overlay_root.queue_free()
	_tonnage_overlay_root = null
	_tonnage_bg = null
	_tonnage_badge = null
	_tonnage_tag = null
	var old: Node = get_node_or_null("TonnageOverlay")
	if old:
		old.queue_free()


func _attach_key_light() -> void:
	if get_node_or_null("BerthLight"):
		return
	var v: Dictionary = TypedVariant.as_dict(DataStore.visual)
	var energy: float = TypedVariant.as_float(v.get("titan_berth_light_energy", 2.4), 2.4)
	if energy <= 0.001:
		return
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "BerthLight"
	light.light_energy = energy
	light.omni_range = TypedVariant.as_float(v.get("titan_berth_light_range", 34.0), 34.0)
	light.light_color = Color(0.95, 0.95, 1.0)
	light.shadow_enabled = false
	light.position = Vector3(0, 8.0, 6.0 if home_side else -6.0)
	add_child(light)


func _world_aabb(root: Node3D) -> AABB:
	if root == null or not is_instance_valid(root):
		return AABB()
	var out: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in _meshes(root):
		var box: AABB = mi.get_aabb()
		var xf: Transform3D = mi.global_transform
		for i: int in range(8):
			var p: Vector3 = xf * box.get_endpoint(i)
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		@warning_ignore("unsafe_cast")
		out.append(node as MeshInstance3D)
	for c: Node in node.get_children():
		out.append_array(_meshes(c))
	return out
