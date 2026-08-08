extends RefCounted
class_name CynoController
## Covert cyno channeling: multi-cyno OK; capitals jump-in with red light near a random active cyno.

const ANNOUNCE_INTERVAL_S: float = 20.0
const JUMP_DURATION_S: float = 0.85

var _board: BoardController
var _match: MatchController
var _combat: CombatResolver
var _match_rng: MatchRng
var _battle_serial: int = 1
var _pending_respawn: Array[Dictionary] = []  # {team, ship_id, star, x, z, field_side_team}
## ship instance_id -> {end, next_announce}
var _active_channels: Dictionary = {}
## World-space FX nodes keyed by cyno ship instance_id.
var _channel_fx: Dictionary = {}


func bind(board: BoardController, match_ctrl: MatchController, combat: CombatResolver = null) -> void:
	_board = board
	_match = match_ctrl
	_combat = combat


func bind_match_rng(rng: MatchRng, serial: int = 1) -> void:
	_match_rng = rng
	_battle_serial = maxi(1, serial)


func _roll_index(n: int, event_kind: String) -> int:
	if n <= 0:
		return 0
	if _match_rng != null:
		return _match_rng.roll_int(_battle_serial, event_kind, 0, n - 1)
	return randi() % n


func clear_channels() -> void:
	for iid_key: Variant in _active_channels.keys():
		var iid: int = TypedVariant.as_int(iid_key, 0)
		_teardown_fx(iid)
	_active_channels.clear()
	_channel_fx.clear()


func has_active_channels() -> bool:
	return not _active_channels.is_empty()


## Combat ended (wipe / time limit): channels are cut, capitals stay in hangar.
## CAPITAL_AND_CYNO §2 — never force-complete a channel to hold the round open.
func abort_channels() -> void:
	var n: int = _active_channels.size()
	for iid_key: Variant in _active_channels.keys():
		var iid: int = TypedVariant.as_int(iid_key, 0)
		var ship: ShipUnit = instance_from_id(iid) as ShipUnit
		if ship != null and is_instance_valid(ship) and not ship.is_destroyed:
			_announce(ship, "诱导中断")
		_teardown_fx(iid)
	_active_channels.clear()
	_channel_fx.clear()
	if n > 0:
		SessionDiagnostics.log("cyno.abort", "n=%d" % n)


func on_battle_start(sim_time: float) -> void:
	clear_channels()
	var started: int = 0
	for s: ShipUnit in _board.all_ships():
		if s.slot_type != "field" or s.is_destroyed or s.is_unmanned:
			continue
		if not s.has_cyno_module():
			continue
		s.cyno_completed = false
		s.cyno_channel_ends_at = sim_time + s.cyno_duration_s()
		s.immobile_in_combat = true
		var iid: int = s.get_instance_id()
		_active_channels[iid] = {
			"end": s.cyno_channel_ends_at,
			"next_announce": sim_time + ANNOUNCE_INTERVAL_S,
		}
		_attach_fx(s)
		_announce(s, "诱导启动，读条 %.0fs" % s.cyno_duration_s())
		started += 1
	if started > 0:
		SessionDiagnostics.log("cyno.start", "n=%d" % started)


func tick(sim_time: float) -> void:
	var done: Array[int] = []
	for iid_key: Variant in _active_channels.keys():
		var iid: int = TypedVariant.as_int(iid_key, 0)
		var ship: ShipUnit = instance_from_id(iid) as ShipUnit
		if ship == null or not is_instance_valid(ship) or ship.is_destroyed:
			if ship != null and is_instance_valid(ship):
				_announce(ship, "诱导中断")
			_teardown_fx(iid)
			done.append(iid)
			continue
		var info: Dictionary = TypedVariant.as_dict(_active_channels[iid])
		var end_t: float = TypedVariant.as_float(info.get("end", 0.0), 0.0)
		var next_ann: float = TypedVariant.as_float(info.get("next_announce", 0.0), 0.0)
		if sim_time >= next_ann and sim_time < end_t:
			var left: float = maxf(0.0, end_t - sim_time)
			_announce(ship, "诱导读条中，剩余 %.0fs" % left)
			info["next_announce"] = sim_time + ANNOUNCE_INTERVAL_S
			_active_channels[iid] = info
		if sim_time < end_t:
			continue
		_complete_cyno(ship)
		done.append(iid)
	for iid_done: int in done:
		_active_channels.erase(iid_done)


func on_ship_destroyed(ship: ShipUnit) -> void:
	if ship == null:
		return
	var iid: int = ship.get_instance_id()
	if _active_channels.has(iid):
		_announce(ship, "诱导中断")
		_teardown_fx(iid)
		_active_channels.erase(iid)


