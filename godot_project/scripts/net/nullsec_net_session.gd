extends Node
class_name NullsecNetSession
## ENet LAN lobby — host/join, seat sync, rulesHash gate, LAN beacon ads.

signal seat_sync(seats: Array)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal rejected(reason: String)
signal match_start(payload: Dictionary)
## UI_AND_SHELL §1.2 — bottom load bar phase + 0..1 progress while entering match.
signal match_loading(phase: String, progress: float)
signal join_accepted(seat: int, in_match: bool)
## SEMI_ASYNC_NETPLAY §3.7 — ship table authority.
signal ships_mismatch(host_hash: String)
signal ships_override_applied(mid_match: bool)
## SEMI_ASYNC §3.3.1 A — full snapshot on the wire: binary + zstd.
signal authority_snapshot_bin_received(data: PackedByteArray)
## SEMI_ASYNC §3.3.1 B — light pos/lock/fire·repair, binary, unreliable_ordered.
signal authority_light_bin_received(data: PackedByteArray)
signal battle_report_received(report: Dictionary)
## SEMI_ASYNC §3.1a — host Battle ended; watch peers must force-complete.
signal battle_ended_received(host_result: String, host_seat: int, reason: String)
signal anticheat_notice_received(message: String)
## SEMI_ASYNC §5.3a — rejoin / host migrate.
signal host_migrated(generation: int, new_host_seat: int)
signal match_terminated_host_lost(reason: String)
signal rejoin_accepted(seat: int)
## MULTIPLAYER_PVP §4.2 — scout intel ask/reply (no view switch).
signal scout_intel_asked(from_seat: int, from_nick: String, scout_ship_name: String, reply_peer: int, target_seat: int)
signal scout_intel_received(target_seat: int, target_nick: String, summary: Dictionary)
## Prepare live fleet sync + first-spend clock (SEMI_ASYNC §3.0 / §3.0d).
signal prepare_fleet_snapshot_received(seat: int, ships: Array)
signal prepare_clock_armed_changed(armed: bool)
## SEMI_ASYNC §3.0a — all contestants finished Prepare timer; enter Battle together.
signal enter_battle_released()
signal urge_prepare_received()
signal lobby_notice(message: String)
## SEMI_ASYNC §4.5 — any seat finished this round → remaining battles 4× + wall-clock draw.
signal seat_battle_finished(seat: int)
## All barrier humans reported battle_done — clear conditional wall draw (§4.5).
signal battle_done_all_ready()
## MULTIPLAYER_PVP §7 — combined end-of-match report (settlement rows + §7.1 titles).
signal match_report_received(report: Dictionary)
## SEMI_ASYNC §4.5 — speed vote from a seat (after host validation).
signal speed_vote_received(seat: int, speed: float)
## MULTIPLAYER_PVP §6 — host-authoritative doomsday play cue.
signal doomsday_play_received(attacker_seat: int, loser_seat: int, logic_tick: int)

## Discovery / announce port (SEMI_ASYNC §7.5 LAN). Game listen = BASE_PORT + code.
const BASE_PORT: int = 24567
const DEFAULT_PORT: int = BASE_PORT ## Alias: beacon port; do not create_server here.
const MAX_CLIENTS: int = 19
const SEAT_TOTAL: int = 20
const TITAN_RACE_SPECTATE: String = "spectate"
const TITAN_RACES: Array = ["caldari", "gallente", "minmatar", "amarr"]
const SECURITY_NULLSEC: String = "nullsec"
const SECURITY_LOWSEC: String = "lowsec"

signal security_mode_changed(mode: String)

var is_host: bool = false
var room_code: int = 0 ## 1..9999
## SEMI_ASYNC §7 — unified room: empty password = verbal「公开」; set = verbal「私密」.
var room_password: String = ""
## Guest-visible flag only (handshake never sends the password).
var room_has_password: bool = false
var rules_hash: String = ""
var pending_join_password: String = ""
## Optional global IPv6 written into room share (dual-stack).
var last_known_host_ipv6: String = ""
## Host's ship-table digest, learned at handshake. Mismatch warns but never blocks the join.
var host_ships_hash: String = ""
var seats: Array = [] ## 20 slots
var local_nick: String = ""
var local_seat: int = -1
var match_started: bool = false
var host_player_cap: int = 20
## Room security: nullsec (负安) or lowsec (低安 · 1v1 对战语义). D-EAC-47.
var security_mode: String = SECURITY_NULLSEC
var last_match_payload: Dictionary = {}
## SEMI_ASYNC §5.3a session continuity.
var session_secret: String = ""
var match_id: String = ""
var opening_host_ships: Dictionary = {}
var opening_host_ships_hash: String = ""
var opening_host_platform: String = "pc" ## "pc" / "mobile" at room open
var host_migrate_generation: int = 0
var last_known_host_ip: String = ""
var pending_rejoin_seat: int = -1
var pending_rejoin_secret: String = ""
var _migrating: bool = false
var _ticket_heartbeat_acc: float = 0.0
var _probe_acc: float = 0.0
var _rtt_ui_acc: float = 0.0
var _probe_sent_msec: int = 0
var _peer: ENetMultiplayerPeer = null
var _listen_port: int = 0
var _beacon: LanBeacon = null
## seat_id -> nick while waiting for scout reply
var _pending_scout_nick: Dictionary = {}
## Prepare fleet cache: seat_id -> Array of ship dicts.
var _prepare_fleet_cache: Dictionary = {}
var _fleet_push_log_n: int = -1
var _fleet_push_log_msec: int = 0
## First-prepare spend gate (host authority).
var prepare_clock_armed: bool = true
## R1 first-spend gate open (MATCH_FLOW §2.1) — pulse must not force-arm while true.
var _prepare_spend_gate_open: bool = false
var _prepare_spent_seats: Dictionary = {}
## SEMI_ASYNC §3.0a stage barriers (host authority).
var _battle_done_seats: Dictionary = {}
var _prepare_done_seats: Dictionary = {}
var _battle_done_gate_open: bool = false
var _prepare_done_gate_open: bool = false
## Guest: prepare_done rejected while clock frozen → retry after arm.
var _pending_prepare_done_report: bool = false
## Guest: already RPC'd prepare_done this clock (avoid HOLD spam); cleared on arm.
var _local_prep_done_sent: bool = false
## Host: prep_done arrived before clock armed → flush on arm.
var _early_prep_done_seats: Dictionary = {}
## Seats that finished battle this round — prepare→battle barrier cohort only.
var _sync_cohort: PackedInt32Array = PackedInt32Array()
var _barrier_diag_acc: float = 0.0
## Wall clock while battle_done / prep_done gate open (SEMI_ASYNC §3.0a pulse escape).
var _barrier_open_wall_ms: int = 0
const BARRIER_FORCE_ESCAPE_MS: int = 20000
## §7 end-of-match report collection (host authority; solo/no-peer emits immediately).
var _match_report_gate_open: bool = false
var _match_report_seats: Dictionary = {}
var _match_report_summaries: Dictionary = {}
## Voluntary host transfer (lobby).
var _pending_transfer_seat: int = -1
var _kicked_local: bool = false
var _pending_transfer_gen: int = 0


func _seat_row(seat: int) -> Dictionary:
	if seat < 0 or seat >= seats.size():
		return {}
	var row_v: Variant = seats[seat]
	if row_v is Dictionary:
		return row_v
	return {}


static func port_for_code(code: int) -> int:
	return BASE_PORT + clampi(code, 1, 9999)


static func random_room_password(length: int = 6) -> String:
	var n: int = clampi(length, 4, 8)
	var out: String = ""
	for _i: int in range(n):
		out += str(randi() % 10)
	return out


static func is_player_race(race: String) -> bool:
	return race in TITAN_RACES


static func is_spectate_race(race: String) -> bool:
	return race == TITAN_RACE_SPECTATE


static func detect_host_player_cap() -> int:
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		return 5
	return 20


static func detect_local_platform() -> String:
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		return "mobile"
	return "pc"


static func is_lowsec(mode: String) -> bool:
	return str(mode) == SECURITY_LOWSEC


func effective_player_cap() -> int:
	if is_lowsec(security_mode):
		return 2
	return host_player_cap


func listen_port() -> int:
	return _listen_port if _listen_port > 0 else port_for_code(maxi(room_code, 1))


func _ready() -> void:
	rules_hash = MatchRng.compute_rules_hash()
	_init_empty_seats()
	set_process(true)


func _process(delta: float) -> void:
	_probe_acc += delta
	_rtt_ui_acc += delta
	if multiplayer and multiplayer.has_multiplayer_peer() and _probe_acc >= 1.0:
		_probe_acc = 0.0
		_send_probe()
	## SEMI_ASYNC §3.0a — while stuck on barrier, emit mp.barrier every 2s.
	if is_host and needs_stage_barrier() and (_battle_done_gate_open or _prepare_done_gate_open):
		_barrier_diag_acc += delta
		if _barrier_diag_acc >= 2.0:
			_barrier_diag_acc = 0.0
			var phase: String = "prep_done" if _prepare_done_gate_open else "battle_done"
			_log_barrier_state(phase, _barrier_missing_now(phase))
	if not match_started or _migrating:
		return
	_ticket_heartbeat_acc += delta
	if _ticket_heartbeat_acc < 5.0:
		return
	_ticket_heartbeat_acc = 0.0
	write_rejoin_ticket()


func _init_empty_seats() -> void:
	seats.clear()
	for i: int in range(SEAT_TOTAL):
		seats.append({
			"seat_id": i,
			"occupied": false,
			"nick": "",
			"peer_id": 0,
			"is_ai": false,
			"titan_race": "",
			"ready": false,
			"ghost": false,
			"platform": "",
			"endpoint_ip": "",
			"endpoint_port": 0,
			"rtt_ms": -1,
		})


func host_room(code: int, nick: String, password: String = "") -> Error:
	is_host = true
	room_code = clampi(code, 1, 9999)
	room_password = password.strip_edges()
	room_has_password = not room_password.is_empty()
	local_nick = nick
	host_player_cap = detect_host_player_cap()
	security_mode = SECURITY_NULLSEC
	return _start_host()


## Thin aliases — verbal「公开/私密」= empty / non-empty password (SEMI_ASYNC §7).
func host_public(code: int, nick: String) -> Error:
	return host_room(code, nick, "")


func host_private(code: int, nick: String, password: String = "") -> Error:
	var pw: String = password.strip_edges()
	if pw.is_empty():
		pw = random_room_password(6)
	return host_room(code, nick, pw)


func join(address: String, port: int, nick: String, expect_hash: String = "", password: String = "") -> Error:
	## Preserve rejoin credentials across close() (SEMI_ASYNC §5.3a).
	var keep_seat: int = pending_rejoin_seat
	var keep_secret: String = pending_rejoin_secret
	var keep_session: String = session_secret
	var keep_mid: String = match_id
	var keep_plat: String = opening_host_platform
	var keep_ships_hash: String = opening_host_ships_hash
	var keep_ships: Dictionary = opening_host_ships.duplicate(true)
	var keep_gen: int = host_migrate_generation
	var keep_sec: String = security_mode
	close()
	pending_rejoin_seat = keep_seat
	pending_rejoin_secret = keep_secret
	session_secret = keep_session
	match_id = keep_mid
	opening_host_platform = keep_plat
	opening_host_ships_hash = keep_ships_hash
	opening_host_ships = keep_ships
	host_migrate_generation = keep_gen
	security_mode = keep_sec
	is_host = false
	local_nick = nick
	local_seat = -1
	match_started = false
	last_match_payload = {}
	host_ships_hash = ""
	pending_join_password = password.strip_edges()
	room_password = pending_join_password
	room_has_password = not pending_join_password.is_empty()
	_listen_port = port
	last_known_host_ip = address
	if expect_hash != "" and expect_hash != rules_hash:
		rejected.emit("版本不符 · 房间主持 %s · 本机 %s" % [expect_hash, rules_hash])
		return ERR_INVALID_PARAMETER
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return err
	_enable_enet_range_compress()
	multiplayer.multiplayer_peer = _peer
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


func _start_host() -> Error:
	var keep_code: int = room_code
	var keep_pw: String = room_password
	var keep_has_pw: bool = room_has_password
	var keep_nick: String = local_nick
	var keep_cap: int = host_player_cap
	var keep_sec: String = security_mode
	close()
	room_code = keep_code
	room_password = keep_pw
	room_has_password = keep_has_pw
	local_nick = keep_nick
	host_player_cap = keep_cap
	security_mode = keep_sec
	is_host = true
	match_started = false
	last_match_payload = {}
	_ensure_session_secret()
	opening_host_platform = detect_local_platform()
	last_known_host_ip = _best_local_ip()
	last_known_host_ipv6 = _best_global_ipv6()
	_listen_port = port_for_code(room_code)
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_server(_listen_port, MAX_CLIENTS)
	if err != OK:
		_peer = null
		_listen_port = 0
		return err
	_enable_enet_range_compress()
	multiplayer.multiplayer_peer = _peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_occupy_seat(0, local_nick, multiplayer.get_unique_id(), false)
	var host_row: Dictionary = _seat_row(0)
	host_row["platform"] = opening_host_platform
	host_row["endpoint_ip"] = last_known_host_ip
	host_row["endpoint_port"] = _listen_port
	local_seat = 0
	_start_beacon()
	_broadcast_seats()
	return OK


