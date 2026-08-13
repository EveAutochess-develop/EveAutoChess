extends RefCounted
class_name CombatEvalTracker
## MULTIPLAYER_PVP §7.1 真人桌战评 — one instance covers one PVP round
## (ShipUnit.TEAM_PLAYER vs TEAM_AI). No「绵羊附体」. 羊望未来命名说明仅在设计专文.

const STREAK_TITLES: Dictionary = {
	5: "五连之勇",
	10: "十连惊世",
	14: "豆蔻倾国",
	30: "三十而立",
	40: "四十不惑",
	50: "五十知命",
	60: "随心所欲",
}

var _open_value: Dictionary = {}
var _open_hp: Dictionary = {}
var _open_manned_count: int = 0
var _open_unit_count: int = 0
var _open_manned_by_team: Dictionary = {}
var _open_max_tonnage: Dictionary = {}
var _open_capital_count: Dictionary = {}
var _open_enemy_all_mining: Dictionary = {} ## team_id of victim -> bool (rival was all mining)
var _open_shield_max: Dictionary = {} ## iid -> float
var _dmg_by_unit: Dictionary = {}
var _dmg_total_by_team: Dictionary = {}
var _dmg_taken_by_key: Dictionary = {}
var _dmg_taken_by_unit: Dictionary = {} ## iid -> float
var _heal_total: float = 0.0
var _heal_by_unit: Dictionary = {} ## iid -> float
var _cap_war_by_unit: Dictionary = {} ## iid -> float (NOS back + neut + remote_cap)
var _lost_value: Dictionary = {}
var _cyno_success_count: Dictionary = {} ## team -> count
var _open_cyno_count: Dictionary = {} ## team -> cyno hulls on field at round open
var _cyno_kills_before_enemy_cyno: Dictionary = {} ## killer team -> count
var _enemy_cyno_done: Dictionary = {} ## team that saw rival cyno
var _early_cyno_kill: Dictionary = {} ## killer team -> bool (within 10s)
var _capital_kill_by_noncap: Dictionary = {} ## killer team -> bool
var _peak_drones: int = 0
var _peak_fighters: int = 0
var _peak_unmanned: int = 0
var _battle_start_wall_ms: int = 0
var _brink_armed: bool = false
var _brink_ok: bool = false
var _brink_winner_team: int = -1
var _implants_fitted: Dictionary = {} ## team -> Dictionary id->true
var _focus_full_ms: Dictionary = {} ## iid -> wall ms when first hit 20 stacks
var _focus_full_held: Dictionary = {} ## iid -> bool held >=120s
var _bombing_targets: Dictionary = {} ## team -> {iid targets set / shared}
var _bombing_ships: Dictionary = {} ## team -> Array iids
var _sniper_triggers: Dictionary = {} ## iid -> count
var _sniper_kills: Dictionary = {} ## iid -> count
var _warhead_strip_count: Dictionary = {} ## team -> int
var _thermal_dmg_offense: Dictionary = {} ## iid -> float (taken on offense rounds)
var _thermal_dmg_defense: Dictionary = {} ## iid -> float
var _barrage_dmg: Dictionary = {} ## team -> float
var _he_coil_high_resist_kill: Dictionary = {} ## team -> bool
var _auto_def_frigate_kill: Dictionary = {} ## team -> bool
var _category_counts: Dictionary = {} ## team -> {cat -> int}
var _has_shield_sup_logi: Dictionary = {} ## team -> bool
var _has_armor_sup_logi: Dictionary = {} ## team -> bool
var _layout_fingerprint: String = ""

## Injected by MatchRoot before finalize (match-scoped meta).
var meta_scout_vs_rival: int = 0
var meta_sold_first_purchase: bool = false
var meta_bought_capital_prepare: bool = false
var meta_streak_by_seat: Dictionary = {} ## seat -> int after this round's outcome applied
var meta_losses_by_seat: Dictionary = {} ## seat -> losses in match
var meta_rejoined_by_seat: Dictionary = {}
var meta_wins_since_rejoin: Dictionary = {}
var meta_divine_hand_by_seat: Dictionary = {} ## seat -> bool
var meta_match_ending: bool = false


func begin_round(board: BoardController) -> void:
	_reset_round()
	_battle_start_wall_ms = Time.get_ticks_msec()
	if board == null:
		return
	_layout_fingerprint = _compute_layout_fingerprint(board, ShipUnit.TEAM_PLAYER)
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		## Field manned OR hangar capitals awaiting cyno (rank seeds).
		var seed_ok: bool = s.slot_type == "field" or (s.slot_type == "hangar" and s.requires_cyno_entry)
		if not seed_ok:
			continue
		if s.is_protect_target:
			continue
		_open_unit_count += 1
		if s.is_unmanned:
			continue
		_open_manned_count += 1
		var tid: int = s.team_id
		_open_manned_by_team[tid] = TypedVariant.as_int(_open_manned_by_team.get(tid, 0), 0) + 1
		_open_value[tid] = TypedVariant.as_int(_open_value.get(tid, 0), 0) + _ship_value(s)
		_open_hp[tid] = TypedVariant.as_float(_open_hp.get(tid, 0.0), 0.0) + _ship_total_hp(s)
		var rank: int = _tonnage_rank(s)
		_open_max_tonnage[tid] = maxi(TypedVariant.as_int(_open_max_tonnage.get(tid, 0), 0), rank)
		if rank >= 5 or s.requires_cyno_entry:
			_open_capital_count[tid] = TypedVariant.as_int(_open_capital_count.get(tid, 0), 0) + 1
		if _is_cyno_hull(s):
			_open_cyno_count[tid] = TypedVariant.as_int(_open_cyno_count.get(tid, 0), 0) + 1
		_open_shield_max[s.get_instance_id()] = maxf(0.0, float(s.shield_hp))
		_scan_fit(s)
		if s.requires_cyno_entry:
			SessionDiagnostics.log(
				"rank.seed",
				"ship=%d slot=%s team=%d iid=%d" % [s.ship_id, s.slot_type, s.team_id, s.get_instance_id()]
			)
	## 买瓜子去: for each team, rival manned all mining / no logi / no offense
	for tid: int in [ShipUnit.TEAM_PLAYER, ShipUnit.TEAM_AI]:
		var rival: int = ShipUnit.TEAM_AI if tid == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
		_open_enemy_all_mining[tid] = _team_all_mining_no_offense(board, rival)


