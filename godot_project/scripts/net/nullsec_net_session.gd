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
## MULTIPLAYER_MATCH_FLOW §5.2 — host matchups + last_rival memory for this round.
signal round_matchups_received(matchups: Dictionary, last_rival_by_seat: Dictionary, round_r: int)
signal lobby_notice(message: String)
## Lobby / transfer — is_host flipped (UI: 功能 / 加人机 / 安等).
signal host_role_changed(is_host_now: bool)
## SEMI_ASYNC §4.5 — any seat finished this round → remaining battles 4× + wall-clock draw.
signal seat_battle_finished(seat: int) ## Manned only — arms §4.5; AI barrier marks stay silent.
## All barrier humans reported battle_done — clear conditional wall draw (§4.5).
signal battle_done_all_ready()
## MULTIPLAYER_PVP §7 — combined end-of-match report (settlement rows + §7.1 titles).
signal match_report_received(report: Dictionary)
## MULTIPLAYER_PVP §7.0 — per-round standings (result / titles / WLD) for every contestant seat.
signal round_standings_received(standings: Dictionary)
## SEMI_ASYNC §4.5 — speed vote from a seat (after host validation).
signal speed_vote_received(seat: int, speed: float)
## MULTIPLAYER_PVP §6 — host-authoritative doomsday play cue.
signal doomsday_play_received(attacker_seat: int, loser_seat: int, logic_tick: int)

## Discovery / announce port (SEMI_ASYNC §7.5 LAN). Game listen = BASE_PORT + code.
const BASE_PORT: int = 24567
const DEFAULT_PORT: int = BASE_PORT ## Alias: beacon port; do not create_server here.
const MAX_CLIENTS: int = 19
const SEAT_TOTAL: int = 20
## SEMI_ASYNC §5.3a — ENet idle disconnect floor ≥10s (LAN default min was 5s).
const ENET_TIMEOUT_LIMIT: int = 32
const ENET_TIMEOUT_MIN_MS: int = 10000
const ENET_TIMEOUT_MAX_MS: int = 45000
const TITAN_RACE_SPECTATE: String = "spectate"
const TITAN_RACES: Array = [
	"caldari", "gallente", "minmatar", "amarr",
	## 势力泰坦仅天使征服者（MULTIPLAYER_PVP §2）；非七族各一项。
	"angel",
]
const SECURITY_NULLSEC: String = "nullsec"
const SECURITY_LOWSEC: String = "lowsec"

signal security_mode_changed(mode: String)

var is_host: bool = false
## Solo 多人联机演练：无 ENet，同一 NullsecRoomUI。
var offline_drill: bool = false
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
## SEMI_ASYNC §7.2 — STUN/UPnP mapped public IPv4 for invite reflexive (not turn_urls).
var last_known_reflexive_ip: String = ""
var last_known_reflexive_port: int = 0
var last_known_reflexive_via: String = ""
var pending_rejoin_seat: int = -1
var pending_rejoin_secret: String = ""
## Lobby seat0 handoff (SEMI_ASYNC §5.3a) — promote in flight on designate.
var _transfer_take_seat0_inflight: bool = false
var _migrating: bool = false
var _ticket_heartbeat_acc: float = 0.0
var _probe_acc: float = 0.0
var _rtt_ui_acc: float = 0.0
var _probe_sent_msec: int = 0
var _peer: ENetMultiplayerPeer = null
var _listen_port: int = 0
var _beacon: LanBeacon = null
## Opening offer/verify/commit (SEMI_ASYNC §3.0b). First start only.
var _opening_hs_active: bool = false
var _opening_hs_deadline: int = 0
var _opening_hs_verify: Dictionary = {}
var _opening_hs_payload: Dictionary = {}
var _opening_hs_offer: Dictionary = {}
var _opening_hs_rollback_ships: Dictionary = {}
var _opening_hs_rollback_hash: String = ""
var _opening_hs_rollback_match_id: String = ""
var _onnx_ready_cached: int = -1
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
## Once true, late seat summaries merge+rebroadcast — never clear/shrink players.
var _match_report_broadcast_done: bool = false
var _last_match_report_players: Array = []
## §7.0 per-round seat_round_summary → host stitch → rpc_round_standings.
var _round_summary_gate_open: bool = false
var _round_summary_seats: Dictionary = {}
var _round_summary_by_seat: Dictionary = {}
var _round_summary_round_id: int = -1
## Last broadcast standings by seat (WLD/titles) — enrich end-report rows.
var _last_standings_by_seat: Dictionary = {}
## Voluntary host transfer (lobby).
var _pending_transfer_seat: int = -1
var _kicked_local: bool = false
var _pending_transfer_gen: int = 0
var _host_promote_in_flight: bool = false


func _seat_row(seat: int) -> Dictionary:
	if seat < 0 or seat >= seats.size():
		return {}
	var row_v: Variant = seats[seat]
	if row_v is Dictionary:
		return row_v
	return {}


## SEMI_ASYNC §5.3a — lobby host UI + titan authority follow ENet server, not a stale flag.
func is_room_host() -> bool:
	if multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return true
	return is_host


func _set_host_role(want_host: bool) -> void:
	if is_host == want_host:
		return
	is_host = want_host
	host_role_changed.emit(want_host)


func _heal_host_role_from_peer() -> void:
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	_set_host_role(multiplayer.is_server())


func _bind_sender_to_held_seat(seat: int, sender: int) -> bool:
	## After transfer, human seats may be held with peer_id==0 until first lobby RPC.
	if sender <= 0 or seat < 0 or seat >= seats.size():
		return false
	var row: Dictionary = _seat_row(seat)
	if row.is_empty():
		return false
	if not TypedVariant.as_bool(row.get("occupied", false), false):
		return false
	if seat_is_proxy(row):
		return false
	var held: int = TypedVariant.as_int(row.get("peer_id", 0), 0)
	if held != 0 and held != sender:
		## Stale id after reconnect — rebind if old peer is gone.
		if _peer_id_still_connected(held):
			return false
		row["peer_id"] = sender
		_capture_peer_endpoint(seat, sender)
		return true
	if held == 0:
		row["peer_id"] = sender
		_capture_peer_endpoint(seat, sender)
	return true


func _peer_id_still_connected(peer_id: int) -> bool:
	if peer_id <= 0 or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	for p: int in multiplayer.get_peers():
		if p == peer_id:
			return true
	return false


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
	## SEMI_ASYNC — only OS mobile feature; touchscreen PCs must stay PC (cap 20).
	if OS.has_feature("mobile"):
		return 5
	return 20


static func detect_local_platform() -> String:
	if OS.has_feature("mobile"):
		return "mobile"
	return "pc"


static func seat_controller_of(row: Dictionary) -> String:
	var c: String = str(row.get("controller", ""))
	if c != "":
		return c
	if TypedVariant.as_bool(row.get("is_ai", false), false):
		return "legacy_ai"
	return "human"


static func seat_is_proxy(row: Dictionary) -> bool:
	return seat_controller_of(row) != "human"


func _seat_counts_for_spend_gate(row: Dictionary) -> bool:
	if not TypedVariant.as_bool(row.get("occupied", false), false):
		return false
	if TypedVariant.as_bool(row.get("ghost", false), false):
		return false
	if not is_player_race(str(row.get("titan_race", ""))):
		return false
	return not seat_is_proxy(row)


func _empty_seat_dict(i: int) -> Dictionary:
	return {
		"seat_id": i,
		"occupied": false,
		"nick": "",
		"peer_id": 0,
		"is_ai": false,
		"controller": "human",
		"owner_peer_id": 0,
		"owner_seat": -1,
		"owner_nick": "",
		"model_bundle_hash": "",
		"titan_race": "",
		"ready": false,
		"ghost": false,
		"platform": "",
		"endpoint_ip": "",
		"endpoint_port": 0,
		"rtt_ms": -1,
	}


func onnx_bundle_ready() -> bool:
	if _onnx_ready_cached >= 0:
		return _onnx_ready_cached == 1
	var pol: OnnxCpuPolicy = OnnxCpuPolicy.new()
	pol.try_autoload()
	_onnx_ready_cached = 1 if pol.nets_ready() else 0
	return _onnx_ready_cached == 1


func invalidate_onnx_bundle_cache() -> void:
	_onnx_ready_cached = -1
	restamp_local_owned_onnx_hashes(true)
	if not seats.is_empty():
		_broadcast_seats()


func local_owns_seat(seat: int) -> bool:
	if seat < 0:
		return false
	if local_seat >= 0 and seat == local_seat:
		return true
	var row: Dictionary = _seat_row(seat)
	if row.is_empty():
		return false
	return TypedVariant.as_int(row.get("owner_seat", -1), -1) == local_seat


func restamp_local_owned_onnx_hashes(force: bool = false) -> void:
	if local_seat < 0:
		return
	var need: bool = false
	for i: int in range(seats.size()):
		var row: Dictionary = _seat_row(i)
		if not TypedVariant.as_bool(row.get("occupied", false), false):
			continue
		if str(row.get("controller", "")) != "onnx":
			continue
		if TypedVariant.as_int(row.get("owner_seat", -1), -1) != local_seat:
			continue
		if force or str(row.get("model_bundle_hash", "")) == "":
			need = true
			break
	if not need:
		return
	var pol: OnnxCpuPolicy = OnnxCpuPolicy.new()
	pol.try_autoload()
	var h: String = pol.model_bundle_hash
	for i: int in range(seats.size()):
		var row: Dictionary = _seat_row(i)
		if not TypedVariant.as_bool(row.get("occupied", false), false):
			continue
		if str(row.get("controller", "")) != "onnx":
			continue
		if TypedVariant.as_int(row.get("owner_seat", -1), -1) != local_seat:
			continue
		if not force and str(row.get("model_bundle_hash", "")) != "":
			continue
		if str(row.get("model_bundle_hash", "")) == h:
			continue
		row["model_bundle_hash"] = h
		if not is_room_host() and multiplayer != null and multiplayer.has_multiplayer_peer():
			rpc_id(1, "rpc_owner_model_hash", i, h)


@rpc("any_peer", "reliable")
func rpc_owner_model_hash(seat: int, bundle_hash: String) -> void:
	if not is_room_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var row: Dictionary = _seat_row(seat)
	if row.is_empty() or not seat_is_proxy(row):
		return
	if TypedVariant.as_int(row.get("owner_peer_id", 0), 0) != sender:
		return
	if str(row.get("controller", "")) != "onnx":
		return
	row["model_bundle_hash"] = bundle_hash
	_broadcast_seats()


func _can_host_add_proxy() -> bool:
	_heal_host_role_from_peer()
	if not is_room_host() or match_started or _opening_hs_active:
		return false
	return detect_local_platform() == "pc"


