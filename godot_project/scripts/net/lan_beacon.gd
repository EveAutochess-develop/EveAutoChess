extends Node
class_name LanBeacon
## SEMI_ASYNC §7.5 LAN discovery: hosts announce on BEACON_PORT; matchers listen.
##
## Android Emulator ≥36.5: peer AVDs share virtual Wi-Fi (`AndroidWifi`).
## Each gets `10.0.2.16+` on wlan0 (eth0 stays isolated `10.0.2.15`).
## Legacy `-shared-net-id N` → `10.1.2.N` still supported when present.
##
## Real Android Wi‑Fi often RX-filters UDP broadcast (PC hears phone; phone misses PC).
## Discover on Android sprays unicast probes across local /24 so PC hosts answer.

const BEACON_PORT: int = 24567
const ANNOUNCE_INTERVAL_S: float = 0.4
## Must cover ≥1 announce interval + probe RTT. 0.35s was shorter than announce → miss.
const DISCOVER_WAIT_S: float = 1.6
const DISCOVER_WAIT_EMULATOR_S: float = 2.0
const DISCOVER_WAIT_ANDROID_S: float = 2.2
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
	## Bind IPv4 explicitly — Android TYPE_ANY ("*") often mishandles IPv4 broadcast RX/TX.
	var err: Error = _udp.bind(BEACON_PORT, "0.0.0.0")
	if err != OK:
		_udp.close()
		_udp = PacketPeerUDP.new()
		err = _udp.bind(0, "0.0.0.0")
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
	return _peer_destinations(IP.get_local_addresses(), false)


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
	## Prefer session LAN IP; refresh if empty so announce carries a joinable endpoint.
	var hip: String = ""
	if _session.has_method("advertise_lan_ip"):
		hip = str(_session.call("advertise_lan_ip")).strip_edges()
	else:
		hip = str(_session.last_known_host_ip).strip_edges()
	## All scored LAN IPv4s — guest tries each when multi-NIC / VPN mis-picks primary.
	var all_ips: Array = []
	for row_v: Variant in LanAffinity.scored_local_ipv4s():
		var row: Dictionary = TypedVariant.as_dict(row_v)
		var lip: String = str(row.get("ip", "")).strip_edges()
		if lip != "" and not all_ips.has(lip):
			all_ips.append(lip)
	if hip != "" and not all_ips.has(hip):
		all_ips.insert(0, hip)
	elif hip == "" and not all_ips.is_empty():
		hip = str(all_ips[0])
	var payload: Dictionary = {
		"v": 2,
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
		## SEMI_ASYNC §7.5 — join IP in payload (Android get_packet_ip often empty).
		"ip": hip,
		"ips": all_ips,
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


## Directed /24 broadcast for a unicast IPv4 (home LAN). Empty if not usable.
static func _subnet_broadcast_24(ip: String) -> String:
	if ip == "" or ip.find(":") >= 0:
		return ""
	if ip.begins_with("127.") or ip.begins_with("169.254."):
		return ""
	var parts: PackedStringArray = ip.split(".")
	if parts.size() != 4:
		return ""
	for p: String in parts:
		if not p.is_valid_int():
			return ""
	## Skip emulator isolated NAT + already-handled Wi-Fi / shared-net (dedicated paths).
	if ip == "10.0.2.15":
		return ""
	if ip.begins_with(SHARED_NET_PREFIX) or _is_emu_wifi_peer(ip):
		return ""
	return "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]


static func _subnet_prefix_24(ip: String) -> String:
	if _subnet_broadcast_24(ip) == "":
		return ""
	var parts: PackedStringArray = ip.split(".")
	return "%s.%s.%s." % [parts[0], parts[1], parts[2]]


## discover_mode: on real Android, also unicast-probe the whole /24 (broadcast RX filtered).
static func _peer_destinations(addrs: PackedStringArray, discover_mode: bool = false) -> PackedStringArray:
	var out: PackedStringArray = ["255.255.255.255"]
	var seen: Dictionary = {"255.255.255.255": true}
	var self_shared: String = ""
	var self_wifi: String = ""
	var lan_prefixes: PackedStringArray = PackedStringArray()
	for a: String in addrs:
		if a.begins_with(SHARED_NET_PREFIX) and self_shared.is_empty():
			self_shared = a
		if _is_emu_wifi_peer(a) and self_wifi.is_empty():
			self_wifi = a
		var bcast: String = _subnet_broadcast_24(a)
		if bcast != "" and not seen.has(bcast):
			seen[bcast] = true
			out.append(bcast)
		var pref: String = _subnet_prefix_24(a)
		if pref != "" and not lan_prefixes.has(pref):
			lan_prefixes.append(pref)
	if not self_shared.is_empty():
		if not seen.has(SHARED_NET_BROADCAST):
			seen[SHARED_NET_BROADCAST] = true
			out.append(SHARED_NET_BROADCAST)
		for i: int in range(1, SHARED_NET_ID_MAX + 1):
			var peer: String = "%s%d" % [SHARED_NET_PREFIX, i]
			if peer != self_shared and not seen.has(peer):
				seen[peer] = true
				out.append(peer)
	if not self_wifi.is_empty():
		if not seen.has(EMU_WIFI_BROADCAST):
			seen[EMU_WIFI_BROADCAST] = true
			out.append(EMU_WIFI_BROADCAST)
		for i: int in range(EMU_WIFI_PEER_FIRST, EMU_WIFI_PEER_LAST + 1):
			var peer_w: String = "%s%d" % [EMU_WIFI_PREFIX, i]
			if peer_w != self_wifi and not seen.has(peer_w):
				seen[peer_w] = true
				out.append(peer_w)
	elif is_android_emulator():
		## eth0-only 10.0.2.15: isolated NAT. Still spray Wi-Fi peer range in case
		## wlan0 comes up mid-session (AndroidWifi).
		if not seen.has(EMU_WIFI_BROADCAST):
			out.append(EMU_WIFI_BROADCAST)
		for i: int in range(EMU_WIFI_PEER_FIRST, EMU_WIFI_PEER_LAST + 1):
			out.append("%s%d" % [EMU_WIFI_PREFIX, i])
		print("[LanBeacon] emulator: prefer AndroidWifi (10.0.2.16+) — eth0 10.0.2.15 is isolated")
	## Real Android discover: unicast /24 so PC hosts reply even when broadcast RX is dead.
	if discover_mode and OS.get_name() == "Android" and not is_android_emulator():
		for pref: String in lan_prefixes:
			for i: int in range(1, 255):
				var peer_lan: String = "%s%d" % [pref, i]
				if seen.has(peer_lan):
					continue
				## Skip self addresses.
				var is_self: bool = false
				for a2: String in addrs:
					if a2 == peer_lan:
						is_self = true
						break
				if is_self:
					continue
				seen[peer_lan] = true
				out.append(peer_lan)
		print("[LanBeacon] android discover: /24 unicast probe prefixes=%d dests=%d" % [lan_prefixes.size(), out.size()])
	return out


## Scan LAN for ~wait_s seconds. Returns Array of Dictionary room ads (with "ip").
static func discover(host: Node, wait_s: float = -1.0) -> Array:
	if host == null or not is_instance_valid(host):
		return []
	var wait: float = wait_s
	if wait < 0.0:
		if is_android_emulator():
			wait = DISCOVER_WAIT_EMULATOR_S
		elif OS.get_name() == "Android":
			wait = DISCOVER_WAIT_ANDROID_S
		else:
			wait = DISCOVER_WAIT_S
	var runner: _DiscoverRunner = _DiscoverRunner.new()
	host.add_child(runner)
	var rooms: Array = await runner.run(wait)
	return rooms


class _DiscoverRunner extends Node:
	func run(wait_s: float) -> Array:
		var udp: PacketPeerUDP = PacketPeerUDP.new()
		var err: Error = udp.bind(LanBeacon.BEACON_PORT, "0.0.0.0")
		if err != OK:
			## Another process may hold the beacon port — still try broadcast probe + ephemeral listen.
			udp.close()
			udp = PacketPeerUDP.new()
			err = udp.bind(0, "0.0.0.0")
			if err != OK:
				queue_free()
				return []
		udp.set_broadcast_enabled(true)
		var probe: PackedByteArray = JSON.stringify({"v": 1, "q": "eac_probe"}).to_utf8_buffer()
		var dests: PackedStringArray = LanBeacon._peer_destinations(IP.get_local_addresses(), true)
		_send_probe_to(udp, probe, dests)
		var found: Dictionary = {} ## key -> ad
		var end_ms: int = Time.get_ticks_msec() + int(maxf(wait_s, 0.05) * 1000.0)
		var next_probe_ms: int = Time.get_ticks_msec() + int(LanBeacon.ANNOUNCE_INTERVAL_S * 1000.0)
		while Time.get_ticks_msec() < end_ms:
			if Time.get_ticks_msec() >= next_probe_ms:
				_send_probe_to(udp, probe, dests)
				next_probe_ms = Time.get_ticks_msec() + int(LanBeacon.ANNOUNCE_INTERVAL_S * 1000.0)
			while udp.get_available_packet_count() > 0:
				var packet_ip: String = udp.get_packet_ip()
				var pkt: PackedByteArray = udp.get_packet()
				var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
				if typeof(parsed) != TYPE_DICTIONARY:
					continue
				var d: Dictionary = parsed
				if str(d.get("q", "")) != "eac_announce":
					continue
				var payload_ip: String = str(d.get("ip", "")).strip_edges()
				var src_ip: String = packet_ip.strip_edges()
				var src_ok: bool = src_ip != "" and src_ip != "0.0.0.0" and not src_ip.begins_with("127.")
				var pay_ok: bool = (
					payload_ip != "" and payload_ip != "0.0.0.0" and not payload_ip.begins_with("127.")
				)
				## SEMI_ASYNC §7.5 — packet source preferred; payload + ips[] as alts.
				var ip: String = ""
				var alt_ips: Array = []
				if src_ok:
					ip = src_ip
					if pay_ok and payload_ip != src_ip:
						alt_ips.append(payload_ip)
				elif pay_ok:
					ip = payload_ip
				var payload_ips_v: Variant = d.get("ips", [])
				if payload_ips_v is Array:
					for iv: Variant in payload_ips_v:
						var extra_ip: String = str(iv).strip_edges()
						if extra_ip == "" or extra_ip == "0.0.0.0" or extra_ip.begins_with("127."):
							continue
						if extra_ip != ip and not alt_ips.has(extra_ip):
							alt_ips.append(extra_ip)
				## Never invent 127.0.0.1 (beacon visible but unjoinable).
				if ip == "" or ip == "0.0.0.0" or ip.begins_with("127."):
					continue
				d["ip"] = ip
				d["packet_ip"] = src_ip
				d["payload_ip"] = payload_ip
				d["alt_ips"] = alt_ips
				var ips_all: Array = alt_ips.duplicate()
				if not ips_all.has(ip):
					ips_all.insert(0, ip)
				d["ips"] = ips_all
				var key: String = "%s:%s:%s" % [d["ip"], str(d.get("port", 0)), str(d.get("code", 0))]
				found[key] = d
				## Also keep each alt as its own candidate row.
				for alt_v: Variant in alt_ips:
					var alt_ip: String = str(alt_v).strip_edges()
					if alt_ip == "" or alt_ip == ip:
						continue
					var d_alt: Dictionary = d.duplicate(true)
					d_alt["ip"] = alt_ip
					var key_alt: String = "%s:%s:%s" % [alt_ip, str(d.get("port", 0)), str(d.get("code", 0))]
					if not found.has(key_alt):
						found[key_alt] = d_alt
			await get_tree().process_frame
		udp.close()
		var out: Array = found.values()
		print("[LanBeacon] discover done wait=%.2f found=%d dests=%d" % [wait_s, out.size(), dests.size()])
		queue_free()
		return out

	func _send_probe_to(udp: PacketPeerUDP, probe: PackedByteArray, dests: PackedStringArray) -> void:
		for dest: String in dests:
			udp.set_dest_address(dest, LanBeacon.BEACON_PORT)
			udp.put_packet(probe)