func tick(board: BoardController) -> void:
	if board == null:
		return
	var drones: int = 0
	var fighters: int = 0
	var unmanned: int = 0
	var manned_alive: Array = []
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		if s.is_unmanned:
			unmanned += 1
			var uk: String = str(s.unmanned_kind)
			if uk == "fighter":
				fighters += 1
			else:
				drones += 1
		elif s.slot_type == "field" and not s.is_protect_target:
			manned_alive.append(s)
		_poll_implant_state(s)
	_peak_drones = maxi(_peak_drones, drones)
	_peak_fighters = maxi(_peak_fighters, fighters)
	_peak_unmanned = maxi(_peak_unmanned, unmanned)
	if manned_alive.size() == 2 and not _brink_armed:
		_brink_armed = true
		var a: ShipUnit = manned_alive[0]
		var b: ShipUnit = manned_alive[1]
		if a.team_id != b.team_id:
			var dph_a: float = _panel_dph(a)
			var dph_b: float = _panel_dph(b)
			var hp_a: float = _ship_total_hp(a)
			var hp_b: float = _ship_total_hp(b)
			_brink_ok = dph_a >= hp_b and dph_b >= hp_a


func on_hit(source_id: int, target_id: int, source_team: int, dealt: float) -> void:
	if dealt <= 0.0:
		return
	## Unmanned damage / taken rolls up to mothership (UI_AND_SHELL §2.6).
	var src_credit: int = _credit_unit_iid(source_id)
	var tgt_credit: int = _credit_unit_iid(target_id)
	_dmg_by_unit[src_credit] = TypedVariant.as_float(_dmg_by_unit.get(src_credit, 0.0), 0.0) + dealt
	_dmg_total_by_team[source_team] = TypedVariant.as_float(_dmg_total_by_team.get(source_team, 0.0), 0.0) + dealt
	var key: String = "%d->%d" % [source_team, tgt_credit]
	_dmg_taken_by_key[key] = TypedVariant.as_float(_dmg_taken_by_key.get(key, 0.0), 0.0) + dealt
	_dmg_taken_by_unit[tgt_credit] = TypedVariant.as_float(_dmg_taken_by_unit.get(tgt_credit, 0.0), 0.0) + dealt
	@warning_ignore("unsafe_cast")
	var src: ShipUnit = instance_from_id(source_id) as ShipUnit
	@warning_ignore("unsafe_cast")
	var tgt: ShipUnit = instance_from_id(target_id) as ShipUnit
	if src != null and is_instance_valid(src):
		if _ship_has_implant(src, "implant_barrage"):
			_barrage_dmg[source_team] = TypedVariant.as_float(_barrage_dmg.get(source_team, 0.0), 0.0) + dealt
		if _ship_has_implant(src, "implant_bombing"):
			_note_bombing_hit(source_team, src_credit, tgt_credit)
		if _ship_has_implant(src, "implant_warhead") and tgt != null and is_instance_valid(tgt):
			if float(tgt.shield_hp) <= 0.01 and float(tgt.armor_hp) <= 0.01 and float(tgt.structure_hp) > 0.01:
				_warhead_strip_count[source_team] = TypedVariant.as_int(_warhead_strip_count.get(source_team, 0), 0) + 1
		if _ship_has_implant(src, "implant_sniper"):
			var sn: Dictionary = TypedVariant.as_dict(src._implant_state.get("sniper", {}))
			if TypedVariant.as_bool(sn.get("force_hit", false), false) or FunctionFit.attack_force_hit(src):
				_sniper_triggers[src_credit] = TypedVariant.as_int(_sniper_triggers.get(src_credit, 0), 0) + 1
	if tgt != null and is_instance_valid(tgt) and _ship_has_implant(tgt, "implant_thermal_cycle"):
		var tc: Dictionary = TypedVariant.as_dict(tgt._implant_state.get("thermal", {"round": 0}))
		var rnd: int = TypedVariant.as_int(tc.get("round", 0), 0)
		## Odd rounds = offense (dmg mul); even = defense.
		if rnd % 2 == 1:
			_thermal_dmg_offense[tgt_credit] = TypedVariant.as_float(_thermal_dmg_offense.get(tgt_credit, 0.0), 0.0) + dealt
		else:
			_thermal_dmg_defense[tgt_credit] = TypedVariant.as_float(_thermal_dmg_defense.get(tgt_credit, 0.0), 0.0) + dealt


func on_heal(amount: float, healer_id: int = 0) -> void:
	if amount > 0.0:
		_heal_total += amount
		if healer_id != 0:
			var hid: int = _credit_unit_iid(healer_id)
			_heal_by_unit[hid] = TypedVariant.as_float(_heal_by_unit.get(hid, 0.0), 0.0) + amount


