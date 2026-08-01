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

## Discovery / announce port (SEMI_ASYNC §7.5 LAN). Game listen = BASE_PORT + code.
const BASE_PORT := 24567
const DEFAULT_PORT := BASE_PORT ## Alias: beacon port; do not create_server here.
const MAX_CLIENTS := 19
const SEAT_TOTAL := 20
const TITAN_RACE_SPECTATE := "spectate"
const TITAN_RACES := ["caldari", "gallente", "minmatar", "amarr"]

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
var last_match_payload: Dictionary = {}
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


func listen_port() -> int:
	return _listen_port if _listen_port > 0 else port_for_code(maxi(room_code, 1))


func _ready() -> void:
	rules_hash = MatchRng.compute_rules_hash()
	_init_empty_seats()


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
		})


func host_public(code: int, nick: String) -> Error:
	is_host = true
	is_private = false
	private_code = ""
	room_code = clampi(code, 1, 9999)
	local_nick = nick
	host_player_cap = detect_host_player_cap()
	return _start_host()


func host_private(code: String, nick: String) -> Error:
	is_host = true
	is_private = true
	private_code = code.strip_edges()
	room_code = code_for_private(private_code)
	local_nick = nick
	host_player_cap = detect_host_player_cap()
	return _start_host()


func join(address: String, port: int, nick: String, expect_hash: String = "") -> Error:
	close()
	is_host = false
	local_nick = nick
	local_seat = -1
	match_started = false
	last_match_payload = {}
	host_ships_hash = ""
	_listen_port = port
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
	rpc_id(id, "rpc_handshake", rules_hash, room_code, is_private, private_code, host_player_cap, match_started, DataStore.ships_table_hash())


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
	_broadcast_seats()


func _on_connected_to_server() -> void:
	rpc_id(1, "rpc_request_join", local_nick, rules_hash)


func _on_server_disconnected() -> void:
	rejected.emit("server disconnected")


@rpc("any_peer", "reliable")
func rpc_handshake(server_hash: String, code: int, priv: bool, priv_code: String = "", player_cap: int = 20, in_match: bool = false, ships_hash: String = "") -> void:
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


@rpc("any_peer", "reliable")
func rpc_request_join(nick: String, client_hash: String) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if client_hash != rules_hash:
		rpc_id(sender, "rpc_join_rejected", "rulesHash mismatch")
		return
	var seat := _first_free_seat()
	if seat < 0:
		rpc_id(sender, "rpc_join_rejected", "room full")
		return
	_occupy_seat(seat, nick, sender, false)
	if match_started:
		seats[seat]["titan_race"] = TITAN_RACE_SPECTATE
		seats[seat]["ready"] = true
		rpc_id(sender, "rpc_join_accepted", seat, true)
		_broadcast_seats()
		## Mid-join watcher needs the host table before it simulates anything.
		rpc_id(sender, "rpc_ships_table", DataStore.export_ships_table(), true)
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


func add_ai_player(nick: String = "人机玩家") -> bool:
	if not is_host or match_started:
		return false
	if player_count() >= host_player_cap:
		return false
	var seat := _first_free_seat()
	if seat < 0:
		return false
	_occupy_seat(seat, nick, 0, true)
	_broadcast_seats()
	return true


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
	_broadcast_seats()


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
		if is_ai:
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
	return player_count() < host_player_cap


func _apply_titan(seat: int, race: String) -> void:
	seats[seat]["titan_race"] = race
	if race == "":
		seats[seat]["ready"] = false
	elif is_spectate_race(race):
		seats[seat]["ready"] = true
	elif bool(seats[seat].get("is_ai", false)) and is_player_race(race):
		seats[seat]["ready"] = true
	elif not is_player_race(race):
		seats[seat]["ready"] = false


func set_local_ready(is_ready: bool) -> void:
	if local_seat < 0:
		return
	var race := str(seats[local_seat].get("titan_race", ""))
	if is_ready and not is_player_race(race):
		return
	seats[local_seat]["ready"] = is_ready
	if is_host:
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


@rpc("any_peer", "reliable")
func rpc_set_ready(seat: int, is_ready: bool) -> void:
	if not is_host:
		return
	if seat < 0 or seat >= seats.size():
		return
	if is_ready and not is_player_race(str(seats[seat].get("titan_race", ""))):
		return
	seats[seat]["ready"] = is_ready
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
	var payload := {"match_seed": seed_v, "rules_hash": rules_hash, "seats": all_occupied}
	match_started = true
	last_match_payload = payload.duplicate(true)
	## Ship table travels only on match entry, ahead of the start payload (§3.7).
	rpc("rpc_ships_table", DataStore.export_ships_table(), false)
	rpc("rpc_match_start", payload)
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
	rpc("rpc_ships_table", DataStore.export_ships_table(), true)


@rpc("authority", "reliable")
func rpc_ships_table(table: Dictionary, mid_match: bool = false) -> void:
	if is_host:
		return
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
	match_start.emit(payload)


func close() -> void:
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
	is_host = false
	local_seat = -1
	match_started = false
	last_match_payload = {}
	host_ships_hash = ""
	DataStore.clear_host_ships_override()
	_init_empty_seats()
