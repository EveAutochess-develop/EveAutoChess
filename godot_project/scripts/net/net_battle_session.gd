extends Node
class_name NetBattleSession
## SEMI_ASYNC §3 — predict → host authority broadcast → repredict; host-only win/loss.

signal authority_snapshot(snap: Dictionary)
signal battle_report(report: Dictionary)
@warning_ignore("unused_signal")
signal anticheat_notify(message: String)
signal round_jobs_complete(reports: Array)
signal spectate_stream(snap: Dictionary)

const LOGIC_HZ_DEFAULT: int = 30
const SYNC_INTERVAL_DEFAULT: int = 6
const FULL_SYNC_INTERVAL_DEFAULT: int = 60
const LIGHT_SYNC_INTERVAL_DEFAULT: int = 6
const PENDING_EVENTS_CAP: int = 96
const LIGHT_EVENTS_CAP: int = 48

var match_rng: MatchRng
var host_sim: HostSimOrchestrator
var headless: EveacHeadless
var is_host: bool = false
var security_mode: String = "nullsec"
var local_seat: int = 0
var host_seat: int = 0
var logic_hz: int = LOGIC_HZ_DEFAULT
var sync_interval: int = SYNC_INTERVAL_DEFAULT
var full_sync_interval: int = FULL_SYNC_INTERVAL_DEFAULT
var light_sync_interval: int = LIGHT_SYNC_INTERVAL_DEFAULT
## Deprecated: lowsec no longer silences authority enrich (SEMI_ASYNC §3.0b 2026-08-06).
var silent_battle: bool = false
var _wall_anchor_msec: int = 0
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
var _pending_events: Array = []
## Owner seat for half-field mirror on guests (SEMI_ASYNC §3.2a).
var owner_seat: int = 0
## SEMI_ASYNC §3.1a — guest only paints authority; skip gap bookkeeping.
var watch_only_apply: bool = false
var _applying_authority: bool = false


func setup(rng: MatchRng, net: NullsecNetSession, payload: Dictionary) -> void:
	match_rng = rng
	_net = net
	is_host = net != null and net.is_host
	security_mode = str(payload.get("security_mode", "nullsec"))
	local_seat = TypedVariant.as_int(payload.get("local_seat", net.local_seat if net else 0), 0)
	host_seat = TypedVariant.as_int(payload.get("host_seat", 0), 0)
	owner_seat = host_seat
	logic_hz = NetConnectivity.logic_hz()
	full_sync_interval = maxi(1, NetConnectivity.full_sync_interval_ticks())
	light_sync_interval = maxi(1, NetConnectivity.light_sync_interval_ticks())
	sync_interval = light_sync_interval
	## Lowsec and nullsec share the same periodic authority enrich path.
	silent_battle = false
	_wall_anchor_msec = Time.get_ticks_msec()
	host_sim = HostSimOrchestrator.new()
	host_sim.setup(rng)
	NetSessionDebug.log_event(
		"net.battle.setup",
		"mode=%s silent=%s host=%s full=%d light=%d" % [
			security_mode, silent_battle, is_host, full_sync_interval, light_sync_interval
		]
	)
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
	_pending_events.clear()


## SEMI_ASYNC §5.3a — after host migration, elected peer must start headless.
func refresh_host_role() -> void:
	is_host = _net != null and _net.is_host
	if _net:
		host_seat = TypedVariant.as_int(_net.last_match_payload.get("host_seat", host_seat), host_seat)
		GameSession.pending_nullsec["host_seat"] = host_seat
	if is_host and headless:
		headless.ensure_running()


func on_local_battle_begin() -> void:
	## Enqueue authority jobs for this round (host). Guests watch snaps only (§3.1a).
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
			## Periodic tick marker only; unit enrich is driven by match_root at sync_interval.
			if _logic_tick % sync_interval == 0:
				pass
			var wall: int = Time.get_ticks_msec() - _wall_anchor_msec
			if wall > 30000 and (_logic_tick % (logic_hz * 5) == 0):
				NetSessionDebug.log_event("net.drift.check", "wall_ms=%d tick=%d" % [wall, _logic_tick])
				if _net and _net.is_host:
					_net.broadcast_ships_hash()


