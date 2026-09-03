extends Node
class_name ModManager
## Content-side mod host under /root/ModManager (PCK cannot register Autoloads).
## Authority: design MODS.md · author protocol godot_project/docs/MOD_PROTOCOL.md

const NODE_NAME: StringName = &"ModManager"
const _SELF: String = "res://scripts/mod/mod_manager.gd"
const INDEX_NAME: String = "mods_index.json"
const SCHEMA_VER_MAX: int = 1
const SYNC_MAX_BYTES: int = 10 * 1024 * 1024 * 1024 ## 10 GiB — sync only
const MAX_ZIP_ENTRIES: int = 100000
const MAX_REL_PATH_LEN: int = 512
const FORBIDDEN_EXT: Array[String] = [
	"exe", "dll", "so", "dylib", "bat", "cmd", "ps1", "sh", "gd", "gdc", "cs", "js", "py", "wasm", "gdshader"
]
const SEED_ROOT: String = "res://mods_seed"

## package_name -> index entry
var index: Dictionary = {}
## Runtime merge caches (cleared on reload)
var runtime_ships: Dictionary = {} ## id(int) -> dict
var runtime_modules: Dictionary = {} ## type_id(int) -> dict
var runtime_function_modules: Dictionary = {} ## id(str|int) -> dict
var runtime_fetters: Dictionary = {} ## id(str) -> dict
var runtime_tonnage: Dictionary = {} ## ship_group -> {icon_path, ...}
var runtime_titan_picks: Dictionary = {} ## race(str) -> {race, label, icon, ship_id, fetter_id, package}
var replacements: Dictionary = {} ## from_key(str) -> to_runtime_id(int)
var disable_ship_ids: Dictionary = {} ## int id or stable key -> true
var disable_equipment_ids: Dictionary = {}
var mod_unit_dirs: Dictionary = {} ## runtime_id(int) -> absolute unit dir
var _package_fx_protocol: Dictionary = {} ## package_name -> int
## Latest enabled mod wins (by enabled_at) — MOD_PROTOCOL P2/P3.
var merged_shop_rules: Dictionary = {}
var merged_ui_overrides: Dictionary = {}
var _merged_ui_overrides_root: String = ""
var merged_prepare_radar_override: Dictionary = {}
var last_merge_warnings: PackedStringArray = PackedStringArray()
var mods_root: String = ""
## Holds instance created while root.add_child is deferred (Autoload setup race).
static var _pending: ModManager = null


static func instance() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	@warning_ignore("unsafe_cast")
	var tree: SceneTree = loop as SceneTree
	var existing: Node = tree.root.get_node_or_null(NodePath(String(NODE_NAME)))
	if existing:
		return existing
	if _pending != null and is_instance_valid(_pending):
		return _pending
	var loaded: Variant = load(_SELF)
	if not (loaded is GDScript):
		return null
	@warning_ignore("unsafe_cast")
	var scr: GDScript = loaded as GDScript
	var created: Variant = scr.new()
	if not (created is Node):
		return null
	@warning_ignore("unsafe_cast")
	var n: Node = created as Node
	n.name = String(NODE_NAME)
	## Boot before tree enter — DataStore._ready may call while root is still adding Autoloads.
	if n is ModManager:
		var mm: ModManager = n as ModManager
		mm._ensure_boot()
		_pending = mm
	tree.root.add_child.call_deferred(n)
	return n


static func get_or_null() -> ModManager:
	var n: Node = instance()
	if n is ModManager:
		return n as ModManager
	return null


## Lobby dropdown rows (official + enabled mod titan_picks). MULTIPLAYER_PVP §2.
static func titan_pick_list() -> Array:
	var mm: ModManager = get_or_null()
	if mm != null and not mm.runtime_titan_picks.is_empty():
		return ModTitanResolve.pick_list_from_registry(mm.runtime_titan_picks)
	return ModTitanResolve.pick_list_from_registry(ModTitanResolve.official_registry())


static func titan_race_keys() -> Array:
	var mm: ModManager = get_or_null()
	if mm != null and not mm.runtime_titan_picks.is_empty():
		return ModTitanResolve.race_keys_from_registry(mm.runtime_titan_picks)
	return ModTitanResolve.race_keys_from_registry(ModTitanResolve.official_registry())


static func is_titan_player_race(race: String) -> bool:
	return str(race).strip_edges().to_lower() in titan_race_keys()


static func tonnage_pity_enabled() -> bool:
	var mm: ModManager = get_or_null()
	if mm == null or mm.merged_shop_rules.is_empty():
		return true
	return not TypedVariant.as_bool(mm.merged_shop_rules.get("disable_tonnage_pity", false), false)


static func equipment_category_pity_enabled() -> bool:
	var mm: ModManager = get_or_null()
	if mm == null or mm.merged_shop_rules.is_empty():
		return true
	return not TypedVariant.as_bool(mm.merged_shop_rules.get("disable_equipment_category_pity", false), false)


static func titan_ship_id_for(race: String) -> int:
	var r: String = str(race).strip_edges().to_lower()
	var mm: ModManager = get_or_null()
	if mm != null and mm.runtime_titan_picks.has(r):
		return TypedVariant.as_int(TypedVariant.as_dict(mm.runtime_titan_picks[r]).get("ship_id", 0), 0)
	var reg: Dictionary = ModTitanResolve.official_registry()
	if reg.has(r):
		return TypedVariant.as_int(TypedVariant.as_dict(reg[r]).get("ship_id", 0), 0)
	return 0


static func titan_fetter_id_for(race: String) -> String:
	var r: String = str(race).strip_edges().to_lower()
	var mm: ModManager = get_or_null()
	if mm != null and mm.runtime_titan_picks.has(r):
		return str(TypedVariant.as_dict(mm.runtime_titan_picks[r]).get("fetter_id", "titan_%s" % r))
	var reg: Dictionary = ModTitanResolve.official_registry()
	if reg.has(r):
		return str(TypedVariant.as_dict(reg[r]).get("fetter_id", "titan_%s" % r))
	return "titan_%s" % r if r != "" else ""


func _ready() -> void:
	_ensure_boot()
	_pending = null


func _ensure_boot() -> void:
	if mods_root != "":
		return
	mods_root = resolve_mods_root()
	DirAccess.make_dir_recursive_absolute(mods_root)
	_load_index()
	_ensure_seed_mods()


func resolve_mods_root() -> String:
	## PC: prefer beside exe; mobile / fallback: user://mods
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return ProjectSettings.globalize_path("user://mods")
	var exe_dir: String = OS.get_executable_path().get_base_dir()
	var beside: String = exe_dir.path_join("mods")
	var probe: String = beside.path_join(".write_probe")
	DirAccess.make_dir_recursive_absolute(beside)
	var f: FileAccess = FileAccess.open(probe, FileAccess.WRITE)
	if f != null:
		f.store_string("ok")
		f.close()
		DirAccess.remove_absolute(probe)
		return beside
	return ProjectSettings.globalize_path("user://mods")


func index_path() -> String:
	return mods_root.path_join(INDEX_NAME)


func _load_index() -> void:
	index.clear()
	var p: String = index_path()
	if not FileAccess.file_exists(p):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	var root: Dictionary = TypedVariant.as_dict(data)
	var mods: Array = TypedVariant.as_array(root.get("mods", []))
	for m_any: Variant in mods:
		var m: Dictionary = TypedVariant.as_dict(m_any)
		var pn: String = str(m.get("package_name", "")).strip_edges()
		if pn != "":
			index[pn] = m


## Bundled seeds under res://mods_seed/<package>/ — copy once if missing; never overwrite.
func _ensure_seed_mods() -> void:
	var da: DirAccess = DirAccess.open(SEED_ROOT)
	if da == null:
		return
	var dirty: bool = false
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if fn == "." or fn == ".." or not da.current_is_dir() or fn.begins_with("."):
			fn = da.get_next()
			continue
		var seed_pkg: String = SEED_ROOT.path_join(fn)
		var mod_json_path: String = seed_pkg.path_join("mod.json")
		if not FileAccess.file_exists(mod_json_path):
			fn = da.get_next()
			continue
		var mod_json: Dictionary = _read_json_file(mod_json_path)
		var pn: String = str(mod_json.get("package_name", fn)).strip_edges()
		if pn == "":
			pn = fn
		var dest: String = package_work_dir(pn)
		if DirAccess.dir_exists_absolute(dest):
			## Already installed (player may have edited) — do not overwrite.
			if not index.has(pn):
				## Dir exists but index lost: re-register disabled without touching files.
				_index_seed_entry(pn, dest, mod_json, false)
				dirty = true
			fn = da.get_next()
			continue
		var copy_res: Dictionary = _copy_res_tree(seed_pkg, dest)
		if not TypedVariant.as_bool(copy_res.get("ok", false), false):
			_note_warn("seed copy fail %s err=%s" % [pn, str(copy_res.get("error", "?"))])
			fn = da.get_next()
			continue
		_repack_zip(pn)
		_index_seed_entry(pn, dest, mod_json, true)
		dirty = true
		print("[ModManager] seed installed package=%s enabled=false" % pn)
		fn = da.get_next()
	da.list_dir_end()
	if dirty:
		save_index()