func on_cap_war(source_id: int, amount: float) -> void:
	if source_id == 0 or amount <= 0.0:
		return
	var sid: int = _credit_unit_iid(source_id)
	_cap_war_by_unit[sid] = TypedVariant.as_float(_cap_war_by_unit.get(sid, 0.0), 0.0) + amount


## Ranking board rows: Array of {iid, name, taken, dealt, heal, cap} sorted by key descending.
func ranking_rows(sort_key: String = "dealt", board: BoardController = null) -> Array:
	var ids: Dictionary = {}
	for k: Variant in _dmg_by_unit.keys():
		ids[TypedVariant.as_int(k, 0)] = true
	for k: Variant in _dmg_taken_by_unit.keys():
		ids[TypedVariant.as_int(k, 0)] = true
	for k: Variant in _heal_by_unit.keys():
		ids[TypedVariant.as_int(k, 0)] = true
	for k: Variant in _cap_war_by_unit.keys():
		ids[TypedVariant.as_int(k, 0)] = true
	## Seed both teams' manned field ships so enemies appear even at 0 stats.
	## Hangar capitals awaiting cyno also seed the rank board (plan G / §7.1).
	if board != null:
		for s: ShipUnit in board.all_ships():
			if s == null or not is_instance_valid(s):
				continue
			if s.is_unmanned or s.is_protect_target:
				continue
			var seed_ok: bool = s.slot_type == "field" or (s.slot_type == "hangar" and s.requires_cyno_entry)
			if not seed_ok or s.is_destroyed:
				continue
			ids[s.get_instance_id()] = true
	var rows: Array = []
	for iid_v: Variant in ids.keys():
		var iid: int = TypedVariant.as_int(iid_v, 0)
		if iid == 0:
			continue
		@warning_ignore("unsafe_cast")
		var ship: ShipUnit = instance_from_id(iid) as ShipUnit
		## Skip leftover unmanned rows; stats should already be on mother.
		if ship != null and is_instance_valid(ship) and ship.is_unmanned:
			continue
		var nm: String = "?"
		var ship_group: String = ""
		var overlay_key: String = "enemy"
		var team_id: int = -1
		if ship != null and is_instance_valid(ship):
			var data: Dictionary = DataStore.get_ship(ship.ship_id) if DataStore else {}
			nm = str(data.get("name", "舰%d" % ship.ship_id))
			ship_group = str(data.get("ship_group", ""))
			team_id = ship.team_id
			if ship.is_protect_target or ship_group == "freighter":
				overlay_key = "friendly"
			elif team_id == ShipUnit.TEAM_PLAYER:
				overlay_key = "fleet"
			else:
				overlay_key = "enemy"
		var row: Dictionary = {
			"iid": iid,
			"name": nm,
			"ship_group": ship_group,
			"overlay_key": overlay_key,
			"team_id": team_id,
			"taken": TypedVariant.as_float(_dmg_taken_by_unit.get(iid, 0.0), 0.0),
			"dealt": TypedVariant.as_float(_dmg_by_unit.get(iid, 0.0), 0.0),
			"heal": TypedVariant.as_float(_heal_by_unit.get(iid, 0.0), 0.0),
			"cap": TypedVariant.as_float(_cap_war_by_unit.get(iid, 0.0), 0.0),
		}
		rows.append(row)
	var sk: String = sort_key if sort_key in ["taken", "dealt", "heal", "cap", "name"] else "dealt"
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if sk == "name":
			return str(a.get("name", "")) < str(b.get("name", ""))
		return TypedVariant.as_float(a.get(sk, 0.0), 0.0) > TypedVariant.as_float(b.get(sk, 0.0), 0.0)
	)
	return rows


## Map unmanned unit iid → mothership iid when mother is still valid.
static func _credit_unit_iid(unit_id: int) -> int:
	if unit_id == 0:
		return 0
	@warning_ignore("unsafe_cast")
	var s: ShipUnit = instance_from_id(unit_id) as ShipUnit
	if s == null or not is_instance_valid(s):
		return unit_id
	if not s.is_unmanned or s.mother_ship_id == 0:
		return unit_id
	@warning_ignore("unsafe_cast")
	var m: ShipUnit = instance_from_id(s.mother_ship_id) as ShipUnit
	if m != null and is_instance_valid(m):
		return m.get_instance_id()
	return unit_id


func on_ship_lost(ship: ShipUnit, killer: ShipUnit = null) -> void:
	if ship == null or not is_instance_valid(ship) or ship.is_protect_target:
		return
	if not ship.is_unmanned:
		_lost_value[ship.team_id] = TypedVariant.as_int(_lost_value.get(ship.team_id, 0), 0) + _ship_value(ship)
	if killer == null or not is_instance_valid(killer):
		return
	var kteam: int = killer.team_id
	if _is_cyno_hull(ship):
		if not TypedVariant.as_bool(_enemy_cyno_done.get(kteam, false), false):
			_cyno_kills_before_enemy_cyno[kteam] = TypedVariant.as_int(_cyno_kills_before_enemy_cyno.get(kteam, 0), 0) + 1
		var elapsed: int = Time.get_ticks_msec() - _battle_start_wall_ms
		if elapsed <= 10000:
			_early_cyno_kill[kteam] = true
	if _tonnage_rank(ship) >= 5 and _tonnage_rank(killer) < 5 and not killer.is_unmanned:
		_capital_kill_by_noncap[kteam] = true
	if _ship_has_implant(killer, "implant_sniper"):
		var kid: int = killer.get_instance_id()
		_sniper_kills[kid] = TypedVariant.as_int(_sniper_kills.get(kid, 0), 0) + 1
	if _ship_has_implant(killer, "implant_he_coil") and _target_has_high_resist(ship):
		_he_coil_high_resist_kill[kteam] = true
	if _ship_has_implant(killer, "implant_auto_def") or _mother_has_implant(killer, "implant_auto_def"):
		if _tonnage_rank(ship) <= 1:
			_auto_def_frigate_kill[kteam] = true
	if _brink_armed and _brink_ok and not ship.is_unmanned:
		_brink_winner_team = kteam
	_note_bombing_kill(kteam, ship.get_instance_id())


