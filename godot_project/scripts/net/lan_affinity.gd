extends RefCounted
class_name LanAffinity
## Same-LAN heuristics for join UX + try order (SEMI_ASYNC §7.5).
## Never treat "beacon seen + ENet timeout" as cross-LAN when /24 overlaps.


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
	## [{ip, score}] descending score.
	var rows: Array = []
	for a: String in local_ipv4s():
		rows.append({"ip": a, "score": _score_ipv4(a)})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return TypedVariant.as_int(x.get("score", 0), 0) > TypedVariant.as_int(y.get("score", 0), 0)
	)
	return rows


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
	for row_v: Variant in scored_local_ipv4s():
		var row: Dictionary = TypedVariant.as_dict(row_v)
		addrs.append({
			"ip": str(row.get("ip", "")),
			"score": TypedVariant.as_int(row.get("score", 0), 0),
			"p24": prefix24(str(row.get("ip", ""))),
		})
	return {
		"platform": OS.get_name(),
		"emulator": LanBeacon.is_android_emulator(),
		"addrs": addrs,
	}


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


static func _score_ipv4(ip: String) -> int:
	## Keep in sync with NullsecNetSession._score_local_ipv4.
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