func _index_seed_entry(pn: String, dest: String, mod_json: Dictionary, fresh_copy: bool) -> void:
	var hash_v: String = compute_tree_hash(dest)
	var zip_p: String = package_zip_path(pn)
	var zip_sha: String = ""
	var byte_size: int = 0
	if FileAccess.file_exists(zip_p):
		var zb: PackedByteArray = FileAccess.get_file_as_bytes(zip_p)
		byte_size = zb.size()
		zip_sha = "" if zb.is_empty() else _sha256_hex(zb)
	var warnings: PackedStringArray = lint_package(dest, mod_json)
	var order: int = TypedVariant.as_int(TypedVariant.as_dict(index.get(pn, {})).get("install_order", 0))
	if order < 1:
		order = _next_install_order()
	var imported: String = "res://mods_seed/%s" % pn
	if not fresh_copy:
		imported = str(TypedVariant.as_dict(index.get(pn, {})).get("imported_from", "seed"))
	var entry: Dictionary = {
		"package_name": pn,
		"version": str(mod_json.get("version", "0")),
		"display_name": str(mod_json.get("display_name", pn)),
		"author": str(mod_json.get("author", "")),
		"description": str(mod_json.get("description", "")),
		"enabled": false,
		"enabled_at": 0,
		"install_order": order,
		"content_hash": hash_v,
		"zip_sha256": zip_sha,
		"byte_size": byte_size,
		"lint_warnings": Array(warnings),
		"imported_from": imported,
		"disclaimer_ack": false,
		"last_error": "",
		"schema_ver": TypedVariant.as_int(mod_json.get("schema_ver", 1)),
		"min_content_rev": str(mod_json.get("min_content_rev", "0")),
		"platforms": TypedVariant.as_dict(mod_json.get("platforms", {"pc": true, "mobile": true})),
		"seed": true,
	}
	index[pn] = entry


