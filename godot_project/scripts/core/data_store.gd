extends Node
## Loads all data/*.json — single source for bricks (no magic numbers in gameplay).
## Prefers user://content_runtime/data (D-EAC-34 semi-expose) over res://data (PCK).


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
## Function bucket (副装备) — id(str) -> dict from equipment/function_modules.json items.
var function_modules: Dictionary = {}
var content_version: String = "local"

func _ready() -> void:
	reload_all()

func reload_all() -> void:
	var seed_res: Dictionary = ContentRuntimeData.ensure_seeded()
	if TypedVariant.as_int(seed_res.get("wrote", 0)) > 0 or TypedVariant.as_int(seed_res.get("pruned", 0)) > 0:
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
	## Nullsec guests/host already hold opening ships in memory — skip disk ship scan + re-hash.
	var keep_host_ships: bool = not host_ships_override.is_empty()
	if keep_host_ships:
		fetters.clear()
		modules.clear()
		function_modules.clear()
		_load_dir_fetters("fetters")
		modules = _load_equipment_table("equipment/modules.json")
		function_modules = _load_function_modules_table("equipment/function_modules.json")
		_apply_ships_table(host_ships_override)
		ShipLook.clear_caches()
		print("[DataStore] reload_all: kept host_ships_override (skipped disk ships scan)")
		return
	ships.clear()
	ship_sources.clear()
	fetters.clear()
	modules.clear()
	function_modules.clear()
	_load_dir_ships("ships")
	_load_dir_ships("unmanned_units")
	_load_dir_fetters("fetters")
	modules = _load_equipment_table("equipment/modules.json")
	function_modules = _load_function_modules_table("equipment/function_modules.json")
	## A live host override outranks whatever is on this client's disk.
	if not host_ships_override.is_empty():
		_apply_ships_table(host_ships_override)
	ShipLook.clear_caches()

func _load_balance(file_name: String) -> Dictionary:
	return ContentRuntimeData.load_json_prefer_runtime("balance".path_join(file_name))

func ship_mesh_path(ship_id: int) -> String:
	var m: Dictionary = visual_meshes.get("ships", {})
	return str(m.get(str(ship_id), ""))

func ship_diffuse_path(ship_id: int) -> String:
	var m: Dictionary = ship_textures.get("ships", {})
	return str(m.get(str(ship_id), ""))

func ship_portrait_path(ship_id: int) -> String:
	var m: Dictionary = ship_portraits.get("ships", {})
	var mapped: String = str(m.get(str(ship_id), ""))
	if mapped != "":
		return mapped
	var s: Dictionary = get_ship(ship_id)
	return str(s.get("portrait", ""))

func _res_file_ok(path: String) -> bool:
	if path == "":
		return false
	if ResourceLoader.exists(path):
		return true
	var abs_path: String = ProjectSettings.globalize_path(path)
	return abs_path != "" and FileAccess.file_exists(abs_path)

func resolve_model_bundle(model_key: String) -> Dictionary:
	## §0 drop-in pack: assets/models/ships/{model_key}/{model.glb,albedo.png,normal.png,pmwo.png,rg.png,reduction.png}
	var out: Dictionary = {"mesh": "", "albedo": "", "normal": "", "pmwo": "", "rg": "", "reduction": ""}
	if model_key == "":
		return out
	var root: String = "res://assets/models/ships/%s" % model_key
	var mesh: String = root.path_join("model.glb")
	if _res_file_ok(mesh):
		out["mesh"] = mesh
	for albedo_name: String in ["albedo.png", "diffuse.png", "albedo.jpg"]:
		var ap: String = root.path_join(albedo_name)
		if _res_file_ok(ap):
			out["albedo"] = ap
			break
	for normal_name: String in ["normal.png", "nrm.png"]:
		var np: String = root.path_join(normal_name)
		if _res_file_ok(np):
			out["normal"] = np
			break
	for extra_name: String in ["pmwo.png", "rg.png", "reduction.png"]:
		var ep: String = root.path_join(extra_name)
		if _res_file_ok(ep):
			out[extra_name.get_basename()] = ep
	return out

func ship_mesh_path_resolved(ship_id: int) -> String:
	var path: String = ship_mesh_path(ship_id)
	if path != "" and _res_file_ok(path):
		return path
	var ship: Dictionary = get_ship(ship_id)
	var key: String = str(ship.get("model_key", ""))
	var bundle: Dictionary = resolve_model_bundle(key)
	return str(bundle.get("mesh", ""))

