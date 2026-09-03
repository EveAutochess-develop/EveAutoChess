extends RefCounted
class_name PlaceHexOutputTranslator

## Temporary bridge: frozen 64-dim hex Place logits → polar (ring,sector) cells.
## @deprecated — delete when PlaceNet outputs N_field dims directly.

static var _hex_world_cache: Dictionary = {}


static func pick_cell(logits: PackedFloat32Array, candidates: Array[Vector2i]) -> Vector2i:
	if candidates.is_empty():
		return Vector2i(-1, -1)
	var best: Vector2i = candidates[0]
	var best_v: float = -1.0e9
	for c: Vector2i in candidates:
		var hex_idx: int = _polar_to_hex_slot(c.x, c.y)
		var v: float = logits[hex_idx] if hex_idx >= 0 and hex_idx < logits.size() else -1.0e9
		if v > best_v:
			best_v = v
			best = c
		elif absf(v - best_v) < 1e-5:
			if c.x < best.x or (c.x == best.x and c.y < best.y):
				best = c
	return best


static func build_mask(candidates: Array[Vector2i]) -> PackedFloat32Array:
	var mask: PackedFloat32Array = PackedFloat32Array()
	mask.resize(PolicyObs.MAX_CELLS)
	for c: Vector2i in candidates:
		var idx: int = _polar_to_hex_slot(c.x, c.y)
		if idx >= 0 and idx < PolicyObs.MAX_CELLS:
			mask[idx] = 1.0
	return mask


static func hex_slot_for_polar_cell(ring: int, sector: int) -> int:
	return _polar_to_hex_slot(ring, sector)


static func _polar_to_hex_slot(ring: int, sector: int) -> int:
	_ensure_hex_cache()
	var polar_pos: Vector3 = BoardPolarGrid.field_cell_to_world(ShipUnit.TEAM_AI, ring, sector)
	var best_key: String = ""
	var best_d: float = INF
	for key: String in _hex_world_cache:
		var p: Vector3 = _hex_world_cache[key]
		var d: float = Vector2(p.x - polar_pos.x, p.z - polar_pos.z).length_squared()
		if d < best_d:
			best_d = d
			best_key = key
	if best_key == "":
		return PolicyObs.flatten_cell(ring, sector)
	var parts: PackedStringArray = best_key.split(",")
	return PolicyObs.flatten_cell(int(parts[0]), int(parts[1]))


static func _ensure_hex_cache() -> void:
	if not _hex_world_cache.is_empty():
		return
	var fh: int = TypedVariant.as_int(DataStore.board.get("field_height", 6), 6)
	for z: int in range(fh):
		var cols: int = BoardController.field_cols_at(z)
		for x: int in range(cols):
			var p: Vector3 = _legacy_hex_cell_to_world(ShipUnit.TEAM_AI, x, z)
			_hex_world_cache["%d,%d" % [x, z]] = p


static func _legacy_hex_cell_to_world(team: int, x: int, z: int) -> Vector3:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var ox: float = TypedVariant.as_float(b.get("hex_offset_x", -3.0), -3.0)
	var oz: float = TypedVariant.as_float(b.get("hex_offset_z", -2.5), -2.5)
	var fh: int = TypedVariant.as_int(b.get("field_height", 6), 6)
	var hoz: float = absf(oz)
	var gap: float = TypedVariant.as_float(b.get("center_gap_z", 4.0), 4.0)
	var fo_z: float = float(fh - 1) * hoz + gap
	if team == ShipUnit.TEAM_AI:
		fo_z = -fo_z
	var cols: int = BoardController.field_cols_at(z)
	var row_left: float = float(cols - 1) * absf(ox) * 0.5
	var offset_x: float = row_left + float(x) * ox
	var offset_z: float = float(z) * oz
	if team == ShipUnit.TEAM_AI:
		offset_x = -offset_x
		offset_z = -offset_z
	return Vector3(offset_x, 0.05, fo_z + offset_z)
