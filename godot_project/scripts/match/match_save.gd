extends RefCounted
class_name MatchSave
## Match saves: last_match.json + named slots index (flagship test first).

const SAVE_PATH: String = "user://save/last_match.json"
const SLOTS_INDEX_PATH: String = "user://save/slots_index.json"
const FLAGSHIP_TEST_ID: String = "qijian_test"
const FLAGSHIP_TEST_NAME: String = "旗舰测试"
const FLAGSHIP_TEST_PATH: String = "user://save/slot_qijian_test.json"
## Shipped in logic.pck (Pack Logic include `data/*` except ships/equipment → data.pck); copied to user:// once if missing.
const BUNDLED_FLAGSHIP_TEST_PATH: String = "res://data/saves/slot_qijian_test.json"
const SAVE_VERSION: int = 1

## Solo resume modes only (`nullsec` is ticket-based, never last_match).
## Empty / unknown → "" so callers can fall back without inventing endless.
static func normalize_solo_mode(raw: Variant) -> String:
	var m: String = str(raw).strip_edges().to_lower()
	if m == "versus" or m == "endless":
		return m
	## Legacy / UI labels that may appear in hand-edited or old slots.
	if m == "vs" or m == "对战" or m == "对战模式":
		return "versus"
	if m == "无尽" or m == "无尽模式":
		return "endless"
	return ""


static func exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

static func clear() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

static func save_from_match(mc: MatchController, board: BoardController, ai: AiController) -> bool:
	if mc == null or board == null:
		return false
	## Snapshot must never capture cyno-gated hulls still sitting on field.
	if board.has_method("recall_cyno_entry_ships_to_hangar"):
		board.recall_cyno_entry_ships_to_hangar()
	## Never persist an empty shop row — refill quietly if needed.
	if mc._shop != null and mc._shop.slots.is_empty():
		mc._shop.refresh_shop(true, false)
	var data: Dictionary = _build_save_dict(mc, board, ai)
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
	var entry: Dictionary = _find_slot(slot_id)
	if entry.is_empty():
		return {}
	return _read_json(str(entry.get("path", "")))


