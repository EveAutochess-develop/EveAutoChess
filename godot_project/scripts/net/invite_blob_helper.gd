extends RefCounted
class_name InviteBlobHelper
## SEMI_ASYNC §7.2 — unified room share: EAC + Base62 (short private / invite merged).

const PREFIX := "EAC"
const LEGACY_PREFIX := "EVEAC1:"
const B62 := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
const KIND_FULL := "full"
const KIND_PRIVATE_SHORT := "private_short"
const KIND_INVALID := "invalid"


static func encode(host_ip: String, port: int, room_hint: String, rules_hash: String, extra: Dictionary = {}) -> String:
	## Preferred: compact binary → Base62. Also keeps JSON fields for tooling.
	var is_private := bool(extra.get("private", room_hint.length() == 6))
	var bytes := _pack_v1(host_ip, port, room_hint, rules_hash, is_private, extra)
	return PREFIX + encode_base62(bytes)


static func decode(blob: String) -> Dictionary:
	var raw := blob.strip_edges()
	if raw.is_empty():
		return {}
	## Legacy Base64 JSON.
	if raw.begins_with(LEGACY_PREFIX) or raw.begins_with("ey"):
		return _decode_legacy(raw)
	var body := raw
	if body.to_upper().begins_with(PREFIX):
		body = body.substr(PREFIX.length())
	var bytes := decode_base62(body)
	if bytes.is_empty():
		## Last resort: old bare base64 JSON.
		return _decode_legacy(raw)
	return _unpack_v1(bytes)


static func classify(raw: String) -> String:
	var s := raw.strip_edges()
	if s.is_empty():
		return KIND_INVALID
	if s.to_upper().begins_with(PREFIX) or s.begins_with(LEGACY_PREFIX):
		return KIND_FULL
	var low := s.to_lower()
	if ShortcodeSignaling.is_valid_private(low):
		return KIND_PRIVATE_SHORT
	## Long base62 without prefix (paste stripped).
	if s.length() >= 12 and _is_base62(s):
		return KIND_FULL
	return KIND_INVALID


static func format_for_clipboard(blob: String) -> String:
	return blob.strip_edges()


static func join_address(decoded: Dictionary) -> Dictionary:
	var ip := str(decoded.get("reflexive_ip", decoded.get("ip", "")))
	var port := int(decoded.get("reflexive_port", decoded.get("port", 0)))
	return {
		"ip": ip,
		"port": port,
		"room": str(decoded.get("room", "")),
		"rules": str(decoded.get("rules", "")),
		"private": bool(decoded.get("private", false)),
	}


static func encode_base62(data: PackedByteArray) -> String:
	if data.is_empty():
		return "0"
	## Interpret as big-endian integer; emit Base62 digits.
	var digits: Array = []
	var n := _bytes_to_int_digits(data) ## array of base-256 limbs, big-endian
	if n.is_empty():
		return "0"
	while not _limbs_is_zero(n):
		var div: Dictionary = _limbs_div_small(n, 62)
		n = div["q"] as Array
		digits.append(int(div["r"]))
	var out := ""
	for i in range(digits.size() - 1, -1, -1):
		out += B62[int(digits[i])]
	return out if out != "" else "0"


static func decode_base62(text: String) -> PackedByteArray:
	var s := text.strip_edges()
	if s.is_empty() or not _is_base62(s):
		return PackedByteArray()
	var n: Array = [0]
	for i in range(s.length()):
		var ch := s.substr(i, 1)
		var v := B62.find(ch)
		if v < 0:
			return PackedByteArray()
		n = _limbs_mul_small(n, 62)
		n = _limbs_add_small(n, v)
	return _limbs_to_bytes(n)


static func _pack_v1(host_ip: String, port: int, room_hint: String, rules_hash: String, is_private: bool, extra: Dictionary) -> PackedByteArray:
	var flags := 0
	if is_private:
		flags |= 1
	var ip_parts := host_ip.split(".")
	var has_ip := ip_parts.size() == 4
	if has_ip:
		flags |= 2
	var ref_ip := str(extra.get("reflexive_ip", ""))
	var ref_port := int(extra.get("reflexive_port", 0))
	var ref_parts := ref_ip.split(".")
	var has_ref := ref_parts.size() == 4 and ref_port > 0
	if has_ref:
		flags |= 4
	var buf := PackedByteArray()
	buf.append(1) ## version
	buf.append(flags)
	buf.append((port >> 8) & 0xFF)
	buf.append(port & 0xFF)
	if has_ip:
		for i in range(4):
			buf.append(clampi(int(ip_parts[i]), 0, 255))
	if has_ref:
		for i in range(4):
			buf.append(clampi(int(ref_parts[i]), 0, 255))
		buf.append((ref_port >> 8) & 0xFF)
		buf.append(ref_port & 0xFF)
	if is_private:
		var room := room_hint.strip_edges().to_lower()
		while room.length() < 6:
			room += "0"
		room = room.substr(0, 6)
		for i in range(6):
			buf.append(room.unicode_at(i) & 0xFF)
	else:
		var code := clampi(int(room_hint), 1, 9999)
		buf.append((code >> 8) & 0xFF)
		buf.append(code & 0xFF)
	var rules := rules_hash.to_utf8_buffer()
	if rules.size() > 64:
		rules = rules.slice(0, 64)
	buf.append(rules.size())
	buf.append_array(rules)
	var sec := str(extra.get("security_mode", "nullsec"))
	buf.append(1 if sec == "lowsec" else 0)
	return buf


