extends RefCounted
class_name StunClient
## SEMI_ASYNC §7.2 — RFC 5389 Binding Request → XOR-MAPPED-ADDRESS (IPv4).
## Uses an ephemeral UDP socket (ENet already owns the game listen port).
## Callers should publish mapped IP with the real listen_port in the invite blob.

const MAGIC: int = 0x2112A442
const BINDING_REQUEST: int = 0x0001
const BINDING_SUCCESS: int = 0x0101
const ATTR_XOR_MAPPED: int = 0x0020
const ATTR_MAPPED: int = 0x0001


static func discover_mapped_ipv4(stun_url: String, timeout_ms: int = 900) -> Dictionary:
	## Returns {} or { "ip": String, "port": int } (STUN-mapped port; prefer listen_port in blob).
	var host_port: Dictionary = _parse_stun_url(stun_url)
	if host_port.is_empty():
		return {}
	var host: String = str(host_port.get("host", ""))
	var port: int = TypedVariant.as_int(host_port.get("port", 3478), 3478)
	if host == "" or port <= 0:
		return {}
	var udp: PacketPeerUDP = PacketPeerUDP.new()
	if udp.bind(0) != OK:
		return {}
	udp.set_dest_address(host, port)
	var txid: PackedByteArray = PackedByteArray()
	txid.resize(12)
	for i: int in range(12):
		txid[i] = randi() & 0xFF
	var req: PackedByteArray = _build_binding_request(txid)
	udp.put_packet(req)
	var deadline: int = Time.get_ticks_msec() + maxi(200, timeout_ms)
	while Time.get_ticks_msec() < deadline:
		OS.delay_msec(20)
		while udp.get_available_packet_count() > 0:
			var pkt: PackedByteArray = udp.get_packet()
			var mapped: Dictionary = _parse_binding_success(pkt, txid)
			if not mapped.is_empty():
				udp.close()
				return mapped
	udp.close()
	return {}


static func discover_first(stun_urls: PackedStringArray, timeout_ms: int = 900) -> Dictionary:
	for u: String in stun_urls:
		var d: Dictionary = discover_mapped_ipv4(u, timeout_ms)
		if not d.is_empty():
			return d
	return {}


static func _parse_stun_url(raw: String) -> Dictionary:
	var s: String = raw.strip_edges()
	var low: String = s.to_lower()
	if low.begins_with("stun:"):
		s = s.substr(5)
	elif low.begins_with("stuns:"):
		s = s.substr(6)
	s = s.strip_edges()
	var q: int = s.find("?")
	if q >= 0:
		s = s.substr(0, q)
	var colon: int = s.rfind(":")
	if colon <= 0:
		return {"host": s, "port": 3478} if s != "" else {}
	var host: String = s.substr(0, colon).strip_edges()
	var port: int = TypedVariant.as_int(s.substr(colon + 1), 3478)
	if host == "":
		return {}
	return {"host": host, "port": port if port > 0 else 3478}


static func _build_binding_request(txid: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(20)
	out[0] = (BINDING_REQUEST >> 8) & 0xFF
	out[1] = BINDING_REQUEST & 0xFF
	out[2] = 0
	out[3] = 0
	out[4] = (MAGIC >> 24) & 0xFF
	out[5] = (MAGIC >> 16) & 0xFF
	out[6] = (MAGIC >> 8) & 0xFF
	out[7] = MAGIC & 0xFF
	for i: int in range(12):
		out[8 + i] = txid[i]
	return out


static func _parse_binding_success(pkt: PackedByteArray, txid: PackedByteArray) -> Dictionary:
	if pkt.size() < 20:
		return {}
	var msg_type: int = (int(pkt[0]) << 8) | int(pkt[1])
	if msg_type != BINDING_SUCCESS:
		return {}
	for i: int in range(12):
		if pkt[8 + i] != txid[i]:
			return {}
	var length: int = (int(pkt[2]) << 8) | int(pkt[3])
	var end: int = mini(pkt.size(), 20 + length)
	var i: int = 20
	while i + 4 <= end:
		var atype: int = (int(pkt[i]) << 8) | int(pkt[i + 1])
		var alen: int = (int(pkt[i + 2]) << 8) | int(pkt[i + 3])
		i += 4
		if i + alen > end:
			break
		if atype == ATTR_XOR_MAPPED or atype == ATTR_MAPPED:
			var mapped: Dictionary = _parse_addr_attr(pkt, i, alen, atype == ATTR_XOR_MAPPED, txid)
			if not mapped.is_empty():
				return mapped
		## 4-byte pad
		i += alen + ((4 - (alen % 4)) % 4)
	return {}


static func _parse_addr_attr(
	pkt: PackedByteArray, off: int, alen: int, xor: bool, _txid: PackedByteArray
) -> Dictionary:
	if alen < 8:
		return {}
	var family: int = int(pkt[off + 1])
	if family != 0x01:
		## IPv6 skipped for invite v2 reflexive slot (IPv4 field).
		return {}
	var port_raw: int = (int(pkt[off + 2]) << 8) | int(pkt[off + 3])
	var port: int = port_raw
	if xor:
		port = port_raw ^ ((MAGIC >> 16) & 0xFFFF)
	var b0: int = int(pkt[off + 4])
	var b1: int = int(pkt[off + 5])
	var b2: int = int(pkt[off + 6])
	var b3: int = int(pkt[off + 7])
	if xor:
		b0 ^= (MAGIC >> 24) & 0xFF
		b1 ^= (MAGIC >> 16) & 0xFF
		b2 ^= (MAGIC >> 8) & 0xFF
		b3 ^= MAGIC & 0xFF
	var ip: String = "%d.%d.%d.%d" % [b0, b1, b2, b3]
	if ip.begins_with("0.") or ip == "255.255.255.255":
		return {}
	return {"ip": ip, "port": port}