func _stamp_owner_from_host(row: Dictionary) -> void:
	var hs: int = local_seat if local_seat >= 0 else 0
	var host_row: Dictionary = _seat_row(hs)
	row["owner_seat"] = hs
	row["owner_peer_id"] = TypedVariant.as_int(host_row.get("peer_id", 0), 0)
	if TypedVariant.as_int(row["owner_peer_id"], 0) <= 0 and multiplayer != null and multiplayer.has_multiplayer_peer():
		row["owner_peer_id"] = multiplayer.get_unique_id()
	row["owner_nick"] = str(host_row.get("nick", local_nick))
	if str(row["owner_nick"]) == "":
		row["owner_nick"] = local_nick


static func is_lowsec(mode: String) -> bool:
	return str(mode) == SECURITY_LOWSEC


func effective_player_cap() -> int:
	if is_lowsec(security_mode):
		return 2
	return host_player_cap


func listen_port() -> int:
	return _listen_port if _listen_port > 0 else port_for_code(maxi(room_code, 1))


## LAN beacon announce join IP (SEMI_ASYNC §7.5).
## Always re-score (ZeroTier may appear after host create; never stick on Wi‑Fi IP).
func advertise_lan_ip() -> String:
	var hip: String = _best_local_ip()
	if hip != "" and hip != "127.0.0.1" and hip != "0.0.0.0":
		last_known_host_ip = hip
	return "" if hip == "127.0.0.1" or hip == "0.0.0.0" else hip


func _ready() -> void:
	rules_hash = MatchRng.compute_rules_hash()
	_init_empty_seats()
	set_process(true)


func _process(delta: float) -> void:
	if _opening_hs_active:
		_tick_opening_handshake()
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
		seats.append(_empty_seat_dict(i))


func host_room(code: int, nick: String, password: String = "") -> Error:
	## 开房现读内容版号，避免 session 早建时冻成 local/旧号。
	rules_hash = MatchRng.compute_rules_hash()
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
	## 进房现读本机内容版号再比对。
	rules_hash = MatchRng.compute_rules_hash()
	## Preserve rejoin credentials across close() (SEMI_ASYNC §5.3a).
	var reclaim: bool = pending_rejoin_seat >= 0
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
	if reclaim:
		pending_rejoin_seat = keep_seat
		pending_rejoin_secret = keep_secret
		session_secret = keep_session
		match_id = keep_mid
		opening_host_platform = keep_plat
		opening_host_ships_hash = keep_ships_hash
		opening_host_ships = keep_ships
		host_migrate_generation = keep_gen
		security_mode = keep_sec
	else:
		## Fresh join after leave/end — do not keep prior match opening material.
		clear_rejoin_ticket()
		opening_host_ships = {}
		opening_host_ships_hash = ""
		opening_host_platform = "pc"
		match_id = ""
		session_secret = ""
		host_migrate_generation = 0
		## security_mode comes from invite / seat_sync for the new room.
	_set_host_role(false)
	local_nick = nick
	local_seat = -1
	match_started = false
	last_match_payload = {}
	host_ships_hash = ""
	## Reclaim / transfer: close() emptied seats — do NOT flash empty lobby UI.
	## Callers restore keep_seats; authority broadcast refreshes after accept.
	if pending_rejoin_seat < 0:
		seat_sync.emit(seats)
	pending_join_password = password.strip_edges()
	room_password = pending_join_password
	room_has_password = not pending_join_password.is_empty()
	_listen_port = port
	last_known_host_ip = address
	## 版本门：字符串全等即可（内容版号）。
	if expect_hash != "" and expect_hash != rules_hash:
		SessionDiagnostics.log(
			"net.join.fail",
			"rules expect=%s local=%s ep=%s:%d" % [expect_hash, rules_hash, address, port]
		)
		rejected.emit("版本不符 · 房间主持 %s · 本机 %s" % [expect_hash, rules_hash])
		return ERR_INVALID_PARAMETER
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_client(address, port)
	if err != OK:
		SessionDiagnostics.log(
			"net.join.fail",
			"enet err=%d ep=%s:%d reclaim=%d" % [err, address, port, pending_rejoin_seat]
		)
		_peer = null
		return err
	SessionDiagnostics.log(
		"net.join.try",
		"ep=%s:%d reclaim=%d pw=%s local_plat=%s host_plat=%s" % [
			address,
			port,
			pending_rejoin_seat,
			"yes" if not pending_join_password.is_empty() else "no",
			detect_local_platform(),
			opening_host_platform if opening_host_platform != "" else "-",
		]
	)
	if detect_local_platform() == "mobile":
		SessionDiagnostics.log(
			"net.lan.join_pc_host",
			"try ep=%s:%d local=mobile host_plat=%s reclaim=%d" % [
				address,
				port,
				opening_host_platform if opening_host_platform != "" else "unknown",
				pending_rejoin_seat,
			]
		)
	_enable_enet_range_compress()
	multiplayer.multiplayer_peer = _peer
	## Peer 1 may not exist until handshake completes — also apply in _on_connected_to_server.
	_apply_enet_timeout_to_peer(1)
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
	_set_host_role(true)
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
	## STUN/UPnP after listen is up — deferred so host UI is not blocked on discover.
	call_deferred("_discover_reflexive_endpoints")
	return OK


func _discover_reflexive_endpoints() -> void:
	if not is_host or _listen_port <= 0:
		return
	last_known_reflexive_ip = ""
	last_known_reflexive_port = 0
	last_known_reflexive_via = ""
	if NetConnectivity.upnp_enabled():
		var up: Dictionary = NetNatAssist.try_upnp_map(_listen_port, 1600)
		var uip: String = str(up.get("ip", "")).strip_edges()
		var uport: int = TypedVariant.as_int(up.get("port", 0), 0)
		if uip != "" and uport > 0:
			last_known_reflexive_ip = uip
			last_known_reflexive_port = uport
			last_known_reflexive_via = "upnp"
			NetSessionDebug.log_event("net.reflexive", "via=upnp ip=%s port=%d" % [uip, uport])
			return
	if not NetConnectivity.public_stun_enabled():
		return
	var stun_urls: PackedStringArray = NetConnectivity.stun_urls()
	if stun_urls.is_empty():
		return
	## One server, short wait — deferred but still on main thread.
	var stun: Dictionary = StunClient.discover_mapped_ipv4(stun_urls[0], 600)
	var sip: String = str(stun.get("ip", "")).strip_edges()
	if sip == "":
		return
	## ENet owns listen_port — publish that port with the STUN-learned public IP.
	last_known_reflexive_ip = sip
	last_known_reflexive_port = _listen_port
	last_known_reflexive_via = "stun"
	NetSessionDebug.log_event("net.reflexive", "via=stun ip=%s port=%d" % [sip, _listen_port])


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
	_apply_enet_timeout_to_peer(id)
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
		if TypedVariant.as_int(_seat_row(i).get("peer_id", 0), 0) != id:
			continue
		if match_started and is_player_race(str(_seat_row(i).get("titan_race", ""))):
			mark_seat_ghost(i)
		elif _pending_transfer_seat >= 0 or _host_promote_in_flight:
			## Hold seat for transfer reclaim — keep nick/titan, clear wire peer.
			_seat_row(i)["peer_id"] = 0
			_seat_row(i)["ready"] = false
		else:
			var left_seat: int = i
			_vacate_seat_row(i)
			_reassign_or_drop_owned_ai(left_seat)
	if not match_started:
		_sync_lobby_ready_gates()
	_broadcast_seats()
	if not match_started:
		_try_start()


func _on_connected_to_server() -> void:
	_apply_enet_timeout_to_peer(1)
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
	if _transfer_take_seat0_inflight:
		## Seat0 handoff promote in progress — ignore old host drop.
		return
	if _pending_transfer_seat >= 0:
		## Designated new host: old listen dropped — promote locally (promote RPC may be lost).
		## Must NOT guest-join here or local_seat/is_host wipe and titan dropdowns stay disabled.
		if _pending_transfer_seat == local_seat and local_seat >= 0:
			var seat: int = local_seat
			if _pending_transfer_gen > 0:
				host_migrate_generation = _pending_transfer_gen
			_pending_transfer_seat = -1
			opening_host_platform = detect_local_platform()
			host_player_cap = detect_host_player_cap()
			await _promote_self_to_host(seat)
			return
		## Lobby seat0 handoff: designate already has local_seat=0 from take_seat0 snap.
		if _pending_transfer_seat == 0 and local_seat == 0 and not is_host:
			if _pending_transfer_gen > 0:
				host_migrate_generation = _pending_transfer_gen
			_pending_transfer_seat = -1
			opening_host_platform = detect_local_platform()
			host_player_cap = detect_host_player_cap()
			await _promote_self_to_host(0)
			return
		var hip: String = last_known_host_ip
		var hport: int = port_for_code(room_code)
		var keep_seat: int = local_seat
		var keep_seats: Array = seats.duplicate(true)
		var keep_pw: String = room_password
		_teardown_peer_only()
		pending_rejoin_seat = keep_seat
		pending_rejoin_secret = session_secret
		var tree: SceneTree = get_tree()
		if tree and hip != "" and hip != "0.0.0.0":
			tree.create_timer(0.55).timeout.connect(func() -> void:
				var err: Error = join(hip, hport, local_nick, rules_hash, keep_pw)
				seats = keep_seats
				local_seat = keep_seat
				pending_rejoin_seat = keep_seat
				pending_rejoin_secret = session_secret
				seat_sync.emit(seats)
				_pending_transfer_seat = -1
				SessionDiagnostics.log(
					"net.transfer.rejoin",
					"via=disconnect err=%d seat=%d ep=%s:%d" % [err, keep_seat, hip, hport]
				)
			)
		else:
			_pending_transfer_seat = -1
			seats = keep_seats
			local_seat = keep_seat
			seat_sync.emit(seats)
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
		_heal_host_role_from_peer()
		if not is_room_host():
			return
	var sender: int = multiplayer.get_remote_sender_id()
	## 现读，与开房时一致：只比内容版号字符串。
	rules_hash = MatchRng.compute_rules_hash()
	if client_hash != rules_hash:
		rpc_id(sender, "rpc_join_rejected", "版本不符 · 房间主持 %s · 本机 %s" % [rules_hash, client_hash])
		return
	## Held-seat reclaim after host transfer / migration — seat_id + session_secret.
	## Lobby transfer must reclaim too (seats stay occupied with peer_id=0; not free).
	if secret != "" and rejoin_seat >= 0:
		if secret != session_secret:
			SessionDiagnostics.log(
				"net.reject",
				"reclaim_secret_mismatch seat=%d from=%d" % [rejoin_seat, sender]
			)
		elif _try_reclaim_held_seat(rejoin_seat, nick, sender, platform):
			if match_started:
				rpc_id(sender, "rpc_rejoin_ok", rejoin_seat)
				_rpc_ships_table_to(sender, true)
				var reclaim_payload: Dictionary = _payload_for_spectate_join()
				reclaim_payload["mid_join_spectate"] = false
				reclaim_payload["rejoin"] = true
				if not reclaim_payload.is_empty():
					rpc_id(sender, "rpc_match_start", reclaim_payload)
			else:
				rpc_id(sender, "rpc_join_accepted", rejoin_seat, false)
			_broadcast_seats()
			SessionDiagnostics.log(
				"net.transfer.rejoin",
				"host_accept seat=%d from=%d match=%s" % [
					rejoin_seat, sender, "1" if match_started else "0"
				]
			)
			return
		else:
			SessionDiagnostics.log(
				"net.reject",
				"reclaim_held_fail seat=%d from=%d peer=%d ghost=%s" % [
					rejoin_seat,
					sender,
					TypedVariant.as_int(_seat_row(rejoin_seat).get("peer_id", 0), 0),
					str(TypedVariant.as_bool(_seat_row(rejoin_seat).get("ghost", false), false)),
				]
			)
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
		_rpc_ships_table_to(sender, true)
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
	SessionDiagnostics.log("net.reject", "reason=%s reclaim=%d" % [r, pending_rejoin_seat])
	rejected.emit(r)