static func _unpack_v1(data: PackedByteArray) -> Dictionary:
	if data.size() < 5:
		return {}
	var v := int(data[0])
	if v != 1:
		return {}
	var flags := int(data[1])
	var is_private := (flags & 1) != 0
	var has_ip := (flags & 2) != 0
	var has_ref := (flags & 4) != 0
	var port := (int(data[2]) << 8) | int(data[3])
	var i := 4
	var ip := ""
	if has_ip:
		if data.size() < i + 4:
			return {}
		ip = "%d.%d.%d.%d" % [data[i], data[i + 1], data[i + 2], data[i + 3]]
		i += 4
	var ref_ip := ""
	var ref_port := 0
	if has_ref:
		if data.size() < i + 6:
			return {}
		ref_ip = "%d.%d.%d.%d" % [data[i], data[i + 1], data[i + 2], data[i + 3]]
		ref_port = (int(data[i + 4]) << 8) | int(data[i + 5])
		i += 6
	var room := ""
	if is_private:
		if data.size() < i + 6:
			return {}
		var chars := ""
		for k in range(6):
			chars += String.chr(int(data[i + k]))
		room = chars
		i += 6
	else:
		if data.size() < i + 2:
			return {}
		var code := (int(data[i]) << 8) | int(data[i + 1])
		room = "%04d" % clampi(code, 1, 9999)
		i += 2
	if data.size() <= i:
		return {}
	var rlen := int(data[i])
	i += 1
	if data.size() < i + rlen:
		return {}
	var rules := data.slice(i, i + rlen).get_string_from_utf8()
	i += rlen
	var security := "nullsec"
	if data.size() > i and int(data[i]) == 1:
		security = "lowsec"
	return {
		"v": 1,
		"ip": ip,
		"port": port,
		"room": room,
		"rules": rules,
		"private": is_private,
		"reflexive_ip": ref_ip,
		"reflexive_port": ref_port,
		"security_mode": security,
		"stun": NetConnectivity.public_stun_enabled(),
	}


static func _decode_legacy(raw: String) -> Dictionary:
	var s := raw.strip_edges()
	if s.begins_with(LEGACY_PREFIX):
		s = s.substr(LEGACY_PREFIX.length())
	var json_txt := Marshalls.base64_to_utf8(s)
	if json_txt == "" and raw.strip_edges().begins_with("{"):
		json_txt = raw.strip_edges()
	var parsed: Variant = JSON.parse_string(json_txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func _is_base62(s: String) -> bool:
	for i in range(s.length()):
		if B62.find(s.substr(i, 1)) < 0:
			return false
	return true


## --- big-integer helpers (base-256 limb arrays, big-endian) ---

static func _bytes_to_int_digits(data: PackedByteArray) -> Array:
	var n: Array = []
	for b in data:
		n.append(int(b))
	while n.size() > 1 and int(n[0]) == 0:
		n.remove_at(0)
	return n


static func _limbs_is_zero(n: Array) -> bool:
	for x in n:
		if int(x) != 0:
			return false
	return true


static func _limbs_div_small(n: Array, d: int) -> Dictionary:
	var q: Array = []
	var r := 0
	for x in n:
		var cur := r * 256 + int(x)
		var qi := int(cur / d)
		r = cur % d
		if not q.is_empty() or qi != 0:
			q.append(qi)
	if q.is_empty():
		q.append(0)
	return {"q": q, "r": r}


static func _limbs_mul_small(n: Array, m: int) -> Array:
	var carry := 0
	var out: Array = []
	for i in range(n.size() - 1, -1, -1):
		var cur := int(n[i]) * m + carry
		out.insert(0, cur & 0xFF)
		carry = cur >> 8
	while carry > 0:
		out.insert(0, carry & 0xFF)
		carry >>= 8
	return out


static func _limbs_add_small(n: Array, add: int) -> Array:
	var out := n.duplicate()
	var i := out.size() - 1
	var carry := add
	while carry > 0:
		if i < 0:
			out.insert(0, carry & 0xFF)
			carry >>= 8
			continue
		var cur := int(out[i]) + carry
		out[i] = cur & 0xFF
		carry = cur >> 8
		i -= 1
	return out


static func _limbs_to_bytes(n: Array) -> PackedByteArray:
	var out := PackedByteArray()
	if _limbs_is_zero(n):
		out.append(0)
		return out
	for x in n:
		out.append(int(x) & 0xFF)
	return out
