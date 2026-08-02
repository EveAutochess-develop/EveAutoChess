extends Node
class_name NullsecNetSession
## ENet LAN lobby — host/join, seat sync, rulesHash gate, LAN beacon ads.

signal seat_sync(seats: Array)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal rejected(reason: String)
signal match_start(payload: Dictionary)
signal join_accepted(seat: int, in_match: bool)
## SEMI_ASYNC_NETPLAY §3.7 — ship table authority.
signal ships_mismatch(host_hash: String)
signal ships_override_applied(mid_match: bool)
## SEMI_ASYNC §3 authority stream (combat + spectate).
signal authority_snapshot_received(snap: Dictionary)
signal battle_report_received(report: Dictionary)
signal anticheat_notice_received(message: String)
## SEMI_ASYNC §5.3a — rejoin / host migrate.
signal host_migrated(generation: int, new_host_seat: int)
signal match_terminated_host_lost(reason: String)
signal rejoin_accepted(seat: int)

## Discovery / announce port (SEMI_ASYNC §7.5 LAN). Game listen = BASE_PORT + code.
const BASE_PORT := 24567
const DEFAULT_PORT := BASE_PORT ## Alias: beacon port; do not create_server here.
const MAX_CLIENTS := 19
const SEAT_TOTAL := 20
const TITAN_RACE_SPECTATE := "spectate"
const TITAN_RACES := ["caldari", "gallente", "minmatar", "amarr"]
const SECURITY_NULLSEC := "nullsec"
const SECURITY_LOWSEC := "lowsec"

signal security_mode_changed(mode: String)

var is_host: bool = false
var room_code: int = 0 ## 1..9999 public (also private port index)
var is_private: bool = false
var private_code: String = ""
var rules_hash: String = ""
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
var _peer: ENetMultiplayerPeer
var _listen_port: int = 0
var _beacon: LanBeacon = null


static func port_for_code(code: int) -> int:
	return BASE_PORT + clampi(code, 1, 9999)


static func code_for_private(priv: String) -> int:
	## Fold private code into 1..9999 for listen-port binding.
	var h := absi(hash(priv.strip_edges().to_lower()))
	return (h % 9999) + 1


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
	if not match_started or _migrating:
		return
	_ticket_heartbeat_acc += delta
	if _ticket_heartbeat_acc < 5.0:
		return
	_ticket_heartbeat_acc = 0.0
	write_rejoin_ticket()


func _init_empty_seats() -> void:
	seats.clear()
	for i in range(SEAT_TOTAL):
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
		})


func host_public(code: int, nick: String) -> Error:
	is_host = true
	is_private = false
	private_code = ""
	room_code = clampi(code, 1, 9999)
	local_nick = nick
	host_player_cap = detect_host_player_cap()
	security_mode = SECURITY_NULLSEC
	return _start_host()


func host_private(code: String, nick: String) -> Error:
	is_host = true
	is_private = true
	private_code = code.strip_edges()
	room_code = code_for_private(private_code)
	local_nick = nick
	host_player_cap = detect_host_player_cap()
	security_mode = SECURITY_NULLSEC
	return _start_host()


func join(address: String, port: int, nick: String, expect_hash: String = "") -> Error:
	## Preserve rejoin credentials across close() (SEMI_ASYNC §5.3a).
	var keep_seat := pending_rejoin_seat
	var keep_secret := pending_rejoin_secret
	var keep_session := session_secret
	var keep_mid := match_id
	var keep_plat := opening_host_platform
	var keep_ships_hash := opening_host_ships_hash
	var keep_ships := opening_host_ships.duplicate(true)
	var keep_gen := host_migrate_generation
	var keep_sec := security_mode
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
	_listen_port = port
	last_known_host_ip = address
	if expect_hash != "" and expect_hash != rules_hash:
		rejected.emit("rulesHash mismatch")
		return ERR_INVALID_PARAMETER
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


