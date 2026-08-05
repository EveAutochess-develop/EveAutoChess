extends RefCounted
class_name OpeningPack
## SEMI_ASYNC §3.0b — ships.json + seeds.json → zip bytes + hash (no full table in logs).

static func build(ships_table: Dictionary, seeds_payload: Dictionary) -> Dictionary:
	var ships_json: String = JSON.stringify(ships_table)
	var seeds_json: String = JSON.stringify(seeds_payload)
	var ships_hash: String = _hash_str(ships_json)
	var pack_hash: String = _hash_str(ships_json + "\n" + seeds_json)
	## Prefer in-memory zip when available; fallback to concatenated framed payload.
	var bytes: PackedByteArray = _pack_framed(ships_json, seeds_json)
	return {
		"bytes": bytes,
		"ships_hash": ships_hash,
		"pack_hash": pack_hash,
		"byte_len": bytes.size(),
	}


static func unpack(bytes: PackedByteArray) -> Dictionary:
	var parts: Dictionary = _unpack_framed(bytes)
	if parts.is_empty():
		return {}
	var ships_s: String = str(parts.get("ships", ""))
	var seeds_s: String = str(parts.get("seeds", ""))
	var ships_v: Variant = JSON.parse_string(ships_s)
	var seeds_v: Variant = JSON.parse_string(seeds_s)
	if typeof(ships_v) != TYPE_DICTIONARY or typeof(seeds_v) != TYPE_DICTIONARY:
		return {}
	return {
		"ships": ships_v,
		"seeds": seeds_v,
		"ships_hash": _hash_str(ships_s),
		"pack_hash": _hash_str(ships_s + "\n" + seeds_s),
	}


static func _pack_framed(ships_json: String, seeds_json: String) -> PackedByteArray:
	var sb: PackedByteArray = ships_json.to_utf8_buffer()
	var eb: PackedByteArray = seeds_json.to_utf8_buffer()
	var out: PackedByteArray = PackedByteArray()
	out.append_array("EACP1".to_utf8_buffer())
	_append_u32(out, sb.size())
	out.append_array(sb)
	_append_u32(out, eb.size())
	out.append_array(eb)
	return out


static func _unpack_framed(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 13:
		return {}
	var magic: String = bytes.slice(0, 5).get_string_from_utf8()
	if magic != "EACP1":
		return {}
	var i: int = 5
	var slen: int = _read_u32(bytes, i)
	i += 4
	if i + slen + 4 > bytes.size():
		return {}
	var ships: String = bytes.slice(i, i + slen).get_string_from_utf8()
	i += slen
	var elen: int = _read_u32(bytes, i)
	i += 4
	if i + elen > bytes.size():
		return {}
	var seeds: String = bytes.slice(i, i + elen).get_string_from_utf8()
	return {"ships": ships, "seeds": seeds}


static func _append_u32(buf: PackedByteArray, v: int) -> void:
	buf.append(v & 0xFF)
	buf.append((v >> 8) & 0xFF)
	buf.append((v >> 16) & 0xFF)
	buf.append((v >> 24) & 0xFF)


static func _read_u32(buf: PackedByteArray, i: int) -> int:
	return int(buf[i]) | (int(buf[i + 1]) << 8) | (int(buf[i + 2]) << 16) | (int(buf[i + 3]) << 24)


static func _hash_str(s: String) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(s.to_utf8_buffer())
	return ctx.finish().hex_encode()