## Copy res:// (or absolute) tree via FileAccess so packed PCK seeds work.
func _copy_res_tree(src: String, dest: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(dest)
	var da: DirAccess = DirAccess.open(src)
	if da == null:
		return {"ok": false, "error": "open_src"}
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if fn == "." or fn == "..":
			fn = da.get_next()
			continue
		var s: String = src.path_join(fn)
		var d: String = dest.path_join(fn)
		if da.current_is_dir():
			var sub: Dictionary = _copy_res_tree(s, d)
			if not TypedVariant.as_bool(sub.get("ok", false), false):
				da.list_dir_end()
				return sub
		else:
			DirAccess.make_dir_recursive_absolute(d.get_base_dir())
			if not FileAccess.file_exists(s):
				da.list_dir_end()
				return {"ok": false, "error": "missing_file"}
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(s)
			var out: FileAccess = FileAccess.open(d, FileAccess.WRITE)
			if out == null:
				da.list_dir_end()
				return {"ok": false, "error": "write_file"}
			out.store_buffer(bytes)
			out.close()
		fn = da.get_next()
	da.list_dir_end()
	return {"ok": true}


func save_index() -> void:
	DirAccess.make_dir_recursive_absolute(mods_root)
	var mods: Array = []
	for pn: Variant in index.keys():
		mods.append(index[pn])
	mods.sort_custom(func(a: Variant, b: Variant) -> bool:
		return TypedVariant.as_int(TypedVariant.as_dict(a).get("install_order", 0)) < TypedVariant.as_int(TypedVariant.as_dict(b).get("install_order", 0))
	)
	var out: Dictionary = {"schema_ver": 1, "mods": mods}
	var f: FileAccess = FileAccess.open(index_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(out, "\t"))
	f.close()


func list_mods_ordered() -> Array:
	var arr: Array = []
	for pn: Variant in index.keys():
		arr.append(index[pn])
	arr.sort_custom(func(a: Variant, b: Variant) -> bool:
		return TypedVariant.as_int(TypedVariant.as_dict(a).get("install_order", 0)) < TypedVariant.as_int(TypedVariant.as_dict(b).get("install_order", 0))
	)
	return arr


func enabled_mods_ordered() -> Array:
	var out: Array = []
	for m_any: Variant in list_mods_ordered():
		var m: Dictionary = TypedVariant.as_dict(m_any)
		if TypedVariant.as_bool(m.get("enabled", false), false):
			out.append({
				"package_name": str(m.get("package_name", "")),
				"version": str(m.get("version", "")),
				"content_hash": str(m.get("content_hash", "")),
				"install_order": TypedVariant.as_int(m.get("install_order", 0)),
				"byte_size": TypedVariant.as_int(m.get("byte_size", 0)),
			})
	return out


func digest_fingerprint() -> String:
	## Stable string for equality checks.
	var parts: PackedStringArray = PackedStringArray()
	for e_any: Variant in enabled_mods_ordered():
		var e: Dictionary = TypedVariant.as_dict(e_any)
		parts.append("%s|%s|%s" % [e.get("package_name"), e.get("content_hash"), e.get("install_order")])
	return "|".join(parts)


func xx_for_package(package_name: String) -> int:
	var m: Dictionary = TypedVariant.as_dict(index.get(package_name, {}))
	var order: int = TypedVariant.as_int(m.get("install_order", 0))
	if order < 1:
		return 0
	return mini(order, 99)


func runtime_id(package_name: String, local_id: int) -> int:
	var xx: int = xx_for_package(package_name)
	if xx < 1:
		return 0
	return xx * 10000 + clampi(local_id, 0, 9999)


func package_work_dir(package_name: String) -> String:
	return mods_root.path_join(package_name)


func package_zip_path(package_name: String) -> String:
	return mods_root.path_join("%s.zip" % package_name)


## --- Import -----------------------------------------------------------------

func import_path(src_path: String, overwrite: bool = false) -> Dictionary:
	## Returns {ok, package_name, warnings[], error}
	var abs_src: String = src_path
	if abs_src.begins_with("user://") or abs_src.begins_with("res://"):
		abs_src = ProjectSettings.globalize_path(abs_src)
	if abs_src == "" or not (FileAccess.file_exists(abs_src) or DirAccess.dir_exists_absolute(abs_src)):
		return {"ok": false, "error": "path_missing"}
	var staging: String = mods_root.path_join("_import_staging_%d" % Time.get_ticks_msec())
	_remove_dir_recursive(staging)
	DirAccess.make_dir_recursive_absolute(staging)
	var copy_res: Dictionary
	if DirAccess.dir_exists_absolute(abs_src):
		copy_res = _copy_dir_tree(abs_src, staging)
	else:
		copy_res = _extract_zip_safe(abs_src, staging, false)
	if not TypedVariant.as_bool(copy_res.get("ok", false), false):
		_remove_dir_recursive(staging)
		return {"ok": false, "error": str(copy_res.get("error", "copy_failed"))}
	var root: String = _resolve_package_root(staging)
	if root == "":
		_remove_dir_recursive(staging)
		return {"ok": false, "error": "no_mod_json"}
	var mod_json: Dictionary = _read_json_file(root.path_join("mod.json"))
	var pn: String = str(mod_json.get("package_name", "")).strip_edges()
	if pn == "":
		_remove_dir_recursive(staging)
		return {"ok": false, "error": "bad_package_name"}
	if index.has(pn) and not overwrite:
		_remove_dir_recursive(staging)
		return {"ok": false, "error": "exists", "package_name": pn}
	if index.has(pn) and overwrite:
		var bak: String = package_zip_path(pn) + ".bak_%d" % int(Time.get_unix_time_from_system())
		if FileAccess.file_exists(package_zip_path(pn)):
			DirAccess.copy_absolute(package_zip_path(pn), bak)
		_remove_dir_recursive(package_work_dir(pn))
	var dest: String = package_work_dir(pn)
	_remove_dir_recursive(dest)
	DirAccess.make_dir_recursive_absolute(dest)
	var move_res: Dictionary = _copy_dir_tree(root, dest)
	_remove_dir_recursive(staging)
	if not TypedVariant.as_bool(move_res.get("ok", false), false):
		return {"ok": false, "error": "install_copy_failed", "package_name": pn}
	## Refresh zip backup from work dir (best-effort).
	_repack_zip(pn)
	var hash_v: String = compute_tree_hash(dest)
	var zip_p: String = package_zip_path(pn)
	var zip_sha: String = ""
	var byte_size: int = 0
	if FileAccess.file_exists(zip_p):
		var zb: PackedByteArray = FileAccess.get_file_as_bytes(zip_p)
		byte_size = zb.size()
		zip_sha = zb.hex_encode() if zb.is_empty() else _sha256_hex(zb)
	var warnings: PackedStringArray = lint_package(dest, mod_json)
	var order: int = TypedVariant.as_int(TypedVariant.as_dict(index.get(pn, {})).get("install_order", 0))
	if order < 1:
		order = _next_install_order()
	if order > 99:
		_remove_dir_recursive(dest)
		if FileAccess.file_exists(zip_p):
			DirAccess.remove_absolute(zip_p)
		return {"ok": false, "error": "too_many_mods"}
	var entry: Dictionary = {
		"package_name": pn,
		"version": str(mod_json.get("version", "0")),
		"display_name": str(mod_json.get("display_name", pn)),
		"author": str(mod_json.get("author", "")),
		"description": str(mod_json.get("description", "")),
		"enabled": false,
		"enabled_at": 0,
		"install_order": order,
		"content_hash": hash_v,
		"zip_sha256": zip_sha,
		"byte_size": byte_size,
		"lint_warnings": Array(warnings),
		"imported_from": abs_src,
		"disclaimer_ack": false,
		"last_error": "",
		"schema_ver": TypedVariant.as_int(mod_json.get("schema_ver", 1)),
		"min_content_rev": str(mod_json.get("min_content_rev", "0")),
		"platforms": TypedVariant.as_dict(mod_json.get("platforms", {"pc": true, "mobile": true})),
	}
	index[pn] = entry
	save_index()
	return {"ok": true, "package_name": pn, "warnings": Array(warnings)}


func uninstall(package_name: String) -> bool:
	if not index.has(package_name):
		return false
	_remove_dir_recursive(package_work_dir(package_name))
	var zp: String = package_zip_path(package_name)
	if FileAccess.file_exists(zp):
		DirAccess.remove_absolute(zp)
	index.erase(package_name)
	save_index()
	return true


func set_enabled(package_name: String, on: bool) -> Dictionary:
	## {ok, error, need_restart}
	if not index.has(package_name):
		return {"ok": false, "error": "missing"}
	var m: Dictionary = TypedVariant.as_dict(index[package_name])
	if on:
		var gate: Dictionary = _enable_gate(package_name, m)
		if not TypedVariant.as_bool(gate.get("ok", false), false):
			m["last_error"] = str(gate.get("error", "gate"))
			index[package_name] = m
			save_index()
			return gate
		m["enabled"] = true
		m["enabled_at"] = int(Time.get_unix_time_from_system())
		m["last_error"] = ""
	else:
		m["enabled"] = false
	index[package_name] = m
	save_index()
	return {"ok": true, "need_restart": true}


func set_disclaimer_ack(package_name: String, ack: bool = true) -> void:
	if not index.has(package_name):
		return
	var m: Dictionary = TypedVariant.as_dict(index[package_name])
	m["disclaimer_ack"] = ack
	index[package_name] = m
	save_index()


func reorder_install(package_name: String, new_order: int) -> void:
	## Assign install_order and compact 1..n
	if not index.has(package_name):
		return
	var ordered: Array = list_mods_ordered()
	var filtered: Array = []
	for m_any: Variant in ordered:
		var m: Dictionary = TypedVariant.as_dict(m_any)
		if str(m.get("package_name", "")) != package_name:
			filtered.append(m)
	new_order = clampi(new_order, 1, filtered.size() + 1)
	var target: Dictionary = TypedVariant.as_dict(index[package_name])
	filtered.insert(new_order - 1, target)
	var i: int = 1
	for m_any2: Variant in filtered:
		var mm: Dictionary = TypedVariant.as_dict(m_any2)
		mm["install_order"] = i
		index[str(mm.get("package_name", ""))] = mm
		i += 1
	save_index()


func apply_install_order_from_digest(ordered: Array) -> void:
	## Align local install_order to remote digest order (same packages+hashes).
	var i: int = 1
	for e_any: Variant in ordered:
		var e: Dictionary = TypedVariant.as_dict(e_any)
		var pn: String = str(e.get("package_name", ""))
		if not index.has(pn):
			continue
		var m: Dictionary = TypedVariant.as_dict(index[pn])
		m["install_order"] = i
		m["enabled"] = true
		m["enabled_at"] = int(Time.get_unix_time_from_system())
		index[pn] = m
		i += 1
	save_index()


func sync_total_bytes_ok(packages: Array) -> bool:
	var total: int = 0
	for e_any: Variant in packages:
		var e: Dictionary = TypedVariant.as_dict(e_any)
		total += TypedVariant.as_int(e.get("byte_size", 0))
		if TypedVariant.as_int(e.get("byte_size", 0)) > SYNC_MAX_BYTES:
			return false
	return total <= SYNC_MAX_BYTES


func install_received_zip(zip_bytes: PackedByteArray, expected_package: String, from_sync: bool = true) -> Dictionary:
	if from_sync and zip_bytes.size() > SYNC_MAX_BYTES:
		return {"ok": false, "error": "sync_too_large"}
	var tmp: String = mods_root.path_join("_recv_%d.zip" % Time.get_ticks_msec())
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "write_tmp"}
	f.store_buffer(zip_bytes)
	f.close()
	## If local exists with different hash → rename local first
	var staging: String = mods_root.path_join("_recv_stage_%d" % Time.get_ticks_msec())
	_remove_dir_recursive(staging)
	DirAccess.make_dir_recursive_absolute(staging)
	var ex: Dictionary = _extract_zip_safe(tmp, staging, from_sync)
	DirAccess.remove_absolute(tmp)
	if not TypedVariant.as_bool(ex.get("ok", false), false):
		_remove_dir_recursive(staging)
		return {"ok": false, "error": str(ex.get("error", "extract"))}
	var root: String = _resolve_package_root(staging)
	var mod_json: Dictionary = _read_json_file(root.path_join("mod.json"))
	var pn: String = str(mod_json.get("package_name", "")).strip_edges()
	if pn == "" or (expected_package != "" and pn != expected_package):
		_remove_dir_recursive(staging)
		return {"ok": false, "error": "package_mismatch"}
	var new_hash: String = compute_tree_hash(root)
	if index.has(pn):
		var old: Dictionary = TypedVariant.as_dict(index[pn])
		if str(old.get("content_hash", "")) != new_hash:
			var suffix: String = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").substr(0, 8)
			var new_name: String = "%s__local_%s" % [pn, suffix]
			while index.has(new_name):
				new_name = "%s_%d" % [new_name, Time.get_ticks_msec() % 1000]
			_rename_installed(pn, new_name)
	var dest: String = package_work_dir(pn)
	_remove_dir_recursive(dest)
	_copy_dir_tree(root, dest)
	_remove_dir_recursive(staging)
	_repack_zip(pn)
	var hash_v: String = compute_tree_hash(dest)
	var mod_json2: Dictionary = _read_json_file(dest.path_join("mod.json"))
	var warnings: PackedStringArray = lint_package(dest, mod_json2)
	var zip_p: String = package_zip_path(pn)
	var zip_sha: String = ""
	var byte_size: int = 0
	if FileAccess.file_exists(zip_p):
		var zb: PackedByteArray = FileAccess.get_file_as_bytes(zip_p)
		byte_size = zb.size()
		zip_sha = _sha256_hex(zb)
	var order: int = TypedVariant.as_int(TypedVariant.as_dict(index.get(pn, {})).get("install_order", 0))
	if order < 1:
		order = _next_install_order()
	index[pn] = {
		"package_name": pn,
		"version": str(mod_json2.get("version", "0")),
		"display_name": str(mod_json2.get("display_name", pn)),
		"author": str(mod_json2.get("author", "")),
		"description": str(mod_json2.get("description", "")),
		"enabled": true,
		"enabled_at": int(Time.get_unix_time_from_system()),
		"install_order": order,
		"content_hash": hash_v,
		"zip_sha256": zip_sha,
		"byte_size": byte_size,
		"lint_warnings": Array(warnings),
		"imported_from": "net_sync",
		"disclaimer_ack": true,
		"last_error": "",
		"schema_ver": TypedVariant.as_int(mod_json2.get("schema_ver", 1)),
		"min_content_rev": str(mod_json2.get("min_content_rev", "0")),
		"platforms": TypedVariant.as_dict(mod_json2.get("platforms", {"pc": true, "mobile": true})),
	}
	save_index()
	return {"ok": true, "package_name": pn, "warnings": Array(warnings)}


func _rename_installed(old_pn: String, new_pn: String) -> void:
	var old_dir: String = package_work_dir(old_pn)
	var new_dir: String = package_work_dir(new_pn)
	if DirAccess.dir_exists_absolute(old_dir):
		DirAccess.rename_absolute(old_dir, new_dir)
	var old_zip: String = package_zip_path(old_pn)
	var new_zip: String = package_zip_path(new_pn)
	if FileAccess.file_exists(old_zip):
		DirAccess.rename_absolute(old_zip, new_zip)
	var m: Dictionary = TypedVariant.as_dict(index.get(old_pn, {}))
	m["package_name"] = new_pn
	m["display_name"] = "%s (%s)" % [str(m.get("display_name", old_pn)), new_pn]
	m["enabled"] = true
	index.erase(old_pn)
	index[new_pn] = m
	## Patch mod.json package_name inside work dir
	var mj_path: String = new_dir.path_join("mod.json")
	var mj: Dictionary = _read_json_file(mj_path)
	if not mj.is_empty():
		mj["package_name"] = new_pn
		_write_json_file(mj_path, mj)
	save_index()


