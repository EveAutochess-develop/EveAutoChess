extends Node
class_name LanBeacon
## SEMI_ASYNC §7.5 LAN discovery: hosts announce on BEACON_PORT; matchers listen.
##
## Android Emulator ≥36.5: peer AVDs share virtual Wi-Fi (`AndroidWifi`).
## Each gets `10.0.2.16+` on wlan0 (eth0 stays isolated `10.0.2.15`).
## Legacy `-shared-net-id N` → `10.1.2.N` still supported when present.

const BEACON_PORT: int = 24567
const ANNOUNCE_INTERVAL_S: float = 0.4
const DISCOVER_WAIT_S: float = 0.35
const DISCOVER_WAIT_EMULATOR_S: float = 1.2
const SHARED_NET_PREFIX: String = "10.1.2."
const SHARED_NET_BROADCAST: String = "10.1.2.255"
const SHARED_NET_ID_MAX: int = 15
## Emulator Virtio Wi-Fi backplane (API Emulator 36.5+).
const EMU_WIFI_PREFIX: String = "10.0.2."
const EMU_WIFI_BROADCAST: String = "10.0.2.255"
const EMU_WIFI_PEER_FIRST: int = 16
const EMU_WIFI_PEER_LAST: int = 31


var _udp: PacketPeerUDP = null
var _session: NullsecNetSession = null
var _acc: float = 0.0


func start_for_host(session: NullsecNetSession) -> void:
	stop()
	_session = session
	_udp = PacketPeerUDP.new()
	## Prefer beacon port so we also answer unicast probes; fall back to ephemeral
	## when another local process already holds it (multi-host same PC).
	var err: Error = _udp.bind(BEACON_PORT)
	if err != OK:
		_udp.close()
		_udp = PacketPeerUDP.new()
		err = _udp.bind(0)
		if err != OK:
			push_warning("[LanBeacon] bind failed: %s" % error_string(err))
			_udp = null
			return
		print("[LanBeacon] host announce on ephemeral (beacon port busy)")
	else:
		print("[LanBeacon] host listening on beacon %d" % BEACON_PORT)
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
	## Reply to unicast / broadcast probes.
	while _udp.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _udp.get_packet()
		var txt: String = pkt.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(txt)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var parsed_d: Dictionary = parsed
		if str(parsed_d.get("q", "")) != "eac_probe":
			continue
		var rip: String = _udp.get_packet_ip()
		var rport: int = _udp.get_packet_port()
		if rip.is_empty():
			continue
		_udp.set_dest_address(rip, rport)
		_udp.put_packet(_announce_bytes())


func _send_announce() -> void:
	if _udp == null or _session == null:
		return
	var bytes: PackedByteArray = _announce_bytes()
	for dest: String in _announce_destinations():
		_udp.set_dest_address(dest, BEACON_PORT)
		_udp.put_packet(bytes)


func _announce_destinations() -> PackedStringArray:
	return _peer_destinations(IP.get_local_addresses())


func _announce_bytes() -> PackedByteArray:
	var occupied: int = 0
	var players: int = 0
	for s_v: Variant in _session.seats:
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = s_v
		if TypedVariant.as_bool(s.get("occupied", false), false):
			occupied += 1
			if NullsecNetSession.is_player_race(str(s.get("titan_race", ""))):
				players += 1
	var payload: Dictionary = {
		"v": 1,
		"q": "eac_announce",
		"code": int(_session.room_code),
		"rules": str(_session.rules_hash),
		"occupied": occupied,
		"cap": NullsecNetSession.SEAT_TOTAL,
		"players": players,
		"player_cap": int(_session.effective_player_cap()),
		"security_mode": str(_session.security_mode),
		"in_match": bool(_session.match_started),
		"nick": str(_session.local_nick),
		"port": int(_session.listen_port()),
	}
	return JSON.stringify(payload).to_utf8_buffer()


static func is_android_emulator() -> bool:
	if OS.get_name() != "Android":
		return false
	if OS.has_feature("emulator"):
		return true
	for a: String in IP.get_local_addresses():
		if a == "10.0.2.15" or a.begins_with(SHARED_NET_PREFIX):
			return true
		if _is_emu_wifi_peer(a):
			return true
	return false


static func on_shared_net() -> bool:
	for a: String in IP.get_local_addresses():
		if a.begins_with(SHARED_NET_PREFIX) or _is_emu_wifi_peer(a):
			return true
	return false


