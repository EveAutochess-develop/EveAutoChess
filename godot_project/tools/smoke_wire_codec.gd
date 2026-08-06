extends SceneTree
## SEMI_ASYNC §3.3.1 — round-trip the binary frame and the light packet layout.
## Run: godot --headless --path godot_project --script res://tools/smoke_wire_codec.gd

func _init() -> void:
	var fails: int = 0
	fails += _check_frame_raw()
	fails += _check_frame_zstd()
	fails += _check_frame_reject()
	fails += _check_light_layout()
	fails += _check_fleet_roundtrip()
	fails += _check_full_unmanned_birth()
	if fails == 0:
		print("[eveac_wire] OK")
	else:
		print("[eveac_wire] FAIL count=%d" % fails)
	quit(1 if fails > 0 else 0)


func _fail(msg: String) -> int:
	print("[eveac_wire] FAIL %s" % msg)
	return 1


func _check_frame_raw() -> int:
	var payload: PackedByteArray = PackedByteArray()
	NetWireCodec.append_u16(payload, 4242)
	NetWireCodec.append_i16(payload, -1234)
	var framed: PackedByteArray = NetWireCodec.wrap(payload, 512)
	if framed.size() != payload.size() + NetWireCodec.HEADER_LEN:
		return _fail("raw frame size=%d" % framed.size())
	if framed[2] != NetWireCodec.COMP_NONE:
		return _fail("raw frame compressed")
	var back: PackedByteArray = NetWireCodec.unwrap(framed)
	if back != payload:
		return _fail("raw round-trip")
	if NetWireCodec.read_u16(back, 0) != 4242 or NetWireCodec.read_i16(back, 2) != -1234:
		return _fail("raw fields")
	return 0


func _check_frame_zstd() -> int:
	var payload: PackedByteArray = PackedByteArray()
	for i: int in range(4000):
		NetWireCodec.append_u16(payload, i % 7)
	var framed: PackedByteArray = NetWireCodec.wrap(payload, 512)
	if framed[2] != NetWireCodec.COMP_ZSTD:
		return _fail("zstd not applied")
	if framed.size() >= payload.size():
		return _fail("zstd grew: %d -> %d" % [payload.size(), framed.size()])
	if NetWireCodec.unwrap(framed) != payload:
		return _fail("zstd round-trip")
	return 0


func _check_frame_reject() -> int:
	if not NetWireCodec.unwrap(PackedByteArray([1, 2, 3])).is_empty():
		return _fail("short frame accepted")
	var bad: PackedByteArray = NetWireCodec.wrap(PackedByteArray([9, 9]), 0)
	bad[0] = 0x00
	if not NetWireCodec.unwrap(bad).is_empty():
		return _fail("bad magic accepted")
	var trunc: PackedByteArray = NetWireCodec.wrap(PackedByteArray([9, 9, 9, 9]), 0)
	trunc.resize(trunc.size() - 1)
	if not NetWireCodec.unwrap(trunc).is_empty():
		return _fail("truncated body accepted")
	return 0


## Mirrors enrich_and_broadcast_light: header 11B + 6B per move + 6B per lock + 4B per event.
func _check_light_layout() -> int:
	var buf: PackedByteArray = PackedByteArray()
	NetWireCodec.append_u8(buf, NetWireCodec.KIND_LIGHT)
	NetWireCodec.append_u16(buf, 3)
	NetWireCodec.append_u32(buf, 900)
	NetWireCodec.append_u8(buf, 1)
	NetWireCodec.append_u8(buf, 2)
	NetWireCodec.append_u16(buf, 1)
	NetWireCodec.append_u16(buf, 5)
	NetWireCodec.append_i16(buf, NetWireCodec.quant_pos(-12.34))
	NetWireCodec.append_i16(buf, NetWireCodec.quant_pos(7.5))
	NetWireCodec.append_u16(buf, 1)
	NetWireCodec.append_u16(buf, 5)
	NetWireCodec.append_u16(buf, 9)
	NetWireCodec.append_u16(buf, NetWireCodec.NO_IDX)
	NetWireCodec.append_u16(buf, 1)
	NetWireCodec.append_u16(buf, 5)
	NetWireCodec.append_u16(buf, 9)
	if buf.size() != 11 + 6 + 2 + 6 + 2 + 4:
		return _fail("light size=%d" % buf.size())
	var p: PackedByteArray = NetWireCodec.unwrap(NetWireCodec.wrap(buf, 512))
	if p[0] != NetWireCodec.KIND_LIGHT or NetWireCodec.read_u16(p, 1) != 3:
		return _fail("light header")
	if NetWireCodec.read_u32(p, 3) != 900:
		return _fail("light tick")
	if NetWireCodec.read_u16(p, 11) != 5:
		return _fail("light move idx")
	if absf(NetWireCodec.dequant_pos(NetWireCodec.read_i16(p, 13)) + 12.34) > 0.005:
		return _fail("light move x")
	if NetWireCodec.read_u16(p, 23) != NetWireCodec.NO_IDX:
		return _fail("light fn idx")
	return 0