func _start_beacon() -> void:
	if _beacon and is_instance_valid(_beacon):
		_beacon.stop()
		_beacon.queue_free()
	_beacon = LanBeacon.new()
	_beacon.name = "LanBeacon"
	add_child(_beacon)
	_beacon.start_for_host(self)


func persist_across_scenes() -> void:
	## Keep ENet + beacon alive when leaving main menu for match.
	if GameSession == null:
		return
	if get_parent() == GameSession:
		return
	reparent(GameSession)


func _on_peer_connected(id: int) -> void:
	peer_joined.emit(id)
	rpc_id(
		id,
		"rpc_handshake",
		rules_hash,
		room_code,
		not room_password.is_empty(),
		"",
		host_player_cap,
		match_started,
		_authority_ships_hash(),
		security_mode,
		session_secret,
		match_id,
		opening_host_platform,
		host_migrate_generation
	)


func _on_peer_disconnected(id: int) -> void:
	peer_left.emit(id)
	for i: int in range(seats.size()):
		if TypedVariant.as_int(_seat_row(i).get("peer_id", 0), 0) == id:
			if match_started and is_player_race(str(_seat_row(i).get("titan_race", ""))):
				mark_seat_ghost(i)
			else:
				_seat_row(i)["occupied"] = false
				_seat_row(i)["nick"] = ""
				_seat_row(i)["peer_id"] = 0
				_seat_row(i)["ready"] = false
				_seat_row(i)["is_ai"] = false
				_seat_row(i)["titan_race"] = ""
				_seat_row(i)["ghost"] = false
	if not match_started:
		_sync_lobby_ready_gates()
	_broadcast_seats()
	if not match_started:
		_try_start()


func _on_connected_to_server() -> void:
	rpc_id(
		1,
		"rpc_request_join",
		local_nick,
		rules_hash,
		detect_local_platform(),
		pending_rejoin_seat,
		pending_rejoin_secret,
		pending_join_password
	)


func _on_server_disconnected() -> void:
	if _kicked_local:
		_kicked_local = false
		rejected.emit("kicked")
		return
	if _pending_transfer_seat >= 0:
		var hip: String = last_known_host_ip
		var hport: int = port_for_code(room_code)
		var keep_seat: int = local_seat
		_teardown_peer_only()
		pending_rejoin_seat = keep_seat
		pending_rejoin_secret = session_secret
		var tree: SceneTree = get_tree()
		if tree and hip != "":
			tree.create_timer(0.35).timeout.connect(func() -> void:
				join(hip, hport, local_nick, rules_hash)
				_pending_transfer_seat = -1
			)
		else:
			_pending_transfer_seat = -1
			rejected.emit("server disconnected")
		return
	if match_started:
		_begin_host_migration()
	else:
		rejected.emit("server disconnected")


@rpc("authority", "reliable")
func rpc_you_were_kicked() -> void:
	## Host eject — must not take host-migration path (MULTIPLAYER_MATCH_FLOW §2.1a).
	_kicked_local = true
	rejected.emit("kicked")
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null


@rpc("any_peer", "reliable")
func rpc_handshake(
	server_hash: String,
	code: int,
	has_password: bool = false,
	_compat_unused: String = "",
	player_cap: int = 20,
	in_match: bool = false,
	ships_hash: String = "",
	sec_mode: String = SECURITY_NULLSEC,
	secret: String = "",
	mid: String = "",
	opener_plat: String = "pc",
	migrate_gen: int = 0
) -> void:
	if server_hash != rules_hash:
		rejected.emit("版本不符 · 房间主持 %s · 本机 %s" % [server_hash, rules_hash])
		multiplayer.multiplayer_peer = null
		return
	room_code = code
	room_has_password = has_password
	## Do not accept password over handshake (only via join / room share).
	host_player_cap = clampi(player_cap, 2, SEAT_TOTAL)
	match_started = in_match
	host_ships_hash = ships_hash
	if secret != "":
		session_secret = secret
	if mid != "":
		match_id = mid
	if opener_plat != "":
		opening_host_platform = opener_plat
	host_migrate_generation = migrate_gen
	_apply_security_mode(sec_mode, false)


@rpc("any_peer", "reliable")
func rpc_request_join(
	nick: String,
	client_hash: String,
	platform: String = "pc",
	rejoin_seat: int = -1,
	secret: String = "",
	password: String = ""
) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if client_hash != rules_hash:
		rpc_id(sender, "rpc_join_rejected", "版本不符 · 房间主持 %s · 本机 %s" % [rules_hash, client_hash])
		return
	## Ghost reclaim (续局票) — seat_id + session_secret.
	if (
		match_started
		and secret != ""
		and secret == session_secret
		and rejoin_seat >= 0
		and _try_reclaim_ghost(rejoin_seat, nick, sender, platform)
	):
		rpc_id(sender, "rpc_rejoin_ok", rejoin_seat)
		rpc_id(sender, "rpc_ships_table", _authority_ships_table(), true)
		var reclaim_payload: Dictionary = _payload_for_spectate_join()
		reclaim_payload["mid_join_spectate"] = false
		reclaim_payload["rejoin"] = true
		if not reclaim_payload.is_empty():
			rpc_id(sender, "rpc_match_start", reclaim_payload)
		_broadcast_seats()
		return
	if not room_password.is_empty() and str(password) != room_password:
		rpc_id(sender, "rpc_join_rejected", "need_password")
		return
	var seat: int = _first_free_seat()
	if seat < 0:
		rpc_id(sender, "rpc_join_rejected", "room full")
		return
	_occupy_seat(seat, nick, sender, false)
	var join_row: Dictionary = _seat_row(seat)
	join_row["platform"] = platform if platform != "" else detect_local_platform()
	_capture_peer_endpoint(seat, sender)
	if match_started:
		join_row["titan_race"] = TITAN_RACE_SPECTATE
		join_row["ready"] = true
		rpc_id(sender, "rpc_join_accepted", seat, true)
		_broadcast_seats()
		## Mid-join watcher needs the host table before it simulates anything.
		rpc_id(sender, "rpc_ships_table", _authority_ships_table(), true)
		var payload: Dictionary = _payload_for_spectate_join()
		if not payload.is_empty():
			rpc_id(sender, "rpc_match_start", payload)
		return
	rpc_id(sender, "rpc_join_accepted", seat, false)
	_broadcast_seats()


@rpc("authority", "reliable")
func rpc_join_rejected(reason: String) -> void:
	var r: String = str(reason)
	if r == "need_password":
		r = "需要房间密码"
	elif r == "room full":
		r = "房间已满"
	rejected.emit(r)


@rpc("authority", "reliable")
func rpc_join_accepted(seat: int, in_match: bool = false) -> void:
	local_seat = seat
	match_started = in_match
	join_accepted.emit(seat, in_match)
	if host_ships_hash != "" and host_ships_hash != DataStore.ships_table_hash():
		ships_mismatch.emit(host_ships_hash)


@rpc("authority", "reliable")
func rpc_rejoin_ok(seat: int) -> void:
	local_seat = seat
	match_started = true
	pending_rejoin_seat = -1
	pending_rejoin_secret = ""
	_migrating = false
	rejoin_accepted.emit(seat)
	join_accepted.emit(seat, true)
	write_rejoin_ticket()


@rpc("authority", "reliable")
func rpc_seats(payload: Array) -> void:
	seats = payload
	seat_sync.emit(seats)


func _broadcast_seats() -> void:
	seat_sync.emit(seats)
	if is_host:
		rpc("rpc_seats", seats)


func _first_free_seat() -> int:
	for i: int in range(mini(SEAT_TOTAL, seats.size())):
		if not TypedVariant.as_bool(_seat_row(i).get("occupied", false), false):
			return i
	return -1


func occupied_count() -> int:
	var n: int = 0
	for s_v: Variant in seats:
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = s_v
		if TypedVariant.as_bool(s.get("occupied", false), false):
			n += 1
	return n


func player_count() -> int:
	var n: int = 0
	for s_v: Variant in seats:
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = s_v
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		if is_player_race(str(s.get("titan_race", ""))):
			n += 1
	return n


func local_is_spectator() -> bool:
	if local_seat < 0 or local_seat >= seats.size():
		return false
	return is_spectate_race(str(_seat_row(local_seat).get("titan_race", "")))


func _occupy_seat(seat: int, nick: String, peer_id: int, is_ai: bool) -> void:
	var row: Dictionary = _seat_row(seat)
	if row.is_empty():
		return
	row["occupied"] = true
	row["nick"] = NickCodec.sanitize(nick) if is_ai else NickCodec.decode_from_wire(NickCodec.encode_for_wire(nick))
	row["peer_id"] = peer_id
	row["is_ai"] = is_ai
	row["ready"] = false
	row["titan_race"] = ""
	row["ghost"] = false
	row["rtt_ms"] = 0 if (multiplayer and peer_id == multiplayer.get_unique_id()) else (-1 if not is_ai else -1)
	if not row.has("platform"):
		row["platform"] = ""
	if not row.has("endpoint_ip"):
		row["endpoint_ip"] = ""
	if not row.has("endpoint_port"):
		row["endpoint_port"] = 0
	NetSessionDebug.log_event(
		"net.seat.occupy",
		"seat=%d nick=%s peer=%d ai=%s" % [seat, NickCodec.display_short(str(row["nick"])), peer_id, is_ai]
	)


func add_ai_player(nick: String = "") -> bool:
	if not is_host or match_started:
		return false
	## Lowsec: may still add seats; ready gate blocks start while >2 titans selected.
	if not is_lowsec(security_mode) and player_count() >= host_player_cap:
		return false
	var seat: int = _first_free_seat()
	if seat < 0:
		return false
	var use_nick: String = NickCodec.sanitize(nick)
	if use_nick == "":
		use_nick = EveStyleNameGenerator.roll()
	_occupy_seat(seat, use_nick, 0, true)
	_broadcast_seats()
	return true


func set_security_mode(mode: String) -> void:
	if not is_host or match_started:
		return
	var next: String = SECURITY_LOWSEC if is_lowsec(mode) else SECURITY_NULLSEC
	if next == security_mode:
		return
	_apply_security_mode(next, true)
	rpc("rpc_security_mode", security_mode)
	_broadcast_seats()
	_try_start()


func _apply_security_mode(mode: String, enforce_ready_gate: bool) -> void:
	security_mode = SECURITY_LOWSEC if is_lowsec(mode) else SECURITY_NULLSEC
	if enforce_ready_gate:
		_sync_lobby_ready_gates()
	security_mode_changed.emit(security_mode)


## Lowsec: >2 titan picks → strip every contender's ready (MULTIPLAYER_PVP §1).
func _clear_ready_when_lowsec_over_cap() -> bool:
	if not is_lowsec(security_mode):
		return false
	if player_count() <= 2:
		return false
	var changed: bool = false
	for i: int in range(seats.size()):
		if not TypedVariant.as_bool(_seat_row(i).get("occupied", false), false):
			continue
		if not is_player_race(str(_seat_row(i).get("titan_race", ""))):
			continue
		if TypedVariant.as_bool(_seat_row(i).get("ready", false), false):
			_seat_row(i)["ready"] = false
			changed = true
	return changed


func lowsec_ready_blocked() -> bool:
	return is_lowsec(security_mode) and player_count() > 2


## AI seats with a titan auto-ready whenever the lobby gate allows (MATCH_FLOW §2 · 3b).
func _refresh_ai_auto_ready() -> bool:
	if match_started:
		return false
	if lowsec_ready_blocked():
		return false
	var changed: bool = false
	for i: int in range(seats.size()):
		if not TypedVariant.as_bool(_seat_row(i).get("occupied", false), false):
			continue
		if not TypedVariant.as_bool(_seat_row(i).get("is_ai", false), false):
			continue
		if TypedVariant.as_bool(_seat_row(i).get("ghost", false), false):
			continue
		if not is_player_race(str(_seat_row(i).get("titan_race", ""))):
			continue
		if TypedVariant.as_bool(_seat_row(i).get("ready", false), false):
			continue
		_seat_row(i)["ready"] = true
		changed = true
	return changed


func _sync_lobby_ready_gates() -> void:
	_clear_ready_when_lowsec_over_cap()
	_refresh_ai_auto_ready()


@rpc("authority", "reliable")
func rpc_security_mode(mode: String) -> void:
	if is_host:
		return
	_apply_security_mode(mode, false)


