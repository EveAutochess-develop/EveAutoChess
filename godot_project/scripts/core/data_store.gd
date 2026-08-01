extends Node
## Loads all data/*.json — single source for bricks (no magic numbers in gameplay).
## Prefers user://content_runtime/data (D-EAC-34 semi-expose) over res://data (PCK).

const _ContentRuntimeData := preload("res://scripts/core/content_runtime_data.gd")

var match_flow: Dictionary = {}
var economy: Dictionary = {}
var board: Dictionary = {}
var combat: Dictionary = {}
var ai: Dictionary = {}
var visual: Dictionary = {}
var weapon_fx: Dictionary = {}
var visual_meshes: Dictionary = {}  # ships: { "1": "res://..." }
var ship_textures: Dictionary = {}  # ships: { "1": "res://..._d.dds" }
var ship_portraits: Dictionary = {}  # ships: { "1": "res://.../portraits/{key}.png" }
var ships: Dictionary = {}  # id(int) -> dict
## id(int) -> relative json path ("ships/1.json") so the dev editor writes back the right file.
var ship_sources: Dictionary = {}
## SEMI_ASYNC_NETPLAY §3.7: host ship table applied in-memory for the duration of a net match.
var host_ships_override: Dictionary = {}
var fetters: Dictionary = {}  # id(str) -> dict
## Autochess representative kits — UI_AND_SHELL §2.5.1 / SHIP_DATA_FULL Sheet「装备」.
var modules: Dictionary = {}  # type_id(int) -> dict
var content_version: String = "local"

func _ready() -> void:
	reload_all()

func reload_all() -> void:
	var seed_res: Dictionary = _ContentRuntimeData.ensure_seeded()
	if int(seed_res.get("wrote", 0)) > 0 or int(seed_res.get("pruned", 0)) > 0:
		print("[DataStore] content_runtime/data seeded wrote=%s skipped=%s pruned=%s" % [
			seed_res.get("wrote", 0), seed_res.get("skipped", 0), seed_res.get("pruned", 0)])
	match_flow = _load_balance("match_flow.json")
	economy = _load_balance("economy.json")
	board = _load_balance("board.json")
	combat = _load_balance("combat.json")
	ai = _load_balance("ai.json")
	visual = _load_balance("visual.json")
	weapon_fx = _load_balance("weapon_fx.json")
	## Portrait/mesh maps stay PCK-only (not semi-exposed).
	visual_meshes = _load_json_res("res://data/visual_meshes.json")
	ship_textures = _load_json_res("res://data/ship_textures.json")
	ship_portraits = _load_json_res("res://data/ship_portraits.json")
	ships.clear()
	ship_sources.clear()
	fetters.clear()
	modules.clear()
	_load_dir_ships("ships")
	_load_dir_ships("unmanned_units")
	_load_dir_fetters("fetters")
	modules = _load_equipment_table("equipment/modules.json")
	## A live host override outranks whatever is on this client's disk.
	if not host_ships_override.is_empty():
		_apply_ships_table(host_ships_override)
	ShipLook.clear_caches()

func _load_balance(file_name: String) -> Dictionary:
	return _ContentRuntimeData.load_json_prefer_runtime("balance".path_join(file_name))

func ship_mesh_path(ship_id: int) -> String:
	var m: Dictionary = visual_meshes.get("ships", {})
	return str(m.get(str(ship_id), ""))

func ship_diffuse_path(ship_id: int) -> String:
	var m: Dictionary = ship_textures.get("ships", {})
	return str(m.get(str(ship_id), ""))

func ship_portrait_path(ship_id: int) -> String:
	var m: Dictionary = ship_portraits.get("ships", {})
	var mapped := str(m.get(str(ship_id), ""))
	if mapped != "":
		return mapped
	var s := get_ship(ship_id)
	return str(s.get("portrait", ""))

func _res_file_ok(path: String) -> bool:
	if path == "":
		return false
	if ResourceLoader.exists(path):
		return true
	var abs_path := ProjectSettings.globalize_path(path)
	return abs_path != "" and FileAccess.file_exists(abs_path)