func on_cyno_success(team_id: int) -> void:
	_cyno_success_count[team_id] = TypedVariant.as_int(_cyno_success_count.get(team_id, 0), 0) + 1
	var rival: int = ShipUnit.TEAM_AI if team_id == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
	_enemy_cyno_done[rival] = true


func finalize(result: String, team_a_seat: int, team_b_seat: int, board: BoardController) -> Array:
	if board:
		for s: ShipUnit in board.all_ships():
			if s != null and is_instance_valid(s) and s.cyno_completed:
				on_cyno_success(s.team_id)
			if s != null and is_instance_valid(s) and not s.is_destroyed:
				_scan_fit(s)
				_poll_implant_state(s)
	var titles: Array = []
	var team_a: int = ShipUnit.TEAM_PLAYER
	var team_b: int = ShipUnit.TEAM_AI
	var a_won: bool = result == "win"
	var b_won: bool = result == "lose"
	var a_lost: bool = result == "lose"
	var b_lost: bool = result == "win"
	var is_draw: bool = result.begins_with("draw")
	var open_val_a: int = TypedVariant.as_int(_open_value.get(team_a, 0), 0)
	var open_val_b: int = TypedVariant.as_int(_open_value.get(team_b, 0), 0)
	_eval_won_side(titles, team_a_seat, team_a, a_won, open_val_a, open_val_b, board)
	_eval_won_side(titles, team_b_seat, team_b, b_won, open_val_b, open_val_a, board)
	_eval_lost_side(titles, team_a_seat, team_a, a_lost)
	_eval_lost_side(titles, team_b_seat, team_b, b_lost)
	_eval_either_side(titles, team_a_seat, team_a, board)
	_eval_either_side(titles, team_b_seat, team_b, board)
	## implant-only titles live in _eval_either_side
	if _open_unit_count > 10:
		_eval_efficient_firepower(titles, team_a_seat, team_a)
		_eval_efficient_firepower(titles, team_b_seat, team_b)
	if _open_unit_count >= 10:
		_eval_layout_mastery(titles, team_a_seat, team_b)
		_eval_layout_mastery(titles, team_b_seat, team_a)
	if is_draw:
		var total_open_hp: float = TypedVariant.as_float(_open_hp.get(team_a, 0.0), 0.0) + TypedVariant.as_float(_open_hp.get(team_b, 0.0), 0.0)
		if total_open_hp > 0.0 and _heal_total >= total_open_hp * 0.5:
			if team_a_seat >= 0:
				titles.append({"seat_id": team_a_seat, "title": "无解至极"})
			if team_b_seat >= 0:
				titles.append({"seat_id": team_b_seat, "title": "无解至极"})
	if _brink_ok and _brink_winner_team == team_a and a_won and team_a_seat >= 0:
		titles.append({"seat_id": team_a_seat, "title": "千钧一发"})
	elif _brink_ok and _brink_winner_team == team_b and b_won and team_b_seat >= 0:
		titles.append({"seat_id": team_b_seat, "title": "千钧一发"})
	_eval_streaks(titles, team_a_seat, a_won)
	_eval_streaks(titles, team_b_seat, b_won)
	return titles


func get_layout_fingerprint() -> String:
	return _layout_fingerprint


func _reset_round() -> void:
	_open_value.clear()
	_open_hp.clear()
	_open_manned_by_team.clear()
	_open_max_tonnage.clear()
	_open_capital_count.clear()
	_open_enemy_all_mining.clear()
	_open_shield_max.clear()
	_dmg_by_unit.clear()
	_dmg_total_by_team.clear()
	_dmg_taken_by_key.clear()
	_dmg_taken_by_unit.clear()
	_heal_total = 0.0
	_heal_by_unit.clear()
	_cap_war_by_unit.clear()
	_lost_value.clear()
	_cyno_success_count.clear()
	_open_cyno_count.clear()
	_cyno_kills_before_enemy_cyno.clear()
	_enemy_cyno_done.clear()
	_early_cyno_kill.clear()
	_capital_kill_by_noncap.clear()
	_peak_drones = 0
	_peak_fighters = 0
	_peak_unmanned = 0
	_open_manned_count = 0
	_open_unit_count = 0
	_brink_armed = false
	_brink_ok = false
	_brink_winner_team = -1
	_implants_fitted.clear()
	_focus_full_ms.clear()
	_focus_full_held.clear()
	_bombing_targets.clear()
	_bombing_ships.clear()
	_sniper_triggers.clear()
	_sniper_kills.clear()
	_warhead_strip_count.clear()
	_thermal_dmg_offense.clear()
	_thermal_dmg_defense.clear()
	_barrage_dmg.clear()
	_he_coil_high_resist_kill.clear()
	_auto_def_frigate_kill.clear()
	_category_counts.clear()
	_has_shield_sup_logi.clear()
	_has_armor_sup_logi.clear()
	_layout_fingerprint = ""