func should_enrich_this_tick() -> bool:
	## Full authority snapshot (~2s).
	return is_host and _logic_tick > 0 and (_logic_tick % maxi(1, full_sync_interval) == 0)


func should_light_this_tick() -> bool:
	## Light pos/lock/events (~0.2s); skip when full fires on the same tick.
	if not is_host or _logic_tick <= 0:
		return false
	if _logic_tick % maxi(1, full_sync_interval) == 0:
		return false
	return _logic_tick % maxi(1, light_sync_interval) == 0


func logic_tick() -> int:
	return _logic_tick


## Mirror host-frame world pos into local seat frame (SEMI_ASYNC §3.2a).
static func mirror_world_pos(pos: Vector3, from_owner_seat: int, to_local_seat: int) -> Vector3:
	if from_owner_seat == to_local_seat:
		return pos
	var po: Vector3 = BoardController.field_origin(ShipUnit.TEAM_PLAYER)
	var ao: Vector3 = BoardController.field_origin(ShipUnit.TEAM_AI)
	## Default board: player +Z, AI −Z — flip Z around midplane between origins.
	var mid_z: float = (po.z + ao.z) * 0.5
	var mid_x: float = (po.x + ao.x) * 0.5
	return Vector3(mid_x * 2.0 - pos.x, pos.y, mid_z * 2.0 - pos.z)


static func mirror_team(team: int) -> int:
	if team == ShipUnit.TEAM_PLAYER:
		return ShipUnit.TEAM_AI
	if team == ShipUnit.TEAM_AI:
		return ShipUnit.TEAM_PLAYER
	return team


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
			if s == null or not is_instance_valid(s):
				continue
			if str(s.slot_type) != "field":
				continue
			var hp: float = float(s.structure_hp) + float(s.armor_hp) + float(s.shield_hp)
			var uid: String = _ensure_net_uid(s)
			units.append({
				"net_uid": uid,
				"id": s.get_instance_id(), ## legacy fallback
				"ship_id": int(s.ship_id),
				"team": int(s.team_id),
				"side": int(s.field_side_team if s.field_side_team >= 0 else s.team_id),
				"grid_x": int(s.grid_x),
				"grid_z": int(s.grid_z),
				"hp": hp,
				"structure": float(s.structure_hp),
				"armor": float(s.armor_hp),
				"shield": float(s.shield_hp),
				"max_hp": maxf(1.0, hp),
				"x": s.global_position.x,
				"y": s.global_position.y,
				"z": s.global_position.z,
				"unmanned": s.is_unmanned,
				"is_destroyed": s.is_destroyed,
				"cyno_completed": s.is_destroyed and FunctionFit.is_cyno_hull(DataStore.get_ship(s.ship_id)),
				"lock_target_id": int(s.lock_target_id),
				"lock_uid": _lock_uid_of(s),
				"pre_lock_target_id": int(s.pre_lock_target_id),
				"pre_lock_timer": float(s.pre_lock_timer),
				"pre_lock_duration_s": float(s.pre_lock_duration_s),
			})
	_income_logs.append({"seat": local_seat, "income_total": income_total, "tick": _logic_tick})
	while _income_logs.size() > 64:
		_income_logs.pop_front()
	var drained: Array = _drain_pending_events(LIGHT_EVENTS_CAP * 2)
	var snap: Dictionary = {
		"kind": "full",
		"logic_tick": _logic_tick,
		"active_serial": _active_serial,
		"state_hash": _hash_units(units),
		"units": units,
		"events": drained,
		"spot_logs": _spot_logs.duplicate(true),
		"income_logs": _income_logs.duplicate(true),
		"host_seat": host_seat,
		"owner_seat": owner_seat if owner_seat >= 0 else host_seat,
		"is_authority": true,
	}
	_last_authority = snap
	authority_snapshot.emit(snap)
	spectate_stream.emit(snap)
	if _net and _net.multiplayer and _net.multiplayer.has_multiplayer_peer():
		_net.broadcast_authority_snapshot(snap)