func resolve_model_bundle(model_key: String) -> Dictionary:
	## §0 drop-in pack: assets/models/ships/{model_key}/{model.glb,albedo.png,normal.png,pmwo.png,rg.png,reduction.png}
	var out := {"mesh": "", "albedo": "", "normal": "", "pmwo": "", "rg": "", "reduction": ""}
	if model_key == "":
		return out
	var root := "res://assets/models/ships/%s" % model_key
	var mesh := root.path_join("model.glb")
	if _res_file_ok(mesh):
		out["mesh"] = mesh
	for albedo_name in ["albedo.png", "diffuse.png", "albedo.jpg"]:
		var ap := root.path_join(albedo_name)
		if _res_file_ok(ap):
			out["albedo"] = ap
			break
	for normal_name in ["normal.png", "nrm.png"]:
		var np := root.path_join(normal_name)
		if _res_file_ok(np):
			out["normal"] = np
			break
	for extra_name in ["pmwo.png", "rg.png", "reduction.png"]:
		var ep := root.path_join(extra_name)
		if _res_file_ok(ep):
			out[extra_name.get_basename()] = ep
	return out

func ship_mesh_path_resolved(ship_id: int) -> String:
	var path := ship_mesh_path(ship_id)
	if path != "" and _res_file_ok(path):
		return path
	var ship := get_ship(ship_id)
	var key := str(ship.get("model_key", ""))
	var bundle := resolve_model_bundle(key)
	return str(bundle.get("mesh", ""))

