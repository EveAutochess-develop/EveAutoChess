extends Node
class_name PointerInput
## PC primary + touch auxiliary unified pointer (INPUT_PC_TOUCH_MAP).
## Mouse and single-finger touch both feed _pointer_*; board picks use the same
## camera ray + model/solid-cell hit tests (BOARD_AND_INPUT §4) — no touch-only soft sphere.

signal drag_begin(ship: ShipUnit)
signal drag_move(world: Vector3)
signal drag_end(sell: bool, slot: Dictionary)
signal tap_ship(ship: ShipUnit)
signal hover_ship(ship: ShipUnit)

## Pixels before Prepare ship press becomes a board drag (short click = info pin).
const SHIP_DRAG_THRESHOLD_PX: float = 10.0

var _root: MatchRoot
var _camera: Camera3D
var _board: BoardController
var _dragging: bool = false
var _press_ship: ShipUnit = null
var _press_screen: Vector2 = Vector2.ZERO
var _ship_drag_armed: bool = false
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
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pointer_down(mb.position)
			else:
				_pointer_up(mb.position)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if _dragging:
			_pointer_drag(mm.position)
		elif _ship_drag_armed and _press_ship != null:
			_try_promote_ship_drag(mm.position)
			if _dragging:
				_pointer_drag(mm.position)
			else:
				_update_hover(mm.position)
		else:
			_update_hover(mm.position)
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.index > 0:
			return  # ignore 2nd finger
		if st.pressed:
			_touch_index = st.index
			_pointer_down(st.position)
		elif st.index == _touch_index:
			_pointer_up(st.position)
			_touch_index = -1
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		if sd.index != _touch_index:
			return
		if _dragging:
			_pointer_drag(sd.position)
		elif _ship_drag_armed and _press_ship != null:
			_try_promote_ship_drag(sd.position)
			if _dragging:
				_pointer_drag(sd.position)

func _pointer_down(screen: Vector2) -> void:
	_press_screen = screen
	_ship_drag_armed = false
	if _root.match_ctrl.stage != MatchController.Stage.PREPARE:
		# tap for info only (player or AI)
		var ship: ShipUnit = _ray_ship(screen)
		if ship:
			tap_ship.emit(ship)
		return
	if _ui_blocks(screen):
		return
	## Prefer function-bucket strip unequip over moving the hull (EQUIPMENT.md).
	if _root and _root.has_method("try_begin_fit_unequip_at_screen"):
		if TypedVariant.as_bool(_root.call("try_begin_fit_unequip_at_screen", screen), false):
			get_viewport().set_input_as_handled()
			return
	var ship2: ShipUnit = _ray_ship(screen)
	if ship2 == null:
		return
	## Berth titans answer the ray so they can be inspected, but they hold no slot, and
	## the salvage freighter is scenery on our team: both are tap-only, so the sell
	## zone never flashes for a hull the board will refuse (FREIGHTER_AND_TITAN §1.2 · §2.1).
	if not _board.is_board_piece(ship2) or ship2.is_protect_target:
		tap_ship.emit(ship2)
		get_viewport().set_input_as_handled()
		return
	var allow_drag: bool = ship2.team_id == ShipUnit.TEAM_PLAYER
	if not allow_drag and get_tree().paused and GameSession.enemy_layout_adjust_active():
		## Dev-only: Prepare+paused enemy layout tweak.
		allow_drag = true
	if allow_drag:
		_press_ship = ship2
		_ship_drag_armed = true
		get_viewport().set_input_as_handled()
	else:
		## Enemy hull (incl. AI covert cyno on our half) — not ours to move.
		if _root:
			_root.show_notice("这是敌方单位")
		tap_ship.emit(ship2)
		get_viewport().set_input_as_handled()

func _try_promote_ship_drag(screen: Vector2) -> void:
	if _dragging or not _ship_drag_armed or _press_ship == null:
		return
	if screen.distance_to(_press_screen) < SHIP_DRAG_THRESHOLD_PX:
		return
	if not is_instance_valid(_press_ship):
		_press_ship = null
		_ship_drag_armed = false
		return
	_ship_drag_armed = false
	_dragging = true
	drag_begin.emit(_press_ship)

func _pointer_drag(screen: Vector2) -> void:
	var w: Vector3 = _screen_to_ground(screen)
	drag_move.emit(w)