@rpc("authority", "reliable")
func rpc_join_accepted(seat: int, in_match: bool = false) -> void:
	local_seat = seat
	match_started = in_match
	join_accepted.emit(seat, in_match)
	seat_sync.emit(seats)
	if not in_match:
		call_deferred("_push_local_lobby_loadout_to_host")
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
	## Preserve own lobby titan if authority briefly sends empty after host transfer / mode switch.
	var keep_seat: int = local_seat
	var keep_race: String = ""
	var keep_ready: bool = false
	if keep_seat >= 0 and keep_seat < seats.size() and not match_started:
		var prev: Dictionary = _seat_row(keep_seat)
		keep_race = str(prev.get("titan_race", ""))
		keep_ready = TypedVariant.as_bool(prev.get("ready", false), false)
	seats = payload
	if (
		not match_started
		and keep_seat >= 0
		and keep_seat < seats.size()
		and keep_race != ""
		and str(_seat_row(keep_seat).get("titan_race", "")) == ""
		and TypedVariant.as_bool(_seat_row(keep_seat).get("occupied", false), false)
	):
		_seat_row(keep_seat)["titan_race"] = keep_race
		if keep_ready:
			_seat_row(keep_seat)["ready"] = true
		_push_local_lobby_loadout_to_host()
	restamp_local_owned_onnx_hashes()
	seat_sync.emit(seats)


func _broadcast_seats() -> void:
	_heal_host_role_from_peer()
	seat_sync.emit(seats)
	if is_room_host() and multiplayer != null and multiplayer.has_multiplayer_peer():
		rpc("rpc_seats", seats.duplicate(true))


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
	if not row.has("controller") or str(row.get("controller", "")) == "":
		row["controller"] = "legacy_ai" if is_ai else "human"
	if str(row.get("controller", "human")) == "human":
		row["owner_seat"] = seat
		row["owner_peer_id"] = peer_id
		row["owner_nick"] = str(row["nick"])
		row["model_bundle_hash"] = ""
		row["is_ai"] = false
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
	return add_onnx_seat(nick)


func add_onnx_seat(nick: String = "") -> bool:
	if not _can_host_add_proxy():
		return false
	if not onnx_bundle_ready():
		lobby_notice.emit("模型包未加载，无法加人机")
		return false
	return _add_proxy_seat("onnx", nick)


func add_llm_seat(nick: String = "") -> bool:
	if not _can_host_add_proxy():
		return false
	return _add_proxy_seat("llm", nick)


func _add_proxy_seat(controller: String, nick: String) -> bool:
	if not is_lowsec(security_mode) and player_count() >= host_player_cap:
		return false
	var seat: int = _first_free_seat()
	if seat < 0:
		return false
	var use_nick: String = NickCodec.sanitize(nick)
	if use_nick == "":
		use_nick = EveStyleNameGenerator.roll()
	var pol: OnnxCpuPolicy = OnnxCpuPolicy.new()
	pol.try_autoload()
	_occupy_seat(seat, use_nick, 0, false)
	var row: Dictionary = _seat_row(seat)
	row["controller"] = controller
	row["is_ai"] = controller == "legacy_ai"
	row["model_bundle_hash"] = pol.model_bundle_hash if controller == "onnx" else ""
	row["platform"] = "pc"
	_stamp_owner_from_host(row)
	var census: Dictionary = _lobby_titan_census()
	var auto_race: String = _proxy_auto_titan_race(pol, census)
	if auto_race != "":
		_apply_titan(seat, auto_race)
	_broadcast_seats()
	return true


func _lobby_titan_census() -> Dictionary:
	var out: Dictionary = {}
	for t: String in WeightDrivenAi.TITAN_IDS:
		out[t] = 0
	for i: int in range(seats.size()):
		var row: Dictionary = _seat_row(i)
		if not TypedVariant.as_bool(row.get("occupied", false), false):
			continue
		var race: String = str(row.get("titan_race", ""))
		if is_player_race(race) and out.has(race):
			out[race] = TypedVariant.as_int(out[race], 0) + 1
	return out


func _proxy_auto_titan_race(pol: OnnxCpuPolicy, census: Dictionary = {}) -> String:
	## Handbook: ONNX reads room titan counts once, then TitanNet; never rotate by seat.
	if pol != null:
		var raced: String = pol.pick_lobby_titan_race(census, "", 2)
		if is_player_race(raced):
			return raced
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var pick_v: Variant = TITAN_RACES[rng.randi_range(0, TITAN_RACES.size() - 1)]
	return str(pick_v)


func begin_offline_drill(mode: String, nick: String) -> bool:
	## Solo 多人联机演练：无 ENet，进房间。本席 human，不代填泰坦、不开战。
	close()
	offline_drill = true
	rules_hash = MatchRng.compute_rules_hash()
	_set_host_role(true)
	match_started = false
	_opening_hs_active = false
	room_code = 1
	room_password = ""
	room_has_password = false
	security_mode = SECURITY_LOWSEC if is_lowsec(mode) else SECURITY_NULLSEC
	local_nick = NickCodec.sanitize(nick)
	if local_nick == "":
		local_nick = "演练棋手"
	host_player_cap = detect_host_player_cap()
	opening_host_platform = detect_local_platform()
	_init_empty_seats()
	local_seat = 0
	_occupy_seat(0, local_nick, 1, false)
	var host_row: Dictionary = _seat_row(0)
	host_row["platform"] = opening_host_platform
	host_row["controller"] = "human"
	host_row["is_ai"] = false
	host_row["owner_seat"] = 0
	host_row["owner_peer_id"] = 1
	host_row["owner_nick"] = local_nick
	host_row["model_bundle_hash"] = ""
	host_row["titan_race"] = ""
	host_row["ready"] = false
	_ensure_session_secret()
	_broadcast_seats()
	return true


func start_offline_drill(mode: String, nick: String) -> bool:
	## Back-compat alias — lobby only, never auto-starts.
	return begin_offline_drill(mode, nick)


func _find_other_pc_human_seat(except_seat: int) -> int:
	for i: int in range(seats.size()):
		if i == except_seat:
			continue
		var row: Dictionary = _seat_row(i)
		if not TypedVariant.as_bool(row.get("occupied", false), false):
			continue
		if seat_is_proxy(row):
			continue
		if TypedVariant.as_bool(row.get("ghost", false), false):
			continue
		if str(row.get("platform", "pc")) != "pc":
			continue
		return i
	return -1


func _reassign_or_drop_owned_ai(left_seat: int) -> void:
	var pc: int = _find_other_pc_human_seat(left_seat)
	var drop: Array = []
	for i: int in range(seats.size()):
		var row: Dictionary = _seat_row(i)
		if not TypedVariant.as_bool(row.get("occupied", false), false):
			continue
		if not seat_is_proxy(row):
			continue
		if TypedVariant.as_int(row.get("owner_seat", -1), -1) != left_seat:
			continue
		if pc >= 0:
			var pc_row: Dictionary = _seat_row(pc)
			row["owner_seat"] = pc
			row["owner_peer_id"] = TypedVariant.as_int(pc_row.get("peer_id", 0), 0)
			row["owner_nick"] = str(pc_row.get("nick", ""))
			if str(row.get("controller", "")) == "onnx":
				if pc == local_seat:
					var pol: OnnxCpuPolicy = OnnxCpuPolicy.new()
					pol.try_autoload()
					row["model_bundle_hash"] = pol.model_bundle_hash
				else:
					row["model_bundle_hash"] = ""
		else:
			drop.append(i)
	for di_v: Variant in drop:
		var di: int = TypedVariant.as_int(di_v, -1)
		var nick: String = str(_seat_row(di).get("nick", ""))
		_vacate_seat_row(di)
		lobby_notice.emit("由于无人能负责模拟，%s 已被自动移除" % nick)


func set_security_mode(mode: String) -> void:
	_heal_host_role_from_peer()
	if not is_room_host() or match_started:
		return
	var next: String = SECURITY_LOWSEC if is_lowsec(mode) else SECURITY_NULLSEC
	if next == security_mode:
		return
	## Mode switch may only clear ready (lowsec over-cap) — never titan_race.
	_apply_security_mode(next, true)
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		rpc("rpc_security_mode", security_mode)
	_broadcast_seats()
	## Guests re-push loadout after mode RPC; second broadcast sticks authority.
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.create_timer(0.12).timeout.connect(func() -> void:
			if is_instance_valid(self) and is_room_host() and not match_started:
				_broadcast_seats()
		)
	_try_start()


func _apply_security_mode(mode: String, enforce_ready_gate: bool) -> void:
	security_mode = SECURITY_LOWSEC if is_lowsec(mode) else SECURITY_NULLSEC
	if enforce_ready_gate:
		_sync_lobby_ready_gates()
	security_mode_changed.emit(security_mode)


func _push_local_lobby_loadout_to_host() -> void:
	## After transfer / mode switch — re-assert this seat's titan so authority cannot stay empty.
	if is_room_host() or match_started:
		return
	if local_seat < 0 or local_seat >= seats.size():
		return
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	var row: Dictionary = _seat_row(local_seat)
	if row.is_empty() or not TypedVariant.as_bool(row.get("occupied", false), false):
		return
	var race: String = str(row.get("titan_race", ""))
	## Never push empty — that would wipe authority after a desynced seat broadcast.
	if race == "":
		return
	rpc_id(1, "rpc_set_titan", local_seat, race)
	if TypedVariant.as_bool(row.get("ready", false), false) and is_player_race(race):
		rpc_id(1, "rpc_set_ready", local_seat, true)


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
		if not seat_is_proxy(_seat_row(i)):
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
	## Guests only — server already applied locally in set_security_mode.
	if is_room_host():
		return
	_apply_security_mode(mode, true)
	_push_local_lobby_loadout_to_host()