func _eval_won_side(titles: Array, seat_id: int, team_id: int, won: bool, open_val_self: int, open_val_rival: int, _board: BoardController) -> void:
	if seat_id < 0 or not won:
		return
	if _open_manned_count > 10 and TypedVariant.as_int(_lost_value.get(team_id, 0), 0) <= 0:
		titles.append({"seat_id": seat_id, "title": "完美胜利"})
	if open_val_rival > 0 and open_val_self < open_val_rival * 0.6:
		titles.append({"seat_id": seat_id, "title": "节约标兵"})
	if open_val_rival > 0 and open_val_self >= open_val_rival * 3:
		titles.append({"seat_id": seat_id, "title": "经济碾压"})
	var lost: int = TypedVariant.as_int(_lost_value.get(team_id, 0), 0)
	if open_val_self > 0 and lost >= open_val_self * 0.8:
		titles.append({"seat_id": seat_id, "title": "力挽狂澜"})
	if TypedVariant.as_int(_cyno_success_count.get(team_id, 0), 0) > 0:
		titles.append({"seat_id": seat_id, "title": "全程强势"})
	var self_n: int = TypedVariant.as_int(_open_manned_by_team.get(team_id, 0), 0)
	var rival_team: int = ShipUnit.TEAM_AI if team_id == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
	var rival_n: int = TypedVariant.as_int(_open_manned_by_team.get(rival_team, 0), 0)
	var self_max: int = TypedVariant.as_int(_open_max_tonnage.get(team_id, 0), 0)
	var rival_max: int = TypedVariant.as_int(_open_max_tonnage.get(rival_team, 0), 0)
	if rival_n > 0 and self_n <= int(rival_n / 3) and self_max <= rival_max:
		titles.append({"seat_id": seat_id, "title": "优势在我"})
	if TypedVariant.as_bool(_open_enemy_all_mining.get(team_id, false), false):
		titles.append({"seat_id": seat_id, "title": "买瓜子去"})
	if meta_scout_vs_rival >= 1 and team_id == ShipUnit.TEAM_PLAYER:
		titles.append({"seat_id": seat_id, "title": "有备而来"})
	if meta_sold_first_purchase and meta_bought_capital_prepare and team_id == ShipUnit.TEAM_PLAYER:
		titles.append({"seat_id": seat_id, "title": "羊望未来"})
	if TypedVariant.as_int(_open_capital_count.get(rival_team, 0), 0) >= 3 \
			and TypedVariant.as_bool(_capital_kill_by_noncap.get(team_id, false), false):
		titles.append({"seat_id": seat_id, "title": "以弱胜强"})
	var cats: Dictionary = TypedVariant.as_dict(_category_counts.get(team_id, {}))
	var ewar_n: int = TypedVariant.as_int(cats.get("ewar", 0), 0) + TypedVariant.as_int(cats.get("cap_warfare", 0), 0)
	if ewar_n > 16:
		titles.append({"seat_id": seat_id, "title": "高级战术"})
	if TypedVariant.as_bool(meta_divine_hand_by_seat.get(seat_id, false), false):
		titles.append({"seat_id": seat_id, "title": "神之一手"})
	if TypedVariant.as_bool(meta_rejoined_by_seat.get(seat_id, false), false) \
			and TypedVariant.as_int(meta_wins_since_rejoin.get(seat_id, 0), 0) == 1:
		titles.append({"seat_id": seat_id, "title": "王者归来"})
	if meta_match_ending and TypedVariant.as_int(meta_losses_by_seat.get(seat_id, 0), 0) == 0:
		titles.append({"seat_id": seat_id, "title": "超级导演"})


func _eval_lost_side(titles: Array, seat_id: int, team_id: int, lost: bool) -> void:
	if seat_id < 0 or not lost:
		return
	## MULTIPLAYER_PVP §7.1 — 等待戈多 requires a cyno hull was fielded.
	if TypedVariant.as_int(_open_cyno_count.get(team_id, 0), 0) <= 0:
		return
	if TypedVariant.as_int(_cyno_success_count.get(team_id, 0), 0) <= 0:
		titles.append({"seat_id": seat_id, "title": "等待戈多"})


func _eval_either_side(titles: Array, seat_id: int, team_id: int, board: BoardController) -> void:
	if seat_id < 0:
		return
	if TypedVariant.as_int(_cyno_kills_before_enemy_cyno.get(team_id, 0), 0) >= 2:
		titles.append({"seat_id": seat_id, "title": "强势镇压"})
	if TypedVariant.as_bool(_early_cyno_kill.get(team_id, false), false):
		titles.append({"seat_id": seat_id, "title": "打出头鸟"})
	if _peak_drones >= 50 or _peak_fighters >= 100:
		titles.append({"seat_id": seat_id, "title": "机械海洋"})
	if _peak_unmanned >= 200:
		titles.append({"seat_id": seat_id, "title": "卡服能手"})
	if _team_has_crane(board, team_id):
		titles.append({"seat_id": seat_id, "title": "鹤立鸡群"})
	if _has_all_implants(team_id):
		titles.append({"seat_id": seat_id, "title": "十二符咒"})
	var cats: Dictionary = TypedVariant.as_dict(_category_counts.get(team_id, {}))
	if TypedVariant.as_int(cats.get("repair", 0), 0) > 16:
		titles.append({"seat_id": seat_id, "title": "自强不息"})
	if TypedVariant.as_int(cats.get("weapon", 0), 0) > 10:
		titles.append({"seat_id": seat_id, "title": "火力优先"})
	_eval_implant_either(titles, seat_id, team_id, board)


