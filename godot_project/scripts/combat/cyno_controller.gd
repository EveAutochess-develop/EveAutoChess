extends RefCounted
class_name CynoController
## Covert cyno channeling: multi-cyno OK; capitals jump-in with red light near a random active cyno.

const ANNOUNCE_INTERVAL_S := 20.0
const JUMP_DURATION_S := 0.85

var _board: BoardController
var _match: MatchController
var _combat: CombatResolver
var _pending_respawn: Array = []  # {team, ship_id, star, x, z, field_side_team}
## ship instance_id -> {end, next_announce}
var _active_channels: Dictionary = {}
## World-space FX nodes keyed by cyno ship instance_id.
var _channel_fx: Dictionary = {}


func bind(board: BoardController, match_ctrl: MatchController, combat: CombatResolver = null) -> void:
	_board = board
	_match = match_ctrl
	_combat = combat


func clear_channels() -> void:
	for iid in _active_channels.keys():
		_teardown_fx(int(iid))
	_active_channels.clear()
	_channel_fx.clear()


func has_active_channels() -> bool:
	return not _active_channels.is_empty()


## Combat ended (wipe / time limit): channels are cut, capitals stay in hangar.
## CAPITAL_AND_CYNO §2 — never force-complete a channel to hold the round open.
func abort_channels() -> void:
	for iid in _active_channels.keys():
		var ship := instance_from_id(int(iid)) as ShipUnit
		if ship != null and is_instance_valid(ship) and not ship.is_destroyed:
			_announce(ship, "诱导中断")
		_teardown_fx(int(iid))
	_active_channels.clear()
	_channel_fx.clear()


func on_battle_start(sim_time: float) -> void:
	clear_channels()
	for s in _board.all_ships():
		if s.slot_type != "field" or s.is_destroyed or s.is_unmanned:
			continue
		if not s.has_cyno_module():
			continue
		s.cyno_completed = false
		s.cyno_channel_ends_at = sim_time + s.cyno_duration_s()
		s.immobile_in_combat = true
		var iid := s.get_instance_id()
		_active_channels[iid] = {
			"end": s.cyno_channel_ends_at,
			"next_announce": sim_time + ANNOUNCE_INTERVAL_S,
		}
		_attach_fx(s)
		_announce(s, "诱导启动，读条 %.0fs" % s.cyno_duration_s())


func tick(sim_time: float) -> void:
	var done: Array = []
	for iid in _active_channels.keys():
		var ship := instance_from_id(int(iid)) as ShipUnit
		if ship == null or not is_instance_valid(ship) or ship.is_destroyed:
			if ship != null and is_instance_valid(ship):
				_announce(ship, "诱导中断")
			_teardown_fx(int(iid))
			done.append(iid)
			continue
		var info: Dictionary = _active_channels[iid]
		var end_t := float(info.get("end", 0.0))
		var next_ann := float(info.get("next_announce", 0.0))
		if sim_time >= next_ann and sim_time < end_t:
			var left := maxf(0.0, end_t - sim_time)
			_announce(ship, "诱导读条中，剩余 %.0fs" % left)
			info["next_announce"] = sim_time + ANNOUNCE_INTERVAL_S
			_active_channels[iid] = info
		if sim_time < end_t:
			continue
		_complete_cyno(ship)
		done.append(iid)
	for iid in done:
		_active_channels.erase(iid)


func on_ship_destroyed(ship: ShipUnit) -> void:
	if ship == null:
		return
	var iid := ship.get_instance_id()
	if _active_channels.has(iid):
		_announce(ship, "诱导中断")
		_teardown_fx(iid)
		_active_channels.erase(iid)


func _complete_cyno(cyno: ShipUnit) -> void:
	if cyno == null or not is_instance_valid(cyno):
		return
	var team := cyno.team_id
	var cyno_x := cyno.grid_x
	var cyno_z := cyno.grid_z
	var cyno_side := cyno.field_side_team if cyno.field_side_team >= 0 else team
	var cyno_sid := cyno.ship_id
	var cyno_star := cyno.star
	cyno.cyno_completed = true
	_teardown_fx(cyno.get_instance_id())
	_announce(cyno, "诱导完成，旗舰跃迁入场")
	## Landing cells: completing cyno grid + other still-channeling cynos (same team).
	var anchor_cells: Array[Vector2i] = [Vector2i(cyno_x, cyno_z)]
	var anchor_sides: Array[int] = [cyno_side]
	for iid in _active_channels.keys():
		var other := instance_from_id(int(iid)) as ShipUnit
		if other == null or not is_instance_valid(other) or other.is_destroyed:
			continue
		if other.get_instance_id() == cyno.get_instance_id():
			continue
		if other.team_id != team:
			continue
		anchor_cells.append(Vector2i(other.grid_x, other.grid_z))
		anchor_sides.append(other.field_side_team if other.field_side_team >= 0 else team)
	## Despawn covert cyno immediately (do not wait for capital jumps / end of frame).
	_despawn_cyno_ship(cyno)
	var capitals: Array = []
	for s in _board.all_ships():
		if s.team_id != team or s.is_destroyed or s.is_unmanned:
			continue
		if s.slot_type != "hangar":
			continue
		if s.requires_cyno_entry:
			capitals.append(s)
	var warped := 0
	for pick_any in capitals:
		var pick: ShipUnit = pick_any
		if pick == null or not is_instance_valid(pick) or pick.is_destroyed:
			continue
		var ai := randi() % anchor_cells.size()
		var ac: Vector2i = anchor_cells[ai]
		var side: int = anchor_sides[ai]
		var cell := _pick_cell_near(team, side, ac.x, ac.y, 6)
		if cell.x < 0:
			break
		var land := BoardController.cell_to_world("field", side, cell.x, cell.y)
		_board.move_ship_to_field_side(pick, cell.x, cell.y, side)
		pick.reset_combat_runtime()
		_play_capital_jump(pick, land)
		if _combat:
			_combat.ensure_auxiliaries_for(pick)
		warped += 1
	if warped > 0:
		_board.recalculate_fetters(team)
		if _match:
			_match.hud_refresh.emit()
	_pending_respawn.append({
		"team": team,
		"ship_id": cyno_sid,
		"star": cyno_star,
		"x": cyno_x,
		"z": cyno_z,
		"field_side_team": cyno_side,
	})