func _check_fleet_roundtrip() -> int:
	var ships: Array = [{
		"ship_id": 582,
		"star": 2,
		"slot_type": "field",
		"x": 3,
		"z": -1,
		"side": 0,
		"net_uid": "0|582|field|3|-1|0",
		"fit": ["fn_armor_rep", "fn_ab"],
	}, {
		"ship_id": 583,
		"star": 1,
		"slot_type": "hangar",
		"x": 0,
		"z": 0,
		"side": -1,
		"net_uid": "0|583|hangar|0|0|1",
		"fit": [],
	}]
	var framed: PackedByteArray = NetWireCodec.encode_fleet(2, ships, 512)
	var decoded: Dictionary = NetWireCodec.decode_fleet(framed)
	if TypedVariant.as_int(decoded.get("seat", -1), -1) != 2:
		return _fail("fleet seat")
	var back: Array = TypedVariant.as_array(decoded.get("ships", []))
	if back.size() != 2:
		return _fail("fleet count=%d" % back.size())
	var a: Dictionary = TypedVariant.as_dict(back[0])
	if TypedVariant.as_int(a.get("ship_id", 0), 0) != 582:
		return _fail("fleet ship_id")
	if str(a.get("slot_type", "")) != "field":
		return _fail("fleet slot")
	if TypedVariant.as_int(a.get("side", -2), -2) != 0:
		return _fail("fleet side")
	var fit: Array = TypedVariant.as_array(a.get("fit", []))
	if fit.size() != 2 or str(fit[0]) != "fn_armor_rep":
		return _fail("fleet fit")
	var b: Dictionary = TypedVariant.as_dict(back[1])
	if str(b.get("slot_type", "")) != "hangar":
		return _fail("fleet hangar")
	return 0


## Mirrors _encode_full unmanned birth: 31B head + 7B birth when flags&4.
func _check_full_unmanned_birth() -> int:
	var buf: PackedByteArray = PackedByteArray()
	NetWireCodec.append_u8(buf, NetWireCodec.KIND_FULL)
	NetWireCodec.append_u16(buf, 1)
	NetWireCodec.append_u32(buf, 10)
	NetWireCodec.append_u16(buf, 0)
	NetWireCodec.append_u8(buf, 0)
	NetWireCodec.append_u8(buf, 0)
	NetWireCodec.append_u32(buf, 0)
	NetWireCodec.append_u16(buf, 1)
	NetWireCodec.append_str(buf, "u|1001|7")
	NetWireCodec.append_u16(buf, 1)
	NetWireCodec.append_u16(buf, 0)
	NetWireCodec.append_i16(buf, NetWireCodec.quant_pos(1.0))
	NetWireCodec.append_i16(buf, NetWireCodec.quant_pos(0.2))
	NetWireCodec.append_i16(buf, NetWireCodec.quant_pos(-2.0))
	NetWireCodec.append_u32(buf, NetWireCodec.quant_hp(10.0))
	NetWireCodec.append_u32(buf, NetWireCodec.quant_hp(20.0))
	NetWireCodec.append_u32(buf, NetWireCodec.quant_hp(30.0))
	NetWireCodec.append_u8(buf, 4) ## unmanned
	NetWireCodec.append_u16(buf, NetWireCodec.NO_IDX)
	NetWireCodec.append_u16(buf, NetWireCodec.NO_IDX)
	NetWireCodec.append_u16(buf, NetWireCodec.NO_IDX)
	NetWireCodec.append_u16(buf, 0)
	NetWireCodec.append_u16(buf, 0)
	NetWireCodec.append_u16(buf, 1001)
	NetWireCodec.append_u8(buf, 1)
	NetWireCodec.append_u8(buf, 0) ## TEAM_PLAYER
	NetWireCodec.append_u16(buf, 0)
	NetWireCodec.append_u8(buf, 0)
	NetWireCodec.append_u16(buf, 0) ## events
	var p: PackedByteArray = NetWireCodec.unwrap(NetWireCodec.wrap(buf, 0))
	if p[0] != NetWireCodec.KIND_FULL:
		return _fail("full kind")
	var i: int = 1 + 2 + 4 + 2 + 1 + 1 + 4
	var n_roster: int = NetWireCodec.read_u16(p, i)
	i += 2
	if n_roster != 1:
		return _fail("full roster n")
	var slen: int = NetWireCodec.read_u8(p, i)
	i += 1 + slen
	var n_units: int = NetWireCodec.read_u16(p, i)
	i += 2
	if n_units != 1:
		return _fail("full units n")
	var flags: int = NetWireCodec.read_u8(p, i + 20)
	if (flags & 4) == 0:
		return _fail("full unmanned flag")
	i += 31
	if NetWireCodec.read_u16(p, i) != 1001:
		return _fail("full birth ship_id")
	if NetWireCodec.read_u8(p, i + 2) != 1:
		return _fail("full birth star")
	return 0