func kick_seat(seat: int) -> void:
	_heal_host_role_from_peer()
	if not is_room_host():
		return
	if seat < 0 or seat >= seats.size():
		return
	var peer_id: int = TypedVariant.as_int(_seat_row(seat).get("peer_id", 0), 0)
	_vacate_seat_row(seat)
	_reassign_or_drop_owned_ai(seat)
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
	_heal_host_role_from_peer()
	var row: Dictionary = _seat_row(seat)
	var proxy: bool = seat_is_proxy(row)
	if is_room_host():
		if seat != local_seat and not proxy:
			return
		if not _can_apply_titan(seat, race):
			return
		_apply_titan(seat, race)
		_broadcast_seats()
		_try_start()
		return
	if seat != local_seat:
		return
	## Optimistic local paint; host echo via rpc_seats is authoritative.
	_apply_titan(seat, race)
	seat_sync.emit(seats)
	if multiplayer != null and multiplayer.has_multiplayer_peer():
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
	elif seat_is_proxy(_seat_row(seat)) and is_player_race(race):
		## Immediate attempt; `_sync_lobby_ready_gates` re-tries when the gate opens later.
		_seat_row(seat)["ready"] = not lowsec_ready_blocked()
	elif not is_player_race(race):
		_seat_row(seat)["ready"] = false
	_sync_lobby_ready_gates()


func set_local_ready(is_ready: bool) -> void:
	if local_seat < 0:
		return
	_heal_host_role_from_peer()
	var race: String = str(_seat_row(local_seat).get("titan_race", ""))
	if is_ready and not is_player_race(race):
		return
	if is_ready and lowsec_ready_blocked():
		return
	_seat_row(local_seat)["ready"] = is_ready
	if is_room_host():
		_sync_lobby_ready_gates()
		_broadcast_seats()
		_try_start()
	else:
		seat_sync.emit(seats)
		if multiplayer != null and multiplayer.has_multiplayer_peer():
			rpc_id(1, "rpc_set_ready", local_seat, is_ready)


@rpc("any_peer", "reliable")
func rpc_set_titan(seat: int, race: String) -> void:
	_heal_host_role_from_peer()
	if not is_room_host():
		return
	if seat < 0 or seat >= seats.size():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _bind_sender_to_held_seat(seat, sender):
		_broadcast_seats() ## bounce UI — never silent-drop after transfer
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
	_heal_host_role_from_peer()
	if not is_room_host():
		return
	if seat < 0 or seat >= seats.size():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _bind_sender_to_held_seat(seat, sender):
		_broadcast_seats()
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
	if match_started or _opening_hs_active:
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
	var rollback_ships: Dictionary = opening_host_ships.duplicate(true)
	var rollback_hash: String = opening_host_ships_hash
	var rollback_mid: String = match_id
	var all_occupied: Array = []
	for s_v: Variant in seats:
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = s_v
		if TypedVariant.as_bool(s.get("occupied", false), false):
			all_occupied.append(s)
	_ensure_session_secret()
	match_loading.emit("正在从房主拉取全舰船与全游戏数据", 0.08)
	## Take ownership of freshly exported table (no extra duplicate) — mobile host OOM risk.
	SessionDiagnostics.begin_critical_window("mp_host_open_match")
	SessionDiagnostics.log_critical(
		"net.host_open_match",
		"before_freeze plat=%s %s" % [opening_host_platform, SessionDiagnostics.mem_detail()]
	)
	_freeze_opening_host_ships(DataStore.export_ships_table(), false)
	SessionDiagnostics.log_critical(
		"net.host_open_match",
		"after_freeze ships=%d hash=%s %s" % [
			opening_host_ships.size(),
			opening_host_ships_hash.substr(0, mini(8, opening_host_ships_hash.length())),
			SessionDiagnostics.mem_detail(),
		]
	)
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
	## Ship table as UTF-8 JSON bytes (cheaper than Variant Dictionary RPC on mobile).
	var ships_json: String = JSON.stringify(opening_host_ships)
	var ships_bytes: PackedByteArray = ships_json.to_utf8_buffer()
	SessionDiagnostics.log_critical(
		"net.host_open_match",
		"ships_bytes=%d %s" % [ships_bytes.size(), SessionDiagnostics.mem_detail()]
	)
	NetSessionDebug.log_pack("opening", {
		"ships_hash": opening_host_ships_hash,
		"rules_hash": rules_hash,
		"bytes": ships_bytes.size(),
		"security_mode": security_mode,
	})
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		rpc("rpc_ships_table_bytes", ships_bytes, false)
	_begin_opening_handshake(payload, seed_v, rollback_ships, rollback_hash, rollback_mid)
	ships_json = ""
	ships_bytes = PackedByteArray()


func _seats_opening_digest() -> Array:
	var out: Array = []
	for s_v: Variant in seats:
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = s_v
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		out.append({
			"seat_id": TypedVariant.as_int(s.get("seat_id", -1), -1),
			"controller": seat_controller_of(s),
			"owner_seat": TypedVariant.as_int(s.get("owner_seat", -1), -1),
			"model_bundle_hash": str(s.get("model_bundle_hash", "")),
			"titan_race": str(s.get("titan_race", "")),
		})
	return out


func _opening_human_seats() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for s_v: Variant in seats:
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = s_v
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		if is_spectate_race(str(s.get("titan_race", ""))):
			continue
		if seat_is_proxy(s):
			continue
		if TypedVariant.as_bool(s.get("ghost", false), false):
			continue
		out.append(TypedVariant.as_int(s.get("seat_id", -1), -1))
	return out


func _begin_opening_handshake(
	payload: Dictionary,
	seed_v: int,
	rollback_ships: Dictionary,
	rollback_hash: String,
	rollback_mid: String
) -> void:
	_opening_hs_rollback_ships = rollback_ships.duplicate(true)
	_opening_hs_rollback_hash = rollback_hash
	_opening_hs_rollback_match_id = rollback_mid
	_opening_hs_payload = payload.duplicate(true)
	_opening_hs_verify.clear()
	_opening_hs_offer = {
		"ships_hash": opening_host_ships_hash,
		"rules_hash": rules_hash,
		"match_seed": seed_v,
		"match_id": match_id,
		"seats_digest": _seats_opening_digest(),
	}
	_opening_hs_active = true
	_opening_hs_deadline = Time.get_ticks_msec() + 5000
	match_loading.emit("正在与房主核对开局信息", 0.2)
	## Host self-verify.
	if local_seat >= 0:
		_opening_hs_verify[local_seat] = true
	if multiplayer == null or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty():
		_commit_opening_handshake()
		return
	rpc("rpc_opening_offer", _opening_hs_offer)
	_tick_opening_handshake()


func _tick_opening_handshake() -> void:
	if not _opening_hs_active or not is_room_host():
		return
	var humans: PackedInt32Array = _opening_human_seats()
	var all_ok: bool = true
	for sid: int in humans:
		if not TypedVariant.as_bool(_opening_hs_verify.get(sid, false), false):
			all_ok = false
			break
	if all_ok:
		_commit_opening_handshake()
		return
	if Time.get_ticks_msec() >= _opening_hs_deadline:
		var missing: String = ""
		var field: String = "timeout"
		for sid: int in humans:
			if TypedVariant.as_bool(_opening_hs_verify.get(sid, false), false):
				continue
			missing = str(_seat_row(sid).get("nick", "席%d" % (sid + 1)))
			break
		_abort_opening_handshake("handshake_timeout", missing, field)


func _commit_opening_handshake() -> void:
	if not _opening_hs_active:
		return
	_opening_hs_active = false
	var payload: Dictionary = _opening_hs_payload.duplicate(true)
	match_started = true
	last_match_payload = payload.duplicate(true)
	_reset_settlement_sync_state()
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		rpc("rpc_opening_commit")
		rpc("rpc_match_start", payload)
	if not offline_drill:
		write_rejoin_ticket()
	match_loading.emit("正在进入对局场景", 0.25)
	SessionDiagnostics.log_critical(
		"net.host_open_match",
		"emit_match_start id=%s %s" % [match_id, SessionDiagnostics.mem_detail()]
	)
	match_start.emit(payload)
	var seed_v: int = TypedVariant.as_int(payload.get("match_seed", 0), 0)
	NetSessionDebug.log_event("net.match_start", "id=%s seed=%d mode=%s" % [match_id, seed_v, security_mode])


func _abort_opening_handshake(reason: String, nick: String, field: String) -> void:
	_opening_hs_active = false
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		rpc("rpc_opening_abort", reason, nick, field)
	opening_host_ships = _opening_hs_rollback_ships.duplicate(true)
	opening_host_ships_hash = _opening_hs_rollback_hash
	match_id = _opening_hs_rollback_match_id
	match_started = false
	clear_rejoin_ticket()
	lobby_notice.emit("开局核对失败：%s · %s" % [nick, field if field != "" else reason])
	match_loading.emit("", 0.0)


@rpc("authority", "reliable")
func rpc_opening_offer(offer: Dictionary) -> void:
	if is_host:
		return
	match_loading.emit("正在与房主核对开局信息", 0.2)
	var field: String = ""
	if str(offer.get("ships_hash", "")) != opening_host_ships_hash and opening_host_ships_hash != "":
		if str(offer.get("ships_hash", "")) != opening_host_ships_hash:
			field = "ships_hash"
	if field == "" and str(offer.get("rules_hash", "")) != rules_hash and rules_hash != "":
		field = "rules_hash"
	var ok: bool = field == ""
	if local_seat >= 0 and multiplayer != null and multiplayer.has_multiplayer_peer():
		rpc_id(1, "rpc_opening_verify", local_seat, ok, field)


@rpc("any_peer", "reliable")
func rpc_opening_verify(seat: int, ok: bool, mismatch_field: String) -> void:
	if not is_host or not _opening_hs_active:
		return
	if not ok:
		var nick: String = str(_seat_row(seat).get("nick", "席%d" % (seat + 1)))
		_abort_opening_handshake("mismatch", nick, mismatch_field)
		return
	_opening_hs_verify[seat] = true
	_tick_opening_handshake()


@rpc("authority", "reliable")
func rpc_opening_commit() -> void:
	if is_host:
		return
	match_loading.emit("正在进入对局场景", 0.25)


@rpc("authority", "reliable")
func rpc_opening_abort(reason: String, nick: String, field: String) -> void:
	_opening_hs_active = false
	match_started = false
	lobby_notice.emit("开局核对失败：%s · %s" % [nick, field if field != "" else reason])
	match_loading.emit("", 0.0)


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
	_freeze_opening_host_ships(DataStore.export_ships_table(), false)
	rpc("rpc_ships_table_bytes", JSON.stringify(opening_host_ships).to_utf8_buffer(), true)


func _rpc_ships_table_to(peer_id: int, mid_match: bool) -> void:
	if peer_id <= 0 or not multiplayer.has_multiplayer_peer():
		return
	var table: Dictionary = _authority_ships_table()
	if table.is_empty():
		return
	rpc_id(peer_id, "rpc_ships_table_bytes", JSON.stringify(table).to_utf8_buffer(), mid_match)


@rpc("authority", "reliable")
func rpc_ships_table_bytes(bytes: PackedByteArray, mid_match: bool = false) -> void:
	if is_host:
		return
	if bytes.is_empty():
		return
	if not mid_match:
		match_loading.emit("正在从房主拉取全舰船与全游戏数据", 0.12)
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		NetSessionDebug.log_event("net.ships_bytes_fail", "len=%d" % bytes.size())
		return
	var table: Dictionary = parsed
	_freeze_opening_host_ships(table, false)
	if DataStore.apply_host_ships_override(table):
		ships_override_applied.emit(mid_match)
	if not mid_match:
		match_loading.emit("正在从房主拉取全舰船与全游戏数据", 0.16)