## 仅主菜单「读取存档」点选旗舰测试时调用；禁止挂到 load_slot / last_match / 继续对局。
static func inject_flagship_test_ai_kit(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return data
	var out: Dictionary = data.duplicate(true)
	## Flagship test is always dual-citadel versus (MATCH_FLOW §5.0b).
	out["mode"] = "versus"
	var ships: Array = []
	var raw_ships: Variant = out.get("ships", [])
	if typeof(raw_ships) == TYPE_ARRAY:
		@warning_ignore("unsafe_cast")
		ships = (raw_ships as Array).duplicate(true)
	## Strip AI cyno/capitals AND clear AI hangar so 3 capitals always fit.
	var kept: Array = []
	for s_any: Variant in ships:
		if typeof(s_any) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var e: Dictionary = s_any as Dictionary
		if TypedVariant.as_int(e.get("team", -1), -1) != ShipUnit.TEAM_AI:
			kept.append(e)
			continue
		var sd: Dictionary = DataStore.get_ship(TypedVariant.as_int(e.get("ship_id", 0), 0))
		var role: String = str(sd.get("capital_role", ""))
		if role == "covert_cyno" or TypedVariant.as_bool(sd.get("requires_cyno_entry", false), false):
			continue
		## Free entire AI hangar for the test kit (field non-capitals may stay).
		if str(e.get("slot_type", "")) == "hangar":
			continue
		kept.append(e)
	var occ: Dictionary = {}
	for e2_v: Variant in kept:
		if typeof(e2_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var e2: Dictionary = e2_v as Dictionary
		occ[_occ_key(e2)] = true
	var cyno_ids: Array = _flagship_test_cyno_ids()
	var capital_ids: Array = _flagship_test_capital_ids()
	if cyno_ids.is_empty() or capital_ids.size() < 3:
		out["ships"] = kept
		return out
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var cyno_id: int = TypedVariant.as_int(cyno_ids[rng.randi_range(0, cyno_ids.size() - 1)], 0)
	var cyno_cell: Vector2i = _first_free_field_cell(occ, ShipUnit.TEAM_AI)
	if cyno_cell.x >= 0:
		var cyno_entry: Dictionary = {
			"ship_id": cyno_id,
			"star": 1,
			"team": ShipUnit.TEAM_AI,
			"slot_type": "field",
			"x": cyno_cell.x,
			"z": cyno_cell.y,
			## AI covert cyno sits on the player half.
			"field_side_team": ShipUnit.TEAM_PLAYER,
		}
		kept.append(cyno_entry)
		occ[_occ_key(cyno_entry)] = true
	var pool: Array = capital_ids.duplicate()
	## Shuffle pick 3 unique capitals into AI hangar.
	for _i: int in range(mini(3, pool.size())):
		var pick_i: int = rng.randi_range(0, pool.size() - 1)
		var cap_id: int = TypedVariant.as_int(pool[pick_i], 0)
		pool.remove_at(pick_i)
		var hang: Vector2i = _first_free_hangar_cell(occ, ShipUnit.TEAM_AI)
		if hang.x < 0:
			push_warning("MatchSave flagship-test inject: AI hangar full; placed %d/3 capitals" % _i)
			break
		var cap_entry: Dictionary = {
			"ship_id": cap_id,
			"star": 1,
			"team": ShipUnit.TEAM_AI,
			"slot_type": "hangar",
			"x": hang.x,
			"z": hang.y,
			"field_side_team": ShipUnit.TEAM_AI,
		}
		kept.append(cap_entry)
		occ[_occ_key(cap_entry)] = true
	out["ships"] = kept
	return out


static func _occ_key(e: Dictionary) -> String:
	return "%d:%s:%d:%d" % [
		TypedVariant.as_int(e.get("team", -1), -1),
		str(e.get("slot_type", "")),
		TypedVariant.as_int(e.get("x", 0), 0),
		TypedVariant.as_int(e.get("z", 0), 0),
	]


static func _flagship_test_cyno_ids() -> Array:
	var out: Array = []
	for id_any: Variant in DataStore.ship_ids():
		var sid: int = TypedVariant.as_int(id_any, 0)
		var sd: Dictionary = DataStore.get_ship(sid)
		if str(sd.get("capital_role", "")) == "covert_cyno":
			out.append(sid)
	if out.is_empty():
		out = [101, 102, 103, 104]
	return out


static func _flagship_test_capital_ids() -> Array:
	var out: Array = []
	const ROLES: Array[String] = ["dreadnought", "carrier", "force_auxiliary"]
	for id_any: Variant in DataStore.ship_ids():
		var sid: int = TypedVariant.as_int(id_any, 0)
		var sd: Dictionary = DataStore.get_ship(sid)
		if str(sd.get("capital_role", "")) in ROLES:
			out.append(sid)
	if out.is_empty():
		out = [111, 112, 113, 114, 121, 122, 123, 124, 131, 132, 133, 134]
	return out


static func _first_free_field_cell(occ: Dictionary, team: int) -> Vector2i:
	var fw: int = TypedVariant.as_int(DataStore.board.get("field_width", 12), 12)
	var fh: int = TypedVariant.as_int(DataStore.board.get("field_height", 6), 6)
	## Prefer mid-line corners (cyno testing posture).
	var preferred: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(fw - 1, 0), Vector2i(0, fh - 1), Vector2i(fw - 1, fh - 1),
	]
	for c: Vector2i in preferred:
		var probe: Dictionary = {"team": team, "slot_type": "field", "x": c.x, "z": c.y}
		if not occ.has(_occ_key(probe)):
			return c
	for z: int in range(fh):
		for x: int in range(fw):
			var probe2: Dictionary = {"team": team, "slot_type": "field", "x": x, "z": z}
			if not occ.has(_occ_key(probe2)):
				return Vector2i(x, z)
	return Vector2i(-1, -1)


static func _first_free_hangar_cell(occ: Dictionary, team: int) -> Vector2i:
	var hw: int = TypedVariant.as_int(DataStore.board.get("hangar_width", 15), 15)
	var hh: int = TypedVariant.as_int(DataStore.board.get("hangar_height", 1), 1)
	for z: int in range(hh):
		for x: int in range(hw):
			var probe: Dictionary = {"team": team, "slot_type": "hangar", "x": x, "z": z}
			if not occ.has(_occ_key(probe)):
				return Vector2i(x, z)
	return Vector2i(-1, -1)

static func list_slots() -> Array:
	_ensure_bundled_flagship_test()
	_ensure_slots_seeded_from_last()
	var idx: Dictionary = _read_json(SLOTS_INDEX_PATH)
	return TypedVariant.as_array(idx.get("slots", []))


## Write a new named archive slot (does not overwrite 旗舰测试).
## Returns {ok, id, path, name} or {ok:false, reason}.
static func save_as_named_slot(display_name: String, mc: MatchController, board: BoardController, ai: AiController) -> Dictionary:
	if mc == null or board == null:
		return {"ok": false, "reason": "no_match"}
	if mc.mode == "nullsec":
		## Hidden in the menu already; hard gate here so no other caller can slip a
		## multiplayer round into a slot (MATCH_FLOW §5.0b 负安多人局不入存档).
		return {"ok": false, "reason": "nullsec"}
	var name: String = display_name.strip_edges()
	if name == "":
		name = "存档 %s" % Time.get_datetime_string_from_system(true, true).replace("T", " ")
	if name == FLAGSHIP_TEST_NAME or name.to_lower() == FLAGSHIP_TEST_ID:
		name = "%s · 手动" % name
	if board.has_method("recall_cyno_entry_ships_to_hangar"):
		board.recall_cyno_entry_ships_to_hangar()
	var data: Dictionary = _build_save_dict(mc, board, ai)
	DirAccess.make_dir_recursive_absolute("user://save")
	var stamp: int = int(Time.get_unix_time_from_system())
	var slot_id: String = "manual_%d" % stamp
	var path: String = "user://save/slot_%s.json" % slot_id
	if not _write_json(path, data):
		return {"ok": false, "reason": "write_failed"}
	## Keep last_match in sync so 「继续上次」also reflects this snapshot.
	_write_json(SAVE_PATH, data)
	_seed_flagship_test_slot_if_missing(data)
	_upsert_slot_index(slot_id, name, path)
	_log_save_census(data)
	return {"ok": true, "id": slot_id, "path": path, "name": name}


static func _upsert_slot_index(slot_id: String, display_name: String, path: String) -> void:
	var idx: Dictionary = _read_json(SLOTS_INDEX_PATH)
	var slots: Array = TypedVariant.as_array(idx.get("slots", []))
	var filtered: Array = []
	for s_v: Variant in slots:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var s_dict: Dictionary = s_v as Dictionary
		if str(s_dict.get("id", "")) == slot_id:
			continue
		filtered.append(s_dict)
	## Keep 旗舰测试 first if present.
	var flagship: Dictionary = {}
	var rest: Array = []
	for s_v: Variant in filtered:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var s_dict: Dictionary = s_v as Dictionary
		if str(s_dict.get("id", "")) == FLAGSHIP_TEST_ID:
			flagship = s_dict
		else:
			rest.append(s_dict)
	rest.push_front({
		"id": slot_id,
		"name": display_name,
		"path": path,
		"updated_at": Time.get_datetime_string_from_system(true, true),
	})
	var out: Array = []
	if not flagship.is_empty():
		out.append(flagship)
	out.append_array(rest)
	_write_json(SLOTS_INDEX_PATH, {"slots": out})


## Rename display name only (id/path unchanged). Returns {ok, name} or {ok:false, reason}.
static func rename_slot(slot_id: String, new_name: String) -> Dictionary:
	slot_id = slot_id.strip_edges()
	var name: String = new_name.strip_edges()
	if slot_id == "" or name == "":
		return {"ok": false, "reason": "empty"}
	var idx: Dictionary = _read_json(SLOTS_INDEX_PATH)
	var slots: Array = TypedVariant.as_array(idx.get("slots", []))
	var found: bool = false
	for i: int in range(slots.size()):
		if typeof(slots[i]) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var e: Dictionary = slots[i] as Dictionary
		if str(e.get("id", "")) != slot_id:
			continue
		e["name"] = name
		e["updated_at"] = Time.get_datetime_string_from_system(true, true)
		slots[i] = e
		found = true
		break
	if not found:
		## Allow renaming a synthetic fallback entry by ensuring index exists.
		if slot_id == FLAGSHIP_TEST_ID and FileAccess.file_exists(FLAGSHIP_TEST_PATH):
			_ensure_flagship_index_entry()
			return rename_slot(slot_id, name)
		return {"ok": false, "reason": "not_found"}
	_write_json(SLOTS_INDEX_PATH, {"slots": slots})
	return {"ok": true, "name": name}


## Delete slot file + index entry. Does not delete last_match.json unless path equals it.
## Returns {ok:true} or {ok:false, reason}.
static func delete_slot(slot_id: String) -> Dictionary:
	slot_id = slot_id.strip_edges()
	if slot_id == "":
		return {"ok": false, "reason": "empty"}
	var entry: Dictionary = _find_slot(slot_id)
	var path: String = str(entry.get("path", ""))
	if path == "" and slot_id == FLAGSHIP_TEST_ID:
		path = FLAGSHIP_TEST_PATH
	if path != "" and path != SAVE_PATH and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var idx: Dictionary = _read_json(SLOTS_INDEX_PATH)
	var slots: Array = TypedVariant.as_array(idx.get("slots", []))
	var filtered: Array = []
	var removed: bool = false
	for s_v: Variant in slots:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var s_dict: Dictionary = s_v as Dictionary
		if str(s_dict.get("id", "")) == slot_id:
			removed = true
			continue
		filtered.append(s_dict)
	if not removed and entry.is_empty() and slot_id != FLAGSHIP_TEST_ID:
		return {"ok": false, "reason": "not_found"}
	_write_json(SLOTS_INDEX_PATH, {"slots": filtered})
	return {"ok": true}

static func _build_save_dict(mc: MatchController, board: BoardController, ai: AiController) -> Dictionary:
	var ships: Array = []
	for s: ShipUnit in board.all_ships():
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
		for e_v: Variant in mc._shop.slots:
			if typeof(e_v) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var slot: Dictionary = e_v as Dictionary
			shop_slots.append({
				"ship_id": TypedVariant.as_int(slot.get("ship_id", 0), 0),
				"purchased": TypedVariant.as_bool(slot.get("purchased", false), false),
			})
	var equip_shop: Array = []
	if mc._shop != null:
		for e2_v: Variant in mc._shop.equipment_slots:
			if typeof(e2_v) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var es: Dictionary = e2_v as Dictionary
			equip_shop.append({
				"id": str(es.get("id", "")),
				"purchased": TypedVariant.as_bool(es.get("purchased", false), false),
			})
	var equip_inv: Array = []
	if mc.has_method("ensure_equipment_inventory_size"):
		mc.ensure_equipment_inventory_size()
		for id_any: Variant in mc.equipment_inventory:
			equip_inv.append(str(id_any))
	var mode_out: String = normalize_solo_mode(mc.mode)
	if mode_out == "":
		## Never persist blank/garbage as endless — default dual-citadel versus.
		mode_out = "versus" if str(mc.mode) != "nullsec" else "nullsec"
	return {
		"save_version": SAVE_VERSION,
		"mode": mode_out,
		"battle_game_stage_count": mc.battle_game_stage_count,
		"round_phase_value": mc.round_phase_value,
		"battle_phase_value": mc.battle_phase_value,
		"player": {
			"gold": mc.player_gold,
			"hp": mc.player_hp,
			"max_hp": mc.player_max_hp,
			"level": mc.player_level,
			"exp": mc.player_exp,
			"up_level_demand": MatchController.exp_demand_for_level(mc.player_level),
			"win_streak": mc.win_streak,
			"loss_streak": mc.loss_streak,
			"shop_locked": mc.shop_locked,
			"shop_slots": shop_slots,
			"equipment_shop_slots": equip_shop,
			"equipment_inventory": equip_inv,
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
	var n: int = 0
	for s_v: Variant in TypedVariant.as_array(data.get("ships", [])):
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var s_dict: Dictionary = s_v as Dictionary
		if TypedVariant.as_int(s_dict.get("team", -1), -1) == team:
			n += 1
	return n


static func _ensure_flagship_index_entry() -> void:
	var idx: Dictionary = _read_json(SLOTS_INDEX_PATH)
	var slots: Array = TypedVariant.as_array(idx.get("slots", []))
	for s_v: Variant in slots:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var s_dict: Dictionary = s_v as Dictionary
		if str(s_dict.get("id", "")) == FLAGSHIP_TEST_ID:
			return
	var filtered: Array = []
	for s_v: Variant in slots:
		if typeof(s_v) == TYPE_DICTIONARY:
			@warning_ignore("unsafe_cast")
			filtered.append(s_v as Dictionary)
	filtered.push_front({
		"id": FLAGSHIP_TEST_ID,
		"name": FLAGSHIP_TEST_NAME,
		"path": FLAGSHIP_TEST_PATH,
		"updated_at": Time.get_datetime_string_from_system(true, true),
	})
	_write_json(SLOTS_INDEX_PATH, {"slots": filtered})


static func _write_flagship_index_entry_fresh() -> void:
	## Called only when the slot file itself is newly written.
	var idx: Dictionary = _read_json(SLOTS_INDEX_PATH)
	var slots: Array = TypedVariant.as_array(idx.get("slots", []))
	var filtered: Array = []
	for s_v: Variant in slots:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var s_dict: Dictionary = s_v as Dictionary
		if str(s_dict.get("id", "")) == FLAGSHIP_TEST_ID:
			continue
		filtered.append(s_dict)
	filtered.push_front({
		"id": FLAGSHIP_TEST_ID,
		"name": FLAGSHIP_TEST_NAME,
		"path": FLAGSHIP_TEST_PATH,
		"updated_at": Time.get_datetime_string_from_system(true, true),
	})
	_write_json(SLOTS_INDEX_PATH, {"slots": filtered})


static func _ensure_bundled_flagship_test() -> void:
	## Fresh installs / packaged shells have empty user:// — seed 旗舰测试 from content.
	if FileAccess.file_exists(FLAGSHIP_TEST_PATH):
		_repair_flagship_test_mode_if_needed()
		_ensure_flagship_index_entry()
		return
	if not FileAccess.file_exists(BUNDLED_FLAGSHIP_TEST_PATH):
		return
	var src: FileAccess = FileAccess.open(BUNDLED_FLAGSHIP_TEST_PATH, FileAccess.READ)
	if src == null:
		return
	var text: String = src.get_as_text()
	src.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = TypedVariant.as_dict(parsed)
	if data.is_empty() or _count_team_ships(data, 0) <= 0:
		return
	data["mode"] = "versus"
	DirAccess.make_dir_recursive_absolute("user://save")
	if not _write_json(FLAGSHIP_TEST_PATH, data):
		return
	_write_flagship_index_entry_fresh()


## Old seeds / first-seed-from-endless last_match left 旗舰测试 as mode=endless
## (no AI citadel on load). Archive is dual-fleet by design → force versus once.
static func _repair_flagship_test_mode_if_needed() -> void:
	var data: Dictionary = _read_json(FLAGSHIP_TEST_PATH)
	if data.is_empty():
		return
	if normalize_solo_mode(data.get("mode", "")) == "versus":
		return
	data["mode"] = "versus"
	_write_json(FLAGSHIP_TEST_PATH, data)


static func _seed_flagship_test_slot_if_missing(data: Dictionary) -> void:
	## Named slot is write-once: autosave must never refresh it after the first seed.
	## (Earlier "skip only if p0==0" still let mid-match losses / sold capitals overwrite the archive.)
	_ensure_bundled_flagship_test()
	if FileAccess.file_exists(FLAGSHIP_TEST_PATH):
		_ensure_flagship_index_entry()
		return
	if _count_team_ships(data, 0) <= 0:
		return
	if not _write_json(FLAGSHIP_TEST_PATH, data):
		return
	_write_flagship_index_entry_fresh()


static func _log_save_census(data: Dictionary) -> void:
	var diag_node: Node = SessionDiagnostics.instance()
	if diag_node == null or not (diag_node is SessionDiagnostics):
		return
	@warning_ignore("unsafe_cast")
	var diag: SessionDiagnostics = diag_node as SessionDiagnostics
	var p0: int = _count_team_ships(data, 0)
	var p1: int = _count_team_ships(data, 1)
	var ids: PackedStringArray = PackedStringArray()
	for s_v: Variant in TypedVariant.as_array(data.get("ships", [])):
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var e: Dictionary = s_v as Dictionary
		if TypedVariant.as_int(e.get("team", -1), -1) != 0:
			continue
		ids.append("%s@%s(%s,%s)" % [e.get("ship_id"), e.get("slot_type"), e.get("x"), e.get("z")])
	var player_d: Dictionary = TypedVariant.as_dict(data.get("player", {}))
	var ai_d: Dictionary = TypedVariant.as_dict(data.get("ai", {}))
	diag.log_event("save", "p0=%d p1=%d gold=%s hp=%s/%s ai_hp=%s/%s ships=[%s]" % [
		p0, p1,
		str(player_d.get("gold", "?")),
		str(player_d.get("hp", "?")),
		str(player_d.get("max_hp", "?")),
		str(ai_d.get("hp", "?")),
		str(ai_d.get("max_hp", "?")),
		",".join(ids),
	])

static func _ensure_slots_seeded_from_last() -> void:
	## If last_match exists but no slots yet, promote it as 旗舰测试.
	if not exists():
		return
	var idx: Dictionary = _read_json(SLOTS_INDEX_PATH)
	var slots: Array = TypedVariant.as_array(idx.get("slots", []))
	if not slots.is_empty():
		return
	var data: Dictionary = load_dict()
	if data.is_empty():
		return
	_seed_flagship_test_slot_if_missing(data)

static func _find_slot(slot_id: String) -> Dictionary:
	for s_v: Variant in list_slots():
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var s: Dictionary = s_v as Dictionary
		if str(s.get("id", "")) == slot_id:
			return s
	return {}

static func _write_json(path: String, data: Dictionary) -> bool:
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
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
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return TypedVariant.as_dict(parsed)
