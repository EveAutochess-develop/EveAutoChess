extends RefCounted
class_name CombatLearnStats
## End-of-round compact hull snapshot for in-match slow learn (handbook §0.2).
## Memory only — never writes files per tick.

var _open: Dictionary = {} ## instance_id -> {ship_id, team, cost, hp}


func reset() -> void:
	_open.clear()


func begin_battle(board: BoardController) -> void:
	_open.clear()
	if board == null:
		return
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s):
			continue
		if s.is_unmanned or s.is_protect_target:
			continue
		if s.slot_type != "field":
			continue
		_open[s.get_instance_id()] = {
			"ship_id": s.ship_id,
			"team": s.team_id,
			"cost": _cost_of(s.ship_id),
			"hp": _hp_sum(s),
		}


func snapshot_end(board: BoardController, kills_player: int, kills_ai: int) -> Array:
	var by_id: Dictionary = {}
	if board != null:
		for s: ShipUnit in board.all_ships():
			if s == null or not is_instance_valid(s):
				continue
			if s.is_unmanned or s.is_protect_target:
				continue
			if s.slot_type != "field" and not _open.has(s.get_instance_id()):
				continue
			var iid: int = s.get_instance_id()
			var opened: Dictionary = TypedVariant.as_dict(_open.get(iid, {}))
			var ship_id: int = s.ship_id
			var team: int = s.team_id
			var cost: int = _cost_of(ship_id)
			var hp0: float = TypedVariant.as_float(opened.get("hp", _hp_sum(s)), _hp_sum(s))
			var survived: bool = not s.is_destroyed and s.structure_hp > 0.01
			var hp1: float = _hp_sum(s) if survived else 0.0
			by_id[iid] = {
				"ship_id": ship_id,
				"team": team,
				"cost": cost,
				"survived": survived,
				"hp_delta": hp1 - hp0,
				"kills": 0,
			}
	for iid_v: Variant in _open.keys():
		var iid: int = TypedVariant.as_int(iid_v, 0)
		if by_id.has(iid):
			continue
		var opened2: Dictionary = TypedVariant.as_dict(_open[iid_v])
		by_id[iid] = {
			"ship_id": TypedVariant.as_int(opened2.get("ship_id", 0), 0),
			"team": TypedVariant.as_int(opened2.get("team", 0), 0),
			"cost": TypedVariant.as_int(opened2.get("cost", 0), 0),
			"survived": false,
			"hp_delta": -TypedVariant.as_float(opened2.get("hp", 0.0), 0.0),
			"kills": 0,
		}
	var out: Array = []
	var first_p: bool = true
	var first_a: bool = true
	for row_v: Variant in by_id.values():
		var row: Dictionary = TypedVariant.as_dict(row_v)
		var team: int = TypedVariant.as_int(row.get("team", 0), 0)
		if team == ShipUnit.TEAM_PLAYER and first_p:
			row["kills"] = maxi(0, kills_player)
			first_p = false
		elif team == ShipUnit.TEAM_AI and first_a:
			row["kills"] = maxi(0, kills_ai)
			first_a = false
		out.append(row)
	return out


static func _hp_sum(s: ShipUnit) -> float:
	return s.shield_hp + s.armor_hp + s.structure_hp


static func _cost_of(ship_id: int) -> int:
	if DataStore == null:
		return 0
	return maxi(0, TypedVariant.as_int(DataStore.get_ship(ship_id).get("cost", 0), 0))
