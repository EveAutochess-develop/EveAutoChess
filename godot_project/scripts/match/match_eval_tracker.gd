extends RefCounted
class_name MatchEvalTracker
## MULTIPLAYER_PVP §7.1 extended combat titles for one human PVP round (same scope as CombatEvalTracker).

const BOWHEAD_SHIP_ID: int = 138

var local_seat: int = 0
var team_local: int = ShipUnit.TEAM_PLAYER

## Lance
var lance_fires: int = 0
var lance_dmg_friend: float = 0.0
var lance_dmg_enemy: float = 0.0
var lance_manned_kills: int = 0
var lance_frigate_kills: int = 0
var lance_fighter_kills: int = 0
var _lance_hit_enemy_iids: Dictionary = {} ## iid -> true
var _enemy_manned_at_first_lance: Dictionary = {} ## iid -> true (snapshot)
var _first_lance_snap_done: bool = false

## Field / losses
var fielded_mining: bool = false
var fielded_bowhead: bool = false
var bowhead_drone_lost: bool = false
var unmanned_lost: int = 0
var manned_lost: int = 0
var max_star3_ships: int = 0
var max_star3_frigates: int = 0
var fielded_star3_capital: bool = false
var _seen_star3_ship_iids: Dictionary = {}
var _seen_star3_frigate_iids: Dictionary = {}
var _bowhead_drone_iids: Dictionary = {}


func reset(seat: int) -> void:
	local_seat = seat
	lance_fires = 0
	lance_dmg_friend = 0.0
	lance_dmg_enemy = 0.0
	lance_manned_kills = 0
	lance_frigate_kills = 0
	lance_fighter_kills = 0
	_lance_hit_enemy_iids.clear()
	_enemy_manned_at_first_lance.clear()
	_first_lance_snap_done = false
	fielded_mining = false
	fielded_bowhead = false
	bowhead_drone_lost = false
	unmanned_lost = 0
	manned_lost = 0
	max_star3_ships = 0
	max_star3_frigates = 0
	fielded_star3_capital = false
	_seen_star3_ship_iids.clear()
	_seen_star3_frigate_iids.clear()
	_bowhead_drone_iids.clear()


func note_prepare_board(board: BoardController) -> void:
	if board == null:
		return
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		if s.team_id != team_local:
			continue
		if s.slot_type != "field":
			continue
		if s.is_mining_ship:
			fielded_mining = true
		if int(s.ship_id) == BOWHEAD_SHIP_ID:
			fielded_bowhead = true
		if s.is_unmanned and s.mother_ship_id != 0:
			var mom: ShipUnit = _find_ship_iid(board, s.mother_ship_id)
			if mom != null and int(mom.ship_id) == BOWHEAD_SHIP_ID:
				_bowhead_drone_iids[s.get_instance_id()] = true
		var star: int = maxi(1, TypedVariant.as_int(s.star, 1))
		if star < 3:
			continue
		var iid: int = s.get_instance_id()
		_seen_star3_ship_iids[iid] = true
		var ton: int = CombatEvalTracker._tonnage_rank(s)
		if ton <= 0:
			_seen_star3_frigate_iids[iid] = true
		if ton >= 5 or s.requires_cyno_entry:
			fielded_star3_capital = true
	max_star3_ships = maxi(max_star3_ships, _seen_star3_ship_iids.size())
	max_star3_frigates = maxi(max_star3_frigates, _seen_star3_frigate_iids.size())


func note_lance_fire_start(board: BoardController, src: ShipUnit) -> void:
	if src == null or src.team_id != team_local:
		return
	lance_fires += 1
	if _first_lance_snap_done or board == null:
		return
	_first_lance_snap_done = true
	for o: ShipUnit in board.all_ships():
		if o == null or not is_instance_valid(o) or o.is_destroyed:
			continue
		if o.slot_type != "field" or o.is_unmanned:
			continue
		if o.team_id == team_local:
			continue
		_enemy_manned_at_first_lance[o.get_instance_id()] = true


func note_lance_hit(src: ShipUnit, tgt: ShipUnit, dealt: float) -> void:
	if src == null or tgt == null or dealt <= 0.0:
		return
	if src.team_id != team_local:
		return
	if tgt.team_id == team_local:
		lance_dmg_friend += dealt
	else:
		lance_dmg_enemy += dealt
		_lance_hit_enemy_iids[tgt.get_instance_id()] = true


func note_ship_lost(ship: ShipUnit, killer: ShipUnit, via_lance: bool) -> void:
	if ship == null:
		return
	if ship.team_id == team_local:
		if ship.is_unmanned:
			unmanned_lost += 1
			if _bowhead_drone_iids.has(ship.get_instance_id()):
				bowhead_drone_lost = true
		else:
			manned_lost += 1
	if not via_lance or killer == null or killer.team_id != team_local:
		return
	if ship.team_id == team_local:
		return
	if not ship.is_unmanned:
		lance_manned_kills += 1
		if CombatEvalTracker._tonnage_rank(ship) <= 0:
			lance_frigate_kills += 1
	else:
		if str(ship.unmanned_kind) == "fighter":
			lance_fighter_kills += 1


func finalize_local(round_gold: int, round_won: bool) -> Array:
	var out: Array = []
	if lance_dmg_friend > lance_dmg_enemy * 2.0 and lance_dmg_friend > 0.0:
		out.append("无畏糕手")
	if lance_fires > 0 and lance_manned_kills >= 2:
		out.append("惊世长虹")
	if lance_frigate_kills >= 2 or lance_fighter_kills >= 10:
		out.append("灭蚊专家")
	if lance_fires > 0 and not _enemy_manned_at_first_lance.is_empty():
		var all_hit: bool = true
		for iid_v: Variant in _enemy_manned_at_first_lance.keys():
			if not _lance_hit_enemy_iids.has(iid_v):
				all_hit = false
				break
		if all_hit:
			out.append("无畏高手")
	if lance_fires >= 5:
		out.append("致命奢华")
	if round_gold >= 200:
		out.append("煤窑老板")
	elif round_gold >= 100:
		out.append("挖矿致富")
	elif round_gold >= 50:
		out.append("幻想时间")
	if fielded_bowhead and not bowhead_drone_lost:
		out.append("护犊狂魔")
	if not fielded_mining and round_gold >= 40:
		out.append("血色钱币")
	if unmanned_lost >= 10 and manned_lost == 0:
		out.append("小兵先行")
	if round_won and _seen_star3_ship_iids.size() >= 1:
		out.append("初窥晨星")
	if round_won and _seen_star3_ship_iids.size() >= 3:
		out.append("猎户腰带")
	if round_won and _seen_star3_ship_iids.size() >= 7:
		out.append("北斗入局")
	if _seen_star3_frigate_iids.size() >= 15:
		out.append("繁星满天")
	if round_won and fielded_star3_capital:
		out.append("极光定空")
	return out


func _find_ship_iid(board: BoardController, iid: int) -> ShipUnit:
	if board == null or iid == 0:
		return null
	for s: ShipUnit in board.all_ships():
		if s != null and is_instance_valid(s) and s.get_instance_id() == iid:
			return s
	return null
