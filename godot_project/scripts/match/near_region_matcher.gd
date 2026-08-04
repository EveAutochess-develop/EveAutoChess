extends RefCounted
class_name NearRegionMatcher
## D-EAC-27 stub: weight by region adjacency / shared skybox neighborhood.

static func pick_opponent(self_region: String, candidates: Array, rng: MatchRng, battle_serial: int) -> int:
	## candidates: [{seat_id, region_id}]
	if candidates.is_empty():
		return -1
	var weights: Array = []
	var total: int = 0
	for c_v: Variant in candidates:
		if not (c_v is Dictionary):
			continue
		var c: Dictionary = c_v
		var rid: String = str(c.get("region_id", ""))
		var w: int = 10
		if rid == self_region:
			w = 40
		elif rid != "" and self_region != "" and rid.substr(0, 3) == self_region.substr(0, 3):
			w = 25
		weights.append(w)
		total += w
	if total <= 0 or rng == null:
		var c0: Dictionary = candidates[0] if candidates[0] is Dictionary else {}
		return TypedVariant.as_int(c0.get("seat_id", 0), 0)
	var roll: int = rng.roll_int(battle_serial, "retarget_tiebreak", 0, total - 1)
	var acc: int = 0
	for i: int in range(candidates.size()):
		acc += TypedVariant.as_int(weights[i], 0)
		if roll < acc:
			var ci: Dictionary = candidates[i] if candidates[i] is Dictionary else {}
			return TypedVariant.as_int(ci.get("seat_id", 0), 0)
	var clast: Dictionary = candidates[candidates.size() - 1] if candidates[candidates.size() - 1] is Dictionary else {}
	return TypedVariant.as_int(clast.get("seat_id", 0), 0)
