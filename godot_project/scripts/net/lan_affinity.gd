extends RefCounted
class_name LanAffinity
## Same-LAN heuristics for join UX + try order (SEMI_ASYNC §7.5).
## Never treat "beacon seen + ENet timeout" as cross-LAN when /24 overlaps.

## Boost so ZeroTier managed IPs beat home Wi‑Fi 192.168 in invite/beacon.
const ZEROTIER_SCORE_BONUS: int = 150


static func local_ipv4s() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for a: String in IP.get_local_addresses():
		var s: String = str(a).strip_edges()
		if _score_ipv4(s) < 0:
			continue
		if not out.has(s):
			out.append(s)
	return out


static func scored_local_ipv4s() -> Array:
	## [{ip, score}] descending score. ZeroTier iface IPs get +ZEROTIER_SCORE_BONUS.
	var zt_ips: Dictionary = _zerotier_ipv4_set()
	var rows: Array = []
	for a: String in local_ipv4s():
		var score: int = _score_ipv4(a)
		if zt_ips.has(a):
			score += ZEROTIER_SCORE_BONUS
		rows.append({"ip": a, "score": score})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return TypedVariant.as_int(x.get("score", 0), 0) > TypedVariant.as_int(y.get("score", 0), 0)
	)
	return rows


static func best_local_ipv4() -> String:
	var rows: Array = scored_local_ipv4s()
	if rows.is_empty():
		return "127.0.0.1"
	return str(TypedVariant.as_dict(rows[0]).get("ip", "127.0.0.1"))


static func prefix24(ip: String) -> String:
	var parts: PackedStringArray = ip.strip_edges().split(".")
	if parts.size() != 4:
		return ""
	return "%s.%s.%s" % [parts[0], parts[1], parts[2]]


static func affinity(candidate_ip: String, locals: PackedStringArray = PackedStringArray()) -> String:
	## same_24 | same_private | public | loopback | empty | unknown
	var ip: String = candidate_ip.strip_edges()
	if ip == "" or ip == "0.0.0.0":
		return "empty"
	if ip.begins_with("127."):
		return "loopback"
	if ip.find(":") >= 0:
		return "ipv6"
	var loc: PackedStringArray = locals if not locals.is_empty() else local_ipv4s()
	var pref: String = prefix24(ip)
	if pref != "":
		for a: String in loc:
			if prefix24(a) == pref:
				return "same_24"
	if _is_rfc1918(ip):
		for a: String in loc:
			if _is_rfc1918(a):
				## Both private but different /24 — still likely home/office, not CGNAT WAN.
				return "same_private"
		return "same_private"
	return "public"


static func is_same_lan(candidate_ip: String, locals: PackedStringArray = PackedStringArray()) -> bool:
	var a: String = affinity(candidate_ip, locals)
	return a == "same_24" or a == "same_private"


static func dump_locals() -> Dictionary:
	var addrs: Array = []
	var zt_ips: Dictionary = _zerotier_ipv4_set()
	for row_v: Variant in scored_local_ipv4s():
		var row: Dictionary = TypedVariant.as_dict(row_v)
		var ip: String = str(row.get("ip", ""))
		addrs.append({
			"ip": ip,
			"score": TypedVariant.as_int(row.get("score", 0), 0),
			"p24": prefix24(ip),
			"zerotier": zt_ips.has(ip),
		})
	return {
		"platform": OS.get_name(),
		"emulator": LanBeacon.is_android_emulator(),
		"addrs": addrs,
	}


static func _zerotier_ipv4_set() -> Dictionary:
	## Godot 4: IP.get_local_interfaces() → {name, friendly, addresses, ...}
	var out: Dictionary = {}
	var ifaces: Variant = IP.get_local_interfaces()
	if typeof(ifaces) != TYPE_ARRAY:
		return out
	for iface_v: Variant in ifaces:
		var iface: Dictionary = TypedVariant.as_dict(iface_v)
		var iname: String = str(iface.get("name", "")).to_lower()
		var friendly: String = str(iface.get("friendly", "")).to_lower()
		if iname.find("zerotier") < 0 and friendly.find("zerotier") < 0:
			continue
		var addrs_v: Variant = iface.get("addresses", [])
		if typeof(addrs_v) == TYPE_PACKED_STRING_ARRAY:
			for a: String in addrs_v:
				var s: String = str(a).strip_edges()
				if _score_ipv4(s) >= 0:
					out[s] = true
		elif typeof(addrs_v) == TYPE_ARRAY:
			for a_v: Variant in addrs_v:
				var s2: String = str(a_v).strip_edges()
				if _score_ipv4(s2) >= 0:
					out[s2] = true
	return out


static func _is_rfc1918(ip: String) -> bool:
	var parts: PackedStringArray = ip.split(".")
	if parts.size() != 4:
		return false
	var a: int = int(parts[0])
	var b: int = int(parts[1])
	if a == 10:
		return true
	if a == 192 and b == 168:
		return true
	if a == 172 and b >= 16 and b <= 31:
		return true
	return false


static func score_ipv4_base(ip: String) -> int:
	return _score_ipv4(ip)


static func _score_ipv4(ip: String) -> int:
	## Keep in sync with NullsecNetSession._score_local_ipv4 base (pre-ZeroTier bonus).
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
	if a == 10 and b == 0 and c == 2:
		if d == 15:
			return -1
		if d >= 16 and d <= 31:
			return 95
	if a == 10 and b == 1 and c == 2 and d >= 1 and d <= 32:
		return 90
	if a == 192 and b == 168:
		return 100
	if a == 10:
		return 50
	if a == 172 and b >= 16 and b <= 31:
		return 10
	return 0