static func _is_emu_wifi_peer(ip: String) -> bool:
	if not ip.begins_with(EMU_WIFI_PREFIX):
		return false
	var tail: String = ip.substr(EMU_WIFI_PREFIX.length())
	if not tail.is_valid_int():
		return false
	var n: int = int(tail)
	return n >= EMU_WIFI_PEER_FIRST and n <= EMU_WIFI_PEER_LAST


static func _peer_destinations(addrs: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = ["255.255.255.255"]
	var self_shared: String = ""
	var self_wifi: String = ""
	for a: String in addrs:
		if a.begins_with(SHARED_NET_PREFIX) and self_shared.is_empty():
			self_shared = a
		if _is_emu_wifi_peer(a) and self_wifi.is_empty():
			self_wifi = a
	if not self_shared.is_empty():
		out.append(SHARED_NET_BROADCAST)
		for i: int in range(1, SHARED_NET_ID_MAX + 1):
			var peer: String = "%s%d" % [SHARED_NET_PREFIX, i]
			if peer != self_shared:
				out.append(peer)
	if not self_wifi.is_empty():
		out.append(EMU_WIFI_BROADCAST)
		for i: int in range(EMU_WIFI_PEER_FIRST, EMU_WIFI_PEER_LAST + 1):
			var peer_w: String = "%s%d" % [EMU_WIFI_PREFIX, i]
			if peer_w != self_wifi:
				out.append(peer_w)
	elif is_android_emulator():
		## eth0-only 10.0.2.15: isolated NAT. Still spray Wi-Fi peer range in case
		## wlan0 comes up mid-session (AndroidWifi).
		out.append(EMU_WIFI_BROADCAST)
		for i: int in range(EMU_WIFI_PEER_FIRST, EMU_WIFI_PEER_LAST + 1):
			out.append("%s%d" % [EMU_WIFI_PREFIX, i])
		print("[LanBeacon] emulator: prefer AndroidWifi (10.0.2.16+) — eth0 10.0.2.15 is isolated")
	return out


## Scan LAN for ~wait_s seconds. Returns Array of Dictionary room ads (with "ip").
static func discover(host: Node, wait_s: float = -1.0) -> Array:
	if host == null or not is_instance_valid(host):
		return []
	var wait: float = wait_s
	if wait < 0.0:
		wait = DISCOVER_WAIT_EMULATOR_S if is_android_emulator() else DISCOVER_WAIT_S
	var runner: _DiscoverRunner = _DiscoverRunner.new()
	host.add_child(runner)
	var rooms: Array = await runner.run(wait)
	return rooms


class _DiscoverRunner extends Node:
	func run(wait_s: float) -> Array:
		var udp: PacketPeerUDP = PacketPeerUDP.new()
		var err: Error = udp.bind(LanBeacon.BEACON_PORT)
		if err != OK:
			## Another process may hold the beacon port — still try broadcast probe + ephemeral listen.
			udp.close()
			udp = PacketPeerUDP.new()
			err = udp.bind(0)
			if err != OK:
				queue_free()
				return []
		udp.set_broadcast_enabled(true)
		var probe: PackedByteArray = JSON.stringify({"v": 1, "q": "eac_probe"}).to_utf8_buffer()
		for dest: String in LanBeacon._peer_destinations(IP.get_local_addresses()):
			udp.set_dest_address(dest, LanBeacon.BEACON_PORT)
			udp.put_packet(probe)
		var found: Dictionary = {} ## key -> ad
		var end_ms: int = Time.get_ticks_msec() + int(maxf(wait_s, 0.05) * 1000.0)
		while Time.get_ticks_msec() < end_ms:
			while udp.get_available_packet_count() > 0:
				var ip: String = udp.get_packet_ip()
				var pkt: PackedByteArray = udp.get_packet()
				var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
				if typeof(parsed) != TYPE_DICTIONARY:
					continue
				var d: Dictionary = parsed
				if str(d.get("q", "")) != "eac_announce":
					continue
				d["ip"] = ip if ip != "" else "127.0.0.1"
				var key: String = "%s:%s:%s" % [d["ip"], str(d.get("port", 0)), str(d.get("code", 0))]
				found[key] = d
			await get_tree().process_frame
		udp.close()
		var out: Array = found.values()
		queue_free()
		return out
