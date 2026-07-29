extends Node
class_name PointerInput
## PC primary + touch auxiliary unified pointer (INPUT_PC_TOUCH_MAP).

signal drag_begin(ship: ShipUnit)
signal drag_move(world: Vector3)
signal drag_end(sell: bool, slot: Dictionary)
signal tap_ship(ship: ShipUnit)
signal hover_ship(ship: ShipUnit)

var _root: MatchRoot
var _camera: Camera3D
var _board: BoardController
var _dragging: bool = false
var _press_ship: ShipUnit = null
var _hover: ShipUnit = null
var _touch_index: int = -1

func setup(root: MatchRoot, camera: Camera3D, board: BoardController) -> void:
	_root = root
	_camera = camera
	_board = board

func is_pointer_dragging() -> bool:
	return _dragging

func ui_blocks_screen(screen: Vector2) -> bool:
	return _ui_blocks(screen)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pointer_down(mb.position)
			else:
				_pointer_up(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_pointer_drag(mm.position)
		else:
			_update_hover(mm.position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.index > 0:
			return  # ignore 2nd finger
		if st.pressed:
			_touch_index = st.index
			_pointer_down(st.position)
		elif st.index == _touch_index:
			_pointer_up(st.position)
			_touch_index = -1
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _touch_index and _dragging:
			_pointer_drag(sd.position)

func _pointer_down(screen: Vector2) -> void:
	if _root.match_ctrl.stage != MatchController.Stage.PREPARE:
		# tap for info only (player or AI)
		var ship := _ray_ship(screen)
		if ship:
			tap_ship.emit(ship)
		return
	if _ui_blocks(screen):
		return
	var ship2 := _ray_ship(screen)
	if ship2 == null:
		return
	var allow_drag := ship2.team_id == ShipUnit.TEAM_PLAYER
	if not allow_drag and get_tree().paused:
		allow_drag = true
	if allow_drag:
		_press_ship = ship2
		_dragging = true
		drag_begin.emit(ship2)
		get_viewport().set_input_as_handled()
	else:
		tap_ship.emit(ship2)
		get_viewport().set_input_as_handled()

func _pointer_drag(screen: Vector2) -> void:
	var w := _screen_to_ground(screen)
	drag_move.emit(w)

func _pointer_up(screen: Vector2) -> void:
	if not _dragging:
		var ship := _ray_ship(screen)
		if ship:
			tap_ship.emit(ship)
		return
	_dragging = false
	var sell := _in_sell_zone(screen)
	var slot := {}
	if not sell:
		var w := _screen_to_ground(screen)
		var team := ShipUnit.TEAM_PLAYER
		var field_side := -1
		if _press_ship:
			team = _press_ship.team_id
			if _press_ship.deploy_enemy_half_only:
				field_side = ShipUnit.TEAM_AI if team == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
			elif _press_ship.slot_type == "field":
				field_side = _board.ship_world_side(_press_ship)
		slot = _board.pick_slot_at(w, team, field_side)
	drag_end.emit(sell, slot)
	_press_ship = null

func _update_hover(screen: Vector2) -> void:
	var ship := _ray_ship(screen)
	if ship != _hover:
		_hover = ship
		hover_ship.emit(ship)

func _ray_ship(screen: Vector2) -> ShipUnit:
	var origin := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	return _board.pick_ship_at(origin, dir)

func _screen_to_ground(screen: Vector2) -> Vector3:
	var origin := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	var t := -origin.y / dir.y
	return origin + dir * t

func _in_sell_zone(screen: Vector2) -> bool:
	var sell := _root.hud.get_node_or_null("Root/Shop/ShopCol/ShopContent/ShopInner/SellZone") as Control
	if sell == null or not sell.visible:
		# During drag sell overlay may cover slots area — also accept full shop rect
		var shop := _root.hud.get_node_or_null("Root/Shop") as Control
		if shop == null or not shop.visible:
			return false
		var content := _root.hud.get_node_or_null("Root/Shop/ShopCol/ShopContent") as Control
		if content and not content.visible:
			return false
		return shop.get_global_rect().has_point(screen)
	return sell.get_global_rect().has_point(screen)

func _control_blocks(path: String, screen: Vector2, require_visible_content: bool = false) -> bool:
	var c := _root.hud.get_node_or_null(path) as Control
	if c == null or not c.visible:
		return false
	if require_visible_content:
		# Collapsed strips still occupy a thin rect — only block if content is up OR the strip itself is hit.
		pass
	return c.get_global_rect().has_point(screen)

func _ui_blocks(screen: Vector2) -> bool:
	## Only opaque HUD chrome blocks board picks; Root gaps are mouse IGNORE.
	if _control_blocks("Root/Shop", screen):
		return true
	if _control_blocks("Root/LeftCol", screen):
		return true
	if _control_blocks("Root/RightCol", screen):
		return true
	if _control_blocks("Root/RoundBar", screen):
		return true
	if _control_blocks("Root/TopRight", screen):
		return true
	return false