@rpc("authority", "reliable")
func rpc_ships_table(table: Dictionary, mid_match: bool = false) -> void:
	## Legacy Dictionary path (older hosts / mid-join reclaim). Prefer bytes.
	if is_host:
		return
	if not mid_match:
		## SEMI_ASYNC §3.7 — keep overlay on this copy until match_start advances phase.
		match_loading.emit("正在从房主拉取全舰船与全游戏数据", 0.12)
	_freeze_opening_host_ships(table, true)
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
	_reset_settlement_sync_state()
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
	## Prefer real LAN IPv4; never encode 127.* (guests treat it as dead + "跨网" UX).
	var ip: String = advertise_lan_ip()
	if ip == "" or ip == "0.0.0.0" or ip.begins_with("127."):
		ip = _best_local_ip()
	if ip.begins_with("127.") or ip == "0.0.0.0":
		ip = ""
	var ipv6: String = last_known_host_ipv6 if last_known_host_ipv6 != "" else _best_global_ipv6()
	var extra: Dictionary = {
		"password": room_password,
		"ipv6": ipv6,
		"security_mode": security_mode,
	}
	## SEMI_ASYNC §7.2 — reflexive = STUN/UPnP mapped host address only.
	## turn_urls stay join-order step ⑤; never stuff relay endpoints into reflexive.
	if last_known_reflexive_ip != "" and last_known_reflexive_port > 0:
		extra["reflexive_ip"] = last_known_reflexive_ip
		extra["reflexive_port"] = last_known_reflexive_port
	LanJoinDebug.log_locals("invite_blob")
	var zt_hit: bool = false
	if ip != "":
		for row_v: Variant in LanAffinity.scored_local_ipv4s():
			var row: Dictionary = TypedVariant.as_dict(row_v)
			if str(row.get("ip", "")) == ip:
				zt_hit = TypedVariant.as_bool(row.get("zerotier", false), false)
				break
	NetSessionDebug.log_event(
		"net.lan.invite",
		"code=%04d ip=%s zerotier=%s v6=%s ref=%s:%d" % [
			room_code, ip, str(zt_hit), ipv6, last_known_reflexive_ip, last_known_reflexive_port
		]
	)
	return InviteBlobHelper.encode(ip, listen_port(), "%04d" % room_code, rules_hash, extra)


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
	## SEMI_ASYNC §7.2 — ZeroTier iface (+150) beats 192.168; else home LAN over Hyper-V / APIPA.
	return LanAffinity.best_local_ipv4()


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
	## Base score only; ZeroTier bonus applied in LanAffinity.scored_local_ipv4s / best_local_ipv4.
	return LanAffinity.score_ipv4_base(ip)


func _freeze_opening_host_ships(table: Dictionary, duplicate_table: bool = true) -> void:
	if table.is_empty():
		return
	opening_host_ships = table.duplicate(true) if duplicate_table else table
	opening_host_ships_hash = DataStore.table_hash(opening_host_ships)


func _authority_ships_table() -> Dictionary:
	if not opening_host_ships.is_empty():
		return opening_host_ships
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


func _try_reclaim_held_seat(seat: int, nick: String, peer_id: int, platform: String) -> bool:
	## SEMI_ASYNC §5.3a — reclaim after transfer / migration (lobby or match).
	if seat < 0 or seat >= seats.size():
		return false
	var row: Dictionary = _seat_row(seat)
	if row.is_empty():
		return false
	if not TypedVariant.as_bool(row.get("occupied", false), false):
		return false
	if TypedVariant.as_bool(row.get("is_ai", false), false):
		return false
	var held_peer: int = TypedVariant.as_int(row.get("peer_id", 0), 0)
	var is_ghost: bool = TypedVariant.as_bool(row.get("ghost", false), false)
	## Seat must be vacated on the wire (peer gone) or marked ghost.
	if held_peer != 0 and not is_ghost:
		return false
	row["ghost"] = false
	row["peer_id"] = peer_id
	row["nick"] = nick
	row["platform"] = platform if platform != "" else str(row.get("platform", ""))
	row["ready"] = is_player_race(str(row.get("titan_race", "")))
	_capture_peer_endpoint(seat, peer_id)
	return true


func _try_reclaim_ghost(seat: int, nick: String, peer_id: int, platform: String) -> bool:
	## Compat alias — prefer _try_reclaim_held_seat.
	return _try_reclaim_held_seat(seat, nick, peer_id, platform)

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
		if seat_is_proxy(row):
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
		await _promote_self_to_host(elected)
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
	## Idempotent — promote RPC and disconnect-designate may both fire.
	if _host_promote_in_flight:
		return
	if is_host and _peer != null and multiplayer != null and multiplayer.multiplayer_peer == _peer:
		_pending_transfer_seat = -1
		return
	_host_promote_in_flight = true
	## Drop client (or prior) peer before binding listen — same-PC transfer needs the old host port free.
	_teardown_peer_only()
	_set_host_role(true)
	rules_hash = MatchRng.compute_rules_hash()
	_listen_port = port_for_code(room_code)
	last_known_host_ip = _best_local_ip()
	## Hold other human seats for seat_id+secret reclaim (lobby transfer otherwise → room full).
	for i: int in range(seats.size()):
		if i == new_host_seat:
			continue
		var hold: Dictionary = _seat_row(i)
		if hold.is_empty():
			continue
		if not TypedVariant.as_bool(hold.get("occupied", false), false):
			continue
		if TypedVariant.as_bool(hold.get("is_ai", false), false):
			continue
		hold["peer_id"] = 0
		if match_started:
			hold["ghost"] = true
	var err: Error = FAILED
	for _attempt: int in range(24):
		_peer = ENetMultiplayerPeer.new()
		err = _peer.create_server(_listen_port, MAX_CLIENTS)
		if err == OK:
			break
		_peer = null
		var tree_retry: SceneTree = get_tree()
		if tree_retry == null:
			break
		await tree_retry.create_timer(0.05).timeout
	if err != OK:
		_peer = null
		_listen_port = 0
		_set_host_role(false)
		_host_promote_in_flight = false
		_terminate_match_host_lost("房主掉线，对局终止")
		return
	_enable_enet_range_compress()
	multiplayer.multiplayer_peer = _peer
	_set_host_role(true)
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
	host_role_changed.emit(true)
	_migrating = false
	_pending_transfer_seat = -1
	_host_promote_in_flight = false


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
	if is_host and _listen_port > 0 and last_known_reflexive_via == "upnp":
		NetNatAssist.remove_upnp_map(_listen_port)
	_teardown_peer_only()
	is_host = false
	offline_drill = false
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
	last_known_reflexive_ip = ""
	last_known_reflexive_port = 0
	last_known_reflexive_via = ""
	pending_rejoin_seat = -1
	pending_rejoin_secret = ""
	pending_join_password = ""
	room_password = ""
	room_has_password = false
	_migrating = false
	_ticket_heartbeat_acc = 0.0
	_prepare_fleet_cache.clear()
	_reset_settlement_sync_state()
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


## SEMI_ASYNC §5.3a — keep link alive through brief host Wi‑Fi blips (≥10s floor).
func _apply_enet_timeout_to_peer(peer_id: int) -> void:
	if _peer == null or peer_id <= 0:
		return
	var ep: ENetPacketPeer = _peer.get_peer(peer_id) as ENetPacketPeer
	if ep == null:
		return
	ep.set_timeout(ENET_TIMEOUT_LIMIT, ENET_TIMEOUT_MIN_MS, ENET_TIMEOUT_MAX_MS)


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
	push_prepare_fleet_snapshot_for_seat(local_seat, ships)


func push_prepare_fleet_snapshot_for_seat(seat: int, ships: Array) -> void:
	if seat < 0:
		return
	var row: Dictionary = _seat_row(seat)
	if seat_is_proxy(row):
		if TypedVariant.as_int(row.get("owner_seat", -1), -1) != local_seat:
			return
	elif seat != local_seat:
		return
	_prepare_fleet_cache[seat] = ships
	var n: int = ships.size()
	var has_peer: bool = multiplayer.has_multiplayer_peer()
	var now: int = Time.get_ticks_msec()
	if n != _fleet_push_log_n or (now - _fleet_push_log_msec) > 3000:
		_fleet_push_log_n = n
		_fleet_push_log_msec = now
		print("[mp.diag] fleet_push seat=%d n=%d host=%s peer=%s" % [seat, n, is_host, has_peer])
		SessionDiagnostics.log("mp.fleet_push", "seat=%d n=%d" % [seat, n])
	if not has_peer:
		return
	var data: PackedByteArray = NetWireCodec.encode_fleet(
		seat, ships, NetConnectivity.wire_compress_min_bytes()
	)
	if is_host:
		_deliver_fleet_bin_to_rivals(seat, data)
	else:
		rpc_id(1, "rpc_prepare_fleet_report_bin", seat, data)


@rpc("any_peer", "reliable")
func rpc_prepare_fleet_report_bin(seat: int, data: PackedByteArray) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var row: Dictionary = _seat_row(seat)
	var peer_ok: bool = TypedVariant.as_int(row.get("peer_id", 0), 0) == sender
	var owner_ok: bool = seat_is_proxy(row) and TypedVariant.as_int(row.get("owner_peer_id", 0), 0) == sender
	if not peer_ok and not owner_ok:
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


## Prefer authoritative round matchups (MATCH_FLOW §5.2); 2p / missing table falls back.
func contestant_rival_seat(for_seat: int) -> int:
	var mu: Dictionary = TypedVariant.as_dict(GameSession.pending_nullsec.get("round_matchups", {}))
	if not mu.is_empty():
		var from_mu: int = NullsecRoundPairing.rival_from_matchups(mu, for_seat)
		## bye → -1; paired → rival. Empty rival_of with missing seat also -1.
		if from_mu >= 0 or TypedVariant.as_int(mu.get("bye_seat", -1), -1) == for_seat:
			return from_mu
		if TypedVariant.as_dict(mu.get("rival_of", {})).has(for_seat) \
			or not TypedVariant.as_array(mu.get("pairs", [])).is_empty():
			return from_mu
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


func publish_round_matchups(matchups: Dictionary, last_rival_by_seat: Dictionary, round_r: int) -> void:
	GameSession.pending_nullsec["round_matchups"] = matchups.duplicate(true)
	GameSession.pending_nullsec["last_rival_by_seat"] = last_rival_by_seat.duplicate(true)
	GameSession.pending_nullsec["round_r"] = round_r
	round_matchups_received.emit(matchups, last_rival_by_seat, round_r)
	if not is_host or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	rpc(
		"rpc_round_matchups",
		matchups.duplicate(true),
		last_rival_by_seat.duplicate(true),
		round_r
	)