func _start_host() -> Error:
	close()
	is_host = true
	match_started = false
	last_match_payload = {}
	_ensure_session_secret()
	opening_host_platform = detect_local_platform()
	last_known_host_ip = _best_local_ip()
	_listen_port = port_for_code(room_code)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(_listen_port, MAX_CLIENTS)
	if err != OK:
		_peer = null
		_listen_port = 0
		return err
	multiplayer.multiplayer_peer = _peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_occupy_seat(0, local_nick, multiplayer.get_unique_id(), false)
	seats[0]["platform"] = opening_host_platform
	seats[0]["endpoint_ip"] = last_known_host_ip
	seats[0]["endpoint_port"] = _listen_port
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
		is_private,
		private_code,
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
	for i in range(seats.size()):
		if int(seats[i].get("peer_id", 0)) == id:
			if match_started and is_player_race(str(seats[i].get("titan_race", ""))):
				mark_seat_ghost(i)
			else:
				seats[i]["occupied"] = false
				seats[i]["nick"] = ""
				seats[i]["peer_id"] = 0
				seats[i]["ready"] = false
				seats[i]["is_ai"] = false
				seats[i]["titan_race"] = ""
				seats[i]["ghost"] = false
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
		pending_rejoin_secret
	)


func _on_server_disconnected() -> void:
	if match_started:
		_begin_host_migration()
	else:
		rejected.emit("server disconnected")


@rpc("any_peer", "reliable")
func rpc_handshake(
	server_hash: String,
	code: int,
	priv: bool,
	priv_code: String = "",
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
		rejected.emit("rulesHash mismatch")
		multiplayer.multiplayer_peer = null
		return
	room_code = code
	is_private = priv
	private_code = priv_code
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
	secret: String = ""
) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if client_hash != rules_hash:
		rpc_id(sender, "rpc_join_rejected", "rulesHash mismatch")
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
		var reclaim_payload := _payload_for_spectate_join()
		reclaim_payload["mid_join_spectate"] = false
		reclaim_payload["rejoin"] = true
		if not reclaim_payload.is_empty():
			rpc_id(sender, "rpc_match_start", reclaim_payload)
		_broadcast_seats()
		return
	var seat := _first_free_seat()
	if seat < 0:
		rpc_id(sender, "rpc_join_rejected", "room full")
		return
	_occupy_seat(seat, nick, sender, false)
	seats[seat]["platform"] = platform if platform != "" else detect_local_platform()
	_capture_peer_endpoint(seat, sender)
	if match_started:
		seats[seat]["titan_race"] = TITAN_RACE_SPECTATE
		seats[seat]["ready"] = true
		rpc_id(sender, "rpc_join_accepted", seat, true)
		_broadcast_seats()
		## Mid-join watcher needs the host table before it simulates anything.
		rpc_id(sender, "rpc_ships_table", _authority_ships_table(), true)
		var payload := _payload_for_spectate_join()
		if not payload.is_empty():
			rpc_id(sender, "rpc_match_start", payload)
		return
	rpc_id(sender, "rpc_join_accepted", seat, false)
	_broadcast_seats()


@rpc("authority", "reliable")
func rpc_join_rejected(reason: String) -> void:
	rejected.emit(reason)


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
	for i in range(mini(SEAT_TOTAL, seats.size())):
		if not bool(seats[i].get("occupied", false)):
			return i
	return -1


func occupied_count() -> int:
	var n := 0
	for s in seats:
		if bool(s.get("occupied", false)):
			n += 1
	return n


func player_count() -> int:
	var n := 0
	for s in seats:
		if not bool(s.get("occupied", false)):
			continue
		if is_player_race(str(s.get("titan_race", ""))):
			n += 1
	return n


func local_is_spectator() -> bool:
	if local_seat < 0 or local_seat >= seats.size():
		return false
	return is_spectate_race(str(seats[local_seat].get("titan_race", "")))


func _occupy_seat(seat: int, nick: String, peer_id: int, is_ai: bool) -> void:
	seats[seat]["occupied"] = true
	seats[seat]["nick"] = nick
	seats[seat]["peer_id"] = peer_id
	seats[seat]["is_ai"] = is_ai
	seats[seat]["ready"] = false
	seats[seat]["titan_race"] = ""
	seats[seat]["ghost"] = false
	if not seats[seat].has("platform"):
		seats[seat]["platform"] = ""
	if not seats[seat].has("endpoint_ip"):
		seats[seat]["endpoint_ip"] = ""
	if not seats[seat].has("endpoint_port"):
		seats[seat]["endpoint_port"] = 0