func _load_json_res(path: String) -> Dictionary:
	## Prefer ResourceLoader.exists — FileAccess.file_exists can miss mounted PCK paths on Android.
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		push_warning("DataStore missing: " + path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f:
			text = f.get_as_text()
	var data: Variant = JSON.parse_string(text)
	return TypedVariant.as_dict(data)

func _collect_json_names(rel_dir: String) -> PackedStringArray:
	var names: Dictionary = {}
	for root: String in [ContentRuntimeData.runtime_path(rel_dir), ContentRuntimeData.res_path(rel_dir)]:
		var dir: DirAccess = DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fn: String = dir.get_next()
		while fn != "":
			if not dir.current_is_dir() and fn.ends_with(".json"):
				names[fn] = true
			fn = dir.get_next()
	var out: PackedStringArray = PackedStringArray(names.keys())
	out.sort()
	return out

func _load_dir_ships(rel_dir: String) -> void:
	for fn: String in _collect_json_names(rel_dir):
		var rel: String = rel_dir.path_join(fn)
		var d: Dictionary = ContentRuntimeData.load_json_prefer_runtime(rel)
		if d.has("id"):
			ships[TypedVariant.as_int(d["id"])] = d
			ship_sources[TypedVariant.as_int(d["id"])] = rel

func _load_dir_fetters(rel_dir: String) -> void:
	for fn: String in _collect_json_names(rel_dir):
		var d: Dictionary = ContentRuntimeData.load_json_prefer_runtime(rel_dir.path_join(fn))
		if d.has("id"):
			fetters[str(d["id"])] = d

func ship_ids() -> Array:
	## Playable shop/AI pool — exclude unmanned templates.
	var ids: Array = []
	for k: Variant in ships.keys():
		var sid: int = TypedVariant.as_int(k)
		var s: Dictionary = ships[k]
		if TypedVariant.as_bool(s.get("is_unmanned", false)):
			continue
		ids.append(sid)
	ids.sort()
	return ids

func get_ship(id: int) -> Dictionary:
	return ships.get(id, {})

func get_star(ship_id: int, star: int) -> Dictionary:
	## Raw stars[] row (editor / disk). Prefer get_star_resolved for combat & UI.
	var s: Dictionary = get_ship(ship_id)
	var stars: Array = TypedVariant.as_array(s.get("stars", []))
	if stars.is_empty() or star < 1:
		return {}
	if star <= stars.size():
		return stars[star - 1]
	## Unmanned tables often ship only ★1; mother star 2/3 must still resolve (SHIP_STATS_V2 §2.5).
	if TypedVariant.as_bool(s.get("is_unmanned", false)) and typeof(stars[0]) == TYPE_DICTIONARY:
		var star1: Dictionary = stars[0]
		return _synthesize_unmanned_star(star1, star)
	return {}

func get_star_resolved(ship_id: int, star: int) -> Dictionary:
	## Manned attack overlaid from hi/attack slots × equipment when resolvable.
	var s: Dictionary = get_ship(ship_id)
	var raw: Dictionary = get_star(ship_id, star)
	if raw.is_empty() or s.is_empty():
		return raw
	return ShipWeaponDerive.merge_into_star(s, raw, star)


func _synthesize_unmanned_star(star1: Dictionary, star: int) -> Dictionary:
	## HP + damage ×k from ★1; repair / tracking / range unchanged (speed is ship-root).
	var row: Dictionary = star1.duplicate(true)
	var mul: float = float(maxi(star, 1))
	if mul <= 1.001:
		return row
	for k: String in ["shield_hp", "armor_hp", "structure_hp"]:
		if row.has(k):
			row[k] = TypedVariant.as_float(row[k]) * mul
	var dmg: Variant = row.get("damage", {})
	if typeof(dmg) == TYPE_DICTIONARY:
		var nd: Dictionary = {}
		var damage: Dictionary = dmg
		for dk: Variant in damage.keys():
			nd[dk] = TypedVariant.as_float(damage[dk]) * mul
		row["damage"] = nd
	return row

func ship_has_group(ship_id: int, tag: String) -> bool:
	var s: Dictionary = get_ship(ship_id)
	var groups: Array = TypedVariant.as_array(s.get("ship_groups", []))
	return tag in groups

## ---- Ship table transport / editing (SEMI_ASYNC_NETPLAY §3.7 · UI_AND_SHELL §2.5.1) ----

## Reserved key inside the ships payload carrying the kits manned attack derives from.
const EQUIPMENT_PAYLOAD_KEY: String = "__equipment__"

## Whole playable table keyed by id string — what the host ships to guests on match entry.
## Manned DPH = slots × kit, so the equipment tables travel with the roster or the two
## sides would simulate different damage (SHIP_STATS_V2 §2.2).
func export_ships_table() -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in ships.keys():
		var ship: Dictionary = TypedVariant.as_dict(ships[k])
		out[str(TypedVariant.as_int(k))] = ship.duplicate(true)
	out[EQUIPMENT_PAYLOAD_KEY] = {
		"modules": _export_equipment_table(modules),
		"function_modules": _export_function_modules_table(function_modules),
	}
	return out

static func _export_equipment_table(table: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in table.keys():
		var entry: Dictionary = TypedVariant.as_dict(table[k])
		out[str(TypedVariant.as_int(k))] = entry.duplicate(true)
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
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			var parts: PackedStringArray = PackedStringArray()
			for k: Variant in keys:
				parts.append("%s:%s" % [str(k), _canonical(d[k])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var items: PackedStringArray = PackedStringArray()
			var array_value: Array = v
			for e: Variant in array_value:
				items.append(_canonical(e))
			return "[%s]" % ",".join(items)
		TYPE_FLOAT:
			return "%.6f" % TypedVariant.as_float(v)
		TYPE_BOOL:
			return "true" if TypedVariant.as_bool(v) else "false"
		TYPE_NIL:
			return "null"
		_:
			return str(v)

## Guest side: host table wins for this match. Memory only — never touches this client's disk.
func apply_host_ships_override(table: Dictionary) -> bool:
	if table.is_empty():
		return false
	host_ships_override = table.duplicate(true)
	var applied: bool = _apply_ships_table(host_ships_override)
	ShipLook.clear_caches()
	return applied

func clear_host_ships_override() -> void:
	if host_ships_override.is_empty():
		return
	host_ships_override.clear()
	reload_all()

func _apply_ships_table(table: Dictionary) -> bool:
	var merged: Dictionary = {}
	for k: Variant in table.keys():
		if typeof(table[k]) != TYPE_DICTIONARY:
			continue
		if str(k) == EQUIPMENT_PAYLOAD_KEY:
			continue
		var d: Dictionary = table[k]
		var sid: int = TypedVariant.as_int(d.get("id", str(k).to_int()))
		merged[sid] = d.duplicate(true)
	if merged.is_empty():
		return false
	ships = merged
	var kits: Variant = table.get(EQUIPMENT_PAYLOAD_KEY, {})
	if kits is Dictionary:
		var kit_dict: Dictionary = kits
		if kit_dict.get("modules") is Dictionary:
			modules = _keyed_by_type_id(TypedVariant.as_dict(kit_dict["modules"]))
		if kit_dict.get("function_modules") is Dictionary:
			function_modules = _keyed_by_string_id(TypedVariant.as_dict(kit_dict["function_modules"]))
	return true

static func _keyed_by_type_id(table: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in table.keys():
		if typeof(table[k]) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = table[k]
		out[TypedVariant.as_int(d.get("typeID", str(k).to_int()))] = d.duplicate(true)
	return out

## Dev ship editor write-back. Editor runs reseed with force=true, so the repo baseline
## has to be written too or the edit would be reverted on the next reload.
func save_ship_json(ship_id: int, data: Dictionary) -> bool:
	var rel: String = str(ship_sources.get(ship_id, "ships/%d.json" % ship_id))
	var text: String = JSON.stringify(data, "  ")
	var ok: bool = _write_text(ContentRuntimeData.runtime_path(rel), text)
	if OS.has_feature("editor"):
		ok = _write_text(ContentRuntimeData.res_path(rel), text) and ok
	return ok

func get_module(type_id: int) -> Dictionary:
	return modules.get(type_id, {})


func get_function_module(item_id: String) -> Dictionary:
	return function_modules.get(str(item_id), {})


## EQUIPMENT §1 — shop cost, or implant synth total (sum of material costs).
func function_module_purchase_value(item_id: String) -> int:
	var mod: Dictionary = get_function_module(item_id)
	if mod.is_empty():
		return 0
	if TypedVariant.as_bool(mod.get("implant", false)):
		var mats: Array = TypedVariant.as_array(mod.get("synth_from", null))
		if mats.size() < 2:
			return maxi(0, TypedVariant.as_int(mod.get("cost", 0)))
		var total: int = 0
		for i: int in range(2):
			var mid: String = str(mats[i]).strip_edges()
			var mat: Dictionary = get_function_module(mid)
			total += TypedVariant.as_int(mat.get("cost", 0)) if not mat.is_empty() else 0
		return total
	return maxi(0, TypedVariant.as_int(mod.get("cost", 10)))


## Same formula as ShipUnit.get_sell_price: purchase − discount, floor min.
func function_module_sell_price(item_id: String) -> int:
	var discount: int = TypedVariant.as_int(economy.get("sell_price_discount", 3))
	var floor_p: int = TypedVariant.as_int(economy.get("sell_price_min", 1))
	return maxi(floor_p, function_module_purchase_value(item_id) - discount)


func function_module_ids() -> Array:
	var out: Array = []
	for k: Variant in function_modules.keys():
		out.append(str(k))
	out.sort()
	return out


func function_module_shop_pool_ids() -> Array:
	return function_module_shop_pool_ids_for_level(1)


## EQUIPMENT §1 — size gates: S any · M≥5 · L≥10 · XL≥15 (economy.json overrides).
func function_module_shop_pool_ids_for_level(player_level: int) -> Array:
	var lvl: int = maxi(1, player_level)
	var need_m: int = TypedVariant.as_int(economy.get("equipment_shop_min_level_m", 5))
	var need_l: int = TypedVariant.as_int(economy.get("equipment_shop_min_level_l", 10))
	var need_xl: int = TypedVariant.as_int(economy.get("equipment_shop_min_level_xl", 15))
	var out: Array = []
	for id: String in function_module_ids():
		var mod: Dictionary = get_function_module(id)
		if mod.is_empty():
			continue
		if mod.has("shop_pool") and not TypedVariant.as_bool(mod.get("shop_pool", true)):
			continue
		var size: String = str(mod.get("size", "S")).strip_edges().to_upper()
		if size == "XL" or size == "CAPITAL":
			if lvl < need_xl:
				continue
		elif size == "L" or size == "LARGE":
			if lvl < need_l:
				continue
		elif size == "M" or size == "MEDIUM":
			if lvl < need_m:
				continue
		## S / empty / unknown → always eligible
		out.append(id)
	return out


## EQUIPMENT §1 shop_category (A–G). Empty = not in pity taxonomy.
func function_module_shop_category(item_id: String) -> String:
	var mod: Dictionary = get_function_module(item_id)
	if mod.is_empty():
		return ""
	return str(mod.get("shop_category", "")).strip_edges()

## `table` is type_id(int) -> dict. Writes equipment/modules.json.
func save_equipment_table(table: Dictionary) -> bool:
	var rel: String = "equipment".path_join("modules.json")
	var serial: Dictionary = {}
	var keys: Array = table.keys()
	keys.sort()
	for k: Variant in keys:
		var tid: int = TypedVariant.as_int(k)
		var d: Dictionary = table[k]
		if d.is_empty():
			continue
		var copy: Dictionary = d.duplicate(true)
		if not copy.has("typeID"):
			copy["typeID"] = tid
		serial[str(tid)] = copy
	var text: String = JSON.stringify(serial, "  ")
	var ok: bool = _write_text(ContentRuntimeData.runtime_path(rel), text)
	if OS.has_feature("editor"):
		ok = _write_text(ContentRuntimeData.res_path(rel), text) and ok
	return ok

## `table` is id(str) -> dict. Writes equipment/function_modules.json `{_meta, items}`.
func save_function_modules_table(table: Dictionary) -> bool:
	var rel: String = "equipment".path_join("function_modules.json")
	var serial: Dictionary = {}
	var keys: Array = table.keys()
	keys.sort()
	for k: Variant in keys:
		var sid: String = str(k)
		var d: Dictionary = table[k]
		if d.is_empty():
			continue
		var copy: Dictionary = d.duplicate(true)
		if not copy.has("id"):
			copy["id"] = sid
		serial[sid] = copy
	var payload: Dictionary = {
		"_meta": {
			"doc": "EQUIPMENT.md",
			"note": "function bucket; markers for first shipment forbidden",
		},
		"items": serial,
	}
	var text: String = JSON.stringify(payload, "  ")
	var ok: bool = _write_text(ContentRuntimeData.runtime_path(rel), text)
	if OS.has_feature("editor"):
		ok = _write_text(ContentRuntimeData.res_path(rel), text) and ok
	return ok

static func _export_function_modules_table(table: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in table.keys():
		var d: Dictionary = TypedVariant.as_dict(table[k])
		out[str(k)] = d.duplicate(true)
	return out

static func _keyed_by_string_id(table: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in table.keys():
		if typeof(table[k]) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = table[k]
		var sid: String = str(d.get("id", k))
		out[sid] = d.duplicate(true)
	return out

func _load_function_modules_table(rel: String) -> Dictionary:
	var raw: Dictionary = ContentRuntimeData.load_json_prefer_runtime(rel)
	var items: Variant = raw.get("items", raw)
	if items is not Dictionary:
		return {}
	var items_dict: Dictionary = items
	var out: Dictionary = {}
	for k: Variant in items_dict.keys():
		if typeof(items_dict[k]) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = items_dict[k]
		var sid: String = str(d.get("id", k))
		out[sid] = d.duplicate(true)
	return out


func _load_equipment_table(rel: String) -> Dictionary:
	var raw: Dictionary = ContentRuntimeData.load_json_prefer_runtime(rel)
	var out: Dictionary = {}
	for k: Variant in raw.keys():
		if typeof(raw[k]) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = raw[k]
		var tid: int = TypedVariant.as_int(d.get("typeID", str(k).to_int()))
		out[tid] = d.duplicate(true)
	return out

func _write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[DataStore] cannot write %s" % path)
		return false
	f.store_string(text)
	f.close()
	return true