@rpc("authority", "reliable")
func rpc_round_matchups(matchups: Dictionary, last_rival_by_seat: Dictionary, round_r: int) -> void:
	if is_host:
		return
	GameSession.pending_nullsec["round_matchups"] = TypedVariant.as_dict(matchups).duplicate(true)
	GameSession.pending_nullsec["last_rival_by_seat"] = TypedVariant.as_dict(last_rival_by_seat).duplicate(true)
	GameSession.pending_nullsec["round_r"] = round_r
	round_matchups_received.emit(matchups, last_rival_by_seat, round_r)


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
	## R1 Prepare only: freeze until every human contestant spends once.
	## Proxy seats (onnx/llm/legacy_ai) do not count. Host owns the set + arm broadcast.
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
	var skipped: PackedStringArray = PackedStringArray()
	for i: int in range(seats.size()):
		var row: Dictionary = _seat_row(i)
		if not _seat_counts_for_spend_gate(row):
			if TypedVariant.as_bool(row.get("occupied", false), false) and seat_is_proxy(row):
				skipped.append("%d:%s" % [i, seat_controller_of(row)])
			continue
		contestants.append("%d:H" % i)
	print("[mp.diag] spend_gate_humans [%s] skip_proxy=[%s]" % [
		",".join(contestants), ",".join(skipped)
	])
	SessionDiagnostics.log("mp.spend_gate_seats", "H=[%s] skip=[%s]" % [
		",".join(contestants), ",".join(skipped),
	])
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
	var row: Dictionary = _seat_row(seat)
	if seat_is_proxy(row):
		print("[mp.diag] spend_rpc REJECT proxy seat=%d" % seat)
		return
	if TypedVariant.as_int(row.get("peer_id", 0), 0) != sender:
		print("[mp.diag] spend_rpc REJECT seat=%d sender=%d" % [seat, sender])
		return
	print("[mp.diag] spend_rpc ACCEPT seat=%d sender=%d" % [seat, sender])
	_mark_prepare_spend(seat)


func _mark_prepare_spend(seat: int) -> void:
	if prepare_clock_armed:
		return
	if not _seat_counts_for_spend_gate(_seat_row(seat)):
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
		if not _seat_counts_for_spend_gate(row):
			continue
		if not TypedVariant.as_bool(_prepare_spent_seats.get(i, false), false):
			missing.append(str(i))
	if not missing.is_empty():
		print("[mp.diag] spend_gate_wait missing_humans=[%s]" % ",".join(missing))
		return
	print("[mp.diag] spend_gate_ALL_HUMANS_READY → arm")
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
## Never force-arms while R1 spend gate is still waiting for every human contestant.
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
		if seat_is_proxy(row):
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
		if seat_is_proxy(_seat_row(i)):
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
	## §4.5: only manned seats arm auto 4× / wall-draw. AI barrier marks stay silent.
	var seat_ai: bool = TypedVariant.as_bool(_seat_row(seat).get("is_ai", false), false)
	if not seat_ai:
		if multiplayer.has_multiplayer_peer() and is_host:
			rpc("rpc_seat_battle_finished", seat)
		else:
			seat_battle_finished.emit(seat)
	_check_battle_done_ready()


@rpc("authority", "reliable", "call_local")
func rpc_seat_battle_finished(seat: int) -> void:
	## Defense: ignore AI seats even if a stale RPC arrives.
	if TypedVariant.as_bool(_seat_row(seat).get("is_ai", false), false):
		return
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


## --- MULTIPLAYER_PVP §7.0 per-round standings + §7 end-of-match report ---

func _reset_settlement_sync_state() -> void:
	_match_report_gate_open = false
	_match_report_seats.clear()
	_match_report_summaries.clear()
	_match_report_broadcast_done = false
	_last_match_report_players.clear()
	_reset_round_summary_gate()
	_last_standings_by_seat.clear()


func _reset_round_summary_gate() -> void:
	_round_summary_gate_open = false
	_round_summary_seats.clear()
	_round_summary_by_seat.clear()
	_round_summary_round_id = -1


## Each seat reports result / titles / cumulative WLD after a PVP round.
## Host stitches AI desks then broadcasts `rpc_round_standings` to all seats.
func submit_seat_round_summary(summary: Dictionary) -> void:
	if summary.is_empty():
		return
	var seat: int = TypedVariant.as_int(summary.get("seat", summary.get("seat_id", local_seat)), local_seat)
	summary = summary.duplicate(true)
	summary["seat"] = seat
	summary["seat_id"] = seat
	if not needs_stage_barrier():
		## Solo / no live peer: apply locally as a one-seat standings pulse.
		var solo: Dictionary = {"summaries": [summary], "round": TypedVariant.as_int(summary.get("round", -1), -1)}
		_apply_round_standings_local(solo)
		round_standings_received.emit(solo)
		SessionDiagnostics.log("net.round_standings", "solo seat=%d result=%s" % [seat, str(summary.get("result", ""))])
		return
	if not is_host:
		rpc_id(1, "rpc_seat_round_summary", summary)
		SessionDiagnostics.log("net.round_summary", "guest_send seat=%d result=%s" % [seat, str(summary.get("result", ""))])
		return
	_host_begin_round_summary_gate(TypedVariant.as_int(summary.get("round", -1), -1))
	_ingest_round_summary(seat, summary)


@rpc("any_peer", "reliable")
func rpc_seat_round_summary(summary: Dictionary) -> void:
	if not is_host:
		return
	var seat: int = TypedVariant.as_int(summary.get("seat", summary.get("seat_id", -1)), -1)
	var sender: int = multiplayer.get_remote_sender_id()
	if seat < 0 or TypedVariant.as_int(_seat_row(seat).get("peer_id", 0), 0) != sender:
		print("[mp.diag] round_summary REJECT seat=%d sender=%d" % [seat, sender])
		return
	_host_begin_round_summary_gate(TypedVariant.as_int(summary.get("round", -1), -1))
	_ingest_round_summary(seat, summary)


## Host-only: inject AI / synthesized desks so stitch does not wait on missing peers.
func host_inject_round_summary(summary: Dictionary) -> void:
	if not is_host or summary.is_empty():
		return
	var seat: int = TypedVariant.as_int(summary.get("seat", summary.get("seat_id", -1)), -1)
	if seat < 0:
		return
	summary = summary.duplicate(true)
	summary["seat"] = seat
	summary["seat_id"] = seat
	_host_begin_round_summary_gate(TypedVariant.as_int(summary.get("round", -1), -1))
	_ingest_round_summary(seat, summary)


func _host_begin_round_summary_gate(round_id: int) -> void:
	if not is_host:
		return
	## New round id → restart collection; same / missing id keeps open gate.
	if _round_summary_gate_open and round_id >= 0 and _round_summary_round_id >= 0 and round_id != _round_summary_round_id:
		_finish_round_standings_collection()
	if not _round_summary_gate_open:
		_round_summary_gate_open = true
		_round_summary_seats.clear()
		_round_summary_by_seat.clear()
		_round_summary_round_id = round_id
		## Mark only seats outside the barrier cohort — AI must be host-injected, not auto-ready.
		var need: Dictionary = {}
		for i: int in _iter_barrier_seats():
			need[i] = true
		for i: int in _iter_contestant_seats():
			if not TypedVariant.as_bool(need.get(i, false), false):
				_round_summary_seats[i] = true
		get_tree().create_timer(6.0).timeout.connect(_finish_round_standings_collection, CONNECT_ONE_SHOT)
		SessionDiagnostics.log("net.round_summary", "gate_open round=%d" % round_id)
	elif round_id >= 0 and _round_summary_round_id < 0:
		_round_summary_round_id = round_id


func _ingest_round_summary(seat: int, summary: Dictionary) -> void:
	if seat < 0:
		return
	_round_summary_seats[seat] = true
	_round_summary_by_seat[seat] = summary
	_check_round_standings_ready()


func _check_round_standings_ready() -> void:
	if not is_host or not _round_summary_gate_open:
		return
	## Only humans block; AI rows come from host_inject (or timeout synthesize).
	for i: int in _iter_barrier_seats():
		if TypedVariant.as_bool(_seat_row(i).get("is_ai", false), false):
			continue
		if not TypedVariant.as_bool(_round_summary_seats.get(i, false), false):
			return
	_finish_round_standings_collection()


func _finish_round_standings_collection() -> void:
	if not is_host or not _round_summary_gate_open:
		return
	_round_summary_gate_open = false
	## Stitch every contestant: live human summaries + AI injects + absent fillers.
	var summaries: Array = []
	var seen: Dictionary = {}
	for i: int in _iter_contestant_seats_including_ghosts():
		var row_v: Variant = _round_summary_by_seat.get(i, null)
		if typeof(row_v) == TYPE_DICTIONARY:
			var s: Dictionary = TypedVariant.as_dict(row_v).duplicate(true)
			s["seat"] = i
			s["seat_id"] = i
			summaries.append(s)
			seen[i] = true
			continue
		summaries.append(_synthesize_round_summary(i))
		seen[i] = true
	for seat_v: Variant in _round_summary_by_seat.keys():
		var sid: int = TypedVariant.as_int(seat_v, -1)
		if sid < 0 or TypedVariant.as_bool(seen.get(sid, false), false):
			continue
		summaries.append(_round_summary_by_seat[seat_v])
	var payload: Dictionary = {
		"round": _round_summary_round_id,
		"summaries": summaries,
	}
	print("[mp.diag] round_standings_ready n=%d round=%d" % [summaries.size(), _round_summary_round_id])
	SessionDiagnostics.log("net.round_standings", "broadcast n=%d round=%d" % [summaries.size(), _round_summary_round_id])
	_round_summary_by_seat.clear()
	_round_summary_seats.clear()
	if multiplayer.has_multiplayer_peer():
		rpc("rpc_round_standings", payload)
	else:
		_apply_round_standings_local(payload)
		round_standings_received.emit(payload)


func _synthesize_round_summary(seat: int) -> Dictionary:
	var row: Dictionary = _seat_row(seat)
	var prev: Dictionary = TypedVariant.as_dict(_last_standings_by_seat.get(seat, {}))
	return {
		"seat": seat,
		"seat_id": seat,
		"rival": TypedVariant.as_int(prev.get("rival", -1), -1),
		"result": str(prev.get("result", "—")),
		"titles": TypedVariant.as_array(prev.get("titles", [])).duplicate(),
		"w": TypedVariant.as_int(prev.get("w", 0), 0),
		"l": TypedVariant.as_int(prev.get("l", 0), 0),
		"d": TypedVariant.as_int(prev.get("d", 0), 0),
		"is_ai": TypedVariant.as_bool(row.get("is_ai", false), false),
		"absent": true,
		"nick": str(row.get("nick", "席位%d" % seat)),
	}


func _apply_round_standings_local(standings: Dictionary) -> void:
	for s_v: Variant in TypedVariant.as_array(standings.get("summaries", [])):
		var s: Dictionary = TypedVariant.as_dict(s_v)
		var seat: int = TypedVariant.as_int(s.get("seat", s.get("seat_id", -1)), -1)
		if seat < 0:
			continue
		_last_standings_by_seat[seat] = s.duplicate(true)