func add_ai_player(nick: String = "人机玩家") -> bool:
	if not is_host or match_started:
		return false
	## Lowsec: may still add seats; ready gate blocks start while >2 titans selected.
	if not is_lowsec(security_mode) and player_count() >= host_player_cap:
		return false
	var seat := _first_free_seat()
	if seat < 0:
		return false
	_occupy_seat(seat, nick, 0, true)
	_broadcast_seats()
	return true


func set_security_mode(mode: String) -> void:
	if not is_host or match_started:
		return
	var next := SECURITY_LOWSEC if is_lowsec(mode) else SECURITY_NULLSEC
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
	var changed := false
	for i in range(seats.size()):
		if not bool(seats[i].get("occupied", false)):
			continue
		if not is_player_race(str(seats[i].get("titan_race", ""))):
			continue
		if bool(seats[i].get("ready", false)):
			seats[i]["ready"] = false
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
	var changed := false
	for i in range(seats.size()):
		if not bool(seats[i].get("occupied", false)):
			continue
		if not bool(seats[i].get("is_ai", false)):
			continue
		if bool(seats[i].get("ghost", false)):
			continue
		if not is_player_race(str(seats[i].get("titan_race", ""))):
			continue
		if bool(seats[i].get("ready", false)):
			continue
		seats[i]["ready"] = true
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
	var peer_id := int(seats[seat].get("peer_id", 0))
	seats[seat]["occupied"] = false
	seats[seat]["nick"] = ""
	seats[seat]["peer_id"] = 0
	seats[seat]["is_ai"] = false
	seats[seat]["ready"] = false
	seats[seat]["titan_race"] = ""
	seats[seat]["ghost"] = false
	if peer_id > 0 and multiplayer.has_multiplayer_peer() and _peer:
		_peer.disconnect_peer(peer_id)
	_sync_lobby_ready_gates()
	_broadcast_seats()
	_try_start()


func mark_seat_ghost(seat: int) -> void:
	if seat < 0 or seat >= seats.size():
		return
	if not bool(seats[seat].get("occupied", false)):
		return
	seats[seat]["ghost"] = true
	seats[seat]["ready"] = false
	seats[seat]["peer_id"] = 0
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
	var sender := multiplayer.get_remote_sender_id()
	if seat < 0 or seat >= seats.size():
		return
	if int(seats[seat].get("peer_id", 0)) != sender:
		return
	mark_seat_ghost(seat)


func clear_ghosts_after_settlement() -> void:
	for i in range(seats.size()):
		if bool(seats[i].get("ghost", false)):
			seats[i]["occupied"] = false
			seats[i]["nick"] = ""
			seats[i]["peer_id"] = 0
			seats[i]["is_ai"] = false
			seats[i]["ready"] = false
			seats[i]["titan_race"] = ""
			seats[i]["ghost"] = false
	_broadcast_seats()


func set_local_titan(race: String) -> void:
	if local_seat < 0:
		return
	set_seat_titan(local_seat, race)


func set_seat_titan(seat: int, race: String) -> void:
	if seat < 0 or seat >= seats.size():
		return
	if not bool(seats[seat].get("occupied", false)):
		return
	if match_started:
		return
	var is_ai := bool(seats[seat].get("is_ai", false))
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
	var cur := str(seats[seat].get("titan_race", ""))
	if is_player_race(cur):
		return true ## switching titan keeps same player slot
	## Lowsec: allow >2 titan picks; ready is cleared/blocked until back to 2.
	if is_lowsec(security_mode):
		return true
	return player_count() < host_player_cap


func _apply_titan(seat: int, race: String) -> void:
	seats[seat]["titan_race"] = race
	if race == "":
		seats[seat]["ready"] = false
	elif is_spectate_race(race):
		seats[seat]["ready"] = true
	elif bool(seats[seat].get("is_ai", false)) and is_player_race(race):
		## Immediate attempt; `_sync_lobby_ready_gates` re-tries when the gate opens later.
		seats[seat]["ready"] = not lowsec_ready_blocked()
	elif not is_player_race(race):
		seats[seat]["ready"] = false
	_sync_lobby_ready_gates()