func kick_seat(seat: int) -> void:
	if not is_host:
		return
	if seat < 0 or seat >= seats.size():
		return
	var peer_id: int = TypedVariant.as_int(_seat_row(seat).get("peer_id", 0), 0)
	_seat_row(seat)["occupied"] = false
	_seat_row(seat)["nick"] = ""
	_seat_row(seat)["peer_id"] = 0
	_seat_row(seat)["is_ai"] = false
	_seat_row(seat)["ready"] = false
	_seat_row(seat)["titan_race"] = ""
	_seat_row(seat)["ghost"] = false
	if peer_id > 0 and multiplayer.has_multiplayer_peer() and _peer:
		rpc_id(peer_id, "rpc_you_were_kicked")
		_peer.disconnect_peer(peer_id)
	_sync_lobby_ready_gates()
	_broadcast_seats()
	_try_start()


func mark_seat_ghost(seat: int) -> void:
	if seat < 0 or seat >= seats.size():
		return
	if not TypedVariant.as_bool(_seat_row(seat).get("occupied", false), false):
		return
	_seat_row(seat)["ghost"] = true
	_seat_row(seat)["ready"] = false
	_seat_row(seat)["peer_id"] = 0
	_broadcast_seats()


func request_mark_local_ghost() -> void:
	if local_seat < 0:
		return
	if is_host:
		mark_seat_ghost(local_seat)
		return
	rpc_id(1, "rpc_mark_ghost", local_seat)


@rpc("any_peer", "reliable")
func rpc_mark_ghost(seat: int) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if seat < 0 or seat >= seats.size():
		return
	if TypedVariant.as_int(_seat_row(seat).get("peer_id", 0), 0) != sender:
		return
	mark_seat_ghost(seat)


func clear_ghosts_after_settlement() -> void:
	for i: int in range(seats.size()):
		if TypedVariant.as_bool(_seat_row(i).get("ghost", false), false):
			_seat_row(i)["occupied"] = false
			_seat_row(i)["nick"] = ""
			_seat_row(i)["peer_id"] = 0
			_seat_row(i)["is_ai"] = false
			_seat_row(i)["ready"] = false
			_seat_row(i)["titan_race"] = ""
			_seat_row(i)["ghost"] = false
	_broadcast_seats()


func set_local_titan(race: String) -> void:
	if local_seat < 0:
		return
	set_seat_titan(local_seat, race)


func set_seat_titan(seat: int, race: String) -> void:
	if seat < 0 or seat >= seats.size():
		return
	if not TypedVariant.as_bool(_seat_row(seat).get("occupied", false), false):
		return
	if match_started:
		return
	var is_ai: bool = TypedVariant.as_bool(_seat_row(seat).get("is_ai", false), false)
	if is_host:
		if seat != local_seat and not is_ai:
			return
		if not _can_apply_titan(seat, race):
			return
		_apply_titan(seat, race)
		_broadcast_seats()
		_try_start()
		return
	if seat != local_seat:
		return
	rpc_id(1, "rpc_set_titan", seat, race)


func _can_apply_titan(seat: int, race: String) -> bool:
	if race == "" or is_spectate_race(race):
		return true
	if not is_player_race(race):
		return false
	var cur: String = str(_seat_row(seat).get("titan_race", ""))
	if is_player_race(cur):
		return true ## switching titan keeps same player slot
	## Lowsec: allow >2 titan picks; ready is cleared/blocked until back to 2.
	if is_lowsec(security_mode):
		return true
	return player_count() < host_player_cap


func _apply_titan(seat: int, race: String) -> void:
	_seat_row(seat)["titan_race"] = race
	if race == "":
		_seat_row(seat)["ready"] = false
	elif is_spectate_race(race):
		_seat_row(seat)["ready"] = true
	elif TypedVariant.as_bool(_seat_row(seat).get("is_ai", false), false) and is_player_race(race):
		## Immediate attempt; `_sync_lobby_ready_gates` re-tries when the gate opens later.
		_seat_row(seat)["ready"] = not lowsec_ready_blocked()
	elif not is_player_race(race):
		_seat_row(seat)["ready"] = false
	_sync_lobby_ready_gates()


func set_local_ready(is_ready: bool) -> void:
	if local_seat < 0:
		return
	var race: String = str(_seat_row(local_seat).get("titan_race", ""))
	if is_ready and not is_player_race(race):
		return
	if is_ready and lowsec_ready_blocked():
		return
	_seat_row(local_seat)["ready"] = is_ready
	if is_host:
		_sync_lobby_ready_gates()
		_broadcast_seats()
		_try_start()
	else:
		rpc_id(1, "rpc_set_ready", local_seat, is_ready)


@rpc("any_peer", "reliable")
func rpc_set_titan(seat: int, race: String) -> void:
	if not is_host:
		return
	if seat < 0 or seat >= seats.size():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if TypedVariant.as_int(_seat_row(seat).get("peer_id", 0), 0) != sender:
		return
	if TypedVariant.as_bool(_seat_row(seat).get("is_ai", false), false):
		return
	if not _can_apply_titan(seat, race):
		_broadcast_seats() ## bounce UI
		return
	_apply_titan(seat, race)
	_broadcast_seats()
	_try_start()


@rpc("any_peer", "reliable")
func rpc_set_ready(seat: int, is_ready: bool) -> void:
	if not is_host:
		return
	if seat < 0 or seat >= seats.size():
		return
	if is_ready and not is_player_race(str(_seat_row(seat).get("titan_race", ""))):
		return
	if is_ready and lowsec_ready_blocked():
		_sync_lobby_ready_gates()
		_broadcast_seats()
		return
	_seat_row(seat)["ready"] = is_ready
	_sync_lobby_ready_gates()
	_broadcast_seats()
	_try_start()


func _try_start() -> void:
	if match_started:
		return
	var players: Array = []
	for s_v: Variant in seats:
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = s_v
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		var race: String = str(s.get("titan_race", ""))
		if is_spectate_race(race):
			continue
		players.append(s)
	if players.size() < 2:
		return
	if is_lowsec(security_mode) and players.size() != 2:
		return
	for s_v: Variant in players:
		if not (s_v is Dictionary):
			return
		var s: Dictionary = s_v
		if not is_player_race(str(s.get("titan_race", ""))):
			return
		if not TypedVariant.as_bool(s.get("ready", false), false):
			return
	var seed_v: int = int(Time.get_unix_time_from_system()) ^ hash(room_code)
	var all_occupied: Array = []
	for s_v: Variant in seats:
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = s_v
		if TypedVariant.as_bool(s.get("occupied", false), false):
			all_occupied.append(s)
	_ensure_session_secret()
	match_loading.emit("正在从房主拉取全舰船与全游戏数据", 0.08)
	_freeze_opening_host_ships(DataStore.export_ships_table())
	if match_id == "":
		match_id = "%d-%s" % [seed_v, session_secret.substr(0, mini(8, session_secret.length()))]
	var payload: Dictionary = {
		"match_seed": seed_v,
		"rules_hash": rules_hash,
		"seats": all_occupied,
		"security_mode": security_mode,
		"host_seat": local_seat if local_seat >= 0 else 0,
		"session_secret": session_secret,
		"match_id": match_id,
		"opening_host_platform": opening_host_platform,
		"opening_host_ships_hash": opening_host_ships_hash,
		"host_migrate_generation": host_migrate_generation,
	}
	match_started = true
	last_match_payload = payload.duplicate(true)
	## Opening pack (ships + seeds) with hash ACK path for lowsec confirm-chain logging.
	var seeds_payload: Dictionary = {
		"match_seed": seed_v,
		"rules_hash": rules_hash,
		"match_id": match_id,
		"session_secret": session_secret,
		"security_mode": security_mode,
	}
	var pack: Dictionary = OpeningPack.build(_authority_ships_table(), seeds_payload)
	NetSessionDebug.log_pack("opening", {
		"ships_hash": str(pack.get("ships_hash", "")),
		"pack_hash": str(pack.get("pack_hash", "")),
		"rules_hash": rules_hash,
		"bytes": TypedVariant.as_int(pack.get("byte_len", 0), 0),
		"security_mode": security_mode,
	})
	if is_lowsec(security_mode) and multiplayer.has_multiplayer_peer():
		rpc("rpc_opening_pack", pack.get("bytes", PackedByteArray()), str(pack.get("pack_hash", "")))
	## Ship table travels only on match entry, ahead of the start payload (§3.7 / 1A freeze).
	rpc("rpc_ships_table", _authority_ships_table(), false)
	match_loading.emit("正在通知各方开局", 0.18)
	rpc("rpc_match_start", payload)
	write_rejoin_ticket()
	match_loading.emit("正在进入对局场景", 0.25)
	match_start.emit(payload)
	NetSessionDebug.log_event("net.match_start", "id=%s seed=%d mode=%s" % [match_id, seed_v, security_mode])


## Lobby-stage edit: guests only need the new digest, the table still waits for match entry.
func broadcast_ships_hash() -> void:
	if not is_host or not multiplayer.has_multiplayer_peer():
		return
	rpc("rpc_ships_hash", DataStore.ships_table_hash())


@rpc("authority", "reliable")
func rpc_ships_hash(hash_v: String) -> void:
	if is_host:
		return
	host_ships_hash = hash_v
	if hash_v != "" and hash_v != DataStore.ships_table_hash():
		ships_mismatch.emit(hash_v)


## Host edited the roster mid-match — push the whole table again right away.
func broadcast_ships_table() -> void:
	if not is_host or not multiplayer.has_multiplayer_peer():
		return
	_freeze_opening_host_ships(DataStore.export_ships_table())
	rpc("rpc_ships_table", opening_host_ships.duplicate(true), true)


@rpc("authority", "reliable")
func rpc_ships_table(table: Dictionary, mid_match: bool = false) -> void:
	if is_host:
		return
	if not mid_match:
		## SEMI_ASYNC §3.7 — keep overlay on this copy until match_start advances phase.
		match_loading.emit("正在从房主拉取全舰船与全游戏数据", 0.12)
	_freeze_opening_host_ships(table)
	if DataStore.apply_host_ships_override(table):
		ships_override_applied.emit(mid_match)
	if not mid_match:
		## Hold the pull copy briefly so「进入对局场景」不会瞬间盖住。
		match_loading.emit("正在从房主拉取全舰船与全游戏数据", 0.16)


func store_match_assignments(assignments: Dictionary) -> void:
	if last_match_payload.is_empty():
		last_match_payload = {}
	last_match_payload["assignments"] = assignments.duplicate(true)


func _payload_for_spectate_join() -> Dictionary:
	var p: Dictionary = last_match_payload.duplicate(true)
	if p.is_empty():
		p = {"match_seed": int(Time.get_unix_time_from_system()), "rules_hash": rules_hash}
	var all_occupied: Array = []
	for s_v: Variant in seats:
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = s_v
		if TypedVariant.as_bool(s.get("occupied", false), false):
			all_occupied.append(s)
	p["seats"] = all_occupied
	p["mid_join_spectate"] = true
	return p


@rpc("authority", "reliable")
func rpc_match_start(payload: Dictionary) -> void:
	match_started = true
	last_match_payload = payload.duplicate(true)
	session_secret = str(payload.get("session_secret", session_secret))
	match_id = str(payload.get("match_id", match_id))
	opening_host_platform = str(payload.get("opening_host_platform", opening_host_platform))
	opening_host_ships_hash = str(payload.get("opening_host_ships_hash", opening_host_ships_hash))
	host_migrate_generation = TypedVariant.as_int(payload.get("host_migrate_generation", host_migrate_generation), host_migrate_generation)
	write_rejoin_ticket()
	## Ships RPC is ordered before this; if table missing, keep pull copy (SEMI_ASYNC §3.7).
	if opening_host_ships.is_empty():
		match_loading.emit("正在从房主拉取全舰船与全游戏数据", 0.18)
	else:
		match_loading.emit("正在进入对局场景", 0.25)
	match_start.emit(payload)


## SEMI_ASYNC §3.3.1 A — full snapshot, binary + zstd, reliable on the default channel.
func broadcast_authority_snapshot_bin(data: PackedByteArray) -> void:
	if not is_host or not multiplayer.has_multiplayer_peer():
		return
	if data.is_empty():
		return
	rpc("rpc_authority_snapshot_bin", data)


@rpc("authority", "reliable")
func rpc_authority_snapshot_bin(data: PackedByteArray) -> void:
	if is_host:
		return
	authority_snapshot_bin_received.emit(data)


## §3.3.1 B — light packet rides its own unreliable_ordered channel so a stalled
## reliable queue never holds up position updates.
func broadcast_authority_light_bin(data: PackedByteArray) -> void:
	if not is_host or not multiplayer.has_multiplayer_peer():
		return
	if data.is_empty():
		return
	rpc("rpc_authority_light_bin", data)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func rpc_authority_light_bin(data: PackedByteArray) -> void:
	if is_host:
		return
	authority_light_bin_received.emit(data)