@rpc("authority", "reliable", "call_local")
func rpc_round_standings(standings: Dictionary) -> void:
	_apply_round_standings_local(standings)
	var n: int = TypedVariant.as_array(standings.get("summaries", [])).size()
	SessionDiagnostics.log(
		"net.round_standings",
		"recv n=%d round=%d host=%d" % [
			n,
			TypedVariant.as_int(standings.get("round", -1), -1),
			1 if is_host else 0,
		]
	)
	round_standings_received.emit(standings)


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
		var solo_players: Array = [local_summary]
		## Prefer full contestant list when standings already know every seat.
		if not _last_standings_by_seat.is_empty():
			solo_players = _players_from_standings_and_local(local_summary)
		var report: Dictionary = NullsecSettlement.make_match_report(match_id, local_seat, solo_players)
		SessionDiagnostics.log("net.match_report", "solo players=%d" % solo_players.size())
		match_report_received.emit(report)
		return
	if local_seat >= 0:
		local_summary["seat_id"] = local_seat
	if not is_host:
		rpc_id(1, "rpc_seat_match_summary", local_summary)
		SessionDiagnostics.log("net.match_report", "guest_submit seat=%d" % local_seat)
		return
	## After a full broadcast, late summaries merge — never wipe players.
	if _match_report_broadcast_done:
		_merge_late_match_summary(local_seat, local_summary)
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
	if _match_report_broadcast_done:
		_merge_late_match_summary(seat, summary)
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
	if not is_host:
		return
	## Allow one-shot finish even if gate already closed (timer + ready race).
	if not _match_report_gate_open and _match_report_broadcast_done:
		return
	_match_report_gate_open = false
	var players: Array = _build_full_match_report_players()
	## Never shrink below a previously broadcast full list.
	if not _last_match_report_players.is_empty() and players.size() < _last_match_report_players.size():
		players = _merge_player_rows_prefer_full(_last_match_report_players, players)
	_last_match_report_players = players.duplicate(true)
	_match_report_broadcast_done = true
	print("[mp.diag] match_report_ready players=%d" % players.size())
	SessionDiagnostics.log("net.match_report", "broadcast players=%d" % players.size())
	rpc("rpc_match_report", NullsecSettlement.make_match_report(match_id, local_seat, players))


func _build_full_match_report_players() -> Array:
	var players: Array = []
	var seen: Dictionary = {}
	## Prefer live summaries; fill every contestant seat (AI / absent / disconnected).
	for i: int in _iter_contestant_seats_including_ghosts():
		var summary_v: Variant = _match_report_summaries.get(i, null)
		if typeof(summary_v) == TYPE_DICTIONARY:
			var s: Dictionary = TypedVariant.as_dict(summary_v).duplicate(true)
			s["seat_id"] = i
			players.append(_enrich_report_row_from_standings(s, i))
			seen[i] = true
			continue
		players.append(_enrich_report_row_from_standings(_synthesize_absent_summary(i), i))
		seen[i] = true
	## Also keep any extra summaries that somehow weren't in contestant iter.
	for seat_v: Variant in _match_report_summaries.keys():
		var sid: int = TypedVariant.as_int(seat_v, -1)
		if sid < 0 or TypedVariant.as_bool(seen.get(sid, false), false):
			continue
		players.append(_enrich_report_row_from_standings(TypedVariant.as_dict(_match_report_summaries[seat_v]), sid))
	return players


func _enrich_report_row_from_standings(row: Dictionary, seat: int) -> Dictionary:
	var out: Dictionary = row.duplicate(true)
	out["seat_id"] = seat
	var st: Dictionary = TypedVariant.as_dict(_last_standings_by_seat.get(seat, {}))
	if st.is_empty():
		return out
	## Fill empty WLD / titles from last round standings (never wipe richer local rows).
	if TypedVariant.as_int(out.get("wins", 0), 0) == 0 and TypedVariant.as_int(out.get("losses", 0), 0) == 0 \
			and TypedVariant.as_int(out.get("draws", 0), 0) == 0:
		out["wins"] = TypedVariant.as_int(st.get("w", 0), 0)
		out["losses"] = TypedVariant.as_int(st.get("l", 0), 0)
		out["draws"] = TypedVariant.as_int(st.get("d", 0), 0)
	var titles: Array = TypedVariant.as_array(out.get("titles", []))
	if titles.is_empty():
		out["titles"] = TypedVariant.as_array(st.get("titles", [])).duplicate()
	return out


func _players_from_standings_and_local(local_summary: Dictionary) -> Array:
	var players: Array = []
	var seen: Dictionary = {}
	var local_sid: int = TypedVariant.as_int(local_summary.get("seat_id", local_seat), local_seat)
	for i: int in _iter_contestant_seats_including_ghosts():
		if i == local_sid:
			players.append(local_summary)
			seen[i] = true
			continue
		var st: Dictionary = TypedVariant.as_dict(_last_standings_by_seat.get(i, {}))
		if not st.is_empty():
			var row: Dictionary = _synthesize_absent_summary(i)
			row["absent"] = false
			row["wins"] = TypedVariant.as_int(st.get("w", 0), 0)
			row["losses"] = TypedVariant.as_int(st.get("l", 0), 0)
			row["draws"] = TypedVariant.as_int(st.get("d", 0), 0)
			row["titles"] = TypedVariant.as_array(st.get("titles", [])).duplicate()
			players.append(row)
			seen[i] = true
			continue
		players.append(_synthesize_absent_summary(i))
		seen[i] = true
	if local_sid >= 0 and not TypedVariant.as_bool(seen.get(local_sid, false), false):
		players.insert(0, local_summary)
	return players


func _merge_late_match_summary(seat: int, summary: Dictionary) -> void:
	if seat < 0:
		return
	_match_report_summaries[seat] = summary
	var players: Array = _build_full_match_report_players()
	if not _last_match_report_players.is_empty():
		players = _merge_player_rows_prefer_full(_last_match_report_players, players)
	## Only rebroadcast when player count grows or a previously empty seat gained data.
	if players.size() < _last_match_report_players.size():
		SessionDiagnostics.log("net.match_report", "late_merge_skip shrink n=%d" % players.size())
		return
	_last_match_report_players = players.duplicate(true)
	SessionDiagnostics.log("net.match_report", "late_rebroadcast players=%d" % players.size())
	rpc("rpc_match_report", NullsecSettlement.make_match_report(match_id, local_seat, players))


func _merge_player_rows_prefer_full(prev: Array, cur: Array) -> Array:
	var by_seat: Dictionary = {}
	for p_v: Variant in prev:
		var p: Dictionary = TypedVariant.as_dict(p_v)
		var sid: int = TypedVariant.as_int(p.get("seat_id", -1), -1)
		if sid >= 0:
			by_seat[sid] = p.duplicate(true)
	for p_v2: Variant in cur:
		var p2: Dictionary = TypedVariant.as_dict(p_v2)
		var sid2: int = TypedVariant.as_int(p2.get("seat_id", -1), -1)
		if sid2 < 0:
			continue
		if not by_seat.has(sid2):
			by_seat[sid2] = p2.duplicate(true)
			continue
		var old: Dictionary = by_seat[sid2]
		## Prefer non-absent / richer WLD / titles.
		if TypedVariant.as_bool(old.get("absent", false), false) and not TypedVariant.as_bool(p2.get("absent", false), false):
			by_seat[sid2] = p2.duplicate(true)
			continue
		var old_wld: int = TypedVariant.as_int(old.get("wins", 0), 0) + TypedVariant.as_int(old.get("losses", 0), 0) + TypedVariant.as_int(old.get("draws", 0), 0)
		var new_wld: int = TypedVariant.as_int(p2.get("wins", 0), 0) + TypedVariant.as_int(p2.get("losses", 0), 0) + TypedVariant.as_int(p2.get("draws", 0), 0)
		if new_wld > old_wld:
			by_seat[sid2] = p2.duplicate(true)
			continue
		if TypedVariant.as_array(old.get("titles", [])).is_empty() and not TypedVariant.as_array(p2.get("titles", [])).is_empty():
			old["titles"] = TypedVariant.as_array(p2.get("titles", [])).duplicate()
			by_seat[sid2] = old
	var out: Array = []
	for i: int in _iter_contestant_seats_including_ghosts():
		if by_seat.has(i):
			out.append(by_seat[i])
		else:
			out.append(_synthesize_absent_summary(i))
	for sid_v: Variant in by_seat.keys():
		var sid3: int = TypedVariant.as_int(sid_v, -1)
		var already: bool = false
		for o_v: Variant in out:
			if TypedVariant.as_int(TypedVariant.as_dict(o_v).get("seat_id", -1), -1) == sid3:
				already = true
				break
		if not already:
			out.append(by_seat[sid_v])
	return out


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
	var n: int = TypedVariant.as_array(report.get("players", [])).size()
	SessionDiagnostics.log(
		"net.match_report",
		"recv players=%d provisional=%d host=%d" % [
			n,
			1 if TypedVariant.as_bool(report.get("provisional", false), false) else 0,
			1 if is_host else 0,
		]
	)
	## Refuse to apply a shrunk report over a fuller one already shown this match.
	if n > 0 and not _last_match_report_players.is_empty() and n < _last_match_report_players.size():
		SessionDiagnostics.log("net.match_report", "reject_shrink have=%d got=%d" % [_last_match_report_players.size(), n])
		return
	if n > 0:
		_last_match_report_players = TypedVariant.as_array(report.get("players", [])).duplicate(true)
		_match_report_broadcast_done = true
	match_report_received.emit(report)


## Host-only escape hatch: caller already assembled every contestant's row (e.g. merged
## locally instead of via the per-seat summary gate) — build the §7 report and broadcast
## it directly, skipping `begin_match_report_collection`'s barrier/timeout bookkeeping.
func host_build_and_broadcast_match_report(players: Array) -> void:
	if not is_host:
		return
	var full: Array = players.duplicate(true)
	if not _last_match_report_players.is_empty() and full.size() < _last_match_report_players.size():
		full = _merge_player_rows_prefer_full(_last_match_report_players, full)
	## Ensure every contestant seat is present.
	var have: Dictionary = {}
	for p_v: Variant in full:
		have[TypedVariant.as_int(TypedVariant.as_dict(p_v).get("seat_id", -1), -1)] = true
	for i: int in _iter_contestant_seats_including_ghosts():
		if not TypedVariant.as_bool(have.get(i, false), false):
			full.append(_enrich_report_row_from_standings(_synthesize_absent_summary(i), i))
	_last_match_report_players = full.duplicate(true)
	_match_report_broadcast_done = true
	var report: Dictionary = NullsecSettlement.make_match_report(match_id, local_seat, full)
	SessionDiagnostics.log("net.match_report", "host_build players=%d" % full.size())
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
## Lobby transfer = seat0 handoff + old host leave/rejoin (SEMI_ASYNC §5.3a).


