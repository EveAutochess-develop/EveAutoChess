extends RefCounted
class_name NullsecRoundPairing
## MULTIPLAYER_MATCH_FLOW §5.2 — host-authoritative nullsec PVP matchups.
## Odd bye + no rematch (unless exactly 2 alive contestants).


## contenders: [{seat_id, is_ai, region_id}]
## last_rival_by_seat: seat_id -> prior rival seat, or -1 if last round was PVE/bye
## Returns { pairs: [[a,b],...], bye_seat: int, rival_of: {seat:rival}, degraded: bool }
static func build_matchups(
	contenders: Array,
	last_rival_by_seat: Dictionary,
	rng: MatchRng,
	battle_serial: int
) -> Dictionary:
	var seats: Array = []
	for c_v: Variant in contenders:
		var c: Dictionary = TypedVariant.as_dict(c_v)
		var sid: int = TypedVariant.as_int(c.get("seat_id", -1), -1)
		if sid < 0:
			continue
		seats.append({
			"seat_id": sid,
			"is_ai": TypedVariant.as_bool(c.get("is_ai", false), false),
			"region_id": str(c.get("region_id", "")),
		})
	var out: Dictionary = {
		"pairs": [],
		"bye_seat": -1,
		"rival_of": {},
		"degraded": false,
	}
	var n: int = seats.size()
	if n <= 0:
		return out
	if n == 1:
		var only_row: Dictionary = TypedVariant.as_dict(seats[0])
		var only: int = TypedVariant.as_int(only_row.get("seat_id", -1), -1)
		out["bye_seat"] = only
		return out
	var ban_rematch: bool = n > 2
	var pool: Array = seats.duplicate(true)
	var degraded: bool = false
	var bye_seat: int = -1
	if pool.size() % 2 == 1:
		var bye_pick: Dictionary = _pick_bye(pool, last_rival_by_seat, rng, battle_serial)
		bye_seat = TypedVariant.as_int(bye_pick.get("seat_id", -1), -1)
		degraded = degraded or TypedVariant.as_bool(bye_pick.get("degraded", false), false)
		pool = _without_seat(pool, bye_seat)
	out["bye_seat"] = bye_seat
	var used: Dictionary = {}
	var pairs: Array = []
	var rival_of: Dictionary = {}
	## Stable seat order then greedy pair with NearRegionMatcher.
	_sort_contenders_by_seat(pool)
	for i: int in range(pool.size()):
		var a_row: Dictionary = TypedVariant.as_dict(pool[i])
		var a: int = TypedVariant.as_int(a_row.get("seat_id", -1), -1)
		if a < 0 or used.has(a):
			continue
		var cands: Array = []
		for j: int in range(i + 1, pool.size()):
			var b_row: Dictionary = TypedVariant.as_dict(pool[j])
			var b: int = TypedVariant.as_int(b_row.get("seat_id", -1), -1)
			if b < 0 or used.has(b):
				continue
			cands.append(b_row)
		if cands.is_empty():
			## Odd leftover after filters — treat as bye if we somehow still have one.
			if bye_seat < 0:
				bye_seat = a
				out["bye_seat"] = a
			continue
		var filtered: Array = cands
		if ban_rematch:
			filtered = _filter_rematch(a, cands, last_rival_by_seat)
			if filtered.is_empty():
				filtered = cands
				degraded = true
				SessionDiagnostics.log(
					"mp.pair_degrade",
					"rematch_relax seat=%d" % a
				)
		var a_region: String = str(a_row.get("region_id", ""))
		var pick: int = NearRegionMatcher.pick_opponent(a_region, filtered, rng, battle_serial)
		if pick < 0:
			var fb: Dictionary = TypedVariant.as_dict(filtered[0])
			pick = TypedVariant.as_int(fb.get("seat_id", -1), -1)
		if pick < 0:
			continue
		used[a] = true
		used[pick] = true
		pairs.append([a, pick])
		rival_of[a] = pick
		rival_of[pick] = a
	out["pairs"] = pairs
	out["rival_of"] = rival_of
	out["degraded"] = degraded
	return out


static func _sort_contenders_by_seat(pool: Array) -> void:
	pool.sort_custom(Callable(NullsecRoundPairing, "_cmp_seat_id"))


static func _cmp_seat_id(a: Variant, b: Variant) -> bool:
	var aa: int = TypedVariant.as_int(TypedVariant.as_dict(a).get("seat_id", 0), 0)
	var bb: int = TypedVariant.as_int(TypedVariant.as_dict(b).get("seat_id", 0), 0)
	return aa < bb


