extends Node
class_name LanBeacon
## SEMI_ASYNC §7.5 LAN discovery: hosts announce on BEACON_PORT; matchers listen.

const BEACON_PORT := 24567
const ANNOUNCE_INTERVAL_S := 0.4
const DISCOVER_WAIT_S := 0.35

var _udp: PacketPeerUDP = null
var _session: NullsecNetSession = null
var _acc: float = 0.0


func start_for_host(session: NullsecNetSession) -> void:
	stop()
	_session = session
	_udp = PacketPeerUDP.new()
	## Ephemeral bind: announce-only; no conflict when many hosts share one PC.
	var err := _udp.bind(0)
	if err != OK:
		push_warning("[LanBeacon] bind ephemeral failed: %s" % error_string(err))
		_udp = null
		return
	_udp.set_broadcast_enabled(true)
	_acc = ANNOUNCE_INTERVAL_S
	set_process(true)
	_send_announce()


func stop() -> void:
	set_process(false)
	_session = null
	if _udp:
		_udp.close()
	_udp = null


func _process(delta: float) -> void:
	if _udp == null or _session == null:
		return
	_acc += delta
	if _acc >= ANNOUNCE_INTERVAL_S:
		_acc = 0.0
		_send_announce()
	## Reply to unicast probes (optional clients that target us).
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var txt := pkt.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(txt)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		if str((parsed as Dictionary).get("q", "")) != "eac_probe":
			continue
		_udp.set_dest_address(_udp.get_packet_ip(), _udp.get_packet_port())
		_udp.put_packet(_announce_bytes())


func _send_announce() -> void:
	if _udp == null or _session == null:
		return
	_udp.set_dest_address("255.255.255.255", BEACON_PORT)
	_udp.put_packet(_announce_bytes())


func _announce_bytes() -> PackedByteArray:
	var occupied := 0
	var players := 0
	for s in _session.seats:
		if bool(s.get("occupied", false)):
			occupied += 1
			if NullsecNetSession.is_player_race(str(s.get("titan_race", ""))):
				players += 1
	var payload := {
		"v": 1,
		"q": "eac_announce",
		"code": int(_session.room_code),
		"private": bool(_session.is_private),
		"private_code": str(_session.private_code),
		"rules": str(_session.rules_hash),
		"occupied": occupied,
		"cap": NullsecNetSession.SEAT_TOTAL,
		"players": players,
		"player_cap": int(_session.host_player_cap),
		"in_match": bool(_session.match_started),
		"nick": str(_session.local_nick),
		"port": int(_session.listen_port()),
	}
	return JSON.stringify(payload).to_utf8_buffer()


## Scan LAN for ~wait_s seconds. Returns Array of Dictionary room ads (with "ip").
static func discover(host: Node, wait_s: float = DISCOVER_WAIT_S) -> Array:
	if host == null or not is_instance_valid(host):
		return []
	var runner := _DiscoverRunner.new()
	host.add_child(runner)
	var rooms: Array = await runner.run(wait_s)
	return rooms


class _DiscoverRunner extends Node:
	func run(wait_s: float) -> Array:
		var udp := PacketPeerUDP.new()
		var err := udp.bind(LanBeacon.BEACON_PORT)
		if err != OK:
			## Another process may hold the beacon port — still try broadcast probe + ephemeral listen.
			udp.close()
			udp = PacketPeerUDP.new()
			err = udp.bind(0)
			if err != OK:
				queue_free()
				return []
		udp.set_broadcast_enabled(true)
		## Probe so announce-only hosts that also poll probes can reply (best-effort).
		var probe := JSON.stringify({"v": 1, "q": "eac_probe"}).to_utf8_buffer()
		udp.set_dest_address("255.255.255.255", LanBeacon.BEACON_PORT)
		udp.put_packet(probe)
		var found: Dictionary = {} ## key -> ad
		var end_ms := Time.get_ticks_msec() + int(maxf(wait_s, 0.05) * 1000.0)
		while Time.get_ticks_msec() < end_ms:
			while udp.get_available_packet_count() > 0:
				var ip := udp.get_packet_ip()
				var pkt := udp.get_packet()
				var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
				if typeof(parsed) != TYPE_DICTIONARY:
					continue
				var d: Dictionary = parsed
				if str(d.get("q", "")) != "eac_announce":
					continue
				d["ip"] = ip if ip != "" else "127.0.0.1"
				var key := "%s:%s:%s" % [d["ip"], str(d.get("port", 0)), str(d.get("code", 0))]
				found[key] = d
			await get_tree().process_frame
		udp.close()
		var out: Array = found.values()
		queue_free()
		return out
