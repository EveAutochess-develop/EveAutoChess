extends RefCounted
class_name MatchSave
## Match saves: last_match.json + named slots index (flagship test first).

const SAVE_PATH := "user://save/last_match.json"
const SLOTS_INDEX_PATH := "user://save/slots_index.json"
const FLAGSHIP_TEST_ID := "qijian_test"
const FLAGSHIP_TEST_NAME := "旗舰测试"
const FLAGSHIP_TEST_PATH := "user://save/slot_qijian_test.json"
const SAVE_VERSION := 1

static func exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

static func clear() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

static func save_from_match(mc: MatchController, board: BoardController, ai: AiController) -> bool:
	if mc == null or board == null:
		return false
	var data := _build_save_dict(mc, board, ai)
	DirAccess.make_dir_recursive_absolute("user://save")
	if not _write_json(SAVE_PATH, data):
		return false
	## last_match rolls every Prepare; 旗舰测试 is a frozen archive (seed once, never mirror).
	_seed_flagship_test_slot_if_missing(data)
	_log_save_census(data)
	return true

static func load_dict() -> Dictionary:
	return _read_json(SAVE_PATH)

static func load_slot_dict(slot_id: String) -> Dictionary:
	var entry := _find_slot(slot_id)
	if entry.is_empty():
		return {}
	return _read_json(str(entry.get("path", "")))

static func list_slots() -> Array:
	_ensure_slots_seeded_from_last()
	var idx := _read_json(SLOTS_INDEX_PATH)
	var slots: Array = idx.get("slots", [])
	if typeof(slots) != TYPE_ARRAY:
		return []
	return slots

static func _build_save_dict(mc: MatchController, board: BoardController, ai: AiController) -> Dictionary:
	var ships: Array = []
	for s in board.all_ships():
		if s == null or s.is_destroyed or s.is_unmanned:
			continue
		ships.append({
			"ship_id": s.ship_id,
			"star": s.star,
			"team": s.team_id,
			"slot_type": s.slot_type,
			"x": s.grid_x,
			"z": s.grid_z,
			"field_side_team": s.field_side_team,
		})
	var shop_slots: Array = []
	if mc._shop != null:
		shop_slots = mc._shop.slots.duplicate(true)
	return {
		"save_version": SAVE_VERSION,
		"mode": mc.mode,
		"battle_game_stage_count": mc.battle_game_stage_count,
		"round_phase_value": mc.round_phase_value,
		"battle_phase_value": mc.battle_phase_value,
		"player": {
			"gold": mc.player_gold,
			"hp": mc.player_hp,
			"max_hp": mc.player_max_hp,
			"level": mc.player_level,
			"exp": mc.player_exp,
			"up_level_demand": mc.up_level_demand,
			"win_streak": mc.win_streak,
			"loss_streak": mc.loss_streak,
			"shop_locked": mc.shop_locked,
			"shop_slots": shop_slots,
		},
		"ai": {
			"gold": ai.ai_gold if ai else 0,
			"hp": mc.ai_hp,
			"max_hp": mc.ai_max_hp,
			"level": ai.ai_level if ai else 1,
			"exp": ai.ai_exp if ai else 0,
			"up_level_demand": ai.up_level_demand if ai else 4,
			"win_streak": ai.win_streak if ai else 0,
			"loss_streak": ai.loss_streak if ai else 0,
			"shop_slots": ai.shop_slots.duplicate(true) if ai else [],
		},
		"ships": ships,
	}

static func _count_team_ships(data: Dictionary, team: int) -> int:
	var n := 0
	for s in data.get("ships", []):
		if typeof(s) == TYPE_DICTIONARY and int((s as Dictionary).get("team", -1)) == team:
			n += 1
	return n


static func _ensure_flagship_index_entry() -> void:
	var idx := _read_json(SLOTS_INDEX_PATH)
	var slots: Array = idx.get("slots", []) if typeof(idx.get("slots", [])) == TYPE_ARRAY else []
	for s in slots:
		if typeof(s) == TYPE_DICTIONARY and str((s as Dictionary).get("id", "")) == FLAGSHIP_TEST_ID:
			return
	var filtered: Array = []
	for s in slots:
		if typeof(s) == TYPE_DICTIONARY:
			filtered.append(s)
	filtered.push_front({
		"id": FLAGSHIP_TEST_ID,
		"name": FLAGSHIP_TEST_NAME,
		"path": FLAGSHIP_TEST_PATH,
		"updated_at": Time.get_datetime_string_from_system(true, true),
	})
	_write_json(SLOTS_INDEX_PATH, {"slots": filtered})


static func _write_flagship_index_entry_fresh() -> void:
	## Called only when the slot file itself is newly written.
	var idx := _read_json(SLOTS_INDEX_PATH)
	var slots: Array = idx.get("slots", []) if typeof(idx.get("slots", [])) == TYPE_ARRAY else []
	var filtered: Array = []
	for s in slots:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str((s as Dictionary).get("id", "")) == FLAGSHIP_TEST_ID:
			continue
		filtered.append(s)
	filtered.push_front({
		"id": FLAGSHIP_TEST_ID,
		"name": FLAGSHIP_TEST_NAME,
		"path": FLAGSHIP_TEST_PATH,
		"updated_at": Time.get_datetime_string_from_system(true, true),
	})
	_write_json(SLOTS_INDEX_PATH, {"slots": filtered})


static func _seed_flagship_test_slot_if_missing(data: Dictionary) -> void:
	## Named slot is write-once: autosave must never refresh it after the first seed.
	## (Earlier "skip only if p0==0" still let mid-match losses / sold capitals overwrite the archive.)
	if FileAccess.file_exists(FLAGSHIP_TEST_PATH):
		_ensure_flagship_index_entry()
		return
	if _count_team_ships(data, 0) <= 0:
		return
	if not _write_json(FLAGSHIP_TEST_PATH, data):
		return
	_write_flagship_index_entry_fresh()


static func _log_save_census(data: Dictionary) -> void:
	var diag := SessionDiagnostics.instance()
	if diag == null:
		return
	var p0 := _count_team_ships(data, 0)
	var p1 := _count_team_ships(data, 1)
	var ids: PackedStringArray = PackedStringArray()
	for s in data.get("ships", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = s
		if int(e.get("team", -1)) != 0:
			continue
		ids.append("%s@%s(%s,%s)" % [e.get("ship_id"), e.get("slot_type"), e.get("x"), e.get("z")])
	diag.log_event("save", "p0=%d p1=%d gold=%s hp=%s ships=[%s]" % [
		p0, p1,
		str((data.get("player", {}) as Dictionary).get("gold", "?")),
		str((data.get("player", {}) as Dictionary).get("hp", "?")),
		",".join(ids),
	])

static func _ensure_slots_seeded_from_last() -> void:
	## If last_match exists but no slots yet, promote it as 旗舰测试.
	if not exists():
		return
	var idx := _read_json(SLOTS_INDEX_PATH)
	var slots: Array = idx.get("slots", []) if typeof(idx.get("slots", [])) == TYPE_ARRAY else []
	if not slots.is_empty():
		return
	var data := load_dict()
	if data.is_empty():
		return
	_seed_flagship_test_slot_if_missing(data)

static func _find_slot(slot_id: String) -> Dictionary:
	for s in list_slots():
		if typeof(s) == TYPE_DICTIONARY and str((s as Dictionary).get("id", "")) == slot_id:
			return s
	return {}

static func _write_json(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)
	return true

static func _read_json(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