## Reserved for win-gated implant titles (currently evaluated in _eval_implant_either).
func _eval_implant_wins(_titles: Array, _seat_id: int, _team_id: int, _board: BoardController) -> void:
	return


func _eval_implant_either(titles: Array, seat_id: int, team_id: int, board: BoardController) -> void:
	if board == null:
		return
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.team_id != team_id or s.is_unmanned:
			continue
		var iid: int = s.get_instance_id()
		if TypedVariant.as_bool(_focus_full_held.get(iid, false), false):
			titles.append({"seat_id": seat_id, "title": "拳拳到肉"})
			break
	for s2: ShipUnit in board.all_ships():
		if s2 == null or not is_instance_valid(s2) or s2.team_id != team_id:
			continue
		if not _ship_has_implant(s2, "implant_pulse_crystal"):
			continue
		var boosters: int = _count_fit_prefix(s2, "shield_booster_")
		if boosters < 2:
			continue
		var taken: float = TypedVariant.as_float(_dmg_taken_by_unit.get(s2.get_instance_id(), 0.0), 0.0)
		var sh_max: float = TypedVariant.as_float(_open_shield_max.get(s2.get_instance_id(), 0.0), 0.0)
		if sh_max > 0.0 and taken > sh_max * 3.0:
			titles.append({"seat_id": seat_id, "title": "不死不灭"})
			break
	if _bombing_precise(team_id):
		titles.append({"seat_id": seat_id, "title": "精准爆破"})
	if TypedVariant.as_bool(_has_shield_sup_logi.get(team_id, false), false) and _end_low_struct_high_shield(board):
		titles.append({"seat_id": seat_id, "title": "妙手回春"})
	if TypedVariant.as_bool(_has_armor_sup_logi.get(team_id, false), false) and _end_low_struct_high_armor(board):
		titles.append({"seat_id": seat_id, "title": "治根治本"})
	for kid_v: Variant in _sniper_triggers.keys():
		var kid: int = TypedVariant.as_int(kid_v, 0)
		@warning_ignore("unsafe_cast")
		var ks: ShipUnit = instance_from_id(kid) as ShipUnit
		if ks == null or not is_instance_valid(ks) or ks.team_id != team_id:
			continue
		var trig: int = TypedVariant.as_int(_sniper_triggers[kid], 0)
		var kills: int = TypedVariant.as_int(_sniper_kills.get(kid, 0), 0)
		if trig >= 5 and kills >= 5 and trig == kills:
			titles.append({"seat_id": seat_id, "title": "弹无虚发"})
			break
	for s3: ShipUnit in board.all_ships():
		if s3 == null or not is_instance_valid(s3) or s3.team_id != team_id:
			continue
		if not _ship_has_implant(s3, "implant_thermal_cycle"):
			continue
		var iid3: int = s3.get_instance_id()
		var off: float = TypedVariant.as_float(_thermal_dmg_offense.get(iid3, 0.0), 0.0)
		var deff: float = TypedVariant.as_float(_thermal_dmg_defense.get(iid3, 0.0), 0.0)
		if off <= 0.01 and deff > 0.0:
			titles.append({"seat_id": seat_id, "title": "攻防交错"})
			break
	var team_dmg: float = TypedVariant.as_float(_dmg_total_by_team.get(team_id, 0.0), 0.0)
	var bar: float = TypedVariant.as_float(_barrage_dmg.get(team_id, 0.0), 0.0)
	if team_dmg > 0.0 and bar >= team_dmg * 0.4:
		titles.append({"seat_id": seat_id, "title": "火力倾泻"})
	if TypedVariant.as_bool(_he_coil_high_resist_kill.get(team_id, false), false):
		titles.append({"seat_id": seat_id, "title": "破甲攻城"})
	if TypedVariant.as_int(_warhead_strip_count.get(team_id, 0), 0) >= 3:
		titles.append({"seat_id": seat_id, "title": "专攻术业"})
	if TypedVariant.as_bool(_auto_def_frigate_kill.get(team_id, false), false):
		titles.append({"seat_id": seat_id, "title": "致命沉默"})


func _eval_streaks(titles: Array, seat_id: int, won: bool) -> void:
	if seat_id < 0 or not won:
		return
	var streak: int = TypedVariant.as_int(meta_streak_by_seat.get(seat_id, 0), 0)
	if STREAK_TITLES.has(streak):
		titles.append({"seat_id": seat_id, "title": str(STREAK_TITLES[streak])})


func _eval_efficient_firepower(titles: Array, seat_id: int, team_id: int) -> void:
	if seat_id < 0:
		return
	var grand_total: float = 0.0
	for t_v: Variant in _dmg_total_by_team.values():
		grand_total += TypedVariant.as_float(t_v, 0.0)
	if grand_total <= 0.0:
		return
	var best: float = 0.0
	for iid_key: Variant in _dmg_by_unit.keys():
		@warning_ignore("unsafe_cast")
		var ship: ShipUnit = instance_from_id(TypedVariant.as_int(iid_key, 0)) as ShipUnit
		if ship == null or not is_instance_valid(ship) or ship.team_id != team_id:
			continue
		best = maxf(best, TypedVariant.as_float(_dmg_by_unit[iid_key], 0.0))
	if best >= grand_total * 0.4:
		titles.append({"seat_id": seat_id, "title": "高效火力"})


