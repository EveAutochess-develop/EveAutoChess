extends RefCounted
class_name InviteBlobHelper
## SEMI_ASYNC §7.2 — room share: EAC + Base62 (v2 dual-stack + optional password).
@warning_ignore_start("untyped_declaration", "inferred_declaration", "unsafe_method_access", "unsafe_call_argument", "inference_on_variant", "unsafe_cast")

const PREFIX := "EAC"
const LEGACY_PREFIX := "EVEAC1:"
const B62 := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
const KIND_FULL := "full"
const KIND_INVALID := "invalid"
## Deprecated classify result — treated as invalid for primary join path.
const KIND_PRIVATE_SHORT := "private_short"


static func encode(host_ip: String, port: int, room_hint: String, rules_hash: String, extra: Dictionary = {}) -> String:
	var bytes := _pack_v2(host_ip, port, room_hint, rules_hash, extra)
	return PREFIX + encode_base62(bytes)


static func decode(blob: String) -> Dictionary:
	var raw := sanitize_paste(blob)
	if raw.is_empty():
		return {}
	## Legacy Base64 JSON.
	if raw.begins_with(LEGACY_PREFIX) or raw.begins_with("ey"):
		return _normalize_decoded(_decode_legacy(raw))
	var body := raw
	if body.to_upper().begins_with(PREFIX):
		body = body.substr(PREFIX.length())
	var bytes := decode_base62(body)
	if bytes.is_empty():
		return _normalize_decoded(_decode_legacy(raw))
	if bytes.size() < 2:
		return {}
	var ver := int(bytes[0])
	if ver == 2:
		return _unpack_v2(bytes)
	if ver == 1:
		return _normalize_decoded(_unpack_v1(bytes))
	return {}


## Strip BOM / zero-width / whitespace junk from Android clipboard pastes.
static func sanitize_paste(raw: String) -> String:
	var s := str(raw)
	if s.is_empty():
		return ""
	var out := ""
	for i in range(s.length()):
		var code := s.unicode_at(i)
		if code <= 32:
			continue
		if code == 0xFEFF or code == 0x200B or code == 0x200C or code == 0x200D or code == 0x2060 or code == 0x00A0:
			continue
		out += String.chr(code)
	return out


static func classify(raw: String) -> String:
	var s := sanitize_paste(raw)
	if s.is_empty():
		return KIND_INVALID
	if s.to_upper().begins_with(PREFIX) or s.begins_with(LEGACY_PREFIX):
		return KIND_FULL
	## Long base62 without prefix (paste stripped).
	if s.length() >= 12 and _is_base62(s):
		return KIND_FULL
	return KIND_INVALID


static func format_for_clipboard(blob: String) -> String:
	return blob.strip_edges()


static func join_address(decoded: Dictionary) -> Dictionary:
	## Primary endpoint (prefer IPv4 for single-slot callers); password + room included.
	var endpoints := join_endpoints(decoded)
	var ip := ""
	var port := 0
	if not endpoints.is_empty():
		ip = str(endpoints[0].get("ip", ""))
		port = int(endpoints[0].get("port", 0))
	## Prefer IPv4 in join_address for backward callers.
	for e in endpoints:
		var cand := str(e.get("ip", ""))
		if cand.find(":") < 0 and cand != "":
			ip = cand
			port = int(e.get("port", 0))
			break
	var password := str(decoded.get("password", ""))
	var room := str(decoded.get("room", ""))
	return {
		"ip": ip,
		"port": port,
		"room": room,
		"rules": str(decoded.get("rules", "")),
		"password": password,
		"ipv6": str(decoded.get("ipv6", "")),
		"has_password": not password.is_empty(),
	}


## Ordered try list per SEMI_ASYNC §7.2 (caller prepends LAN if any).
## Home Wi‑Fi: IPv4 before global IPv6 (v6 often blackholes on same SSID).
static func join_endpoints(decoded: Dictionary) -> Array:
	var out: Array = []
	var port := int(decoded.get("port", 0))
	var ipv6 := str(decoded.get("ipv6", "")).strip_edges()
	var ipv4 := str(decoded.get("ip", "")).strip_edges()
	var ref_ip := str(decoded.get("reflexive_ip", "")).strip_edges()
	var ref_port := int(decoded.get("reflexive_port", 0))
	if ipv4 != "" and not ipv4.begins_with("127.") and port > 0:
		out.append({"ip": ipv4, "port": port, "via": "blob_v4"})
	if ipv6 != "" and port > 0:
		out.append({"ip": ipv6, "port": port, "via": "blob_v6"})
	if ref_ip != "" and ref_port > 0:
		out.append({"ip": ref_ip, "port": ref_port, "via": "blob_ref"})
	return out


static func encode_base62(data: PackedByteArray) -> String:
	if data.is_empty():
		return "0"
	var digits: Array = []
	var n := _bytes_to_int_digits(data)
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


