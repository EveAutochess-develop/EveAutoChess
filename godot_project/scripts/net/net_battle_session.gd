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
## §3.1a — guest side-equipment FX repeats on this beat while a function target holds.
const GUEST_FN_FX_PERIOD_S: float = 1.0
## Active session so MixedLance can force a full snap on lock without MatchRoot coupling.
static var _live: NetBattleSession = null

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
## Optional: Callable(seat_id) -> int manned field count for AI seats without fleet cache.
var manned_count_fn: Callable = Callable()
var _applying_authority: bool = false

## §3.4 — light cadence runs on the wall clock, not on tick modulo.
var _light_min_interval_ms: int = 100
var _light_max_gap_ms: int = 500
var _wire_compress_min: int = 512
var _last_full_ms: int = 0
var _last_light_ms: int = 0
## Host: manned roster drift requests an immediate full on the next enrich tick.
var _force_full: bool = false
## §3.3.1 A — host roster: array position is the only unit key on the wire.
var _roster: PackedStringArray = PackedStringArray()
var _roster_gen: int = 0
var _roster_iid: Dictionary = {}
var _sent_pos_q: Dictionary = {}
var _sent_lock: Dictionary = {}
## §3.3.1 B — guest side: roster index → local ship, plus dead reckoning state.
var _g_roster_gen: int = -1
var _g_ships: Array = []
var _g_owner_seat: int = 0
var _g_state: Dictionary = {}
var _g_extrapolate_max_s: float = 1.0
var _g_pos_smooth_s: float = 0.15
var _g_hp_smooth_s: float = 0.3
var _g_seed: int = 0
## Unmanned net_uid sequence — host-minted only (§3.2a).
var _unmanned_uid_seq: int = 0
## Guest: ship instance ids that currently have a net-driven lance FX.
var _g_lance_iids: Dictionary = {}


static func live_session() -> NetBattleSession:
	return _live