## SEMI_ASYNC §3.3B — ~0.2s light: x/z, lock_uid, fire/repair events.
func enrich_and_broadcast_light(board: BoardController) -> void:
	if not is_host:
		return
	var units: Array = []
	if board:
		for s_v: Variant in board.all_ships():
			if not (s_v is ShipUnit):
				continue
			var s: ShipUnit = s_v
			if s == null or not is_instance_valid(s):
				continue
			if str(s.slot_type) != "field":
				continue
			if s.is_destroyed:
				continue
			units.append({
				"net_uid": _ensure_net_uid(s),
				"x": snappedf(s.global_position.x, 0.001),
				"z": snappedf(s.global_position.z, 0.001),
				"lock_uid": _lock_uid_of(s),
			})
	var pkt: Dictionary = {
		"kind": "light",
		"logic_tick": _logic_tick,
		"host_seat": host_seat,
		"owner_seat": owner_seat if owner_seat >= 0 else host_seat,
		"units": units,
		"events": _drain_pending_events(LIGHT_EVENTS_CAP),
		"is_authority": true,
	}
	if _net and _net.multiplayer and _net.multiplayer.has_multiplayer_peer():
		_net.broadcast_authority_light(pkt)


func record_combat_event(
	kind: String,
	src: ShipUnit,
	tgt: ShipUnit,
	amount: float,
	fx_kind: String = ""
) -> void:
	if not is_host:
		return
	if amount <= 0.0 or src == null or tgt == null:
		return
	if not is_instance_valid(src) or not is_instance_valid(tgt):
		return
	var k: String = str(kind)
	if k != "damage" and k != "repair":
		return
	var fx: String = str(fx_kind)
	if fx == "" and k == "damage" and src.has_method("resolve_weapon_fx_kind"):
		fx = str(src.resolve_weapon_fx_kind())
	_pending_events.append({
		"kind": k,
		"src_uid": _ensure_net_uid(src),
		"tgt_uid": _ensure_net_uid(tgt),
		"amount": snappedf(amount, 0.1),
		"fx": fx,
		"tick": _logic_tick,
	})
	while _pending_events.size() > PENDING_EVENTS_CAP:
		_pending_events.pop_front()
	record_spot_hit(src.get_instance_id(), tgt.get_instance_id(), amount)


func _drain_pending_events(cap: int) -> Array:
	if _pending_events.is_empty():
		return []
	var n: int = mini(_pending_events.size(), maxi(1, cap))
	var out: Array = _pending_events.slice(0, n)
	_pending_events = _pending_events.slice(n, _pending_events.size())
	return out


func _ensure_net_uid(s: ShipUnit) -> String:
	var uid: String = str(s.net_uid)
	if uid == "":
		uid = "%d|%d|%d|%d|%d" % [local_seat, int(s.ship_id), int(s.team_id), int(s.grid_x), int(s.grid_z)]
		s.net_uid = uid
	return uid


func _lock_uid_of(s: ShipUnit) -> String:
	var lid: int = int(s.lock_target_id)
	if lid == 0:
		return ""
	@warning_ignore("unsafe_cast")
	var t: ShipUnit = instance_from_id(lid) as ShipUnit
	if t == null or not is_instance_valid(t):
		return ""
	return _ensure_net_uid(t)