func broadcast_battle_report(report: Dictionary) -> void:
	if not is_host or not multiplayer.has_multiplayer_peer():
		return
	rpc("rpc_battle_report", report)


@rpc("authority", "reliable")
func rpc_battle_report(report: Dictionary) -> void:
	if is_host:
		return
	battle_report_received.emit(report)


## SEMI_ASYNC §3.1a — authority seat finished Battle; watch peers end from this.
func broadcast_battle_ended(host_result: String, host_seat: int, reason: String = "wipe") -> void:
	if not is_host or not multiplayer.has_multiplayer_peer():
		return
	rpc("rpc_battle_ended", str(host_result), host_seat, str(reason))


@rpc("authority", "reliable")
func rpc_battle_ended(host_result: String, host_seat: int, reason: String) -> void:
	if is_host:
		return
	battle_ended_received.emit(str(host_result), host_seat, str(reason))


func broadcast_anticheat_notice(message: String) -> void:
	## Notify-only (D-EAC-38): never kick / ban.
	if not multiplayer.has_multiplayer_peer():
		anticheat_notice_received.emit(str(message))
		return
	if is_host:
		anticheat_notice_received.emit(str(message))
		rpc("rpc_anticheat_notice", str(message))
	else:
		rpc_id(1, "rpc_anticheat_notice_to_host", str(message))


@rpc("any_peer", "reliable")
func rpc_anticheat_notice_to_host(message: String) -> void:
	if not is_host:
		return
	broadcast_anticheat_notice(str(message))


@rpc("authority", "reliable")
func rpc_anticheat_notice(message: String) -> void:
	if is_host:
		return
	anticheat_notice_received.emit(str(message))


func make_invite_blob() -> String:
	var ip: String = last_known_host_ip if last_known_host_ip != "" else _best_local_ip()
	if ip == "" or ip == "0.0.0.0":
		ip = "127.0.0.1"
	var ipv6: String = last_known_host_ipv6 if last_known_host_ipv6 != "" else _best_global_ipv6()
	return InviteBlobHelper.encode(ip, listen_port(), "%04d" % room_code, rules_hash, {
		"password": room_password,
		"ipv6": ipv6,
		"security_mode": security_mode,
	})


func clear_rejoin_ticket() -> void:
	NullsecRejoinTicket.clear()


func write_rejoin_ticket() -> void:
	NullsecRejoinTicket.write_from_session(self)


func _ensure_session_secret() -> void:
	if session_secret != "":
		return
	var c: Crypto = Crypto.new()
	session_secret = Marshalls.raw_to_base64(c.generate_random_bytes(16))


func _best_local_ip() -> String:
	## SEMI_ASYNC §7.2 — prefer home LAN over Hyper-V / APIPA.
	var best: String = ""
	var best_score: int = -1
	for a: String in IP.get_local_addresses():
		var s: String = str(a)
		var score: int = _score_local_ipv4(s)
		if score < 0:
			continue
		if score > best_score:
			best_score = score
			best = s
	return best if best != "" else "127.0.0.1"


func _best_global_ipv6() -> String:
	## SEMI_ASYNC §7.2 — global unicast only; skip link-local / ULA / loopback.
	for a: String in IP.get_local_addresses():
		var s: String = str(a).strip_edges()
		if s.find(":") < 0:
			continue
		var low: String = s.to_lower()
		if low == "::1" or low.begins_with("fe80"):
			continue
		if low.begins_with("fc") or low.begins_with("fd"):
			continue
		## Drop zone id (fe80::1%eth0 style) if any slipped through.
		if s.find("%") >= 0:
			continue
		return s
	return ""


func _score_local_ipv4(ip: String) -> int:
	if ip == "" or ip.find(":") >= 0 or ip.begins_with("127."):
		return -1
	if ip.begins_with("169.254."):
		return -1
	var parts: PackedStringArray = ip.split(".")
	if parts.size() != 4:
		return -1
	var a: int = int(parts[0])
	var b: int = int(parts[1])
	var c: int = int(parts[2])
	var d: int = int(parts[3])
	## Android emulator AndroidWifi peers 10.0.2.16–31 — reachable across AVDs (SEMI_ASYNC §7).
	## eth0 10.0.2.15 is isolated NAT per AVD — never advertise it as the join endpoint.
	if a == 10 and b == 0 and c == 2:
		if d == 15:
			return -1
		if d >= 16 and d <= 31:
			return 95
	## Legacy -shared-net-id backplane 10.1.2.N
	if a == 10 and b == 1 and c == 2 and d >= 1 and d <= 32:
		return 90
	if a == 192 and b == 168:
		return 100
	if a == 10:
		return 50
	if a == 172 and b >= 16 and b <= 31:
		return 10
	return 0


func _freeze_opening_host_ships(table: Dictionary) -> void:
	if table.is_empty():
		return
	opening_host_ships = table.duplicate(true)
	opening_host_ships_hash = DataStore.table_hash(opening_host_ships)


func _authority_ships_table() -> Dictionary:
	if not opening_host_ships.is_empty():
		return opening_host_ships.duplicate(true)
	return DataStore.export_ships_table()


func _authority_ships_hash() -> String:
	if opening_host_ships_hash != "":
		return opening_host_ships_hash
	if not opening_host_ships.is_empty():
		return DataStore.table_hash(opening_host_ships)
	return DataStore.ships_table_hash()


func _capture_peer_endpoint(seat: int, peer_id: int) -> void:
	if seat < 0 or seat >= seats.size() or _peer == null or peer_id <= 0:
		return
	var ep: ENetPacketPeer = _peer.get_peer(peer_id) as ENetPacketPeer
	if ep == null:
		return
	var row: Dictionary = _seat_row(seat)
	if row.is_empty():
		return
	row["endpoint_ip"] = str(ep.get_remote_address())
	row["endpoint_port"] = int(ep.get_remote_port())


func _try_reclaim_ghost(seat: int, nick: String, peer_id: int, platform: String) -> bool:
	if seat < 0 or seat >= seats.size():
		return false
	var row: Dictionary = _seat_row(seat)
	if row.is_empty():
		return false
	if not TypedVariant.as_bool(row.get("occupied", false), false):
		return false
	if not TypedVariant.as_bool(row.get("ghost", false), false):
		return false
	row["ghost"] = false
	row["peer_id"] = peer_id
	row["nick"] = nick
	row["platform"] = platform if platform != "" else str(row.get("platform", ""))
	row["ready"] = is_player_race(str(row.get("titan_race", "")))
	_capture_peer_endpoint(seat, peer_id)
	return true


static func elect_new_host_seat(seat_rows: Array, opener_plat: String, match_seed: int, generation: int) -> int:
	## Deterministic election. Returns -1 → terminate (PC opener, no PC left).
	var candidates: Array = []
	for s_v: Variant in seat_rows:
		if not (s_v is Dictionary):
			continue
		var row: Dictionary = s_v
		if not TypedVariant.as_bool(row.get("occupied", false), false):
			continue
		if TypedVariant.as_bool(row.get("ghost", false), false):
			continue
		if TypedVariant.as_bool(row.get("is_ai", false), false):
			continue
		if not is_player_race(str(row.get("titan_race", ""))):
			continue
		candidates.append(TypedVariant.as_int(row.get("seat_id", -1), -1))
	candidates = candidates.filter(func(x: Variant) -> bool: return TypedVariant.as_int(x, -1) >= 0)
	if candidates.is_empty():
		return -1
	var same: Array = []
	for sid_v: Variant in candidates:
		var sid: int = TypedVariant.as_int(sid_v, -1)
		var plat: String = ""
		for row_v: Variant in seat_rows:
			if not (row_v is Dictionary):
				continue
			var s_row: Dictionary = row_v
			if TypedVariant.as_int(s_row.get("seat_id", -2), -2) == sid:
				plat = str(s_row.get("platform", ""))
				break
		if plat == str(opener_plat):
			same.append(sid)
	if not same.is_empty():
		candidates = same
	elif str(opener_plat) == "pc":
		return -1
	candidates.sort()
	var parts: PackedStringArray = PackedStringArray()
	for sid_v: Variant in candidates:
		parts.append(str(TypedVariant.as_int(sid_v, -1)))
	var key: String = "%d|host_migrate|%d|%s" % [int(match_seed), int(generation), ",".join(parts)]
	var h: int = absi(hash(key))
	return TypedVariant.as_int(candidates[h % candidates.size()], -1)


func _begin_host_migration() -> void:
	if _migrating:
		return
	_migrating = true
	var old_host: int = TypedVariant.as_int(last_match_payload.get("host_seat", 0), 0)
	if old_host >= 0 and old_host < seats.size():
		_seat_row(old_host)["ghost"] = true
		_seat_row(old_host)["peer_id"] = 0
		_seat_row(old_host)["ready"] = false
	## Drop dead peer sockets but keep lobby/match fields for election.
	_teardown_peer_only()
	var gen: int = host_migrate_generation + 1
	var seed_v: int = TypedVariant.as_int(last_match_payload.get("match_seed", 0), 0)
	var elected: int = elect_new_host_seat(seats, opening_host_platform, seed_v, gen)
	if elected < 0:
		_terminate_match_host_lost("房主掉线，对局终止")
		return
	host_migrate_generation = gen
	if last_match_payload.is_empty():
		last_match_payload = {}
	last_match_payload["host_seat"] = elected
	last_match_payload["host_migrate_generation"] = gen
	if elected == local_seat:
		_promote_self_to_host(elected)
		return
	var hip: String = ""
	if elected >= 0 and elected < seats.size():
		hip = str(_seat_row(elected).get("endpoint_ip", ""))
	## New host listens on room code port (not the old client ephemeral source port).
	var hport: int = port_for_code(room_code)
	if hip == "" or hip == "0.0.0.0":
		_terminate_match_host_lost("房主掉线，对局终止")
		return
	pending_rejoin_seat = local_seat
	pending_rejoin_secret = session_secret
	var nick: String = local_nick
	var keep_seat: int = local_seat
	var keep_payload: Dictionary = last_match_payload.duplicate(true)
	var keep_seats: Array = seats.duplicate(true)
	var err: Error = join(hip, hport, nick, rules_hash)
	last_match_payload = keep_payload
	seats = keep_seats
	match_started = true
	local_seat = keep_seat
	pending_rejoin_seat = keep_seat
	pending_rejoin_secret = session_secret
	if err != OK:
		_terminate_match_host_lost("房主掉线，对局终止")
		return
	_migrating = false
	write_rejoin_ticket()
	host_migrated.emit(gen, elected)


func _promote_self_to_host(new_host_seat: int) -> void:
	is_host = true
	_listen_port = port_for_code(room_code)
	last_known_host_ip = _best_local_ip()
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_server(_listen_port, MAX_CLIENTS)
	if err != OK:
		_peer = null
		_listen_port = 0
		_terminate_match_host_lost("房主掉线，对局终止")
		return
	_enable_enet_range_compress()
	multiplayer.multiplayer_peer = _peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	var uid: int = multiplayer.get_unique_id()
	if local_seat >= 0 and local_seat < seats.size():
		_seat_row(local_seat)["peer_id"] = uid
		_seat_row(local_seat)["ghost"] = false
		_seat_row(local_seat)["platform"] = detect_local_platform()
		_seat_row(local_seat)["endpoint_ip"] = last_known_host_ip
		_seat_row(local_seat)["endpoint_port"] = _listen_port
	if not opening_host_ships.is_empty():
		DataStore.apply_host_ships_override(opening_host_ships)
	_start_beacon()
	_broadcast_seats()
	rpc(
		"rpc_host_migrated",
		host_migrate_generation,
		new_host_seat,
		last_known_host_ip,
		_listen_port,
		session_secret
	)
	write_rejoin_ticket()
	host_migrated.emit(host_migrate_generation, new_host_seat)
	_migrating = false


@rpc("any_peer", "reliable")
func rpc_host_migrated(
	generation: int,
	new_host_seat: int,
	host_ip: String = "",
	host_port: int = 0,
	secret: String = ""
) -> void:
	host_migrate_generation = generation
	if host_ip != "":
		last_known_host_ip = host_ip
	if secret != "":
		session_secret = secret
	if last_match_payload.is_empty():
		last_match_payload = {}
	last_match_payload["host_seat"] = new_host_seat
	last_match_payload["host_migrate_generation"] = generation
	if host_port > 0 and not is_host and (multiplayer == null or not multiplayer.has_multiplayer_peer()):
		## Late notice — try reconnect with pending rejoin.
		pending_rejoin_seat = local_seat
		pending_rejoin_secret = session_secret
		join(host_ip, host_port, local_nick, rules_hash)
		match_started = true
	write_rejoin_ticket()
	host_migrated.emit(generation, new_host_seat)


func _terminate_match_host_lost(reason: String) -> void:
	_migrating = false
	clear_rejoin_ticket()
	match_started = false
	match_terminated_host_lost.emit(reason if reason != "" else "房主掉线，对局终止")
	_teardown_peer_only()