func setup(rng: MatchRng, net: NullsecNetSession, payload: Dictionary) -> void:
	_live = self
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
	_light_min_interval_ms = maxi(16, NetConnectivity.light_min_interval_ms())
	_light_max_gap_ms = maxi(_light_min_interval_ms, NetConnectivity.light_max_gap_ms())
	_wire_compress_min = NetConnectivity.wire_compress_min_bytes()
	_g_extrapolate_max_s = maxf(0.0, NetConnectivity.guest_extrapolate_max_s())
	_g_pos_smooth_s = maxf(0.01, NetConnectivity.guest_pos_smooth_s())
	_g_hp_smooth_s = maxf(0.01, NetConnectivity.guest_hp_correct_smooth_s())
	_g_seed = TypedVariant.as_int(payload.get("seed", 0), 0)
	## Lowsec and nullsec share the same periodic authority enrich path.
	silent_battle = false
	_wall_anchor_msec = Time.get_ticks_msec()
	host_sim = HostSimOrchestrator.new()
	host_sim.setup(rng)
	NetSessionDebug.log_event(
		"net.battle.setup",
		"mode=%s silent=%s host=%s full=%d light_ms=%d/%d" % [
			security_mode, silent_battle, is_host,
			full_sync_interval, _light_min_interval_ms, _light_max_gap_ms
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
	_reset_wire_state()


func _exit_tree() -> void:
	if _live == self:
		_live = null


func _reset_wire_state() -> void:
	_roster = PackedStringArray()
	_roster_gen = 0
	_roster_iid.clear()
	_sent_pos_q.clear()
	_sent_lock.clear()
	_last_full_ms = 0
	_last_light_ms = 0
	_force_full = false
	_g_roster_gen = -1
	_g_ships.clear()
	_g_state.clear()
	_g_lance_iids.clear()
	_unmanned_uid_seq = 0


## SEMI_ASYNC §5.3a — after host migration, elected peer must start headless.
func refresh_host_role() -> void:
	var was_host: bool = is_host
	is_host = _net != null and _net.is_host
	if _net:
		host_seat = TypedVariant.as_int(_net.last_match_payload.get("host_seat", host_seat), host_seat)
		GameSession.pending_nullsec["host_seat"] = host_seat
	if is_host and headless:
		headless.ensure_running()
	_reset_wire_state()
	## New authority must rebuild roster + push a full snap; demoted peers wait for it.
	if is_host:
		_force_full = true
	elif was_host and not is_host:
		## Leaving authority: clear guest coast so the next full snap reseats cleanly.
		_g_state.clear()
		_g_ships.clear()
		_g_roster_gen = -1


func request_force_full_sync() -> void:
	_force_full = true


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
			_enqueue_pvp_or_ai_instant(
				TypedVariant.as_int(contenders[0], 0),
				TypedVariant.as_int(contenders[1], 0)
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
				_enqueue_pvp_or_ai_instant(a, b)
	else:
		## Nullsec PVE: humans / local seats sim creeps on-device (SEMI_ASYNC §3.2).
		## Only enqueue lightweight HostSim reports for ai_player seats with no client.
		for seat_v: Variant in contenders:
			var seat: int = TypedVariant.as_int(seat_v, -1)
			if seat < 0:
				continue
			if not _pending_seat_is_ai(seat):
				continue
			var task: String = "pve_salvage" if (round_r % 2 == 0) else "pve_eliminate"
			host_sim.enqueue_pve(seat, task)
		## No AI PVE jobs → titan/prepare must not wait on an empty HostSim queue forever.
		if host_sim.pending_count() == 0:
			_awaiting_titan = false


func _enqueue_pvp_or_ai_instant(seat_a: int, seat_b: int) -> void:
	## Only ai_player ↔ ai_player skips combat (MATCH_FLOW §5.0). Human tables stay real.
	if _pending_seat_is_ai(seat_a) and _pending_seat_is_ai(seat_b):
		var ships_a: int = _manned_field_count_for_seat(seat_a)
		var ships_b: int = _manned_field_count_for_seat(seat_b)
		var kg: int = TypedVariant.as_int(DataStore.economy.get("kill_gold_per_ship", 1), 1)
		_active_serial = host_sim.enqueue_ai_vs_ai_instant(seat_a, seat_b, ships_a, ships_b, kg)
		NetSessionDebug.log_event(
			"net.ai_instant",
			"a=%d b=%d ships=%d/%d gold=%d/%d" % [
				seat_a, seat_b, ships_a, ships_b, ships_b * kg, ships_a * kg
			]
		)
		return
	var home: int = seat_a if seat_a == host_seat or seat_b != host_seat else seat_b
	_active_serial = host_sim.enqueue_pvp(seat_a, seat_b, home)


func _pending_seat_is_ai(seat_id: int) -> bool:
	for s_v: Variant in TypedVariant.as_array(GameSession.pending_nullsec.get("seats", [])):
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if TypedVariant.as_int(s.get("seat_id", -1), -1) == seat_id:
			return TypedVariant.as_bool(s.get("is_ai", false), false)
	return false


func _manned_field_count_for_seat(seat_id: int) -> int:
	## Prefer Prepare fleet cache (humans); AI seats fall back to estimate callback / 0.
	if _net != null and _net.has_method("manned_field_count_cached"):
		var cached_n: int = TypedVariant.as_int(_net.call("manned_field_count_cached", seat_id), 0)
		if cached_n > 0:
			return cached_n
	if manned_count_fn.is_valid():
		return maxi(0, TypedVariant.as_int(manned_count_fn.call(seat_id), 0))
	return 0


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
			var wall: int = Time.get_ticks_msec() - _wall_anchor_msec
			if wall > 30000 and (_logic_tick % (logic_hz * 5) == 0):
				NetSessionDebug.log_event("net.drift.check", "wall_ms=%d tick=%d" % [wall, _logic_tick])
				if _net and _net.is_host:
					_net.broadcast_ships_hash()


func should_enrich_this_tick() -> bool:
	## Full authority snapshot (~2s), or manned-roster force.
	if not is_host:
		return false
	if _force_full:
		return true
	return _logic_tick > 0 and (_logic_tick % maxi(1, full_sync_interval) == 0)


## SEMI_ASYNC §3.4 — light packets ride the wall clock: never denser than
## light_min_interval_ms, never sparser than light_max_gap_ms while a battle runs.
func should_light_now() -> bool:
	if not is_host or _logic_tick <= 0:
		return false
	var now: int = Time.get_ticks_msec()
	var gap: int = now - _last_light_ms
	if gap >= _light_max_gap_ms:
		return true
	if gap < _light_min_interval_ms:
		return false
	## A full snapshot just went out — its state is fresher than a light packet.
	return now - _last_full_ms >= _light_min_interval_ms


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


func enrich_and_broadcast(board: BoardController, income_total: int = 0) -> void:
	if not is_host:
		return
	var units: Array = []
	var ships: Array = []
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
			ships.append(s)
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
	_rebuild_roster(ships)
	_income_logs.append({"seat": local_seat, "income_total": income_total, "tick": _logic_tick})
	while _income_logs.size() > 64:
		_income_logs.pop_front()
	var drained: Array = _drain_pending_events(LIGHT_EVENTS_CAP * 2)
	var state_hash: String = _hash_units(units)
	## Local shape is unchanged: spectate + anticheat keep reading the Dictionary.
	## Only the wire form is binary, and spot / income logs stay host-local (§3.3.1 A).
	var snap: Dictionary = {
		"kind": "full",
		"logic_tick": _logic_tick,
		"active_serial": _active_serial,
		"state_hash": state_hash,
		"units": units,
		"events": drained,
		"spot_logs": _spot_logs.duplicate(true),
		"income_logs": _income_logs.duplicate(true),
		"host_seat": host_seat,
		"owner_seat": owner_seat if owner_seat >= 0 else host_seat,
		"is_authority": true,
	}
	_last_authority = snap
	_last_full_ms = Time.get_ticks_msec()
	_force_full = false
	_sent_pos_q.clear()
	_sent_lock.clear()
	authority_snapshot.emit(snap)
	spectate_stream.emit(snap)
	if _net and _net.multiplayer and _net.multiplayer.has_multiplayer_peer():
		_net.broadcast_authority_snapshot_bin(_encode_full(ships, drained, state_hash))


## SEMI_ASYNC §3.3.1 B — light: moved x/z, changed locks, fire/repair pairs. Nothing else.
func enrich_and_broadcast_light(board: BoardController) -> void:
	if not is_host:
		return
	if board != null and _manned_roster_needs_full(board):
		## Manned field roster drift → force next tick full; unmanned alone never does.
		_force_full = true
		return
	## Lance Prep/Fire/End: upgrade light cadence to full so angle trailers keep syncing.
	if board != null and _any_active_lance(board):
		_force_full = true
		_last_light_ms = Time.get_ticks_msec()
		return
	_last_light_ms = Time.get_ticks_msec()
	if board == null or _roster.is_empty():
		return
	var moves: PackedByteArray = PackedByteArray()
	var n_move: int = 0
	var locks: PackedByteArray = PackedByteArray()
	var n_lock: int = 0
	for s_v: Variant in board.all_ships():
		if not (s_v is ShipUnit):
			continue
		var s: ShipUnit = s_v
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		var idx: int = TypedVariant.as_int(_roster_iid.get(s.get_instance_id(), -1), -1)
		if idx < 0:
			continue
		if _ship_can_move(s):
			var qx: int = NetWireCodec.quant_pos(s.global_position.x)
			var qy: int = NetWireCodec.quant_pos(s.global_position.y)
			var qz: int = NetWireCodec.quant_pos(s.global_position.z)
			var q: Vector3i = Vector3i(qx, qy, qz)
			## Quantized-identical positions never go on the wire.
			if _sent_pos_q.get(idx, null) != q:
				_sent_pos_q[idx] = q
				NetWireCodec.append_u16(moves, idx)
				NetWireCodec.append_i16(moves, qx)
				NetWireCodec.append_i16(moves, qy)
				NetWireCodec.append_i16(moves, qz)
				n_move += 1
		var pair: Vector2i = Vector2i(_idx_of_iid(int(s.lock_target_id)), _idx_of_fn_target(s))
		if _sent_lock.get(idx, null) != pair:
			_sent_lock[idx] = pair
			NetWireCodec.append_u16(locks, idx)
			NetWireCodec.append_u16(locks, pair.x)
			NetWireCodec.append_u16(locks, pair.y)
			n_lock += 1
	var events: Array = _drain_pending_events(LIGHT_EVENTS_CAP)
	if n_move == 0 and n_lock == 0 and events.is_empty():
		return
	var buf: PackedByteArray = PackedByteArray()
	NetWireCodec.append_u8(buf, NetWireCodec.KIND_LIGHT)
	NetWireCodec.append_u16(buf, _roster_gen)
	NetWireCodec.append_u32(buf, _logic_tick)
	NetWireCodec.append_u8(buf, host_seat)
	NetWireCodec.append_u8(buf, owner_seat if owner_seat >= 0 else host_seat)
	NetWireCodec.append_u16(buf, n_move)
	buf.append_array(moves)
	NetWireCodec.append_u16(buf, n_lock)
	buf.append_array(locks)
	_append_event_pairs(buf, events)
	if _net and _net.multiplayer and _net.multiplayer.has_multiplayer_peer():
		_net.broadcast_authority_light_bin(NetWireCodec.wrap(buf, _wire_compress_min))


func _encode_full(ships: Array, events: Array, state_hash: String) -> PackedByteArray:
	var buf: PackedByteArray = PackedByteArray()
	NetWireCodec.append_u8(buf, NetWireCodec.KIND_FULL)
	NetWireCodec.append_u16(buf, _roster_gen)
	NetWireCodec.append_u32(buf, _logic_tick)
	NetWireCodec.append_u16(buf, _active_serial)
	NetWireCodec.append_u8(buf, host_seat)
	NetWireCodec.append_u8(buf, owner_seat if owner_seat >= 0 else host_seat)
	NetWireCodec.append_u32(buf, state_hash.hex_to_int())
	## Roster rides every full: a late joiner must never wait for the next change.
	NetWireCodec.append_u16(buf, _roster.size())
	for uid: String in _roster:
		NetWireCodec.append_str(buf, uid)
	NetWireCodec.append_u16(buf, ships.size())
	for i: int in range(ships.size()):
		var s: ShipUnit = ships[i]
		NetWireCodec.append_u16(buf, i)
		NetWireCodec.append_i16(buf, NetWireCodec.quant_pos(s.global_position.x))
		NetWireCodec.append_i16(buf, NetWireCodec.quant_pos(s.global_position.y))
		NetWireCodec.append_i16(buf, NetWireCodec.quant_pos(s.global_position.z))
		NetWireCodec.append_u32(buf, NetWireCodec.quant_hp(s.shield_hp))
		NetWireCodec.append_u32(buf, NetWireCodec.quant_hp(s.armor_hp))
		NetWireCodec.append_u32(buf, NetWireCodec.quant_hp(s.structure_hp))
		var flags: int = 0
		if s.is_destroyed:
			flags |= 1
		if s.is_destroyed and FunctionFit.is_cyno_hull(DataStore.get_ship(s.ship_id)):
			flags |= 2
		if s.is_unmanned:
			flags |= 4
		NetWireCodec.append_u8(buf, flags)
		NetWireCodec.append_u16(buf, _idx_of_iid(int(s.lock_target_id)))
		NetWireCodec.append_u16(buf, _idx_of_fn_target(s))
		NetWireCodec.append_u16(buf, _idx_of_iid(int(s.pre_lock_target_id)))
		NetWireCodec.append_u16(buf, clampi(roundi(s.pre_lock_timer * 1000.0), 0, 65535))
		NetWireCodec.append_u16(buf, clampi(roundi(s.pre_lock_duration_s * 1000.0), 0, 65535))
		if s.is_unmanned:
			## Birth desc — guest rebuilds missing drones from this (§3.3.1 A).
			NetWireCodec.append_u16(buf, clampi(int(s.ship_id), 0, 65535))
			NetWireCodec.append_u8(buf, clampi(int(s.star), 1, 255))
			NetWireCodec.append_u8(buf, clampi(int(s.team_id), 0, 255))
			NetWireCodec.append_u16(buf, _idx_of_iid(int(s.mother_ship_id)))
			var sq: int = int(s.fighter_squadron_id)
			NetWireCodec.append_u8(buf, 0 if sq < 0 else clampi(sq + 1, 1, 255))
	_append_event_pairs(buf, events)
	_append_lance_aims(buf, ships)
	return NetWireCodec.wrap(buf, _wire_compress_min)


## Events carry two indices only: kind comes from src.is_logistic, fx from the
## weapon, amount is estimated locally (§3.1a).
func _append_event_pairs(buf: PackedByteArray, events: Array) -> void:
	var pairs: PackedByteArray = PackedByteArray()
	var n: int = 0
	for e_v: Variant in events:
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e_v
		var si: int = TypedVariant.as_int(_roster_iid.get(TypedVariant.as_int(e.get("src_id", 0), 0), -1), -1)
		var ti: int = TypedVariant.as_int(_roster_iid.get(TypedVariant.as_int(e.get("tgt_id", 0), 0), -1), -1)
		if si < 0 or ti < 0:
			continue
		NetWireCodec.append_u16(pairs, si)
		NetWireCodec.append_u16(pairs, ti)
		n += 1
	NetWireCodec.append_u16(buf, n)
	buf.append_array(pairs)


func _append_lance_aims(buf: PackedByteArray, ships: Array) -> void:
	## SEMI_ASYNC §3.3.1 A — every full while Prep/Fire/End must list ALL active aims.
	var rows: Array = MixedLance.collect_active_aim_rows(ships, Callable(self, "_idx_of_iid"))
	NetWireCodec.append_u16(buf, rows.size())
	for r_v: Variant in rows:
		var r: Dictionary = TypedVariant.as_dict(r_v)
		NetWireCodec.append_u16(buf, TypedVariant.as_int(r.get("idx", 0), 0))
		NetWireCodec.append_i16(buf, MixedLance.quant_angle(TypedVariant.as_float(r.get("az_xz", 0.0))))
		NetWireCodec.append_i16(buf, MixedLance.quant_angle(TypedVariant.as_float(r.get("el_xy", 0.0))))


## True while any field ship is in Prep/Fire/End — keep fulls carrying angles.
func _any_active_lance(board: BoardController) -> bool:
	return MixedLance.has_any_active(board)


func _rebuild_roster(ships: Array) -> void:
	var next: PackedStringArray = PackedStringArray()
	var iids: Dictionary = {}
	for i: int in range(ships.size()):
		var s: ShipUnit = ships[i]
		next.append(_ensure_net_uid(s))
		iids[s.get_instance_id()] = i
	if next != _roster:
		_roster_gen = (_roster_gen + 1) & 0xFFFF
		_sent_pos_q.clear()
		_sent_lock.clear()
	_roster = next
	_roster_iid = iids


func _idx_of_iid(iid: int) -> int:
	if iid == 0:
		return NetWireCodec.NO_IDX
	return TypedVariant.as_int(_roster_iid.get(iid, NetWireCodec.NO_IDX), NetWireCodec.NO_IDX)


func _idx_of_fn_target(s: ShipUnit) -> int:
	var ft: Variant = s._function_target
	if ft == null or not (ft is ShipUnit):
		return NetWireCodec.NO_IDX
	@warning_ignore("unsafe_cast")
	var t: ShipUnit = ft as ShipUnit
	if not is_instance_valid(t):
		return NetWireCodec.NO_IDX
	return _idx_of_iid(t.get_instance_id())


static func _ship_can_move(s: ShipUnit) -> bool:
	if s.immobile_in_combat:
		return false
	if s.has_cyno_module():
		return false
	return true


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
		"src_id": src.get_instance_id(),
		"tgt_id": tgt.get_instance_id(),
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
	if uid != "":
		return uid
	if s.is_unmanned:
		## Session-unique — mother grid collision must never collapse the roster.
		_unmanned_uid_seq = (_unmanned_uid_seq + 1) & 0x7FFFFFFF
		uid = "u|%d|%d" % [int(s.ship_id), _unmanned_uid_seq]
	else:
		uid = "%d|%d|%d|%d|%d" % [local_seat, int(s.ship_id), int(s.team_id), int(s.grid_x), int(s.grid_z)]
	s.net_uid = uid
	return uid


## Alive manned field ships missing from the host roster → force full.
## Unmanned spawn/despawn alone never trips this (§3.2a).
func _manned_roster_needs_full(board: BoardController) -> bool:
	if _roster.is_empty():
		return false
	for s_v: Variant in board.all_ships():
		if not (s_v is ShipUnit):
			continue
		var s: ShipUnit = s_v
		if s == null or not is_instance_valid(s) or s.is_destroyed or s.is_unmanned:
			continue
		if str(s.slot_type) != "field":
			continue
		if not _roster_iid.has(s.get_instance_id()):
			return true
	for iid_v: Variant in _roster_iid.keys():
		var iid: int = TypedVariant.as_int(iid_v, 0)
		var idx: int = TypedVariant.as_int(_roster_iid.get(iid, -1), -1)
		if idx < 0 or idx >= _roster.size():
			continue
		if str(_roster[idx]).begins_with("u|"):
			continue
		@warning_ignore("unsafe_cast")
		var ship: ShipUnit = instance_from_id(iid) as ShipUnit
		if ship == null or not is_instance_valid(ship):
			return true
	return false


func _lock_uid_of(s: ShipUnit) -> String:
	var lid: int = int(s.lock_target_id)
	if lid == 0:
		return ""
	@warning_ignore("unsafe_cast")
	var t: ShipUnit = instance_from_id(lid) as ShipUnit
	if t == null or not is_instance_valid(t):
		return ""
	return _ensure_net_uid(t)


## ─────────────────────────── guest apply (binary) ───────────────────────────

## SEMI_ASYNC §3.3.1 A — decode a full snapshot and re-anchor the guest board.
func apply_full_bin(
	data: PackedByteArray,
	board: BoardController,
	firing_fx: Object = null,
	float_text: Object = null
) -> void:
	if is_host or board == null:
		return
	var p: PackedByteArray = NetWireCodec.unwrap(data)
	if p.size() < 17 or p[0] != NetWireCodec.KIND_FULL:
		return
	var i: int = 1
	var gen: int = NetWireCodec.read_u16(p, i)
	i += 2
	_logic_tick = NetWireCodec.read_u32(p, i)
	i += 4
	_active_serial = NetWireCodec.read_u16(p, i)
	i += 2
	host_seat = NetWireCodec.read_u8(p, i)
	i += 1
	_g_owner_seat = NetWireCodec.read_u8(p, i)
	i += 1
	## state_hash is diagnostics only on guests.
	i += 4
	var n_roster: int = NetWireCodec.read_u16(p, i)
	i += 2
	var roster: PackedStringArray = PackedStringArray()
	for _r: int in range(n_roster):
		if i >= p.size():
			return
		var slen: int = NetWireCodec.read_u8(p, i)
		i += 1
		if i + slen > p.size():
			return
		roster.append(p.slice(i, i + slen).get_string_from_utf8())
		i += slen
	_g_ships = _resolve_roster(board, roster)
	_g_roster_gen = gen
	if i + 2 > p.size():
		return
	var n_units: int = NetWireCodec.read_u16(p, i)
	i += 2
	var gaps: int = 0
	var now: int = Time.get_ticks_msec()
	## Pass 1: apply known units; queue unmanned birth for missing slots.
	var pending_birth: Array = []
	for _u: int in range(n_units):
		if i + 31 > p.size():
			return
		var idx: int = NetWireCodec.read_u16(p, i)
		var wx: float = NetWireCodec.dequant_pos(NetWireCodec.read_i16(p, i + 2))
		var wy: float = NetWireCodec.dequant_pos(NetWireCodec.read_i16(p, i + 4))
		var wz: float = NetWireCodec.dequant_pos(NetWireCodec.read_i16(p, i + 6))
		var sh: float = NetWireCodec.dequant_hp(NetWireCodec.read_u32(p, i + 8))
		var ar: float = NetWireCodec.dequant_hp(NetWireCodec.read_u32(p, i + 12))
		var st_hp: float = NetWireCodec.dequant_hp(NetWireCodec.read_u32(p, i + 16))
		var flags: int = NetWireCodec.read_u8(p, i + 20)
		var lock_i: int = NetWireCodec.read_u16(p, i + 21)
		var fn_i: int = NetWireCodec.read_u16(p, i + 23)
		var pre_i: int = NetWireCodec.read_u16(p, i + 25)
		var pre_t: int = NetWireCodec.read_u16(p, i + 27)
		var pre_d: int = NetWireCodec.read_u16(p, i + 29)
		i += 31
		var birth_ship_id: int = 0
		var birth_star: int = 1
		var birth_team: int = 0
		var birth_mother: int = NetWireCodec.NO_IDX
		var birth_sq: int = -1
		if (flags & 4) != 0:
			if i + 7 > p.size():
				return
			birth_ship_id = NetWireCodec.read_u16(p, i)
			birth_star = NetWireCodec.read_u8(p, i + 2)
			birth_team = NetWireCodec.read_u8(p, i + 3)
			birth_mother = NetWireCodec.read_u16(p, i + 4)
			var sq_plus: int = NetWireCodec.read_u8(p, i + 6)
			birth_sq = -1 if sq_plus <= 0 else (sq_plus - 1)
			i += 7
		var pos: Vector3 = mirror_world_pos(Vector3(wx, wy, wz), _g_owner_seat, local_seat)
		var s: ShipUnit = _ship_at(idx)
		if s == null:
			if (flags & 4) != 0 and (flags & 1) == 0 and birth_ship_id > 0:
				pending_birth.append({
					"idx": idx,
					"pos": pos,
					"sh": sh, "ar": ar, "st": st_hp,
					"flags": flags,
					"lock_i": lock_i, "fn_i": fn_i,
					"pre_i": pre_i, "pre_t": pre_t, "pre_d": pre_d,
					"ship_id": birth_ship_id,
					"star": birth_star,
					"team": birth_team,
					"mother_idx": birth_mother,
					"squadron": birth_sq,
					"uid": roster[idx] if idx < roster.size() else "",
				})
			continue
		if not watch_only_apply:
			var auth_hp: float = sh + ar + st_hp
			var local_hp: float = float(s.structure_hp) + float(s.armor_hp) + float(s.shield_hp)
			if absf(auth_hp - local_hp) / maxf(1.0, auth_hp) > NetConnectivity.anticheat_gap_hp_rel():
				gaps += 1
		_apply_unit_from_full(
			s, pos, sh, ar, st_hp, flags, lock_i, fn_i, pre_i, pre_t, pre_d, now
		)
	## Pass 2: spawn missing unmanned after mothers are resolved.
	for b_v: Variant in pending_birth:
		var b: Dictionary = b_v
		var idx2: int = TypedVariant.as_int(b.get("idx", -1), -1)
		if idx2 < 0:
			continue
		var mother: ShipUnit = _ship_at(TypedVariant.as_int(b.get("mother_idx", NetWireCodec.NO_IDX), NetWireCodec.NO_IDX))
		var tteam: int = TypedVariant.as_int(b.get("team", 0), 0)
		if _g_owner_seat != local_seat:
			tteam = mirror_team(tteam)
		var d: ShipUnit = board.spawn_unmanned(
			TypedVariant.as_int(b.get("ship_id", 0), 0),
			tteam,
			TypedVariant.as_vector3(b.get("pos", Vector3.ZERO)),
			mother,
			maxi(1, TypedVariant.as_int(b.get("star", 1), 1)),
			TypedVariant.as_int(b.get("squadron", -1), -1)
		)
		if d == null or not is_instance_valid(d):
			continue
		d.net_uid = str(b.get("uid", ""))
		if d.get_node_or_null(EngineBoosterTrail.ROOT_NAME) == null:
			EngineBoosterTrail.ensure_on(d, d.team_id == ShipUnit.TEAM_PLAYER)
		EngineBoosterTrail.set_emitting_on(d, true)
		if idx2 < _g_ships.size():
			_g_ships[idx2] = d
		_apply_unit_from_full(
			d,
			TypedVariant.as_vector3(b.get("pos", Vector3.ZERO)),
			TypedVariant.as_float(b.get("sh", 0.0), 0.0),
			TypedVariant.as_float(b.get("ar", 0.0), 0.0),
			TypedVariant.as_float(b.get("st", 0.0), 0.0),
			TypedVariant.as_int(b.get("flags", 0), 0),
			TypedVariant.as_int(b.get("lock_i", NetWireCodec.NO_IDX), NetWireCodec.NO_IDX),
			TypedVariant.as_int(b.get("fn_i", NetWireCodec.NO_IDX), NetWireCodec.NO_IDX),
			TypedVariant.as_int(b.get("pre_i", NetWireCodec.NO_IDX), NetWireCodec.NO_IDX),
			TypedVariant.as_int(b.get("pre_t", 0), 0),
			TypedVariant.as_int(b.get("pre_d", 0), 0),
			now
		)
	if watch_only_apply:
		_guest_cull_orphan_unmanned(board, roster)
	var after_events: int = _replay_event_pairs(p, i, firing_fx, float_text)
	_apply_lance_aims_bin(p, after_events)
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


func _apply_unit_from_full(
	s: ShipUnit,
	pos: Vector3,
	sh: float,
	ar: float,
	st_hp: float,
	flags: int,
	lock_i: int,
	fn_i: int,
	pre_i: int,
	pre_t: int,
	pre_d: int,
	now: int
) -> void:
	var alive: bool = (flags & 1) == 0
	if alive and s.is_destroyed:
		## Authority still alive — resurrect (no HP smooth from zero).
		s.is_destroyed = false
		s.visible = true
		s.shield_hp = sh
		s.armor_hp = ar
		s.structure_hp = st_hp
		s.refresh_health_bar()
		_g_state.erase(s.get_instance_id())
		if s.global_position.distance_squared_to(pos) > 0.0001:
			s.global_position = pos
	elif watch_only_apply:
		_guest_note_pos(s, pos, now)
		_guest_note_hp(s, Vector3(sh, ar, st_hp))
	else:
		if s.global_position.distance_squared_to(pos) > 0.0001:
			s.global_position = pos
		s.shield_hp = sh
		s.armor_hp = ar
		s.structure_hp = st_hp
		s.refresh_health_bar()
	if not alive and not s.is_destroyed:
		s.is_destroyed = true
		s.visible = false
		_g_state.erase(s.get_instance_id())
	_apply_lock_idx(s, lock_i)
	_guest_note_fn_target(s, fn_i)
	s.pre_lock_target_id = _iid_at(pre_i)
	s.pre_lock_timer = float(pre_t) / 1000.0
	s.pre_lock_duration_s = float(pre_d) / 1000.0


func _guest_cull_orphan_unmanned(board: BoardController, roster: PackedStringArray) -> void:
	var keep: Dictionary = {}
	for uid: String in roster:
		keep[uid] = true
	var doomed: Array = []
	for s_v: Variant in board.all_ships():
		if not (s_v is ShipUnit):
			continue
		var s: ShipUnit = s_v
		if s == null or not is_instance_valid(s) or not s.is_unmanned:
			continue
		var uid2: String = str(s.net_uid)
		if uid2 == "" or not keep.has(uid2):
			doomed.append(s)
	for d_v: Variant in doomed:
		@warning_ignore("unsafe_cast")
		var d: ShipUnit = d_v as ShipUnit
		if d != null and is_instance_valid(d):
			_g_state.erase(d.get_instance_id())
			board.remove_ship_node(d)


## SEMI_ASYNC §3.3.1 B — decode a light packet; drop it when the roster is stale.
func apply_light_bin(
	data: PackedByteArray,
	board: BoardController,
	firing_fx: Object = null,
	float_text: Object = null
) -> void:
	if is_host or board == null:
		return
	var p: PackedByteArray = NetWireCodec.unwrap(data)
	if p.size() < 11 or p[0] != NetWireCodec.KIND_LIGHT:
		return
	var gen: int = NetWireCodec.read_u16(p, 1)
	if gen != _g_roster_gen or _g_ships.is_empty():
		return
	_logic_tick = NetWireCodec.read_u32(p, 3)
	host_seat = NetWireCodec.read_u8(p, 7)
	_g_owner_seat = NetWireCodec.read_u8(p, 8)
	var i: int = 9
	var n_move: int = NetWireCodec.read_u16(p, i)
	i += 2
	var now: int = Time.get_ticks_msec()
	for _m: int in range(n_move):
		if i + 8 > p.size():
			return
		var idx: int = NetWireCodec.read_u16(p, i)
		var wx: float = NetWireCodec.dequant_pos(NetWireCodec.read_i16(p, i + 2))
		var wy: float = NetWireCodec.dequant_pos(NetWireCodec.read_i16(p, i + 4))
		var wz: float = NetWireCodec.dequant_pos(NetWireCodec.read_i16(p, i + 6))
		i += 8
		var s: ShipUnit = _ship_at(idx)
		if s == null or s.is_destroyed:
			continue
		var pos: Vector3 = mirror_world_pos(Vector3(wx, wy, wz), _g_owner_seat, local_seat)
		## Mirror flips XZ; keep authority Y. Deck-locked hulls stay on deck.
		if not s.y_axis_unlocked():
			pos.y = BoardController.DECK_Y
		if watch_only_apply:
			_guest_note_pos(s, pos, now)
		elif s.global_position.distance_squared_to(pos) > 0.0001:
			s.global_position = pos
	if i + 2 > p.size():
		return
	var n_lock: int = NetWireCodec.read_u16(p, i)
	i += 2
	for _l: int in range(n_lock):
		if i + 6 > p.size():
			return
		var idx2: int = NetWireCodec.read_u16(p, i)
		var lock_i: int = NetWireCodec.read_u16(p, i + 2)
		var fn_i: int = NetWireCodec.read_u16(p, i + 4)
		i += 6
		var s2: ShipUnit = _ship_at(idx2)
		if s2 == null or s2.is_destroyed:
			continue
		_apply_lock_idx(s2, lock_i)
		_guest_note_fn_target(s2, fn_i)
	_replay_event_pairs(p, i, firing_fx, float_text)


func _replay_event_pairs(p: PackedByteArray, i: int, firing_fx: Object, float_text: Object) -> int:
	if i + 2 > p.size():
		return i
	var n: int = NetWireCodec.read_u16(p, i)
	i += 2
	for _e: int in range(n):
		if i + 4 > p.size():
			return i
		var src: ShipUnit = _ship_at(NetWireCodec.read_u16(p, i))
		var tgt: ShipUnit = _ship_at(NetWireCodec.read_u16(p, i + 2))
		i += 4
		if src == null or tgt == null or tgt.is_destroyed:
			continue
		_guest_fire_once(src, tgt, firing_fx, float_text)
		if watch_only_apply:
			## Authority just fired for real — restart the self-fire clock from here.
			var st: Dictionary = _guest_state(src)
			st["fire_acc"] = 0.0
			st["last_evt_ms"] = Time.get_ticks_msec()
	return i


func _apply_lance_aims_bin(p: PackedByteArray, i: int) -> void:
	## Trailer optional for older hosts: missing bytes → clear nothing new.
	if i + 2 > p.size():
		return
	var n: int = NetWireCodec.read_u16(p, i)
	i += 2
	var seen: Dictionary = {}
	for _l: int in range(n):
		if i + 6 > p.size():
			break
		var idx: int = NetWireCodec.read_u16(p, i)
		var az: float = MixedLance.dequant_angle(NetWireCodec.read_i16(p, i + 2))
		var el: float = MixedLance.dequant_angle(NetWireCodec.read_i16(p, i + 4))
		i += 6
		var s: ShipUnit = _ship_at(idx)
		if s == null or s.is_destroyed:
			continue
		if _g_owner_seat != local_seat:
			var dir: Vector3 = MixedLance.angles_to_dir(az, el)
			dir = Vector3(-dir.x, dir.y, -dir.z)
			az = MixedLance.dir_to_az_xz(dir)
			el = MixedLance.dir_to_el_xy(dir)
		MixedLance.apply_guest_aim(s, az, el)
		seen[s.get_instance_id()] = true
		_g_lance_iids[s.get_instance_id()] = true
	## Drop guest FX for lances no longer in the trailer.
	var drop: Array = []
	for iid_v: Variant in _g_lance_iids.keys():
		var iid: int = TypedVariant.as_int(iid_v, 0)
		if seen.has(iid):
			continue
		drop.append(iid)
	for iid2_v: Variant in drop:
		var iid2: int = TypedVariant.as_int(iid2_v, 0)
		_g_lance_iids.erase(iid2)
		@warning_ignore("unsafe_cast")
		var ship: ShipUnit = instance_from_id(iid2) as ShipUnit
		if ship != null and is_instance_valid(ship):
			MixedLance.clear_guest_aim(ship)


func _ship_at(idx: int) -> ShipUnit:
	if idx < 0 or idx >= _g_ships.size():
		return null
	var s_v: Variant = _g_ships[idx]
	if s_v == null or not (s_v is ShipUnit):
		return null
	@warning_ignore("unsafe_cast")
	var s: ShipUnit = s_v as ShipUnit
	return s if is_instance_valid(s) else null


func _iid_at(idx: int) -> int:
	var s: ShipUnit = _ship_at(idx)
	return s.get_instance_id() if s != null else 0


func _apply_lock_idx(s: ShipUnit, idx: int) -> void:
	var t: ShipUnit = _ship_at(idx)
	if t == null or t.is_destroyed:
		s.lock_target_id = 0
		s.combat_target = null
		return
	s.lock_target_id = t.get_instance_id()
	s.combat_target = t


func _resolve_roster(board: BoardController, roster: PackedStringArray) -> Array:
	var by_uid: Dictionary = {}
	var by_fb: Dictionary = {}
	for s_v: Variant in board.all_ships():
		if not (s_v is ShipUnit):
			continue
		var s: ShipUnit = s_v
		if s == null or not is_instance_valid(s):
			continue
		var uid: String = str(s.net_uid)
		if uid != "":
			by_uid[uid] = s
		## Grid fallback only for manned — drones share mother grid and must not collide.
		if not s.is_unmanned:
			by_fb["%d|%d|%d|%d" % [int(s.ship_id), int(s.team_id), int(s.grid_x), int(s.grid_z)]] = s
	var out: Array = []
	out.resize(roster.size())
	for i: int in range(roster.size()):
		var uid2: String = roster[i]
		var found: Variant = by_uid.get(uid2, null)
		if found == null and not uid2.begins_with("u|"):
			## Host-minted manned combat uid seat|ship_id|team|gx|gz — try both teams.
			var parts: PackedStringArray = uid2.split("|")
			if parts.size() == 5 and parts[2].is_valid_int():
				var team: int = int(parts[2])
				var k1: String = "%s|%d|%s|%s" % [parts[1], team, parts[3], parts[4]]
				var k2: String = "%s|%d|%s|%s" % [parts[1], mirror_team(team), parts[3], parts[4]]
				found = by_fb.get(k1, by_fb.get(k2, null))
				if found is ShipUnit:
					@warning_ignore("unsafe_cast")
					var fs: ShipUnit = found as ShipUnit
					if str(fs.net_uid) == "":
						fs.net_uid = uid2
		out[i] = found if (found is ShipUnit) else null
	return out


## ─────────────────────── guest dead reckoning (§3.1a) ───────────────────────

func _guest_state(s: ShipUnit) -> Dictionary:
	var iid: int = s.get_instance_id()
	if not _g_state.has(iid):
		_g_state[iid] = {
			"vel": Vector3.ZERO,
			"err": Vector3.ZERO,
			"last_ms": 0,
			"last_pos": s.global_position,
			"fire_acc": 0.0,
			"fn_acc": 0.0,
			"fn_iid": 0,
			"last_evt_ms": 0,
			"hp_t": Vector3.ZERO,
			"hp_left": 0.0,
		}
	return _g_state[iid]


func _guest_note_pos(s: ShipUnit, pos: Vector3, now: int) -> void:
	var st: Dictionary = _guest_state(s)
	var last_ms: int = TypedVariant.as_int(st.get("last_ms", 0), 0)
	if last_ms <= 0:
		s.global_position = pos
		st["vel"] = Vector3.ZERO
		st["err"] = Vector3.ZERO
	else:
		var dt: float = float(now - last_ms) / 1000.0
		if dt > 0.001 and dt <= 1.0:
			var last_pos: Vector3 = TypedVariant.as_vector3(st.get("last_pos", pos), pos)
			var v: Vector3 = (pos - last_pos) / dt
			if not s.y_axis_unlocked():
				v.y = 0.0
			var cap: float = s.combat_move_speed() * 1.5
			if v.length() > cap:
				v = v.normalized() * cap
			st["vel"] = v
		## Never snap: the gap between prediction and authority eases out over
		## guest_pos_smooth_s inside guest_present_tick.
		st["err"] = pos - s.global_position
	st["last_pos"] = pos
	st["last_ms"] = now


func _guest_note_hp(s: ShipUnit, hp: Vector3) -> void:
	var st: Dictionary = _guest_state(s)
	st["hp_t"] = hp
	st["hp_left"] = _g_hp_smooth_s


func _guest_note_fn_target(s: ShipUnit, idx: int) -> void:
	if not watch_only_apply:
		return
	var st: Dictionary = _guest_state(s)
	st["fn_iid"] = _iid_at(idx)


## Called every frame by match_root while a guest watches an authority table.
func guest_present_tick(
	delta: float,
	firing_fx: Object = null,
	float_text: Object = null,
	speed_mul: float = 1.0
) -> void:
	if is_host or not watch_only_apply or _g_state.is_empty() or delta <= 0.0:
		return
	var now: int = Time.get_ticks_msec()
	var pos_k: float = 1.0 - exp(-delta / _g_pos_smooth_s)
	var hp_k: float = 1.0 - exp(-delta / _g_hp_smooth_s)
	for iid_v: Variant in _g_state.keys():
		var iid: int = TypedVariant.as_int(iid_v, 0)
		@warning_ignore("unsafe_cast")
		var s: ShipUnit = instance_from_id(iid) as ShipUnit
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			_g_state.erase(iid_v)
			continue
		var st: Dictionary = _g_state[iid_v]
		_guest_tick_motion(s, st, delta, pos_k, now)
		_guest_tick_hp(s, st, delta, hp_k)
		_guest_tick_fire(s, st, delta, speed_mul, firing_fx, float_text)
	## Lance FX may outlive motion state entries; drive from the aim set.
	for lance_iid_v: Variant in _g_lance_iids.keys():
		var lid: int = TypedVariant.as_int(lance_iid_v, 0)
		@warning_ignore("unsafe_cast")
		var ls: ShipUnit = instance_from_id(lid) as ShipUnit
		if ls == null or not is_instance_valid(ls) or ls.is_destroyed:
			_g_lance_iids.erase(lance_iid_v)
			continue
		MixedLance.guest_tick_visual(ls, delta)


func _guest_tick_motion(s: ShipUnit, st: Dictionary, delta: float, pos_k: float, now: int) -> void:
	var vel: Vector3 = TypedVariant.as_vector3(st.get("vel", Vector3.ZERO), Vector3.ZERO)
	var age: float = float(now - TypedVariant.as_int(st.get("last_ms", now), now)) / 1000.0
	if age > _g_extrapolate_max_s and vel.length_squared() > 0.0:
		## Silence for too long: coast down on the hull's own inertia instead of
		## flying off the field.
		vel *= exp(-delta / maxf(0.05, s.combat_inertia_tau_s()))
		if vel.length() < 0.01:
			vel = Vector3.ZERO
		st["vel"] = vel
	var err: Vector3 = TypedVariant.as_vector3(st.get("err", Vector3.ZERO), Vector3.ZERO)
	var take: Vector3 = err * pos_k
	st["err"] = err - take
	var step: Vector3 = vel * delta + take
	if step.length_squared() > 1.0e-10:
		s.global_position += step
	s.move_velocity_wu = vel
	if vel.length_squared() > 0.01:
		if s.y_axis_unlocked():
			s.face_dir_3d(vel)
		else:
			s.face_dir_xz(vel)


func _guest_tick_hp(s: ShipUnit, st: Dictionary, delta: float, hp_k: float) -> void:
	var left: float = TypedVariant.as_float(st.get("hp_left", 0.0), 0.0)
	if left <= 0.0:
		return
	var t: Vector3 = TypedVariant.as_vector3(st.get("hp_t", Vector3.ZERO), Vector3.ZERO)
	s.shield_hp = lerpf(s.shield_hp, t.x, hp_k)
	s.armor_hp = lerpf(s.armor_hp, t.y, hp_k)
	s.structure_hp = lerpf(s.structure_hp, t.z, hp_k)
	var next_left: float = left - delta
	st["hp_left"] = next_left
	if next_left <= 0.0:
		s.shield_hp = t.x
		s.armor_hp = t.y
		s.structure_hp = t.z
	s.refresh_health_bar()


func _guest_tick_fire(
	s: ShipUnit,
	st: Dictionary,
	delta: float,
	speed_mul: float,
	firing_fx: Object,
	float_text: Object
) -> void:
	var fn_iid: int = TypedVariant.as_int(st.get("fn_iid", 0), 0)
	if fn_iid != 0 and firing_fx != null:
		var fn_acc: float = TypedVariant.as_float(st.get("fn_acc", 0.0), 0.0) + delta
		if fn_acc >= GUEST_FN_FX_PERIOD_S:
			fn_acc = 0.0
			_guest_play_function(s, fn_iid, firing_fx)
		st["fn_acc"] = fn_acc
	var tgt: ShipUnit = _guest_lock_target(s)
	if tgt == null:
		st["fire_acc"] = 0.0
		return
	if not s.is_logistic and not s.has_offensive_damage():
		return
	if s.has_cyno_module() or not s.attacks_enabled():
		return
	if s.grid_dist_to(tgt) > s.world_range_cells() + 0.001:
		return
	var acc: float = TypedVariant.as_float(st.get("fire_acc", 0.0), 0.0) + delta * maxf(0.01, speed_mul)
	var period: float = maxf(0.2, s.attack_duration)
	if acc >= period:
		acc = 0.0
		## Lock-driven self-fire keeps the picture alive while packets are missing;
		## the next full snapshot corrects whatever it estimated wrong.
		_guest_fire_once(s, tgt, firing_fx, float_text)
	st["fire_acc"] = acc


func _guest_lock_target(s: ShipUnit) -> ShipUnit:
	var t_v: Variant = s.combat_target
	if t_v == null or not (t_v is ShipUnit):
		return null
	@warning_ignore("unsafe_cast")
	var t: ShipUnit = t_v as ShipUnit
	if not is_instance_valid(t) or t.is_destroyed:
		return null
	return t


func _guest_play_function(s: ShipUnit, fn_iid: int, firing_fx: Object) -> void:
	@warning_ignore("unsafe_cast")
	var t: ShipUnit = instance_from_id(fn_iid) as ShipUnit
	if t == null or not is_instance_valid(t) or t.is_destroyed:
		return
	if not firing_fx.has_method("play_function"):
		return
	var def: Dictionary = FunctionFit.guest_visual_fx(s)
	if def.is_empty():
		return
	firing_fx.call(
		"play_function", s, t,
		str(def.get("kind", "")),
		TypedVariant.as_float(def.get("duration_s", 1.0), 1.0)
	)


## §3.1a — guests estimate the number and paint it; only authority may kill a ship.
func _guest_fire_once(src: ShipUnit, tgt: ShipUnit, firing_fx: Object, float_text: Object) -> void:
	if src.is_logistic:
		var heal: Dictionary = src.heal_dict_scaled()
		var amount: float = _apply_visual_repair(tgt, heal)
		if amount > 0.0 and float_text != null and float_text.has_method("add_heal"):
			float_text.call("add_heal", tgt.global_position, amount, tgt.get_instance_id())
		elif amount > 0.0 and float_text != null and float_text.has_method("spawn"):
			float_text.call("spawn", tgt.global_position, "+%d" % roundi(amount), Color(0.35, 0.95, 0.55))
		if firing_fx != null and firing_fx.has_method("play"):
			firing_fx.call("play", src, tgt, "remote_armor", 0.45)
		return
	if not watch_only_apply:
		## Peers that still run their own CombatResolver only need the FX.
		if firing_fx != null and firing_fx.has_method("play"):
			firing_fx.call("play", src, tgt, str(src.resolve_weapon_fx_kind()), 0.35)
		return
	var dmg: Dictionary = _guest_damage_dict(src, tgt)
	var res: Dictionary = tgt.apply_hit_dict(dmg, false)
	var dealt: float = TypedVariant.as_float(res.get("dealt", 0.0), 0.0)
	if dealt > 0.0 and float_text != null and float_text.has_method("add_damage"):
		float_text.call("add_damage", tgt.global_position, dealt, tgt.get_instance_id())
	elif dealt > 0.0 and float_text != null and float_text.has_method("spawn"):
		float_text.call("spawn", tgt.global_position, "-%d" % roundi(dealt), Color(1.0, 0.45, 0.35))
	if firing_fx != null and firing_fx.has_method("play"):
		firing_fx.call("play", src, tgt, str(src.resolve_weapon_fx_kind()), 0.35)


func _guest_damage_dict(src: ShipUnit, tgt: ShipUnit) -> Dictionary:
	## Deliberately skips FunctionFit transforms: those mutate implant / debuff
	## state that only the authority may own.
	var mul: float = src.star_dph_mul * (1.0 + src.damage_pct_bonus / 100.0)
	if src.is_missile_weapon():
		mul *= src.missile_damage_factor_vs(tgt)
	else:
		## Turret quality is host RNG. Guests use a seed-derived band so every
		## guest paints the same number without drifting far from authority.
		mul *= 0.7 + 0.3 * _g_rnd01(src.get_instance_id(), tgt.get_instance_id())
	return {
		"emp": src.damage_emp * mul,
		"thermal": src.damage_thermal * mul,
		"kinetic": src.damage_kinetic * mul,
		"explosive": src.damage_explosive * mul,
	}


func _g_rnd01(a: int, b: int) -> float:
	var h: int = hash("%d:%d:%d:%d" % [_g_seed, _logic_tick, a, b])
	return float(absi(h) % 65536) / 65535.0


func _apply_visual_repair(s: ShipUnit, heal: Dictionary) -> float:
	var applied: float = 0.0
	var add: float = minf(
		maxf(0.0, s.max_shield - s.shield_hp),
		maxf(0.0, TypedVariant.as_float(heal.get("shield", 0.0), 0.0))
	)
	s.shield_hp += add
	applied += add
	add = minf(
		maxf(0.0, s.max_armor - s.armor_hp),
		maxf(0.0, TypedVariant.as_float(heal.get("armor", 0.0), 0.0))
	)
	s.armor_hp += add
	applied += add
	add = minf(
		maxf(0.0, s.max_structure - s.structure_hp),
		maxf(0.0, TypedVariant.as_float(heal.get("structure", 0.0), 0.0))
	)
	s.structure_hp += add
	applied += add
	if applied > 0.0:
		s.refresh_health_bar()
	return applied


## ────────────────────────────── legacy / local ──────────────────────────────

## Local spectate re-emit (host frame only). Guests take the binary path instead.
func apply_authority(snap: Dictionary) -> void:
	## Reentrancy guard: the emit below feeds spectate handlers that call back in.
	if _applying_authority:
		return
	if TypedVariant.as_bool(snap.get("is_authority", false), false) == false:
		return
	_applying_authority = true
	_last_authority = snap
	_logic_tick = TypedVariant.as_int(snap.get("logic_tick", _logic_tick), _logic_tick)
	authority_snapshot.emit(snap)
	spectate_stream.emit(snap)
	_applying_authority = false


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
