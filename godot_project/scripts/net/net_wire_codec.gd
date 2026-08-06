extends RefCounted
class_name NetWireCodec
## SEMI_ASYNC §3.3.1 — shared binary wire helpers for the full / light authority packets.
## Frame: magic 'E' | ver | comp | raw_len(u32) | body. Body is zstd only above a threshold.

const MAGIC: int = 0x45
const VERSION: int = 2
const COMP_NONE: int = 0
const COMP_ZSTD: int = 1
const HEADER_LEN: int = 7
## §7.6 packet hard cap — a malformed raw_len must never drive a huge allocation.
const MAX_RAW_LEN: int = 1 << 20

const KIND_FULL: int = 0
const KIND_LIGHT: int = 1
const KIND_FLEET: int = 2
## 0xFFFF marks "no target" in every index slot.
const NO_IDX: int = 0xFFFF
## World units are quantized to 1 cm; i16 covers +-327 wu.
const POS_SCALE: float = 100.0
## HP is quantized to 0.1 into u32 (absolute, never a ratio of a locally derived max).
const HP_SCALE: float = 10.0
const U16_MAX: int = 0xFFFF
const U32_MAX: int = 0xFFFFFFFF


static func wrap(payload: PackedByteArray, compress_min: int) -> PackedByteArray:
	var body: PackedByteArray = payload
	var comp: int = COMP_NONE
	if compress_min > 0 and payload.size() >= compress_min:
		var z: PackedByteArray = payload.compress(FileAccess.COMPRESSION_ZSTD)
		if z.size() > 0 and z.size() < payload.size():
			body = z
			comp = COMP_ZSTD
	var out: PackedByteArray = PackedByteArray()
	out.append(MAGIC)
	out.append(VERSION)
	out.append(comp)
	append_u32(out, payload.size())
	out.append_array(body)
	return out


static func unwrap(bytes: PackedByteArray) -> PackedByteArray:
	var empty: PackedByteArray = PackedByteArray()
	if bytes.size() < HEADER_LEN:
		return empty
	if bytes[0] != MAGIC or bytes[1] != VERSION:
		return empty
	var comp: int = bytes[2]
	var raw_len: int = read_u32(bytes, 3)
	if raw_len <= 0 or raw_len > MAX_RAW_LEN:
		return empty
	var body: PackedByteArray = bytes.slice(HEADER_LEN, bytes.size())
	if comp == COMP_NONE:
		return body if body.size() == raw_len else empty
	if comp != COMP_ZSTD:
		return empty
	var out: PackedByteArray = body.decompress(raw_len, FileAccess.COMPRESSION_ZSTD)
	return out if out.size() == raw_len else empty


static func quant_pos(v: float) -> int:
	return clampi(roundi(v * POS_SCALE), -32768, 32767)


static func dequant_pos(q: int) -> float:
	return float(q) / POS_SCALE


static func quant_hp(v: float) -> int:
	return clampi(roundi(maxf(0.0, v) * HP_SCALE), 0, U32_MAX)


static func dequant_hp(q: int) -> float:
	return float(q) / HP_SCALE


static func append_u8(buf: PackedByteArray, v: int) -> void:
	buf.append(v & 0xFF)


static func append_u16(buf: PackedByteArray, v: int) -> void:
	var n: int = buf.size()
	buf.resize(n + 2)
	buf.encode_u16(n, v & U16_MAX)


static func append_i16(buf: PackedByteArray, v: int) -> void:
	var n: int = buf.size()
	buf.resize(n + 2)
	buf.encode_s16(n, clampi(v, -32768, 32767))


static func append_u32(buf: PackedByteArray, v: int) -> void:
	var n: int = buf.size()
	buf.resize(n + 4)
	buf.encode_u32(n, v & U32_MAX)


static func append_i32(buf: PackedByteArray, v: int) -> void:
	var n: int = buf.size()
	buf.resize(n + 4)
	buf.encode_s32(n, clampi(v, -2147483648, 2147483647))


static func append_f32(buf: PackedByteArray, v: float) -> void:
	var n: int = buf.size()
	buf.resize(n + 4)
	buf.encode_float(n, v)


static func append_str(buf: PackedByteArray, s: String) -> void:
	var sb: PackedByteArray = s.to_utf8_buffer()
	if sb.size() > 255:
		sb = sb.slice(0, 255)
	buf.append(sb.size())
	buf.append_array(sb)


static func read_u8(buf: PackedByteArray, i: int) -> int:
	return int(buf[i])