func _teardown_peer_only() -> void:
	if _beacon and is_instance_valid(_beacon):
		_beacon.stop()
		_beacon.queue_free()
	_beacon = null
	if multiplayer and multiplayer.has_multiplayer_peer():
		if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
			multiplayer.connected_to_server.disconnect(_on_connected_to_server)
		if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
			multiplayer.server_disconnected.disconnect(_on_server_disconnected)
		if multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.disconnect(_on_peer_connected)
		if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
		multiplayer.multiplayer_peer = null
	_peer = null
	_listen_port = 0


func close() -> void:
	_teardown_peer_only()
	is_host = false
	local_seat = -1
	match_started = false
	last_match_payload = {}
	host_ships_hash = ""
	session_secret = ""
	match_id = ""
	opening_host_ships = {}
	opening_host_ships_hash = ""
	opening_host_platform = "pc"
	host_migrate_generation = 0
	last_known_host_ip = ""
	last_known_host_ipv6 = ""
	pending_rejoin_seat = -1
	pending_rejoin_secret = ""
	pending_join_password = ""
	room_password = ""
	room_has_password = false
	_migrating = false
	_ticket_heartbeat_acc = 0.0
	DataStore.end_match_host_ships_material()
	_init_empty_seats()


## SEMI_ASYNC §3.9 / §7.1 — ENet range coder (complements payload zstd).
func _enable_enet_range_compress() -> void:
	if _peer == null:
		return
	var host_v: Variant = null
	if _peer.has_method("get_host"):
		host_v = _peer.call("get_host")
	if host_v == null:
		host_v = _peer.get("host")
	if not (host_v is ENetConnection):
		return
	@warning_ignore("unsafe_cast")
	var host: ENetConnection = host_v
	host.compress(ENetConnection.COMPRESS_RANGE_CODER)


## --- Prepare fleet sync (SEMI_ASYNC §3.0d binary · rival-only) ---

func manned_field_count_cached(seat: int) -> int:
	## Prepare 终态有人 field 舰（击杀金同口径）；无人不计。
	@warning_ignore("unsafe_cast")
	var cached: Array = _prepare_fleet_cache.get(seat, []) as Array
	var n: int = 0
	for e_v: Variant in cached:
		var e: Dictionary = TypedVariant.as_dict(e_v)
		if e.is_empty():
			continue
		if str(e.get("slot_type", "")) != "field":
			continue
		if TypedVariant.as_bool(e.get("is_unmanned", false), false):
			continue
		n += 1
	return n


func push_prepare_fleet_snapshot(ships: Array) -> void:
	if local_seat < 0:
		return
	_prepare_fleet_cache[local_seat] = ships
	var n: int = ships.size()
	var has_peer: bool = multiplayer.has_multiplayer_peer()
	## Avoid logcat flood — only note size changes / rare heartbeat.
	var now: int = Time.get_ticks_msec()
	if n != _fleet_push_log_n or (now - _fleet_push_log_msec) > 3000:
		_fleet_push_log_n = n
		_fleet_push_log_msec = now
		print("[mp.diag] fleet_push seat=%d n=%d host=%s peer=%s" % [local_seat, n, is_host, has_peer])
		SessionDiagnostics.log("mp.fleet_push", "seat=%d n=%d" % [local_seat, n])
	if not has_peer:
		return
	var data: PackedByteArray = NetWireCodec.encode_fleet(
		local_seat, ships, NetConnectivity.wire_compress_min_bytes()
	)
	if is_host:
		_deliver_fleet_bin_to_rivals(local_seat, data)
		## Host applying own push for local spectate/debug is N/A — rivals only.
	else:
		rpc_id(1, "rpc_prepare_fleet_report_bin", local_seat, data)


@rpc("any_peer", "reliable")
func rpc_prepare_fleet_report_bin(seat: int, data: PackedByteArray) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if TypedVariant.as_int(_seat_row(seat).get("peer_id", 0), 0) != sender:
		print("[mp.diag] fleet_report REJECT seat=%d sender=%d" % [seat, sender])
		return
	var decoded: Dictionary = NetWireCodec.decode_fleet(data)
	var ships: Array = TypedVariant.as_array(decoded.get("ships", []))
	_prepare_fleet_cache[seat] = ships
	print("[mp.diag] fleet_report seat=%d n=%d → rivals" % [seat, ships.size()])
	SessionDiagnostics.log("mp.fleet_report", "seat=%d n=%d" % [seat, ships.size()])
	_deliver_fleet_bin_to_rivals(seat, data)


@rpc("authority", "reliable")
func rpc_prepare_fleet_snapshot_bin(seat: int, data: PackedByteArray) -> void:
	var decoded: Dictionary = NetWireCodec.decode_fleet(data)
	var ships: Array = TypedVariant.as_array(decoded.get("ships", []))
	var seat_wire: int = TypedVariant.as_int(decoded.get("seat", seat), seat)
	_prepare_fleet_cache[seat_wire] = ships
	print("[mp.diag] fleet_snap_rx seat=%d n=%d" % [seat_wire, ships.size()])
	SessionDiagnostics.log("mp.fleet_snap_rx", "seat=%d n=%d" % [seat_wire, ships.size()])
	prepare_fleet_snapshot_received.emit(seat_wire, ships)


func request_prepare_fleet_snapshot(seat: int) -> void:
	if seat < 0:
		return
	print("[mp.diag] fleet_request seat=%d host=%s" % [seat, is_host])
	SessionDiagnostics.log("mp.fleet_request", "seat=%d" % seat)
	if is_host or not multiplayer.has_multiplayer_peer():
		@warning_ignore("unsafe_cast")
		var cached: Array = _prepare_fleet_cache.get(seat, []) as Array
		print("[mp.diag] fleet_request_local seat=%d n=%d" % [seat, cached.size()])
		prepare_fleet_snapshot_received.emit(seat, cached)
		return
	rpc_id(1, "rpc_request_prepare_fleet", seat)


@rpc("any_peer", "reliable")
func rpc_request_prepare_fleet(seat: int) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	@warning_ignore("unsafe_cast")
	var cached: Array = _prepare_fleet_cache.get(seat, []) as Array
	var data: PackedByteArray = NetWireCodec.encode_fleet(
		seat, cached, NetConnectivity.wire_compress_min_bytes()
	)
	rpc_id(sender, "rpc_prepare_fleet_snapshot_bin", seat, data)


## Same first-other-contender rule as MatchRoot._nullsec_rival_seat (2p correct).
func contestant_rival_seat(for_seat: int) -> int:
	for i: int in range(seats.size()):
		var row: Dictionary = _seat_row(i)
		if not TypedVariant.as_bool(row.get("occupied", false), false):
			continue
		var sid: int = TypedVariant.as_int(row.get("seat_id", i), i)
		if sid == for_seat or sid < 0:
			continue
		if not is_player_race(str(row.get("titan_race", ""))):
			continue
		return sid
	return -1


func _deliver_fleet_bin_to_rivals(from_seat: int, data: PackedByteArray) -> void:
	## Deliver to every contestant whose rival is from_seat (preserves apply filter).
	var delivered: Dictionary = {}
	for i: int in range(seats.size()):
		var row: Dictionary = _seat_row(i)
		if not TypedVariant.as_bool(row.get("occupied", false), false):
			continue
		var sid: int = TypedVariant.as_int(row.get("seat_id", i), i)
		if sid == from_seat or sid < 0:
			continue
		if not is_player_race(str(row.get("titan_race", ""))):
			continue
		if contestant_rival_seat(sid) != from_seat:
			continue
		if TypedVariant.as_bool(row.get("is_ai", false), false):
			continue
		if sid == local_seat:
			## Host is the rival — apply locally.
			var decoded: Dictionary = NetWireCodec.decode_fleet(data)
			var ships: Array = TypedVariant.as_array(decoded.get("ships", []))
			prepare_fleet_snapshot_received.emit(from_seat, ships)
			delivered[sid] = true
			continue
		var peer_id: int = TypedVariant.as_int(row.get("peer_id", 0), 0)
		if peer_id <= 0 or delivered.has(peer_id):
			continue
		delivered[peer_id] = true
		rpc_id(peer_id, "rpc_prepare_fleet_snapshot_bin", from_seat, data)


## --- First-prepare spend clock ---

func begin_prepare_spend_gate() -> void:
	## R1 Prepare only: freeze until all contestant seats spend once.
	## Clients only mirror freeze; host owns the set + arm broadcast.
	## IMPORTANT: session default prepare_clock_armed=true — must NOT treat that as
	## "already armed" or guests skip the gate and solo-run the timer (stuck async).
	## MATCH_FLOW: never open spend-gate after battle_game_stage_count > 0 (caller must guard).
	var has_peer: bool = multiplayer.has_multiplayer_peer()
	print("[mp.diag] spend_gate_begin host=%s peer=%s local_seat=%d seats=%d armed_was=%s" % [
		is_host, has_peer, local_seat, seats.size(), prepare_clock_armed
	])
	SessionDiagnostics.log(
		"mp.spend_gate_begin",
		"host=%s peer=%s seat=%d n=%d" % [is_host, has_peer, local_seat, seats.size()]
	)
	## Always clear local arm first — only host rpc_prepare_clock_armed may re-arm peers.
	prepare_clock_armed = false
	_prepare_spend_gate_open = true
	prepare_clock_armed_changed.emit(false)
	if not is_host and has_peer:
		print("[mp.diag] spend_gate_begin client freeze (await host arm)")
		return
	_prepare_spent_seats.clear()
	var contestants: PackedStringArray = PackedStringArray()
	for i: int in range(seats.size()):
		var row: Dictionary = _seat_row(i)
		if not TypedVariant.as_bool(row.get("occupied", false), false):
			continue
		if TypedVariant.as_bool(row.get("ghost", false), false):
			continue
		if not is_player_race(str(row.get("titan_race", ""))):
			continue
		var is_ai: bool = TypedVariant.as_bool(row.get("is_ai", false), false)
		if is_ai:
			_prepare_spent_seats[i] = true
		contestants.append("%d:%s" % [i, "AI" if is_ai else "H"])
	print("[mp.diag] spend_gate_contestants [%s] spent=%s" % [
		",".join(contestants), str(_prepare_spent_seats.keys())
	])
	SessionDiagnostics.log("mp.spend_gate_seats", ",".join(contestants))
	_check_prepare_clock_ready()


func report_local_prepare_spend() -> void:
	if prepare_clock_armed or local_seat < 0:
		return
	print("[mp.diag] spend_report seat=%d host=%s" % [local_seat, is_host])
	SessionDiagnostics.log("mp.spend_report", "seat=%d" % local_seat)
	if is_host or not multiplayer.has_multiplayer_peer():
		_mark_prepare_spend(local_seat)
	else:
		rpc_id(1, "rpc_prepare_first_spend", local_seat)


@rpc("any_peer", "reliable")
func rpc_prepare_first_spend(seat: int) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if TypedVariant.as_int(_seat_row(seat).get("peer_id", 0), 0) != sender:
		print("[mp.diag] spend_rpc REJECT seat=%d sender=%d" % [seat, sender])
		return
	print("[mp.diag] spend_rpc ACCEPT seat=%d sender=%d" % [seat, sender])
	_mark_prepare_spend(seat)


func _mark_prepare_spend(seat: int) -> void:
	if prepare_clock_armed:
		return
	_prepare_spent_seats[seat] = true
	print("[mp.diag] spend_marked seat=%d spent=%s" % [seat, str(_prepare_spent_seats.keys())])
	SessionDiagnostics.log("mp.spend_marked", "seat=%d" % seat)
	_check_prepare_clock_ready()


func _check_prepare_clock_ready() -> void:
	if prepare_clock_armed:
		return
	var missing: PackedStringArray = PackedStringArray()
	for i: int in range(seats.size()):
		var row: Dictionary = _seat_row(i)
		if not TypedVariant.as_bool(row.get("occupied", false), false):
			continue
		if TypedVariant.as_bool(row.get("ghost", false), false):
			continue
		if not is_player_race(str(row.get("titan_race", ""))):
			continue
		if not TypedVariant.as_bool(_prepare_spent_seats.get(i, false), false):
			missing.append(str(i))
	if not missing.is_empty():
		print("[mp.diag] spend_gate_wait missing=[%s]" % ",".join(missing))
		return
	print("[mp.diag] spend_gate_ALL_READY → arm")
	_arm_prepare_clock()