func _swap_seat_rows(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= seats.size() or b >= seats.size():
		return
	var ra: Variant = seats[a]
	var rb: Variant = seats[b]
	seats[a] = rb
	seats[b] = ra
	if seats[a] is Dictionary:
		var da: Dictionary = seats[a]
		da["seat_id"] = a
		seats[a] = da
	if seats[b] is Dictionary:
		var db: Dictionary = seats[b]
		db["seat_id"] = b
		seats[b] = db


func _vacate_seat_row(seat: int) -> void:
	if seat < 0 or seat >= seats.size():
		return
	seats[seat] = _empty_seat_dict(seat)


func transfer_host_to_seat(seat: int) -> void:
	if not is_room_host():
		_heal_host_role_from_peer()
		if not is_room_host():
			return
	if match_started:
		lobby_notice.emit("对局中不能转移房主")
		return
	if seat < 0 or seat >= seats.size() or seat == local_seat:
		return
	var row: Dictionary = _seat_row(seat)
	if not TypedVariant.as_bool(row.get("occupied", false), false):
		return
	if TypedVariant.as_bool(row.get("ghost", false), false):
		return
	if seat_is_proxy(row):
		lobby_notice.emit("不能转移房主给人机")
		return
	var plat: String = str(row.get("platform", "pc"))
	if plat == "mobile" and not is_lowsec(security_mode) and player_count() > 5:
		lobby_notice.emit("手机新房主参赛超过 5 人，无法转让")
		return
	var peer_id: int = TypedVariant.as_int(row.get("peer_id", 0), 0)
	_capture_peer_endpoint(seat, peer_id)
	var hip: String = str(row.get("endpoint_ip", "")).strip_edges()
	if peer_id <= 0 or hip == "" or hip == "0.0.0.0":
		lobby_notice.emit("目标端点不可用")
		SessionDiagnostics.log(
			"net.transfer.begin",
			"fail=endpoint seat=%d peer=%d ip=%s" % [seat, peer_id, hip]
		)
		return
	var hport: int = port_for_code(room_code)
	host_migrate_generation += 1
	_pending_transfer_seat = seat
	_pending_transfer_gen = host_migrate_generation
	## In-place: no seat swap — promote target seat; everyone keeps local_seat.
	if last_match_payload.is_empty():
		last_match_payload = {}
	last_match_payload["host_seat"] = seat
	last_match_payload["host_migrate_generation"] = host_migrate_generation
	var keep_code: int = room_code
	var keep_pw: String = room_password
	var keep_rh: String = rules_hash if rules_hash != "" else MatchRng.compute_rules_hash()
	var keep_nick: String = local_nick
	var keep_sec: String = security_mode
	var old_seat: int = local_seat
	var old_secret: String = session_secret
	SessionDiagnostics.log(
		"net.host_transfer",
		"seat=%d in_place=1 peer=%d ep=%s:%d gen=%d" % [
			seat, peer_id, hip, hport, host_migrate_generation
		]
	)
	rpc_id(peer_id, "rpc_transfer_host_promote", host_migrate_generation, seat)
	rpc(
		"rpc_transfer_guest_reconnect",
		host_migrate_generation,
		hip,
		hport,
		keep_code,
		keep_pw,
		keep_rh,
		peer_id,
		seat
	)
	call_deferred(
		"_old_host_demote_and_rejoin",
		hip, hport, keep_nick, keep_rh, keep_pw, keep_code, keep_sec, old_seat, old_secret, seat
	)


@rpc("authority", "call_remote", "reliable")
func rpc_transfer_take_seat0(
	generation: int,
	seats_snap: Array,
	code: int,
	password: String,
	expect_hash: String,
	sec_mode: String
) -> void:
	_transfer_take_seat0_inflight = true
	_pending_transfer_seat = 0
	_pending_transfer_gen = generation
	host_migrate_generation = generation
	seats = seats_snap.duplicate(true)
	local_seat = 0
	room_code = clampi(code, 1, 9999)
	room_password = str(password)
	room_has_password = not room_password.is_empty()
	rules_hash = expect_hash if expect_hash != "" else MatchRng.compute_rules_hash()
	security_mode = sec_mode if sec_mode != "" else SECURITY_NULLSEC
	opening_host_platform = detect_local_platform()
	host_player_cap = detect_host_player_cap()
	if last_match_payload.is_empty():
		last_match_payload = {}
	last_match_payload["host_seat"] = 0
	last_match_payload["host_migrate_generation"] = generation
	SessionDiagnostics.log(
		"net.transfer.promote0",
		"gen=%d plat=%s code=%04d" % [generation, opening_host_platform, room_code]
	)
	await _promote_self_to_host(0)
	_transfer_take_seat0_inflight = false
	_pending_transfer_seat = -1
	seat_sync.emit(seats)


@rpc("authority", "call_remote", "reliable")
func rpc_transfer_guest_reconnect(
	generation: int,
	host_ip: String,
	host_port: int,
	code: int,
	password: String,
	expect_hash: String,
	new_host_peer_id: int,
	new_host_seat: int = -1
) -> void:
	if _transfer_take_seat0_inflight:
		return
	if new_host_peer_id > 0 and multiplayer != null and multiplayer.get_unique_id() == new_host_peer_id:
		return
	if is_host:
		return
	host_migrate_generation = generation
	var hs: int = new_host_seat if new_host_seat >= 0 else 0
	_pending_transfer_seat = hs
	_pending_transfer_gen = generation
	if host_ip != "":
		last_known_host_ip = host_ip
	room_code = clampi(code, 1, 9999)
	room_password = str(password)
	room_has_password = not room_password.is_empty()
	if expect_hash != "":
		rules_hash = expect_hash
	if last_match_payload.is_empty():
		last_match_payload = {}
	last_match_payload["host_seat"] = hs
	last_match_payload["host_migrate_generation"] = generation
	var keep_seat: int = local_seat
	var keep_secret: String = session_secret
	var keep_seats: Array = seats.duplicate(true)
	var keep_nick: String = local_nick
	var keep_pw: String = room_password
	var keep_rh: String = rules_hash
	_teardown_peer_only()
	pending_rejoin_seat = keep_seat
	pending_rejoin_secret = keep_secret
	var tree: SceneTree = get_tree()
	if tree == null or host_ip == "" or host_ip == "0.0.0.0":
		_pending_transfer_seat = -1
		seats = keep_seats
		local_seat = keep_seat
		seat_sync.emit(seats)
		lobby_notice.emit("转让后重连失败")
		return
	tree.create_timer(0.65).timeout.connect(func() -> void:
		var err: Error = join(host_ip, host_port, keep_nick, keep_rh, keep_pw)
		seats = keep_seats
		local_seat = keep_seat
		pending_rejoin_seat = keep_seat
		pending_rejoin_secret = keep_secret
		seat_sync.emit(seats)
		_pending_transfer_seat = -1
		SessionDiagnostics.log(
			"net.transfer.guest_rejoin",
			"err=%d seat=%d host_seat=%d ep=%s:%d" % [err, keep_seat, hs, host_ip, host_port]
		)
		if err != OK:
			lobby_notice.emit("转让后重连失败")
	)


func _old_host_demote_and_rejoin(
	hip: String,
	hport: int,
	nick: String,
	expect_hash: String,
	password: String,
	code: int,
	sec_mode: String,
	keep_seat: int,
	keep_secret: String,
	new_host_seat: int
) -> void:
	var gen: int = host_migrate_generation
	_set_host_role(false)
	## Release listen so designate can bind (same-PC / same port).
	_teardown_peer_only()
	is_host = false
	local_seat = keep_seat
	pending_rejoin_seat = keep_seat
	pending_rejoin_secret = keep_secret
	session_secret = keep_secret
	match_started = false
	room_code = clampi(code, 1, 9999)
	room_password = password
	room_has_password = not password.is_empty()
	rules_hash = expect_hash if expect_hash != "" else MatchRng.compute_rules_hash()
	security_mode = sec_mode if sec_mode != "" else SECURITY_NULLSEC
	local_nick = nick
	_pending_transfer_seat = -1
	if last_match_payload.is_empty():
		last_match_payload = {}
	last_match_payload["host_seat"] = new_host_seat
	last_match_payload["host_migrate_generation"] = gen
	seat_sync.emit(seats)
	host_migrated.emit(gen, new_host_seat)
	host_role_changed.emit(false)
	lobby_notice.emit("已转让房主 · 正在以客机重连…")
	var tree: SceneTree = get_tree()
	if tree == null or hip == "" or hip == "0.0.0.0":
		SessionDiagnostics.log("net.transfer.old_host_rejoin", "fail=no_endpoint")
		lobby_notice.emit("转让后重连失败")
		return
	tree.create_timer(0.75).timeout.connect(func() -> void:
		pending_rejoin_seat = keep_seat
		pending_rejoin_secret = keep_secret
		var err: Error = join(hip, hport, nick, expect_hash, password)
		SessionDiagnostics.log(
			"net.transfer.old_host_rejoin",
			"err=%d seat=%d host_seat=%d ep=%s:%d" % [err, keep_seat, new_host_seat, hip, hport]
		)
		if err != OK:
			lobby_notice.emit("转让后重连失败")
	)


## Legacy seat0 handoff kept for older peers; lobby uses in-place promote.
func _old_host_leave_and_rejoin(
	hip: String,
	hport: int,
	nick: String,
	expect_hash: String,
	password: String,
	code: int,
	sec_mode: String
) -> void:
	_old_host_demote_and_rejoin(hip, hport, nick, expect_hash, password, code, sec_mode, -1, "", 0)


## Legacy RPC names kept so older peers do not hard-error; lobby uses seat0 handoff.
@rpc("any_peer", "reliable")
func rpc_host_transfer_pending(seat: int, generation: int, host_ip: String, host_port: int) -> void:
	_pending_transfer_seat = seat
	_pending_transfer_gen = generation
	host_migrate_generation = generation
	if host_ip != "":
		last_known_host_ip = host_ip
	if last_match_payload.is_empty():
		last_match_payload = {}
	last_match_payload["host_seat"] = 0 if seat == 0 else seat
	last_match_payload["host_migrate_generation"] = generation
	if host_port > 0:
		pass


@rpc("any_peer", "reliable")
func rpc_transfer_host_promote(generation: int, seat: int) -> void:
	## Lobby / mid-match: promote this seat in place (no seat remap).
	if local_seat != seat:
		return
	if _transfer_take_seat0_inflight:
		return
	SessionDiagnostics.log(
		"net.transfer.promote",
		"seat=%d gen=%d in_place=1 plat=%s" % [seat, generation, detect_local_platform()]
	)
	host_migrate_generation = generation
	## Keep room-open platform for migration caps; refresh listen cap for this device.
	host_player_cap = detect_host_player_cap()
	if last_match_payload.is_empty():
		last_match_payload = {}
	last_match_payload["host_seat"] = seat
	last_match_payload["host_migrate_generation"] = generation
	await _promote_self_to_host(seat if seat >= 0 else 0)
	_pending_transfer_seat = -1


func urge_prepare(seat: int) -> void:
	_heal_host_role_from_peer()
	if not is_room_host():
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


## --- SEMI_ASYNC §3.0c probe ---

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