func _repredict_from_authority(board: BoardController, snap: Dictionary) -> void:
	var by_uid: Dictionary = {}
	var by_fallback: Dictionary = {}
	for u_v: Variant in TypedVariant.as_array(snap.get("units", [])):
		if typeof(u_v) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = u_v
		var uid: String = str(u.get("net_uid", ""))
		if uid != "":
			by_uid[uid] = u
		var fb: String = "%d|%d|%d|%d" % [
			TypedVariant.as_int(u.get("ship_id", 0), 0),
			TypedVariant.as_int(u.get("team", 0), 0),
			TypedVariant.as_int(u.get("grid_x", 0), 0),
			TypedVariant.as_int(u.get("grid_z", 0), 0),
		]
		by_fallback[fb] = u
		## Legacy instance-id key (will miss across peers).
		by_fallback["iid:%d" % TypedVariant.as_int(u.get("id", 0), 0)] = u
	if by_uid.is_empty() and by_fallback.is_empty():
		return
	var auth_owner: int = TypedVariant.as_int(snap.get("owner_seat", snap.get("host_seat", host_seat)), host_seat)
	var gaps: int = 0
	var ships_by_uid: Dictionary = _index_ships_by_uid(board)
	for s_v: Variant in board.all_ships():
		if not (s_v is ShipUnit):
			continue
		var s: ShipUnit = s_v
		if s == null or not is_instance_valid(s):
			continue
		var u_v2: Variant = null
		if str(s.net_uid) != "" and by_uid.has(s.net_uid):
			u_v2 = by_uid[s.net_uid]
		else:
			## Guest ships: host team is mirrored — try both team keys.
			var fb1: String = "%d|%d|%d|%d" % [int(s.ship_id), int(s.team_id), int(s.grid_x), int(s.grid_z)]
			var fb2: String = "%d|%d|%d|%d" % [int(s.ship_id), mirror_team(int(s.team_id)), int(s.grid_x), int(s.grid_z)]
			if by_fallback.has(fb1):
				u_v2 = by_fallback[fb1]
			elif by_fallback.has(fb2):
				u_v2 = by_fallback[fb2]
			elif by_fallback.has("iid:%d" % s.get_instance_id()):
				u_v2 = by_fallback["iid:%d" % s.get_instance_id()]
		if typeof(u_v2) != TYPE_DICTIONARY:
			continue
		var u2: Dictionary = u_v2
		if u2.is_empty():
			continue
		if str(s.net_uid) == "" and str(u2.get("net_uid", "")) != "":
			s.net_uid = str(u2.get("net_uid", ""))
		## Watch-only peers are not predicting — skip anticheat HP gap bookkeeping.
		if not watch_only_apply:
			var auth_hp: float = TypedVariant.as_float(u2.get("hp", 0.0), 0.0)
			var local_hp: float = float(s.structure_hp) + float(s.armor_hp) + float(s.shield_hp)
			var max_hp: float = maxf(1.0, TypedVariant.as_float(u2.get("max_hp", 1.0), 1.0))
			if absf(auth_hp - local_hp) / max_hp > NetConnectivity.anticheat_gap_hp_rel():
				gaps += 1
		if u2.has("structure"):
			s.structure_hp = TypedVariant.as_float(u2.get("structure", s.structure_hp), s.structure_hp)
			s.armor_hp = TypedVariant.as_float(u2.get("armor", s.armor_hp), s.armor_hp)
			s.shield_hp = TypedVariant.as_float(u2.get("shield", s.shield_hp), s.shield_hp)
		var wx: float = TypedVariant.as_float(u2.get("x", s.global_position.x), s.global_position.x)
		var wy: float = TypedVariant.as_float(u2.get("y", s.global_position.y), s.global_position.y)
		var wz: float = TypedVariant.as_float(u2.get("z", s.global_position.z), s.global_position.z)
		var mirrored: Vector3 = mirror_world_pos(Vector3(wx, wy, wz), auth_owner, local_seat)
		## Skip tiny writes — reduces Transform dirty / UI redraw hitch on guests.
		if s.global_position.distance_squared_to(mirrored) > 0.0001:
			s.global_position = mirrored
		if TypedVariant.as_bool(u2.get("is_destroyed", false), false) and not s.is_destroyed:
			s.is_destroyed = true
			s.visible = false
		if u2.has("lock_uid"):
			_apply_lock_uid(s, str(u2.get("lock_uid", "")), ships_by_uid)
		elif u2.has("lock_target_id"):
			s.lock_target_id = TypedVariant.as_int(u2.get("lock_target_id", s.lock_target_id), s.lock_target_id)
		if u2.has("pre_lock_target_id"):
			s.pre_lock_target_id = TypedVariant.as_int(u2.get("pre_lock_target_id", s.pre_lock_target_id), s.pre_lock_target_id)
			s.pre_lock_timer = TypedVariant.as_float(u2.get("pre_lock_timer", s.pre_lock_timer), s.pre_lock_timer)
			s.pre_lock_duration_s = TypedVariant.as_float(u2.get("pre_lock_duration_s", s.pre_lock_duration_s), s.pre_lock_duration_s)
	if gaps > 0:
		_gap_streak += 1
		## SEMI_ASYNC §6.2 — HP streak is log-only; UI notify is W/L prediction only.
		if _gap_streak >= NetConnectivity.anticheat_gap_streak():
			NetSessionDebug.log_event(
				"net.anticheat_gap",
				"hp_streak=%d gaps=%d (log only)" % [_gap_streak, gaps]
			)
			_gap_streak = 0
	else:
		_gap_streak = maxi(0, _gap_streak - 1)