func _arm_prepare_clock() -> void:
	if prepare_clock_armed:
		return
	prepare_clock_armed = true
	_prepare_spend_gate_open = false
	_barrier_open_wall_ms = 0
	## New prepare clock → clear prior round's prepare-done marks.
	_prepare_done_seats.clear()
	_prepare_done_gate_open = false
	_local_prep_done_sent = false
	print("[mp.diag] net_clock_ARMED host=%s → rpc" % is_host)
	SessionDiagnostics.log("mp.net_clock_armed", "host=%s" % is_host)
	if is_host and multiplayer.has_multiplayer_peer():
		rpc("rpc_prepare_clock_armed")
	prepare_clock_armed_changed.emit(true)
	## Flush prep_done that arrived while frozen (SEMI_ASYNC §3.0a 重报).
	if is_host and not _early_prep_done_seats.is_empty():
		var early: Array = _early_prep_done_seats.keys()
		_early_prep_done_seats.clear()
		begin_prepare_done_gate()
		for s_v: Variant in early:
			_mark_prepare_done(TypedVariant.as_int(s_v, -1))
	if _pending_prepare_done_report:
		_pending_prepare_done_report = false
		call_deferred("report_local_prepare_done")


func is_battle_done_gate_open() -> bool:
	return _battle_done_gate_open


## True while battle_done gate waits on ≥1 human contestant (conditional wall-draw arm).
func has_battle_done_missing_humans() -> bool:
	if not _battle_done_gate_open:
		return false
	for i: int in _iter_barrier_seats():
		if TypedVariant.as_bool(_seat_row(i).get("is_ai", false), false):
			continue
		if not TypedVariant.as_bool(_battle_done_seats.get(i, false), false):
			return true
	return false


func is_prepare_done_gate_open() -> bool:
	return _prepare_done_gate_open


func is_prepare_spend_gate_pending() -> bool:
	## R1 first-spend freeze still open — pulse escape must NOT force-arm (MATCH_FLOW §2.1).
	return _prepare_spend_gate_open and not prepare_clock_armed


## SEMI_ASYNC §3.0a — wall-clock heal / force for prepare freeze & barrier deadlock.
## Returns comma-joined action tags (empty if idle).
## Never force-arms while R1 spend gate is still waiting for every contestant.
func pulse_prepare_escape() -> String:
	if not needs_stage_barrier():
		_barrier_open_wall_ms = 0
		return ""
	var actions: PackedStringArray = PackedStringArray()
	var now: int = Time.get_ticks_msec()
	if prepare_clock_armed and _pending_prepare_done_report:
		_pending_prepare_done_report = false
		call_deferred("report_local_prepare_done")
		actions.append("flush_pending_prep_done")
	if is_host:
		if _battle_done_gate_open:
			_check_battle_done_ready()
			actions.append("recheck_battle_done")
		if _prepare_done_gate_open:
			_check_prepare_done_ready()
			actions.append("recheck_prep_done")
		## Host stuck as sole missing prep_done while clock already armed.
		if _prepare_done_gate_open and prepare_clock_armed and local_seat >= 0:
			var miss: PackedStringArray = _barrier_missing_now("prep_done")
			if miss.size() == 1 and miss[0] == str(local_seat):
				_mark_prepare_done(local_seat)
				actions.append("host_self_prep_done")
	var gate_open: bool = _battle_done_gate_open or _prepare_done_gate_open
	if gate_open:
		if _barrier_open_wall_ms <= 0:
			_barrier_open_wall_ms = now
		elif is_host and now - _barrier_open_wall_ms >= BARRIER_FORCE_ESCAPE_MS:
			_force_barrier_escape()
			actions.append("force_barrier_escape")
			_barrier_open_wall_ms = 0
	else:
		_barrier_open_wall_ms = 0
	return ",".join(actions)


## Host: clear stuck battle_done / prep_done and release (last-resort).
func force_barrier_escape() -> void:
	_force_barrier_escape()


func _force_barrier_escape() -> void:
	if not is_host:
		return
	print("[mp.diag] prep_pulse_escape FORCE barrier open_bd=%s open_pd=%s" % [
		_battle_done_gate_open, _prepare_done_gate_open
	])
	SessionDiagnostics.log("mp.prep_pulse_escape", "force_barrier")
	if _battle_done_gate_open:
		for i: int in _iter_barrier_seats():
			if TypedVariant.as_bool(_seat_row(i).get("is_ai", false), false):
				continue
			_battle_done_seats[i] = true
		_check_battle_done_ready()
		if _battle_done_gate_open:
			_battle_done_gate_open = false
			_arm_prepare_clock()
	if _prepare_done_gate_open:
		for i: int in _iter_prepare_cohort():
			if TypedVariant.as_bool(_seat_row(i).get("is_ai", false), false):
				continue
			_prepare_done_seats[i] = true
		_check_prepare_done_ready()
		if _prepare_done_gate_open:
			_prepare_done_gate_open = false
			if multiplayer.has_multiplayer_peer():
				rpc("rpc_enter_battle")
			enter_battle_released.emit()


## Host last-resort: force arm even if local net flag already true (re-emit to peers).
## Forbidden while R1 spend gate still waits for first spends (MATCH_FLOW §2.1).
func force_arm_prepare_clock_escape() -> void:
	if not is_host:
		return
	if is_prepare_spend_gate_pending():
		print("[mp.diag] prep_pulse_escape force_arm BLOCKED spend_gate")
		SessionDiagnostics.log("mp.prep_pulse_escape", "force_arm_blocked_spend_gate")
		return
	print("[mp.diag] prep_pulse_escape force_arm was_armed=%s" % prepare_clock_armed)
	SessionDiagnostics.log("mp.prep_pulse_escape", "force_arm")
	_battle_done_gate_open = false
	_barrier_open_wall_ms = 0
	if prepare_clock_armed:
		## Re-broadcast so guests that missed rpc_prepare_clock_armed catch up.
		if multiplayer.has_multiplayer_peer():
			rpc("rpc_prepare_clock_armed")
		prepare_clock_armed_changed.emit(true)
		if _pending_prepare_done_report:
			_pending_prepare_done_report = false
			call_deferred("report_local_prepare_done")
		return
	_arm_prepare_clock()


@rpc("authority", "reliable")
func rpc_prepare_clock_armed() -> void:
	prepare_clock_armed = true
	_prepare_spend_gate_open = false
	_local_prep_done_sent = false
	print("[mp.diag] rpc_prepare_clock_armed received")
	SessionDiagnostics.log("mp.rpc_clock_armed", "")
	prepare_clock_armed_changed.emit(true)
	if _pending_prepare_done_report:
		_pending_prepare_done_report = false
		call_deferred("report_local_prepare_done")


## --- SEMI_ASYNC §3.0a: battle-done → prepare clock; prepare-done → enter battle ---

func needs_stage_barrier() -> bool:
	## Remote peer present → keep stages locked together.
	if not multiplayer.has_multiplayer_peer():
		return false
	return multiplayer.get_peers().size() >= 1


func _iter_contestant_seats() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in range(seats.size()):
		var row: Dictionary = _seat_row(i)
		if not TypedVariant.as_bool(row.get("occupied", false), false):
			continue
		if TypedVariant.as_bool(row.get("ghost", false), false):
			continue
		if not is_player_race(str(row.get("titan_race", ""))):
			continue
		out.append(i)
	return out


## Seats that must report for §3.0a barriers (excludes ghost / spectate / dead peers).
func _iter_barrier_seats() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var peers: PackedInt32Array = PackedInt32Array()
	if multiplayer.has_multiplayer_peer():
		peers = multiplayer.get_peers()
	var self_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	for i: int in _iter_contestant_seats():
		var row: Dictionary = _seat_row(i)
		if TypedVariant.as_bool(row.get("is_ai", false), false):
			## AI auto-marked; still listed so auto-mark path finds them.
			out.append(i)
			continue
		if is_spectate_race(str(row.get("titan_race", ""))):
			continue
		var peer: int = TypedVariant.as_int(row.get("peer_id", 0), 0)
		if peer <= 0:
			## No live peer — do not block (orphaned / mid-migrate).
			continue
		if peer != self_id and peers.size() > 0 and not (peer in peers):
			## Disconnected human — skip so 1v1/MVP cannot softlock.
			continue
		out.append(i)
	return out


func _auto_mark_ai_seats(into: Dictionary) -> void:
	for i: int in _iter_contestant_seats():
		if TypedVariant.as_bool(_seat_row(i).get("is_ai", false), false):
			into[i] = true


func _auto_mark_inactive_barrier_seats(into: Dictionary) -> void:
	## Mark everyone who must NOT block: AI + seats absent from barrier list.
	_auto_mark_ai_seats(into)
	var need: Dictionary = {}
	for i: int in _iter_barrier_seats():
		need[i] = true
	for i: int in _iter_contestant_seats():
		if not TypedVariant.as_bool(need.get(i, false), false):
			into[i] = true


func _iter_prepare_cohort() -> PackedInt32Array:
	if _sync_cohort.is_empty():
		return _iter_barrier_seats()
	return _sync_cohort


func _auto_mark_cohort_inactive(into: Dictionary) -> void:
	_auto_mark_ai_seats(into)
	var need: Dictionary = {}
	for i: int in _iter_prepare_cohort():
		need[i] = true
	for i: int in _iter_contestant_seats():
		if not TypedVariant.as_bool(need.get(i, false), false):
			into[i] = true
	## Also mark cohort seats whose peer dropped mid-prepare.
	var peers: PackedInt32Array = PackedInt32Array()
	if multiplayer.has_multiplayer_peer():
		peers = multiplayer.get_peers()
	var self_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	for i: int in _iter_prepare_cohort():
		var row: Dictionary = _seat_row(i)
		if TypedVariant.as_bool(row.get("is_ai", false), false):
			into[i] = true
			continue
		if TypedVariant.as_bool(row.get("ghost", false), false):
			into[i] = true
			continue
		var peer: int = TypedVariant.as_int(row.get("peer_id", 0), 0)
		if peer <= 0:
			into[i] = true
			continue
		if peer != self_id and peers.size() > 0 and not (peer in peers):
			into[i] = true


func _cohort_csv() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in _iter_prepare_cohort():
		parts.append(str(i))
	return ",".join(parts)


func _barrier_missing_now(phase: String) -> PackedStringArray:
	var missing: PackedStringArray = PackedStringArray()
	var marks: Dictionary = _prepare_done_seats if phase == "prep_done" else _battle_done_seats
	var seats_iter: PackedInt32Array = _iter_prepare_cohort() if phase == "prep_done" else _iter_barrier_seats()
	for i: int in seats_iter:
		if TypedVariant.as_bool(_seat_row(i).get("is_ai", false), false):
			continue
		if not TypedVariant.as_bool(marks.get(i, false), false):
			missing.append(str(i))
	return missing


func _barrier_missing_nicks(phase: String) -> PackedStringArray:
	var nicks: PackedStringArray = PackedStringArray()
	for s: String in _barrier_missing_now(phase):
		var seat: int = int(s) if s.is_valid_int() else -1
		var row: Dictionary = _seat_row(seat)
		var nick: String = NickCodec.display_short(str(row.get("nick", "")))
		if nick == "" or nick == "?":
			nick = "席%d" % seat
		nicks.append(nick)
	return nicks


## HUD copy for prepare freeze / peer-hold (MATCH_FLOW §2.1).
func barrier_wait_hud_text(phase: String) -> String:
	var nicks: PackedStringArray = _barrier_missing_nicks(phase)
	if nicks.is_empty():
		return "等待对齐" if phase == "prep_done" else "等待开战钟"
	var who: String = "、".join(nicks)
	if phase == "battle_done":
		return "等待 %s 结束战斗" % who
	return "等待 %s" % who


func _log_barrier_state(phase: String, missing: PackedStringArray) -> void:
	var marked: PackedStringArray = PackedStringArray()
	var peers_info: PackedStringArray = PackedStringArray()
	var marks: Dictionary = _prepare_done_seats if phase == "prep_done" else _battle_done_seats
	var seats_iter: PackedInt32Array = _iter_prepare_cohort() if phase == "prep_done" else _iter_barrier_seats()
	for i: int in seats_iter:
		var row: Dictionary = _seat_row(i)
		peers_info.append("%d:p%d:ai%d:g%d" % [
			i,
			TypedVariant.as_int(row.get("peer_id", 0), 0),
			1 if TypedVariant.as_bool(row.get("is_ai", false), false) else 0,
			1 if TypedVariant.as_bool(row.get("ghost", false), false) else 0,
		])
		if TypedVariant.as_bool(marks.get(i, false), false):
			marked.append(str(i))
	var detail: String = "phase=%s host=%s armed=%s cohort=[%s] marked=[%s] missing=[%s] missing_nicks=[%s] seats=[%s]" % [
		phase,
		is_host,
		prepare_clock_armed,
		_cohort_csv(),
		",".join(marked),
		",".join(missing),
		",".join(_barrier_missing_nicks(phase)),
		";".join(peers_info),
	]
	print("[mp.barrier] %s" % detail)
	SessionDiagnostics.log("mp.barrier", detail)