## --- Merge into DataStore ---------------------------------------------------

func merge_enabled_into_datastore(_ds: Node = null) -> void:
	## Always merges into Autoload DataStore (typed); `_ds` kept for call-site compat.
	runtime_ships.clear()
	_package_fx_protocol.clear()
	runtime_modules.clear()
	runtime_function_modules.clear()
	runtime_fetters.clear()
	runtime_tonnage.clear()
	runtime_titan_picks.clear()
	replacements.clear()
	disable_ship_ids.clear()
	disable_equipment_ids.clear()
	mod_unit_dirs.clear()
	_package_fx_protocol.clear()
	merged_shop_rules.clear()
	merged_ui_overrides.clear()
	_merged_ui_overrides_root = ""
	merged_prepare_radar_override.clear()
	last_merge_warnings = PackedStringArray()
	var enabled: Array = []
	for m_any: Variant in list_mods_ordered():
		var m: Dictionary = TypedVariant.as_dict(m_any)
		if TypedVariant.as_bool(m.get("enabled", false), false):
			enabled.append(m)
	## Dependency topo: simple multi-pass
	var topo_ready: Array = []
	var pending: Array = enabled.duplicate()
	var guard: int = 0
	while not pending.is_empty() and guard < 64:
		guard += 1
		var progressed: bool = false
		var still: Array = []
		for m_any2: Variant in pending:
			var mm: Dictionary = TypedVariant.as_dict(m_any2)
			if _deps_satisfied(mm):
				topo_ready.append(mm)
				progressed = true
			else:
				still.append(mm)
		pending = still
		if not progressed:
			for bad_any: Variant in pending:
				var bad: Dictionary = TypedVariant.as_dict(bad_any)
				_note_warn("%s: dependency missing" % bad.get("package_name"))
				bad["last_error"] = "dependency"
				bad["enabled"] = false
				index[str(bad.get("package_name", ""))] = bad
			save_index()
			break
	## Incompatibilities
	var enabled_names: Dictionary = {}
	for r_any: Variant in topo_ready:
		enabled_names[str(TypedVariant.as_dict(r_any).get("package_name", ""))] = true
	var blocked: Dictionary = {}
	for r_any2: Variant in topo_ready:
		var rr: Dictionary = TypedVariant.as_dict(r_any2)
		var pn: String = str(rr.get("package_name", ""))
		var mj: Dictionary = _read_json_file(package_work_dir(pn).path_join("mod.json"))
		for inc_any: Variant in TypedVariant.as_array(mj.get("incompatibilities", [])):
			var inc: Dictionary = TypedVariant.as_dict(inc_any)
			var other: String = str(inc.get("package", ""))
			if other != "" and enabled_names.has(other):
				blocked[pn] = true
				blocked[other] = true
				_note_warn("%s incompatible with %s" % [pn, other])
	var load_list: Array = []
	for r_any3: Variant in topo_ready:
		var r3: Dictionary = TypedVariant.as_dict(r_any3)
		var p3: String = str(r3.get("package_name", ""))
		if blocked.has(p3):
			r3["last_error"] = "incompatible"
			r3["enabled"] = false
			index[p3] = r3
			continue
		var gate: Dictionary = _enable_gate(p3, r3)
		if not TypedVariant.as_bool(gate.get("ok", false), false):
			r3["last_error"] = str(gate.get("error", "gate"))
			r3["enabled"] = false
			index[p3] = r3
			continue
		load_list.append(r3)
	save_index()
	## Latest enabled_at wins for disable tables + shop_rules + ui_overrides
	var latest_disable: Dictionary = {}
	var latest_at: int = -1
	var latest_rules_at: int = -1
	var latest_ui_at: int = -1
	var latest_radar_at: int = -1
	for r_any4: Variant in load_list:
		var r4: Dictionary = TypedVariant.as_dict(r_any4)
		var at: int = TypedVariant.as_int(r4.get("enabled_at", 0))
		if at >= latest_at:
			latest_at = at
			latest_disable = r4
		var pn4: String = str(r4.get("package_name", ""))
		var mj4: Dictionary = _read_json_file(package_work_dir(pn4).path_join("mod.json"))
		if mj4.has("shop_rules") and at >= latest_rules_at:
			latest_rules_at = at
			merged_shop_rules = TypedVariant.as_dict(mj4.get("shop_rules", {}))
		if mj4.has("ui_overrides") and at >= latest_ui_at:
			latest_ui_at = at
			merged_ui_overrides = TypedVariant.as_dict(mj4.get("ui_overrides", {}))
			_merged_ui_overrides_root = package_work_dir(pn4)
		if mj4.has("prepare_radar_override") and at >= latest_radar_at:
			latest_radar_at = at
			merged_prepare_radar_override = TypedVariant.as_dict(mj4.get("prepare_radar_override", {}))
	if not latest_disable.is_empty():
		var lpn: String = str(latest_disable.get("package_name", ""))
		var lmj: Dictionary = _read_json_file(package_work_dir(lpn).path_join("mod.json"))
		for d_any: Variant in TypedVariant.as_array(lmj.get("disable_ships", [])):
			disable_ship_ids[_disable_key(d_any)] = true
		for d2_any: Variant in TypedVariant.as_array(lmj.get("disable_equipment", [])):
			disable_equipment_ids[_disable_key(d2_any)] = true
	## Official tonnage keys (must not overwrite)
	var official_tonnage: Dictionary = UiAssets.TONNAGE_ICON_MAP
	## Mount units by install_order
	load_list.sort_custom(func(a: Variant, b: Variant) -> bool:
		return TypedVariant.as_int(TypedVariant.as_dict(a).get("install_order", 0)) < TypedVariant.as_int(TypedVariant.as_dict(b).get("install_order", 0))
	)
	var claimed_runtime: Dictionary = {} ## runtime_id -> package
	for r_any5: Variant in load_list:
		var r5: Dictionary = TypedVariant.as_dict(r_any5)
		_merge_one_mod(r5, official_tonnage, claimed_runtime, null)
	_merge_titan_picks_from_mods(load_list)
	## Apply replacements (latest enabled_at wins per from)
	var repl_by_from: Dictionary = {} ## from_key -> {at, to_id}
	for r_any6: Variant in load_list:
		var r6: Dictionary = TypedVariant.as_dict(r_any6)
		var pn6: String = str(r6.get("package_name", ""))
		var mj6: Dictionary = _read_json_file(package_work_dir(pn6).path_join("mod.json"))
		var at6: int = TypedVariant.as_int(r6.get("enabled_at", 0))
		for rep_any: Variant in TypedVariant.as_array(mj6.get("replacements", [])):
			_register_replacement(repl_by_from, rep_any, pn6, at6)
		_scan_unit_replaces(package_work_dir(pn6), pn6, at6, repl_by_from)
	for fk: Variant in repl_by_from.keys():
		var info: Dictionary = TypedVariant.as_dict(repl_by_from[fk])
		replacements[str(fk)] = TypedVariant.as_int(info.get("to_id", 0))
	## Inject into DataStore — never overwrite official same integer id
	for sid_any: Variant in runtime_ships.keys():
		var sid: int = TypedVariant.as_int(sid_any)
		if disable_ship_ids.has(str(sid)) or disable_ship_ids.has(sid):
			continue
		if DataStore.ships.has(sid) and str(TypedVariant.as_dict(DataStore.ships[sid]).get("_mod_package", "")) == "":
			_note_warn("skip mod ship id %s — would overwrite official" % sid)
			continue
		var ship: Dictionary = TypedVariant.as_dict(runtime_ships[sid])
		DataStore.ships[sid] = ship
		DataStore.ship_sources[sid] = "mod:%s" % str(ship.get("_mod_package", ""))
	for mid_any: Variant in runtime_modules.keys():
		var mid: int = TypedVariant.as_int(mid_any)
		if DataStore.modules.has(mid) and str(TypedVariant.as_dict(DataStore.modules[mid]).get("_mod_package", "")) == "":
			_note_warn("skip mod module id %s — would overwrite official" % mid)
			continue
		DataStore.modules[mid] = runtime_modules[mid_any]
	for fid_any: Variant in runtime_function_modules.keys():
		DataStore.function_modules[fid_any] = runtime_function_modules[fid_any]
	var titan_fetter_override: Dictionary = _titan_fetter_override_ids()
	for fet_any: Variant in runtime_fetters.keys():
		var fid: String = str(fet_any)
		if DataStore.fetters.has(fid):
			if titan_fetter_override.has(fid):
				DataStore.fetters[fid] = runtime_fetters[fid]
				continue
			_note_warn("fetter_id collision skip: %s" % fid)
			continue
		DataStore.fetters[fid] = runtime_fetters[fid]
	## Extend economy unlock map for new tonnage
	if not runtime_tonnage.is_empty():
		var eco: Dictionary = TypedVariant.as_dict(DataStore.economy)
		var unlocks: Dictionary = TypedVariant.as_dict(eco.get("shop_unlock_level_by_group", {}))
		for tg: Variant in runtime_tonnage.keys():
			var tdef: Dictionary = TypedVariant.as_dict(runtime_tonnage[tg])
			unlocks[str(tg)] = TypedVariant.as_int(tdef.get("shop_unlock_level", 6))
		eco["shop_unlock_level_by_group"] = unlocks
		DataStore.economy = eco
	## Register tonnage icons into UiAssets runtime extension
	UiAssets.register_mod_tonnage_icons(runtime_tonnage)
	UiAssets.register_mod_coin_icon(coin_icon_absolute_path())