func set_local_ready(is_ready: bool) -> void:
	if local_seat < 0:
		return
	var race := str(seats[local_seat].get("titan_race", ""))
	if is_ready and not is_player_race(race):
		return
	if is_ready and lowsec_ready_blocked():
		return
	seats[local_seat]["ready"] = is_ready
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
	var sender := multiplayer.get_remote_sender_id()
	if int(seats[seat].get("peer_id", 0)) != sender:
		return
	if bool(seats[seat].get("is_ai", false)):
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
	if is_ready and not is_player_race(str(seats[seat].get("titan_race", ""))):
		return
	if is_ready and lowsec_ready_blocked():
		_sync_lobby_ready_gates()
		_broadcast_seats()
		return
	seats[seat]["ready"] = is_ready
	_sync_lobby_ready_gates()
	_broadcast_seats()
	_try_start()


func _try_start() -> void:
	if match_started:
		return
	var players: Array = []
	for s in seats:
		if not bool(s.get("occupied", false)):
			continue
		var race := str(s.get("titan_race", ""))
		if is_spectate_race(race):
			continue
		players.append(s)
	if players.size() < 2:
		return
	if is_lowsec(security_mode) and players.size() != 2:
		return
	for s in players:
		if not is_player_race(str(s.get("titan_race", ""))):
			return
		if not bool(s.get("ready", false)):
			return
	var seed_v := int(Time.get_unix_time_from_system()) ^ hash(room_code)
	var all_occupied: Array = []
	for s in seats:
		if bool(s.get("occupied", false)):
			all_occupied.append(s)
	_ensure_session_secret()
	_freeze_opening_host_ships(DataStore.export_ships_table())
	if match_id == "":
		match_id = "%d-%s" % [seed_v, session_secret.substr(0, mini(8, session_secret.length()))]
	var payload := {
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
	## Ship table travels only on match entry, ahead of the start payload (§3.7 / 1A freeze).
	rpc("rpc_ships_table", _authority_ships_table(), false)
	rpc("rpc_match_start", payload)
	write_rejoin_ticket()
	match_start.emit(payload)


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
	_freeze_opening_host_ships(table)
	if DataStore.apply_host_ships_override(table):
		ships_override_applied.emit(mid_match)


func store_match_assignments(assignments: Dictionary) -> void:
	if last_match_payload.is_empty():
		last_match_payload = {}
	last_match_payload["assignments"] = assignments.duplicate(true)


func _payload_for_spectate_join() -> Dictionary:
	var p := last_match_payload.duplicate(true)
	if p.is_empty():
		p = {"match_seed": int(Time.get_unix_time_from_system()), "rules_hash": rules_hash}
	var all_occupied: Array = []
	for s in seats:
		if bool(s.get("occupied", false)):
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
	host_migrate_generation = int(payload.get("host_migrate_generation", host_migrate_generation))
	write_rejoin_ticket()
	match_start.emit(payload)


func broadcast_authority_snapshot(snap: Dictionary) -> void:
	if not is_host or not multiplayer.has_multiplayer_peer():
		return
	rpc("rpc_authority_snapshot", snap)


@rpc("authority", "reliable")
func rpc_authority_snapshot(snap: Dictionary) -> void:
	if is_host:
		return
	authority_snapshot_received.emit(snap)


func broadcast_battle_report(report: Dictionary) -> void:
	if not is_host or not multiplayer.has_multiplayer_peer():
		return
	rpc("rpc_battle_report", report)


@rpc("authority", "reliable")
func rpc_battle_report(report: Dictionary) -> void:
	if is_host:
		return
	battle_report_received.emit(report)


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
	var ip := last_known_host_ip if last_known_host_ip != "" else _best_local_ip()
	if ip == "" or ip == "0.0.0.0":
		ip = "127.0.0.1"
	var room := private_code if is_private else "%04d" % room_code
	return InviteBlobHelper.encode(ip, listen_port(), room, rules_hash, {
		"private": is_private,
		"security_mode": security_mode,
	})


func clear_rejoin_ticket() -> void:
	NullsecRejoinTicket.clear()


func write_rejoin_ticket() -> void:
	NullsecRejoinTicket.write_from_session(self)


func _ensure_session_secret() -> void:
	if session_secret != "":
		return
	var c := Crypto.new()
	session_secret = Marshalls.raw_to_base64(c.generate_random_bytes(16))


func _best_local_ip() -> String:
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.begins_with("127.") or s.find(":") >= 0:
			continue
		return s
	return "127.0.0.1"


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
	seats[seat]["endpoint_ip"] = str(ep.get_remote_address())
	seats[seat]["endpoint_port"] = int(ep.get_remote_port())


func _try_reclaim_ghost(seat: int, nick: String, peer_id: int, platform: String) -> bool:
	if seat < 0 or seat >= seats.size():
		return false
	var row: Dictionary = seats[seat]
	if not bool(row.get("occupied", false)):
		return false
	if not bool(row.get("ghost", false)):
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
	for s in seat_rows:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = s
		if not bool(row.get("occupied", false)):
			continue
		if bool(row.get("ghost", false)):
			continue
		if bool(row.get("is_ai", false)):
			continue
		if not is_player_race(str(row.get("titan_race", ""))):
			continue
		candidates.append(int(row.get("seat_id", -1)))
	candidates = candidates.filter(func(x): return int(x) >= 0)
	if candidates.is_empty():
		return -1
	var same: Array = []
	for sid in candidates:
		var plat := ""
		for s in seat_rows:
			if typeof(s) == TYPE_DICTIONARY and int(s.get("seat_id", -2)) == int(sid):
				plat = str(s.get("platform", ""))
				break
		if plat == str(opener_plat):
			same.append(int(sid))
	if not same.is_empty():
		candidates = same
	elif str(opener_plat) == "pc":
		return -1
	candidates.sort()
	var parts := PackedStringArray()
	for sid in candidates:
		parts.append(str(int(sid)))
	var key := "%d|host_migrate|%d|%s" % [int(match_seed), int(generation), ",".join(parts)]
	var h := absi(hash(key))
	return int(candidates[h % candidates.size()])


func _begin_host_migration() -> void:
	if _migrating:
		return
	_migrating = true
	var old_host := int(last_match_payload.get("host_seat", 0))
	if old_host >= 0 and old_host < seats.size():
		seats[old_host]["ghost"] = true
		seats[old_host]["peer_id"] = 0
		seats[old_host]["ready"] = false
	## Drop dead peer sockets but keep lobby/match fields for election.
	_teardown_peer_only()
	var gen := host_migrate_generation + 1
	var seed_v := int(last_match_payload.get("match_seed", 0))
	var elected := elect_new_host_seat(seats, opening_host_platform, seed_v, gen)
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
	var hip := ""
	if elected >= 0 and elected < seats.size():
		hip = str(seats[elected].get("endpoint_ip", ""))
	## New host listens on room code port (not the old client ephemeral source port).
	var hport := port_for_code(room_code)
	if hip == "" or hip == "0.0.0.0":
		_terminate_match_host_lost("房主掉线，对局终止")
		return
	pending_rejoin_seat = local_seat
	pending_rejoin_secret = session_secret
	var nick := local_nick
	var keep_seat := local_seat
	var keep_payload := last_match_payload.duplicate(true)
	var keep_seats := seats.duplicate(true)
	var err := join(hip, hport, nick, rules_hash)
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
	var err := _peer.create_server(_listen_port, MAX_CLIENTS)
	if err != OK:
		_peer = null
		_listen_port = 0
		_terminate_match_host_lost("房主掉线，对局终止")
		return
	multiplayer.multiplayer_peer = _peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	var uid := multiplayer.get_unique_id()
	if local_seat >= 0 and local_seat < seats.size():
		seats[local_seat]["peer_id"] = uid
		seats[local_seat]["ghost"] = false
		seats[local_seat]["platform"] = detect_local_platform()
		seats[local_seat]["endpoint_ip"] = last_known_host_ip
		seats[local_seat]["endpoint_port"] = _listen_port
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
	pending_rejoin_seat = -1
	pending_rejoin_secret = ""
	_migrating = false
	_ticket_heartbeat_acc = 0.0
	DataStore.clear_host_ships_override()
	_init_empty_seats()
