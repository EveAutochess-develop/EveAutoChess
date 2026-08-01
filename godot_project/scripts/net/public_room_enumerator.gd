extends RefCounted
class_name PublicRoomEnumerator
## Public codes 1..9999; continue cursor; reverse after 9999→1.

static func next_codes(batch: int = 32) -> Array:
	var st: Dictionary = NullsecLobbyPopup.load_enum_cursor()
	var cursor := int(st.get("cursor", 1))
	var dir := int(st.get("dir", 1))
	var out: Array = []
	for _i in range(batch):
		out.append(cursor)
		var stepped: Dictionary = step(cursor, dir)
		cursor = int(stepped["cursor"])
		dir = int(stepped["dir"])
	NullsecLobbyPopup.save_enum_cursor(cursor, dir)
	return out


static func peek_cursor() -> int:
	return int(NullsecLobbyPopup.load_enum_cursor().get("cursor", 1))


static func peek_dir() -> int:
	return int(NullsecLobbyPopup.load_enum_cursor().get("dir", 1))


static func step(cursor: int, dir: int) -> Dictionary:
	cursor += dir
	if cursor > 9999:
		cursor = 9999
		dir = -1
	elif cursor < 1:
		cursor = 1
		dir = 1
	return {"cursor": cursor, "dir": dir}


## Advance persisted cursor to just past `code` (same sweep direction).
static func advance_past(code: int) -> void:
	var st: Dictionary = NullsecLobbyPopup.load_enum_cursor()
	var dir := int(st.get("dir", 1))
	var next := clampi(code, 1, 9999) + dir
	if next > 9999:
		next = 9999
		dir = -1
	elif next < 1:
		next = 1
		dir = 1
	NullsecLobbyPopup.save_enum_cursor(next, dir)


## Count same-version public rooms currently in match (for skip hint).
static func count_in_match_public(rooms: Array, rules_hash: String) -> int:
	var n := 0
	for r in rooms:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = r
		if bool(d.get("private", false)):
			continue
		if str(d.get("rules", "")) != rules_hash:
			continue
		if bool(d.get("in_match", false)):
			n += 1
	return n


## Pick first joinable public room at/after cursor; wrap to min if none.
## Full rooms (occupied>=20) silently skipped. ignore_in_match skips in_match ads.
static func pick_public_room(rooms: Array, rules_hash: String, ignore_in_match: bool = false) -> Dictionary:
	var cursor := peek_cursor()
	var dir := peek_dir()
	var candidates: Array = []
	for r in rooms:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = r
		if bool(d.get("private", false)):
			continue
		if str(d.get("rules", "")) != rules_hash:
			continue
		var occ := int(d.get("occupied", 0))
		var cap := int(d.get("cap", NullsecNetSession.SEAT_TOTAL))
		if occ >= cap:
			continue ## silent skip full
		if ignore_in_match and bool(d.get("in_match", false)):
			continue
		var code := int(d.get("code", 0))
		if code < 1 or code > 9999:
			continue
		candidates.append(d)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("code", 0)) < int(b.get("code", 0))
	)
	## Prefer first code >= cursor when sweeping forward; <= when reverse.
	if dir >= 0:
		for d in candidates:
			if int(d.get("code", 0)) >= cursor:
				return d
		return candidates[0]
	for i in range(candidates.size() - 1, -1, -1):
		var d: Dictionary = candidates[i]
		if int(d.get("code", 0)) <= cursor:
			return d
	return candidates[candidates.size() - 1]


## First free public code starting at cursor, skipping `taken` codes.
static func claim_free_code(taken: Dictionary) -> int:
	var st: Dictionary = NullsecLobbyPopup.load_enum_cursor()
	var cursor := int(st.get("cursor", 1))
	var dir := int(st.get("dir", 1))
	var start := cursor
	for _i in range(9999):
		if not taken.has(cursor):
			var stepped: Dictionary = step(cursor, dir)
			NullsecLobbyPopup.save_enum_cursor(int(stepped["cursor"]), int(stepped["dir"]))
			return cursor
		var s2: Dictionary = step(cursor, dir)
		cursor = int(s2["cursor"])
		dir = int(s2["dir"])
		if cursor == start and _i > 0:
			break
	return clampi(start, 1, 9999)