static func read_u16(buf: PackedByteArray, i: int) -> int:
	return buf.decode_u16(i)


static func read_i16(buf: PackedByteArray, i: int) -> int:
	return buf.decode_s16(i)


static func read_u32(buf: PackedByteArray, i: int) -> int:
	return buf.decode_u32(i)


static func read_i32(buf: PackedByteArray, i: int) -> int:
	return buf.decode_s32(i)


static func read_f32(buf: PackedByteArray, i: int) -> float:
	return buf.decode_float(i)


static func append_i8(buf: PackedByteArray, v: int) -> void:
	buf.append(clampi(v, -128, 127) & 0xFF)


static func read_i8(buf: PackedByteArray, i: int) -> int:
	var v: int = int(buf[i])
	if v >= 128:
		return v - 256
	return v


## SEMI_ASYNC §3.0d — Prepare fleet mutual sync (manned only).
## side bits: 0=PLAYER(0), 1=AI(1), 2=unspecified — avoid ShipUnit import here.
static func encode_fleet(seat: int, ships: Array, compress_min: int) -> PackedByteArray:
	var buf: PackedByteArray = PackedByteArray()
	append_u8(buf, KIND_FLEET)
	append_u8(buf, clampi(seat, 0, 255))
	append_u16(buf, ships.size())
	for entry_v: Variant in ships:
		var e: Dictionary = TypedVariant.as_dict(entry_v)
		append_u16(buf, clampi(TypedVariant.as_int(e.get("ship_id", 0), 0), 0, 65535))
		append_u8(buf, clampi(TypedVariant.as_int(e.get("star", 1), 1), 1, 255))
		var flags: int = 0
		if str(e.get("slot_type", "field")) == "hangar":
			flags |= 1
		var side: int = TypedVariant.as_int(e.get("side", -1), -1)
		var side_bits: int = 2
		if side == 0:
			side_bits = 0
		elif side == 1:
			side_bits = 1
		flags |= (side_bits & 0x3) << 1
		append_u8(buf, flags)
		append_i8(buf, TypedVariant.as_int(e.get("x", 0), 0))
		append_i8(buf, TypedVariant.as_int(e.get("z", 0), 0))
		append_str(buf, str(e.get("net_uid", "")))
		var fit: Array = TypedVariant.as_array(e.get("fit", []))
		append_u8(buf, clampi(fit.size(), 0, 255))
		var fi: int = 0
		for fid_v: Variant in fit:
			if fi >= 255:
				break
			append_str(buf, str(fid_v))
			fi += 1
	return NetWireCodec.wrap(buf, compress_min)


static func decode_fleet(data: PackedByteArray) -> Dictionary:
	var empty: Dictionary = {"seat": -1, "ships": []}
	var p: PackedByteArray = NetWireCodec.unwrap(data)
	if p.size() < 4 or p[0] != KIND_FLEET:
		return empty
	var seat: int = read_u8(p, 1)
	var n: int = read_u16(p, 2)
	var i: int = 4
	var ships: Array = []
	for _k: int in range(n):
		if i + 6 > p.size():
			return empty
		var sid: int = read_u16(p, i)
		var star: int = read_u8(p, i + 2)
		var flags: int = read_u8(p, i + 3)
		var x: int = read_i8(p, i + 4)
		var z: int = read_i8(p, i + 5)
		i += 6
		if i >= p.size():
			return empty
		var ulen: int = read_u8(p, i)
		i += 1
		if i + ulen > p.size():
			return empty
		var uid: String = p.slice(i, i + ulen).get_string_from_utf8()
		i += ulen
		if i >= p.size():
			return empty
		var fit_n: int = read_u8(p, i)
		i += 1
		var fit: Array = []
		for _f: int in range(fit_n):
			if i >= p.size():
				return empty
			var flen: int = read_u8(p, i)
			i += 1
			if i + flen > p.size():
				return empty
			fit.append(p.slice(i, i + flen).get_string_from_utf8())
			i += flen
		var side_bits: int = (flags >> 1) & 0x3
		var side: int = -1
		if side_bits == 0:
			side = 0
		elif side_bits == 1:
			side = 1
		ships.append({
			"ship_id": sid,
			"star": star,
			"slot_type": "hangar" if (flags & 1) != 0 else "field",
			"x": x,
			"z": z,
			"side": side,
			"net_uid": uid,
			"fit": fit,
		})
	return {"seat": seat, "ships": ships}
