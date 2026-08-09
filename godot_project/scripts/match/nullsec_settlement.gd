extends RefCounted
class_name NullsecSettlement
## Ghost seat + end-of-match list / match_report history (MULTIPLAYER_MATCH_FLOW §2.1).

static func make_row(
	nick: String,
	level: int,
	gold_earned: int,
	result: String,
	ships: Array,
	titles: Array = [],
	seat_id: int = -1,
	wins: int = 0,
	losses: int = 0,
	draws: int = 0,
	rank: int = 0,
	kills: int = 0,
	is_ai: bool = false,
	absent: bool = false
) -> Dictionary:
	## ships: [{ship_id, star, equips?}]; titles: [{"title": "完美胜利"}, ...] (MULTIPLAYER_PVP §7.1).
	return {
		"nick": nick,
		"nick_full": NickCodec.sanitize(nick),
		"level": level,
		"gold_earned": gold_earned,
		"result": result, ## rank outcome / WLD label
		"ships": ships,
		"titles": titles,
		"seat_id": seat_id,
		"wins": wins,
		"losses": losses,
		"draws": draws,
		"rank": rank,
		"kills": kills,
		"is_ai": is_ai,
		"absent": absent,
	}


## §7.1 结算/历史每人第二行："称号 ，称号*n"（n≥2 才加 *n）。Accepts either a plain
## Array of title-name Strings or an Array of {"title": name} Dictionaries.
static func format_titles_line(titles: Array) -> String:
	if titles.is_empty():
		return ""
	var counts: Dictionary = {}
	var order: Array = []
	for t_v: Variant in titles:
		var name: String = ""
		if typeof(t_v) == TYPE_DICTIONARY:
			var t: Dictionary = t_v
			name = str(t.get("title", t.get("name", "")))
		else:
			name = str(t_v)
		name = name.strip_edges()
		if name == "":
			continue
		if not counts.has(name):
			counts[name] = 0
			order.append(name)
		counts[name] = TypedVariant.as_int(counts[name], 0) + 1
	var parts: PackedStringArray = PackedStringArray()
	for name: String in order:
		var n: int = TypedVariant.as_int(counts[name], 1)
		parts.append("%s*%d" % [name, n] if n >= 2 else name)
	return " ，".join(parts)


## MULTIPLAYER_PVP §7 — death order (later = better) → gold → kills → rng shuffle.
static func assign_ranks(players: Array, rng: MatchRng = null) -> Array:
	var rows: Array = players.duplicate()
	## Stable shuffle keys first.
	var shuffle_keys: Dictionary = {}
	for i: int in range(rows.size()):
		var seat: int = TypedVariant.as_int(TypedVariant.as_dict(rows[i]).get("seat_id", i), i)
		if rng != null:
			shuffle_keys[seat] = rng.stream_randf("rank_shuffle")
		else:
			shuffle_keys[seat] = float(seat)
	rows.sort_custom(func(a_v: Variant, b_v: Variant) -> bool:
		var a: Dictionary = TypedVariant.as_dict(a_v)
		var b: Dictionary = TypedVariant.as_dict(b_v)
		var ae: int = TypedVariant.as_int(a.get("elimination_order", 0), 0)
		var be: int = TypedVariant.as_int(b.get("elimination_order", 0), 0)
		## Alive (0) sorts after any death order; among dead, higher order = later death = better.
		var a_alive: bool = ae <= 0
		var b_alive: bool = be <= 0
		if a_alive != b_alive:
			return a_alive ## alive first
		if not a_alive and ae != be:
			return ae > be
		var ag: int = TypedVariant.as_int(a.get("gold_earned", 0), 0)
		var bg: int = TypedVariant.as_int(b.get("gold_earned", 0), 0)
		if ag != bg:
			return ag > bg
		var ak: int = TypedVariant.as_int(a.get("kills", 0), 0)
		var bk: int = TypedVariant.as_int(b.get("kills", 0), 0)
		if ak != bk:
			return ak > bk
		var asid: int = TypedVariant.as_int(a.get("seat_id", 0), 0)
		var bsid: int = TypedVariant.as_int(b.get("seat_id", 0), 0)
		return TypedVariant.as_float(shuffle_keys.get(asid, 0.0), 0.0) < TypedVariant.as_float(shuffle_keys.get(bsid, 0.0), 0.0)
	)
	for i: int in range(rows.size()):
		var r: Dictionary = TypedVariant.as_dict(rows[i])
		r["rank"] = i + 1
		if str(r.get("result", "")) == "" or str(r.get("result", "")) == "—" or str(r.get("result", "")) in ["胜", "负", "平"]:
			var elim: int = TypedVariant.as_int(r.get("elimination_order", 0), 0)
			if i == 0:
				r["result"] = "冠军"
			elif elim > 0:
				r["result"] = "淘汰"
			else:
				r["result"] = "存活"
		rows[i] = r
	return rows


static func make_match_report(match_id: String, local_seat: int, players: Array, rng: MatchRng = null) -> Dictionary:
	## players: full-seat rows for detail; list bar uses local seat only.
	var ranked: Array = assign_ranks(players, rng)
	var local_row: Dictionary = {}
	for p_v: Variant in ranked:
		if typeof(p_v) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_v
		if TypedVariant.as_int(p.get("seat_id", -1), -1) == local_seat:
			local_row = p
			break
	return {
		"match_id": match_id,
		"at": Time.get_datetime_string_from_system(),
		"local_seat": local_seat,
		"summary": local_row,
		"players": ranked,
		"rows": ranked, ## backward compat with old panel
	}


static func save_history(rows: Array) -> void:
	## Legacy: append rows-only entry.
	save_match_report({"at": Time.get_datetime_string_from_system(), "rows": rows, "players": rows})


static func save_match_report(report: Dictionary) -> void:
	## Upsert by match_id (MULTIPLAYER_PVP §7.0b): same id replaces; empty/missing id appends.
	var path: String = "user://save/nullsec_history.json"
	var prev: Array = []
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_ARRAY:
			prev = parsed
	var mid: String = str(report.get("match_id", "")).strip_edges()
	var replaced: bool = false
	if mid != "":
		for i: int in range(prev.size()):
			if typeof(prev[i]) != TYPE_DICTIONARY:
				continue
			var existing: Dictionary = prev[i]
			if str(existing.get("match_id", "")).strip_edges() == mid:
				prev[i] = report
				replaced = true
				break
	if not replaced:
		prev.append(report)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prev, "\t"))
	NetSessionDebug.log_event(
		"net.match_report",
		"id=%s players=%d upsert=%d provisional=%d" % [
			mid,
			TypedVariant.as_array(report.get("players", [])).size(),
			1 if replaced else 0,
			1 if TypedVariant.as_bool(report.get("provisional", false), false) else 0,
		]
	)


static func load_all() -> Array:
	var path: String = "user://save/nullsec_history.json"
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		return []
	return parsed