## After a finished round: update last_rival memory for next pairing.
## global_pve: entire round was sleeper PVE for all → clear all to -1.
static func advance_last_rivals(
	last_rival_by_seat: Dictionary,
	matchups: Dictionary,
	contender_seats: Array,
	global_pve: bool
) -> Dictionary:
	var next_map: Dictionary = last_rival_by_seat.duplicate(true)
	if global_pve:
		for sid_v: Variant in contender_seats:
			next_map[TypedVariant.as_int(sid_v, -1)] = -1
		return next_map
	var rival_of: Dictionary = TypedVariant.as_dict(matchups.get("rival_of", {}))
	var bye: int = TypedVariant.as_int(matchups.get("bye_seat", -1), -1)
	for sid_v: Variant in contender_seats:
		var sid: int = TypedVariant.as_int(sid_v, -1)
		if sid < 0:
			continue
		if sid == bye:
			next_map[sid] = -1
		elif rival_of.has(sid):
			next_map[sid] = TypedVariant.as_int(rival_of.get(sid, -1), -1)
		else:
			next_map[sid] = -1
	return next_map


static func rival_from_matchups(matchups: Dictionary, seat: int) -> int:
	if seat < 0:
		return -1
	var bye: int = TypedVariant.as_int(matchups.get("bye_seat", -1), -1)
	if seat == bye:
		return -1
	var rival_of: Dictionary = TypedVariant.as_dict(matchups.get("rival_of", {}))
	if rival_of.has(seat):
		return TypedVariant.as_int(rival_of.get(seat, -1), -1)
	## Also accept pairs list.
	for p_v: Variant in TypedVariant.as_array(matchups.get("pairs", [])):
		var p: Array = TypedVariant.as_array(p_v)
		if p.size() < 2:
			continue
		var a: int = TypedVariant.as_int(p[0], -1)
		var b: int = TypedVariant.as_int(p[1], -1)
		if a == seat:
			return b
		if b == seat:
			return a
	return -1


static func _pick_bye(
	pool: Array,
	last_rival_by_seat: Dictionary,
	rng: MatchRng,
	battle_serial: int
) -> Dictionary:
	## Prefer seats that fought a player last round; never pick protected humans first.
	var preferred: Array = []
	var ai_pool: Array = []
	var protected_humans: Array = []
	for row_v: Variant in pool:
		var row: Dictionary = TypedVariant.as_dict(row_v)
		var sid: int = TypedVariant.as_int(row.get("seat_id", -1), -1)
		var is_ai: bool = TypedVariant.as_bool(row.get("is_ai", false), false)
		var last_r: int = TypedVariant.as_int(last_rival_by_seat.get(sid, -1), -1)
		if is_ai:
			ai_pool.append(row)
		if last_r >= 0:
			preferred.append(row)
		elif not is_ai:
			protected_humans.append(row)
	var pick_from: Array = preferred
	var degraded: bool = false
	if pick_from.is_empty():
		pick_from = ai_pool
	if pick_from.is_empty():
		pick_from = pool
		degraded = true
		SessionDiagnostics.log("mp.pair_degrade", "bye_protected_exhausted n=%d" % pool.size())
	var idx: int = 0
	if rng != null and pick_from.size() > 1:
		idx = rng.roll_int(battle_serial, "nullsec_bye", 0, pick_from.size() - 1)
	var chosen: Dictionary = TypedVariant.as_dict(pick_from[clampi(idx, 0, pick_from.size() - 1)])
	return {
		"seat_id": TypedVariant.as_int(chosen.get("seat_id", -1), -1),
		"degraded": degraded,
	}


static func _filter_rematch(seat_a: int, cands: Array, last_rival_by_seat: Dictionary) -> Array:
	var last_a: int = TypedVariant.as_int(last_rival_by_seat.get(seat_a, -1), -1)
	var out: Array = []
	for c_v: Variant in cands:
		var c: Dictionary = TypedVariant.as_dict(c_v)
		var b: int = TypedVariant.as_int(c.get("seat_id", -1), -1)
		if b < 0:
			continue
		if last_a >= 0 and b == last_a:
			continue
		var last_b: int = TypedVariant.as_int(last_rival_by_seat.get(b, -1), -1)
		if last_b >= 0 and last_b == seat_a:
			continue
		out.append(c)
	return out


static func _without_seat(pool: Array, seat_id: int) -> Array:
	var out: Array = []
	for row_v: Variant in pool:
		var row: Dictionary = TypedVariant.as_dict(row_v)
		if TypedVariant.as_int(row.get("seat_id", -1), -1) == seat_id:
			continue
		out.append(row)
	return out
