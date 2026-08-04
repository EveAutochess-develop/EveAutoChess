extends Node
class_name NetBattleSession
## SEMI_ASYNC §3 — predict → host authority broadcast → repredict; host-only win/loss.

signal authority_snapshot(snap: Dictionary)
signal battle_report(report: Dictionary)
signal anticheat_notify(message: String)
signal round_jobs_complete(reports: Array)
signal spectate_stream(snap: Dictionary)

const LOGIC_HZ_DEFAULT: int = 30
const SYNC_INTERVAL_DEFAULT: int = 15

var match_rng: MatchRng
var host_sim: HostSimOrchestrator
var headless: EveacHeadless
var is_host: bool = false
var security_mode: String = "nullsec"
var local_seat: int = 0
var host_seat: int = 0
var logic_hz: int = LOGIC_HZ_DEFAULT
var sync_interval: int = SYNC_INTERVAL_DEFAULT
var _logic_tick: int = 0
var _accum: float = 0.0
var _gap_streak: int = 0
var _round_reports: Array = []
var _awaiting_titan: bool = false
var _net: NullsecNetSession
var _active_serial: int = 0
var _last_authority: Dictionary = {}
var _spot_logs: Array = []
var _income_logs: Array = []


func setup(rng: MatchRng, net: NullsecNetSession, payload: Dictionary) -> void:
	match_rng = rng
	_net = net
	is_host = net != null and net.is_host
	security_mode = str(payload.get("security_mode", "nullsec"))
	local_seat = TypedVariant.as_int(payload.get("local_seat", net.local_seat if net else 0), 0)
	host_seat = TypedVariant.as_int(payload.get("host_seat", 0), 0)
	logic_hz = NetConnectivity.logic_hz()
	sync_interval = NetConnectivity.sync_interval_ticks()
	host_sim = HostSimOrchestrator.new()
	host_sim.setup(rng)
	host_sim.battle_job_finished.connect(_on_job_finished)
	host_sim.round_finished.connect(_on_round_finished)
	headless = EveacHeadless.new()
	headless.bind_orchestrator(host_sim)
	if is_host:
		headless.ensure_running()
	_logic_tick = 0
	_round_reports.clear()
	_spot_logs.clear()
	_income_logs.clear()


## SEMI_ASYNC §5.3a — after host migration, elected peer must start headless.
func refresh_host_role() -> void:
	is_host = _net != null and _net.is_host
	if _net:
		host_seat = TypedVariant.as_int(_net.last_match_payload.get("host_seat", host_seat), host_seat)
		GameSession.pending_nullsec["host_seat"] = host_seat
	if is_host and headless:
		headless.ensure_running()


func on_local_battle_begin() -> void:
	## Enqueue authority jobs for this round (host). Guests only predict.
	if not is_host or host_sim == null:
		return
	_round_reports.clear()
	_awaiting_titan = true
	var seats: Array = TypedVariant.as_array(GameSession.pending_nullsec.get("seats", []))
	var contenders: Array = []
	for s_v: Variant in seats:
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = s_v
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		var race: String = str(s.get("titan_race", ""))
		if NullsecNetSession.is_spectate_race(race):
			continue
		if not NullsecNetSession.is_player_race(race):
			continue
		contenders.append(TypedVariant.as_int(s.get("seat_id", -1), -1))
	if NullsecNetSession.is_lowsec(security_mode):
		## Lowsec: single PVP job on host home between the two contenders.
		if contenders.size() >= 2:
			_active_serial = host_sim.enqueue_pvp(
				TypedVariant.as_int(contenders[0], 0),
				TypedVariant.as_int(contenders[1], 0),
				host_seat
			)
		return
	## Nullsec: enqueue PVE or PVP for every contender seat / pair.
	var round_r: int = TypedVariant.as_int(GameSession.pending_nullsec.get("round_r", 1), 1)
	var pvp: bool = NullsecPveDirector.is_pvp_round(round_r)
	if pvp:
		var used: Dictionary = {}
		for i: int in range(contenders.size()):
			var a: int = TypedVariant.as_int(contenders[i], -1)
			if used.has(a):
				continue
			var b: int = -1
			for j: int in range(i + 1, contenders.size()):
				var cand: int = TypedVariant.as_int(contenders[j], -1)
				if not used.has(cand):
					b = cand
					break
			if b < 0:
				host_sim.enqueue_pve(a, "pve_eliminate")
			else:
				used[a] = true
				used[b] = true
				var home: int = a if a == host_seat or b != host_seat else b
				host_sim.enqueue_pvp(a, b, home)
	else:
		for seat_v: Variant in contenders:
			var seat: int = TypedVariant.as_int(seat_v, -1)
			var task: String = "pve_salvage" if (round_r % 2 == 0) else "pve_eliminate"
			host_sim.enqueue_pve(seat, task)