func _eval_layout_mastery(titles: Array, victim_seat: int, attacker_team: int) -> void:
	if victim_seat < 0:
		return
	var total: float = TypedVariant.as_float(_dmg_total_by_team.get(attacker_team, 0.0), 0.0)
	if total <= 0.0:
		return
	var best: float = 0.0
	var prefix: String = "%d->" % attacker_team
	for key_v: Variant in _dmg_taken_by_key.keys():
		var key: String = str(key_v)
		if not key.begins_with(prefix):
			continue
		best = maxf(best, TypedVariant.as_float(_dmg_taken_by_key[key], 0.0))
	if best >= total * 0.8:
		titles.append({"seat_id": victim_seat, "title": "布局之道"})


static func _ship_value(s: ShipUnit) -> int:
	var cost: int = TypedVariant.as_int(DataStore.get_ship(s.ship_id).get("cost", 1), 1)
	var star_mul: int = 1
	match maxi(1, int(s.star)):
		1:
			star_mul = 1
		2:
			star_mul = 3
		_:
			star_mul = 9
	return maxi(1, cost * star_mul)


static func _ship_total_hp(s: ShipUnit) -> float:
	return maxf(0.0, float(s.shield_hp)) + maxf(0.0, float(s.armor_hp)) + maxf(0.0, float(s.structure_hp))


static func _panel_dph(s: ShipUnit) -> float:
	var cycle: float = maxf(0.05, float(s.attack_duration))
	var raw: float = float(s.damage_emp) + float(s.damage_thermal) + float(s.damage_kinetic) + float(s.damage_explosive)
	return raw / cycle


static func _tonnage_rank(s: ShipUnit) -> int:
	if s.requires_cyno_entry:
		return 5
	var g: String = str(DataStore.get_ship(s.ship_id).get("ship_group", "")).to_lower()
	match g:
		"frigate":
			return 0
		"destroyer":
			return 1
		"cruiser":
			return 2
		"battlecruiser":
			return 3
		"battleship":
			return 4
		"dreadnought", "carrier", "force_auxiliary", "supercarrier", "titan", "freighter", "capital", "capital_industrial", "industrial_command":
			return 5
		_:
			var role: String = str(DataStore.get_ship(s.ship_id).get("capital_role", ""))
			return 5 if role != "" else 0


static func _is_cyno_hull(s: ShipUnit) -> bool:
	return FunctionFit.is_cyno_hull(DataStore.get_ship(s.ship_id))


func _ship_has_implant(s: ShipUnit, implant_id: String) -> bool:
	for entry: Variant in s.get_function_fit():
		var e: Dictionary = TypedVariant.as_dict(entry)
		if str(e.get("id", "")) == implant_id:
			return true
	return false


func _mother_has_implant(s: ShipUnit, implant_id: String) -> bool:
	if s.mother_ship_id != 0:
		@warning_ignore("unsafe_cast")
		var m: ShipUnit = instance_from_id(s.mother_ship_id) as ShipUnit
		if m != null and is_instance_valid(m):
			return _ship_has_implant(m, implant_id)
	return false


func _count_fit_prefix(s: ShipUnit, prefix: String) -> int:
	var n: int = 0
	for entry: Variant in s.get_function_fit():
		var e: Dictionary = TypedVariant.as_dict(entry)
		if str(e.get("id", "")).begins_with(prefix):
			n += 1
	return n


func _scan_fit(s: ShipUnit) -> void:
	var tid: int = s.team_id
	if not _implants_fitted.has(tid):
		_implants_fitted[tid] = {}
	if not _category_counts.has(tid):
		_category_counts[tid] = {}
	for entry: Variant in s.get_function_fit():
		var e: Dictionary = TypedVariant.as_dict(entry)
		var fid: String = str(e.get("id", "")).strip_edges()
		var def: Dictionary = TypedVariant.as_dict(e.get("def", DataStore.get_function_module(fid)))
		if TypedVariant.as_bool(def.get("implant", false), false):
			_implants_fitted[tid][fid] = true
			if fid == "implant_shield_support" and (s.is_logistic or str(s.resolve_weapon_fx_kind()) == "heal"):
				_has_shield_sup_logi[tid] = true
			if fid == "implant_armor_support" and (s.is_logistic or str(s.resolve_weapon_fx_kind()) == "heal"):
				_has_armor_sup_logi[tid] = true
			if fid == "implant_bombing":
				if not _bombing_ships.has(tid):
					_bombing_ships[tid] = []
				var arr: Array = _bombing_ships[tid]
				var iid: int = s.get_instance_id()
				if not arr.has(iid):
					arr.append(iid)
		var cat: String = str(def.get("shop_category", ""))
		if cat != "":
			var cats: Dictionary = _category_counts[tid]
			cats[cat] = TypedVariant.as_int(cats.get(cat, 0), 0) + 1


func _poll_implant_state(s: ShipUnit) -> void:
	if not _ship_has_implant(s, "implant_focus_crystal"):
		return
	var st: Dictionary = TypedVariant.as_dict(s._implant_state.get("focus", {"stacks": 0}))
	var stacks: int = TypedVariant.as_int(st.get("stacks", 0), 0)
	var iid: int = s.get_instance_id()
	if stacks >= 20:
		if not _focus_full_ms.has(iid):
			_focus_full_ms[iid] = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - TypedVariant.as_int(_focus_full_ms[iid], 0) >= 120000:
			_focus_full_held[iid] = true
	else:
		_focus_full_ms.erase(iid)


func _has_all_implants(team_id: int) -> bool:
	var have: Dictionary = TypedVariant.as_dict(_implants_fitted.get(team_id, {}))
	var need: int = 0
	var got: int = 0
	for k: Variant in DataStore.function_modules.keys():
		var d: Dictionary = DataStore.function_modules[k]
		if not TypedVariant.as_bool(d.get("implant", false), false):
			continue
		need += 1
		if TypedVariant.as_bool(have.get(str(k), false), false):
			got += 1
	return need > 0 and got >= need