func _pointer_up(screen: Vector2) -> void:
	if _ship_drag_armed and not _dragging:
		## Short click on own piece — pin ship detail (PC + mobile, INPUT_PC_TOUCH_MAP).
		var ship_tap: ShipUnit = _press_ship if _press_ship != null and is_instance_valid(_press_ship) else _ray_ship(screen)
		_press_ship = null
		_ship_drag_armed = false
		if ship_tap:
			tap_ship.emit(ship_tap)
		return
	if not _dragging:
		var ship: ShipUnit = _ray_ship(screen)
		if ship:
			tap_ship.emit(ship)
		return
	_dragging = false
	## The pressed hull can be gone by release (star merge on a prior action, sell).
	if _press_ship != null and not is_instance_valid(_press_ship):
		_press_ship = null
	var sell: bool = _in_sell_zone(screen)
	var slot: Dictionary = {}
	if not sell:
		## Dropping onto another of your own ships = swap intent (BOARD_AND_INPUT §4).
		## Prefer the hull under the cursor over nearest-empty-cell, or the swap misses.
		## Exclude the dragged hull — it sits under the cursor while following the pointer.
		var under: ShipUnit = _ray_ship(screen, _press_ship)
		if (
			_press_ship != null
			and under != null
			and under != _press_ship
			and under.team_id == _press_ship.team_id
			and not under.is_protect_target
			and _board.is_board_piece(under)
		):
			var side: int = under.team_id
			if under.slot_type == "field":
				side = _board.ship_world_side(under)
			slot = {
				"slot_type": under.slot_type,
				"x": under.grid_x,
				"z": under.grid_z,
				"team": side,
				"swap_instance_id": under.get_instance_id(),
			}
		else:
			var team: int = ShipUnit.TEAM_PLAYER
			var field_side: int = -1
			if _press_ship:
				team = _press_ship.team_id
				if _press_ship.deploy_enemy_half_only:
					field_side = ShipUnit.TEAM_AI if team == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
				elif _press_ship.slot_type == "field":
					field_side = _board.ship_world_side(_press_ship)
			var origin: Vector3 = _camera.project_ray_origin(screen)
			var dir: Vector3 = _camera.project_ray_normal(screen)
			slot = _board.pick_slot_by_ray(origin, dir, team, field_side)
	drag_end.emit(sell, slot)
	_press_ship = null

func hovered_ship() -> ShipUnit:
	return _hover if _hover != null and is_instance_valid(_hover) else null

func pick_ship_at_screen(screen: Vector2) -> ShipUnit:
	return _ray_ship(screen)

func _update_hover(screen: Vector2) -> void:
	if _hover != null and not is_instance_valid(_hover):
		_hover = null
	var ship: ShipUnit = _ray_ship(screen)
	if ship != _hover:
		_hover = ship
		hover_ship.emit(ship)

func _ray_ship(screen: Vector2, exclude: ShipUnit = null) -> ShipUnit:
	var origin: Vector3 = _camera.project_ray_origin(screen)
	var dir: Vector3 = _camera.project_ray_normal(screen)
	var ship: ShipUnit = _board.pick_ship_at(origin, dir, exclude)
	if ship:
		return ship
	## Nullsec berth titans are decorative and not board-registered.
	if _root and _root.has_method("_pick_berth_unit_under_cursor"):
		## Reuse berth pick with explicit ray (cursor path already known).
		for berth_name: String in ["_titan_berth", "_rival_titan_berth"]:
			var berth_v: Variant = _root.get(berth_name)
			if berth_v is Node and is_instance_valid(berth_v):
				var berth: Node = berth_v
				if berth.has_method("pick_hits_ray"):
					if TypedVariant.as_bool(berth.call("pick_hits_ray", origin, dir), false):
						var unit_v: Variant = berth.get("unit")
						if unit_v is ShipUnit and is_instance_valid(unit_v):
							var su: ShipUnit = unit_v
							return su
	return null

func _screen_to_ground(screen: Vector2) -> Vector3:
	var origin: Vector3 = _camera.project_ray_origin(screen)
	var dir: Vector3 = _camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	var t: float = -origin.y / dir.y
	return origin + dir * t

func _in_sell_zone(screen: Vector2) -> bool:
	var sell: Control = _root.hud.get_node_or_null("Root/Shop/ShopCol/ShopContent/ShopInner/SellZone") as Control
	if sell == null or not sell.visible:
		# During drag sell overlay may cover slots area — also accept full shop rect
		var shop: Control = _root.hud.get_node_or_null("Root/Shop") as Control
		if shop == null or not shop.visible:
			return false
		var content: Control = _root.hud.get_node_or_null("Root/Shop/ShopCol/ShopContent") as Control
		if content and not content.visible:
			return false
		return shop.get_global_rect().has_point(screen)
	return sell.get_global_rect().has_point(screen)

func _control_blocks(path: String, screen: Vector2, require_visible_content: bool = false) -> bool:
	var c: Control = _root.hud.get_node_or_null(path) as Control
	if c == null or not c.visible:
		return false
	if require_visible_content:
		## Shop content may be collapsed while the Shop root still fills the bottom strip.
		var content: Control = c.get_node_or_null("ShopCol/ShopContent") as Control
		if content and not content.visible:
			return false
	return c.get_global_rect().has_point(screen)

func _ui_blocks(screen: Vector2) -> bool:
	if _root == null or _root.hud == null:
		return false
	## Bottom shop (when expanded), left reserve, right info — not the full HUD root.
	if _control_blocks("Root/Shop", screen, true):
		return true
	if _control_blocks("Root/LeftCol", screen):
		return true
	if _control_blocks("Root/RightCol", screen):
		return true
	return false