func coin_icon_absolute_path() -> String:
	var rel: String = str(merged_ui_overrides.get("coin_icon", "")).strip_edges()
	if rel == "" or _merged_ui_overrides_root == "":
		return ""
	return _merged_ui_overrides_root.path_join(rel)


func resolve_ship_id(raw_id: int, mod_ref: Dictionary = {}) -> int:
	if not mod_ref.is_empty():
		var pn: String = str(mod_ref.get("package_name", ""))
		var lid: int = TypedVariant.as_int(mod_ref.get("local_id", -1))
		if pn != "" and lid >= 0:
			var rid: int = runtime_id(pn, lid)
			if rid > 0:
				return rid
	var key: String = str(raw_id)
	if replacements.has(key):
		return TypedVariant.as_int(replacements[key])
	return raw_id


func is_ship_disabled(ship_id: int) -> bool:
	if disable_ship_ids.has(ship_id) or disable_ship_ids.has(str(ship_id)):
		return true
	## Also if replaced away
	return false


func mod_ref_for_ship(ship_id: int) -> Dictionary:
	var ship: Dictionary = TypedVariant.as_dict(runtime_ships.get(ship_id, {}))
	if ship.is_empty() and DataStore != null:
		ship = DataStore.get_ship(ship_id)
	var pn: String = str(ship.get("_mod_package", ""))
	if pn == "":
		return {}
	return {"package_name": pn, "local_id": TypedVariant.as_int(ship.get("local_id", ship_id % 10000))}


func unit_dir_for_ship(ship_id: int) -> String:
	return str(mod_unit_dirs.get(ship_id, ""))


func write_unit_json(ship_id: int, data: Dictionary) -> bool:
	var dir: String = unit_dir_for_ship(ship_id)
	if dir == "":
		return false
	var pn: String = str(data.get("_mod_package", ""))
	var out: Dictionary = data.duplicate(true)
	out.erase("id")
	out.erase("_mod_package")
	out.erase("_mod_unit_dir")
	if not _write_json_file(dir.path_join("unit.json"), out):
		return false
	if pn != "":
		_repack_zip(pn)
		var entry: Dictionary = TypedVariant.as_dict(index.get(pn, {}))
		entry["content_hash"] = compute_tree_hash(package_work_dir(pn))
		if FileAccess.file_exists(package_zip_path(pn)):
			var zb: PackedByteArray = FileAccess.get_file_as_bytes(package_zip_path(pn))
			entry["byte_size"] = zb.size()
			entry["zip_sha256"] = _sha256_hex(zb)
		index[pn] = entry
		save_index()
	return true


## --- Internals --------------------------------------------------------------

func _enable_gate(package_name: String, m: Dictionary) -> Dictionary:
	var schema: int = TypedVariant.as_int(m.get("schema_ver", 1))
	if schema > SCHEMA_VER_MAX:
		return {"ok": false, "error": "schema_ver"}
	var min_rev: String = str(m.get("min_content_rev", "0"))
	var cur: String = "0"
	if DataStore != null:
		cur = str(DataStore.content_version)
	if min_rev != "0" and min_rev != "" and cur != "local" and _version_lt(cur, min_rev):
		return {"ok": false, "error": "min_content_rev"}
	var plats: Dictionary = TypedVariant.as_dict(m.get("platforms", {}))
	var on_mobile: bool = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	if on_mobile and plats.has("mobile") and not TypedVariant.as_bool(plats.get("mobile", true), true):
		return {"ok": false, "error": "platform_mobile"}
	if (not on_mobile) and plats.has("pc") and not TypedVariant.as_bool(plats.get("pc", true), true):
		return {"ok": false, "error": "platform_pc"}
	if not DirAccess.dir_exists_absolute(package_work_dir(package_name)):
		return {"ok": false, "error": "missing_work_dir"}
	return {"ok": true}


func _deps_satisfied(m: Dictionary) -> bool:
	var pn: String = str(m.get("package_name", ""))
	var mj: Dictionary = _read_json_file(package_work_dir(pn).path_join("mod.json"))
	for d_any: Variant in TypedVariant.as_array(mj.get("dependencies", [])):
		var d: Dictionary = TypedVariant.as_dict(d_any)
		var dep: String = str(d.get("package", ""))
		if dep == "":
			continue
		if not index.has(dep):
			return false
		var dep_m: Dictionary = TypedVariant.as_dict(index[dep])
		if not TypedVariant.as_bool(dep_m.get("enabled", false), false):
			return false
		var need: String = str(d.get("min_version", ""))
		if need != "" and _version_lt(str(dep_m.get("version", "0")), need):
			return false
	return true


func _merge_one_mod(m: Dictionary, official_tonnage: Dictionary, claimed_runtime: Dictionary, _ds: Node = null) -> void:
	var pn: String = str(m.get("package_name", ""))
	var root: String = package_work_dir(pn)
	var mj: Dictionary = _read_json_file(root.path_join("mod.json"))
	var xx: int = xx_for_package(pn)
	if xx < 1 or xx > 99:
		_note_warn("%s: bad xx" % pn)
		return
	_package_fx_protocol[pn] = TypedVariant.as_int(mj.get("fx_protocol", 1), 1)
	## tonnage
	for tg_any: Variant in TypedVariant.as_array(mj.get("tonnage_groups", [])):
		var tg: Dictionary = TypedVariant.as_dict(tg_any)
		var tid: String = str(tg.get("id", ""))
		if tid == "":
			continue
		if official_tonnage.has(tid):
			_note_warn("%s: tonnage hits official key %s — skip" % [pn, tid])
			continue
		var icon_rel: String = str(tg.get("icon", "")).strip_edges()
		if icon_rel != "":
			var icon_abs: String = root.path_join(icon_rel)
			if FileAccess.file_exists(icon_abs):
				tg["icon"] = icon_abs
		runtime_tonnage[tid] = tg
	var local_seen: Dictionary = {}
	_scan_units(root.path_join("units/ships"), pn, xx, "ship", local_seen, claimed_runtime)
	_scan_units(root.path_join("units/unmanned"), pn, xx, "unmanned", local_seen, claimed_runtime)
	_scan_units(root.path_join("units/equipment"), pn, xx, "equipment", local_seen, claimed_runtime)
	## fetters
	var fet_dir: String = root.path_join("fetters")
	if DirAccess.dir_exists_absolute(fet_dir):
		var da: DirAccess = DirAccess.open(fet_dir)
		if da:
			da.list_dir_begin()
			var fn: String = da.get_next()
			while fn != "":
				if not da.current_is_dir() and fn.ends_with(".json"):
					var fd: Dictionary = _read_json_file(fet_dir.path_join(fn))
					var fid: String = str(fd.get("id", fn.get_basename()))
					runtime_fetters[fid] = fd
				fn = da.get_next()
			da.list_dir_end()
	## Optional assets.zip mount
	var assets_zip: String = root.path_join("assets.zip")
	if FileAccess.file_exists(assets_zip):
		ProjectSettings.load_resource_pack(assets_zip, true)


