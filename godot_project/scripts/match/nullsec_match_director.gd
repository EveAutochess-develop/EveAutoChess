extends RefCounted
class_name NullsecMatchDirector
## Lobby → assign nullsec regions (must include Period Basis) → hand off to orchestrator.

signal regions_assigned(assignments: Dictionary)

var match_rng: MatchRng
var seats: Array = [] ## [{seat_id, nick, is_ai, titan_race, ready, region_id}]
var assignments: Dictionary = {} ## seat_id -> region_id

func setup(rng: MatchRng) -> void:
	match_rng = rng

func set_seats(p_seats: Array) -> void:
	seats = p_seats.duplicate(true)

func all_ready_and_titans_selected() -> bool:
	if seats.is_empty():
		return false
	for s in seats:
		if not bool(s.get("ready", false)):
			return false
		if str(s.get("titan_race", "")) == "":
			return false
	return true

func assign_regions() -> Dictionary:
	## One region per participating player seat; spectators skipped.
	var pool: Array = SkyboxCatalog.nullsec_regions()
	var ids: Array = []
	for r in pool:
		var rid := str(r.get("region_id", ""))
		if rid != "":
			ids.append(rid)
	if ids.is_empty():
		ids = ["period_basis", "delve", "fountain", "querious"]
	var must: Array = SkyboxCatalog.must_include_region_ids()
	for m in must:
		var ms := str(m)
		if ms not in ids:
			ids.append(ms)
	## Shuffle with match stream
	var shuffled: Array = ids.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := 0
		if match_rng:
			j = match_rng.stream_randi_range("match", 0, i)
		else:
			j = randi() % (i + 1)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var player_seats: Array = []
	for seat in seats:
		if typeof(seat) != TYPE_DICTIONARY:
			continue
		var race := str(seat.get("titan_race", ""))
		if NullsecNetSession.is_spectate_race(race):
			continue
		if not bool(seat.get("occupied", true)):
			continue
		player_seats.append(seat)
	var n := mini(player_seats.size(), shuffled.size())
	var picked: Array = shuffled.slice(0, maxi(n, 1))
	var must_id := "period_basis"
	if must.size() > 0:
		must_id = str(must[0])
	if must_id not in picked and must_id in shuffled:
		if picked.is_empty():
			picked.append(must_id)
		else:
			## Drop it on a random slot: pinning index 0 handed 贝斯星域 to seat 0
			## (normally the local player) every single match.
			var slot := 0
			if picked.size() > 1:
				if match_rng:
					slot = match_rng.stream_randi_range("match", 0, picked.size() - 1)
				else:
					slot = randi() % picked.size()
			picked[slot] = must_id
	assignments.clear()
	for i in range(player_seats.size()):
		var seat: Dictionary = player_seats[i]
		var sid := int(seat.get("seat_id", i))
		var rid := str(picked[i % picked.size()]) if not picked.is_empty() else must_id
		assignments[sid] = rid
		seat["region_id"] = rid
	regions_assigned.emit(assignments)
	return assignments.duplicate()
