extends RefCounted
class_name PublicRoomEnumerator
## Room codes 1..9999; continue cursor; reverse after 9999→1.
## SEMI_ASYNC §7 — no private filter; match try-joins all candidates.
@warning_ignore_start("untyped_declaration", "inferred_declaration", "unsafe_method_access", "unsafe_call_argument", "inference_on_variant", "unsafe_cast")

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


static func count_in_match(rooms: Array, rules_hash: String) -> int:
	var n := 0
	for r in rooms:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = r
		if str(d.get("rules", "")) != rules_hash:
			continue
		if bool(d.get("in_match", false)):
			n += 1
	return n


static func count_rules_mismatch(rooms: Array, rules_hash: String) -> int:
	var n := 0
	for r in rooms:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = r
		var rh := str(d.get("rules", ""))
		if rh == "" or rh == rules_hash:
			continue
		n += 1
	return n


## Deprecated aliases.
static func count_in_match_public(rooms: Array, rules_hash: String) -> int:
	return count_in_match(rooms, rules_hash)


static func count_rules_mismatch_public(rooms: Array, rules_hash: String) -> int:
	return count_rules_mismatch(rooms, rules_hash)


## Ordered join candidates (same rules, not full); optional skip in_match.
## Same room_code on multiple hosts is kept as separate endpoints (key ip:port).
static func list_join_candidates(rooms: Array, rules_hash: String, ignore_in_match: bool = false) -> Array:
	var cursor := peek_cursor()
	var dir := peek_dir()
	var candidates: Array = []
	var seen_ep: Dictionary = {} ## "ip:port" — never collapse by code alone
	for r in rooms:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = r
		if str(d.get("rules", "")) != rules_hash:
			continue
		var occ := int(d.get("occupied", 0))
		var cap := int(d.get("cap", NullsecNetSession.SEAT_TOTAL))
		if occ >= cap:
			continue
		if ignore_in_match and bool(d.get("in_match", false)):
			continue
		var code := int(d.get("code", 0))
		if code < 1 or code > 9999:
			continue
		var ip := str(d.get("ip", ""))
		var port := int(d.get("port", NullsecNetSession.port_for_code(code)))
		var ep := "%s:%d" % [ip, port]
		if ep == ":0" or seen_ep.has(ep):
			continue
		seen_ep[ep] = true
		candidates.append(d)
	if candidates.is_empty():
		return []
	## code asc, then emptier first when same code (prefer joinable public seats).
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := int(a.get("code", 0))
		var cb := int(b.get("code", 0))
		if ca != cb:
			return ca < cb
		return int(a.get("occupied", 0)) < int(b.get("occupied", 0))
	)
	## Rotate so sweep starts at cursor (all endpoints with that code stay contiguous).
	var ordered: Array = []
	if dir >= 0:
		for d in candidates:
			if int(d.get("code", 0)) >= cursor:
				ordered.append(d)
		for d in candidates:
			if int(d.get("code", 0)) < cursor:
				ordered.append(d)
	else:
		for i in range(candidates.size() - 1, -1, -1):
			var d: Dictionary = candidates[i]
			if int(d.get("code", 0)) <= cursor:
				ordered.append(d)
		for i in range(candidates.size() - 1, -1, -1):
			var d2: Dictionary = candidates[i]
			if int(d2.get("code", 0)) > cursor:
				ordered.append(d2)
	return ordered


## Count full rooms (occupied>=cap) with matching rules.
static func count_full(rooms: Array, rules_hash: String) -> int:
	var n := 0
	for r in rooms:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = r
		if str(d.get("rules", "")) != rules_hash:
			continue
		var occ := int(d.get("occupied", 0))
		var cap := int(d.get("cap", NullsecNetSession.SEAT_TOTAL))
		if occ >= cap:
			n += 1
	return n


## Pick first joinable room at/after cursor (legacy single-pick).
static func pick_public_room(rooms: Array, rules_hash: String, ignore_in_match: bool = false) -> Dictionary:
	var list := list_join_candidates(rooms, rules_hash, ignore_in_match)
	if list.is_empty():
		return {}
	return list[0]


## First free code starting at cursor, skipping `taken` codes (LAN peer codes + local bind fails).
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