## SEMI_ASYNC §3.3B — guest apply light packet (pos / lock / fire·repair).
func apply_light(
	pkt: Dictionary,
	board: BoardController,
	firing_fx: Object = null,
	float_text: Object = null
) -> void:
	if is_host or board == null:
		return
	if TypedVariant.as_bool(pkt.get("is_authority", false), false) == false:
		return
	_logic_tick = TypedVariant.as_int(pkt.get("logic_tick", _logic_tick), _logic_tick)
	var auth_owner: int = TypedVariant.as_int(pkt.get("owner_seat", pkt.get("host_seat", host_seat)), host_seat)
	var by_uid: Dictionary = _index_ships_by_uid(board)
	for u_v: Variant in TypedVariant.as_array(pkt.get("units", [])):
		if typeof(u_v) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = u_v
		var uid: String = str(u.get("net_uid", ""))
		if uid == "" or not by_uid.has(uid):
			continue
		var s: ShipUnit = by_uid[uid]
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		var wx: float = TypedVariant.as_float(u.get("x", s.global_position.x), s.global_position.x)
		var wz: float = TypedVariant.as_float(u.get("z", s.global_position.z), s.global_position.z)
		var mirrored: Vector3 = mirror_world_pos(Vector3(wx, s.global_position.y, wz), auth_owner, local_seat)
		if s.global_position.distance_squared_to(mirrored) > 0.0001:
			s.global_position = mirrored
		_apply_lock_uid(s, str(u.get("lock_uid", "")), by_uid)
	_replay_events(TypedVariant.as_array(pkt.get("events", [])), board, firing_fx, float_text)


func apply_authority(snap: Dictionary, board: BoardController = null, firing_fx: Object = null, float_text: Object = null) -> void:
	## Guest / spectate: apply host snapshot then continue predicting.
	## Reentrancy guard: apply emits spectate_stream; spectate handler must not re-apply.
	if _applying_authority:
		return
	if TypedVariant.as_bool(snap.get("is_authority", false), false) == false:
		return
	_applying_authority = true
	_last_authority = snap
	_logic_tick = TypedVariant.as_int(snap.get("logic_tick", _logic_tick), _logic_tick)
	authority_snapshot.emit(snap)
	spectate_stream.emit(snap)
	if board == null or is_host:
		_applying_authority = false
		return
	_repredict_from_authority(board, snap)
	_replay_events(TypedVariant.as_array(snap.get("events", [])), board, firing_fx, float_text)
	_applying_authority = false


