extends RefCounted
class_name NearRegionMatcher
## D-EAC-27 stub: weight by region adjacency / shared skybox neighborhood.

static func pick_opponent(self_region: String, candidates: Array, rng: MatchRng, battle_serial: int) -> int:
	## candidates: [{seat_id, region_id}]
	if candidates.is_empty():
		return -1
	var weights: Array = []
	var total := 0
	for c in candidates:
		var rid := str(c.get("region_id", ""))
		var w := 10
		if rid == self_region:
			w = 40
		elif rid != "" and self_region != "" and rid.substr(0, 3) == self_region.substr(0, 3):
			w = 25
		weights.append(w)
		total += w
	if total <= 0 or rng == null:
		return int(candidates[0].get("seat_id", 0))
	var roll := rng.roll_int(battle_serial, "retarget_tiebreak", 0, total - 1)
	var acc := 0
	for i in range(candidates.size()):
		acc += int(weights[i])
		if roll < acc:
			return int(candidates[i].get("seat_id", 0))
	return int(candidates[candidates.size() - 1].get("seat_id", 0))