func _despawn_cyno_ship(cyno: ShipUnit) -> void:
	if cyno == null or not is_instance_valid(cyno):
		return
	_teardown_fx(cyno.get_instance_id())
	cyno.visible = false
	cyno.is_destroyed = true
	cyno.immobile_in_combat = false
	if _board:
		_board.remove_ship_node(cyno)


func _play_capital_jump(ship: ShipUnit, land: Vector3) -> void:
	var world := _board.get_world_root() if _board else null
	if world == null or ship == null:
		ship.global_position = land
		ship.set_combat_tint(true)
		if ship.has_method("rebuild_health_bar"):
			ship.rebuild_health_bar()
		if _combat and _combat.has_method("schedule_capital_hull_morph"):
			_combat.schedule_capital_hull_morph(ship)
		elif ship.has_method("begin_hull_morph_if_needed"):
			ship.begin_hull_morph_if_needed()
		return
	var fx := CapitalJumpFx.new()
	fx.name = "CapitalJumpFx_%d" % ship.get_instance_id()
	world.add_child(fx)
	fx.play(ship, land, JUMP_DURATION_S, func () -> void:
		if ship == null or not is_instance_valid(ship):
			return
		if _combat and _combat.has_method("schedule_capital_hull_morph"):
			_combat.schedule_capital_hull_morph(ship)
		elif ship.has_method("begin_hull_morph_if_needed"):
			ship.begin_hull_morph_if_needed()
	)


func _announce(ship: ShipUnit, msg: String) -> void:
	if _match == null:
		return
	var who := str(DataStore.get_ship(ship.ship_id).get("name", "诱导舰"))
	_match.notice.emit("%s：%s" % [who, msg])


func _attach_fx(ship: ShipUnit) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var iid := ship.get_instance_id()
	_teardown_fx(iid)
	var world := _board.get_world_root() if _board else null
	if world == null:
		return
	var fx := CynoChannelFx.new()
	fx.name = "CynoChannelFx_%d" % iid
	world.add_child(fx)
	fx.setup(ship)
	_channel_fx[iid] = fx


func _teardown_fx(ship_iid: int) -> void:
	if _channel_fx.has(ship_iid):
		var fx = _channel_fx[ship_iid]
		_channel_fx.erase(ship_iid)
		if fx != null and is_instance_valid(fx):
			fx.queue_free()
		return
	## Legacy: FX parented under ship.
	var ship := instance_from_id(ship_iid) as ShipUnit
	if ship == null or not is_instance_valid(ship):
		return
	var old := ship.get_node_or_null("CynoChannelFx")
	if old != null and is_instance_valid(old):
		old.queue_free()


func _pick_cell_near(owner_team: int, _side_team: int, cx: int, cz: int, radius: int) -> Vector2i:
	var fh := int(DataStore.board.get("field_height", 6))
	var candidates: Array[Vector2i] = []
	for z in range(fh):
		var cols: int = BoardController.field_cols_at(z)
		for x in range(cols):
			var d: int = absi(x - cx) + absi(z - cz)
			if d < 1 or d > radius:
				continue
			if _board.is_field_cell_free_for(owner_team, x, z):
				candidates.append(Vector2i(x, z))
	if candidates.is_empty():
		for z2 in range(fh):
			var cols2: int = BoardController.field_cols_at(z2)
			for x2 in range(cols2):
				if _board.is_field_cell_free_for(owner_team, x2, z2):
					candidates.append(Vector2i(x2, z2))
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[randi() % candidates.size()]


func on_prepare_start() -> void:
	var pending := _pending_respawn.duplicate(true)
	_pending_respawn.clear()
	clear_channels()
	for entry in pending:
		var team := int(entry.get("team", 0))
		var sid := int(entry.get("ship_id", 0))
		var star := int(entry.get("star", 1))
		var x := int(entry.get("x", 0))
		var z := int(entry.get("z", 0))
		var side := int(entry.get("field_side_team", team))
		if not _board.is_field_cell_free_for(team, x, z):
			var hang := _board.find_empty_hangar(team)
			if hang.x < 0:
				continue
			var ship_h := _board.spawn_ship(sid, star, team, "hangar", hang.x, hang.y)
			ship_h.field_side_team = team
			continue
		var ship := _board.spawn_ship(sid, star, team, "field", x, z)
		ship.field_side_team = side
		ship.global_position = BoardController.cell_to_world("field", side, x, z)
		_board.recalculate_fetters(team)