## v2: flags bit1=ipv4 bit2=ref bit3=ipv6 bit4=password; always room_code u16.
static func _pack_v2(host_ip: String, port: int, room_hint: String, rules_hash: String, extra: Dictionary) -> PackedByteArray:
	var flags := 0
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
	var ipv6 := str(extra.get("ipv6", "")).strip_edges()
	var ipv6_bytes := _pack_ipv6(ipv6)
	var has_v6 := ipv6_bytes.size() == 16
	if has_v6:
		flags |= 8
	var password := str(extra.get("password", "")).strip_edges()
	if password.length() > 32:
		password = password.substr(0, 32)
	var pw_bytes := password.to_utf8_buffer()
	if pw_bytes.size() > 0:
		flags |= 16
	var code := clampi(int(room_hint), 1, 9999)
	if code < 1:
		code = 1
	var buf := PackedByteArray()
	buf.append(2) ## version
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
	if has_v6:
		buf.append_array(ipv6_bytes)
	buf.append((code >> 8) & 0xFF)
	buf.append(code & 0xFF)
	if pw_bytes.size() > 0:
		buf.append(pw_bytes.size() & 0xFF)
		buf.append_array(pw_bytes)
	var rules := rules_hash.to_utf8_buffer()
	if rules.size() > 64:
		rules = rules.slice(0, 64)
	buf.append(rules.size())
	buf.append_array(rules)
	var sec := str(extra.get("security_mode", "nullsec"))
	buf.append(1 if sec == "lowsec" else 0)
	return buf


static func _unpack_v2(data: PackedByteArray) -> Dictionary:
	if data.size() < 5:
		return {}
	if int(data[0]) != 2:
		return {}
	var flags := int(data[1])
	var has_ip := (flags & 2) != 0
	var has_ref := (flags & 4) != 0
	var has_v6 := (flags & 8) != 0
	var has_pw := (flags & 16) != 0
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
	var ipv6 := ""
	if has_v6:
		if data.size() < i + 16:
			return {}
		ipv6 = _unpack_ipv6(data.slice(i, i + 16))
		i += 16
	if data.size() < i + 2:
		return {}
	var code := (int(data[i]) << 8) | int(data[i + 1])
	var room := "%04d" % clampi(code, 1, 9999)
	i += 2
	var password := ""
	if has_pw:
		if data.size() <= i:
			return {}
		var plen := int(data[i])
		i += 1
		if data.size() < i + plen:
			return {}
		password = data.slice(i, i + plen).get_string_from_utf8()
		i += plen
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
		"v": 2,
		"ip": ip,
		"ipv6": ipv6,
		"port": port,
		"room": room,
		"room_code": clampi(code, 1, 9999),
		"password": password,
		"rules": rules,
		"reflexive_ip": ref_ip,
		"reflexive_port": ref_port,
		"security_mode": security,
		"stun": NetConnectivity.public_stun_enabled(),
	}


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
	buf.append(1)
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
	var password := ""
	if is_private:
		if data.size() < i + 6:
			return {}
		var chars := ""
		for k in range(6):
			chars += String.chr(int(data[i + k]))
		## Legacy private shortcode → treat as password; room code unknown (1).
		password = chars
		room = "0001"
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
		"password": password,
		"rules": rules,
		"reflexive_ip": ref_ip,
		"reflexive_port": ref_port,
		"security_mode": security,
		"stun": NetConnectivity.public_stun_enabled(),
	}


static func _normalize_decoded(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	var out := d.duplicate(true)
	if not out.has("password"):
		out["password"] = ""
	if bool(out.get("private", false)) and str(out.get("password", "")) == "":
		## Old blobs: private shortcode lived in room field.
		var room := str(out.get("room", ""))
		if room.length() == 6:
			out["password"] = room
	out.erase("private")
	if not out.has("ipv6"):
		out["ipv6"] = ""
	if not out.has("room_code"):
		var rc := int(out.get("room", 0))
		if rc >= 1 and rc <= 9999:
			out["room_code"] = rc
	return out


static func _pack_ipv6(addr: String) -> PackedByteArray:
	var s := addr.strip_edges()
	if s.is_empty() or s.find(":") < 0:
		return PackedByteArray()
	## Expand :: then parse 8 hextets.
	if s.begins_with("["):
		s = s.trim_prefix("[").trim_suffix("]")
	var parts := s.split(":")
	## Handle compression
	var left: PackedStringArray = []
	var right: PackedStringArray = []
	var seen_empty := false
	for p in parts:
		if p == "":
			if seen_empty:
				continue
			seen_empty = true
			continue
		if not seen_empty:
			left.append(p)
		else:
			right.append(p)
	var hextets: Array = []
	for p in left:
		hextets.append(p)
	if seen_empty:
		var miss := 8 - left.size() - right.size()
		for _i in range(maxi(miss, 0)):
			hextets.append("0")
		for p in right:
			hextets.append(p)
	if hextets.size() != 8:
		return PackedByteArray()
	var out := PackedByteArray()
	for h in hextets:
		var v := _parse_hextet(str(h))
		if v < 0:
			return PackedByteArray()
		out.append((v >> 8) & 0xFF)
		out.append(v & 0xFF)
	return out


static func _parse_hextet(h: String) -> int:
	if h.is_empty() or h.length() > 4:
		return -1
	var v := 0
	for i in range(h.length()):
		var c := h.unicode_at(i)
		var d := -1
		if c >= 48 and c <= 57:
			d = c - 48
		elif c >= 97 and c <= 102:
			d = c - 97 + 10
		elif c >= 65 and c <= 70:
			d = c - 65 + 10
		else:
			return -1
		v = (v << 4) | d
	return v


static func _unpack_ipv6(data: PackedByteArray) -> String:
	if data.size() != 16:
		return ""
	var parts: PackedStringArray = []
	for i in range(8):
		var v := (int(data[i * 2]) << 8) | int(data[i * 2 + 1])
		parts.append("%x" % v)
	return ":".join(parts)


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
