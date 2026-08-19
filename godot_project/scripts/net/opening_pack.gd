extends RefCounted
class_name OpeningPack
## SEMI_ASYNC §3.0b — opening digest hashes (zip/framed pack RPCs removed).


static func pack_hash_from_json(ships_json: String, seeds_json: String) -> String:
	return _hash_str(ships_json + "\n" + seeds_json)


static func pack_hash_only(ships_table: Dictionary, seeds_payload: Dictionary) -> String:
	return pack_hash_from_json(JSON.stringify(ships_table), JSON.stringify(seeds_payload))


static func _hash_str(s: String) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(s.to_utf8_buffer())
	return ctx.finish().hex_encode()