func _scan_units(dir_path: String, pn: String, xx: int, kind: String, local_seen: Dictionary, claimed_runtime: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var sub: String = da.get_next()
	while sub != "":
		if da.current_is_dir() and not sub.begins_with("."):
			var unit_dir: String = dir_path.path_join(sub)
			var uj: Dictionary = _read_json_file(unit_dir.path_join("unit.json"))
			if uj.is_empty():
				_note_warn("%s: missing unit.json in %s" % [pn, unit_dir])
			else:
				_register_unit(uj, unit_dir, pn, xx, kind, local_seen, claimed_runtime)
		sub = da.get_next()
	da.list_dir_end()


func _register_unit(uj: Dictionary, unit_dir: String, pn: String, xx: int, kind: String, local_seen: Dictionary, claimed_runtime: Dictionary) -> void:
	var lid_raw: Variant = uj.get("local_id", uj.get("id", -1))
	var lid: int = TypedVariant.as_int(lid_raw, -1)
	if lid < 0:
		_note_warn("%s: unit missing local_id (%s)" % [pn, unit_dir])
		return
	if lid > 9999:
		_note_warn("%s: local_id %s looks like full id — using XXXX only" % [pn, lid])
		lid = lid % 10000
	if local_seen.has(lid):
		_note_warn("%s: XXXX %s collision — skip %s" % [pn, lid, unit_dir])
		return
	local_seen[lid] = true
	var rid: int = xx * 10000 + lid
	if claimed_runtime.has(rid):
		## Later mount wins: drop previous
		_note_warn("runtime id %s collision; later mod %s wins over %s" % [rid, pn, claimed_runtime[rid]])
		runtime_ships.erase(rid)
		runtime_modules.erase(rid)
	claimed_runtime[rid] = pn
	var data: Dictionary = uj.duplicate(true)
	data["local_id"] = lid
	data["id"] = rid
	data["_mod_package"] = pn
	data["_mod_unit_dir"] = unit_dir
	mod_unit_dirs[rid] = unit_dir
	## visual merge
	var vis_path: String = unit_dir.path_join("visual.json")
	if FileAccess.file_exists(vis_path):
		data["_visual"] = _read_json_file(vis_path)
	var portrait: String = unit_dir.path_join("portrait/portrait.png")
	if FileAccess.file_exists(portrait):
		data["portrait"] = portrait
	var shop_bg: String = unit_dir.path_join("shop_bg/tips_skybox.png")
	if FileAccess.file_exists(shop_bg):
		data["shop_skybox"] = shop_bg
	var model_glb: String = unit_dir.path_join("model/model.glb")
	if FileAccess.file_exists(model_glb):
		data["_mod_model_glb"] = model_glb
	var model_obj: String = unit_dir.path_join("model/model.obj")
	if FileAccess.file_exists(model_obj):
		data["_mod_model_obj"] = model_obj
	var icon_png: String = unit_dir.path_join("icon/icon.png")
	if FileAccess.file_exists(icon_png) and not data.has("icon"):
		data["icon"] = icon_png
	_apply_weapon_fx_override(data, unit_dir, pn, lid)
	_apply_interaction_fx_override(data, unit_dir, pn, lid)
	_apply_trail_override(data, pn, lid, kind)
	_apply_prepare_radar_override(data, pn, lid, kind)
	if kind == "equipment":
		var ekind: String = str(data.get("kind", "main"))
		if ekind == "function":
			runtime_function_modules[str(rid)] = data
		else:
			if not data.has("attack_range"):
				_note_warn("%s: main equip local_id %s missing attack_range (board cells 0–999) — runtime falls back COMBAT §3.1" % [pn, lid])
			else:
				var ar: float = TypedVariant.as_float(data.get("attack_range", -1.0), -1.0)
				if ar < 0.0 or ar > 999.0:
					_note_warn("%s: main equip local_id %s attack_range out of 0–999 — will clamp" % [pn, lid])
					data["attack_range"] = clampf(ar, 0.0, 999.0)
			runtime_modules[rid] = data
		return
	if kind == "unmanned":
		data["is_unmanned"] = true
		data["shop_eligible"] = false
	## ship_group gate
	var sg: String = str(data.get("ship_group", ""))
	var official: bool = UiAssets.TONNAGE_ICON_MAP.has(sg)
	var mod_tg: bool = runtime_tonnage.has(sg)
	if sg != "" and not official and not mod_tg:
		_note_warn("%s: ship_group %s unregistered — skip ship %s" % [pn, sg, lid])
		return
	_autofill_ship(data)
	runtime_ships[rid] = data


func _merge_titan_picks_from_mods(load_list: Array) -> void:
	for r_any: Variant in load_list:
		var r: Dictionary = TypedVariant.as_dict(r_any)
		var pn: String = str(r.get("package_name", ""))
		var xx: int = xx_for_package(pn)
		if xx < 1:
			continue
		var mj: Dictionary = _read_json_file(package_work_dir(pn).path_join("mod.json"))
		for pick_any: Variant in TypedVariant.as_array(mj.get("titan_picks", [])):
			if typeof(pick_any) != TYPE_DICTIONARY:
				continue
			var pick: Dictionary = TypedVariant.as_dict(pick_any)
			var label: String = "%s:titan_pick" % pn
			for note: String in ModTitanResolve.lint_pick(pick, label):
				_note_warn(note)
			var norm: Dictionary = ModTitanResolve.normalize_pick(pick, pn, xx, runtime_ships, runtime_fetters)
			if norm.is_empty():
				continue
			for note2: String in ModTitanResolve.validate_normalized_pick(norm, label, runtime_ships, runtime_fetters):
				_note_warn(note2)
			var race: String = str(norm.get("race", "")).strip_edges().to_lower()
			if race == "":
				continue
			runtime_titan_picks[race] = norm


func _titan_fetter_override_ids() -> Dictionary:
	## Mod titan_picks may replace official titan_* meta fetters when mod supplies the fetter json.
	var out: Dictionary = {}
	for race_any: Variant in runtime_titan_picks.keys():
		var pick: Dictionary = TypedVariant.as_dict(runtime_titan_picks[race_any])
		if str(pick.get("package", "")).strip_edges() == "":
			continue
		var fid: String = str(pick.get("fetter_id", "")).strip_edges()
		if fid == "" or not runtime_fetters.has(fid):
			continue
		var fdef: Dictionary = TypedVariant.as_dict(runtime_fetters[fid])
		if not TypedVariant.as_bool(fdef.get("meta", false), false):
			continue
		out[fid] = true
	return out


func _apply_weapon_fx_override(data: Dictionary, unit_dir: String, pn: String, lid: int) -> void:
	var ov: Dictionary = TypedVariant.as_dict(data.get("weapon_fx_override", {}))
	if ov.is_empty():
		return
	var label: String = "%s#%s" % [pn, lid]
	var kinds: Dictionary = TypedVariant.as_dict(DataStore.weapon_fx.get("kinds", {}))
	for note: String in ModFxResolve.lint_override(ov, label, kinds):
		_note_warn(note)
	data["weapon_fx_override"] = ModFxResolve.normalize_override_paths(ov, unit_dir)


func _apply_trail_override(data: Dictionary, pn: String, lid: int, kind: String) -> void:
	## Ships / unmanned only. Prefer unit.json; else lift from visual.json stash.
	var ov: Dictionary = ModTrailResolve.pick_from_unit_data(data)
	if ov.is_empty():
		data.erase("trail_override")
		return
	if kind == "equipment":
		_note_warn("%s#%s: trail_override ignored on equipment" % [pn, lid])
		data.erase("trail_override")
		return
	var label: String = "%s#%s" % [pn, lid]
	for note: String in ModTrailResolve.lint_override(ov, label):
		_note_warn(note)
	var cleaned: Dictionary = {}
	for k: String in ModTrailResolve.SAFE_KEYS:
		if ov.has(k):
			cleaned[k] = ov[k]
	if cleaned.is_empty():
		data.erase("trail_override")
		return
	data["trail_override"] = cleaned


func _apply_prepare_radar_override(data: Dictionary, pn: String, lid: int, kind: String) -> void:
	if kind == "equipment":
		data.erase("prepare_radar_override")
		return
	var ov: Dictionary = ModPrepareRadarResolve.pick_from_unit_data(data)
	if ov.is_empty():
		data.erase("prepare_radar_override")
		return
	var label: String = "%s#%s" % [pn, lid]
	for note: String in ModPrepareRadarResolve.lint_override(ov, label):
		_note_warn(note)
	var cleaned: Dictionary = {}
	for k: String in ModPrepareRadarResolve.SAFE_KEYS:
		if ov.has(k):
			cleaned[k] = ov[k]
	if cleaned.is_empty():
		data.erase("prepare_radar_override")
		return
	data["prepare_radar_override"] = cleaned


func _apply_interaction_fx_override(data: Dictionary, unit_dir: String, pn: String, lid: int) -> void:
	var ov: Dictionary = TypedVariant.as_dict(data.get("interaction_fx_override", {}))
	var kind_only: String = str(data.get("interaction_fx", "")).strip_edges()
	var has_ix: bool = not ov.is_empty() or kind_only != ""
	if not has_ix:
		return
	var label: String = "%s#%s" % [pn, lid]
	var pkg_proto: int = TypedVariant.as_int(_package_fx_protocol.get(pn, 1), 1)
	if pkg_proto < ModInteractionFxResolve.FX_PROTOCOL_SUPPORTED:
		_note_warn("%s: interaction_fx ignored (fx_protocol %d < %d)" % [label, pkg_proto, ModInteractionFxResolve.FX_PROTOCOL_SUPPORTED])
		data.erase("interaction_fx")
		data.erase("interaction_fx_override")
		return
	if pkg_proto > ModInteractionFxResolve.FX_PROTOCOL_SUPPORTED:
		_note_warn("%s: fx_protocol %d > shell %d — interaction fields may clamp" % [
			label, pkg_proto, ModInteractionFxResolve.FX_PROTOCOL_SUPPORTED
		])
	var kinds: Dictionary = TypedVariant.as_dict(DataStore.interaction_fx.get("kinds", {}))
	if kind_only != "" and not kinds.has(kind_only):
		_note_warn("%s: interaction_fx unknown kind '%s'" % [label, kind_only])
	if ov.is_empty():
		return
	for note: String in ModInteractionFxResolve.lint_override(ov, label, kinds):
		_note_warn(note)
	var normalized: Dictionary = ModInteractionFxResolve.normalize_override_paths(ov, unit_dir)
	var recipe_abs: String = str(normalized.get("recipe_abs", "")).strip_edges()
	if recipe_abs != "" and FileAccess.file_exists(recipe_abs):
		var recipe: Dictionary = ModInteractionFxResolve.load_recipe_file(recipe_abs)
		var base_kind: String = str(normalized.get("base", ov.get("base", "burst_sprite")))
		var kind_def: Dictionary = TypedVariant.as_dict(kinds.get(base_kind, {}))
		var max_layers: int = TypedVariant.as_int(kind_def.get("max_layers", 4), 4)
		var max_p: int = TypedVariant.as_int(kind_def.get("max_particles_per_layer", 128), 128)
		for note2: String in ModInteractionFxResolve.lint_recipe(recipe, label, max_layers, max_p):
			_note_warn(note2)
	elif str(ov.get("recipe", "")).strip_edges() != "":
		_note_warn("%s: interaction recipe missing: %s" % [label, ov.get("recipe")])
	data["interaction_fx_override"] = normalized


## Enabled mod with menu{} — largest install_order wins (tie: enabled_at). Local UI only.
func get_menu_override() -> Dictionary:
	_ensure_boot()
	var best: Dictionary = {}
	var best_order: int = -1
	var best_at: int = -1
	for pn_any: Variant in index.keys():
		var pn: String = str(pn_any)
		var entry: Dictionary = TypedVariant.as_dict(index.get(pn, {}))
		if not TypedVariant.as_bool(entry.get("enabled", false), false):
			continue
		var dest: String = package_work_dir(pn)
		var mod_json: Dictionary = _read_json_file(dest.path_join("mod.json"))
		var menu: Dictionary = TypedVariant.as_dict(mod_json.get("menu", {}))
		if menu.is_empty():
			continue
		var order: int = TypedVariant.as_int(entry.get("install_order", 0))
		var eat: int = TypedVariant.as_int(entry.get("enabled_at", 0))
		if order < best_order:
			continue
		if order == best_order and eat <= best_at:
			continue
		best_order = order
		best_at = eat
		best = menu.duplicate(true)
		var bg_rel: String = str(best.get("bg", "")).strip_edges().replace("\\", "/")
		if bg_rel != "":
			var bg_abs: String = dest.path_join(bg_rel)
			if FileAccess.file_exists(bg_abs):
				best["bg"] = bg_abs
			else:
				_note_warn("%s: menu.bg missing %s" % [pn, bg_rel])
				best.erase("bg")
		var title: String = str(best.get("title", "")).strip_edges()
		if title == "":
			best.erase("title")
		else:
			best["title"] = title
	return best


func _autofill_ship(data: Dictionary) -> void:
	if not data.has("function_slots"):
		data["function_slots"] = {"slots": []}
	if not data.has("fetter_ids"):
		data["fetter_ids"] = []
	if not data.has("mid_battle_leave_allowed"):
		data["mid_battle_leave_allowed"] = false
	var stars: Array = TypedVariant.as_array(data.get("stars", []))
	if stars.is_empty():
		data["stars"] = [{
			"shield_hp": 400, "armor_hp": 500, "structure_hp": 250,
			"shield_resist": [0.2, 0.2, 0.2, 0.2],
			"armor_resist": [0.2, 0.2, 0.2, 0.2],
			"structure_resist": [0.2, 0.2, 0.2, 0.2],
		}]
	elif stars.size() == 1:
		var s1: Dictionary = TypedVariant.as_dict(stars[0])
		var s2: Dictionary = s1.duplicate(true)
		var s3: Dictionary = s1.duplicate(true)
		for k: String in ["shield_hp", "armor_hp", "structure_hp"]:
			s2[k] = TypedVariant.as_int(s1.get(k, 0)) * 2
			s3[k] = TypedVariant.as_int(s1.get(k, 0)) * 3
		data["stars"] = [s1, s2, s3]
	## mining_gold → round_actions
	if data.has("mining_gold_per_round") and TypedVariant.as_array(data.get("round_actions", [])).is_empty():
		data["round_actions"] = [{
			"id": "mining_income",
			"phase": "economy_income",
			"op": "add_gold",
			"params": {
				"per_star": TypedVariant.as_int(data.get("mining_gold_per_round", 0)),
				"require_alive_on_field": true,
			},
		}]


func _register_replacement(repl_by_from: Dictionary, rep_any: Variant, pn: String, at: int) -> void:
	var rep: Dictionary = TypedVariant.as_dict(rep_any)
	var mode: String = str(rep.get("mode", "role"))
	if mode != "role":
		return
	var from_key: String = _from_key(rep.get("from", null))
	var to_local: int = TypedVariant.as_int(rep.get("to_local", rep.get("to", -1)))
	if from_key == "" or to_local < 0:
		return
	var to_id: int = runtime_id(pn, to_local)
	var prev: Dictionary = TypedVariant.as_dict(repl_by_from.get(from_key, {}))
	if TypedVariant.as_int(prev.get("at", -1)) <= at:
		repl_by_from[from_key] = {"at": at, "to_id": to_id, "package": pn}


func _scan_unit_replaces(root: String, pn: String, at: int, repl_by_from: Dictionary) -> void:
	for sub: String in ["units/ships", "units/unmanned", "units/equipment"]:
		var d: String = root.path_join(sub)
		if not DirAccess.dir_exists_absolute(d):
			continue
		var da: DirAccess = DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		var dir_name: String = da.get_next()
		while dir_name != "":
			if da.current_is_dir() and not dir_name.begins_with("."):
				var uj: Dictionary = _read_json_file(d.path_join(dir_name).path_join("unit.json"))
				if uj.has("replaces") and uj.get("replaces") != null:
					var lid: int = TypedVariant.as_int(uj.get("local_id", -1))
					_register_replacement(repl_by_from, {
						"from": uj.get("replaces"),
						"to_local": lid,
						"mode": str(uj.get("replace_mode", "role")),
					}, pn, at)
			dir_name = da.get_next()
		da.list_dir_end()


func _from_key(from_v: Variant) -> String:
	if typeof(from_v) == TYPE_DICTIONARY:
		var d: Dictionary = TypedVariant.as_dict(from_v)
		return "%s:%s" % [d.get("package", ""), d.get("local_id", "")]
	return str(TypedVariant.as_int(from_v, -1))


func _disable_key(v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY:
		return _from_key(v)
	return TypedVariant.as_int(v, -1)


func lint_package(root: String, mod_json: Dictionary) -> PackedStringArray:
	var w: PackedStringArray = PackedStringArray()
	var pn: String = str(mod_json.get("package_name", ""))
	var re: RegEx = RegEx.new()
	re.compile("^[a-z][a-z0-9_-]{1,63}$")
	if re.search(pn) == null:
		w.append("package_name 不符合 kebab 建议")
	if str(mod_json.get("display_name", "")) == "":
		w.append("缺 display_name")
	if str(mod_json.get("author", "")) == "":
		w.append("缺 author")
	for pick_any: Variant in TypedVariant.as_array(mod_json.get("titan_picks", [])):
		if typeof(pick_any) != TYPE_DICTIONARY:
			w.append("titan_picks 项必须是对象")
			continue
		for note: String in ModTitanResolve.lint_pick(TypedVariant.as_dict(pick_any), "%s:titan_picks" % pn):
			w.append(note)
	var local_ids: Dictionary = {}
	for sub: String in ["units/ships", "units/unmanned", "units/equipment"]:
		var d: String = root.path_join(sub)
		if not DirAccess.dir_exists_absolute(d):
			continue
		var da: DirAccess = DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		var dir_name: String = da.get_next()
		while dir_name != "":
			if da.current_is_dir() and not dir_name.begins_with("."):
				var uj: Dictionary = _read_json_file(d.path_join(dir_name).path_join("unit.json"))
				if uj.is_empty():
					w.append("缺 unit.json: %s/%s" % [sub, dir_name])
				else:
					var lid: int = TypedVariant.as_int(uj.get("local_id", uj.get("id", -1)))
					if lid < 0:
						w.append("缺 local_id: %s/%s" % [sub, dir_name])
					elif local_ids.has(lid):
						w.append("XXXX 撞车 %s" % lid)
					else:
						local_ids[lid] = true
					if lid > 9999:
						w.append("疑似完整六位 id: %s" % lid)
					var ov: Dictionary = TypedVariant.as_dict(uj.get("weapon_fx_override", {}))
					if not ov.is_empty():
						var kinds: Dictionary = TypedVariant.as_dict(DataStore.weapon_fx.get("kinds", {}))
						for note: String in ModFxResolve.lint_override(ov, "%s/%s" % [sub, dir_name], kinds):
							w.append(note)
					var trail_ov: Dictionary = TypedVariant.as_dict(uj.get("trail_override", {}))
					if trail_ov.is_empty():
						var vis_path: String = d.path_join(dir_name).path_join("visual.json")
						if FileAccess.file_exists(vis_path):
							var vis_j: Dictionary = _read_json_file(vis_path)
							trail_ov = TypedVariant.as_dict(vis_j.get("trail_override", {}))
					if not trail_ov.is_empty():
						if sub.ends_with("equipment"):
							w.append("%s/%s: trail_override only on ships/unmanned" % [sub, dir_name])
						else:
							for note_tr: String in ModTrailResolve.lint_override(trail_ov, "%s/%s" % [sub, dir_name]):
								w.append(note_tr)
					var ix_ov: Dictionary = TypedVariant.as_dict(uj.get("interaction_fx_override", {}))
					var ix_kind: String = str(uj.get("interaction_fx", "")).strip_edges()
					if not ix_ov.is_empty() or ix_kind != "":
						var pkg_proto: int = TypedVariant.as_int(mod_json.get("fx_protocol", 1), 1)
						if pkg_proto < ModInteractionFxResolve.FX_PROTOCOL_SUPPORTED:
							w.append("interaction_fx 需 mod.json fx_protocol >= %d（当前 %d）" % [
								ModInteractionFxResolve.FX_PROTOCOL_SUPPORTED, pkg_proto
							])
						else:
							var ix_kinds: Dictionary = TypedVariant.as_dict(DataStore.interaction_fx.get("kinds", {}))
							for note_ix: String in ModInteractionFxResolve.lint_override(ix_ov, "%s/%s" % [sub, dir_name], ix_kinds):
								w.append(note_ix)
							if ix_kind != "" and not ix_kinds.is_empty() and not ix_kinds.has(ix_kind):
								w.append("%s/%s: interaction_fx unknown kind '%s'" % [sub, dir_name, ix_kind])
					var ixf: Dictionary = TypedVariant.as_dict(uj.get("interaction_fx_override", {}))
					if not ixf.is_empty() or str(uj.get("interaction_fx", "")).strip_edges() != "":
						var pkg_proto: int = TypedVariant.as_int(mod_json.get("fx_protocol", 1), 1)
						if pkg_proto >= 2 and TypedVariant.as_int(DataStore.interaction_fx.get("fx_protocol", 2), 2) < 2:
							w.append("%s/%s: interaction_fx requires shell fx_protocol 2" % [sub, dir_name])
					if not ixf.is_empty():
						var ix_kinds: Dictionary = TypedVariant.as_dict(DataStore.interaction_fx.get("kinds", {}))
						for note_ix: String in ModInteractionFxResolve.lint_override(ixf, "%s/%s" % [sub, dir_name], ix_kinds):
							w.append(note_ix)
			dir_name = da.get_next()
		da.list_dir_end()
	var menu_root: Dictionary = TypedVariant.as_dict(mod_json.get("menu", {}))
	if not menu_root.is_empty():
		var bg: String = str(menu_root.get("bg", "")).strip_edges().replace("\\", "/")
		if bg != "":
			var ext: String = bg.get_extension().to_lower()
			if ext != "jpg" and ext != "jpeg" and ext != "png" and ext != "webp":
				w.append("menu.bg 扩展名须为 jpg/png/webp")
			elif bg.contains(".."):
				w.append("menu.bg 禁止 ..")
			elif not FileAccess.file_exists(root.path_join(bg)):
				w.append("menu.bg 文件缺失: %s" % bg)
	return w


func compute_tree_hash(root: String) -> String:
	var files: PackedStringArray = PackedStringArray()
	_collect_files(root, root, files)
	files.sort()
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for rel: String in files:
		var abs_p: String = root.path_join(rel)
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(abs_p)
		ctx.update(rel.replace("\\", "/").to_utf8_buffer())
		ctx.update(PackedByteArray([0]))
		ctx.update(bytes)
	return ctx.finish().hex_encode()


func _collect_files(root: String, cur: String, out: PackedStringArray) -> void:
	var da: DirAccess = DirAccess.open(cur)
	if da == null:
		return
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if fn == "." or fn == "..":
			fn = da.get_next()
			continue
		if fn == "__MACOSX" or fn == ".DS_Store" or fn == "Thumbs.db":
			fn = da.get_next()
			continue
		var full: String = cur.path_join(fn)
		if da.current_is_dir():
			_collect_files(root, full, out)
		else:
			var rel: String = full.substr(root.length()).trim_prefix("/").trim_prefix("\\")
			out.append(rel.replace("\\", "/"))
		fn = da.get_next()
	da.list_dir_end()


func _extract_zip_safe(zip_path: String, dest: String, enforce_sync_size: bool) -> Dictionary:
	var zr: ZIPReader = ZIPReader.new()
	if zr.open(zip_path) != OK:
		return {"ok": false, "error": "zip_open"}
	var names: PackedStringArray = zr.get_files()
	if names.size() > MAX_ZIP_ENTRIES:
		zr.close()
		return {"ok": false, "error": "too_many_entries"}
	var total: int = 0
	for fn: String in names:
		var norm: String = fn.replace("\\", "/")
		if norm.contains("..") or norm.begins_with("/") or (norm.length() >= 2 and norm[1] == ":"):
			zr.close()
			return {"ok": false, "error": "zip_slip"}
		if norm.length() > MAX_REL_PATH_LEN:
			zr.close()
			return {"ok": false, "error": "path_too_long"}
		var base: String = norm.get_file().to_lower()
		if base == ".ds_store" or norm.begins_with("__macosx"):
			continue
		var ext: String = base.get_extension()
		if FORBIDDEN_EXT.has(ext):
			zr.close()
			return {"ok": false, "error": "forbidden_ext:%s" % ext}
		if norm.ends_with("/"):
			continue
		var data: PackedByteArray = zr.read_file(fn)
		total += data.size()
		if enforce_sync_size and total > SYNC_MAX_BYTES:
			zr.close()
			return {"ok": false, "error": "sync_unpack_too_large"}
		var out_path: String = dest.path_join(norm)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			zr.close()
			return {"ok": false, "error": "write_failed"}
		f.store_buffer(data)
		f.close()
	zr.close()
	return {"ok": true}


func _resolve_package_root(staging: String) -> String:
	if FileAccess.file_exists(staging.path_join("mod.json")):
		return staging
	var da: DirAccess = DirAccess.open(staging)
	if da == null:
		return ""
	var dirs: PackedStringArray = PackedStringArray()
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if da.current_is_dir() and not fn.begins_with(".") and fn != "__MACOSX":
			dirs.append(fn)
		fn = da.get_next()
	da.list_dir_end()
	if dirs.size() == 1:
		var only: String = staging.path_join(dirs[0])
		if FileAccess.file_exists(only.path_join("mod.json")):
			return only
	return ""


func _repack_zip(package_name: String) -> bool:
	var root: String = package_work_dir(package_name)
	if not DirAccess.dir_exists_absolute(root):
		return false
	var zip_path: String = package_zip_path(package_name)
	var zp: ZIPPacker = ZIPPacker.new()
	if zp.open(zip_path) != OK:
		return false
	var files: PackedStringArray = PackedStringArray()
	_collect_files(root, root, files)
	for rel: String in files:
		zp.start_file(rel.replace("\\", "/"))
		zp.write_file(FileAccess.get_file_as_bytes(root.path_join(rel)))
		zp.close_file()
	zp.close()
	return true


func _next_install_order() -> int:
	var mx: int = 0
	for pn: Variant in index.keys():
		mx = maxi(mx, TypedVariant.as_int(TypedVariant.as_dict(index[pn]).get("install_order", 0)))
	return mx + 1


func _note_warn(msg: String) -> void:
	last_merge_warnings.append(msg)
	push_warning("[ModManager] %s" % msg)


func _version_lt(a: String, b: String) -> bool:
	var pa: PackedStringArray = a.split(".")
	var pb: PackedStringArray = b.split(".")
	var n: int = maxi(pa.size(), pb.size())
	for i: int in range(n):
		var ai: int = TypedVariant.as_int(pa[i] if i < pa.size() else "0", 0)
		var bi: int = TypedVariant.as_int(pb[i] if i < pb.size() else "0", 0)
		if ai < bi:
			return true
		if ai > bi:
			return false
	return false


func _sha256_hex(bytes: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return TypedVariant.as_dict(data)


func _write_json_file(path: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


func _copy_dir_tree(src: String, dest: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(dest)
	var da: DirAccess = DirAccess.open(src)
	if da == null:
		return {"ok": false, "error": "open_src"}
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if fn == "." or fn == "..":
			fn = da.get_next()
			continue
		var s: String = src.path_join(fn)
		var d: String = dest.path_join(fn)
		if da.current_is_dir():
			var sub: Dictionary = _copy_dir_tree(s, d)
			if not TypedVariant.as_bool(sub.get("ok", false), false):
				da.list_dir_end()
				return sub
		else:
			DirAccess.make_dir_recursive_absolute(d.get_base_dir())
			var err: Error = DirAccess.copy_absolute(s, d)
			if err != OK:
				da.list_dir_end()
				return {"ok": false, "error": "copy_file"}
		fn = da.get_next()
	da.list_dir_end()
	return {"ok": true}


func _remove_dir_recursive(path: String) -> void:
	if path == "" or not DirAccess.dir_exists_absolute(path):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var da: DirAccess = DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if fn != "." and fn != "..":
			var full: String = path.path_join(fn)
			if da.current_is_dir():
				_remove_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		fn = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)