func _complete_cyno(cyno: ShipUnit) -> void:
	if cyno == null or not is_instance_valid(cyno):
		return
	var team: int = cyno.team_id
	var cyno_x: int = cyno.grid_x
	var cyno_z: int = cyno.grid_z
	var cyno_side: int = cyno.field_side_team if cyno.field_side_team >= 0 else team
	var cyno_sid: int = cyno.ship_id
	var cyno_star: int = cyno.star
	cyno.cyno_completed = true
	_teardown_fx(cyno.get_instance_id())
	_announce(cyno, "诱导完成，旗舰跃迁入场")
	SessionDiagnostics.log("cyno.complete", "ship=%d team=%d" % [cyno.ship_id, cyno.team_id])
	if _board != null:
		var tree: SceneTree = _board.get_tree()
		if tree != null:
			tree.call_group("match_root", "notify_cyno_success", team)
	## Landing cells: completing cyno grid + other still-channeling cynos (same team).
	var anchor_cells: Array[Vector2i] = [Vector2i(cyno_x, cyno_z)]
	var anchor_sides: Array[int] = [cyno_side]
	for iid_key: Variant in _active_channels.keys():
		var iid: int = TypedVariant.as_int(iid_key, 0)
		var other: ShipUnit = instance_from_id(iid) as ShipUnit
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
	var capitals: Array[ShipUnit] = []
	for s: ShipUnit in _board.all_ships():
		if s.team_id != team or s.is_destroyed or s.is_unmanned:
			continue
		if s.slot_type != "hangar":
			continue
		if s.requires_cyno_entry:
			capitals.append(s)
	var warped: int = 0
	for pick: ShipUnit in capitals:
		if pick == null or not is_instance_valid(pick) or pick.is_destroyed:
			continue
		var ai: int = _roll_index(anchor_cells.size(), "cyno_anchor")
		var ac: Vector2i = anchor_cells[ai]
		var side: int = anchor_sides[ai]
		var cell: Vector2i = _pick_cell_near(team, side, ac.x, ac.y, 6)
		if cell.x < 0:
			break
		var land: Vector3 = BoardController.cell_to_world("field", side, cell.x, cell.y)
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
	var world: Node3D = _board.get_world_root() if _board else null
	if world == null or ship == null:
		ship.global_position = land
		ship.capital_jumping = false
		ship.set_combat_tint(true)
		if ship.has_method("rebuild_health_bar"):
			ship.rebuild_health_bar()
		if _combat and _combat.has_method("schedule_capital_hull_morph"):
			_combat.schedule_capital_hull_morph(ship)
		elif ship.has_method("begin_hull_morph_if_needed"):
			ship.begin_hull_morph_if_needed()
		return
	var fx: CapitalJumpFx = CapitalJumpFx.new()
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
	var sd: Dictionary = DataStore.get_ship(ship.ship_id)
	var who: String = str(sd.get("name", "诱导舰"))
	_match.notice.emit("%s：%s" % [who, msg])


func _attach_fx(ship: ShipUnit) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var iid: int = ship.get_instance_id()
	_teardown_fx(iid)
	var world: Node3D = _board.get_world_root() if _board else null
	if world == null:
		return
	var fx: CynoChannelFx = CynoChannelFx.new()
	fx.name = "CynoChannelFx_%d" % iid
	world.add_child(fx)
	fx.setup(ship)
	_channel_fx[iid] = fx


func _teardown_fx(ship_iid: int) -> void:
	if _channel_fx.has(ship_iid):
		var fx_v: Variant = _channel_fx[ship_iid]
		_channel_fx.erase(ship_iid)
		if fx_v is Node:
			var fx: Node = fx_v
			if is_instance_valid(fx):
				fx.queue_free()
		return
	## Legacy: FX parented under ship.
	var ship: ShipUnit = instance_from_id(ship_iid) as ShipUnit
	if ship == null or not is_instance_valid(ship):
		return
	var old: Node = ship.get_node_or_null("CynoChannelFx") as Node
	if old != null and is_instance_valid(old):
		old.queue_free()


func _pick_cell_near(owner_team: int, _side_team: int, cx: int, cz: int, radius: int) -> Vector2i:
	var fh: int = TypedVariant.as_int(DataStore.board.get("field_height", 6), 6)
	var candidates: Array[Vector2i] = []
	for z: int in range(fh):
		var cols: int = BoardController.field_cols_at(z)
		for x: int in range(cols):
			var d: int = absi(x - cx) + absi(z - cz)
			if d < 1 or d > radius:
				continue
			if _board.is_field_cell_free_for(owner_team, x, z):
				candidates.append(Vector2i(x, z))
	if candidates.is_empty():
		for z2: int in range(fh):
			var cols2: int = BoardController.field_cols_at(z2)
			for x2: int in range(cols2):
				if _board.is_field_cell_free_for(owner_team, x2, z2):
					candidates.append(Vector2i(x2, z2))
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[_roll_index(candidates.size(), "cyno_cell")]


func on_prepare_start() -> void:
	var pending: Array = _pending_respawn.duplicate(true)
	_pending_respawn.clear()
	clear_channels()
	for entry_v: Variant in pending:
		var entry: Dictionary = TypedVariant.as_dict(entry_v)
		var team: int = TypedVariant.as_int(entry.get("team", 0), 0)
		var sid: int = TypedVariant.as_int(entry.get("ship_id", 0), 0)
		var star: int = TypedVariant.as_int(entry.get("star", 1), 1)
		var x: int = TypedVariant.as_int(entry.get("x", 0), 0)
		var z: int = TypedVariant.as_int(entry.get("z", 0), 0)
		var side: int = TypedVariant.as_int(entry.get("field_side_team", team), team)
		if not _board.is_field_cell_free_for(team, x, z):
			var hang: Vector2i = _board.find_empty_hangar(team)
			if hang.x < 0:
				continue
			var ship_h: ShipUnit = _board.spawn_ship(sid, star, team, "hangar", hang.x, hang.y)
			ship_h.field_side_team = team
			continue
		var ship: ShipUnit = _board.spawn_ship(sid, star, team, "field", x, z)
		ship.field_side_team = side
		ship.global_position = BoardController.cell_to_world("field", side, x, z)
		_board.recalculate_fetters(team)