func _load_json_res(path: String) -> Dictionary:
	## Prefer ResourceLoader.exists — FileAccess.file_exists can miss mounted PCK paths on Android.
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		push_warning("DataStore missing: " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			text = f.get_as_text()
	var data = JSON.parse_string(text)
	return data if typeof(data) == TYPE_DICTIONARY else {}

func _collect_json_names(rel_dir: String) -> PackedStringArray:
	var names: Dictionary = {}
	for root in [_ContentRuntimeData.runtime_path(rel_dir), _ContentRuntimeData.res_path(rel_dir)]:
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if not dir.current_is_dir() and fn.ends_with(".json"):
				names[fn] = true
			fn = dir.get_next()
	var out: PackedStringArray = PackedStringArray(names.keys())
	out.sort()
	return out

func _load_dir_ships(rel_dir: String) -> void:
	for fn in _collect_json_names(rel_dir):
		var rel := rel_dir.path_join(fn)
		var d := _ContentRuntimeData.load_json_prefer_runtime(rel)
		if d.has("id"):
			ships[int(d["id"])] = d
			ship_sources[int(d["id"])] = rel

func _load_dir_fetters(rel_dir: String) -> void:
	for fn in _collect_json_names(rel_dir):
		var d := _ContentRuntimeData.load_json_prefer_runtime(rel_dir.path_join(fn))
		if d.has("id"):
			fetters[str(d["id"])] = d

func ship_ids() -> Array:
	## Playable shop/AI pool — exclude unmanned templates.
	var ids: Array = []
	for k in ships.keys():
		var sid := int(k)
		var s: Dictionary = ships[k]
		if bool(s.get("is_unmanned", false)):
			continue
		ids.append(sid)
	ids.sort()
	return ids

func get_ship(id: int) -> Dictionary:
	return ships.get(id, {})

func get_star(ship_id: int, star: int) -> Dictionary:
	## Raw stars[] row (editor / disk). Prefer get_star_resolved for combat & UI.
	var s := get_ship(ship_id)
	var stars = s.get("stars", [])
	if star < 1 or star > stars.size():
		return {}
	return stars[star - 1]

func get_star_resolved(ship_id: int, star: int) -> Dictionary:
	## Manned attack overlaid from hi/attack slots × equipment when resolvable.
	var s := get_ship(ship_id)
	var raw := get_star(ship_id, star)
	if raw.is_empty() or s.is_empty():
		return raw
	return ShipWeaponDerive.merge_into_star(s, raw, star)

func ship_has_group(ship_id: int, tag: String) -> bool:
	var s := get_ship(ship_id)
	var groups = s.get("ship_groups", [])
	return tag in groups

## ---- Ship table transport / editing (SEMI_ASYNC_NETPLAY §3.7 · UI_AND_SHELL §2.5.1) ----

## Reserved key inside the ships payload carrying the kits manned attack derives from.
const EQUIPMENT_PAYLOAD_KEY := "__equipment__"

## Whole playable table keyed by id string — what the host ships to guests on match entry.
## Manned DPH = slots × kit, so the equipment tables travel with the roster or the two
## sides would simulate different damage (SHIP_STATS_V2 §2.2).
func export_ships_table() -> Dictionary:
	var out: Dictionary = {}
	for k in ships.keys():
		out[str(int(k))] = (ships[k] as Dictionary).duplicate(true)
	out[EQUIPMENT_PAYLOAD_KEY] = {
		"modules": _export_equipment_table(modules),
	}
	return out

static func _export_equipment_table(table: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in table.keys():
		out[str(int(k))] = (table[k] as Dictionary).duplicate(true)
	return out

## Stable digest of the ship table; compared against the host's in the lobby.
func ships_table_hash() -> String:
	return table_hash(export_ships_table())

static func table_hash(table: Dictionary) -> String:
	return _canonical(table).sha256_text()

## Key-sorted, float-normalized serialization so two machines agree byte for byte.
static func _canonical(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys: Array = d.keys()
			keys.sort_custom(func(a, b): return str(a) < str(b))
			var parts := PackedStringArray()
			for k in keys:
				parts.append("%s:%s" % [str(k), _canonical(d[k])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var items := PackedStringArray()
			for e in (v as Array):
				items.append(_canonical(e))
			return "[%s]" % ",".join(items)
		TYPE_FLOAT:
			return "%.6f" % float(v)
		TYPE_BOOL:
			return "true" if bool(v) else "false"
		TYPE_NIL:
			return "null"
		_:
			return str(v)

## Guest side: host table wins for this match. Memory only — never touches this client's disk.
func apply_host_ships_override(table: Dictionary) -> bool:
	if table.is_empty():
		return false
	host_ships_override = table.duplicate(true)
	var applied := _apply_ships_table(host_ships_override)
	ShipLook.clear_caches()
	return applied

func clear_host_ships_override() -> void:
	if host_ships_override.is_empty():
		return
	host_ships_override.clear()
	reload_all()

func _apply_ships_table(table: Dictionary) -> bool:
	var merged: Dictionary = {}
	for k in table.keys():
		if typeof(table[k]) != TYPE_DICTIONARY:
			continue
		if str(k) == EQUIPMENT_PAYLOAD_KEY:
			continue
		var d: Dictionary = table[k]
		var sid := int(d.get("id", str(k).to_int()))
		merged[sid] = d.duplicate(true)
	if merged.is_empty():
		return false
	ships = merged
	var kits: Variant = table.get(EQUIPMENT_PAYLOAD_KEY, {})
	if typeof(kits) == TYPE_DICTIONARY:
		var kit_dict: Dictionary = kits
		if typeof(kit_dict.get("modules")) == TYPE_DICTIONARY:
			modules = _keyed_by_type_id(kit_dict["modules"])
	return true

static func _keyed_by_type_id(table: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in table.keys():
		if typeof(table[k]) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = table[k]
		out[int(d.get("typeID", str(k).to_int()))] = d.duplicate(true)
	return out

## Dev ship editor write-back. Editor runs reseed with force=true, so the repo baseline
## has to be written too or the edit would be reverted on the next reload.
func save_ship_json(ship_id: int, data: Dictionary) -> bool:
	var rel := str(ship_sources.get(ship_id, "ships/%d.json" % ship_id))
	var text := JSON.stringify(data, "  ")
	var ok := _write_text(_ContentRuntimeData.runtime_path(rel), text)
	if OS.has_feature("editor"):
		ok = _write_text(_ContentRuntimeData.res_path(rel), text) and ok
	return ok

func get_module(type_id: int) -> Dictionary:
	return modules.get(type_id, {})

## `table` is type_id(int) -> dict. Writes equipment/modules.json.
func save_equipment_table(table: Dictionary) -> bool:
	var rel := "equipment".path_join("modules.json")
	var serial: Dictionary = {}
	var keys: Array = table.keys()
	keys.sort()
	for k in keys:
		var tid := int(k)
		var d: Dictionary = table[k]
		if d.is_empty():
			continue
		var copy: Dictionary = d.duplicate(true)
		if not copy.has("typeID"):
			copy["typeID"] = tid
		serial[str(tid)] = copy
	var text := JSON.stringify(serial, "  ")
	var ok := _write_text(_ContentRuntimeData.runtime_path(rel), text)
	if OS.has_feature("editor"):
		ok = _write_text(_ContentRuntimeData.res_path(rel), text) and ok
	return ok


func _load_equipment_table(rel: String) -> Dictionary:
	var raw := _ContentRuntimeData.load_json_prefer_runtime(rel)
	var out: Dictionary = {}
	for k in raw.keys():
		if typeof(raw[k]) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = raw[k]
		var tid := int(d.get("typeID", str(k).to_int()))
		out[tid] = d.duplicate(true)
	return out

func _write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[DataStore] cannot write %s" % path)
		return false
	f.store_string(text)
	f.close()
	return true