func _process(delta: float) -> void:
	if match_rng == null:
		return
	var step: float = 1.0 / float(maxi(1, logic_hz))
	_accum += delta
	while _accum >= step:
		_accum -= step
		_logic_tick += 1
		if is_host and host_sim:
			host_sim.tick_authority(step)
			if _logic_tick % sync_interval == 0:
				_broadcast_authority()


func _broadcast_authority() -> void:
	var snap: Dictionary = build_authority_snapshot()
	_last_authority = snap
	authority_snapshot.emit(snap)
	spectate_stream.emit(snap)
	if _net and _net.is_host and _net.multiplayer and _net.multiplayer.has_multiplayer_peer():
		_net.broadcast_authority_snapshot(snap)


func build_authority_snapshot() -> Dictionary:
	var units: Array = []
	## Caller (match_root) may enrich; base carries tick + hash + logs.
	return {
		"logic_tick": _logic_tick,
		"active_serial": _active_serial,
		"state_hash": _hash_units(units),
		"units": units,
		"spot_logs": _spot_logs.duplicate(true),
		"income_logs": _income_logs.duplicate(true),
		"host_seat": host_seat,
		"is_authority": true,
	}


func enrich_and_broadcast(board: BoardController, income_total: int = 0) -> void:
	if not is_host:
		return
	var units: Array = []
	if board:
		for s_v: Variant in board.all_ships():
			if not (s_v is ShipUnit):
				continue
			var s: ShipUnit = s_v
			if s == null or not is_instance_valid(s) or s.is_unmanned:
				continue
			if str(s.slot_type) != "field":
				continue
			var hp: float = float(s.structure_hp) + float(s.armor_hp) + float(s.shield_hp)
			units.append({
				"id": s.get_instance_id(),
				"ship_id": int(s.ship_id),
				"team": int(s.team_id),
				"hp": hp,
				"structure": float(s.structure_hp),
				"armor": float(s.armor_hp),
				"shield": float(s.shield_hp),
				"max_hp": maxf(1.0, hp),
				"x": s.global_position.x,
				"z": s.global_position.z,
			})
	_income_logs.append({"seat": local_seat, "income_total": income_total, "tick": _logic_tick})
	while _income_logs.size() > 64:
		_income_logs.pop_front()
	var snap: Dictionary = {
		"logic_tick": _logic_tick,
		"active_serial": _active_serial,
		"state_hash": _hash_units(units),
		"units": units,
		"spot_logs": _spot_logs.duplicate(true),
		"income_logs": _income_logs.duplicate(true),
		"host_seat": host_seat,
		"is_authority": true,
	}
	_last_authority = snap
	authority_snapshot.emit(snap)
	spectate_stream.emit(snap)
	if _net and _net.multiplayer and _net.multiplayer.has_multiplayer_peer():
		_net.broadcast_authority_snapshot(snap)


func apply_authority(snap: Dictionary, board: BoardController = null) -> void:
	## Guest / spectate: apply host snapshot then continue predicting.
	if TypedVariant.as_bool(snap.get("is_authority", false), false) == false:
		return
	_last_authority = snap
	_logic_tick = TypedVariant.as_int(snap.get("logic_tick", _logic_tick), _logic_tick)
	authority_snapshot.emit(snap)
	spectate_stream.emit(snap)
	if board == null or is_host:
		return
	_repredict_from_authority(board, snap)