func _team_all_mining_no_offense(board: BoardController, team_id: int) -> bool:
	var any: bool = false
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.team_id != team_id or s.is_unmanned:
			continue
		if s.slot_type != "field":
			continue
		any = true
		if not s.is_mining_ship:
			return false
		if s.is_logistic or str(s.resolve_weapon_fx_kind()) == "heal":
			return false
		if s.has_offensive_damage():
			return false
	return any


func _team_has_crane(board: BoardController, team_id: int) -> bool:
	if board == null:
		return false
	var ranks: Array = []
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.team_id != team_id or s.is_unmanned:
			continue
		if s.slot_type != "field":
			continue
		ranks.append(_tonnage_rank(s))
	if ranks.size() < 2:
		return false
	for i: int in range(ranks.size()):
		var ok: bool = true
		for j: int in range(ranks.size()):
			if i == j:
				continue
			if TypedVariant.as_int(ranks[i], 0) < TypedVariant.as_int(ranks[j], 0) + 3:
				ok = false
				break
		if ok:
			return true
	return false


func _note_bombing_hit(team: int, _source_id: int, target_id: int) -> void:
	if not _bombing_targets.has(team):
		_bombing_targets[team] = {"targets": {}, "kill_before_boost_end": false}
	var st: Dictionary = _bombing_targets[team]
	var targets: Dictionary = TypedVariant.as_dict(st.get("targets", {}))
	targets[target_id] = true
	st["targets"] = targets
	_bombing_targets[team] = st


func _note_bombing_kill(team: int, target_id: int) -> void:
	if not _bombing_targets.has(team):
		return
	var st: Dictionary = _bombing_targets[team]
	var targets: Dictionary = TypedVariant.as_dict(st.get("targets", {}))
	if targets.has(target_id) and targets.size() == 1:
		st["kill_before_boost_end"] = true
		_bombing_targets[team] = st


func _bombing_precise(team_id: int) -> bool:
	var ships: Array = TypedVariant.as_array(_bombing_ships.get(team_id, []))
	if ships.size() < 3:
		return false
	var st: Dictionary = TypedVariant.as_dict(_bombing_targets.get(team_id, {}))
	var targets: Dictionary = TypedVariant.as_dict(st.get("targets", {}))
	if targets.size() != 1:
		return false
	if not TypedVariant.as_bool(st.get("kill_before_boost_end", false), false):
		return false
	## Target tonnage ≥ each bomber +1 — best-effort using live/instance lookup.
	var tid: int = TypedVariant.as_int(targets.keys()[0], 0)
	@warning_ignore("unsafe_cast")
	var tgt: ShipUnit = instance_from_id(tid) as ShipUnit
	var tgt_rank: int = _tonnage_rank(tgt) if tgt != null and is_instance_valid(tgt) else 99
	for sid_v: Variant in ships:
		@warning_ignore("unsafe_cast")
		var bomber: ShipUnit = instance_from_id(TypedVariant.as_int(sid_v, 0)) as ShipUnit
		if bomber == null or not is_instance_valid(bomber):
			continue
		if tgt_rank < _tonnage_rank(bomber) + 1:
			return false
	return true


func _end_low_struct_high_shield(board: BoardController) -> bool:
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_destroyed or s.is_unmanned:
			continue
		var total: float = _ship_total_hp(s)
		if total <= 0.0:
			continue
		var sp: float = float(s.structure_hp) / total
		var sh: float = float(s.shield_hp) / total
		if sp <= 0.10 and sh >= 0.10 and _count_fit_prefix(s, "shield_booster_") == 0:
			return true
	return false


func _end_low_struct_high_armor(board: BoardController) -> bool:
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_destroyed or s.is_unmanned:
			continue
		var total: float = _ship_total_hp(s)
		if total <= 0.0:
			continue
		var sp: float = float(s.structure_hp) / total
		var ar: float = float(s.armor_hp) / total
		if sp <= 0.10 and ar >= 0.10 and _count_fit_prefix(s, "armor_repairer_") == 0:
			return true
	return false


func _target_has_high_resist(s: ShipUnit) -> bool:
	var sd: Dictionary = DataStore.get_ship(s.ship_id)
	for layer2: String in ["shield_resist", "armor_resist"]:
		var r: Dictionary = TypedVariant.as_dict(sd.get(layer2, {}))
		for k2: Variant in r.keys():
			if TypedVariant.as_float(r[k2], 0.0) >= 0.9:
				return true
	return false


static func _compute_layout_fingerprint(board: BoardController, team_id: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.team_id != team_id or s.is_unmanned:
			continue
		if s.slot_type != "field" and s.slot_type != "hangar":
			continue
		parts.append("%d:%s:%d:%d" % [s.ship_id, s.slot_type, s.grid_x, s.grid_z])
	parts.sort()
	return ",".join(parts)


static func layout_is_plus_one(prev: String, cur: String) -> bool:
	if prev == "" or cur == "" or prev == cur:
		return false
	var a: PackedStringArray = prev.split(",")
	var b: PackedStringArray = cur.split(",")
	if b.size() != a.size() + 1:
		return false
	var aset: Dictionary = {}
	for p: String in a:
		aset[p] = true
	var extra: int = 0
	for p2: String in b:
		if not aset.has(p2):
			extra += 1
		else:
			aset.erase(p2)
	return extra == 1 and aset.is_empty()