func begin_battle_done_clock_gate() -> void:
	## After a battle: freeze Prepare clocks until every contestant finishes combat.
	if not needs_stage_barrier():
		return
	var has_peer: bool = multiplayer.has_multiplayer_peer()
	print("[mp.diag] battle_done_gate_begin host=%s peer=%s open=%s" % [
		is_host, has_peer, _battle_done_gate_open
	])
	## Always freeze local clock; host owns the seat set.
	prepare_clock_armed = false
	prepare_clock_armed_changed.emit(false)
	if not is_host and has_peer:
		SessionDiagnostics.log("mp.battle_done_gate", "client_freeze")
		return
	if _battle_done_gate_open:
		## Guest may have reported first — keep existing marks.
		_check_battle_done_ready()
		return
	_battle_done_gate_open = true
	_battle_done_seats.clear()
	_sync_cohort = PackedInt32Array()
	_auto_mark_inactive_barrier_seats(_battle_done_seats)
	SessionDiagnostics.log("mp.battle_done_gate", "host_open")
	_check_battle_done_ready()


func report_local_battle_done() -> void:
	if not needs_stage_barrier() or local_seat < 0:
		return
	if not _battle_done_gate_open and is_host:
		begin_battle_done_clock_gate()
	print("[mp.diag] battle_done_report seat=%d host=%s" % [local_seat, is_host])
	SessionDiagnostics.log("mp.battle_done_report", "seat=%d" % local_seat)
	if is_host or not multiplayer.has_multiplayer_peer():
		_mark_battle_done(local_seat)
	else:
		## Guest may finish first — host opens gate on first RPC.
		rpc_id(1, "rpc_round_battle_done", local_seat)


@rpc("any_peer", "reliable")
func rpc_round_battle_done(seat: int) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if TypedVariant.as_int(_seat_row(seat).get("peer_id", 0), 0) != sender:
		print("[mp.diag] battle_done REJECT seat=%d sender=%d" % [seat, sender])
		return
	if not _battle_done_gate_open:
		begin_battle_done_clock_gate()
	print("[mp.diag] battle_done ACCEPT seat=%d" % seat)
	_mark_battle_done(seat)


func _mark_battle_done(seat: int) -> void:
	_battle_done_seats[seat] = true
	## §4.5: notify every peer so remaining tables go 4× and start 2min wall clock.
	if multiplayer.has_multiplayer_peer() and is_host:
		rpc("rpc_seat_battle_finished", seat)
	else:
		seat_battle_finished.emit(seat)
	_check_battle_done_ready()


@rpc("authority", "reliable", "call_local")
func rpc_seat_battle_finished(seat: int) -> void:
	print("[mp.diag] seat_battle_finished seat=%d" % seat)
	SessionDiagnostics.log("mp.seat_battle_finished", "seat=%d" % seat)
	seat_battle_finished.emit(seat)


func _check_battle_done_ready() -> void:
	if not is_host or not _battle_done_gate_open:
		return
	_auto_mark_inactive_barrier_seats(_battle_done_seats)
	var missing: PackedStringArray = PackedStringArray()
	for i: int in _iter_barrier_seats():
		if TypedVariant.as_bool(_seat_row(i).get("is_ai", false), false):
			continue
		if not TypedVariant.as_bool(_battle_done_seats.get(i, false), false):
			missing.append(str(i))
	_log_barrier_state("battle_done", missing)
	if not missing.is_empty():
		print("[mp.diag] battle_done_wait missing=[%s]" % ",".join(missing))
		return
	_battle_done_gate_open = false
	## Cohort for prepare→battle = seats that finished this battle (not whole room).
	_sync_cohort = PackedInt32Array()
	for i: int in _iter_barrier_seats():
		if TypedVariant.as_bool(_battle_done_seats.get(i, false), false) \
			or TypedVariant.as_bool(_seat_row(i).get("is_ai", false), false):
			_sync_cohort.append(i)
	if _sync_cohort.is_empty():
		for i: int in _iter_barrier_seats():
			_sync_cohort.append(i)
	print("[mp.diag] battle_done_ALL_READY -> arm clock cohort=[%s]" % _cohort_csv())
	SessionDiagnostics.log("mp.barrier", "battle_done_all cohort=[%s]" % _cohort_csv())
	if multiplayer.has_multiplayer_peer() and is_host:
		rpc("rpc_battle_done_all_ready")
	else:
		battle_done_all_ready.emit()
	_arm_prepare_clock()


@rpc("authority", "reliable", "call_local")
func rpc_battle_done_all_ready() -> void:
	print("[mp.diag] battle_done_all_ready")
	SessionDiagnostics.log("mp.wall_draw", "all_ready")
	battle_done_all_ready.emit()


## --- MULTIPLAYER_PVP §7 end-of-match report (settlement rows + §7.1 titles) ---

## Public entry point: submit this seat's own settlement summary (host stores it directly;
## guest ships it to the host via RPC). Thin alias over `begin_match_report_collection` so
## callers can read intent from the call site.
func submit_local_match_summary(summary: Dictionary) -> void:
	begin_match_report_collection(summary)


## Every contestant submits its own local settlement summary; host stitches them into
## one combined report and broadcasts it. Solo / no-live-peer tables have nothing to
## collect, so they just emit locally right away.
func begin_match_report_collection(local_summary: Dictionary) -> void:
	if not needs_stage_barrier():
		match_report_received.emit(NullsecSettlement.make_match_report(match_id, local_seat, [local_summary]))
		return
	if local_seat >= 0:
		local_summary["seat_id"] = local_seat
	if not is_host:
		rpc_id(1, "rpc_seat_match_summary", local_summary)
		return
	if not _match_report_gate_open:
		_match_report_gate_open = true
		_match_report_seats.clear()
		_match_report_summaries.clear()
		_auto_mark_inactive_barrier_seats(_match_report_seats)
		## Never let a dropped peer hang the settlement screen forever.
		get_tree().create_timer(8.0).timeout.connect(_finish_match_report_collection, CONNECT_ONE_SHOT)
	_ingest_match_summary(local_seat, local_summary)


@rpc("any_peer", "reliable")
func rpc_seat_match_summary(summary: Dictionary) -> void:
	if not is_host:
		return
	var seat: int = TypedVariant.as_int(summary.get("seat_id", -1), -1)
	var sender: int = multiplayer.get_remote_sender_id()
	if seat < 0 or TypedVariant.as_int(_seat_row(seat).get("peer_id", 0), 0) != sender:
		print("[mp.diag] match_summary REJECT seat=%d sender=%d" % [seat, sender])
		return
	if not _match_report_gate_open:
		_match_report_gate_open = true
		_match_report_seats.clear()
		_match_report_summaries.clear()
		_auto_mark_inactive_barrier_seats(_match_report_seats)
		get_tree().create_timer(8.0).timeout.connect(_finish_match_report_collection, CONNECT_ONE_SHOT)
	_ingest_match_summary(seat, summary)


func _ingest_match_summary(seat: int, summary: Dictionary) -> void:
	if seat < 0:
		return
	_match_report_seats[seat] = true
	_match_report_summaries[seat] = summary
	_check_match_report_ready()


func _check_match_report_ready() -> void:
	if not is_host or not _match_report_gate_open:
		return
	for i: int in _iter_barrier_seats():
		if TypedVariant.as_bool(_seat_row(i).get("is_ai", false), false):
			continue
		if not TypedVariant.as_bool(_match_report_seats.get(i, false), false):
			return
	_finish_match_report_collection()


func _finish_match_report_collection() -> void:
	if not _match_report_gate_open:
		return
	_match_report_gate_open = false
	var players: Array = []
	var seen: Dictionary = {}
	## Prefer live summaries; fill every contestant seat (AI / absent / disconnected).
	for i: int in _iter_contestant_seats_including_ghosts():
		var summary_v: Variant = _match_report_summaries.get(i, null)
		if typeof(summary_v) == TYPE_DICTIONARY:
			var s: Dictionary = summary_v
			s["seat_id"] = i
			players.append(s)
			seen[i] = true
			continue
		players.append(_synthesize_absent_summary(i))
		seen[i] = true
	## Also keep any extra summaries that somehow weren't in contestant iter.
	for seat_v: Variant in _match_report_summaries.keys():
		var sid: int = TypedVariant.as_int(seat_v, -1)
		if sid < 0 or TypedVariant.as_bool(seen.get(sid, false), false):
			continue
		players.append(_match_report_summaries[seat_v])
	print("[mp.diag] match_report_ready players=%d" % players.size())
	rpc("rpc_match_report", NullsecSettlement.make_match_report(match_id, local_seat, players))


## Contestants for end report — includes ghost / eliminated (still listed).
func _iter_contestant_seats_including_ghosts() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in range(seats.size()):
		var row: Dictionary = _seat_row(i)
		if not TypedVariant.as_bool(row.get("occupied", false), false):
			## Ghost seats may clear occupied; still include if titan race was a player.
			if not is_player_race(str(row.get("titan_race", ""))):
				continue
		elif is_spectate_race(str(row.get("titan_race", ""))):
			continue
		elif not is_player_race(str(row.get("titan_race", ""))):
			continue
		out.append(i)
	return out


func _synthesize_absent_summary(seat: int) -> Dictionary:
	var row: Dictionary = _seat_row(seat)
	var nick: String = str(row.get("nick", "席位%d" % seat))
	var is_ai: bool = TypedVariant.as_bool(row.get("is_ai", false), false)
	var ghost: bool = TypedVariant.as_bool(row.get("ghost", false), false)
	var result: String = "淘汰" if ghost else "—"
	var summary: Dictionary = NullsecSettlement.make_row(nick, 1, 0, result, [], [], seat)
	summary["absent"] = true
	summary["is_ai"] = is_ai
	summary["ghost"] = ghost
	summary["titan_race"] = str(row.get("titan_race", ""))
	return summary


func push_speed_vote(speed: float) -> void:
	if local_seat < 0:
		return
	if not multiplayer.has_multiplayer_peer() or not needs_stage_barrier():
		speed_vote_received.emit(local_seat, speed)
		return
	if is_host:
		rpc("rpc_speed_vote_apply", local_seat, speed)
	else:
		rpc_id(1, "rpc_speed_vote", local_seat, speed)


@rpc("any_peer", "reliable")
func rpc_speed_vote(seat: int, speed: float) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if TypedVariant.as_int(_seat_row(seat).get("peer_id", 0), 0) != sender:
		print("[mp.diag] speed_vote REJECT seat=%d sender=%d" % [seat, sender])
		return
	rpc("rpc_speed_vote_apply", seat, speed)


@rpc("authority", "reliable", "call_local")
func rpc_speed_vote_apply(seat: int, speed: float) -> void:
	speed_vote_received.emit(seat, speed)


func broadcast_doomsday_play(attacker_seat: int, loser_seat: int, logic_tick: int) -> void:
	if not is_host:
		return
	if multiplayer.has_multiplayer_peer() and needs_stage_barrier():
		rpc("rpc_doomsday_play", attacker_seat, loser_seat, logic_tick)
	else:
		doomsday_play_received.emit(attacker_seat, loser_seat, logic_tick)


@rpc("authority", "reliable", "call_local")
func rpc_doomsday_play(attacker_seat: int, loser_seat: int, logic_tick: int) -> void:
	doomsday_play_received.emit(attacker_seat, loser_seat, logic_tick)


@rpc("authority", "reliable", "call_local")
func rpc_match_report(report: Dictionary) -> void:
	match_report_received.emit(report)


## Host-only escape hatch: caller already assembled every contestant's row (e.g. merged
## locally instead of via the per-seat summary gate) — build the §7 report and broadcast
## it directly, skipping `begin_match_report_collection`'s barrier/timeout bookkeeping.
func host_build_and_broadcast_match_report(players: Array) -> void:
	if not is_host:
		return
	var report: Dictionary = NullsecSettlement.make_match_report(match_id, local_seat, players)
	if multiplayer.has_multiplayer_peer():
		rpc("rpc_match_report", report)
	else:
		match_report_received.emit(report)


func begin_prepare_done_gate() -> void:
	## Prepare timers running: collect who finished; release enter-battle together.
	if not needs_stage_barrier():
		return
	if not is_host and multiplayer.has_multiplayer_peer():
		_prepare_done_gate_open = true
		print("[mp.diag] prep_done_gate client wait")
		return
	if _prepare_done_gate_open:
		_check_prepare_done_ready()
		return
	_prepare_done_gate_open = true
	_prepare_done_seats.clear()
	_auto_mark_cohort_inactive(_prepare_done_seats)
	print("[mp.diag] prep_done_gate_begin host=%s cohort=[%s]" % [is_host, _cohort_csv()])
	SessionDiagnostics.log("mp.barrier", "prep_done_begin cohort=[%s]" % _cohort_csv())
	_check_prepare_done_ready()