func _index_ships_by_uid(board: BoardController) -> Dictionary:
	var by_uid: Dictionary = {}
	for s_v: Variant in board.all_ships():
		if not (s_v is ShipUnit):
			continue
		var s: ShipUnit = s_v
		if s == null or not is_instance_valid(s):
			continue
		var uid: String = str(s.net_uid)
		if uid != "":
			by_uid[uid] = s
	return by_uid


func _apply_lock_uid(s: ShipUnit, lock_uid: String, by_uid: Dictionary) -> void:
	if lock_uid == "":
		s.lock_target_id = 0
		s.combat_target = null
		return
	if not by_uid.has(lock_uid):
		return
	var t: ShipUnit = by_uid[lock_uid]
	if t == null or not is_instance_valid(t) or t.is_destroyed:
		s.lock_target_id = 0
		s.combat_target = null
		return
	s.lock_target_id = t.get_instance_id()
	s.combat_target = t


func _replay_events(
	events: Array,
	board: BoardController,
	firing_fx: Object,
	float_text: Object
) -> void:
	if events.is_empty() or board == null:
		return
	var by_uid: Dictionary = _index_ships_by_uid(board)
	for e_v: Variant in events:
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e_v
		var src_uid: String = str(e.get("src_uid", ""))
		var tgt_uid: String = str(e.get("tgt_uid", ""))
		if src_uid == "" or tgt_uid == "" or not by_uid.has(src_uid) or not by_uid.has(tgt_uid):
			continue
		var src: ShipUnit = by_uid[src_uid]
		var tgt: ShipUnit = by_uid[tgt_uid]
		if src == null or tgt == null or not is_instance_valid(src) or not is_instance_valid(tgt):
			continue
		var amount: float = TypedVariant.as_float(e.get("amount", 0.0), 0.0)
		var kind: String = str(e.get("kind", ""))
		var fx: String = str(e.get("fx", ""))
		if kind == "damage":
			if amount > 0.0:
				_apply_visual_damage(tgt, amount)
				if float_text != null and float_text.has_method("spawn"):
					float_text.call("spawn", tgt.global_position, "-%d" % roundi(amount), Color(1.0, 0.45, 0.35))
			if firing_fx != null and firing_fx.has_method("play"):
				var fx_kind: String = fx if fx != "" else "laser"
				firing_fx.call("play", src, tgt, fx_kind, 0.35)
		elif kind == "repair":
			if amount > 0.0:
				_apply_visual_repair(tgt, amount)
				if float_text != null and float_text.has_method("spawn"):
					float_text.call("spawn", tgt.global_position, "+%d" % roundi(amount), Color(0.35, 0.95, 0.55))
			if firing_fx != null and firing_fx.has_method("play"):
				var rfx: String = fx if fx != "" else "remote_armor"
				firing_fx.call("play", src, tgt, rfx, 0.45)


func _apply_visual_damage(s: ShipUnit, amount: float) -> void:
	var left: float = maxf(0.0, amount)
	var take: float = minf(s.shield_hp, left)
	s.shield_hp -= take
	left -= take
	if left <= 0.0:
		return
	take = minf(s.armor_hp, left)
	s.armor_hp -= take
	left -= take
	if left <= 0.0:
		return
	s.structure_hp = maxf(0.0, s.structure_hp - left)


func _apply_visual_repair(s: ShipUnit, amount: float) -> void:
	var left: float = maxf(0.0, amount)
	var room: float = maxf(0.0, s.max_shield - s.shield_hp)
	var add: float = minf(room, left)
	s.shield_hp += add
	left -= add
	if left <= 0.0:
		return
	room = maxf(0.0, s.max_armor - s.armor_hp)
	add = minf(room, left)
	s.armor_hp += add
	left -= add
	if left <= 0.0:
		return
	s.structure_hp = minf(s.max_structure, s.structure_hp + left)


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
