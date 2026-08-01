extends RefCounted
class_name NullsecSettlement
## Ghost seat + end-of-match list rows.

static func make_row(nick: String, level: int, gold_earned: int, result: String, ships: Array) -> Dictionary:
	## ships: [{ship_id, star}]
	return {
		"nick": nick,
		"level": level,
		"gold_earned": gold_earned,
		"result": result, ## W/L/D
		"ships": ships,
	}

static func save_history(rows: Array) -> void:
	var path := "user://save/nullsec_history.json"
	var prev: Array = []
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_ARRAY:
			prev = parsed
	prev.append({"at": Time.get_datetime_string_from_system(), "rows": rows})
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prev, "\t"))