func report_local_prepare_done() -> void:
	if not needs_stage_barrier() or local_seat < 0:
		return
	## Do not advance prepare→battle barrier before the prepare clock has armed
	## (R1 spend-gate / post-battle wait). Early reports caused host/guest deadlock.
	if not prepare_clock_armed:
		_pending_prepare_done_report = true
		print("[mp.diag] prep_done_report PENDING (clock not armed) seat=%d" % local_seat)
		return
	_pending_prepare_done_report = false
	if _local_prep_done_sent:
		print("[mp.diag] prep_done_report SKIP duplicate seat=%d" % local_seat)
		return
	if not _prepare_done_gate_open:
		begin_prepare_done_gate()
	print("[mp.diag] prep_done_report seat=%d host=%s" % [local_seat, is_host])
	SessionDiagnostics.log("mp.prep_done_report", "seat=%d" % local_seat)
	_local_prep_done_sent = true
	if is_host or not multiplayer.has_multiplayer_peer():
		_mark_prepare_done(local_seat)
	else:
		## Do NOT mark host-side completion locally — wait for rpc_enter_battle.
		rpc_id(1, "rpc_prepare_stage_done", local_seat)


@rpc("any_peer", "reliable")
func rpc_prepare_stage_done(seat: int) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if TypedVariant.as_int(_seat_row(seat).get("peer_id", 0), 0) != sender:
		print("[mp.diag] prep_done REJECT seat=%d sender=%d" % [seat, sender])
		return
	if not prepare_clock_armed:
		## Queue — never drop; flush on arm (fixes 1v1 softlock).
		_early_prep_done_seats[seat] = true
		print("[mp.diag] prep_done QUEUED (host clock not armed) seat=%d" % seat)
		return
	if not _prepare_done_gate_open:
		begin_prepare_done_gate()
	print("[mp.diag] prep_done ACCEPT seat=%d" % seat)
	_mark_prepare_done(seat)


func _mark_prepare_done(seat: int) -> void:
	_prepare_done_seats[seat] = true
	_check_prepare_done_ready()


## Host-authoritative fallback: if host timer finished and every *other*
## contestant already reported, mark self and release even if local report raced.
func _check_prepare_done_ready() -> void:
	if not is_host or not _prepare_done_gate_open:
		return
	_auto_mark_cohort_inactive(_prepare_done_seats)
	var missing: PackedStringArray = PackedStringArray()
	for i: int in _iter_prepare_cohort():
		if TypedVariant.as_bool(_seat_row(i).get("is_ai", false), false):
			continue
		if not TypedVariant.as_bool(_prepare_done_seats.get(i, false), false):
			missing.append(str(i))
	_log_barrier_state("prep_done", missing)
	if not missing.is_empty():
		print("[mp.diag] prep_done_wait missing=[%s] cohort=[%s]" % [",".join(missing), _cohort_csv()])
		return
	_prepare_done_gate_open = false
	print("[mp.diag] prep_done_ALL_READY -> enter_battle cohort=[%s]" % _cohort_csv())
	SessionDiagnostics.log("mp.barrier", "prep_done_all cohort=[%s]" % _cohort_csv())
	if multiplayer.has_multiplayer_peer():
		rpc("rpc_enter_battle")
	enter_battle_released.emit()


@rpc("authority", "reliable")
func rpc_enter_battle() -> void:
	print("[mp.diag] rpc_enter_battle received")
	SessionDiagnostics.log("mp.rpc_enter_battle", "")
	enter_battle_released.emit()


## --- Lobby seat「功能」: transfer / urge ---

func transfer_host_to_seat(seat: int) -> void:
	if not is_host:
		return
	if seat < 0 or seat >= seats.size() or seat == local_seat:
		return
	var row: Dictionary = _seat_row(seat)
	if not TypedVariant.as_bool(row.get("occupied", false), false):
		return
	if TypedVariant.as_bool(row.get("ghost", false), false):
		return
	if TypedVariant.as_bool(row.get("is_ai", false), false):
		lobby_notice.emit("不能转移房主给人机")
		return
	var plat: String = str(row.get("platform", "pc"))
	if plat == "mobile" and not is_lowsec(security_mode) and player_count() > 5:
		lobby_notice.emit("手机新房主参赛超过 5 人，无法转让")
		return
	var peer_id: int = TypedVariant.as_int(row.get("peer_id", 0), 0)
	var hip: String = str(row.get("endpoint_ip", ""))
	if peer_id <= 0 or hip == "" or hip == "0.0.0.0":
		lobby_notice.emit("目标端点不可用")
		return
	host_migrate_generation += 1
	_pending_transfer_seat = seat
	_pending_transfer_gen = host_migrate_generation
	if last_match_payload.is_empty():
		last_match_payload = {}
	last_match_payload["host_seat"] = seat
	last_match_payload["host_migrate_generation"] = host_migrate_generation
	var hport: int = port_for_code(room_code)
	rpc("rpc_host_transfer_pending", seat, host_migrate_generation, hip, hport)
	rpc_id(peer_id, "rpc_transfer_host_promote", host_migrate_generation, seat)
	call_deferred("_complete_outgoing_host_transfer", hip, hport)


@rpc("any_peer", "reliable")
func rpc_host_transfer_pending(seat: int, generation: int, host_ip: String, host_port: int) -> void:
	_pending_transfer_seat = seat
	_pending_transfer_gen = generation
	host_migrate_generation = generation
	if host_ip != "":
		last_known_host_ip = host_ip
	if last_match_payload.is_empty():
		last_match_payload = {}
	last_match_payload["host_seat"] = seat
	last_match_payload["host_migrate_generation"] = generation
	## host_port reserved for clients that reconnect on disconnect.
	if host_port > 0:
		pass


@rpc("any_peer", "reliable")
func rpc_transfer_host_promote(generation: int, seat: int) -> void:
	if local_seat != seat:
		return
	host_migrate_generation = generation
	opening_host_platform = detect_local_platform()
	host_player_cap = detect_host_player_cap()
	_promote_self_to_host(seat)
	_pending_transfer_seat = -1


func _complete_outgoing_host_transfer(hip: String, hport: int) -> void:
	is_host = false
	var keep_seat: int = local_seat
	var gen: int = host_migrate_generation
	var new_host: int = TypedVariant.as_int(last_match_payload.get("host_seat", -1), -1)
	_teardown_peer_only()
	pending_rejoin_seat = keep_seat
	pending_rejoin_secret = session_secret
	## Match scene flips remote_watch_only via this signal (same path as failover).
	host_migrated.emit(gen, new_host)
	var tree: SceneTree = get_tree()
	if tree == null or hip == "":
		_pending_transfer_seat = -1
		return
	tree.create_timer(0.35).timeout.connect(func() -> void:
		var err: Error = join(hip, hport, local_nick, rules_hash)
		_pending_transfer_seat = -1
		if err != OK:
			lobby_notice.emit("转让后重连失败")
	)


func urge_prepare(seat: int) -> void:
	if not is_host:
		return
	if seat < 0 or seat >= seats.size() or seat == local_seat:
		return
	var row: Dictionary = _seat_row(seat)
	if not TypedVariant.as_bool(row.get("occupied", false), false):
		return
	if TypedVariant.as_bool(row.get("ghost", false), false):
		return
	if is_spectate_race(str(row.get("titan_race", ""))):
		return
	if TypedVariant.as_bool(row.get("ready", false), false):
		return
	if TypedVariant.as_bool(row.get("is_ai", false), false):
		## AI auto-ready; nudge is a no-op notice locally.
		lobby_notice.emit("已催促人机席（人机会自动准备）")
		return
	var peer_id: int = TypedVariant.as_int(row.get("peer_id", 0), 0)
	if peer_id <= 0:
		return
	rpc_id(peer_id, "rpc_urge_prepare")
	lobby_notice.emit("已催促席位 %02d" % (seat + 1))


@rpc("authority", "reliable")
func rpc_urge_prepare() -> void:
	urge_prepare_received.emit()
	lobby_notice.emit("房主催促准备")


## Ask target seat for economy/fleet summary (MULTIPLAYER_PVP §4.2.2).
func request_scout_intel(target_seat: int, from_seat: int, from_nick: String, scout_ship_name: String) -> void:
	var row: Dictionary = _seat_row(target_seat)
	if row.is_empty() or not TypedVariant.as_bool(row.get("occupied", false), false):
		scout_intel_received.emit(target_seat, "?", {})
		return
	var target_nick: String = str(row.get("nick", "?"))
	var is_ai: bool = TypedVariant.as_bool(row.get("is_ai", false), false)
	var peer_id: int = TypedVariant.as_int(row.get("peer_id", 0), 0)
	## Local / AI / missing peer → host answers (or this client if alone).
	if is_ai or peer_id <= 0 or target_seat == local_seat:
		if is_host or not multiplayer.has_multiplayer_peer():
			scout_intel_asked.emit(from_seat, from_nick, scout_ship_name, multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0, target_seat)
		else:
			rpc_id(1, "rpc_scout_intel_ask", from_seat, from_nick, scout_ship_name, target_seat)
		return
	if peer_id == multiplayer.get_unique_id():
		scout_intel_asked.emit(from_seat, from_nick, scout_ship_name, peer_id, target_seat)
		return
	rpc_id(peer_id, "rpc_scout_intel_ask", from_seat, from_nick, scout_ship_name, target_seat)
	## Keep nick for reply formatting if peer never answers.
	_pending_scout_nick[target_seat] = target_nick


@rpc("any_peer", "reliable")
func rpc_scout_intel_ask(from_seat: int, from_nick: String, scout_ship_name: String, target_seat: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	## Host may be asked to answer for AI seats.
	if is_host and TypedVariant.as_bool(_seat_row(target_seat).get("is_ai", false), false):
		scout_intel_asked.emit(from_seat, from_nick, scout_ship_name, sender, target_seat)
		return
	if target_seat != local_seat:
		return
	scout_intel_asked.emit(from_seat, from_nick, scout_ship_name, sender, target_seat)


func reply_scout_intel(to_peer: int, target_seat: int, target_nick: String, summary: Dictionary) -> void:
	if to_peer <= 0 or not multiplayer.has_multiplayer_peer() or to_peer == multiplayer.get_unique_id():
		scout_intel_received.emit(target_seat, target_nick, summary)
		return
	rpc_id(to_peer, "rpc_scout_intel_reply", target_seat, target_nick, summary)


@rpc("any_peer", "reliable")
func rpc_scout_intel_reply(target_seat: int, target_nick: String, summary: Dictionary) -> void:
	var nick: String = target_nick if target_nick != "" else str(_pending_scout_nick.get(target_seat, "?"))
	_pending_scout_nick.erase(target_seat)
	scout_intel_received.emit(target_seat, nick, summary)


## --- SEMI_ASYNC §3.0b opening pack + §3.0c probe ---

@rpc("authority", "reliable")
func rpc_opening_pack(bytes: PackedByteArray, pack_hash: String) -> void:
	if is_host:
		return
	var unpacked: Dictionary = OpeningPack.unpack(bytes)
	var got: String = str(unpacked.get("pack_hash", ""))
	NetSessionDebug.log_pack("opening_rx", {
		"pack_hash": pack_hash,
		"got_hash": got,
		"bytes": bytes.size(),
		"ships_hash": str(unpacked.get("ships_hash", "")),
	})
	if got != "" and got == pack_hash:
		rpc_id(1, "rpc_opening_pack_ack", pack_hash)
	else:
		NetSessionDebug.log_event("net.ack.opening_fail", "expected=%s got=%s" % [pack_hash, got])


@rpc("any_peer", "reliable")
func rpc_opening_pack_ack(pack_hash: String) -> void:
	if not is_host:
		return
	NetSessionDebug.log_event(
		"net.ack.opening",
		"from=%d hash=%s" % [multiplayer.get_remote_sender_id(), pack_hash.substr(0, mini(16, pack_hash.length()))]
	)


func _send_probe() -> void:
	if not multiplayer or not multiplayer.has_multiplayer_peer():
		return
	_probe_sent_msec = Time.get_ticks_msec()
	if is_host:
		for p: int in multiplayer.get_peers():
			rpc_id(p, "rpc_probe_ping", _probe_sent_msec)
	else:
		rpc_id(1, "rpc_probe_ping", _probe_sent_msec)


@rpc("any_peer", "unreliable")
func rpc_probe_ping(sent_msec: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	rpc_id(sender, "rpc_probe_pong", sent_msec)


@rpc("any_peer", "unreliable")
func rpc_probe_pong(sent_msec: int) -> void:
	var rtt: int = maxi(0, Time.get_ticks_msec() - sent_msec)
	var sender: int = multiplayer.get_remote_sender_id()
	for i: int in range(seats.size()):
		var row: Dictionary = _seat_row(i)
		if TypedVariant.as_int(row.get("peer_id", 0), 0) == sender:
			row["rtt_ms"] = rtt
			break
	if local_seat >= 0 and not is_host and sender == 1:
		_seat_row(local_seat)["rtt_ms"] = rtt
	elif local_seat >= 0 and is_host:
		_seat_row(local_seat)["rtt_ms"] = 0
	if is_host and _rtt_ui_acc >= 2.0:
		_rtt_ui_acc = 0.0
		_broadcast_seats()