func _repredict_from_authority(board: BoardController, snap: Dictionary) -> void:
	var by_id: Dictionary = {}
	for u_v: Variant in TypedVariant.as_array(snap.get("units", [])):
		if typeof(u_v) == TYPE_DICTIONARY:
			var u: Dictionary = u_v
			by_id[TypedVariant.as_int(u.get("id", 0), 0)] = u
	if by_id.is_empty():
		return
	var gaps: int = 0
	for s_v: Variant in board.all_ships():
		if not (s_v is ShipUnit):
			continue
		var s: ShipUnit = s_v
		if s == null or not is_instance_valid(s):
			continue
		var u_v2: Variant = by_id.get(s.get_instance_id(), {})
		if typeof(u_v2) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = u_v2
		if u.is_empty():
			continue
		var auth_hp: float = TypedVariant.as_float(u.get("hp", 0.0), 0.0)
		var local_hp: float = float(s.structure_hp) + float(s.armor_hp) + float(s.shield_hp)
		var max_hp: float = maxf(1.0, TypedVariant.as_float(u.get("max_hp", 1.0), 1.0))
		if absf(auth_hp - local_hp) / max_hp > NetConnectivity.anticheat_gap_hp_rel():
			gaps += 1
		if u.has("structure"):
			s.structure_hp = TypedVariant.as_float(u.get("structure", s.structure_hp), s.structure_hp)
			s.armor_hp = TypedVariant.as_float(u.get("armor", s.armor_hp), s.armor_hp)
			s.shield_hp = TypedVariant.as_float(u.get("shield", s.shield_hp), s.shield_hp)
		s.global_position = Vector3(
			TypedVariant.as_float(u.get("x", s.global_position.x), s.global_position.x),
			s.global_position.y,
			TypedVariant.as_float(u.get("z", s.global_position.z), s.global_position.z)
		)
	if gaps > 0:
		_gap_streak += 1
		if _gap_streak >= NetConnectivity.anticheat_gap_streak():
			var msg: String = "联机对照：本地预测与房主权威多次偏差（仅通知，不踢号）"
			anticheat_notify.emit(msg)
			if _net and _net.multiplayer and _net.multiplayer.has_multiplayer_peer():
				_net.broadcast_anticheat_notice(msg)
			_gap_streak = 0
	else:
		_gap_streak = maxi(0, _gap_streak - 1)


func record_spot_hit(source_id: int, target_id: int, dealt: float) -> void:
	if not is_host:
		return
	_spot_logs.append({
		"tick": _logic_tick,
		"src": source_id,
		"tgt": target_id,
		"dealt": dealt,
	})
	while _spot_logs.size() > 64:
		_spot_logs.pop_front()


func host_result_for_serial(serial: int) -> Dictionary:
	for r_v: Variant in _round_reports:
		if not (r_v is Dictionary):
			continue
		var r: Dictionary = r_v
		if TypedVariant.as_int(r.get("serial", -1), -1) == serial:
			return r
	return {}


func all_jobs_done() -> bool:
	return host_sim != null and host_sim.pending_count() == 0 and not _round_reports.is_empty()


func take_round_reports() -> Array:
	var out: Array = _round_reports.duplicate(true)
	_round_reports.clear()
	_awaiting_titan = false
	return out


func _on_job_finished(_serial: int, report: Dictionary) -> void:
	_round_reports.append(report)
	battle_report.emit(report)
	if _net and is_host and _net.multiplayer and _net.multiplayer.has_multiplayer_peer():
		_net.broadcast_battle_report(report)
	if host_sim and host_sim.pending_count() == 0:
		var flushed: Array = host_sim.flush_round()
		round_jobs_complete.emit(flushed if not flushed.is_empty() else _round_reports)


func _on_round_finished(reports: Array) -> void:
	round_jobs_complete.emit(reports)


static func _hash_units(units: Array) -> String:
	var acc: String = ""
	for u_v: Variant in units:
		if typeof(u_v) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = u_v
		acc += "%d:%.1f:%.1f:%.1f;" % [
			TypedVariant.as_int(u.get("ship_id", 0), 0),
			TypedVariant.as_float(u.get("hp", 0), 0.0),
			TypedVariant.as_float(u.get("x", 0), 0.0),
			TypedVariant.as_float(u.get("z", 0), 0.0),
		]
	return "%08x" % hash(acc)
